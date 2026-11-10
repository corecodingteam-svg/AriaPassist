import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { ParseResult, sanitize, validRrule } from "./schema.ts";

const item = {
  title: "Pay electricity bill",
  category: "bills" as const,
  datetime: "2026-12-05T10:00:00+05:30",
  all_day: false,
  recurrence: "FREQ=MONTHLY;BYMONTHDAY=5",
  priority: "normal" as const,
  amount: 1840,
  contact: null,
  notes: null,
  target_id: null,
  snooze_minutes: null,
  list_name: null,
  place: null,
};
const base: ParseResult = {
  intent: "create_reminder",
  items: [item],
  query: "none",
  clarification_needed: null,
  spoken_reply: "Done!",
};

Deno.test("spec example validates against the schema", () => {
  assert(ParseResult.safeParse(base).success);
});

Deno.test("rrule subset matches the app", () => {
  for (const ok of ["FREQ=DAILY", "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR", "FREQ=MONTHLY;BYMONTHDAY=-1", "FREQ=DAILY;COUNT=3", "RRULE:FREQ=YEARLY"]) {
    assert(validRrule(ok), ok);
  }
  for (const bad of ["FREQ=HOURLY", "FREQ=MONTHLY;BYDAY=2MO", "BYDAY=MO", "FREQ=DAILY;BYSETPOS=1", "FREQ=DAILY;COUNT=2;UNTIL=20270101"]) {
    assert(!validRrule(bad), bad);
  }
});

Deno.test("sanitize rejects bad datetimes and recurrences", () => {
  assertThrows(() => sanitize({ ...base, items: [{ ...item, datetime: "tomorrow" }] }, new Set()));
  assertThrows(() => sanitize({ ...base, items: [{ ...item, recurrence: "FREQ=HOURLY" }] }, new Set()));
  assertThrows(() => sanitize({ ...base, items: [{ ...item, title: "  " }] }, new Set()));
});

Deno.test("sanitize drops target ids the client didn't send", () => {
  const r = sanitize(
    { ...base, intent: "complete", items: [{ ...item, target_id: "not-mine" }] },
    new Set(["mine"]),
  );
  assertEquals(r.items[0].target_id, null);
  const ok = sanitize(
    { ...base, intent: "complete", items: [{ ...item, target_id: "mine" }] },
    new Set(["mine"]),
  );
  assertEquals(ok.items[0].target_id, "mine");
});
