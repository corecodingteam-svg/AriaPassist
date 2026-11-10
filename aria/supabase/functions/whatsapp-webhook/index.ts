// GET  /functions/v1/whatsapp-webhook  — Meta verification handshake
// POST /functions/v1/whatsapp-webhook  — replies ("done") + delivery receipts
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { json } from "../_shared/cors.ts";
import { parseWebhook, verifyMeta } from "../_shared/whatsapp.ts";

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (req.method === "GET") {
    const ok = url.searchParams.get("hub.mode") === "subscribe" &&
      url.searchParams.get("hub.verify_token") === (Deno.env.get("WHATSAPP_VERIFY_TOKEN") ?? "\u0000");
    return ok
      ? new Response(url.searchParams.get("hub.challenge") ?? "", { status: 200 })
      : new Response("forbidden", { status: 403 });
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const raw = await req.text();
  if (!(await verifyMeta(raw, req.headers.get("X-Hub-Signature-256"), Deno.env.get("WHATSAPP_APP_SECRET") ?? ""))) {
    return json({ error: "bad_signature" }, 401);
  }
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const results: string[] = [];
  for (const i of parseWebhook(body)) {
    const { data } = await admin.rpc("apply_whatsapp_inbound", {
      p_phone: i.phone, p_context_wamid: i.contextWamid, p_text: i.text,
      p_status: i.status, p_status_wamid: i.statusWamid,
    });
    results.push(String(data));
  }
  return json({ result: results });
});
