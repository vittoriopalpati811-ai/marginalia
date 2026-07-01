// pick-daily-highlight — Supabase Edge Function
//
// Picks the single highlight most resonant for this moment via Groq.
// Raw health signals are NEVER sent — only an abstract on-device tone.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface HighlightInput {
  content: string;
  bookTitle: string;
}

// ─── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }

  // Auth: require a valid Supabase user JWT before any model work.
  const user = await requireUser(req);
  if (!user) {
    return json({ error: "unauthorized" }, 401);
  }

  // Per-user throttle on the shared Groq LLM (see recommend-books). Graceful:
  // selectedIndex 0 just shows the first highlight, which the client expects.
  if (await isRateLimited(req, "daily_highlight", 20, 86400)) {
    return json({ selectedIndex: 0, rate_limited: true });
  }

  let body: {
    highlights?: HighlightInput[];
    context?: Record<string, unknown>;
  };
  try {
    body = await req.json();
  } catch {
    return json({ selectedIndex: 0 });
  }

  // Defensive clamping: cap the array AND each text field before building.
  const MAX_FIELD = 400;
  const clampField = (v: unknown): string => String(v ?? "").slice(0, MAX_FIELD);
  const highlights: HighlightInput[] = (Array.isArray(body.highlights) ? body.highlights : [])
    .slice(0, 40)
    .map((h) => ({
      content: clampField(h?.content),
      bookTitle: clampField(h?.bookTitle),
    }));
  const ctx: Record<string, unknown> = body.context ?? {};

  if (highlights.length === 0) return json({ selectedIndex: 0 });
  if (highlights.length === 1) return json({ selectedIndex: 0 });

  const groqKey = Deno.env.get("GROQ_API_KEY");
  if (!groqKey) {
    console.error("GROQ_API_KEY not configured");
    return json({ selectedIndex: 0 });
  }

  const prompt = buildPrompt(highlights, ctx);

  try {
    const selectedIndex = await callGroq(groqKey, prompt, highlights.length);
    return json({ selectedIndex });
  } catch (e) {
    console.error("Groq error:", e);
    return json({ selectedIndex: 0 });
  }
});

// ─── Prompt ───────────────────────────────────────────────────────────────────

function buildPrompt(
  highlights: HighlightInput[],
  ctx: Record<string, unknown>
): string {
  const hour = (ctx.hour as number) ?? new Date().getHours();
  const timeLabel =
    hour < 6  ? "notte fonda" :
    hour < 12 ? "mattina" :
    hour < 14 ? "pausa pranzo" :
    hour < 18 ? "pomeriggio" :
    hour < 22 ? "sera" : "tarda serata";

  const contextParts: string[] = [`Ora: ${timeLabel} (${hour}:00)`];

  if (ctx.weather && ctx.weatherCity) {
    const weatherMap: Record<string, string> = {
      sunny: "sole", rain: "pioggia", cloudy: "cielo coperto",
      snow: "neve", clear: "cielo sereno",
    };
    const cond = weatherMap[ctx.weather as string] ?? String(ctx.weather);
    contextParts.push(`Meteo: ${cond} a ${ctx.weatherCity}, ${ctx.weatherTemp}°C`);
  }
  // Privacy by design: only an abstract non-health tone reaches the LLM.
  if (ctx.tone) {
    const toneMap: Record<string, string> = {
      gentle: "gentile, consolatorio, intimo",
      uplifting: "energico, propositivo, luminoso",
      reflective: "riflessivo, calmo, introspettivo",
    };
    const tone = toneMap[ctx.tone as string];
    if (tone) contextParts.push(`Tono preferito per oggi: ${tone}`);
  }
  if (Array.isArray(ctx.calendarEvents)) {
    // Clamp the array AND each title before splicing into the prompt.
    const events = (ctx.calendarEvents as unknown[])
      .slice(0, 8)
      .map((e) => String(e ?? "").slice(0, 80))
      .filter((e) => e.length > 0);
    if (events.length > 0) {
      contextParts.push(`Impegni di oggi: ${events.join(", ")}`);
    }
  }

  const list = highlights
    .map((h, i) => `[${i}] "${h.content}" - ${h.bookTitle || "libro"}`)
    .join("\n");

  return `Sei un bibliotecario italiano con un senso raffinato del momento giusto per ogni lettura.

CONTESTO ATTUALE:
${contextParts.join("\n")}

HAI A DISPOSIZIONE ${highlights.length} HIGHLIGHT:
${list}

Scegli l'highlight piu adatto a questo preciso momento, considerando l'ora del giorno, il meteo e l'umore che trasmette. Pensa a quale citazione risuonerebbe di piu adesso.

Rispondi SOLO con il numero intero dell'indice scelto (es: 7). Nessun altro testo, nessuna spiegazione.`;
}

// ─── Groq API ───────────────────────────────────────────────────────────────────

async function callGroq(
  apiKey: string,
  prompt: string,
  maxIndex: number
): Promise<number> {
  const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      // gpt-oss-120b: Groq's recommended replacement for the deprecated
      // llama-3.3-70b-versatile (decommissioned 2026-08-16). It is a REASONING
      // model — the chain-of-thought goes to a separate `reasoning` field so
      // `content` still holds just the index, BUT that reasoning consumes
      // completion tokens: the old `max_tokens: 8` would truncate before any
      // content is emitted. reasoning_effort "low" keeps it fast/cheap; the
      // larger budget leaves room for the (tiny) final answer.
      model: "openai/gpt-oss-120b",
      messages: [{ role: "user", content: prompt }],
      max_completion_tokens: 2048,
      reasoning_effort: "low",
      temperature: 0.4,
    }),
    signal: AbortSignal.timeout(20_000),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Groq ${res.status}: ${errText}`);
  }

  const data = await res.json();
  const rawText: string = (data?.choices?.[0]?.message?.content ?? "").trim();

  const match = rawText.match(/\d+/);
  if (!match) throw new Error(`Unexpected Groq response: "${rawText}"`);

  const idx = parseInt(match[0], 10);
  if (isNaN(idx) || idx < 0 || idx >= maxIndex) return 0;
  return idx;
}

// ─── Auth ───────────────────────────────────────────────────────────────────

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

// Per-user rate limit via check_rate_limit (RAISES when the caller exceeds the
// budget). true = limited; fails OPEN on any other error.
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
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );
    const { error } = await supabase.rpc("check_rate_limit", {
      p_action: action,
      p_max: max,
      p_window_seconds: windowSeconds,
    });
    return !!error;
  } catch (_) {
    return false;
  }
}

// ─── Utility ──────────────────────────────────────────────────────────────────

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
