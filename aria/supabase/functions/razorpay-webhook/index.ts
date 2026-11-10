// POST /functions/v1/razorpay-webhook
// Razorpay (UPI / cards, direct & web payments) → subscriptions.
// Signature: X-Razorpay-Signature = HMAC-SHA256(raw body, RAZORPAY_WEBHOOK_SECRET).
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { fromRazorpay, verifyRazorpay } from "../_shared/billing.ts";
import { json } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const raw = await req.text();
  const ok = await verifyRazorpay(
    raw, req.headers.get("X-Razorpay-Signature"), Deno.env.get("RAZORPAY_WEBHOOK_SECRET") ?? "",
  );
  if (!ok) return json({ error: "bad_signature" }, 401);

  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const eventId = req.headers.get("X-Razorpay-Event-Id") ?? crypto.randomUUID();
  // deno-lint-ignore no-explicit-any
  const event = fromRazorpay(body as any, eventId);
  if ("ignored" in event) return json({ result: "ignored", reason: event.ignored });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data, error } = await admin.rpc("apply_billing_event", { e: event });
  if (error) {
    console.error("apply_billing_event failed", error);
    return json({ error: "apply_failed" }, 500);
  }
  return json({ result: data });
});
