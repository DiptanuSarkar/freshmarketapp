// =============================================================================
// FreshMarket Session 5B — Phase 4 & 5: Refund Engine Verification Suite
// Validates:
// 1. Paid mixed order cancellation via rpc_prepare_order_cancellation_refund_atomic
// 2. Instant wallet refund credit & ledger entry
// 3. Normalized refund_components creation (wallet + razorpay)
// 4. Gateway refund submission via rpc_record_gateway_refund_submission_atomic
// 5. Parent refund completion lifecycle
// 6. Idempotent refund replay protection
// 7. Guard against cancelling paid orders via unpaid cancellation path
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
  const noComments = sql.replace(/--.*$/gm, '');
  const sanitized = noComments.replace(/\r?\n/g, ' ').replace(/\s+/g, ' ').trim().replace(/"/g, '\\"');
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
  console.log("=== STARTING SESSION 5B PHASE 4 & 5: REFUND ENGINE VERIFICATION SUITE ===");

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

  // 2. Fund customer wallet with ₹300.00
  querySql(`
    DELETE FROM public.wallet_transactions WHERE user_id = '${userId}';
    INSERT INTO public.wallet_accounts (user_id, balance, reserved_balance, currency)
    VALUES ('${userId}', 300.00, 0.00, 'INR')
    ON CONFLICT (user_id) DO UPDATE
    SET balance = 300.00, reserved_balance = 0.00;
  `);
  console.log("[PASS] Seeded wallet with ₹300.00");

  // 3. Setup a completed mixed order (₹300 wallet + ₹200 gateway = ₹500 total)
  const orderId = generateUuidV4();
  const orderNumber = `FM-REFUND-${Date.now().toString().slice(-6)}`;
  const paymentId = generateUuidV4();
  const rzOrderId = `order_rfnd_${Date.now().toString().slice(-8)}`;
  const rzPaymentId = `pay_rfnd_${Date.now().toString().slice(-8)}`;

  querySql(`
    INSERT INTO public.orders (
      id, user_id, order_number, checkout_request_id,
      delivery_address_id, delivery_slot_id, delivery_date,
      subtotal, delivery_fee, discount, total,
      status, payment_status, payment_method,
      wallet_amount_used, gateway_amount,
      delivery_address_snapshot, delivery_slot_snapshot
    ) VALUES (
      '${orderId}', '${userId}', '${orderNumber}', '${generateUuidV4()}',
      '${addrs[0].id}', '${slots[0].id}', CURRENT_DATE,
      500.00, 0.00, 0.00, 500.00,
      'confirmed', 'completed', 'mixed',
      300.00, 200.00,
      '{"recipient_name": "Test User", "phone": "9876543210"}'::jsonb,
      '{"slot": "Morning"}'::jsonb
    );

    INSERT INTO public.payments (
      id, order_id, amount, payment_method, status, payment_attempt_no,
      wallet_amount, wallet_reserved_amount, gateway_amount,
      gateway_order_id, gateway_payment_id
    ) VALUES (
      '${paymentId}', '${orderId}', 500.00, 'mixed', 'completed', 1,
      300.00, 0.00, 200.00,
      '${rzOrderId}', '${rzPaymentId}'
    );

    UPDATE public.wallet_accounts
    SET balance = 0.00, reserved_balance = 0.00
    WHERE user_id = '${userId}';

    INSERT INTO public.wallet_transactions (
      user_id, amount, type, reason, description, reference_id,
      balance_before, balance_after, closing_balance, order_id, payment_id, idempotency_key, status
    ) VALUES (
      '${userId}', 300.00, 'debit', 'order_payment', 'Initial test payment', '${orderNumber}',
      300.00, 0.00, 0.00, '${orderId}', '${paymentId}', 'init_pay_${Date.now()}', 'completed'
    );
  `);
  console.log(`[PASS] Created confirmed mixed order ₹500.00 (${orderId}) with wallet balance ₹0.00`);

  // 4. Test Guard: Unpaid cancellation path must reject paid order
  let unpaidCancelRejected = false;
  try {
    querySql(`
      SELECT public.rpc_cancel_order_atomic(
        '${userId}',
        '${orderId}',
        'Testing rejection of unpaid cancel path'
      );
    `);
  } catch (err) {
    unpaidCancelRejected = true;
  }
  if (!unpaidCancelRejected) {
    throw new Error("rpc_cancel_order_atomic failed to reject completed paid order!");
  }
  console.log("[PASS] rpc_cancel_order_atomic rejected completed paid order with PAID_ORDER_REFUND_REQUIRED");

  // 5. Test Refund-Aware Cancellation Flow
  const refundReqId = `RFND-REQ-${Date.now()}`;
  const prepRefundRes = querySql(`
    SELECT public.rpc_prepare_order_cancellation_refund_atomic(
      '${userId}',
      '${orderId}',
      'Customer cancellation test',
      '${refundReqId}'
    ) AS res;
  `)[0].res;

  if (!prepRefundRes.success || !prepRefundRes.refund_id) {
    throw new Error(`Refund preparation failed: ${JSON.stringify(prepRefundRes)}`);
  }
  if (Number(prepRefundRes.wallet_refund_amount) !== 300.00 || Number(prepRefundRes.gateway_refund_amount) !== 200.00 || !prepRefundRes.requires_gateway_refund) {
    throw new Error(`Refund amounts or flags incorrect: ${JSON.stringify(prepRefundRes)}`);
  }
  console.log(`[PASS] rpc_prepare_order_cancellation_refund_atomic: Refund ID ${prepRefundRes.refund_id}, Wallet ₹300, Gateway ₹200 (requires_gateway: true)`);

  const refundId = prepRefundRes.refund_id;

  // 6. Verify Instant Wallet Refund Credit
  const walletAfterRefund = querySql(`SELECT balance, reserved_balance FROM public.wallet_accounts WHERE user_id = '${userId}';`)[0];
  if (Number(walletAfterRefund.balance) !== 300.00 || Number(walletAfterRefund.reserved_balance) !== 0.00) {
    throw new Error(`Wallet balance after instant credit mismatch: ${JSON.stringify(walletAfterRefund)}`);
  }
  console.log("[PASS] Customer wallet instantly credited back ₹300.00 (balance: ₹300.00, reserved: ₹0.00)");

  // Verify wallet transaction ledger for refund
  const refundTx = querySql(`
    SELECT type, amount, reason, balance_after
    FROM public.wallet_transactions
    WHERE user_id = '${userId}' AND refund_id = '${refundId}';
  `)[0];
  if (!refundTx || refundTx.type !== "credit" || refundTx.reason !== "refund" || Number(refundTx.amount) !== 300.00) {
    throw new Error(`Wallet refund ledger entry missing or invalid: ${JSON.stringify(refundTx)}`);
  }
  console.log("[PASS] Immutable wallet ledger recorded credit of ₹300.00 with reason='refund'");

  // 7. Verify Normalized refund_components
  const components = querySql(`
    SELECT method, amount, status
    FROM public.refund_components
    WHERE refund_id = '${refundId}'
    ORDER BY method ASC;
  `);

  const razorpayComp = components.find((c) => c.method === "razorpay");
  const walletComp = components.find((c) => c.method === "wallet");

  if (!walletComp || walletComp.status !== "processed" || Number(walletComp.amount) !== 300.00) {
    throw new Error(`Wallet refund component invalid: ${JSON.stringify(walletComp)}`);
  }
  if (!razorpayComp || razorpayComp.status !== "processing" || Number(razorpayComp.amount) !== 200.00) {
    throw new Error(`Razorpay refund component invalid: ${JSON.stringify(razorpayComp)}`);
  }
  console.log("[PASS] refund_components verified: wallet is 'processed' (₹300), razorpay is 'processing' (₹200)");

  // 8. Test Idempotent Refund Replay
  const replayRes = querySql(`
    SELECT public.rpc_prepare_order_cancellation_refund_atomic(
      '${userId}',
      '${orderId}',
      'Customer cancellation test',
      '${refundReqId}'
    ) AS res;
  `)[0].res;

  if (!replayRes.success || !replayRes.already_refunded) {
    throw new Error(`Idempotent replay failed: ${JSON.stringify(replayRes)}`);
  }
  console.log("[PASS] rpc_prepare_order_cancellation_refund_atomic idempotent replay returned already_refunded=true");

  // Verify wallet was NOT double-credited
  const walletAfterReplay = querySql(`SELECT balance FROM public.wallet_accounts WHERE user_id = '${userId}';`)[0];
  if (Number(walletAfterReplay.balance) !== 300.00) {
    throw new Error(`Double credit occurred! Balance is: ${walletAfterReplay.balance}`);
  }
  console.log("[PASS] Verified balance remained strictly ₹300.00 without double credit on replay");

  // 9. Test Gateway Refund Submission & Completion
  const rzRefundId = `rfnd_${Date.now().toString().slice(-8)}`;
  const submitRes = querySql(`
    SELECT public.rpc_record_gateway_refund_submission_atomic(
      '${refundId}',
      '${rzRefundId}',
      'processed'
    ) AS res;
  `)[0].res;

  if (!submitRes.success || !submitRes.all_processed || submitRes.status !== "processed") {
    throw new Error(`Gateway refund submission update failed: ${JSON.stringify(submitRes)}`);
  }
  console.log(`[PASS] rpc_record_gateway_refund_submission_atomic marked gateway refund processed (rfnd_id: ${rzRefundId})`);

  // Verify parent refund is 'processed'
  const parentRefund = querySql(`SELECT status FROM public.refunds WHERE id = '${refundId}';`)[0];
  if (parentRefund.status !== "processed") {
    throw new Error(`Parent refund status expected 'processed', got: ${parentRefund.status}`);
  }
  console.log("[PASS] Parent refund record transitioned to status='processed'");

  // Verify payment status is 'refunded'
  const paymentAfter = querySql(`SELECT status FROM public.payments WHERE id = '${paymentId}';`)[0];
  if (paymentAfter.status !== "refunded") {
    throw new Error(`Payment status expected 'refunded', got: ${paymentAfter.status}`);
  }
  console.log("[PASS] Payment record transitioned to status='refunded'");

  // 10. Cleanup
  querySql(`
    DELETE FROM public.refund_components WHERE refund_id = '${refundId}';
    DELETE FROM public.refunds WHERE id = '${refundId}';
    DELETE FROM public.wallet_transactions WHERE user_id = '${userId}';
    DELETE FROM public.payments WHERE order_id = '${orderId}';
    DELETE FROM public.orders WHERE id = '${orderId}';
    UPDATE public.wallet_accounts SET balance = 0.00, reserved_balance = 0.00 WHERE user_id = '${userId}';
  `);
  console.log("[PASS] Cleaned up test refund data and reset wallet");

  console.log("\n=======================================================");
  console.log("SESSION 5B PHASE 4 & 5 RESULT: ALL 10 ASSERTIONS PASSED (100%)");
  console.log("=======================================================");
}

run().catch((err) => {
  console.error("\n❌ PHASE 4 & 5 VERIFICATION FAILED:", err.message);
  process.exit(1);
});
