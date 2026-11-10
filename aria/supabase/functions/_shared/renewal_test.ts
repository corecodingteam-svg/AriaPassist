import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { emailMessage, formatDate, headline, type Notice, whatsappMessage } from "./renewal.ts";

const base: Notice = {
  notice_id: "n", channel: "email", step: "d7", user_id: "u", is_owner: true, phone: "+919800000001",
  email: "a@t.dev", plan_code: "family", plan_name: "Family", circle_name: "Sharma family",
  ends_at: "2026-11-16T04:30:00Z", timezone: "Asia/Kolkata",
};

Deno.test("headlines per step", () => {
  assertEquals(formatDate(base.ends_at, "Asia/Kolkata"), "16 Nov");
  assertEquals(headline(base), "Your Family plan ends on 16 Nov. Renew to keep it.");
  assertEquals(headline({ ...base, step: "d1" }), "Your Family plan ends tomorrow. Tap to renew.");
  assert(headline({ ...base, step: "d0", is_owner: false }).includes("for Sharma family has ended"));
  assert(headline({ ...base, step: "courtesy" }).includes("renews automatically"));
  assert(headline({ ...base, step: "payment_issue" }).includes("update your payment method"));
});

Deno.test("WhatsApp template and email", () => {
  const w = whatsappMessage(base, "aria_renewal");
  assertEquals(w.to, "919800000001");
  assertEquals(w.template.components[0].parameters.map((p) => p.text), ["Family", headline(base)]);
  const e = emailMessage(base, "Aria <hello@aria.app>");
  assertEquals(e.to, ["a@t.dev"]);
  assert(e.html.includes("Renew in the app"));
  assert(e.html.includes("non-refundable"));
  assert(!emailMessage({ ...base, step: "courtesy" }, "x").html.includes("Renew in the app"), "no nagging CTA");
});
