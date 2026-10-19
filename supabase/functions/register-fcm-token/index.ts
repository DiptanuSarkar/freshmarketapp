import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { createUserClient, createServiceClient } from "../_shared/keys.ts";

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing Authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const userClient = createUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth.getUser();

    if (authError || !user) {
      return new Response(
        JSON.stringify({ success: false, error: "Unauthorized user session" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const body = await req.json();
    const token = body.token as string | undefined;
    const deviceType = (body.device_type as string | undefined) || "android";

    if (!token || typeof token !== "string" || token.trim().length === 0) {
      return new Response(
        JSON.stringify({ success: false, error: "Invalid or empty token" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Call service-client RPC to safely reassign token and isolate customer
    const serviceClient = createServiceClient();
    const { error: rpcError } = await serviceClient.rpc("rpc_register_fcm_token", {
      p_token: token.trim(),
      p_device_type: deviceType,
    });

    if (rpcError) {
      // Direct SQL fallback if RPC needs auth context
      await serviceClient
        .from("fcm_tokens")
        .update({ is_active: false, updated_at: new Date().toISOString() })
        .eq("token", token.trim())
        .neq("user_id", user.id)
        .eq("is_active", true);

      const { data: existing } = await serviceClient
        .from("fcm_tokens")
        .select("id")
        .eq("user_id", user.id)
        .eq("token", token.trim())
        .maybeSingle();

      if (existing) {
        await serviceClient
          .from("fcm_tokens")
          .update({
            is_active: true,
            device_type: deviceType,
            updated_at: new Date().toISOString(),
            last_seen_at: new Date().toISOString(),
          })
          .eq("id", existing.id);
      } else {
        await serviceClient.from("fcm_tokens").insert({
          user_id: user.id,
          token: token.trim(),
          device_type: deviceType,
          is_active: true,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          last_seen_at: new Date().toISOString(),
        });
      }
    }

    return new Response(
      JSON.stringify({ success: true, message: "FCM token registered successfully" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({
        success: false,
        error: err instanceof Error ? err.message : String(err),
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
