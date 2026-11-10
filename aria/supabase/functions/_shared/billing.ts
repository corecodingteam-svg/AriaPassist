// Pure webhook → normalised billing event mapping (unit-tested in
// billing_test.ts). The SQL function public.apply_billing_event() takes
// the result; it is idempotent per (provider, event_id).

export type PlanCode = "personal" | "family" | "team";
export type Period = "month" | "year";
export type Status = "trialing" | "active" | "past_due" | "canceled" | "expired";

export interface BillingEvent {
  provider: "revenuecat" | "razorpay";
  event_id: string;
  type: string;
  circle_id: string;
  user_id?: string;
  plan_code: PlanCode;
  period?: Period;
  status: Status;
  external_ref: string;
  product_id?: string;
  current_period_end?: string;
  trial_end?: string;
  cancel_at_period_end?: boolean;
  amount_inr?: number;
  occurred_at?: string;
  raw?: unknown;
}

/** Store product ids: `aria_family_month`, `aria_team_year`, or Play's
 *  `aria_family:monthly` base-plan form. */
export function parseProduct(id: string | undefined | null): { plan: PlanCode; period?: Period } | null {
  if (!id) return null;
  const m = /aria[_.-](personal|family|team)(?:[_.:-](month|monthly|year|yearly|annual))?/i.exec(id);
  if (!m) return null;
  const p = m[2]?.toLowerCase();
  const period: Period | undefined = !p ? undefined : p.startsWith("month") ? "month" : "year";
  return { plan: m[1].toLowerCase() as PlanCode, period };
}

const iso = (ms?: number | null) => (ms ? new Date(ms).toISOString() : undefined);

// deno-lint-ignore no-explicit-any
type Json = Record<string, any>;

/** RevenueCat webhook body → event, or a reason it's ignored. */
export function fromRevenueCat(body: Json): BillingEvent | { ignored: string } {
  const e = body?.event as Json | undefined;
  if (!e?.type || !e?.id) return { ignored: "malformed" };
  if (e.type === "TEST") return { ignored: "test" };
  const circle = e.subscriber_attributes?.circle_id?.value as string | undefined;
  if (!circle) return { ignored: "no_circle" };
  const productId = (e.type === "PRODUCT_CHANGE" && e.new_product_id) || e.product_id;
  const product = parseProduct(productId);
  if (!product) return { ignored: "unknown_product" };
  const trial = e.period_type === "TRIAL";
  const end = iso(e.expiration_at_ms);
  const base = {
    provider: "revenuecat" as const,
    event_id: String(e.id),
    circle_id: circle,
    user_id: e.app_user_id ?? undefined,
    plan_code: product.plan,
    period: product.period,
    external_ref: String(e.original_transaction_id ?? e.transaction_id ?? e.id),
    product_id: productId,
    occurred_at: iso(e.event_timestamp_ms),
    raw: e,
  };
  const amount = e.currency === "INR" && typeof e.price_in_purchased_currency === "number"
    ? e.price_in_purchased_currency : undefined;
  const live = trial
    ? { status: "trialing" as const, trial_end: end, current_period_end: end }
    : { status: "active" as const, current_period_end: end };
  switch (e.type) {
    case "INITIAL_PURCHASE":
    case "NON_RENEWING_PURCHASE":
      return { ...base, ...live, type: trial ? "trial_started" : "purchase", amount_inr: trial ? 0 : amount };
    case "RENEWAL":
      return { ...base, ...live, type: "renewal", amount_inr: amount };
    case "PRODUCT_CHANGE":
      return { ...base, ...live, type: "product_change" };
    case "UNCANCELLATION":
    case "SUBSCRIPTION_EXTENDED":
    case "TEMPORARY_ENTITLEMENT_GRANT":
      return { ...base, ...live, type: "uncanceled" };
    case "CANCELLATION":
      // A store refund (Google/Apple can refund without asking us) ends
      // access immediately; an ordinary cancel keeps it until the period end.
      if (e.cancel_reason === "CUSTOMER_SUPPORT") {
        const at = iso(e.event_timestamp_ms) ?? new Date().toISOString();
        return { ...base, status: "expired", current_period_end: at, cancel_at_period_end: true, type: "refunded" };
      }
      return { ...base, status: "canceled", current_period_end: end, cancel_at_period_end: true, type: "canceled" };
    case "BILLING_ISSUE":
      return { ...base, status: "past_due", current_period_end: end, type: "billing_issue" };
    case "EXPIRATION":
      return { ...base, status: "expired", current_period_end: end, type: "expired" };
    default:
      return { ignored: `unhandled:${e.type}` };
  }
}

/** Razorpay subscription webhook → event. */
export function fromRazorpay(body: Json, eventId: string): BillingEvent | { ignored: string } {
  const sub = body?.payload?.subscription?.entity as Json | undefined;
  if (!sub?.id || !body?.event) return { ignored: "malformed" };
  const notes = sub.notes ?? {};
  if (!notes.circle_id) return { ignored: "no_circle" };
  const plan = parseProduct(`aria_${notes.plan_code}_${notes.period ?? ""}`);
  if (!plan) return { ignored: "unknown_plan" };
  const pay = body.payload?.payment?.entity as Json | undefined;
  const end = sub.current_end ? new Date(sub.current_end * 1000).toISOString() : undefined;
  const base = {
    provider: "razorpay" as const,
    event_id: eventId,
    circle_id: String(notes.circle_id),
    user_id: notes.user_id ? String(notes.user_id) : undefined,
    plan_code: plan.plan,
    period: plan.period,
    external_ref: String(sub.id),
    product_id: sub.plan_id ? String(sub.plan_id) : undefined,
    current_period_end: end,
    occurred_at: body.created_at ? new Date(body.created_at * 1000).toISOString() : undefined,
    raw: body,
  };
  switch (body.event) {
    case "subscription.activated":
      return { ...base, status: "active", type: "purchase" };
    case "subscription.charged":
      return {
        ...base, status: "active", type: "renewal",
        amount_inr: pay?.currency === "INR" && typeof pay.amount === "number" ? pay.amount / 100 : undefined,
      };
    case "subscription.cancelled":
      return { ...base, status: "canceled", cancel_at_period_end: true, type: "canceled" };
    case "subscription.halted":
    case "subscription.pending":
      return { ...base, status: "past_due", type: "billing_issue" };
    case "subscription.completed":
    case "subscription.expired":
      return { ...base, status: "expired", type: "expired" };
    default:
      return { ignored: `unhandled:${body.event}` };
  }
}

/** Razorpay signs the raw body with HMAC-SHA256 (hex). Constant-time compare. */
export async function verifyRazorpay(raw: string, signature: string | null, secret: string): Promise<boolean> {
  if (!signature || !secret) return false;
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(raw)));
  const hex = [...mac].map((b) => b.toString(16).padStart(2, "0")).join("");
  return safeEqual(hex, signature.trim().toLowerCase());
}

export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
