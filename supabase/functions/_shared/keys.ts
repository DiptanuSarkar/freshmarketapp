import { createClient } from "npm:@supabase/supabase-js@2.48.1";

/**
 * Safely resolves default publishable and secret keys from environment variables.
 * Prefers new hosted keys (SUPABASE_PUBLISHABLE_KEYS, SUPABASE_PUBLISHABLE_KEY, SUPABASE_SECRET_KEYS, SUPABASE_SECRET_KEY)
 * with graceful fallback to legacy keys (SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY) during migration.
 */

export function getSupabaseUrl(): string {
  return Deno.env.get("SUPABASE_URL") ?? "";
}

export function getPublishableKey(): string {
  // 1. Direct publishable key
  const direct = Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  if (direct && direct.trim().length > 0) return direct.trim();

  // 2. Publishable keys list (comma-separated or JSON)
  const list = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (list && list.trim().length > 0) {
    try {
      const parsed = JSON.parse(list);
      if (Array.isArray(parsed) && parsed.length > 0) {
        return typeof parsed[0] === "string"
          ? parsed[0]
          : (parsed[0].api_key || parsed[0].key || "");
      }
    } catch {
      const first = list.split(",")[0].trim();
      if (first.length > 0) return first;
    }
  }

  // 3. Fallback to legacy anon key
  return Deno.env.get("SUPABASE_ANON_KEY") ?? "";
}

export function getSecretKey(): string {
  // 1. Direct secret key
  const direct = Deno.env.get("SUPABASE_SECRET_KEY");
  if (direct && direct.trim().length > 0) return direct.trim();

  // 2. Secret keys list (comma-separated or JSON)
  const list = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (list && list.trim().length > 0) {
    try {
      const parsed = JSON.parse(list);
      if (Array.isArray(parsed) && parsed.length > 0) {
        return typeof parsed[0] === "string"
          ? parsed[0]
          : (parsed[0].api_key || parsed[0].key || "");
      }
    } catch {
      const first = list.split(",")[0].trim();
      if (first.length > 0) return first;
    }
  }

  // 3. Fallback to legacy service role key
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

export function createServiceClient() {
  const url = getSupabaseUrl();
  const secret = getSecretKey();
  if (!url || !secret) {
    throw new Error("Missing Supabase URL or Secret Key in server environment.");
  }
  return createClient(url, secret, {
    auth: { persistSession: false },
  });
}

export function createUserClient(authHeader: string) {
  const url = getSupabaseUrl();
  const pubKey = getPublishableKey();
  if (!url || !pubKey) {
    throw new Error("Missing Supabase URL or Publishable Key in server environment.");
  }
  return createClient(url, pubKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
}
