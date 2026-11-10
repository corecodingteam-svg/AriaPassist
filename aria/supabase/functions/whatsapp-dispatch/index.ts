// POST /functions/v1/whatsapp-dispatch  (pg_cron, every minute)
// Claims due reminders for opted-in users and sends WhatsApp templates.
// WHATSAPP_PROVIDER=meta sends via the Cloud API; anything else ("log",
// the default) only logs — safe for local dev and before Meta approval.
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { json } from "../_shared/cors.ts";
import { safeEqual } from "../_shared/billing.ts";
import { type DueMessage, templateMessage } from "../_shared/whatsapp.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const secret = Deno.env.get("CRON_SECRET") ?? "";
  if (!secret || !safeEqual(req.headers.get("x-cron-secret") ?? "", secret)) {
    return json({ error: "unauthorized" }, 401);
  }
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data, error } = await admin.rpc("claim_whatsapp_due", { p_limit: 100 });
  if (error) return json({ error: "claim_failed" }, 500);

  const provider = Deno.env.get("WHATSAPP_PROVIDER") ?? "log";
  const token = Deno.env.get("WHATSAPP_TOKEN");
  const phoneId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID");
  const template = Deno.env.get("WHATSAPP_TEMPLATE") ?? "aria_reminder";
  const results: Record<string, number> = { sent: 0, failed: 0, logged: 0 };

  for (const m of (data ?? []) as DueMessage[]) {
    const body = templateMessage(m, template);
    let status = "logged", wamid: string | null = null, err: string | null = null;
    if (provider === "meta" && token && phoneId) {
      const res = await fetch(`https://graph.facebook.com/v21.0/${phoneId}/messages`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const out = await res.json().catch(() => ({}));
      if (res.ok) {
        status = "sent";
        wamid = out?.messages?.[0]?.id ?? null;
      } else {
        status = "failed";
        err = String(out?.error?.message ?? res.status).slice(0, 300);
      }
    } else {
      console.log("whatsapp (log mode)", m.reminder_id, JSON.stringify(body.template.components));
    }
    results[status] = (results[status] ?? 0) + 1;
    await admin.rpc("record_whatsapp_send", { p_outbox: m.outbox_id, p_status: status, p_wamid: wamid, p_error: err });
  }
  return json({ result: "ok", ...results });
});
