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
//   ANTHROPIC_API_KEY    — Anthropic API key (sk-ant-…)
//
// Auto-injected by Supabase:
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
//
// Deploy:
//   supabase functions deploy recommend-books
// Set key:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-…

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

  let body: { books?: InputBook[]; existingTitles?: string[] };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const books: InputBook[] = (body.books ?? []).slice(0, 20);
  const existingTitles: string[] = (body.existingTitles ?? []).map((t) =>
    t.toLowerCase().trim()
  );

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

  // ── 2. Build Claude prompt ───────────────────────────────────────────────

  const prompt = buildPrompt(withPlots, existingTitles);

  // ── 3. Call Claude API ───────────────────────────────────────────────────

  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!anthropicKey) {
    return json({ error: "ANTHROPIC_API_KEY not configured" }, 500);
  }

  let claudeResponse: Recommendation[];
  try {
    claudeResponse = await callClaude(anthropicKey, prompt);
  } catch (e) {
    console.error("Claude API error:", e);
    return json({ error: "AI service unavailable" }, 502);
  }

  return json({ recommendations: claudeResponse });
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
  existingTitles: string[]
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

  return `Sei un bibliotecario italiano esperto e appassionato lettore. Analizza i libri che questo utente ha letto e i suoi highlight personali, poi suggerisci 5 libri che potrebbe amare.

LIBRI LETTI E HIGHLIGHT DELL'UTENTE:
${bookList}${exclusionNote}

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

// ─── Claude API ───────────────────────────────────────────────────────────────

async function callClaude(
  apiKey: string,
  prompt: string
): Promise<Recommendation[]> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5",
      max_tokens: 1024,
      messages: [{ role: "user", content: prompt }],
    }),
    signal: AbortSignal.timeout(30_000),
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Claude API ${res.status}: ${errText}`);
  }

  const data = await res.json();
  const rawText: string = data?.content?.[0]?.text ?? "";

  // Extract JSON from response (Claude sometimes wraps in ```json … ```)
  const extracted = extractJson(rawText);
  const parsed = JSON.parse(extracted);

  if (!Array.isArray(parsed)) {
    throw new Error("Claude response is not an array");
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
