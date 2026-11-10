// POST /functions/v1/parse
// Body: { text, now, timezone, reminders?: [{id,title}] }
// Returns the ParseResult JSON, or an error the app treats as "use the
// on-device parser" (503 / 422 / 429 / 504).
import Anthropic from "npm:@anthropic-ai/sdk@1.6.0";
import { zodOutputFormat } from "npm:@anthropic-ai/sdk@1.6.0/helpers/zod";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { z } from "npm:zod@4.6.7";
import { corsHeaders, json } from "../_shared/cors.ts";
import { SYSTEM_PROMPT } from "./prompt.ts";
import { ParseResult, sanitize } from "./schema.ts";

// Spec §11: small/fast model for parsing; override with PARSER_MODEL.
const MODEL = Deno.env.get("PARSER_MODEL") ?? "claude-haiku-5-5";
const API_KEY = Deno.env.get("ANTHROPIC_API_KEY");

// The app gives up at 4 s and falls back on-device, so never wait longer.
const anthropic = API_KEY
  ? new Anthropic({ apiKey: API_KEY, timeout: 3_500, maxRetries: 0 })
  : null;

const Body = z.object({
  text: z.string().min(1).max(1000),
  now: z.string(),
  timezone: z.string().max(64),
  reminders: z
    .array(z.object({ id: z.string().max(64), title: z.string().max(200) }))
    .max(50)
    .default([]),
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // Authenticated users only (the gateway verifies the JWT; we need the id).
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return json({ error: "unauthorized" }, 401);

  const parsed = Body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return json({ error: "bad_request" }, 400);
  const body = parsed.data;

  if (!anthropic) return json({ error: "parser_unavailable" }, 503);

  // Per-user rate limit (DB function, counts the last minute).
  const { data: allowed, error: rlErr } = await supabase.rpc("take_parse_token");
  if (rlErr || allowed !== true) return json({ error: "rate_limited" }, 429);

  const context = [
    `Current local time: ${body.now}`,
    `Timezone: ${body.timezone}`,
    body.reminders.length
      ? `Existing reminders:\n${body.reminders.map((r) => `- ${r.id}: ${r.title}`).join("\n")}`
      : "Existing reminders: none",
  ].join("\n");

  try {
    const response = await anthropic.messages.parse({
      model: MODEL,
      max_tokens: 2048,
      system: SYSTEM_PROMPT,
      // Volatile content (time, reminders, utterance) goes last.
      messages: [
        { role: "user", content: `${context}\n\nUser said: """${body.text}"""` },
      ],
      output_config: { effort: "low", format: zodOutputFormat(ParseResult) },
    });

    if (response.stop_reason === "refusal") return json({ error: "refused" }, 422);
    if (response.stop_reason === "max_tokens" || !response.parsed_output) {
      return json({ error: "invalid_output" }, 422);
    }
    const clean = sanitize(
      response.parsed_output,
      new Set(body.reminders.map((r) => r.id)),
    );
    return json({ ...clean, source: "llm", model: MODEL });
  } catch (e) {
    if (e instanceof Anthropic.APIConnectionTimeoutError) {
      return json({ error: "timeout" }, 504);
    }
    if (e instanceof Anthropic.RateLimitError) {
      return json({ error: "upstream_rate_limited" }, 503);
    }
    if (e instanceof Anthropic.APIError) {
      console.error("anthropic error", e.status, e.message);
      return json({ error: "upstream_error" }, 503);
    }
    // sanitize() rejections and anything unexpected.
    console.error("parse failed", e);
    return json({ error: "invalid_output" }, 422);
  }
});
