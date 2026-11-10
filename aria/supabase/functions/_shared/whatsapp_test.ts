import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { formatTime, parseWebhook, templateMessage, verifyMeta } from "./whatsapp.ts";

Deno.test("template message: title, rupees, local time, no plus in number", () => {
  const m = templateMessage({
    outbox_id: "o", reminder_id: "r", phone: "+919888888888", title: "Pay electricity bill",
    due_at: "2026-11-09T13:00:00Z", timezone: "Asia/Kolkata", amount: 1840,
  }, "aria_reminder");
  assertEquals(m.to, "919888888888");
  assertEquals(m.template.name, "aria_reminder");
  assertEquals(m.template.components[0].parameters.map((p) => p.text), ["Pay electricity bill — ₹1,840", "6:30 pm"]);
  assertEquals(formatTime("2026-11-09T03:30:00Z", null), "9:00 am");
});

Deno.test("webhook: replies with context and receipts", () => {
  const items = parseWebhook({
    entry: [{
      changes: [{
        value: {
          messages: [{ from: "919888888888", type: "text", text: { body: "Done" }, context: { id: "wamid.A" } }],
          statuses: [{ id: "wamid.B", status: "read" }],
        },
      }],
    }],
  });
  assertEquals(items, [
    { phone: "+919888888888", contextWamid: "wamid.A", text: "Done", status: null, statusWamid: null },
    { phone: null, contextWamid: null, text: null, status: "read", statusWamid: "wamid.B" },
  ]);
  assertEquals(parseWebhook({}), []);
});

Deno.test("Meta signature", async () => {
  const raw = '{"entry":[]}';
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode("app-secret"),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = [...new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(raw)))]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
  assert(await verifyMeta(raw, `sha256=${sig}`, "app-secret"));
  assert(!(await verifyMeta(raw, `sha256=${sig}`, "other")));
  assert(!(await verifyMeta(raw, sig, "app-secret")));
});
