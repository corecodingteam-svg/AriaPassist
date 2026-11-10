// WhatsApp (Meta Cloud API) helpers — pure, unit-tested in whatsapp_test.ts.

export interface DueMessage {
  outbox_id: string;
  reminder_id: string;
  phone: string;
  title: string;
  due_at: string;
  timezone: string | null;
  amount: number | null;
}

/** "6:30 pm" in the reminder's zone (en-IN). */
export function formatTime(iso: string, zone: string | null): string {
  return new Intl.DateTimeFormat("en-IN", {
    hour: "numeric", minute: "2-digit", hour12: true, timeZone: zone ?? "Asia/Kolkata",
  }).format(new Date(iso)).replace(/\s?([ap])m/i, (_, x) => ` ${x.toLowerCase()}m`);
}

/** Business-initiated messages must use an approved template. Template
 *  body (register in WhatsApp Manager):
 *    "⏰ Reminder: {{1}} ({{2}}). Reply DONE when it's done." */
export function templateMessage(m: DueMessage, template: string, lang = "en") {
  const what = m.amount != null ? `${m.title} — ₹${Math.round(m.amount).toLocaleString("en-IN")}` : m.title;
  return {
    messaging_product: "whatsapp",
    to: m.phone.replace(/^\+/, ""),
    type: "template",
    template: {
      name: template,
      language: { code: lang },
      components: [{
        type: "body",
        parameters: [
          { type: "text", text: what.slice(0, 200) },
          { type: "text", text: formatTime(m.due_at, m.timezone) },
        ],
      }],
    },
  };
}

export interface Inbound {
  phone: string | null;
  contextWamid: string | null;
  text: string | null;
  status: string | null;
  statusWamid: string | null;
}

/** Flattens a webhook body into replies and delivery receipts. */
// deno-lint-ignore no-explicit-any
export function parseWebhook(body: any): Inbound[] {
  const out: Inbound[] = [];
  for (const entry of body?.entry ?? []) {
    for (const change of entry?.changes ?? []) {
      const v = change?.value ?? {};
      for (const m of v.messages ?? []) {
        const text = m.type === "text" ? m.text?.body
          : m.type === "button" ? m.button?.text
          : m.type === "interactive" ? (m.interactive?.button_reply?.title ?? null)
          : null;
        out.push({ phone: m.from ? `+${m.from}` : null, contextWamid: m.context?.id ?? null, text, status: null, statusWamid: null });
      }
      for (const s of v.statuses ?? []) {
        out.push({ phone: null, contextWamid: null, text: null, status: s.status ?? null, statusWamid: s.id ?? null });
      }
    }
  }
  return out;
}

/** X-Hub-Signature-256: "sha256=" + HMAC-SHA256(app secret, raw body). */
export async function verifyMeta(raw: string, header: string | null, appSecret: string): Promise<boolean> {
  if (!header?.startsWith("sha256=") || !appSecret) return false;
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(appSecret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(raw)));
  const hex = [...mac].map((b) => b.toString(16).padStart(2, "0")).join("");
  const got = header.slice(7).toLowerCase();
  if (got.length !== hex.length) return false;
  let diff = 0;
  for (let i = 0; i < hex.length; i++) diff |= hex.charCodeAt(i) ^ got.charCodeAt(i);
  return diff === 0;
}
