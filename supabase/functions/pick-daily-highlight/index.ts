// pick-daily-highlight — Supabase Edge Function
// ─────────────────────────────────────────────────────────────────────────────
//
// Receives a sample of the user's highlights and current context (time, weather,
// steps, cycle phase), then asks Llama 3.3 70B (via Groq) to pick the single
// highlight most resonant for this specific moment.
//
// Returns the index of the selected highlight — Flutter maps it back to the
// actual Highlight object and displays the original text unchanged.
//
// Request body (POST, JSON):
//   {
//     highlights: [{ content: string, bookTitle: string }],  ← up to 40
//     context: {
//       hour:         number,    ← 0–23
//       weather?:     string,    ← 'sunny' | 'rain' | 'cloudy' | 'snow' | 'clear'
//       weatherCity?: string,
//       weatherTemp?: number,
//       stepsToday?:  number,
//       lastWorkout?: string,
//       cyclePhase?:  string,
//     }
//   }
//
// Response (always 200, JSON):
//   { selectedIndex: number }   ← index in the received highlights array
//
// Required secret: GROQ_API_KEY  (same key used by recommend-books)
// Deploy: supabase functions deploy pick-daily-highlight

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

  // ── Auth: require a valid Supabase user JWT ────────────────────────────────
  // Previously unauthenticated: anyone could pump unbounded user text into the
  // Groq LLM prompt. Require a verified caller before doing any model work.
  const user = await requireUser(req);
  if (!user) {
    return json({ error: "unauthorized" }, 401);
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

  // Defensive clamping: cap the array AND each text field to <=400 chars before
  // building the prompt. Bounds prompt size, token cost, and injection length.
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
  // ── Context description ──────────────────────────────────────────────────
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
  if (ctx.stepsToday) {
    contextParts.push(`Passi oggi: ${ctx.stepsToday}`);
  }
  if (ctx.lastWorkout) {
    contextParts.push(`Attività fisica recente: ${ctx.lastWorkout}`);
  }
  if (ctx.cyclePhase) {
    const phaseMap: Record<string, string> = {
      menstruation: "mestruazioni", follicular: "fase follicolare",
      ovulation: "ovulazione", luteal: "fase luteale",
    };
    const phase = phaseMap[ctx.cyclePhase as string] ?? String(ctx.cyclePhase);
    contextParts.push(`Fase del ciclo: ${phase}`);
  }
  if (Array.isArray(ctx.calendarEvents) &&
      (ctx.calendarEvents as string[]).length > 0) {
    contextParts.push(
      `Impegni di oggi: ${(ctx.calendarEvents as string[]).join(", ")}`,
    );
  }

  // ── Highlight list ───────────────────────────────────────────────────────
  const list = highlights
    .map((h, i) => `[${i}] "${h.content}" — ${h.bookTitle || "libro"}`)
    .join("\n");

  return `Sei un bibliotecario italiano con un senso raffinato del momento giusto per ogni lettura.

CONTESTO ATTUALE:
${contextParts.join("\n")}

HAI A DISPOSIZIONE ${highlights.length} HIGHLIGHT:
${list}

Scegli l'highlight più adatto a questo preciso momento, considerando l'ora del giorno, il meteo, l'umore che trasmette e il contesto fisico dell'utente. Pensa a quale citazione risuonerebbe di più adesso — se è mattina prendi qualcosa di energico o meditativo, se piove qualcosa di malinconico o introspettivo, se è sera qualcosa di caldo.

Rispondi SOLO con il numero intero dell'indice scelto (es: 7). Nessun altro testo, nessuna spiegazione.`;
}

// ─── Groq API ─────────────────────────────────────────────────────────────────

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
      model: "llama-3.3-70b-versatile",
      messages: [{ role: "user", content: prompt }],
      max_tokens: 8,       // We only need a single integer
      temperature: 0.4,    // Lower temp for more consistent selection
    }),
    signal: AbortSignal.timeout(20_000),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Groq ${res.status}: ${errText}`);
  }

  const data = await res.json();
  const rawText: string = (data?.choices?.[0]?.message?.content ?? "").trim();

  // Parse the integer — Groq might return "7" or "7\n" or "index: 7"
  const match = rawText.match(/\d+/);
  if (!match) throw new Error(`Unexpected Groq response: "${rawText}"`);

  const idx = parseInt(match[0], 10);
  if (isNaN(idx) || idx < 0 || idx >= maxIndex) return 0;
  return idx;
}

// ─── Auth ───────────────────────────────────────────────────────────────────
//
// Verifies the incoming `Authorization: Bearer <jwt>` against Supabase Auth
// using the anon key + the caller's JWT. Returns the authenticated user, or
// null if the token is missing/invalid (caller should answer 401).

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

// ─── Utility ──────────────────────────────────────────────────────────────────

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
