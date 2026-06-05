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
  plot: string;
  categories: string[];
  pages: string;
  why: string;
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
  // Groq LLM prompt (cost/abuse + prompt-injection surface). Require a verified
  // caller before doing any model work.
  const user = await requireUser(req);
  if (!user) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: {
    books?: InputBook[];
    existingTitles?: string[];
    context?: Record<string, unknown>;
    userName?: string;
    lang?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  // Caps tuned for llama-3.1-8b-instant's 6 K TPM ceiling.
  //
  // The client now samples up to 3 highlights from EVERY book in the
  // user's library (capped at 40 books) so the model sees the whole
  // reading life, not just the last fortnight. With 3 highlights × 80
  // chars × 40 books = 9.6 K chars / ~2.5 K tokens for the highlight
  // payload, plus plot summaries only for books with sparse highlights
  // (≤2). Total request stays ~3-3.5 K tokens, leaving 2.5-3 K TPM
  // headroom for two more invocations inside the same minute.
  // Defensive clamping: cap array sizes AND every text field to <=400 chars
  // before any of it reaches the prompt. The client already trims, but the
  // server must not trust client input — this bounds prompt size, token cost,
  // and prompt-injection payload length.
  const MAX_FIELD = 400;
  const clampField = (v: unknown): string => String(v ?? "").slice(0, MAX_FIELD);

  const books: InputBook[] = (Array.isArray(body.books) ? body.books : [])
    .slice(0, 40)
    .map((b) => ({
      title: clampField(b?.title),
      author: clampField(b?.author),
      highlights: (Array.isArray(b?.highlights) ? b.highlights : [])
        .slice(0, 8)
        .map(clampField),
    }));
  const existingTitles: string[] = (Array.isArray(body.existingTitles) ? body.existingTitles : [])
    .map((t) => clampField(t).toLowerCase().trim())
    .slice(0, 50);
  const userContext: Record<string, unknown> = body.context ?? {};
  const userName: string = clampField(body.userName).trim();
  // Output language for the AI-written "reason" — defaults to Italian; English
  // when the app locale is 'en' (US rollout). The client sends `lang`.
  const lang: string = body.lang === "en" ? "en" : "it";

  if (books.length === 0) {
    return json({ recommendations: [], reason: "no_books" });
  }

  // ── 1. Fetch Open Library plots — only when we need the help ─────────────
  //
  // For books with ≥ 3 highlights, the highlights themselves are a much
  // stronger mood signal than a generic Open Library summary, and the
  // plot fetch costs both latency (up to 8 s per book) and tokens. So we
  // skip the fetch in that case and let the highlights carry the signal.

  const withPlots = await Promise.all(
    books.map(async (book) => {
      if (book.highlights.length >= 3) {
        return { ...book, plot: "" };
      }
      const plot = await fetchOpenLibraryPlot(book.title, book.author);
      return { ...book, plot };
    })
  );

  // ── 2. Build prompt ──────────────────────────────────────────────────────

  const prompt = buildPrompt(withPlots, existingTitles, userContext, userName, lang);

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

    // Plot summaries were 600 chars × 20 books = 12 K chars of pure plot
    // text alone. With the 8B model's 6 K TPM limit that was untenable.
    // 220 chars is one good sentence — enough for the model to know the
    // book's mood and theme without bloating the prompt.
    if (doc.description) return extractText(doc.description).slice(0, 180);

    const key = doc.key as string | undefined;
    if (!key) return "";

    const worksRes = await fetch(`https://openlibrary.org${key}.json`, {
      signal: AbortSignal.timeout(6_000),
    });
    if (!worksRes.ok) return "";

    const works = await worksRes.json();
    return extractText(works.description ?? "").slice(0, 180);
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
  userName: string,
  lang: string
): string {
  const en = lang === "en";
  const bookList = books
    .map((b, i) => {
      // Up to 8 highlights × 80 chars per book. The client already
      // pre-selected the 100 most-recent highlights overall, so the
      // server-side cap is a safety net rather than a primary trim.
      const lines: string[] = [`${i + 1}. "${b.title}" di ${b.author}`];
      if (b.plot) lines.push(`   Trama: ${b.plot}`);
      if (b.highlights.length > 0) {
        lines.push(
          `   Highlight: ${b.highlights.slice(0, 8).map((h) => `"${h.slice(0, 80)}"`).join(" | ")}`
        );
      }
      return lines.join("\n");
    })
    .join("\n\n");

  const exclusionNote =
    existingTitles.length > 0
      ? (en
          ? `\n\nDo not suggest titles already in their library: ${existingTitles.slice(0, 25).join(", ")}.`
          : `\n\nNon suggerire titoli già nella sua libreria: ${existingTitles.slice(0, 25).join(", ")}.`)
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
    ? (en
        ? `\n\nUSER CONTEXT: ${contextParts.join("; ")}. You may use it to nuance the picks, but it is optional.`
        : `\n\nCONTESTO UTENTE: ${contextParts.join("; ")}. Puoi usarlo per sfumare i consigli, ma non è obbligatorio.`)
    : "";

  // How to address the user in the reason field
  const addressee = userName ? userName : "lettore";
  const reasonInstruction = en
    ? (userName
        ? `For each book write a "reason" in ENGLISH (2-3 sentences), addressing the user directly by name, in the second person. ALWAYS start with "${userName}, you'll love" or "${userName}, you'll appreciate" or "${userName}, you'll be won over by" — never "The reader" or impersonal phrasing. Cite concrete connections with their highlights.`
        : `For each book write a "reason" in ENGLISH (2-3 sentences) in direct second person ("you'll love", "you'll appreciate", "it will win you over"). Cite concrete connections with their highlights.`)
    : (userName
        ? `Per ogni libro scrivi una "reason" in italiano (2-3 frasi) rivolgendoti direttamente all'utente per nome, in seconda persona. Inizia SEMPRE con "${userName}, apprezzerai" oppure "${userName}, adorerai" oppure "${userName}, ti conquisterà" — mai con "Il lettore" o frasi impersonali. Cita connessioni concrete con i suoi highlight.`
        : `Per ogni libro scrivi una "reason" in italiano (2-3 frasi) in seconda persona diretta ("apprezzerai", "adorerai", "ti conquisterà"). Cita connessioni concrete con i suoi highlight.`);

  if (en) {
    return `You are an expert librarian and passionate reader. Analyze the books this user has read and their personal highlights, then suggest 5 books they would love.

BOOKS READ:
${bookList}${exclusionNote}${contextNote}

INSTRUCTIONS:
- Suggest exactly 5 books the user has NOT read yet.
- Choose books that resonate with the themes, ideas and style of the highlights.
- Mix classics and contemporary, and authors from different countries.
- ${reasonInstruction}
- Also fill, for each book: "plot" (1-2 sentence synopsis in ENGLISH), "categories" (2-4 genres such as "Fiction", "Mystery", "Coming-of-age"), "pages" (approximate page count as a plain number string), and "why" (ONE sentence starting with "Because you read" that cites ONE specific book from their list above).
- Reply ONLY with valid JSON in the format below, no markdown and no extra text. Use straight quotes (") only, never typographic quotes.

{
  "recommendations": [
    {
      "title": "Title",
      "author": "Author",
      "year": "year",
      "reason": "Personalised explanation.",
      "plot": "One or two sentence synopsis.",
      "categories": ["Fiction", "Mystery"],
      "pages": "320",
      "why": "Because you read X by Y."
    }
  ]
}`;
  }

  return `Sei un bibliotecario italiano esperto e appassionato lettore. Analizza i libri che questo utente ha letto e i suoi highlight personali, poi suggerisci 5 libri che potrebbe amare.

LIBRI LETTI:
${bookList}${exclusionNote}${contextNote}

ISTRUZIONI:
- Suggerisci esattamente 5 libri che l'utente NON ha ancora letto.
- Scegli libri che risuonano con i temi, le idee e lo stile degli highlight.
- Varia tra classici e contemporanei, italiani e stranieri.
- ${reasonInstruction}
- Compila inoltre, per ogni libro: "plot" (trama in 1-2 frasi, in italiano), "categories" (2-4 generi, es. "Narrativa", "Giallo", "Formazione"), "pages" (numero di pagine approssimativo come stringa numerica), e "why" (UNA frase che inizia con "Perché hai letto" e cita UN libro specifico dalla sua lista qui sopra).
- Rispondi SOLO con JSON valido nel formato sotto, senza markdown e senza testo extra. Usa esclusivamente virgolette dritte ("), mai virgolette tipografiche.

{
  "recommendations": [
    {
      "title": "Titolo",
      "author": "Autore",
      "year": "anno",
      "reason": "Spiegazione personalizzata.",
      "plot": "Trama in una o due frasi.",
      "categories": ["Narrativa", "Giallo"],
      "pages": "320",
      "why": "Perché hai letto X di Y."
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
      // 2048 was too tight for THIS prompt: 5 recommendations each carrying
      // title+author+year+reason (2-3 sentences) +plot (1-2 sentences)
      // +categories +pages +why easily exceeds 2 K output tokens for a large
      // library. The response was being TRUNCATED mid-string, JSON.parse threw,
      // and the caller surfaced reason 'ai_error' (HTTP 200 in ~8 s, empty
      // list) — exactly the failure big libraries (50+ books) hit every time.
      // 4096 gives comfortable headroom; the salvage parse below is the second
      // line of defence if a response is still cut off.
      max_tokens: 4096,
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

  // Tolerant parse: returns the recommendations array even when the model
  // response is fenced in markdown OR truncated mid-object (the latter is what
  // a large library used to trip — the JSON was cut off and a bare JSON.parse
  // threw → reason 'ai_error'). See parseRecommendations for the strategy.
  const list = parseRecommendations(rawText);

  if (!Array.isArray(list)) {
    throw new Error("Response missing recommendations array");
  }

  return (list as Recommendation[]).slice(0, 5).map((r) => {
    const rr = r as Record<string, unknown>;
    return {
      title:  String(r.title  ?? ""),
      author: String(r.author ?? ""),
      year:   String(r.year   ?? ""),
      reason: String(r.reason ?? ""),
      plot:   String(rr.plot ?? ""),
      categories: Array.isArray(rr.categories)
        ? (rr.categories as unknown[]).map((c) => String(c)).slice(0, 5)
        : [],
      pages:  String(rr.pages ?? ""),
      why:    String(rr.why ?? ""),
    };
  });
}

// Best-effort extraction of the recommendations array from a raw model
// response. Robust to three real-world failure modes the 8B model produces:
//
//   1. Markdown fences (```json … ```) around the JSON.
//   2. A bare array instead of the {recommendations:[…]} wrapper.
//   3. A TRUNCATED response — the single biggest cause of 'ai_error' for large
//      libraries. When max_tokens is hit mid-object the JSON is invalid, so a
//      strict JSON.parse throws and the whole batch is lost. Here we instead
//      salvage every COMPLETE recommendation object that did make it through
//      and discard only the trailing partial one. As long as the model emitted
//      at least one whole object before the cut, the user still gets picks.
//
// Returns the parsed array, or null if nothing usable could be recovered (the
// caller then throws → reason 'ai_error', same as before).
function parseRecommendations(text: string): unknown[] | null {
  const cleaned = extractJson(text);

  // Fast path: the response is well-formed (the common case, and always the
  // case now that max_tokens is 4096). Accept either the object wrapper or a
  // bare array.
  try {
    const parsed = JSON.parse(cleaned);
    const list = Array.isArray(parsed)
      ? parsed
      : (parsed as { recommendations?: unknown[] }).recommendations;
    if (Array.isArray(list)) return list;
  } catch {
    // fall through to salvage
  }

  // Salvage path: the JSON is malformed/truncated. Walk the string and pull
  // out each top-level `{...}` object inside the recommendations array using
  // brace-depth tracking that ignores braces appearing inside string literals.
  // Each balanced object is parsed independently; the final unbalanced one
  // (the truncation point) is simply never closed, so it is skipped.
  const salvaged = salvageObjects(cleaned);
  return salvaged.length > 0 ? salvaged : null;
}

// Pull every balanced `{…}` JSON object out of `text`, parsing each one in
// isolation. String-literal awareness (incl. escaped quotes) keeps braces and
// quotes inside values from corrupting the depth count. Any object that fails
// to parse on its own is dropped rather than aborting the whole salvage.
function salvageObjects(text: string): unknown[] {
  const objects: unknown[] = [];
  let depth = 0;
  let start = -1;
  let inString = false;
  let escaped = false;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch === "\\") {
        escaped = true;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }

    if (ch === '"') {
      inString = true;
    } else if (ch === "{") {
      if (depth === 0) start = i;
      depth++;
    } else if (ch === "}") {
      if (depth > 0) {
        depth--;
        if (depth === 0 && start !== -1) {
          const candidate = text.slice(start, i + 1);
          try {
            const obj = JSON.parse(candidate);
            // Skip the outer wrapper object ({"recommendations": …}) — we only
            // want the per-book objects, which carry a title.
            if (obj && typeof obj === "object" && "title" in obj) {
              objects.push(obj);
            }
          } catch {
            // drop this fragment
          }
          start = -1;
        }
      }
    }
  }

  return objects;
}

function extractJson(text: string): string {
  const fenceMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenceMatch) return fenceMatch[1].trim();

  // Prefer an object wrapper (`{...}`); fall back to a bare array (`[...]`)
  // if the model emitted one despite the prompt. We slice to the LAST closing
  // brace/bracket so a well-formed response is returned intact; a truncated
  // one (no closing brace) falls through to the salvage parser upstream.
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
