// POST /functions/v1/renewal-dispatch  (pg_cron daily, 10:00 IST)
// Claims due renewal reminders and sends them by WhatsApp and email.
// WHATSAPP_PROVIDER=meta / EMAIL_PROVIDER=resend send for real; anything
// else only logs (local dev, before accounts exist).
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { json } from "../_shared/cors.ts";
import { safeEqual } from "../_shared/billing.ts";
import { emailMessage, type Notice, whatsappMessage } from "../_shared/renewal.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const secret = Deno.env.get("CRON_SECRET") ?? "";
  if (!secret || !safeEqual(req.headers.get("x-cron-secret") ?? "", secret)) {
    return json({ error: "unauthorized" }, 401);
  }
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data, error } = await admin.rpc("claim_renewal_notices", { p_limit: 500 });
  if (error) return json({ error: "claim_failed" }, 500);

  const wa = {
    provider: Deno.env.get("WHATSAPP_PROVIDER") ?? "log",
    token: Deno.env.get("WHATSAPP_TOKEN"),
    phoneId: Deno.env.get("WHATSAPP_PHONE_NUMBER_ID"),
    template: Deno.env.get("WHATSAPP_RENEWAL_TEMPLATE") ?? "aria_renewal",
  };
  const mail = {
    provider: Deno.env.get("EMAIL_PROVIDER") ?? "log",
    key: Deno.env.get("RESEND_API_KEY"),
    from: Deno.env.get("EMAIL_FROM") ?? "Aria <hello@example.com>",
  };
  const results: Record<string, number> = { sent: 0, failed: 0, logged: 0 };

  for (const n of (data ?? []) as Notice[]) {
    let status = "logged", err: string | null = null;
    try {
      if (n.channel === "whatsapp" && wa.provider === "meta" && wa.token && wa.phoneId) {
        const res = await fetch(`https://graph.facebook.com/v21.0/${wa.phoneId}/messages`, {
          method: "POST",
          headers: { Authorization: `Bearer ${wa.token}`, "Content-Type": "application/json" },
          body: JSON.stringify(whatsappMessage(n, wa.template)),
        });
        status = res.ok ? "sent" : "failed";
        if (!res.ok) err = (await res.text()).slice(0, 300);
      } else if (n.channel === "email" && mail.provider === "resend" && mail.key) {
        const res = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: { Authorization: `Bearer ${mail.key}`, "Content-Type": "application/json" },
          body: JSON.stringify(emailMessage(n, mail.from)),
        });
        status = res.ok ? "sent" : "failed";
        if (!res.ok) err = (await res.text()).slice(0, 300);
      } else {
        console.log("renewal (log mode)", n.channel, n.step, n.plan_code, n.user_id);
      }
    } catch (e) {
      status = "failed";
      err = String(e).slice(0, 300);
    }
    results[status] = (results[status] ?? 0) + 1;
    await admin.rpc("record_renewal_notice", { p_id: n.notice_id, p_status: status, p_error: err });
  }
  return json({ result: "ok", ...results });
});
