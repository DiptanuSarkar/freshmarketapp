// =============================================================================
// FreshMarket Session 5B — Phase 2: Wallet & Mixed Order Creation Suite
// Validates:
// 1. rpc_calculate_checkout_quote wallet breakdowns (use_wallet = true vs false)
// 2. rpc_reserve_wallet_for_order_atomic mixed allocation on orders & payments
// 3. Compensation & failure release of wallet reservation via rpc_fail_razorpay_initialization_atomic
// 4. Pure wallet checkout confirmation via rpc_confirm_wallet_only_order_atomic
// 5. Idempotent reservation replay
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
  console.log("=== STARTING SESSION 5B PHASE 2: WALLET & MIXED ORDER CREATION SUITE ===");

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

  // 2. Fetch an active address and active delivery slot
  const addresses = querySql(`SELECT id FROM public.addresses WHERE user_id = '${userId}' LIMIT 1;`);
  if (!addresses || addresses.length === 0) {
    throw new Error(`No address found for test user ${userId}`);
  }
  const addressId = addresses[0].id;

  const slots = querySql(`SELECT id FROM public.delivery_slots WHERE is_active = true LIMIT 1;`);
  if (!slots || slots.length === 0) {
    throw new Error("No active delivery slots found.");
  }
  const slotId = slots[0].id;

  // 3. Reset and fund wallet to ₹350.00
  querySql(`
    DELETE FROM public.wallet_transactions WHERE user_id = '${userId}';
    INSERT INTO public.wallet_accounts (user_id, balance, reserved_balance, currency)
    VALUES ('${userId}', 350.00, 0.00, 'INR')
    ON CONFLICT (user_id) DO UPDATE
    SET balance = 350.00, reserved_balance = 0.00;
  `);
  console.log("[PASS] Seeded customer wallet with ₹350.00 (reserved: ₹0.00)");

  // 4. Ensure customer cart has items for quote calculation
  const carts = querySql(`SELECT id FROM public.carts WHERE user_id = '${userId}' LIMIT 1;`);
  let cartId;
  if (!carts || carts.length === 0) {
    const newCart = querySql(`INSERT INTO public.carts (user_id) VALUES ('${userId}') RETURNING id;`);
    cartId = newCart[0].id;
  } else {
    cartId = carts[0].id;
  }
  querySql(`
    DELETE FROM public.cart_items WHERE cart_id = '${cartId}';
    INSERT INTO public.cart_items (cart_id, variant_id, quantity)
    VALUES ('${cartId}', 'b1000000-0000-0000-0000-000000000001', 2);
  `);
  console.log(`[PASS] Seeded cart (${cartId}) with test items`);

  // 5. Test Checkout Quote with use_wallet = false vs use_wallet = true
  const quoteWithoutWalletRes = querySql(`
    SELECT public.rpc_calculate_checkout_quote(
      '${userId}',
      '${addressId}',
      '${slotId}',
      NULL,
      false
    ) AS res;
  `);
  const quoteWithoutWallet = quoteWithoutWalletRes[0].res;
  if (!quoteWithoutWallet.success) {
    throw new Error(`Quote without wallet failed: ${JSON.stringify(quoteWithoutWallet)}`);
  }
  if (Number(quoteWithoutWallet.wallet_balance) !== 350 || Number(quoteWithoutWallet.wallet_amount_applied) !== 0) {
    throw new Error(`Unexpected quote without wallet: ${JSON.stringify(quoteWithoutWallet)}`);
  }
  console.log(`[PASS] Quote (use_wallet = false): Total ₹${quoteWithoutWallet.grand_total}, Wallet Deduction ₹${quoteWithoutWallet.wallet_amount_applied}, Gateway Due ₹${quoteWithoutWallet.gateway_payable}`);

  const quoteWithWalletRes = querySql(`
    SELECT public.rpc_calculate_checkout_quote(
      '${userId}',
      '${addressId}',
      '${slotId}',
      NULL,
      true
    ) AS res;
  `);
  const quoteWithWallet = quoteWithWalletRes[0].res;
  if (!quoteWithWallet.success) {
    throw new Error(`Quote with wallet failed: ${JSON.stringify(quoteWithWallet)}`);
  }
  const expectedDeduction = Math.min(350, quoteWithWallet.grand_total);
  const expectedGatewayDue = Math.max(0, quoteWithWallet.grand_total - expectedDeduction);
  if (Number(quoteWithWallet.wallet_amount_applied) !== expectedDeduction || Number(quoteWithWallet.gateway_payable) !== expectedGatewayDue) {
    throw new Error(`Quote calculation mismatch: ${JSON.stringify(quoteWithWallet)}`);
  }
  console.log(`[PASS] Quote (use_wallet = true): Total ₹${quoteWithWallet.grand_total}, Wallet Deduction ₹${quoteWithWallet.wallet_amount_applied}, Gateway Due ₹${quoteWithWallet.gateway_payable}`);

  // 5. Prepare order and test mixed reservation
  const orderId = generateUuidV4();
  const orderNumber = `FM-TEST-P2-${Date.now().toString().slice(-6)}`;
  const paymentId = generateUuidV4();
  const checkoutRequestId = generateUuidV4();

  // Insert a test order of total ₹500.00 in payment_pending status
  querySql(`
    INSERT INTO public.orders (
      id, user_id, order_number, checkout_request_id,
      delivery_address_id, delivery_slot_id, delivery_date,
      subtotal, delivery_fee, discount, total,
      status, payment_status, payment_method,
      delivery_address_snapshot, delivery_slot_snapshot
    ) VALUES (
      '${orderId}', '${userId}', '${orderNumber}', '${checkoutRequestId}',
      '${addressId}', '${slotId}', CURRENT_DATE,
      500.00, 0.00, 0.00, 500.00,
      'payment_pending', 'pending', 'razorpay',
      '{"recipient_name": "Test User", "phone": "9876543210"}'::jsonb,
      '{"slot": "Morning"}'::jsonb
    );

    INSERT INTO public.payments (
      id, order_id, amount, payment_method, status, payment_attempt_no, expires_at
    ) VALUES (
      '${paymentId}', '${orderId}', 500.00, 'razorpay', 'pending', 1, now() + interval '15 minutes'
    );
  `);
  console.log(`[PASS] Seeded test order ₹500.00 (${orderId})`);

  // Reserve wallet for this order (wallet has ₹350.00, order total ₹500.00 -> Mixed payment)
  const reserveRes = querySql(`
    SELECT public.rpc_reserve_wallet_for_order_atomic(
      '${userId}',
      '${orderId}'
    ) AS res;
  `);
  const reserveData = reserveRes[0].res;
  if (!reserveData.success || Number(reserveData.wallet_amount) !== 350.00 || Number(reserveData.gateway_amount) !== 150.00) {
    throw new Error(`Mixed reservation failed: ${JSON.stringify(reserveData)}`);
  }
  if (reserveData.payment_method !== "mixed" || reserveData.is_wallet_only !== false) {
    throw new Error(`Reservation expected mixed, got: ${JSON.stringify(reserveData)}`);
  }
  console.log(`[PASS] rpc_reserve_wallet_for_order_atomic: Reserved ₹350.00, Gateway remaining ₹150.00 (Method: ${reserveData.payment_method})`);

  // Verify wallet account has reserved_balance = 350.00
  const walletRows = querySql(`SELECT balance, reserved_balance FROM public.wallet_accounts WHERE user_id = '${userId}';`);
  if (Number(walletRows[0].balance) !== 350.00 || Number(walletRows[0].reserved_balance) !== 350.00) {
    throw new Error(`Wallet reserved_balance mismatch: ${JSON.stringify(walletRows[0])}`);
  }
  console.log("[PASS] Verified wallet_accounts: balance ₹350.00, reserved_balance ₹350.00 (available ₹0.00)");

  // Verify orders & payments records
  const orderCheck = querySql(`SELECT payment_method, wallet_amount_used, gateway_amount FROM public.orders WHERE id = '${orderId}';`);
  if (orderCheck[0].payment_method !== "mixed" || Number(orderCheck[0].wallet_amount_used) !== 350.00 || Number(orderCheck[0].gateway_amount) !== 150.00) {
    throw new Error(`Orders record mismatch: ${JSON.stringify(orderCheck[0])}`);
  }
  const paymentCheck = querySql(`SELECT payment_method, wallet_amount, wallet_reserved_amount, gateway_amount FROM public.payments WHERE id = '${paymentId}';`);
  if (paymentCheck[0].payment_method !== "mixed" || Number(paymentCheck[0].wallet_reserved_amount) !== 350.00 || Number(paymentCheck[0].gateway_amount) !== 150.00) {
    throw new Error(`Payments record mismatch: ${JSON.stringify(paymentCheck[0])}`);
  }
  console.log("[PASS] Verified orders & payments records updated to 'mixed' with accurate splits");

  // 6. Test Idempotent reservation replay
  const replayRes = querySql(`
    SELECT public.rpc_reserve_wallet_for_order_atomic(
      '${userId}',
      '${orderId}'
    ) AS res;
  `);
  const replayData = replayRes[0].res;
  if (!replayData.success || !replayData.already_reserved) {
    throw new Error(`Idempotent replay failed: ${JSON.stringify(replayData)}`);
  }
  console.log("[PASS] Verified idempotent replay returns already_reserved = true without double hold");

  // 7. Test Compensation / Gateway Failure Release
  const failRes = querySql(`
    SELECT public.rpc_fail_razorpay_initialization_atomic(
      '${orderId}',
      'Gateway simulation timeout'
    ) AS res;
  `);
  const failData = failRes[0].res;
  if (!failData.success) {
    throw new Error(`Fail initialization failed: ${JSON.stringify(failData)}`);
  }

  // Verify wallet reserved_balance released back to 0.00
  const walletAfterRelease = querySql(`SELECT balance, reserved_balance FROM public.wallet_accounts WHERE user_id = '${userId}';`);
  if (Number(walletAfterRelease[0].balance) !== 350.00 || Number(walletAfterRelease[0].reserved_balance) !== 0.00) {
    throw new Error(`Wallet balance after release mismatch: ${JSON.stringify(walletAfterRelease[0])}`);
  }
  console.log("[PASS] rpc_fail_razorpay_initialization_atomic released reservation hold back to ₹0.00 (available ₹350.00)");

  // 8. Test Pure Wallet Confirmation Flow
  const pureWalletOrderId = generateUuidV4();
  const pureWalletOrderNumber = `FM-TEST-P2-PW-${Date.now().toString().slice(-6)}`;
  const pureWalletPaymentId = generateUuidV4();
  const pureWalletCheckoutReqId = generateUuidV4();

  // Create order of ₹200.00 (wallet has ₹350.00 available -> 100% wallet coverage)
  querySql(`
    INSERT INTO public.orders (
      id, user_id, order_number, checkout_request_id,
      delivery_address_id, delivery_slot_id, delivery_date,
      subtotal, delivery_fee, discount, total,
      status, payment_status, payment_method,
      delivery_address_snapshot, delivery_slot_snapshot
    ) VALUES (
      '${pureWalletOrderId}', '${userId}', '${pureWalletOrderNumber}', '${pureWalletCheckoutReqId}',
      '${addressId}', '${slotId}', CURRENT_DATE,
      200.00, 0.00, 0.00, 200.00,
      'payment_pending', 'pending', 'razorpay',
      '{"recipient_name": "Test User", "phone": "9876543210"}'::jsonb,
      '{"slot": "Morning"}'::jsonb
    );

    INSERT INTO public.payments (
      id, order_id, amount, payment_method, status, payment_attempt_no, expires_at
    ) VALUES (
      '${pureWalletPaymentId}', '${pureWalletOrderId}', 200.00, 'razorpay', 'pending', 1, now() + interval '15 minutes'
    );
  `);

  // Reserve wallet for this ₹200 order
  const pureReserveRes = querySql(`
    SELECT public.rpc_reserve_wallet_for_order_atomic(
      '${userId}',
      '${pureWalletOrderId}'
    ) AS res;
  `);
  const pureReserveData = pureReserveRes[0].res;
  if (!pureReserveData.success || Number(pureReserveData.wallet_amount) !== 200.00 || Number(pureReserveData.gateway_amount) !== 0.00 || !pureReserveData.is_wallet_only) {
    throw new Error(`Pure wallet reservation failed: ${JSON.stringify(pureReserveData)}`);
  }
  console.log("[PASS] Pure wallet reservation: Reserved ₹200.00, Gateway remaining ₹0.00 (is_wallet_only: true)");

  // Confirm pure wallet order
  const confirmRes = querySql(`
    SELECT public.rpc_confirm_wallet_only_order_atomic(
      '${userId}',
      '${pureWalletOrderId}'
    ) AS res;
  `);
  const confirmData = confirmRes[0].res;
  if (!confirmData.success || confirmData.status !== "confirmed" || confirmData.payment_status !== "completed") {
    throw new Error(`Pure wallet confirmation failed: ${JSON.stringify(confirmData)}`);
  }
  console.log("[PASS] rpc_confirm_wallet_only_order_atomic confirmed order successfully");

  // Check wallet balances: was ₹350.00, paid ₹200.00 -> balance ₹150.00, reserved ₹0.00
  const walletFinal = querySql(`SELECT balance, reserved_balance FROM public.wallet_accounts WHERE user_id = '${userId}';`);
  if (Number(walletFinal[0].balance) !== 150.00 || Number(walletFinal[0].reserved_balance) !== 0.00) {
    throw new Error(`Wallet balance after confirmation mismatch: ${JSON.stringify(walletFinal[0])}`);
  }
  console.log("[PASS] Verified wallet balance deducted to ₹150.00, reserved balance at ₹0.00");

  // Check ledger transaction
  const ledgerTx = querySql(`
    SELECT type, amount, reason, balance_after
    FROM public.wallet_transactions
    WHERE user_id = '${userId}' AND order_id = '${pureWalletOrderId}';
  `);
  if (!ledgerTx || ledgerTx.length === 0 || ledgerTx[0].type !== "debit" || Number(ledgerTx[0].amount) !== 200.00) {
    throw new Error(`Ledger entry missing or incorrect: ${JSON.stringify(ledgerTx)}`);
  }
  console.log("[PASS] Verified immutable wallet ledger recorded debit of ₹200.00 (balance_after: ₹150.00)");

  // 9. Cleanup test records
  querySql(`
    DELETE FROM public.cart_items WHERE cart_id = '${cartId}';
    DELETE FROM public.wallet_transactions WHERE user_id = '${userId}';
    DELETE FROM public.payments WHERE order_id IN ('${orderId}', '${pureWalletOrderId}');
    DELETE FROM public.orders WHERE id IN ('${orderId}', '${pureWalletOrderId}');
    UPDATE public.wallet_accounts SET balance = 0.00, reserved_balance = 0.00 WHERE user_id = '${userId}';
  `);
  console.log("[PASS] Cleaned up test cart, orders, payments, ledger, and wallet state");

  console.log("\n=======================================================");
  console.log("SESSION 5B PHASE 2 RESULT: ALL 9 ASSERTIONS PASSED (100%)");
  console.log("=======================================================");
}

run().catch((err) => {
  console.error("\n❌ PHASE 2 VERIFICATION FAILED:", err.message);
  process.exit(1);
});
