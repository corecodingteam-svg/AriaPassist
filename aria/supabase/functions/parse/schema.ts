import { z } from "npm:zod@4.6.7";

/**
 * The parser contract (spec §5.2), shared by the model's structured output
 * and server-side validation. Every field is required-but-nullable so the
 * structured-output schema stays strict (no optional keys).
 */
export const Category = z.enum([
  "health",
  "bills",
  "people",
  "home",
  "work",
  "personal",
]);
export const Intent = z.enum([
  "create_reminder",
  "create_list_item",
  "create_note",
  "query",
  "update",
  "delete",
  "snooze",
  "complete",
]);
export const QueryKind = z.enum(["today", "missed", "lookup", "none"]);

export const ParsedItem = z.object({
  title: z.string().describe("Short, natural title, e.g. 'Pay electricity bill'"),
  category: Category,
  datetime: z
    .string()
    .nullable()
    .describe("ISO 8601 with offset, e.g. 2026-12-05T10:00:00+05:30; null if no time"),
  all_day: z.boolean(),
  recurrence: z
    .string()
    .nullable()
    .describe("RRULE subset: FREQ=DAILY|WEEKLY|MONTHLY|YEARLY, INTERVAL, BYDAY (weekly), BYMONTHDAY (monthly), COUNT or UNTIL"),
  priority: z.enum(["low", "normal", "high", "urgent"]),
  amount: z.number().nullable().describe("Rupee amount for bills, else null"),
  contact: z.string().nullable(),
  notes: z.string().nullable(),
  target_id: z
    .string()
    .nullable()
    .describe("For update/delete/snooze/complete: id of the existing reminder from context"),
  snooze_minutes: z.number().int().nullable(),
  list_name: z.string().nullable().describe("For create_list_item: target list, e.g. 'Grocery'"),
  place: z
    .object({
      name: z.string().describe("Place as the user said it: 'home', 'work', 'pharmacy'"),
      on: z.enum(["arrive", "leave"]),
    })
    .nullable()
    .describe("Location trigger: 'when I get home' → {name:'home', on:'arrive'}. Null for time-based reminders."),
});

export const ParseResult = z.object({
  intent: Intent,
  items: z.array(ParsedItem),
  query: QueryKind,
  clarification_needed: z
    .string()
    .nullable()
    .describe("One short question when the request is ambiguous, else null"),
  spoken_reply: z.string().describe("Warm, one-sentence reply Aria speaks back"),
});
export type ParseResult = z.infer<typeof ParseResult>;

// Mirrors the app's RecurrenceRule.tryParse subset exactly.
const RRULE_PART =
  /^(FREQ=(DAILY|WEEKLY|MONTHLY|YEARLY)|INTERVAL=\d{1,3}|BYDAY=(MO|TU|WE|TH|FR|SA|SU)(,(MO|TU|WE|TH|FR|SA|SU))*|BYMONTHDAY=-?\d{1,2}(,-?\d{1,2})*|COUNT=\d{1,4}|UNTIL=\d{8}(T\d{6}Z?)?)$/;

export function validRrule(rule: string): boolean {
  const parts = rule.replace(/^RRULE:/i, "").toUpperCase().split(";").filter(Boolean);
  if (!parts.some((p) => p.startsWith("FREQ="))) return false;
  if (parts.some((p) => p.startsWith("COUNT=")) && parts.some((p) => p.startsWith("UNTIL="))) {
    return false;
  }
  return parts.every((p) => RRULE_PART.test(p));
}

/**
 * Semantic checks structured outputs can't express. Returns a cleaned
 * result or throws. Unknown target ids are dropped (never trust the model
 * to reference rows the user didn't send).
 */
export function sanitize(r: ParseResult, knownIds: Set<string>): ParseResult {
  if (r.items.length > 10) throw new Error("too many items");
  const items = r.items.map((it) => {
    const title = it.title.trim().slice(0, 200);
    if (!title && r.intent.startsWith("create")) throw new Error("empty title");
    if (it.datetime !== null && Number.isNaN(Date.parse(it.datetime))) {
      throw new Error(`bad datetime: ${it.datetime}`);
    }
    if (it.recurrence !== null && !validRrule(it.recurrence)) {
      throw new Error(`unsupported recurrence: ${it.recurrence}`);
    }
    if (it.amount !== null && (it.amount < 0 || it.amount > 1e9)) {
      throw new Error("bad amount");
    }
    if (it.snooze_minutes !== null && (it.snooze_minutes < 1 || it.snooze_minutes > 60 * 24 * 30)) {
      throw new Error("bad snooze");
    }
    return {
      ...it,
      title,
      notes: it.notes?.slice(0, 2000) ?? null,
      target_id: it.target_id && knownIds.has(it.target_id) ? it.target_id : null,
    };
  });
  return {
    ...r,
    items,
    spoken_reply: r.spoken_reply.slice(0, 300),
    clarification_needed: r.clarification_needed?.slice(0, 200) ?? null,
  };
}
