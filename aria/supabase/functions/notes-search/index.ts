// POST /functions/v1/notes-search   { query: string, limit?: number }
// Semantic search over the caller's notes ("what's the wifi password?").
// Embeds with Supabase's built-in gte-small (384 dims, runs inside the
// edge runtime — no third-party AI). Notes without an embedding are
// embedded lazily, at most 30 per call.
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { z } from "npm:zod@4.6.7";
import { corsHeaders, json } from "../_shared/cors.ts";

// deno-lint-ignore no-explicit-any
const model = new (globalThis as any).Supabase.ai.Session("gte-small");

async function embed(text: string): Promise<number[]> {
  return await model.run(text, { mean_pool: true, normalize: true });
}

const Body = z.object({
  query: z.string().min(1).max(300),
  limit: z.number().int().min(1).max(10).default(5),
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const user = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: auth } = await user.auth.getUser();
  if (!auth.user) return json({ error: "unauthorized" }, 401);

  const parsed = Body.safeParse(await req.json().catch(() => null));
  if (!parsed.success) return json({ error: "bad_request" }, 400);

  // 1. Embed notes the caller can read that have no embedding yet. Reads
  //    go through RLS (user client); the write uses the service role only
  //    for those same ids, because shared notes may belong to others.
  const { data: missing } = await user
    .from("notes")
    .select("id, text")
    .is("embedding", null)
    .is("deleted_at", null)
    .limit(30);
  if (missing?.length) {
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    for (const n of missing) {
      const vector = await embed(n.text);
      await admin.from("notes").update({ embedding: JSON.stringify(vector) }).eq("id", n.id);
    }
  }

  // 2. Nearest notes (match_notes is SECURITY INVOKER → RLS applies).
  const queryVector = await embed(parsed.data.query);
  const { data, error } = await user.rpc("match_notes", {
    query_embedding: JSON.stringify(queryVector),
    match_count: parsed.data.limit,
  });
  if (error) return json({ error: "search_failed" }, 500);
  return json({ results: data ?? [] });
});
