// POST /functions/v1/revenuecat-webhook
// RevenueCat → subscriptions. Configure in RevenueCat › Integrations ›
// Webhooks with Authorization header "Bearer <REVENUECAT_WEBHOOK_SECRET>".
// The app logs in to RevenueCat with the Supabase user id and sets the
// subscriber attribute `circle_id` before purchasing.
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { fromRevenueCat, safeEqual } from "../_shared/billing.ts";
import { json } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const secret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";
  const auth = req.headers.get("Authorization") ?? "";
  if (!secret || !safeEqual(auth, `Bearer ${secret}`)) return json({ error: "unauthorized" }, 401);

  const body = await req.json().catch(() => null);
  const event = fromRevenueCat(body);
  // 200 for ignored events so RevenueCat doesn't retry them forever.
  if ("ignored" in event) return json({ result: "ignored", reason: event.ignored });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data, error } = await admin.rpc("apply_billing_event", { e: event });
  if (error) {
    console.error("apply_billing_event failed", error);
    return json({ error: "apply_failed" }, 500); // retried by RevenueCat
  }
  return json({ result: data });
});
