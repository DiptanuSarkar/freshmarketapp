// =============================================================================
// Firebase Cloud Messaging (FCM HTTP v1) Shared Client Module
// - OAuth 2.0 service account authentication using standard Web Crypto RS256
// - In-memory access token caching with proactive renewal
// - Structured provider response classification: success, invalid_token, transient_error, permanent_error
// - Strictly zero private key leakage in logs or responses
// =============================================================================

interface ServiceAccountCredentials {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

let cachedAccessToken: string | null = null;
let tokenExpiresAt = 0;

/**
 * Resolves Firebase service account credentials safely from environment variables.
 */
function getFirebaseCredentials(): ServiceAccountCredentials | null {
  // Option A: Single JSON secret
  const saJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (saJson && saJson.trim().length > 0) {
    try {
      const parsed = JSON.parse(saJson);
      if (parsed.project_id && parsed.client_email && parsed.private_key) {
        return {
          projectId: parsed.project_id,
          clientEmail: parsed.client_email,
          privateKey: parsed.private_key,
        };
      }
    } catch (_) {}
  }

  // Option B: Individual environment variables
  const projectId =
    Deno.env.get("FIREBASE_PROJECT_ID") || "fresh-market-cbf43";
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL");
  const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY");

  if (clientEmail && privateKey) {
    return {
      projectId,
      clientEmail,
      privateKey: privateKey.replace(/\\n/g, "\n"),
    };
  }

  return null;
}

/**
 * Converts a base64url string to Uint8Array.
 */
function base64UrlToBytes(base64url: string): Uint8Array {
  let base64 = base64url.replace(/-/g, "+").replace(/_/g, "/");
  while (base64.length % 4) {
    base64 += "=";
  }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/**
 * Encodes a Uint8Array or string to base64url.
 */
function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function stringToBase64Url(str: string): string {
  return bytesToBase64Url(new TextEncoder().encode(str));
}

/**
 * Imports an RSA PEM private key into a WebCrypto CryptoKey.
 */
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const cleanPem = pem
    .replace(/-----BEGIN[ A-Z_-]+-----/g, "")
    .replace(/-----END[ A-Z_-]+-----/g, "")
    .replace(/\s+/g, "");

  const binaryDer = base64UrlToBytes(cleanPem);

  return await crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer as ArrayBuffer,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"]
  );
}

/**
 * Mints and caches short-lived Google OAuth 2.0 access token for FCM v1.
 */
export async function getFcmAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && tokenExpiresAt > now + 300) {
    return cachedAccessToken;
  }

  const creds = getFirebaseCredentials();
  if (!creds) {
    throw new Error(
      "Missing Firebase server credentials. Ensure FIREBASE_CLIENT_EMAIL and FIREBASE_PRIVATE_KEY are set."
    );
  }

  const header = {
    alg: "RS256",
    typ: "JWT",
  };

  const payload = {
    iss: creds.clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600,
    iat: now,
  };

  const encodedHeader = stringToBase64Url(JSON.stringify(header));
  const encodedPayload = stringToBase64Url(JSON.stringify(payload));
  const signInput = `${encodedHeader}.${encodedPayload}`;

  const cryptoKey = await importPrivateKey(creds.privateKey);
  const signatureBytes = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signInput)
  );

  const signedJwt = `${signInput}.${bytesToBase64Url(new Uint8Array(signatureBytes))}`;

  // Exchange JWT for access token
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: signedJwt,
    }),
  });

  if (!tokenResponse.ok) {
    const errorBody = await tokenResponse.text();
    throw new Error(`OAuth2 token minting failed (${tokenResponse.status}): ${errorBody}`);
  }

  const tokenData = await tokenResponse.json();
  cachedAccessToken = tokenData.access_token;
  tokenExpiresAt = now + (tokenData.expires_in || 3600);

  return cachedAccessToken!;
}

export type FcmSendResult =
  | { status: "success"; messageId: string }
  | { status: "invalid_token"; error: string }
  | { status: "transient_error"; error: string }
  | { status: "permanent_error"; error: string };

/**
 * Sends a notification message via FCM HTTP v1 API.
 */
export async function sendFcmMessage(params: {
  token: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
  channelId?: string;
}): Promise<FcmSendResult> {
  const creds = getFirebaseCredentials();
  const projectId = creds?.projectId || "fresh-market-cbf43";

  let accessToken: string;
  try {
    accessToken = await getFcmAccessToken();
  } catch (err) {
    return {
      status: "transient_error",
      error: `Authentication error: ${err instanceof Error ? err.message : String(err)}`,
    };
  }

  // Ensure all data fields are string values for FCM specification
  const stringifiedData: Record<string, string> = {};
  if (params.data) {
    for (const [key, val] of Object.entries(params.data)) {
      if (val === null || val === undefined) continue;
      stringifiedData[key] = typeof val === "string" ? val : JSON.stringify(val);
    }
  }

  const fcmMessage = {
    message: {
      token: params.token,
      notification: {
        title: params.title,
        body: params.body,
      },
      data: stringifiedData,
      android: {
        priority: "HIGH",
        notification: {
          channel_id: params.channelId || "freshmarket_general",
          sound: "default",
          default_sound: true,
          default_vibrate_timings: true,
        },
      },
    },
  };

  try {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(fcmMessage),
      }
    );

    if (res.ok) {
      const data = await res.json();
      return {
        status: "success",
        messageId: data.name || "message_sent",
      };
    }

    const errorText = await res.text();
    const statusCode = res.status;

    // Classify FCM response errors
    if (
      statusCode === 404 ||
      errorText.includes("UNREGISTERED") ||
      errorText.includes("registration-token-not-registered") ||
      errorText.includes("INVALID_ARGUMENT")
    ) {
      return {
        status: "invalid_token",
        error: `Token unregistered or invalid (${statusCode}): ${errorText}`,
      };
    }

    if (statusCode === 429 || statusCode >= 500) {
      return {
        status: "transient_error",
        error: `Provider rate-limit or transient failure (${statusCode}): ${errorText}`,
      };
    }

    return {
      status: "permanent_error",
      error: `Permanent provider error (${statusCode}): ${errorText}`,
    };
  } catch (netErr) {
    return {
      status: "transient_error",
      error: `Network fetch failed: ${netErr instanceof Error ? netErr.message : String(netErr)}`,
    };
  }
}
