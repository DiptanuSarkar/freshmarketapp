// =============================================================================
// FreshMarket Session 5A — Online Payment Engine Verification Suite
// Executes live tests against linked Supabase remote project & Edge Functions
// Tests RPC Privilege Lockdown, Webhook Security, Signature Verification,
// Deduplication, and Edge Function Authentication Boundaries.
// =============================================================================

const https = require("https");
const dns = require("dns");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

// Load .env if present
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
const ANON_KEY =
  process.env.SUPABASE_ANON_KEY ||
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpaHBtcnF0anRseWtmeGt5aW1wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTExMjg4MjgsImV4cCI6MjEwNjcwNDgyOH0.J_9CEjB8vSoE83CiTNgu82OAKxs7Bp16sNdmxzaFAks";

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

function customFetch(urlStr, options = {}) {
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
    if (options.body) {
      req.write(options.body);
    }
    req.end();
  });
}

const fetch = customFetch;

function generateUuidV4() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}`;
}

async function loginUser(email, password) {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: ANON_KEY,
    },
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Failed to login ${email}: ${res.status} ${text}`);
  }
  const data = await res.json();
  return {
    token: data.access_token,
    user: data.user,
  };
}

async function restRpc(rpcName, body, token) {
  const headers = {
    "Content-Type": "application/json",
    apikey: ANON_KEY,
  };
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${rpcName}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body || {}),
  });
  let data = null;
  try {
    data = await res.json();
  } catch {}
  return { status: res.status, data };
}

async function callEdgeFunction(name, body, token, headers = {}) {
  const reqHeaders = {
    "Content-Type": "application/json",
    apikey: ANON_KEY,
    ...headers,
  };
  if (token) {
    reqHeaders["Authorization"] = `Bearer ${token}`;
  }
  const res = await fetch(`${SUPABASE_URL}/functions/v1/${name}`, {
    method: "POST",
    headers: reqHeaders,
    body: typeof body === "string" ? body : JSON.stringify(body || {}),
  });
  let data = null;
  try {
    data = await res.json();
  } catch {}
  return { status: res.status, data };
}

async function run() {
  const results = [];
  function assert(condition, name, details = "") {
    if (condition) {
      console.log(`[PASS] ${name}`);
      results.push({ name, pass: true, details });
    } else {
      console.error(`[FAIL] ${name}: ${details}`);
      results.push({ name, pass: false, details });
    }
  }

  console.log("=== STARTING SESSION 5A VERIFICATION SUITE ===");

  // 1. Authenticate Customer
  console.log("\n--- Authenticating Test Customer ---");
  const email = process.env.TEST_CUSTOMER_A_EMAIL;
  const pass = process.env.TEST_CUSTOMER_A_PASSWORD;
  if (!email || !pass) {
    throw new Error("TEST_CUSTOMER_A_EMAIL and TEST_CUSTOMER_A_PASSWORD must be configured in environment or .env");
  }
  const cust = await loginUser(email, pass);
  assert(cust.token && cust.user.id, "Test customer authenticated via Supabase Auth");

  // 2. RPC Privilege Lockdown Checks (Phase 28)
  console.log("\n--- Phase 28: Privileged Payment RPC Permission Lockdown ---");
  const privilegedRpcs = [
    "rpc_prepare_razorpay_order_atomic",
    "rpc_set_payment_gateway_order",
    "rpc_fail_razorpay_initialization_atomic",
    "rpc_confirm_razorpay_payment_atomic",
    "rpc_record_razorpay_payment_failure_atomic",
    "rpc_prepare_razorpay_retry_atomic",
    "rpc_expire_pending_razorpay_orders",
  ];

  for (const rpc of privilegedRpcs) {
    // Attempt call with authenticated customer token
    const custRes = await restRpc(rpc, {}, cust.token);
    assert(
      custRes.status === 401 || custRes.status === 403 || custRes.status === 404,
      `Authenticated customer CANNOT execute ${rpc} directly (status ${custRes.status})`
    );

    // Attempt call as anonymous
    const anonRes = await restRpc(rpc, {}, null);
    assert(
      anonRes.status === 401 || anonRes.status === 403 || anonRes.status === 404,
      `Anonymous client CANNOT execute ${rpc} directly (status ${anonRes.status})`
    );
  }

  // 3. Edge Function Authentication Boundaries
  console.log("\n--- Edge Function Authentication & Boundary Checks ---");
  
  // create-razorpay-order requires JWT
  const unauthCreate = await callEdgeFunction("create-razorpay-order", {}, null);
  assert(
    unauthCreate.status === 401,
    "create-razorpay-order rejects unauthenticated call with 401"
  );

  // verify-razorpay-payment requires JWT
  const unauthVerify = await callEdgeFunction("verify-razorpay-payment", {}, null);
  assert(
    unauthVerify.status === 401,
    "verify-razorpay-payment rejects unauthenticated call with 401"
  );

  // check-payment-status requires JWT
  const unauthCheck = await callEdgeFunction("check-payment-status", {}, null);
  assert(
    unauthCheck.status === 401,
    "check-payment-status rejects unauthenticated call with 401"
  );

  // 4. Webhook Security & Signature Tests (Phase 29)
  console.log("\n--- Phase 29: Webhook Security & Signature Verification ---");
  
  // Empty signature header
  const noSigRes = await callEdgeFunction("razorpay-webhook", { event: "payment.captured" }, null);
  assert(
    noSigRes.status === 400,
    "razorpay-webhook rejects request missing x-razorpay-signature with 400"
  );

  // Invalid signature header
  const invalidSigRes = await callEdgeFunction(
    "razorpay-webhook",
    { event: "payment.captured" },
    null,
    { "x-razorpay-signature": "bogus_signature_hex_12345" }
  );
  assert(
    invalidSigRes.status === 400,
    "razorpay-webhook rejects invalid signature with 400"
  );

  // Webhook for unsupported event
  const testSecret = process.env.RAZORPAY_WEBHOOK_SECRET;
  if (testSecret) {
    console.log("\n--- Testing Webhook with configured RAZORPAY_WEBHOOK_SECRET ---");
    const rawPayload = JSON.stringify({
      event: "payment.dispute.created",
      contains: ["payment"],
      payload: {},
      created_at: Math.floor(Date.now() / 1000),
    });
    const validHmac = crypto.createHmac("sha256", testSecret).update(rawPayload).digest("hex");
    const unsupportedEventRes = await callEdgeFunction(
      "razorpay-webhook",
      rawPayload,
      null,
      { "x-razorpay-signature": validHmac }
    );
    assert(
      unsupportedEventRes.status === 200 && unsupportedEventRes.data?.ignored === true,
      "razorpay-webhook safely ignores unhandled event with 200"
    );

    // Duplicate event deduplication test
    const dummyEventId = `test_evt_${Date.now()}`;
    const capturePayload = JSON.stringify({
      id: dummyEventId,
      event: "payment.captured",
      contains: ["payment"],
      payload: {
        payment: {
          entity: {
            id: `pay_${Date.now()}`,
            order_id: "order_nonexistent_999",
            amount: 54000,
            currency: "INR",
            status: "captured",
          },
        },
      },
      created_at: Math.floor(Date.now() / 1000),
    });
    const captureHmac = crypto.createHmac("sha256", testSecret).update(capturePayload).digest("hex");

    // First arrival
    const arrival1 = await callEdgeFunction(
      "razorpay-webhook",
      capturePayload,
      null,
      { "x-razorpay-signature": captureHmac }
    );
    assert(
      arrival1.status === 200,
      "Valid signed webhook for payment.captured processed with status 200"
    );

    // Second arrival (duplicate)
    const arrival2 = await callEdgeFunction(
      "razorpay-webhook",
      capturePayload,
      null,
      { "x-razorpay-signature": captureHmac }
    );
    assert(
      arrival2.status === 200 && arrival2.data?.duplicate === true,
      "Duplicate webhook delivery detected and deduplicated via payment_webhook_events"
    );
  } else {
    console.log(
      "\n[NOTE] RAZORPAY_WEBHOOK_SECRET environment variable not set locally. Skipping live HMAC delivery."
    );
  }

  // 5. Live Razorpay Order Creation & Idempotency (Phase 5, Phase 9, Phase 26)
  console.log("\n--- Section 5: Live Razorpay Order Creation & Edge Function Tests ---");
  
  // Ensure Alice has active cart with items
  const cartRes = await fetch(`${SUPABASE_URL}/rest/v1/carts`, {
    headers: {
      apikey: ANON_KEY,
      Authorization: `Bearer ${cust.token}`,
    },
  });
  const carts = await cartRes.json();
  let cartA = carts[0];
  if (!cartA) {
    const newCartRes = await fetch(`${SUPABASE_URL}/rest/v1/carts`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: ANON_KEY,
        Authorization: `Bearer ${cust.token}`,
        Prefer: "return=representation",
      },
      body: JSON.stringify({ user_id: cust.user.id }),
    });
    const newCarts = await newCartRes.json();
    cartA = newCarts[0];
  }

  // Clear existing cart items and add 1 pack of Chicken 500g
  await fetch(`${SUPABASE_URL}/rest/v1/cart_items?cart_id=eq.${cartA.id}`, {
    method: "DELETE",
    headers: {
      apikey: ANON_KEY,
      Authorization: `Bearer ${cust.token}`,
    },
  });

  await fetch(`${SUPABASE_URL}/rest/v1/cart_items`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: ANON_KEY,
      Authorization: `Bearer ${cust.token}`,
    },
    body: JSON.stringify({
      cart_id: cartA.id,
      variant_id: "b1000000-0000-0000-0000-000000000001",
      quantity: 1,
    }),
  });

  // Get address
  const addrRes = await fetch(
    `${SUPABASE_URL}/rest/v1/addresses?user_id=eq.${cust.user.id}&limit=1`,
    {
      headers: {
        apikey: ANON_KEY,
        Authorization: `Bearer ${cust.token}`,
      },
    }
  );
  const addrs = await addrRes.json();

  // Get delivery slot
  const slotRes = await fetch(
    `${SUPABASE_URL}/rest/v1/delivery_slots?is_active=eq.true&limit=1`,
    {
      headers: {
        apikey: ANON_KEY,
        Authorization: `Bearer ${cust.token}`,
      },
    }
  );
  const slots = await slotRes.json();

  if (addrs[0] && slots[0]) {
    const reqId = generateUuidV4();
    const createOrderRes = await callEdgeFunction(
      "create-razorpay-order",
      {
        checkout_request_id: reqId,
        address_id: addrs[0].id,
        delivery_slot_id: slots[0].id,
      },
      cust.token
    );

    assert(
      createOrderRes.status === 200 && createOrderRes.data?.success === true,
      `create-razorpay-order successfully created order with status ${createOrderRes.status}`,
      JSON.stringify(createOrderRes.data)
    );
    assert(
      typeof createOrderRes.data?.razorpay_order_id === "string" &&
        createOrderRes.data.razorpay_order_id.startsWith("order_"),
      `Gateway returned authentic Razorpay Order ID: ${createOrderRes.data?.razorpay_order_id}`
    );
    assert(
      typeof createOrderRes.data?.razorpay_key_id === "string" &&
        createOrderRes.data.razorpay_key_id.startsWith("rzp_test_"),
      `Public Razorpay Key ID returned safely: ${createOrderRes.data?.razorpay_key_id}`
    );
    assert(
      createOrderRes.data?.currency === "INR" &&
        typeof createOrderRes.data?.amount_paise === "number" &&
        createOrderRes.data.amount_paise > 0,
      `Authoritative INR paise calculated by backend: ₹${(createOrderRes.data?.amount_paise || 0) / 100} (${createOrderRes.data?.amount_paise} paise)`
    );

    // Test Idempotent replay of same request ID
    const replayRes = await callEdgeFunction(
      "create-razorpay-order",
      {
        checkout_request_id: reqId,
        address_id: addrs[0].id,
        delivery_slot_id: slots[0].id,
      },
      cust.token
    );
    assert(
      replayRes.status === 200 &&
        replayRes.data?.razorpay_order_id === createOrderRes.data?.razorpay_order_id,
      "Replaying same checkout_request_id returns existing payment-pending order (idempotent)",
      JSON.stringify(replayRes.data)
    );

    // Test check-payment-status endpoint
    const statusRes = await callEdgeFunction(
      "check-payment-status",
      { order_id: createOrderRes.data?.internal_order_id },
      cust.token
    );
    assert(
      statusRes.status === 200 &&
        statusRes.data?.status === "payment_pending" &&
        statusRes.data?.payment_status === "pending",
      "check-payment-status accurately reports payment_pending state"
    );
  } else {
    console.warn("Could not find test address or slot for live order creation test");
  }

  console.log("\n=== SESSION 5A VERIFICATION SUITE SUMMARY ===");
  const passed = results.filter((r) => r.pass).length;
  console.log(`Passed: ${passed} / ${results.length}`);
}

run().catch((err) => {
  console.error("FATAL ERROR IN SUITE:", err);
  process.exit(1);
});
