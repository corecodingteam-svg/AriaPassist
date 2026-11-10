import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { fromRazorpay, fromRevenueCat, parseProduct, verifyRazorpay } from "./billing.ts";

const circle = "f1000000-0000-0000-0000-0000000000f1";
const rc = (event: Record<string, unknown>) => ({
  event: {
    id: "evt", app_user_id: "user-1", product_id: "aria_family_month",
    original_transaction_id: "GPA.1", expiration_at_ms: Date.UTC(2026, 11, 9),
    subscriber_attributes: { circle_id: { value: circle } }, currency: "INR",
    price_in_purchased_currency: 199, period_type: "NORMAL", ...event,
  },
});

Deno.test("product ids", () => {
  assertEquals(parseProduct("aria_family_month"), { plan: "family", period: "month" });
  assertEquals(parseProduct("aria_team:annual"), { plan: "team", period: "year" });
  assertEquals(parseProduct("com.aria.aria_personal_yearly"), { plan: "personal", period: "year" });
  assertEquals(parseProduct("aria_personal"), { plan: "personal", period: undefined });
  assertEquals(parseProduct("other_sku"), null);
});

Deno.test("RevenueCat purchase, trial, cancel, expire", () => {
  const p = fromRevenueCat(rc({ type: "INITIAL_PURCHASE" }));
  assert(!("ignored" in p));
  assertEquals([p.status, p.type, p.plan_code, p.period, p.amount_inr, p.external_ref, p.circle_id],
    ["active", "purchase", "family", "month", 199, "GPA.1", circle]);
  assertEquals(p.current_period_end, "2026-12-09T00:00:00.000Z");

  const t = fromRevenueCat(rc({ type: "INITIAL_PURCHASE", period_type: "TRIAL" }));
  assert(!("ignored" in t));
  assertEquals([t.status, t.type, t.trial_end, t.amount_inr], ["trialing", "trial_started", t.current_period_end, 0]);

  const c = fromRevenueCat(rc({ type: "CANCELLATION" }));
  assert(!("ignored" in c));
  assertEquals([c.status, c.cancel_at_period_end], ["canceled", true]);

  const refund = fromRevenueCat(rc({ type: "CANCELLATION", cancel_reason: "CUSTOMER_SUPPORT", event_timestamp_ms: Date.UTC(2026, 10, 20) }));
  assert(!("ignored" in refund));
  assertEquals([refund.status, refund.type, refund.current_period_end], ["expired", "refunded", "2026-11-20T00:00:00.000Z"]);

  const x = fromRevenueCat(rc({ type: "EXPIRATION" }));
  assert(!("ignored" in x));
  assertEquals(x.status, "expired");

  const ch = fromRevenueCat(rc({ type: "PRODUCT_CHANGE", new_product_id: "aria_team_year" }));
  assert(!("ignored" in ch));
  assertEquals([ch.plan_code, ch.period], ["team", "year"]);
});

Deno.test("RevenueCat ignores what it can't place", () => {
  assertEquals(fromRevenueCat(rc({ type: "TEST" })), { ignored: "test" });
  assertEquals(fromRevenueCat(rc({ type: "INITIAL_PURCHASE", subscriber_attributes: {} })), { ignored: "no_circle" });
  assertEquals(fromRevenueCat(rc({ type: "INITIAL_PURCHASE", product_id: "x" })), { ignored: "unknown_product" });
  assertEquals(fromRevenueCat({}), { ignored: "malformed" });
  assertEquals(fromRevenueCat(rc({ type: "USD_ONLY" })), { ignored: "unhandled:USD_ONLY" });
  const usd = fromRevenueCat(rc({ type: "RENEWAL", currency: "USD", price_in_purchased_currency: 2.99 }));
  assert(!("ignored" in usd));
  assertEquals(usd.amount_inr, undefined);
});

Deno.test("Razorpay charged and cancelled", () => {
  const body = (event: string) => ({
    event, created_at: 1794700000,
    payload: {
      subscription: { entity: { id: "sub_1", plan_id: "plan_x", current_end: 1797300000,
        notes: { circle_id: circle, plan_code: "team", period: "year", user_id: "user-1" } } },
      payment: { entity: { amount: 499900, currency: "INR" } },
    },
  });
  const c = fromRazorpay(body("subscription.charged"), "evt_1");
  assert(!("ignored" in c));
  assertEquals([c.status, c.plan_code, c.period, c.amount_inr, c.external_ref, c.user_id],
    ["active", "team", "year", 4999, "sub_1", "user-1"]);
  const x = fromRazorpay(body("subscription.cancelled"), "evt_2");
  assert(!("ignored" in x));
  assertEquals(x.status, "canceled");
  assertEquals(fromRazorpay({ event: "payment.captured", payload: {} }, "e"), { ignored: "malformed" });
});

Deno.test("Razorpay signature", async () => {
  const raw = '{"event":"subscription.charged"}';
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode("s3cret"),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = [...new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(raw)))]
    .map((b) => b.toString(16).padStart(2, "0")).join("");
  assert(await verifyRazorpay(raw, sig, "s3cret"));
  assert(!(await verifyRazorpay(raw + " ", sig, "s3cret")));
  assert(!(await verifyRazorpay(raw, sig, "")));
  assert(!(await verifyRazorpay(raw, null, "s3cret")));
});
