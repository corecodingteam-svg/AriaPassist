// POST /functions/v1/razorpay-checkout  { circle_id, plan_code, period }
// Creates a Razorpay subscription for the circle's owner and returns its
// hosted checkout URL (UPI, cards). The webhook activates it after payment.
// Only for builds/regions where direct payments are allowed — store builds
// sell through Play Billing / App Store via RevenueCat.
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { z } from "npm:zod@4.6.7";
import { corsHeaders, json } from "../_shared/cors.ts";

const Body = z.object({
  circle_id: z.uuid(),
  plan_code: z.enum(["personal", "family", "team"]),
  period: z.enum(["month", "year"]),
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  const parsed = Body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return json({ error: "bad_request" }, 400);
  const { circle_id, plan_code, period } = parsed.data;
  const rzpPlan = Deno.env.get(`RAZORPAY_PLAN_${plan_code.toUpperCase()}_${period.toUpperCase()}`);
  if (!keyId || !keySecret || !rzpPlan) return json({ error: "not_configured" }, 503);

  const user = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: auth } = await user.auth.getUser();
  if (!auth.user) return json({ error: "unauthorized" }, 401);
  const { data: circle } = await user.from("circles").select("id, owner_id").eq("id", circle_id).maybeSingle();
  if (!circle || circle.owner_id !== auth.user.id) return json({ error: "forbidden" }, 403);

  const res = await fetch("https://api.razorpay.com/v1/subscriptions", {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      plan_id: rzpPlan,
      total_count: period === "month" ? 120 : 10,
      customer_notify: 1,
      notes: { circle_id, plan_code, period, user_id: auth.user.id },
    }),
  });
  if (!res.ok) {
    console.error("razorpay error", res.status, await res.text());
    return json({ error: "provider_error" }, 502);
  }
  const sub = await res.json();
  return json({ url: sub.short_url, subscription_id: sub.id });
});
