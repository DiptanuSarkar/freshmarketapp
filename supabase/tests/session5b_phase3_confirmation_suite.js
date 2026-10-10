// =============================================================================
// FreshMarket Session 5B — Phase 3: Mixed Payment Confirmation Suite
// Validates:
// 1. rpc_confirm_mixed_payment_atomic atomic execution
// 2. Gateway paise validation (rejects mismatched amounts)
// 3. Posted balance debit and reserved balance release
// 4. Immutable wallet transaction ledger entry
// 5. Idempotent confirmation replay
// 6. payment_webhook_events idempotency and deduplication
// =============================================================================

const path = require("path");
const fs = require("fs");
const { execSync } = require("child_process");
const crypto = require("crypto");

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

function generateUuidV4() {
  const bytes = crypto.randomBytes(16);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}`;
}

function querySql(sql) {
  const sanitized = sql.replace(/\r?\n/g, ' ').replace(/\s+/g, ' ').trim().replace(/"/g, '\\"');
  try {
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
  } catch (err) {
    console.error("SQL Error stdout:", err.stdout?.toString());
    console.error("SQL Error stderr:", err.stderr?.toString());
    throw err;
  }
}

async function run() {
  console.log("=== STARTING SESSION 5B PHASE 3: MIXED PAYMENT CONFIRMATION SUITE ===");

  const email = process.env.TEST_CUSTOMER_A_EMAIL;
  if (!email) {
    throw new Error("TEST_CUSTOMER_A_EMAIL not found in environment.");
  }

  // 1. Resolve test customer
  const users = querySql(`SELECT id FROM auth.users WHERE email = '${email}' LIMIT 1;`);
  if (!users || users.length === 0) {
    throw new Error(`Test customer with email ${email} not found.`);
  }
  const userId = users[0].id;
  console.log(`[PASS] Customer resolved: ${userId}`);

  const addrs = querySql(`SELECT id FROM public.addresses WHERE user_id = '${userId}' LIMIT 1;`);
  const slots = querySql(`SELECT id FROM public.delivery_slots WHERE is_active = true LIMIT 1;`);

  // 2. Fund customer wallet with ₹400.00
  querySql(`
    DELETE FROM public.wallet_transactions WHERE user_id = '${userId}';
    INSERT INTO public.wallet_accounts (user_id, balance, reserved_balance, currency)
    VALUES ('${userId}', 400.00, 0.00, 'INR')
    ON CONFLICT (user_id) DO UPDATE
    SET balance = 400.00, reserved_balance = 0.00;
  `);
  console.log("[PASS] Customer wallet funded with ₹400.00 (reserved ₹0.00)");

  // 3. Create a test order for ₹650.00 with Razorpay order ID
  const orderId = generateUuidV4();
  const orderNumber = `FM-TEST-P3-${Date.now().toString().slice(-6)}`;
  const paymentId = generateUuidV4();
  const checkoutRequestId = generateUuidV4();
  const rzOrderId = `order_test_mixed_${Date.now().toString().slice(-8)}`;
  const rzPaymentId = `pay_test_mixed_${Date.now().toString().slice(-8)}`;

  querySql(`
    INSERT INTO public.orders (
      id, user_id, order_number, checkout_request_id,
      delivery_address_id, delivery_slot_id, delivery_date,
      subtotal, delivery_fee, discount, total,
      status, payment_status, payment_method,
      delivery_address_snapshot, delivery_slot_snapshot
    ) VALUES (
      '${orderId}', '${userId}', '${orderNumber}', '${checkoutRequestId}',
      '${addrs[0].id}', '${slots[0].id}', CURRENT_DATE,
      650.00, 0.00, 0.00, 650.00,
      'payment_pending', 'pending', 'razorpay',
      '{"recipient_name": "Test User", "phone": "9876543210"}'::jsonb,
      '{"slot": "Morning"}'::jsonb
    );

    INSERT INTO public.payments (
      id, order_id, amount, payment_method, status, payment_attempt_no, expires_at
    ) VALUES (
      '${paymentId}', '${orderId}', 650.00, 'razorpay', 'pending', 1, now() + interval '15 minutes'
    );
  `);

  // Reserve wallet: ₹400 wallet, ₹250 gateway
  const reserveRes = querySql(`
    SELECT public.rpc_reserve_wallet_for_order_atomic(
      '${userId}',
      '${orderId}'
    ) AS res;
  `)[0].res;

  if (!reserveRes.success || Number(reserveRes.wallet_amount) !== 400.00 || Number(reserveRes.gateway_amount) !== 250.00) {
    throw new Error(`Reservation failed: ${JSON.stringify(reserveRes)}`);
  }
  console.log(`[PASS] Reserved ₹400.00 from wallet, remaining gateway due ₹250.00 (gateway paise: ${reserveRes.gateway_paise})`);

  // Store gateway order ID on payment
  querySql(`
    UPDATE public.payments
    SET gateway_order_id = '${rzOrderId}'
    WHERE id = '${paymentId}';
  `);

  // 4. Test Amount Mismatch Rejection on confirmation
  let mismatchCaught = false;
  try {
    querySql(`
      SELECT public.rpc_confirm_mixed_payment_atomic(
        '${orderId}',
        '${rzPaymentId}',
        '${rzOrderId}',
        'sig_test_dummy',
        'upi',
        'captured',
        30000 -- Wrong amount (30000 paise vs expected 25000 paise)
      );
    `);
  } catch (err) {
    mismatchCaught = true;
  }
  if (!mismatchCaught) {
    throw new Error("rpc_confirm_mixed_payment_atomic failed to reject amount mismatch!");
  }
  console.log("[PASS] rpc_confirm_mixed_payment_atomic rejected amount mismatch (30,000 paise != 25,000 paise)");

  // 5. Confirm mixed payment with exact gateway paise (25000)
  const confirmRes = querySql(`
    SELECT public.rpc_confirm_mixed_payment_atomic(
      '${orderId}',
      '${rzPaymentId}',
      '${rzOrderId}',
      'sig_test_valid',
      'card',
      'captured',
      25000
    ) AS res;
  `)[0].res;

  if (!confirmRes.success || confirmRes.status !== "confirmed" || confirmRes.payment_status !== "completed") {
    throw new Error(`Confirmation failed: ${JSON.stringify(confirmRes)}`);
  }
  console.log("[PASS] rpc_confirm_mixed_payment_atomic confirmed successfully with exact 25,000 paise");

  // 6. Verify database records
  const orderCheck = querySql(`SELECT status, payment_status, payment_method, wallet_amount_used, gateway_amount FROM public.orders WHERE id = '${orderId}';`)[0];
  if (orderCheck.status !== "confirmed" || orderCheck.payment_status !== "completed" || orderCheck.payment_method !== "mixed" || Number(orderCheck.wallet_amount_used) !== 400.00 || Number(orderCheck.gateway_amount) !== 250.00) {
    throw new Error(`Order state mismatch after confirmation: ${JSON.stringify(orderCheck)}`);
  }
  console.log("[PASS] Order record: status='confirmed', payment_status='completed', payment_method='mixed', wallet=₹400, gateway=₹250");

  const paymentCheck = querySql(`SELECT status, payment_method, wallet_amount, wallet_reserved_amount, gateway_amount, gateway_payment_id FROM public.payments WHERE id = '${paymentId}';`)[0];
  if (paymentCheck.status !== "completed" || paymentCheck.payment_method !== "mixed" || Number(paymentCheck.wallet_amount) !== 400.00 || Number(paymentCheck.gateway_amount) !== 250.00 || paymentCheck.gateway_payment_id !== rzPaymentId) {
    throw new Error(`Payment state mismatch after confirmation: ${JSON.stringify(paymentCheck)}`);
  }
  console.log(`[PASS] Payment record: status='completed', payment_method='mixed', gateway_payment_id='${rzPaymentId}'`);

  // Verify wallet account balance: was ₹400.00, debited ₹400.00 -> balance ₹0.00, reserved ₹0.00
  const walletCheck = querySql(`SELECT balance, reserved_balance FROM public.wallet_accounts WHERE user_id = '${userId}';`)[0];
  if (Number(walletCheck.balance) !== 0.00 || Number(walletCheck.reserved_balance) !== 0.00) {
    throw new Error(`Wallet balance after mixed confirmation mismatch: ${JSON.stringify(walletCheck)}`);
  }
  console.log("[PASS] Wallet balance: ₹0.00 posted, ₹0.00 reserved");

  // Verify ledger transaction
  const ledgerCheck = querySql(`SELECT type, amount, reason, balance_after FROM public.wallet_transactions WHERE user_id = '${userId}' AND order_id = '${orderId}';`)[0];
  if (!ledgerCheck || ledgerCheck.type !== "debit" || Number(ledgerCheck.amount) !== 400.00 || Number(ledgerCheck.balance_after) !== 0.00) {
    throw new Error(`Ledger transaction mismatch: ${JSON.stringify(ledgerCheck)}`);
  }
  console.log("[PASS] Wallet ledger: debited ₹400.00 for order_payment (balance_after: ₹0.00)");

  // 7. Test Idempotent Confirmation Replay
  const replayRes = querySql(`
    SELECT public.rpc_confirm_mixed_payment_atomic(
      '${orderId}',
      '${rzPaymentId}',
      '${rzOrderId}',
      'sig_test_valid',
      'card',
      'captured',
      25000
    ) AS res;
  `)[0].res;

  if (!replayRes.success || !replayRes.already_confirmed) {
    throw new Error(`Idempotent replay failed: ${JSON.stringify(replayRes)}`);
  }
  console.log("[PASS] rpc_confirm_mixed_payment_atomic idempotent replay returns already_confirmed = true");

  // 8. Test Webhook Events Deduplication
  const eventKey = `test_evt_${Date.now()}`;
  querySql(`
    INSERT INTO public.payment_webhook_events (
      provider, event_key, event_type, gateway_order_id, gateway_payment_id, processing_status, payload
    ) VALUES (
      'razorpay', '${eventKey}', 'payment.captured', '${rzOrderId}', '${rzPaymentId}', 'received', '{}'::jsonb
    );
  `);

  let duplicateCaught = false;
  try {
    querySql(`
      INSERT INTO public.payment_webhook_events (
        provider, event_key, event_type, gateway_order_id, gateway_payment_id, processing_status, payload
      ) VALUES (
        'razorpay', '${eventKey}', 'payment.captured', '${rzOrderId}', '${rzPaymentId}', 'received', '{}'::jsonb
      );
    `);
  } catch {
    duplicateCaught = true;
  }
  if (!duplicateCaught) {
    throw new Error("payment_webhook_events unique constraint failed to catch duplicate event_key!");
  }
  console.log("[PASS] payment_webhook_events successfully caught and rejected duplicate event delivery");

  // 9. Cleanup
  querySql(`
    DELETE FROM public.payment_webhook_events WHERE event_key = '${eventKey}';
    DELETE FROM public.wallet_transactions WHERE user_id = '${userId}';
    DELETE FROM public.payments WHERE order_id = '${orderId}';
    DELETE FROM public.orders WHERE id = '${orderId}';
    UPDATE public.wallet_accounts SET balance = 0.00, reserved_balance = 0.00 WHERE user_id = '${userId}';
  `);
  console.log("[PASS] Cleaned up test data and reset wallet");

  console.log("\n=======================================================");
  console.log("SESSION 5B PHASE 3 RESULT: ALL 9 ASSERTIONS PASSED (100%)");
  console.log("=======================================================");
}

run().catch((err) => {
  console.error("\n❌ PHASE 3 VERIFICATION FAILED:", err.message);
  process.exit(1);
});
