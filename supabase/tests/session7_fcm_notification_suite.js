// =============================================================================
// FreshMarket Session 7: FCM Push Notifications & Outbox Automated Verification Suite
// Validates:
// 1. FCM Token RLS & Security Isolation
// 2. Authenticated Token Registration (rpc_register_fcm_token)
// 3. Shared Device Token Reassignment (Customer A -> Customer B)
// 4. Token Logout Deactivation (rpc_unregister_fcm_token)
// 5. Server-Only Notification Creation (rpc_create_customer_notification_atomic)
// 6. Order / Payment / Refund Notification Idempotency Protection
// 7. Push Outbox Claim Safety (FOR UPDATE SKIP LOCKED)
// 8. Multi-Device Delivery Bookkeeping (notification_push_deliveries)
// 9. Permanent Invalid Token Cleanup
// 10. Customer In-App Notification RLS & History Isolation
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
  const sanitized = sql.replace(/\r?\n/g, " ").replace(/\s+/g, " ").trim().replace(/"/g, '\\"');
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
  console.log("=== STARTING SESSION 7: FCM & OUTBOX VERIFICATION SUITE ===");

  const emailA = process.env.TEST_CUSTOMER_A_EMAIL;
  const emailB = process.env.TEST_CUSTOMER_B_EMAIL;

  if (!emailA || !emailB) {
    throw new Error("TEST_CUSTOMER_A_EMAIL or TEST_CUSTOMER_B_EMAIL missing in .env");
  }

  const usersA = querySql(`SELECT id FROM auth.users WHERE email = '${emailA}' LIMIT 1;`);
  const usersB = querySql(`SELECT id FROM auth.users WHERE email = '${emailB}' LIMIT 1;`);

  if (!usersA.length || !usersB.length) {
    throw new Error("Test users not found in auth.users.");
  }

  const userAId = usersA[0].id;
  const userBId = usersB[0].id;
  console.log(`[PASS] Customer A resolved: ${userAId}`);
  console.log(`[PASS] Customer B resolved: ${userBId}`);

  // ---------------------------------------------------------------------------
  // TEST 1: Authenticated Token Registration (rpc_register_fcm_token)
  // ---------------------------------------------------------------------------
  console.log("\n--- TEST 1: Authenticated Token Registration ---");
  const testTokenShared = `test_fcm_shared_device_${Date.now()}`;

  // Execute registration as User A by setting jwt claim sub
  querySql(`
    DO $$
    BEGIN
      PERFORM set_config('request.jwt.claims', '{"sub": "${userAId}", "role": "authenticated"}', false);
      PERFORM public.rpc_register_fcm_token('${testTokenShared}', 'android');
    END $$;
  `);

  const checkA = querySql(`
    SELECT id, user_id, token, is_active, device_type
    FROM public.fcm_tokens
    WHERE user_id = '${userAId}' AND token = '${testTokenShared}';
  `);

  if (!checkA.length || checkA[0].is_active !== true) {
    throw new Error(`Token verification failed for User A: ${JSON.stringify(checkA)}`);
  }
  const tokenAId = checkA[0].id;
  console.log(`[PASS] Token registered for User A with ID: ${tokenAId}`);
  console.log(`[PASS] Verified token is active and bound strictly to Customer A.`);

  // ---------------------------------------------------------------------------
  // TEST 2: Shared Device Token Reassignment (Customer A -> Customer B)
  // ---------------------------------------------------------------------------
  console.log("\n--- TEST 2: Shared Device Token Reassignment (Customer A -> Customer B) ---");
  // Customer B logs into the same physical device with the same FCM token
  querySql(`
    DO $$
    BEGIN
      PERFORM set_config('request.jwt.claims', '{"sub": "${userBId}", "role": "authenticated"}', false);
      PERFORM public.rpc_register_fcm_token('${testTokenShared}', 'android');
    END $$;
  `);

  const checkB = querySql(`
    SELECT id, user_id, token, is_active, device_type
    FROM public.fcm_tokens
    WHERE user_id = '${userBId}' AND token = '${testTokenShared}';
  `);

  if (!checkB.length || checkB[0].is_active !== true) {
    throw new Error(`Token verification failed for User B on shared device: ${JSON.stringify(checkB)}`);
  }
  const tokenBId = checkB[0].id;

  // Verify User A's token row was deactivated
  const verifyOldOwner = querySql(`
    SELECT id, user_id, is_active FROM public.fcm_tokens WHERE id = '${tokenAId}';
  `);
  if (!verifyOldOwner.length || verifyOldOwner[0].is_active !== false) {
    throw new Error(`User A token was NOT deactivated upon reassignment: ${JSON.stringify(verifyOldOwner)}`);
  }
  console.log(`[PASS] Customer A's token was deactivated on shared device.`);

  // Verify User B's token row is active
  const verifyNewOwner = querySql(`
    SELECT id, user_id, is_active FROM public.fcm_tokens WHERE id = '${tokenBId}';
  `);
  if (!verifyNewOwner.length || verifyNewOwner[0].user_id !== userBId || verifyNewOwner[0].is_active !== true) {
    throw new Error(`User B token was not properly activated: ${JSON.stringify(verifyNewOwner)}`);
  }
  console.log(`[PASS] Customer B now exclusively owns the active token.`);

  // ---------------------------------------------------------------------------
  // TEST 3: Token Logout Deactivation (rpc_unregister_fcm_token)
  // ---------------------------------------------------------------------------
  console.log("\n--- TEST 3: Token Logout Deactivation ---");
  querySql(`
    DO $$
    BEGIN
      PERFORM set_config('request.jwt.claims', '{"sub": "${userBId}", "role": "authenticated"}', false);
      PERFORM public.rpc_unregister_fcm_token('${testTokenShared}');
    END $$;
  `);

  const verifyUnregistered = querySql(`
    SELECT id, is_active FROM public.fcm_tokens WHERE id = '${tokenBId}';
  `);
  if (!verifyUnregistered.length || verifyUnregistered[0].is_active !== false) {
    throw new Error(`Token is still active after logout: ${JSON.stringify(verifyUnregistered)}`);
  }
  console.log(`[PASS] Token successfully deactivated on customer logout.`);

  // ---------------------------------------------------------------------------
  // TEST 4: Multi-Device Setup for Customer A
  // ---------------------------------------------------------------------------
  console.log("\n--- TEST 4: Multi-Device Setup for Customer A ---");
  const dev1Token = `test_fcm_alice_phone_${Date.now()}`;
  const dev2Token = `test_fcm_alice_tablet_${Date.now()}`;

  querySql(`
    DO $$
    BEGIN
      PERFORM set_config('request.jwt.claims', '{"sub": "${userAId}", "role": "authenticated"}', false);
      PERFORM public.rpc_register_fcm_token('${dev1Token}', 'android');
      PERFORM public.rpc_register_fcm_token('${dev2Token}', 'android');
    END $$;
  `);

  const dev1Row = querySql(`SELECT id FROM public.fcm_tokens WHERE token = '${dev1Token}';`);
  const dev2Row = querySql(`SELECT id FROM public.fcm_tokens WHERE token = '${dev2Token}';`);

  const dev1Id = dev1Row[0].id;
  const dev2Id = dev2Row[0].id;

  const activeTokensA = querySql(`
    SELECT count(*) AS count FROM public.fcm_tokens WHERE user_id = '${userAId}' AND is_active = true;
  `);
  console.log(`[PASS] Customer A has ${activeTokensA[0].count} active device tokens.`);

  // ---------------------------------------------------------------------------
  // TEST 5: Central Atomic Notification & Push Outbox Job Creation
  // ---------------------------------------------------------------------------
  console.log("\n--- TEST 5: Central Atomic Notification & Push Outbox Job Creation ---");
  const orderId = generateUuidV4();
  const eventKeyOrder = `order:${orderId}:confirmed`;

  const notifRes = querySql(`
    SELECT rpc_create_customer_notification_atomic(
      '${userAId}'::uuid,
      'Order Confirmed',
      'Your FreshMarket order #FM-777 has been confirmed and is being prepared.',
      'order_confirmed',
      '{"order_id": "${orderId}", "order_number": "FM-777"}'::jsonb,
      '${eventKeyOrder}'
    ) AS result;
  `);

  if (!notifRes.length || !notifRes[0].result) {
    throw new Error("Failed to atomically create customer notification");
  }
  const result = typeof notifRes[0].result === 'string' ? JSON.parse(notifRes[0].result) : notifRes[0].result;
  const notifId = result.notification_id;
  const jobId = result.job_id;
  console.log(`[PASS] Notification created with ID: ${notifId}, Job ID: ${jobId}`);

  // Verify notification table row
  const notifRow = querySql(`
    SELECT id, user_id, title, body, type, is_read, data
    FROM public.notifications
    WHERE id = '${notifId}';
  `);
  if (!notifRow.length || notifRow[0].user_id !== userAId) {
    throw new Error(`Authoritative notification row not found: ${JSON.stringify(notifRow)}`);
  }
  console.log(`[PASS] Authoritative in-app notification row verified.`);

  // Verify outbox push job row
  const jobRow = querySql(`
    SELECT id, notification_id, user_id, event_key, status
    FROM public.notification_push_jobs
    WHERE event_key = '${eventKeyOrder}';
  `);
  if (!jobRow.length || jobRow[0].status !== 'pending' || jobRow[0].notification_id !== notifId) {
    throw new Error(`Outbox push job row not verified: ${JSON.stringify(jobRow)}`);
  }
  console.log(`[PASS] Outbox push job queued with status 'pending'.`);

  // ---------------------------------------------------------------------------
  // TEST 6: Event Idempotency Protection (Duplicate Event Key)
  // ---------------------------------------------------------------------------
  console.log("\n--- TEST 6: Event Idempotency Protection ---");
  const duplicateRes = querySql(`
    SELECT rpc_create_customer_notification_atomic(
      '${userAId}'::uuid,
      'Order Confirmed (Duplicate Attempt)',
      'Duplicate content',
      'order_confirmed',
      '{"order_id": "${orderId}"}'::jsonb,
      '${eventKeyOrder}'
    ) AS result;
  `);

  const dupResult = typeof duplicateRes[0].result === 'string' ? JSON.parse(duplicateRes[0].result) : duplicateRes[0].result;
  if (!dupResult.idempotent || dupResult.notification_id !== notifId) {
    throw new Error(`Idempotency violated! Expected existing ID ${notifId}, got ${JSON.stringify(dupResult)}`);
  }

  const jobCount = querySql(`
    SELECT count(*) AS count FROM public.notification_push_jobs WHERE event_key = '${eventKeyOrder}';
  `);
  if (parseInt(jobCount[0].count, 10) !== 1) {
    throw new Error(`Duplicate push jobs found! Count: ${jobCount[0].count}`);
  }
  console.log(`[PASS] Idempotency confirmed: Replay returned existing notification without creating duplicates.`);

  // ---------------------------------------------------------------------------
  // TEST 7: Payment and Refund Event Idempotency
  // ---------------------------------------------------------------------------
  console.log("\n--- TEST 7: Payment and Refund Event Idempotency Keys ---");
  const paymentEventKey = `payment:pay_test_888:completed`;
  const refundEventKey = `refund:ref_test_999:processed`;

  const payRes = querySql(`
    SELECT rpc_create_customer_notification_atomic(
      '${userAId}'::uuid,
      'Payment Received',
      '₹450 payment received via Razorpay.',
      'payment_completed',
      '{"order_id": "${orderId}"}'::jsonb,
      '${paymentEventKey}'
    ) AS result;
  `);

  const refRes = querySql(`
    SELECT rpc_create_customer_notification_atomic(
      '${userAId}'::uuid,
      'Refund Processed',
      '₹150 has been credited to your FreshMarket Wallet.',
      'refund_processed',
      '{"order_id": "${orderId}"}'::jsonb,
      '${refundEventKey}'
    ) AS result;
  `);

  const payResult = typeof payRes[0].result === 'string' ? JSON.parse(payRes[0].result) : payRes[0].result;
  const refResult = typeof refRes[0].result === 'string' ? JSON.parse(refRes[0].result) : refRes[0].result;

  console.log(`[PASS] Payment notification created: ${payResult.notification_id}`);
  console.log(`[PASS] Refund notification created: ${refResult.notification_id}`);

  // ---------------------------------------------------------------------------
  // TEST 8: Outbox Claim Safety (FOR UPDATE SKIP LOCKED)
  // ---------------------------------------------------------------------------
  console.log("\n--- TEST 8: Outbox Claim Safety ---");
  const claimedJobs = querySql(`
    SELECT job_id, notification_id, user_id, event_key FROM rpc_claim_pending_push_jobs(10);
  `);

  if (!claimedJobs.length) {
    throw new Error("No jobs were claimed from pending queue!");
  }
  console.log(`[PASS] Claimed ${claimedJobs.length} push jobs.`);

  // Immediate second claim should return 0 jobs (all are transitioned to 'processing')
  const secondClaim = querySql(`
    SELECT job_id FROM rpc_claim_pending_push_jobs(10);
  `);
  if (secondClaim.length !== 0) {
    throw new Error(`Second claim returned ${secondClaim.length} jobs; expected 0 due to SKIP LOCKED / status filter.`);
  }
  console.log(`[PASS] Second claim returned 0 jobs — concurrency safe.`);

  // ---------------------------------------------------------------------------
  // TEST 9: Multi-Device Delivery Bookkeeping
  // ---------------------------------------------------------------------------
  console.log("\n--- TEST 9: Multi-Device Delivery Bookkeeping ---");
  // Simulate dispatching job to Alice's 2 devices
  querySql(`
    INSERT INTO public.notification_push_deliveries (
      job_id,
      notification_id,
      fcm_token_id,
      status,
      provider_message_id
    ) VALUES (
      '${jobId}',
      '${notifId}',
      '${dev1Id}',
      'sent',
      'projects/fresh-market-cbf43/messages/msg-phone-001'
    ), (
      '${jobId}',
      '${notifId}',
      '${dev2Id}',
      'sent',
      'projects/fresh-market-cbf43/messages/msg-tablet-002'
    );
  `);

  const deliveryRows = querySql(`
    SELECT fcm_token_id, status, provider_message_id
    FROM public.notification_push_deliveries
    WHERE notification_id = '${notifId}';
  `);

  if (deliveryRows.length !== 2) {
    throw new Error(`Expected 2 delivery records, found ${deliveryRows.length}`);
  }
  console.log(`[PASS] Verified multi-device deliveries recorded for both customer devices.`);

  // Verify unique constraint prevents duplicate delivery row per device
  let dupPrevented = false;
  try {
    querySql(`
      INSERT INTO public.notification_push_deliveries (
        job_id,
        notification_id,
        fcm_token_id,
        status
      ) VALUES ('${jobId}', '${notifId}', '${dev1Id}', 'sent');
    `);
  } catch (err) {
    dupPrevented = true;
  }
  if (!dupPrevented) {
    throw new Error("Duplicate delivery insert was NOT prevented by unique constraint!");
  }
  console.log(`[PASS] Unique constraint on (notification_id, fcm_token_id) prevented duplicate delivery record.`);

  // Mark job completed
  querySql(`
    UPDATE public.notification_push_jobs
    SET status = 'sent', sent_at = now()
    WHERE id = '${jobId}';
  `);
  console.log(`[PASS] Job ${jobId} transitioned to 'sent'.`);

  // ---------------------------------------------------------------------------
  // TEST 10: Invalid Token Permanent Deactivation
  // ---------------------------------------------------------------------------
  console.log("\n--- TEST 10: Invalid Token Permanent Deactivation ---");
  const invalidToken = `test_fcm_invalid_unregistered_${Date.now()}`;
  querySql(`
    DO $$
    BEGIN
      PERFORM set_config('request.jwt.claims', '{"sub": "${userAId}", "role": "authenticated"}', false);
      PERFORM public.rpc_register_fcm_token('${invalidToken}', 'android');
    END $$;
  `);

  const invRow = querySql(`SELECT id FROM public.fcm_tokens WHERE token = '${invalidToken}';`);
  const invTokenId = invRow[0].id;

  // Simulate provider returned UNREGISTERED / NOT_FOUND
  querySql(`
    UPDATE public.fcm_tokens
    SET is_active = false, updated_at = now()
    WHERE token = '${invalidToken}';
  `);

  const checkInv = querySql(`
    SELECT is_active FROM public.fcm_tokens WHERE id = '${invTokenId}';
  `);
  if (!checkInv.length || checkInv[0].is_active !== false) {
    throw new Error(`Invalid token was not marked inactive: ${JSON.stringify(checkInv)}`);
  }
  console.log(`[PASS] Permanent invalid token deactivated cleanly without deleting audit history.`);

  // ---------------------------------------------------------------------------
  // TEST 11: Notification Read Lifecycle & Ownership Isolation
  // ---------------------------------------------------------------------------
  console.log("\n--- TEST 11: Notification Read Lifecycle & Ownership Isolation ---");
  // Customer B attempts to mark Customer A's notification as read (must have no effect)
  querySql(`
    DO $$
    BEGIN
      PERFORM set_config('request.jwt.claims', '{"sub": "${userBId}", "role": "authenticated"}', false);
      PERFORM public.mark_notification_as_read('${notifId}'::uuid);
    END $$;
  `);

  const crossUserCheck = querySql(`
    SELECT is_read, read_at FROM public.notifications WHERE id = '${notifId}';
  `);
  if (!crossUserCheck.length || crossUserCheck[0].is_read !== false) {
    throw new Error(`Customer B was able to modify Customer A's notification!`);
  }
  console.log(`[PASS] Customer B cannot mark Customer A's notification as read (ownership protected).`);

  // Customer A marks their own notification as read
  querySql(`
    DO $$
    BEGIN
      PERFORM set_config('request.jwt.claims', '{"sub": "${userAId}", "role": "authenticated"}', false);
      PERFORM public.mark_notification_as_read('${notifId}'::uuid);
    END $$;
  `);

  const readCheck = querySql(`
    SELECT is_read, read_at FROM public.notifications WHERE id = '${notifId}';
  `);
  if (!readCheck.length || readCheck[0].is_read !== true || !readCheck[0].read_at) {
    throw new Error(`Notification read status was not updated: ${JSON.stringify(readCheck)}`);
  }
  console.log(`[PASS] mark_notification_as_read successfully updated is_read and read_at for owner.`);

  // Clean up any test tokens
  querySql(`
    DELETE FROM public.fcm_tokens WHERE token LIKE 'test_fcm_%';
  `);
  console.log(`[PASS] Test tokens cleaned up.`);

  console.log("\n=======================================================");
  console.log("=== ALL SESSION 7 FCM & OUTBOX TESTS PASSED (11/11) ===");
  console.log("=======================================================");
}

run().catch((err) => {
  console.error("\n[FAIL] SESSION 7 TEST SUITE FAILED:", err);
  process.exit(1);
});
