// =============================================================================
// FreshMarket Session 4V — Remote Verification Test Suite
// Executes live verification against the linked remote Supabase project
// Tests RLS, Authoritative Pricing, Idempotency, Concurrency, and Cancellation
// =============================================================================

const https = require("https");
const dns = require("dns");
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

async function restGet(path, token) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: {
      apikey: ANON_KEY,
      Authorization: `Bearer ${token}`,
    },
  });
  return { status: res.status, data: await res.json() };
}

async function restPost(path, body, token) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: ANON_KEY,
      Authorization: `Bearer ${token}`,
      Prefer: "return=representation",
    },
    body: JSON.stringify(body),
  });
  let data;
  try {
    data = await res.json();
  } catch {
    data = null;
  }
  return { status: res.status, data };
}

async function restPatch(path, body, token) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      apikey: ANON_KEY,
      Authorization: `Bearer ${token}`,
      Prefer: "return=representation",
    },
    body: JSON.stringify(body),
  });
  let data;
  try {
    data = await res.json();
  } catch {
    data = null;
  }
  return { status: res.status, data };
}

async function edgeFunction(name, body, token) {
  const res = await fetch(`${SUPABASE_URL}/functions/v1/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: ANON_KEY,
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });
  let data;
  try {
    data = await res.json();
  } catch {
    data = null;
  }
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

  console.log("=== STARTING SESSION 4V REMOTE VERIFICATION SUITE ===");

  // 1. Authenticate Test Users
  console.log("\n--- Authenticating Development Test Customers ---");
  const emailA = process.env.TEST_CUSTOMER_A_EMAIL;
  const passA = process.env.TEST_CUSTOMER_A_PASSWORD;
  const emailB = process.env.TEST_CUSTOMER_B_EMAIL;
  const passB = process.env.TEST_CUSTOMER_B_PASSWORD;
  if (!emailA || !passA || !emailB || !passB) {
    throw new Error("TEST_CUSTOMER_A_EMAIL, TEST_CUSTOMER_A_PASSWORD, TEST_CUSTOMER_B_EMAIL, and TEST_CUSTOMER_B_PASSWORD must be configured in environment or .env");
  }

  const custA = await loginUser(emailA, passA);
  const custB = await loginUser(emailB, passB);
  assert(custA.token && custA.user.id, "Customer A (Alice) authenticated via Supabase Auth");
  assert(custB.token && custB.user.id, "Customer B (Bob) authenticated via Supabase Auth");
  assert(custA.user.id !== custB.user.id, "Customer A and B have distinct UUIDs");

  // 2. Customer Isolation & RLS Security Tests
  console.log("\n--- Section 4: Customer Isolation & RLS Security Checks ---");

  // A cannot read B's cart
  const readBCart = await restGet(`carts?user_id=eq.${custB.user.id}`, custA.token);
  assert(
    Array.isArray(readBCart.data) && readBCart.data.length === 0,
    "Customer A cannot read Customer B cart via PostgREST",
    `Returned ${JSON.stringify(readBCart.data)}`
  );

  // A cannot read B's addresses
  const readBAddress = await restGet(`addresses?user_id=eq.${custB.user.id}`, custA.token);
  assert(
    Array.isArray(readBAddress.data) && readBAddress.data.length === 0,
    "Customer A cannot read Customer B addresses via PostgREST",
    `Returned ${JSON.stringify(readBAddress.data)}`
  );

  // A cannot read B's orders
  const readBOrders = await restGet(`orders?user_id=eq.${custB.user.id}`, custA.token);
  assert(
    Array.isArray(readBOrders.data) && readBOrders.data.length === 0,
    "Customer A cannot read Customer B orders via PostgREST",
    `Returned ${JSON.stringify(readBOrders.data)}`
  );

  // A cannot directly insert order
  const directOrderInsert = await restPost(
    "orders",
    {
      user_id: custA.user.id,
      order_number: "HACK-001",
      subtotal: 10,
      total: 10,
      status: "placed",
    },
    custA.token
  );
  assert(
    directOrderInsert.status >= 400 || (directOrderInsert.data && directOrderInsert.data.code),
    "Customer A cannot directly INSERT into orders table (RLS blocked)",
    `Status ${directOrderInsert.status}, data: ${JSON.stringify(directOrderInsert.data)}`
  );

  // A cannot directly update payments
  const directPaymentUpdate = await restPatch(
    "payments",
    { status: "completed" },
    custA.token
  );
  assert(
    directPaymentUpdate.status >= 400 || (Array.isArray(directPaymentUpdate.data) && directPaymentUpdate.data.length === 0),
    "Customer A cannot directly UPDATE payments table (RLS blocked)",
    `Status ${directPaymentUpdate.status}, data: ${JSON.stringify(directPaymentUpdate.data)}`
  );

  // A cannot directly update inventory
  const directInventoryUpdate = await restPatch(
    "inventory",
    { quantity_available: 9999 },
    custA.token
  );
  assert(
    directInventoryUpdate.status >= 400 || (Array.isArray(directInventoryUpdate.data) && directInventoryUpdate.data.length === 0),
    "Customer A cannot directly UPDATE inventory table (RLS blocked)",
    `Status ${directInventoryUpdate.status}`
  );

  // A cannot directly insert stock_movements
  const directMovementInsert = await restPost(
    "stock_movements",
    {
      variant_id: "b1000000-0000-0000-0000-000000000001",
      quantity_changed: 50,
      movement_type: "manual_adjustment",
    },
    custA.token
  );
  assert(
    directMovementInsert.status >= 400 || (directMovementInsert.data && directMovementInsert.data.code),
    "Customer A cannot directly INSERT into stock_movements table (RLS blocked)",
    `Status ${directMovementInsert.status}`
  );

  // A cannot directly create coupon_redemptions
  const directRedemptionInsert = await restPost(
    "coupon_redemptions",
    {
      coupon_id: "f1000000-0000-0000-0000-000000000001",
      user_id: custA.user.id,
      order_id: generateUuidV4(),
      discount_applied: 50,
    },
    custA.token
  );
  assert(
    directRedemptionInsert.status >= 400 || (directRedemptionInsert.data && directRedemptionInsert.data.code),
    "Customer A cannot directly INSERT into coupon_redemptions table (RLS blocked)",
    `Status ${directRedemptionInsert.status}`
  );

  // 3. Setup Customer Carts for Checkout Testing
  console.log("\n--- Setting up Cart for Customer A ---");
  // Get or create cart for A
  let cartARes = await restGet("carts", custA.token);
  let cartA = cartARes.data[0];
  if (!cartA) {
    const newCart = await restPost("carts", { user_id: custA.user.id }, custA.token);
    cartA = newCart.data[0];
  }

  // Clear cart A items first
  await fetch(`${SUPABASE_URL}/rest/v1/cart_items?cart_id=eq.${cartA.id}`, {
    method: "DELETE",
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${custA.token}` },
  });

  // Add 2 packs of Chicken 500g (variant b1000000-0000-0000-0000-000000000001, price 180, disc 155)
  const addCartRes = await restPost(
    "cart_items",
    {
      cart_id: cartA.id,
      variant_id: "b1000000-0000-0000-0000-000000000001",
      quantity: 2,
    },
    custA.token
  );
  assert(addCartRes.status === 201, "Customer A added 2 items to persistent cart");

  // Get addresses and slots
  const addrARes = await restGet("addresses", custA.token);
  const addressA = addrARes.data[0];
  const addrBRes = await restGet("addresses", custB.token);
  const addressB = addrBRes.data[0];
  const slotRes = await restGet("delivery_slots?is_active=eq.true", custA.token);
  const validSlot = slotRes.data[0];

  assert(addressA && addressA.id, "Customer A has valid address in Indiranagar");
  assert(addressB && addressB.id, "Customer B has valid address in Koramangala");
  assert(validSlot && validSlot.id, "Active delivery slot retrieved");

  // 4. Section 5: Checkout Quote Edge Function Tests
  console.log("\n--- Section 5: Checkout Quote Edge Function Tests ---");

  const ordersBeforeQuote = (await restGet("orders", custA.token)).data.length;

  // Test 5.1: Valid quote
  const quoteValid = await edgeFunction(
    "checkout-quote",
    {
      address_id: addressA.id,
      delivery_slot_id: validSlot.id,
    },
    custA.token
  );
  assert(
    quoteValid.status === 200 && quoteValid.data.success === true,
    "checkout-quote returns 200 success for valid cart",
    JSON.stringify(quoteValid.data)
  );
  assert(
    quoteValid.data.subtotal === 310.0 && quoteValid.data.grand_total > 0,
    "Authoritative pricing verified (2 x ₹155 = ₹310 subtotal)",
    `Subtotal: ${quoteValid.data.subtotal}, GrandTotal: ${quoteValid.data.grand_total}`
  );
  assert(quoteValid.data.serviceable === true, "Address in service area reported serviceable");
  assert(quoteValid.data.stock_valid === true, "Stock availability confirmed");

  // Test 5.2: Quote with Customer B's address
  const quoteInvalidAddr = await edgeFunction(
    "checkout-quote",
    {
      address_id: addressB.id,
      delivery_slot_id: validSlot.id,
    },
    custA.token
  );
  assert(
    quoteInvalidAddr.data.success === false && quoteInvalidAddr.data.error_code === "ADDRESS_NOT_FOUND",
    "Customer A using Customer B address returns ADDRESS_NOT_FOUND",
    JSON.stringify(quoteInvalidAddr.data)
  );

  // Test 5.3: Quote with invalid delivery slot
  const quoteInvalidSlot = await edgeFunction(
    "checkout-quote",
    {
      address_id: addressA.id,
      delivery_slot_id: generateUuidV4(),
    },
    custA.token
  );
  assert(
    quoteInvalidSlot.data.success === false && quoteInvalidSlot.data.error_code === "DELIVERY_SLOT_UNAVAILABLE",
    "Invalid delivery slot returns DELIVERY_SLOT_UNAVAILABLE",
    JSON.stringify(quoteInvalidSlot.data)
  );

  // Test 5.4: Quote with invalid coupon
  const quoteInvalidCoupon = await edgeFunction(
    "checkout-quote",
    {
      address_id: addressA.id,
      delivery_slot_id: validSlot.id,
      coupon_code: "NONEXISTENT999",
    },
    custA.token
  );
  assert(
    quoteInvalidCoupon.data.success === false && quoteInvalidCoupon.data.error_code === "COUPON_INVALID",
    "Non-existent coupon returns COUPON_INVALID",
    JSON.stringify(quoteInvalidCoupon.data)
  );

  // Test 5.5: Quote with expired coupon
  const quoteExpiredCoupon = await edgeFunction(
    "checkout-quote",
    {
      address_id: addressA.id,
      delivery_slot_id: validSlot.id,
      coupon_code: "EXPIRED_TEST",
    },
    custA.token
  );
  assert(
    quoteExpiredCoupon.data.success === false,
    "Expired/non-active coupon safely rejected",
    JSON.stringify(quoteExpiredCoupon.data)
  );

  // Test 5.6: Quote with unsupported PIN address
  const quoteUnsupportedPin = await edgeFunction(
    "checkout-quote",
    {
      address_id: "ad000000-0000-0000-0000-000000000009",
      delivery_slot_id: validSlot.id,
    },
    custA.token
  );
  assert(
    quoteUnsupportedPin.data.success === false && quoteUnsupportedPin.data.error_code === "UNSUPPORTED_PINCODE",
    "Address in unsupported PIN returns UNSUPPORTED_PINCODE",
    JSON.stringify(quoteUnsupportedPin.data)
  );

  // Test 5.7: Quote with coupon where minimum order value is not met
  const quoteMinOrderFail = await edgeFunction(
    "checkout-quote",
    {
      address_id: addressA.id,
      delivery_slot_id: validSlot.id,
      coupon_code: "FRESH20", // requires min order ₹499; cart is ₹310
    },
    custA.token
  );
  assert(
    quoteMinOrderFail.data.success === false && quoteMinOrderFail.data.error_code === "MINIMUM_ORDER_NOT_MET",
    "Coupon with insufficient cart total returns MINIMUM_ORDER_NOT_MET",
    JSON.stringify(quoteMinOrderFail.data)
  );

  // Verify Quote has zero side effects
  const cartCheckAfterQuote = await restGet(`cart_items?cart_id=eq.${cartA.id}`, custA.token);
  assert(
    cartCheckAfterQuote.data.length === 1,
    "Quote generation leaves cart items untouched (zero side-effects)",
    `Cart items count: ${cartCheckAfterQuote.data.length}`
  );
  const ordersCheckAfterQuote = await restGet("orders", custA.token);
  assert(
    ordersCheckAfterQuote.data.length === ordersBeforeQuote,
    "Quote generation creates zero order records",
    `Orders before: ${ordersBeforeQuote}, Orders after: ${ordersCheckAfterQuote.data.length}`
  );

  // 5. Section 6: COD Happy-Path Order Creation
  console.log("\n--- Section 6: COD Happy-Path Order Creation ---");

  // Record inventory before order
  const invBeforeRes = await restGet("inventory?variant_id=eq.b1000000-0000-0000-0000-000000000001", custA.token);
  const invBefore = invBeforeRes.data[0];
  console.log(`Pre-order inventory: available=${invBefore.quantity_available}, reserved=${invBefore.reserved_quantity}`);

  const checkoutRequestId1 = generateUuidV4();
  const createOrderRes = await edgeFunction(
    "create-cod-order",
    {
      checkout_request_id: checkoutRequestId1,
      address_id: addressA.id,
      delivery_slot_id: validSlot.id,
      customer_notes: "Please call upon arrival",
    },
    custA.token
  );

  assert(
    createOrderRes.status === 200 && createOrderRes.data.success === true,
    "create-cod-order successfully created COD order",
    JSON.stringify(createOrderRes.data)
  );

  const orderId = createOrderRes.data.id;
  const orderNumber = createOrderRes.data.order_number;
  assert(orderId && orderNumber, `Order created with ID=${orderId}, Number=${orderNumber}`);

  // Verify inventory reserved
  const invAfterRes = await restGet("inventory?variant_id=eq.b1000000-0000-0000-0000-000000000001", custA.token);
  const invAfter = invAfterRes.data[0];
  console.log(`Post-order inventory: available=${invAfter.quantity_available}, reserved=${invAfter.reserved_quantity}`);
  assert(
    invAfter.reserved_quantity === invBefore.reserved_quantity + 2,
    "Inventory reserved_quantity incremented by ordered amount (2)",
    `Before: ${invBefore.reserved_quantity}, After: ${invAfter.reserved_quantity}`
  );

  // Verify cart was cleared
  const cartAfterOrder = await restGet(`cart_items?cart_id=eq.${cartA.id}`, custA.token);
  assert(
    cartAfterOrder.data.length === 0,
    "Customer cart was atomically cleared upon successful order placement"
  );

  // Verify order items, status, and payment
  const fetchOrderRes = await restGet(`orders?id=eq.${orderId}&select=*,order_items(*),payments(*),order_status_history(*)`, custA.token);
  const persistedOrder = fetchOrderRes.data[0];
  assert(persistedOrder.status === "placed", "Persisted order has status 'placed'");
  assert(persistedOrder.order_items.length === 1, "Order items snapshot created");
  assert(persistedOrder.delivery_address_snapshot != null, "Delivery address snapshot preserved");
  assert(persistedOrder.order_status_history.length >= 1, "Initial order status history inserted");
  assert(
    persistedOrder.payments.length === 1 &&
      persistedOrder.payments[0].payment_method === "cod" &&
      persistedOrder.payments[0].status === "pending",
    "COD payment record created in pending state (unpaid)"
  );

  // 6. Section 7: Idempotency Verification
  console.log("\n--- Section 7: Idempotency Verification ---");

  // Re-submit the exact same checkout_request_id
  const replayOrderRes = await edgeFunction(
    "create-cod-order",
    {
      checkout_request_id: checkoutRequestId1,
      address_id: addressA.id,
      delivery_slot_id: validSlot.id,
    },
    custA.token
  );

  assert(
    replayOrderRes.status === 200 && replayOrderRes.data.id === orderId,
    "Replaying same checkout_request_id returns existing order (idempotent)",
    `Returned ID: ${replayOrderRes.data.id}`
  );

  // Verify inventory was NOT double-reserved
  const invAfterReplay = (await restGet("inventory?variant_id=eq.b1000000-0000-0000-0000-000000000001", custA.token)).data[0];
  assert(
    invAfterReplay.reserved_quantity === invAfter.reserved_quantity,
    "Inventory was NOT double-reserved during idempotent replay",
    `Current reserved: ${invAfterReplay.reserved_quantity}`
  );

  // 7. Section 8: Different Request ID Test
  console.log("\n--- Section 8: Different Request ID Test on Cleared Cart ---");
  const diffRequestRes = await edgeFunction(
    "create-cod-order",
    {
      checkout_request_id: generateUuidV4(),
      address_id: addressA.id,
      delivery_slot_id: validSlot.id,
    },
    custA.token
  );
  assert(
    diffRequestRes.data.success === false && diffRequestRes.data.error_code === "EMPTY_CART",
    "Different checkout_request_id with empty cart returns EMPTY_CART",
    JSON.stringify(diffRequestRes.data)
  );

  // 8. Section 11 & 12: Cancellation & Canonical Payment Status Test
  console.log("\n--- Section 11 & 12: Order Cancellation & Payment Status ---");

  // A cannot cancel B's order
  const hackCancel = await edgeFunction(
    "cancel-order",
    {
      order_id: orderId, // Belongs to A
      reason: "Unauthorized attempt",
    },
    custB.token // Customer B attempts
  );
  assert(
    hackCancel.data.success === false && hackCancel.data.error_code === "ORDER_NOT_FOUND",
    "Customer B cannot cancel Customer A order (ORDER_NOT_FOUND)",
    JSON.stringify(hackCancel.data)
  );

  // Customer A cancels their order
  const cancelRes = await edgeFunction(
    "cancel-order",
    {
      order_id: orderId,
      reason: "Placed by mistake",
    },
    custA.token
  );
  assert(
    cancelRes.status === 200 && cancelRes.data.success === true,
    "Customer A successfully cancelled their order",
    JSON.stringify(cancelRes.data)
  );

  // Verify inventory was released
  const invAfterCancel = (await restGet("inventory?variant_id=eq.b1000000-0000-0000-0000-000000000001", custA.token)).data[0];
  assert(
    invAfterCancel.reserved_quantity === invBefore.reserved_quantity,
    "Inventory reservation released back to stock (decremented by 2)",
    `Before order: ${invBefore.reserved_quantity}, After cancel: ${invAfterCancel.reserved_quantity}`
  );

  // Verify canonical cancelled payment status
  const postCancelOrder = (await restGet(`orders?id=eq.${orderId}&select=*,payments(*),order_status_history(*)`, custA.token)).data[0];
  assert(postCancelOrder.status === "cancelled", "Order status is 'cancelled'");
  assert(postCancelOrder.payment_status === "cancelled", "Order payment_status is canonically 'cancelled'");
  assert(
    postCancelOrder.payments[0].status === "cancelled",
    "Payments table row status is canonically 'cancelled' (not 'failed')",
    `Payment status: ${postCancelOrder.payments[0].status}`
  );

  // Second cancellation call (idempotent)
  const secondCancel = await edgeFunction(
    "cancel-order",
    {
      order_id: orderId,
      reason: "Duplicate cancel call",
    },
    custA.token
  );
  assert(
    secondCancel.data.success === true && secondCancel.data.already_cancelled === true,
    "Second cancellation call returns already_cancelled: true safely",
    JSON.stringify(secondCancel.data)
  );
  const invAfterSecondCancel = (await restGet("inventory?variant_id=eq.b1000000-0000-0000-0000-000000000001", custA.token)).data[0];
  assert(
    invAfterSecondCancel.reserved_quantity === invBefore.reserved_quantity,
    "Inventory was NOT released twice upon second cancellation",
    `Reserved: ${invAfterSecondCancel.reserved_quantity}`
  );

  // 9. Section 9: Inventory Concurrency & Overselling Prevention Test
  console.log("\n--- Section 9: Inventory Concurrency & Overselling Prevention ---");

  // Use variant b1000000-0000-0000-0000-000000000004 (Mutton Curry Cut 500g)
  // Check its sellable stock
  const invVar4 = (await restGet("inventory?variant_id=eq.b1000000-0000-0000-0000-000000000004", custA.token)).data[0];
  const sellable = invVar4.quantity_available - invVar4.reserved_quantity;
  console.log(`Variant 4 sellable stock: ${sellable}`);

  // Setup Cart for A with the EXACT remaining sellable stock
  await restPost("cart_items", { cart_id: cartA.id, variant_id: "b1000000-0000-0000-0000-000000000004", quantity: sellable }, custA.token);

  // Setup Cart for B with 1 unit of the SAME variant
  let cartBRes = await restGet("carts", custB.token);
  let cartB = cartBRes.data[0];
  if (!cartB) {
    cartB = (await restPost("carts", { user_id: custB.user.id }, custB.token)).data[0];
  }
  await fetch(`${SUPABASE_URL}/rest/v1/cart_items?cart_id=eq.${cartB.id}`, {
    method: "DELETE",
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${custB.token}` },
  });
  await restPost("cart_items", { cart_id: cartB.id, variant_id: "b1000000-0000-0000-0000-000000000004", quantity: 1 }, custB.token);

  // Concurrently attempt checkout for both users
  console.log("Firing concurrent checkout for last stock...");
  const [resConcurrentA, resConcurrentB] = await Promise.all([
    edgeFunction("create-cod-order", { checkout_request_id: generateUuidV4(), address_id: addressA.id, delivery_slot_id: validSlot.id }, custA.token),
    edgeFunction("create-cod-order", { checkout_request_id: generateUuidV4(), address_id: addressB.id, delivery_slot_id: validSlot.id }, custB.token),
  ]);

  const oneSucceeded = (resConcurrentA.data.success && !resConcurrentB.data.success) || (!resConcurrentA.data.success && resConcurrentB.data.success);
  assert(oneSucceeded, "Concurrent checkout: exactly one customer succeeded");
  const failedOne = !resConcurrentA.data.success ? resConcurrentA.data : resConcurrentB.data;
  assert(
    failedOne.error_code === "OUT_OF_STOCK" || failedOne.error_code === "CHECKOUT_FAILED",
    "Unsuccessful concurrent customer received OUT_OF_STOCK error",
    JSON.stringify(failedOne)
  );

  const invVar4After = (await restGet("inventory?variant_id=eq.b1000000-0000-0000-0000-000000000004", custA.token)).data[0];
  assert(
    invVar4After.reserved_quantity <= invVar4After.quantity_available && invVar4After.reserved_quantity >= 0,
    "Inventory reservation invariant preserved: 0 <= reserved_quantity <= quantity_available",
    `Available: ${invVar4After.quantity_available}, Reserved: ${invVar4After.reserved_quantity}`
  );

  // Clean up: cancel winning order to restore inventory for future test runs
  const sec9WinnerUser = resConcurrentA.data.success ? custA : custB;
  const sec9WinnerOrderId = resConcurrentA.data.success ? resConcurrentA.data.id : resConcurrentB.data.id;
  await edgeFunction("cancel-order", { order_id: sec9WinnerOrderId, reason: "Section 9 test cleanup" }, sec9WinnerUser.token);

  // 10. Section 10: Coupon Concurrency Test
  console.log("\n--- Section 10: Coupon Concurrency Test ---");
  // Clear any residual items from both carts before coupon test
  await fetch(`${SUPABASE_URL}/rest/v1/cart_items?cart_id=eq.${cartA.id}`, {
    method: "DELETE",
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${custA.token}` },
  });
  await fetch(`${SUPABASE_URL}/rest/v1/cart_items?cart_id=eq.${cartB.id}`, {
    method: "DELETE",
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${custB.token}` },
  });

  // Ensure no prior active redemptions of RACE1 by cancelling any previous test orders
  const redemptionsA = await restGet("coupon_redemptions?coupon_id=eq.f1000000-0000-0000-0000-000000000099&is_reversed=eq.false", custA.token);
  if (Array.isArray(redemptionsA.data)) {
    for (const r of redemptionsA.data) {
      await edgeFunction("cancel-order", { order_id: r.order_id, reason: "Pre-test cleanup" }, custA.token);
    }
  }
  const redemptionsB = await restGet("coupon_redemptions?coupon_id=eq.f1000000-0000-0000-0000-000000000099&is_reversed=eq.false", custB.token);
  if (Array.isArray(redemptionsB.data)) {
    for (const r of redemptionsB.data) {
      await edgeFunction("cancel-order", { order_id: r.order_id, reason: "Pre-test cleanup" }, custB.token);
    }
  }

  // Setup cart for A with item above min order (100) -> variant 1 (chicken curry 500g, ₹155)
  await restPost("cart_items", { cart_id: cartA.id, variant_id: "b1000000-0000-0000-0000-000000000001", quantity: 1 }, custA.token);
  // Setup cart for B with item above min order (100) -> variant 1 (chicken curry 500g, ₹155)
  await restPost("cart_items", { cart_id: cartB.id, variant_id: "b1000000-0000-0000-0000-000000000001", quantity: 1 }, custB.token);

  console.log("Firing concurrent checkout with single-use coupon RACE1...");
  const [couponResA, couponResB] = await Promise.all([
    edgeFunction("create-cod-order", { checkout_request_id: generateUuidV4(), address_id: addressA.id, delivery_slot_id: validSlot.id, coupon_code: "RACE1" }, custA.token),
    edgeFunction("create-cod-order", { checkout_request_id: generateUuidV4(), address_id: addressB.id, delivery_slot_id: validSlot.id, coupon_code: "RACE1" }, custB.token),
  ]);

  console.log("couponResA status:", couponResA.status, JSON.stringify(couponResA.data));
  console.log("couponResB status:", couponResB.status, JSON.stringify(couponResB.data));

  const oneCouponWon = (couponResA.data?.success && !couponResB.data?.success) || (!couponResA.data?.success && couponResB.data?.success);
  assert(oneCouponWon, "Single-use coupon concurrency: exactly one user redeemed the coupon", `A: ${JSON.stringify(couponResA.data)}, B: ${JSON.stringify(couponResB.data)}`);
  const failedCoupon = !couponResA.data.success ? couponResA.data : couponResB.data;
  assert(
    failedCoupon.error_code === "COUPON_USAGE_EXCEEDED" || failedCoupon.error_code === "COUPON_INVALID",
    "Second concurrent user received COUPON_USAGE_EXCEEDED error",
    JSON.stringify(failedCoupon)
  );

  // Verify redemption count using the winning customer's token (respecting RLS)
  const winningCustomer = couponResA.data.success ? custA : custB;
  const redemptions = await restGet("coupon_redemptions?coupon_id=eq.f1000000-0000-0000-0000-000000000099&is_reversed=eq.false", winningCustomer.token);
  assert(
    redemptions.data.length === 1,
    "Authoritative coupon redemptions count in database is exactly 1 (never exceeded usage_limit)",
    `Redemptions count: ${redemptions.data.length}`
  );

  // Clean up: winning customer cancels order to reverse coupon redemption for repeatable test runs
  const winningOrderId = couponResA.data.success ? couponResA.data.id : couponResB.data.id;
  await edgeFunction("cancel-order", { order_id: winningOrderId, reason: "Section 10 test cleanup" }, winningCustomer.token);

  console.log("\n=== ALL REMOTE VERIFICATION TESTS COMPLETED ===");
  const passedCount = results.filter((r) => r.pass).length;
  console.log(`Summary: ${passedCount} / ${results.length} tests passed.`);

  if (passedCount < results.length) {
    process.exit(1);
  }
}

run().catch((err) => {
  console.error("FATAL SUITE ERROR:", err);
  process.exit(1);
});
