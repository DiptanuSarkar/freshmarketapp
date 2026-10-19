import { SupabaseClient } from "npm:@supabase/supabase-js@2.48.1";
import { getSupabaseUrl, getSecretKey } from "./keys.ts";

export interface CreateNotificationParams {
  userId: string;
  title: string;
  body: string;
  type: string;
  data: Record<string, unknown>;
  eventKey: string;
  triggerDispatch?: boolean;
}

/**
 * Centrally creates authoritative customer notification and durable push outbox job.
 * Guaranteed idempotent by eventKey. Commerce operations never fail if push fails.
 */
export async function createCustomerNotification(
  client: SupabaseClient,
  params: CreateNotificationParams
): Promise<{ success: boolean; notificationId?: string; jobId?: string }> {
  try {
    const { data, error } = await client.rpc(
      "rpc_create_customer_notification_atomic",
      {
        p_user_id: params.userId,
        p_title: params.title,
        p_body: params.body,
        p_type: params.type,
        p_data: params.data,
        p_event_key: params.eventKey,
      }
    );

    if (error) {
      console.error("Error creating customer notification:", error);
      return { success: false };
    }

    const notifId = data?.notification_id;
    const jobId = data?.job_id;

    // Trigger immediate async push dispatch without awaiting or blocking caller
    if (params.triggerDispatch !== false && jobId) {
      const url = `${getSupabaseUrl()}/functions/v1/dispatch-push-notifications`;
      const secret = getSecretKey();
      fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${secret}`,
        },
        body: JSON.stringify({ job_id: jobId }),
      }).catch((e) => {
        // Safe non-blocking log
        console.warn("Immediate push dispatch trigger deferred to outbox worker:", e);
      });
    }

    return {
      success: true,
      notificationId: notifId,
      jobId: jobId,
    };
  } catch (err) {
    console.error("Unexpected notification creation error:", err);
    return { success: false };
  }
}
