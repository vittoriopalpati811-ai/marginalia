// recommend-books — Supabase Edge Function
// ─────────────────────────────────────────────────────────────────────────────
//
// Receives the user's last 20 books (title, author, sample highlights) from
// the Flutter app, fetches plot descriptions from Open Library, then asks
// Claude to recommend 3–5 books the user has NOT yet read.
//
// Request body (POST, JSON):
//   {
//     books: [                      ← up to 20 most-recent books
//       {
//         title:      string,
//         author:     string,
//         highlights: string[],     ← up to 4 highlights for context
//       },
//       …
//     ],
//     existingTitles: string[],     ← full list of library titles (for exclusion)
//   }
//
// Response (200, JSON):
//   {
//     recommendations: [
//       { title: string, author: string, year: string, reason: string },
//       …
//     ]
//   }
//
// Required secrets:
//   GEMINI_API_KEY    — Google AI Studio key (free: 1 500 req/day, 15 RPM)
//                       https://aistudio.google.com/apikey
//
// Auto-injected by Supabase:
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
//
// Deploy:
//   supabase functions deploy recommend-books
// Set key:
//   supabase secrets set GEMINI_API_KEY=AIza…

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

  if (books.length === 0) {
    return json({ recommendations: [] });
  }

  // ── 1. Fetch Open Library plots in parallel ──────────────────────────────

  const withPlots = await Promise.all(
    books.map(async (book) => {
      const plot = await fetchOpenLibraryPlot(book.title, book.author);
      return { ...book, plot };
    })
  );

  // ── 2. Build prompt ──────────────────────────────────────────────────────

  const prompt = buildPrompt(withPlots, existingTitles, userContext);

  // ── 3. Call Gemini API ───────────────────────────────────────────────────

  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  if (!geminiKey) {
    return json({ error: "GEMINI_API_KEY not configured" }, 500);
  }

  let geminiResponse: Recommendation[];
  try {
    geminiResponse = await callGemini(geminiKey, prompt);
  } catch (e) {
    console.error("Gemini API error:", e);
    // Return empty array (200) so Flutter never sees a non-2xx → no FunctionException
    return json({ recommendations: [] });
  }

  return json({ recommendations: geminiResponse });
});

// ─── Open Library ─────────────────────────────────────────────────────────────

async function fetchOpenLibraryPlot(
  title: string,
  author: string
): Promise<string> {
  try {
    const q = encodeURIComponent(`${title} ${author}`);
    const searchUrl =
      `https://openlibrary.org/search.json?q=${q}&limit=1&fields=key,description`;
    const searchRes = await fetch(searchUrl, {
      signal: AbortSignal.timeout(8_000),
    });
    if (!searchRes.ok) return "";

    const data = await searchRes.json();
    const docs = data?.docs ?? [];
    if (docs.length === 0) return "";

    const doc = docs[0];

    // Some search results include description directly
    if (doc.description) {
      return extractText(doc.description).slice(0, 600);
    }

    // Otherwise fetch the Works record
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
  ctx: Record<string, unknown>
): string {
  const bookList = books
    .map((b, i) => {
      const lines: string[] = [`${i + 1}. "${b.title}" di ${b.author}`];
      if (b.plot) lines.push(`   Trama: ${b.plot}`);
      if (b.highlights.length > 0) {
        lines.push(
          `   Highlight dell'utente: ${b.highlights.slice(0, 3).map((h) => `"${h.slice(0, 150)}"`).join(" | ")}`
        );
      }
      return lines.join("\n");
    })
    .join("\n\n");

  const exclusionNote =
    existingTitles.length > 0
      ? `\n\nNon suggerire MAI questi titoli già in libreria (sono ${existingTitles.length} libri): ${existingTitles.slice(0, 40).join(", ")}${existingTitles.length > 40 ? ", e altri…" : ""}.`
      : "";

  // Build contextual note from weather + health data
  const contextParts: string[] = [];
  if (ctx.weather && ctx.weatherCity) {
    const weatherMap: Record<string, string> = {
      sunny: "sole", rain: "pioggia", cloudy: "nuvolo",
      snow: "neve", clear: "sereno",
    };
    const cond = weatherMap[ctx.weather as string] ?? String(ctx.weather);
    contextParts.push(
      `Oggi c'è ${cond} a ${ctx.weatherCity}, ${ctx.weatherTemp}°C`
    );
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
    ? `\n\nCONTESTO DELL'UTENTE OGGI: ${contextParts.join("; ")}. Puoi usarlo per aggiungere sfumature alla motivazione (es. un libro da leggere sotto la pioggia, un saggio per una giornata di recupero fisico), ma non è obbligatorio.`
    : "";

  return `Sei un bibliotecario italiano esperto e appassionato lettore. Analizza i libri che questo utente ha letto e i suoi highlight personali, poi suggerisci 5 libri che potrebbe amare.

LIBRI LETTI E HIGHLIGHT DELL'UTENTE:
${bookList}${exclusionNote}${contextNote}

ISTRUZIONI:
- Suggerisci esattamente 5 libri che l'utente NON ha ancora letto.
- Scegli libri che risuonano con i temi, le idee e lo stile che emergono dagli highlight.
- Varia tra classici e contemporanei, italiani e stranieri.
- Per ogni libro scrivi una "reason" in italiano (2-3 frasi) che spieghi PERCHÉ questo libro specifico risuonerà con questo lettore specifico, citando connessioni concrete con i suoi highlight o i temi dei libri letti.
- Rispondi SOLO con un array JSON valido, senza markdown, senza testo extra.

Formato risposta:
[
  {
    "title": "Titolo del libro",
    "author": "Nome Autore",
    "year": "anno di pubblicazione originale",
    "reason": "Spiegazione personalizzata in italiano di perché questo libro."
  }
]`;
}

// ─── Gemini API (google/gemini-2.0-flash — free tier) ────────────────────────
//
// Free limits: 15 RPM, 1 500 req/day (as of 2025)
// Key: https://aistudio.google.com/apikey  (no credit card required)

async function callGemini(
  apiKey: string,
  prompt: string
): Promise<Recommendation[]> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${apiKey}`;

  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        maxOutputTokens: 1024,
        temperature: 0.7,
      },
    }),
    signal: AbortSignal.timeout(30_000),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Gemini API ${res.status}: ${errText}`);
  }

  const data = await res.json();
  const rawText: string =
    data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";

  // Extract JSON array from response (Gemini may wrap in ```json … ```)
  const extracted = extractJson(rawText);
  const parsed = JSON.parse(extracted);

  if (!Array.isArray(parsed)) {
    throw new Error("Gemini response is not an array");
  }

  return (parsed as Recommendation[]).slice(0, 5).map((r) => ({
    title:  String(r.title  ?? ""),
    author: String(r.author ?? ""),
    year:   String(r.year   ?? ""),
    reason: String(r.reason ?? ""),
  }));
}

function extractJson(text: string): string {
  // Strip leading/trailing markdown fences if present
  const fenceMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenceMatch) return fenceMatch[1].trim();

  // Find first '[' to last ']'
  const start = text.indexOf("[");
  const end   = text.lastIndexOf("]");
  if (start !== -1 && end !== -1 && end > start) {
    return text.slice(start, end + 1);
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
