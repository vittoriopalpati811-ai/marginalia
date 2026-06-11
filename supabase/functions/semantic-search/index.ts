// ─── semantic-search Edge Function ───────────────────────────────────────────
//
// Semantic (meaning-based) search over a user's OWN highlights, powered entirely
// by Supabase's built-in `gte-small` embedding model (384-dim) — no external API,
// no key, free. Two modes:
//
//   { "mode": "index", "limit": 100 }
//     Embeds up to `limit` of the caller's highlights that don't yet have an
//     embedding, and reports how many remain. Called after import + periodically
//     so the search corpus stays fresh.
//
//   { "mode": "search", "query": "...", "match_count": 20 }
//     Embeds the query and returns the caller's nearest highlights by cosine
//     similarity (via the match_highlights RPC + pgvector HNSW index), each with
//     its book title/author.
//
// The caller is always authenticated (verify_jwt + requireUser). The recipient
// filter (user_id) is the VERIFIED caller id, passed to a service-role-only RPC,
// so a client can never read another user's highlights.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

async function requireUser(req: Request): Promise<{ id: string } | null> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return null;
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: `Bearer ${jwt}` } } },
  );
  const { data, error } = await supabase.auth.getUser(jwt);
  if (error || !data?.user) return null;
  return { id: data.user.id };
}

// Per-user rate limit via check_rate_limit (RAISES on exceed). true = limited;
// fails OPEN on any other error so a glitch never blocks a real user.
async function isRateLimited(
  req: Request,
  action: string,
  max: number,
  windowSeconds: number,
): Promise<boolean> {
  try {
    const jwt = (req.headers.get("Authorization") ?? "")
      .replace(/^Bearer\s+/i, "")
      .trim();
    if (!jwt) return false;
    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );
    const { error } = await sb.rpc("check_rate_limit", {
      p_action: action,
      p_max: max,
      p_window_seconds: windowSeconds,
    });
    return !!error;
  } catch (_) {
    return false;
  }
}

// The built-in embedding model. Lives at module scope so it is initialised once
// per isolate, not per request.
// deno-lint-ignore no-explicit-any
const model = new (globalThis as any).Supabase.ai.Session("gte-small");

async function embed(text: string): Promise<number[]> {
  const out = await model.run(text, { mean_pool: true, normalize: true });
  return out as number[];
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const caller = await requireUser(req);
  if (!caller) return jsonResponse({ error: "unauthorized" }, 401);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return jsonResponse({ error: "invalid JSON body" }, 400); }
  if (body === null || typeof body !== "object") {
    return jsonResponse({ error: "body must be a JSON object" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const mode = body.mode;

  // Per-user throttle on the Supabase.ai embedding compute (index loops up to
  // 200 embeds/call; search runs one). Graceful empty shapes the client expects.
  if (mode === "index" && (await isRateLimited(req, "semantic_index", 10, 3600))) {
    return jsonResponse({ embedded: 0, remaining: 0, rate_limited: true });
  }
  if (mode === "search" && (await isRateLimited(req, "semantic_search", 60, 3600))) {
    return jsonResponse({ results: [], rate_limited: true });
  }

  try {
    // ── INDEX: embed the caller's un-embedded highlights ────────────────────
    if (mode === "index") {
      const limit = Math.min(Math.max(Number(body.limit ?? 100), 1), 200);
      const { data: rows, error } = await supabase
        .from("highlights")
        .select("id, content")
        .eq("user_id", caller.id)
        .is("embedding", null)
        .limit(limit);
      if (error) {
        console.error("semantic-search index select:", error);
        return jsonResponse({ error: "internal_error" }, 500);
      }

      let embedded = 0;
      for (const r of rows ?? []) {
        const text = String((r as { content?: unknown }).content ?? "").slice(0, 1200);
        if (!text.trim()) continue;
        try {
          const vec = await embed(text);
          await supabase.from("highlights").update({ embedding: vec }).eq("id", (r as { id: string }).id);
          embedded++;
        } catch (_) { /* skip a single bad row, keep going */ }
      }

      const { count } = await supabase
        .from("highlights")
        .select("id", { count: "exact", head: true })
        .eq("user_id", caller.id)
        .is("embedding", null);

      return jsonResponse({ embedded, remaining: count ?? 0 });
    }

    // ── SEARCH: embed the query, return nearest highlights ──────────────────
    if (mode === "search") {
      const query = String(body.query ?? "").slice(0, 500).trim();
      if (!query) return jsonResponse({ results: [] });
      const matchCount = Math.min(Math.max(Number(body.match_count ?? 20), 1), 50);

      const vec = await embed(query);
      const { data: matches, error } = await supabase.rpc("match_highlights", {
        p_user_id: caller.id,
        p_query_embedding: vec,
        p_match_count: matchCount,
      });
      if (error) {
        console.error("semantic-search match:", error);
        return jsonResponse({ results: [] }, 200);
      }

      const list = (matches ?? []) as Array<{ id: string; content: string; book_id: string | null; location: string | null; similarity: number }>;
      const bookIds = [...new Set(list.map((m) => m.book_id).filter(Boolean))] as string[];
      const titles: Record<string, { title: string | null; author: string | null }> = {};
      if (bookIds.length) {
        const { data: books } = await supabase.from("books").select("id, title, author").in("id", bookIds);
        for (const b of (books ?? []) as Array<{ id: string; title: string | null; author: string | null }>) {
          titles[b.id] = { title: b.title, author: b.author };
        }
      }

      const results = list.map((m) => ({
        id: m.id,
        content: m.content,
        location: m.location,
        similarity: m.similarity,
        book_title: m.book_id ? (titles[m.book_id]?.title ?? null) : null,
        book_author: m.book_id ? (titles[m.book_id]?.author ?? null) : null,
      }));
      return jsonResponse({ results });
    }

    return jsonResponse({ error: "unknown mode (use 'index' or 'search')" }, 400);
  } catch (e) {
    console.error("semantic-search:", e);
    return jsonResponse({ error: "internal_error" }, 500);
  }
});
