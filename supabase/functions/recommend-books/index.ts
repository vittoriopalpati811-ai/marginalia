// recommend-books — Supabase Edge Function
// ─────────────────────────────────────────────────────────────────────────────
//
// Receives the user's last 20 books (title, author, sample highlights) from
// the Flutter app, fetches plot descriptions from Open Library, then asks
// Llama 3.3 70B (via Groq) to recommend 5 books the user has NOT yet read.
//
// Request body (POST, JSON):
//   {
//     books: [{ title, author, highlights: string[] }],  ← up to 20 books
//     existingTitles: string[],                           ← for exclusion
//     context?: { weather?, weatherCity?, weatherTemp?,
//                 stepsToday?, lastWorkout?, cyclePhase? }
//   }
//
// Response (always 200, JSON):
//   { recommendations: [{ title, author, year, reason }] }
//   (empty array on any error — Flutter never sees a non-2xx)
//
// Required secret:
//   GROQ_API_KEY  — free at https://console.groq.com
//                   Free tier: 30 RPM, 14 400 req/day
//
// Deploy:
//   supabase functions deploy recommend-books
// Set key:
//   supabase secrets set GROQ_API_KEY=gsk_…

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ─── Types ────────────────────────────────────────────────────────────────────

interface InputBook {
  title: string;
  author: string;
  highlights: string[];
}

interface Recommendation {
  title: string;
  author: string;
  year: string;
  reason: string;
}

// ─── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }

  let body: {
    books?: InputBook[];
    existingTitles?: string[];
    context?: Record<string, unknown>;
    userName?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const books: InputBook[] = (body.books ?? []).slice(0, 20);
  const existingTitles: string[] = (body.existingTitles ?? []).map((t) =>
    t.toLowerCase().trim()
  );
  const userContext: Record<string, unknown> = body.context ?? {};
  const userName: string = (body.userName ?? "").trim();

  if (books.length === 0) {
    return json({ recommendations: [], reason: "no_books" });
  }

  // ── 1. Fetch Open Library plots in parallel ──────────────────────────────

  const withPlots = await Promise.all(
    books.map(async (book) => {
      const plot = await fetchOpenLibraryPlot(book.title, book.author);
      return { ...book, plot };
    })
  );

  // ── 2. Build prompt ──────────────────────────────────────────────────────

  const prompt = buildPrompt(withPlots, existingTitles, userContext, userName);

  // ── 3. Call Groq API ─────────────────────────────────────────────────────

  const groqKey = Deno.env.get("GROQ_API_KEY");
  if (!groqKey) {
    console.error("GROQ_API_KEY not configured");
    return json({ recommendations: [], reason: "ai_unconfigured" });
  }

  let recommendations: Recommendation[];
  try {
    recommendations = await callGroq(groqKey, prompt);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("Groq API error:", msg);
    // Surface rate-limit explicitly so the client can show "torna domani"
    // instead of a generic empty state. Match on the HTTP code text the
    // throw site interpolates: `Groq API 429: …`.
    if (/\b429\b/.test(msg) || /rate.?limit/i.test(msg)) {
      return json({ recommendations: [], reason: "rate_limit" });
    }
    return json({ recommendations: [], reason: "ai_error" });
  }

  if (recommendations.length === 0) {
    return json({ recommendations: [], reason: "ai_empty" });
  }

  return json({ recommendations, reason: "ok" });
});

// ─── Open Library ─────────────────────────────────────────────────────────────

async function fetchOpenLibraryPlot(
  title: string,
  author: string
): Promise<string> {
  try {
    const q = encodeURIComponent(`${title} ${author}`);
    const searchRes = await fetch(
      `https://openlibrary.org/search.json?q=${q}&limit=1&fields=key,description`,
      { signal: AbortSignal.timeout(8_000) }
    );
    if (!searchRes.ok) return "";

    const data = await searchRes.json();
    const doc = data?.docs?.[0];
    if (!doc) return "";

    if (doc.description) return extractText(doc.description).slice(0, 600);

    const key = doc.key as string | undefined;
    if (!key) return "";

    const worksRes = await fetch(`https://openlibrary.org${key}.json`, {
      signal: AbortSignal.timeout(6_000),
    });
    if (!worksRes.ok) return "";

    const works = await worksRes.json();
    return extractText(works.description ?? "").slice(0, 600);
  } catch {
    return "";
  }
}

function extractText(raw: unknown): string {
  if (typeof raw === "string") return raw;
  if (raw && typeof raw === "object" && "value" in (raw as object)) {
    return (raw as { value: string }).value ?? "";
  }
  return "";
}

// ─── Prompt builder ───────────────────────────────────────────────────────────

interface BookWithPlot extends InputBook {
  plot: string;
}

function buildPrompt(
  books: BookWithPlot[],
  existingTitles: string[],
  ctx: Record<string, unknown>,
  userName: string
): string {
  const bookList = books
    .map((b, i) => {
      const lines: string[] = [`${i + 1}. "${b.title}" di ${b.author}`];
      if (b.plot) lines.push(`   Trama: ${b.plot}`);
      if (b.highlights.length > 0) {
        lines.push(
          `   Highlight: ${b.highlights.slice(0, 3).map((h) => `"${h.slice(0, 150)}"`).join(" | ")}`
        );
      }
      return lines.join("\n");
    })
    .join("\n\n");

  const exclusionNote =
    existingTitles.length > 0
      ? `\n\nNon suggerire MAI questi titoli (${existingTitles.length} libri già in libreria): ${existingTitles.slice(0, 40).join(", ")}${existingTitles.length > 40 ? ", e altri…" : ""}.`
      : "";

  const contextParts: string[] = [];
  if (ctx.weather && ctx.weatherCity) {
    const weatherMap: Record<string, string> = {
      sunny: "sole", rain: "pioggia", cloudy: "nuvolo",
      snow: "neve", clear: "sereno",
    };
    const cond = weatherMap[ctx.weather as string] ?? String(ctx.weather);
    contextParts.push(`Oggi c'è ${cond} a ${ctx.weatherCity}, ${ctx.weatherTemp}°C`);
  }
  if (ctx.stepsToday) {
    contextParts.push(`l'utente ha fatto ${ctx.stepsToday} passi oggi`);
  }
  if (ctx.lastWorkout) {
    contextParts.push(`ha fatto ${ctx.lastWorkout} di recente`);
  }
  if (ctx.cyclePhase) {
    const phaseMap: Record<string, string> = {
      menstruation: "mestruazioni", follicular: "fase follicolare",
      ovulation: "ovulazione", luteal: "fase luteale",
    };
    const phase = phaseMap[ctx.cyclePhase as string] ?? String(ctx.cyclePhase);
    contextParts.push(`si trova in fase di ${phase} del ciclo`);
  }

  const contextNote = contextParts.length > 0
    ? `\n\nCONTESTO UTENTE: ${contextParts.join("; ")}. Puoi usarlo per sfumare i consigli, ma non è obbligatorio.`
    : "";

  // How to address the user in the reason field
  const addressee = userName ? userName : "lettore";
  const reasonInstruction = userName
    ? `Per ogni libro scrivi una "reason" in italiano (2-3 frasi) rivolgendoti direttamente all'utente per nome, in seconda persona. Inizia SEMPRE con "${userName}, apprezzerai" oppure "${userName}, adorerai" oppure "${userName}, ti conquisterà" — mai con "Il lettore" o frasi impersonali. Cita connessioni concrete con i suoi highlight.`
    : `Per ogni libro scrivi una "reason" in italiano (2-3 frasi) in seconda persona diretta ("apprezzerai", "adorerai", "ti conquisterà"). Cita connessioni concrete con i suoi highlight.`;

  return `Sei un bibliotecario italiano esperto e appassionato lettore. Analizza i libri che questo utente ha letto e i suoi highlight personali, poi suggerisci 5 libri che potrebbe amare.

LIBRI LETTI:
${bookList}${exclusionNote}${contextNote}

ISTRUZIONI:
- Suggerisci esattamente 5 libri che l'utente NON ha ancora letto.
- Scegli libri che risuonano con i temi, le idee e lo stile degli highlight.
- Varia tra classici e contemporanei, italiani e stranieri.
- ${reasonInstruction}
- Rispondi SOLO con JSON valido nel formato sotto, senza markdown e senza testo extra. Usa esclusivamente virgolette dritte ("), mai virgolette tipografiche.

{
  "recommendations": [
    {
      "title": "Titolo",
      "author": "Autore",
      "year": "anno",
      "reason": "Spiegazione personalizzata."
    }
  ]
}`;
}

// ─── Groq API (llama-3.1-8b-instant — free tier) ─────────────────────────────
//
// Was llama-3.3-70b-versatile, which has a 100 K tokens-per-day cap on free.
// One personalised recommendation request runs ~1.4 K tokens, so the 70B
// model ran out of quota after ~70 calls/day — a single moderately active
// user could exhaust the whole org's daily budget. Production logs showed
// the 429 was being hit every afternoon ("Used 98935 / Limit 100000").
//
// 8B-instant has a much higher daily allowance (~500 K TPD as of 2026) and
// is more than enough for short book recommendations — we're not asking
// for chain-of-thought reasoning, just "pick 5 titles + write 1 sentence".
// Quality regression is minimal; throughput improves ~7×.
// Dashboard: https://console.groq.com

async function callGroq(
  apiKey: string,
  prompt: string
): Promise<Recommendation[]> {
  const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "llama-3.1-8b-instant",
      messages: [{ role: "user", content: prompt }],
      max_tokens: 1024,
      temperature: 0.7,
      // Force the model to emit a syntactically valid JSON object. Without
      // this the 8B model occasionally produces malformed JSON (smart-quote
      // closure, trailing comma in a long string). Logs showed:
      //   "Expected ',' or '}' after property value in JSON at position 221"
      // json_object mode guarantees parseable JSON; we then unwrap the
      // top-level "recommendations" key.
      response_format: { type: "json_object" },
    }),
    signal: AbortSignal.timeout(30_000),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Groq API ${res.status}: ${errText}`);
  }

  const data = await res.json();
  const rawText: string = data?.choices?.[0]?.message?.content ?? "";

  // json_object mode returns parseable JSON directly. extractJson is kept
  // as a safety net in case the model still wraps the answer in markdown.
  const extracted = extractJson(rawText);
  const parsed = JSON.parse(extracted);

  // Accept either {recommendations: [...]} (preferred) or a bare array
  // (legacy / safety).
  const list: unknown = Array.isArray(parsed)
    ? parsed
    : (parsed as { recommendations?: unknown[] }).recommendations;

  if (!Array.isArray(list)) {
    throw new Error("Response missing recommendations array");
  }

  return (list as Recommendation[]).slice(0, 5).map((r) => ({
    title:  String(r.title  ?? ""),
    author: String(r.author ?? ""),
    year:   String(r.year   ?? ""),
    reason: String(r.reason ?? ""),
  }));
}

function extractJson(text: string): string {
  const fenceMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenceMatch) return fenceMatch[1].trim();

  // Prefer an object wrapper (`{...}`); fall back to a bare array (`[...]`)
  // if the model emitted one despite the prompt.
  const objStart = text.indexOf("{");
  const objEnd   = text.lastIndexOf("}");
  if (objStart !== -1 && objEnd > objStart) {
    return text.slice(objStart, objEnd + 1);
  }
  const arrStart = text.indexOf("[");
  const arrEnd   = text.lastIndexOf("]");
  if (arrStart !== -1 && arrEnd > arrStart) {
    return text.slice(arrStart, arrEnd + 1);
  }
  return text.trim();
}

// ─── Utility ──────────────────────────────────────────────────────────────────

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
