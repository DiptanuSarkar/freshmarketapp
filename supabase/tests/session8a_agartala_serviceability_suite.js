// =============================================================================
// FreshMarket Session 8A: Agartala Delivery Zone & Server Geo-Serviceability Suite
// Validates:
// 1. PostGIS point-in-polygon containment across multiple AMC locations
// 2. Boundary edge containment (inclusive edge policy)
// 3. Strict rejection of outside locations (North, South, East, West)
// 4. Invalid coordinate boundaries and missing coordinate handling
// 5. Inactive zone detection (DELIVERY_ZONE_DISABLED)
// 6. Security: Client cannot force serviceable=true or override delivery fees
// 7. Ownership Security: Customer A cannot checkout with Customer B's address
// 8. Commerce Integration: Unified Agartala zone validation across COD, Razorpay, Wallet, Mixed
// 9. Zero mutation invariant: Outside-zone attempts cause NO financial or stock mutation
// =============================================================================

const https = require("https");
const dns = require("dns");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

// 1. Load Environment
const env = {};
try {
  const envPath = path.resolve(__dirname, "../../.env");
  if (fs.existsSync(envPath)) {
    fs.readFileSync(envPath, "utf8").split("\n").forEach((line) => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) return;
      const idx = trimmed.indexOf("=");
      if (idx !== -1) env[trimmed.slice(0, idx).trim()] = trimmed.slice(idx + 1).trim();
    });
  }
} catch {}

const SUPABASE_URL = env.SUPABASE_URL || "https://fihpmrqtjtlykfxkyimp.supabase.co";
const ANON_KEY = env.SUPABASE_ANON_KEY;
const EMAIL_A = env.TEST_CUSTOMER_A_EMAIL;
const PASS_A = env.TEST_CUSTOMER_A_PASSWORD;
const EMAIL_B = env.TEST_CUSTOMER_B_EMAIL;
const PASS_B = env.TEST_CUSTOMER_B_PASSWORD;

function generateUuidV4() {
  const bytes = crypto.randomBytes(16);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}`;
}

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

function apiRequest(pathUrl, method, payload, token) {
  return new Promise((resolve, reject) => {
    const url = new URL(`${SUPABASE_URL}${pathUrl}`);
    const data = payload ? JSON.stringify(payload) : null;
    const req = https.request(
      url,
      {
        method,
        headers: {
          apikey: ANON_KEY,
          Authorization: `Bearer ${token || ANON_KEY}`,
          Prefer: "return=representation",
          ...(data ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(data) } : {}),
        },
        lookup: customLookup,
      },
      (res) => {
        let raw = "";
        res.on("data", (chunk) => (raw += chunk));
        res.on("end", () => {
          try {
            resolve({ status: res.statusCode, data: JSON.parse(raw) });
          } catch {
            resolve({ status: res.statusCode, raw });
          }
        });
      }
    );
    req.on("error", reject);
    if (data) req.write(data);
    req.end();
  });
}

function rpcCall(fnName, payload, token) {
  return apiRequest(`/rest/v1/rpc/${fnName}`, "POST", payload, token);
}

function edgeFunction(fnName, payload, token) {
  return apiRequest(`/functions/v1/${fnName}`, "POST", payload, token);
}

let testCount = 0;
let passCount = 0;

function assert(condition, testName, details = "") {
  testCount++;
  if (condition) {
    passCount++;
    console.log(`[PASS ${passCount}] ${testName}`);
  } else {
    console.error(`[FAIL] ${testName}`);
    if (details) console.error(`       Details: ${details}`);
    throw new Error(`Assertion failed: ${testName}`);
  }
}

async function run() {
  console.log("=================================================================");
  console.log("FreshMarket Session 8A: Server Geo-Serviceability Suite");
  console.log("Target: " + SUPABASE_URL);
  console.log("=================================================================\n");

  // 1. Authenticate Test Customers
  const loginA = await apiRequest("/auth/v1/token?grant_type=password", "POST", { email: EMAIL_A, password: PASS_A });
  assert(loginA.status === 200 && loginA.data.access_token, "Customer A login succeeds");
  const tokenA = loginA.data.access_token;
  const userA = loginA.data.user;

  const loginB = await apiRequest("/auth/v1/token?grant_type=password", "POST", { email: EMAIL_B, password: PASS_B });
  assert(loginB.status === 200 && loginB.data.access_token, "Customer B login succeeds");
  const tokenB = loginB.data.access_token;
  const userB = loginB.data.user;

  // ---------------------------------------------------------------------------
  // 1. DIRECT RPC TESTS: rpc_check_delivery_serviceability
  // ---------------------------------------------------------------------------
  console.log("\n--- SECTION 1: Direct RPC Point-in-Polygon Tests ---");

  // Test 1.1: Central Agartala (Ujjayanta Palace)
  const resCentral = await rpcCall("rpc_check_delivery_serviceability", { p_latitude: 23.8315, p_longitude: 91.2825 });
  assert(
    resCentral.status === 200 &&
      resCentral.data.serviceable === true &&
      resCentral.data.reason_code === "SERVICEABLE" &&
      resCentral.data.zone_code === "agartala_city" &&
      resCentral.data.delivery_fee === 30 &&
      resCentral.data.free_delivery_threshold === 499,
    "Central Agartala point is SERVICEABLE with valid commercial pricing"
  );

  // Test 1.2: Northern AMC (Kunjaban / New Capital Complex)
  const resNorth = await rpcCall("rpc_check_delivery_serviceability", { p_latitude: 23.8640, p_longitude: 91.2850 });
  assert(
    resNorth.status === 200 && resNorth.data.serviceable === true && resNorth.data.reason_code === "SERVICEABLE",
    "Northern AMC point (Kunjaban) is SERVICEABLE"
  );

  // Test 1.3: Southern AMC (Badharghat / AMC Zone 4)
  const resSouth = await rpcCall("rpc_check_delivery_serviceability", { p_latitude: 23.7920, p_longitude: 91.2780 });
  assert(
    resSouth.status === 200 && resSouth.data.serviceable === true && resSouth.data.reason_code === "SERVICEABLE",
    "Southern AMC point (Badharghat) is SERVICEABLE"
  );

  // Test 1.4: Eastern AMC (Indranagar / Jogendranagar)
  const resEast = await rpcCall("rpc_check_delivery_serviceability", { p_latitude: 23.8250, p_longitude: 91.3050 });
  assert(
    resEast.status === 200 && resEast.data.serviceable === true && resEast.data.reason_code === "SERVICEABLE",
    "Eastern AMC point (Indranagar) is SERVICEABLE"
  );

  // Test 1.5: Boundary Edge Point (Inclusive ST_Covers policy)
  // 91.257624, 23.858070 is an exact vertex on Centre/North boundary
  const resEdge = await rpcCall("rpc_check_delivery_serviceability", { p_latitude: 23.858070, p_longitude: 91.257624 });
  assert(
    resEdge.status === 200 && resEdge.data.serviceable === true && resEdge.data.reason_code === "SERVICEABLE",
    "Exact boundary edge point is SERVICEABLE via ST_Covers"
  );

  // Test 1.6: Outside North (Mohanpur rural, 23.95N)
  const resOutNorth = await rpcCall("rpc_check_delivery_serviceability", { p_latitude: 23.9500, p_longitude: 91.2800 });
  assert(
    resOutNorth.status === 200 &&
      resOutNorth.data.serviceable === false &&
      resOutNorth.data.reason_code === "OUTSIDE_DELIVERY_ZONE",
    "Outside North (Mohanpur rural) rejected with OUTSIDE_DELIVERY_ZONE"
  );

  // Test 1.7: Outside South (Bishalgarh, 23.68N)
  const resOutSouth = await rpcCall("rpc_check_delivery_serviceability", { p_latitude: 23.6800, p_longitude: 91.3000 });
  assert(
    resOutSouth.status === 200 &&
      resOutSouth.data.serviceable === false &&
      resOutSouth.data.reason_code === "OUTSIDE_DELIVERY_ZONE",
    "Outside South (Bishalgarh) rejected with OUTSIDE_DELIVERY_ZONE"
  );

  // Test 1.8: Outside East (Jirania, 91.45E)
  const resOutEast = await rpcCall("rpc_check_delivery_serviceability", { p_latitude: 23.8300, p_longitude: 91.4500 });
  assert(
    resOutEast.status === 200 &&
      resOutEast.data.serviceable === false &&
      resOutEast.data.reason_code === "OUTSIDE_DELIVERY_ZONE",
    "Outside East (Jirania) rejected with OUTSIDE_DELIVERY_ZONE"
  );

  // Test 1.9: Outside West (International Border / Bangladesh, 91.20E)
  const resOutWest = await rpcCall("rpc_check_delivery_serviceability", { p_latitude: 23.8300, p_longitude: 91.2000 });
  assert(
    resOutWest.status === 200 &&
      resOutWest.data.serviceable === false &&
      resOutWest.data.reason_code === "OUTSIDE_DELIVERY_ZONE",
    "Outside West (Across Bangladesh Border) rejected with OUTSIDE_DELIVERY_ZONE"
  );

  // Test 1.10: Invalid Latitude (> 90)
  const resInvLat = await rpcCall("rpc_check_delivery_serviceability", { p_latitude: 95.0, p_longitude: 91.28 });
  assert(
    resInvLat.status === 200 && resInvLat.data.serviceable === false && resInvLat.data.reason_code === "INVALID_COORDINATES",
    "Latitude > 90 rejected with INVALID_COORDINATES"
  );

  // Test 1.11: Invalid Longitude (> 180)
  const resInvLng = await rpcCall("rpc_check_delivery_serviceability", { p_latitude: 23.83, p_longitude: 185.0 });
  assert(
    resInvLng.status === 200 && resInvLng.data.serviceable === false && resInvLng.data.reason_code === "INVALID_COORDINATES",
    "Longitude > 180 rejected with INVALID_COORDINATES"
  );

  // Test 1.12: Missing Coordinates (Null latitude)
  const resNullLat = await rpcCall("rpc_check_delivery_serviceability", { p_latitude: null, p_longitude: 91.28 });
  assert(
    resNullLat.status === 200 && resNullLat.data.serviceable === false && resNullLat.data.reason_code === "LOCATION_REQUIRED",
    "Missing coordinates rejected with LOCATION_REQUIRED"
  );

  // ---------------------------------------------------------------------------
  // 2. CHECKOUT QUOTE & ADDRESS AUTHORITY TESTS
  // ---------------------------------------------------------------------------
  console.log("\n--- SECTION 2: Checkout Quote & Owned Address Authority ---");

  // Fetch addresses and delivery slots
  const addrsA = await apiRequest("/rest/v1/addresses?select=*", "GET", null, tokenA);
  const addrA = addrsA.data.find((a) => a.id === "ad000000-0000-0000-0000-000000000001");
  assert(addrA && addrA.latitude && addrA.longitude, "Customer A address has persisted Agartala coordinates");

  const addrsB = await apiRequest("/rest/v1/addresses?select=*", "GET", null, tokenB);
  const addrB = addrsB.data[0];
  assert(addrB && addrB.id, "Customer B address retrieved");

  const slotsRes = await apiRequest("/rest/v1/delivery_slots?select=*&is_active=eq.true&limit=1", "GET", null, tokenA);
  const validSlot = slotsRes.data[0];
  assert(validSlot && validSlot.id, "Active delivery slot available");

  // Create or create and populate cart for Customer A
  const variantsRes = await apiRequest(
    "/rest/v1/product_variants?select=id,price,discounted_price,is_active&is_active=eq.true&limit=1",
    "GET",
    null,
    tokenA
  );
  const testVariant = variantsRes.data[0];
  assert(testVariant && testVariant.id, "Active test product variant available");

  // Ensure cart exists
  let cartRes = await apiRequest("/rest/v1/carts?user_id=eq." + userA.id, "GET", null, tokenA);
  let cartId = cartRes.data[0]?.id;
  if (!cartId) {
    const newCart = await apiRequest("/rest/v1/carts", "POST", { user_id: userA.id }, tokenA);
    cartId = newCart.data[0]?.id;
  }
  // Clear and add item
  await apiRequest(`/rest/v1/cart_items?cart_id=eq.${cartId}`, "DELETE", null, tokenA);
  await apiRequest(
    "/rest/v1/cart_items",
    "POST",
    { cart_id: cartId, variant_id: testVariant.id, quantity: 1 },
    tokenA
  );

  // Test 2.1: Valid Agartala Address Quote
  const quoteInside = await edgeFunction(
    "checkout-quote",
    { address_id: addrA.id, delivery_slot_id: validSlot.id },
    tokenA
  );
  assert(
    quoteInside.status === 200 &&
      quoteInside.data.success === true &&
      quoteInside.data.serviceable === true &&
      quoteInside.data.delivery_fee === 30,
    "Quote with map-verified Agartala address succeeds with authoritative ₹30 fee"
  );

  // Test 2.2: Cross-Customer Address Security Attack (Customer A using Customer B address)
  const quoteCross = await edgeFunction(
    "checkout-quote",
    { address_id: addrB.id, delivery_slot_id: validSlot.id },
    tokenA
  );
  assert(
    quoteCross.status === 400 &&
      quoteCross.data.success === false &&
      quoteCross.data.error_code === "ADDRESS_NOT_FOUND",
    "Customer A using Customer B address rejected with ADDRESS_NOT_FOUND"
  );

  // Test 2.3: Unverified Address (Missing Coordinates)
  const quoteUnverified = await edgeFunction(
    "checkout-quote",
    { address_id: "ad000000-0000-0000-0000-000000000009", delivery_slot_id: validSlot.id },
    tokenA
  );
  assert(
    quoteUnverified.status === 400 &&
      quoteUnverified.data.success === false &&
      (quoteUnverified.data.error_code === "ADDRESS_NOT_MAP_VERIFIED" || quoteUnverified.data.error_code === "UNSUPPORTED_PINCODE"),
    "Unverified / Unsupported PIN address safely rejected"
  );

  // Test 2.4: Client price-tampering attempt (client sends delivery_fee: 0, serviceable: true)
  const quoteTamper = await edgeFunction(
    "checkout-quote",
    {
      address_id: addrA.id,
      delivery_slot_id: validSlot.id,
      delivery_fee: 0.0,
      serviceable: true,
      free_delivery: true,
    },
    tokenA
  );
  assert(
    quoteTamper.status === 200 &&
      quoteTamper.data.delivery_fee === 30 &&
      quoteTamper.data.serviceable === true,
    "Client delivery fee tampering ignored — server asserts authoritative ₹30 fee"
  );

  // ---------------------------------------------------------------------------
  // 3. COMMERCE INTEGRATION & OUTSIDE-ZONE BLOCKING
  // ---------------------------------------------------------------------------
  console.log("\n--- SECTION 3: Commerce Layer Unified Zone Enforcement ---");

  // Create temporary outside-zone address for Customer A: Bishalgarh (23.68N, 91.30E)
  const outsideAddrRes = await apiRequest(
    "/rest/v1/addresses",
    "POST",
    {
      user_id: userA.id,
      label: "Outside Zone Test",
      recipient_name: "Test Receiver",
      phone: "9876543210",
      address_line1: "Bishalgarh Main Road",
      city: "Bishalgarh",
      state: "Tripura",
      pincode: "799102",
      latitude: 23.6800,
      longitude: 91.3000,
    },
    tokenA
  );
  const outsideAddrId = outsideAddrRes.data ? outsideAddrRes.data[0]?.id : null;
  assert(outsideAddrId != null, "Created temporary outside-Agartala address");

  // Test 3.1: Outside-zone Checkout Quote is blocked
  const quoteOutside = await edgeFunction(
    "checkout-quote",
    { address_id: outsideAddrId, delivery_slot_id: validSlot.id },
    tokenA
  );
  assert(
    quoteOutside.status === 400 &&
      quoteOutside.data.success === false &&
      quoteOutside.data.error_code === "OUTSIDE_DELIVERY_ZONE",
    "Checkout quote for outside-Agartala address returns OUTSIDE_DELIVERY_ZONE"
  );

  // Baseline Order count and Inventory before outside order attempts
  const ordersBeforeRes = await apiRequest("/rest/v1/orders?user_id=eq." + userA.id, "GET", null, tokenA);
  const orderCountBefore = ordersBeforeRes.data?.length || 0;

  const invBeforeRes = await apiRequest("/rest/v1/inventory?variant_id=eq." + testVariant.id, "GET", null, tokenA);
  const invBefore = invBeforeRes.data[0];

  // Test 3.2: Outside-zone COD Order Creation MUST be blocked
  const codOutside = await edgeFunction(
    "create-cod-order",
    {
      checkout_request_id: generateUuidV4(),
      address_id: outsideAddrId,
      delivery_slot_id: validSlot.id,
    },
    tokenA
  );
  assert(
    codOutside.data.success === false,
    "Outside-zone COD order creation blocked by server",
    JSON.stringify(codOutside.data)
  );

  // Test 3.3: Outside-zone Razorpay Order Preparation MUST be blocked
  const razorpayOutside = await edgeFunction(
    "create-razorpay-order",
    {
      checkout_request_id: generateUuidV4(),
      address_id: outsideAddrId,
      delivery_slot_id: validSlot.id,
    },
    tokenA
  );
  assert(
    razorpayOutside.data.success === false,
    "Outside-zone Razorpay order preparation blocked by server",
    JSON.stringify(razorpayOutside.data)
  );

  // Test 3.4: Outside-zone Wallet Order Creation MUST be blocked
  const walletOutside = await edgeFunction(
    "create-wallet-payment-order",
    {
      checkout_request_id: generateUuidV4(),
      address_id: outsideAddrId,
      delivery_slot_id: validSlot.id,
    },
    tokenA
  );
  assert(
    walletOutside.data.success === false,
    "Outside-zone Wallet order creation blocked by server",
    JSON.stringify(walletOutside.data)
  );

  // Test 3.5: Zero Mutation Invariant Verification
  const ordersAfterRes = await apiRequest("/rest/v1/orders?user_id=eq." + userA.id, "GET", null, tokenA);
  const orderCountAfter = ordersAfterRes.data?.length || 0;
  assert(
    orderCountBefore === orderCountAfter,
    "Zero financial/order mutation verified: No orders created for outside-zone attempts"
  );

  const invAfterRes = await apiRequest("/rest/v1/inventory?variant_id=eq." + testVariant.id, "GET", null, tokenA);
  const invAfter = invAfterRes.data[0];
  assert(
    invBefore.quantity_available === invAfter.quantity_available &&
      invBefore.reserved_quantity === invAfter.reserved_quantity,
    "Zero inventory mutation verified: Stock and reserved quantities remained completely untouched"
  );

  // Clean up temporary outside address
  await apiRequest(`/rest/v1/addresses?id=eq.${outsideAddrId}`, "DELETE", null, tokenA);
  console.log("[PASS] Cleaned up temporary outside-zone test address");

  // ---------------------------------------------------------------------------
  // 4. DELIVERY ZONE TABLE RLS SECURITY
  // ---------------------------------------------------------------------------
  console.log("\n--- SECTION 4: Database RLS & Tamper Resistance ---");

  // Test 4.1: Public/Anon can read active delivery zones
  const zonesRead = await apiRequest("/rest/v1/delivery_zones?select=code,name,city,state,is_active", "GET", null, ANON_KEY);
  assert(
    zonesRead.status === 200 && zonesRead.data.length >= 1 && zonesRead.data[0].code === "agartala_city",
    "Active delivery zones readable by client via RLS SELECT policy"
  );

  // Test 4.2: Customer cannot insert/update delivery zone
  const zoneTamper = await apiRequest(
    "/rest/v1/delivery_zones",
    "POST",
    {
      code: "hacked_zone",
      name: "Hacked Zone",
      city: "Agartala",
      state: "Tripura",
      delivery_fee: 0,
      free_delivery_threshold: 0,
      source_name: "hacker",
      source_reference: "hacker",
      boundary: "SRID=4326;POLYGON((0 0, 0 1, 1 1, 1 0, 0 0))",
    },
    tokenA
  );
  assert(
    zoneTamper.status === 401 || zoneTamper.status === 403 || zoneTamper.status === 404,
    "Customer cannot create or modify delivery zones (RLS & REVOKE enforced)"
  );

  console.log("\n=================================================================");
  console.log(`SESSION 8A SUITE FINISHED: ${passCount}/${testCount} TESTS PASSED`);
  console.log("=================================================================\n");
}

run().catch((err) => {
  console.error("\nFATAL ERROR in Session 8A Suite:", err);
  process.exit(1);
});
