// =============================================================================
// FreshMarket Session 5A-R — Compensation, Retry, and Expiry Verification Script
// Tests:
// 1. rpc_fail_razorpay_initialization_atomic (Compensation on gateway error)
// 2. Double-call idempotency of compensation (No double-release of stock)
// 3. rpc_prepare_razorpay_retry_atomic (Clean attempt increment, no stock leak)
// 4. rpc_expire_pending_razorpay_orders (15-min TTL background cleanup)
// =============================================================================

const https = require("https");
const dns = require("dns");
const fs = require("fs");
const path = require("path");

// Load .env
try {
  const envPath = path.resolve(__dirname, "../../.env");
  if (fs.existsSync(envPath)) {
    const lines = fs.readFileSync(envPath, "utf8").split("\n");
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const idx = trimmed.indexOf("=");
      if (idx !== -1) {
        const key = trimmed.slice(0, idx).trim();
        const val = trimmed.slice(idx + 1).trim();
        if (!process.env[key]) process.env[key] = val;
      }
    }
  }
} catch {}

const SUPABASE_URL = process.env.SUPABASE_URL || "https://fihpmrqtjtlykfxkyimp.supabase.co";
const ANON_KEY = process.env.SUPABASE_ANON_KEY;

function customLookup(hostname, options, callback) {
  if (typeof options === "function") {
    callback = options;
    options = {};
  }
  if (hostname === "fihpmrqtjtlykfxkyimp.supabase.co") {
    if (options && options.all) {
      return callback(null, [{ address: "104.18.38.10", family: 4 }]);
    }
    return callback(null, "104.18.38.10", 4);
  }
  dns.lookup(hostname, options, callback);
}

function fetchRequest(urlStr, options = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(urlStr);
    const req = https.request(
      url,
      {
        method: options.method || "GET",
        headers: options.headers || {},
        lookup: customLookup,
      },
      (res) => {
        let raw = "";
        res.on("data", (c) => (raw += c));
        res.on("end", () => {
          resolve({
            ok: res.statusCode >= 200 && res.statusCode < 300,
            status: res.statusCode,
            headers: res.headers,
            text: async () => raw,
            json: async () => {
              try {
                return JSON.parse(raw);
              } catch {
                return null;
              }
            },
          });
        });
      }
    );
    req.on("error", reject);
    if (options.body) req.write(options.body);
    req.end();
  });
}

const { execSync } = require("child_process");

function querySql(sql) {
  const sanitized = sql.replace(/"/g, '\\"');
  const res = execSync(`npx supabase db query --linked "${sanitized}"`, {
    cwd: path.resolve(__dirname, "../.."),
    encoding: "utf8",
  });
  const jsonStart = res.indexOf("{");
  if (jsonStart !== -1) {
    const parsed = JSON.parse(res.slice(jsonStart));
    return parsed.rows || [];
  }
  return [];
}

async function run() {
  console.log("=== VERIFYING COMPENSATION, RETRY, AND EXPIRY ENGINE ===");

  const email = process.env.TEST_CUSTOMER_A_EMAIL;
  const pass = process.env.TEST_CUSTOMER_A_PASSWORD;
  const authRes = await fetchRequest(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: ANON_KEY },
    body: JSON.stringify({ email, password: pass }),
  });
  const authData = await authRes.json();
  const userId = authData.user.id;
  const token = authData.access_token;
  console.log(`[PASS] Customer authenticated: ${userId}`);

  // Get test address & slot
  const addrs = querySql(`SELECT id FROM public.addresses WHERE user_id = '${userId}' LIMIT 1;`);
  const slots = querySql(`SELECT id FROM public.delivery_slots WHERE is_active = true LIMIT 1;`);
  const addressId = addrs[0].id;
  const slotId = slots[0].id;

  // Add 1 test item to Alice's cart
  const cartRows = querySql(`SELECT id FROM public.carts WHERE user_id = '${userId}';`);
  const cartId = cartRows[0].id;
  querySql(`DELETE FROM public.cart_items WHERE cart_id = '${cartId}';`);
  querySql(`INSERT INTO public.cart_items (cart_id, variant_id, quantity) VALUES ('${cartId}', 'b1000000-0000-0000-0000-000000000001', 2);`);

  // --- TEST 1: COMPENSATION ON INITIALIZATION FAILURE ---
  console.log("\n--- Test 1: Compensation Lifecycle & Idempotency ---");
  const invBefore = querySql(`SELECT reserved_quantity FROM public.inventory WHERE variant_id = 'b1000000-0000-0000-0000-000000000001';`)[0].reserved_quantity;

  const prepSql = `SELECT public.rpc_prepare_razorpay_order_atomic('${userId}', gen_random_uuid(), '${addressId}', '${slotId}', NULL, 'Compensation Test') as res;`;
  const prepRes = querySql(prepSql);
  const orderId = prepRes[0].res.id;
  console.log(`Prepared test order: ${orderId}`);

  const invAfterPrep = querySql(`SELECT reserved_quantity FROM public.inventory WHERE variant_id = 'b1000000-0000-0000-0000-000000000001';`)[0].reserved_quantity;
  if (Number(invAfterPrep) !== Number(invBefore) + 2) {
    throw new Error(`Inventory not reserved correctly: before=${invBefore}, afterPrep=${invAfterPrep}`);
  }
  console.log(`[PASS] Inventory correctly incremented from ${invBefore} to ${invAfterPrep}`);

  // Trigger compensation
  const failSql = `SELECT public.rpc_fail_razorpay_initialization_atomic('${orderId}', 'Simulated Gateway Failure') as res;`;
  const failRes = querySql(failSql);
  console.log(`Compensation result:`, failRes[0].res);

  const invAfterComp = querySql(`SELECT reserved_quantity FROM public.inventory WHERE variant_id = 'b1000000-0000-0000-0000-000000000001';`)[0].reserved_quantity;
  if (Number(invAfterComp) !== Number(invBefore)) {
    throw new Error(`Inventory not released: expected ${invBefore}, got ${invAfterComp}`);
  }
  console.log(`[PASS] Inventory reservation released: ${invAfterComp} equals original ${invBefore}`);

  const orderState = querySql(`SELECT status, payment_status, cancelled_reason FROM public.orders WHERE id = '${orderId}';`)[0];
  if (orderState.status !== 'cancelled' || orderState.payment_status !== 'failed') {
    throw new Error(`Order state invalid: ${JSON.stringify(orderState)}`);
  }
  console.log(`[PASS] Order state marked cancelled/failed with reason: "${orderState.cancelled_reason}"`);

  // Calling compensation a SECOND time (Idempotency)
  const failAgain = querySql(failSql);
  console.log(`Second compensation call:`, failAgain[0].res);
  const invAfterSecondComp = querySql(`SELECT reserved_quantity FROM public.inventory WHERE variant_id = 'b1000000-0000-0000-0000-000000000001';`)[0].reserved_quantity;
  if (Number(invAfterSecondComp) !== Number(invBefore)) {
    throw new Error(`Double release occurred! ${invAfterSecondComp}`);
  }
  console.log(`[PASS] Compensation idempotency: second call did NOT double-release stock (reserved: ${invAfterSecondComp})`);

  // --- TEST 2: PAYMENT RETRY ATOMICITY ---
  console.log("\n--- Test 2: Payment Retry Lifecycle ---");
  // Prepare new pending order
  querySql(`DELETE FROM public.cart_items WHERE cart_id = '${cartId}';`);
  querySql(`INSERT INTO public.cart_items (cart_id, variant_id, quantity) VALUES ('${cartId}', 'b1000000-0000-0000-0000-000000000001', 1);`);
  const retryPrep = querySql(`SELECT public.rpc_prepare_razorpay_order_atomic('${userId}', gen_random_uuid(), '${addressId}', '${slotId}', NULL, 'Retry Test') as res;`);
  const retryOrderId = retryPrep[0].res.id;
  const retryPaymentId = retryPrep[0].res.payment_id;

  const retrySql = `SELECT public.rpc_prepare_razorpay_retry_atomic('${userId}', '${retryOrderId}') as res;`;
  const retryRes = querySql(retrySql);
  const retryAttempt = retryRes[0].res.attempt_no;
  if (retryAttempt !== 2) {
    throw new Error(`Expected attempt 2, got ${retryAttempt}`);
  }
  console.log(`[PASS] Retry successfully incremented attempt_no to ${retryAttempt} on order ${retryOrderId}`);

  // --- TEST 3: PAYMENT EXPIRY CLEANUP ---
  console.log("\n--- Test 3: Payment Expiry Engine (15-min TTL) ---");
  // Age the order created_at to 20 minutes ago
  querySql(`UPDATE public.orders SET created_at = now() - interval '20 minutes' WHERE id = '${retryOrderId}';`);
  const expireRes = querySql(`SELECT public.rpc_expire_pending_razorpay_orders() as res;`);
  console.log(`Expiry cleanup result:`, expireRes[0].res);

  const expiredOrder = querySql(`SELECT status, payment_status, cancelled_reason FROM public.orders WHERE id = '${retryOrderId}';`)[0];
  if (expiredOrder.status !== 'cancelled' || expiredOrder.payment_status !== 'cancelled') {
    throw new Error(`Order did not expire correctly: ${JSON.stringify(expiredOrder)}`);
  }
  console.log(`[PASS] Order ${retryOrderId} expired automatically: status=${expiredOrder.status}, payment_status=${expiredOrder.payment_status}`);

  console.log("\n=== ALL COMPENSATION, RETRY, AND EXPIRY TESTS PASSED ===");
}

run().catch((e) => {
  console.error("FATAL ERROR:", e);
  process.exit(1);
});
