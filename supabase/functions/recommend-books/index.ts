// recommend-books — Supabase Edge Function
// ─────────────────────────────────────────────────────────────────────────────
//
// Receives the user's last 20 books (title, author, sample highlights) from
// the Flutter app, fetches plot descriptions from Open Library, then asks
// Llama 3.3 70B (via Groq) to recommend 5 books the user has NOT yet read.
//
// Request body (POST, JSON):
//   {
//     books: [{ title, author, highlights: string[] }],  ← any length; the
//                 server randomly samples min(12, books.length) of them and
//                 ≤2 highlights each to stay under the 6 K TPM limit
//     existingTitles: string[],                           ← for exclusion (≤20)
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
  match: number; // AI confidence 0-99 (0 = absent → UI hides it)
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

  // Per-user throttle: the Groq free tier is shared org-wide and was already
  // exhausted in production, so one scripted abuser could deny the AI feature
  // for everyone. Generous cap; degrades gracefully (the client already handles
  // an empty recommendations list).
  if (await isRateLimited(req, "recommend_books", 20, 86400)) {
    return json({ recommendations: [], rate_limited: true });
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

  // Caps tuned for llama-3.1-8b-instant's HARD 6 000 tokens-per-MINUTE ceiling.
  //
  // The old caps (40 books × 8 highlights + a 50-title exclusion list +
  // 4096 reserved output tokens) put a single call for a large library
  // (≈996 highlights, 50+ books) WELL over 6 K TPM → HTTP 429 → reason
  // 'rate_limit'. Worse, retrying inside the same minute 429'd again, so
  // "Riprova" looked dead. Founder direction: "se sono troppi libri
  // prendine un numero accettabile randomico."
  //
  // New budget per call:
  //   • RANDOM subset of min(12, books.length) books (not all 40).
  //   • ≤ 2 highlights/book, each ≤ 80 chars  → ~12 × 2 × 80 = 1 920 chars
  //     ≈ 500 tokens of highlight payload.
  //   • exclusion list capped at 20 titles (was 50).
  //   • max_tokens lowered 4096 → 2800 (see callGroq).
  // Total input ~600-900 tokens + ≤2800 output ≈ <3 700 tokens/call, so a
  // single retry within the same minute still fits comfortably under 6 K.
  //
  // Defensive clamping: cap array sizes AND every text field to <=400 chars
  // before any of it reaches the prompt. The client already trims, but the
  // server must not trust client input — this bounds prompt size, token cost,
  // and prompt-injection payload length.
  const MAX_FIELD = 400;
  const MAX_BOOKS = 12; // random subset — keeps a call+retry under 6 K TPM
  const MAX_HIGHLIGHTS_PER_BOOK = 2;
  const MAX_EXCLUSION_TITLES = 20;
  const clampField = (v: unknown): string => String(v ?? "").slice(0, MAX_FIELD);

  // Fisher-Yates shuffle so each call samples a DIFFERENT random subset of the
  // library — over repeated days the user still sees their whole shelf inform
  // the picks, but any single request stays tiny. Non-mutating on the original.
  const sampleBooks = <T>(arr: T[], n: number): T[] => {
    const copy = arr.slice();
    for (let i = copy.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [copy[i], copy[j]] = [copy[j], copy[i]];
    }
    return copy.slice(0, n);
  };

  const allBooks: InputBook[] = (Array.isArray(body.books) ? body.books : [])
    .map((b) => ({
      title: clampField(b?.title),
      author: clampField(b?.author),
      highlights: (Array.isArray(b?.highlights) ? b.highlights : [])
        .slice(0, MAX_HIGHLIGHTS_PER_BOOK)
        .map((h) => clampField(h).slice(0, 80)),
    }))
    .filter((b) => b.title.length > 0);
  // Take a random subset rather than the first N — see sampleBooks above.
  const books: InputBook[] = sampleBooks(allBooks, MAX_BOOKS);
  const existingTitles: string[] = (Array.isArray(body.existingTitles) ? body.existingTitles : [])
    .map((t) => clampField(t).toLowerCase().trim())
    .slice(0, MAX_EXCLUSION_TITLES);
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
      // Up to 2 highlights × 80 chars per book — already trimmed upstream;
      // re-clamp here as a safety net so the prompt size stays bounded under
      // the 6 K TPM ceiling regardless of caller input.
      const lines: string[] = [`${i + 1}. "${b.title}" di ${b.author}`];
      if (b.plot) lines.push(`   Trama: ${b.plot}`);
      if (b.highlights.length > 0) {
        lines.push(
          `   Highlight: ${b.highlights.slice(0, 2).map((h) => `"${h.slice(0, 80)}"`).join(" | ")}`
        );
      }
      return lines.join("\n");
    })
    .join("\n\n");

  const exclusionNote =
    existingTitles.length > 0
      ? (en
          ? `\n\nDo not suggest titles already in their library: ${existingTitles.slice(0, 20).join(", ")}.`
          : `\n\nNon suggerire titoli già nella sua libreria: ${existingTitles.slice(0, 20).join(", ")}.`)
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
- For EACH recommendation first choose a "sourceBook": the SINGLE book from the BOOKS READ list above that MOST justifies the pick (strongest affinity of theme, style, author or era). Copy its "title" and "author" EXACTLY as they appear in the list; never cite a book that is not in the list.
- The "reason" must explain the link to THAT sourceBook, and "why" must be EXACTLY "Because you read " + sourceBook title + " by " + sourceBook author + ".". The book cited in "why" MUST be the same as sourceBook and the same one the reason refers to — NEVER a different book.
- Also fill, for each book: "plot" (1-2 sentence synopsis in ENGLISH), "categories" (2-4 genres such as "Fiction", "Mystery", "Coming-of-age"), "pages" (approximate page count as a plain number string).
- Add "match": an INTEGER from 72 to 98 — how strongly THIS user will love the book. ALWAYS include this field for every book. USE THE FULL RANGE and spread the five scores widely so the difference is obvious: a near-perfect fit 95-98, a strong fit 86-92, a decent-but-looser fit 74-82. Do NOT cluster them within a few points and never give two books the same value. Genuine confidence, never a round placeholder.
- Reply ONLY with valid JSON in the format below, no markdown and no extra text. Use straight quotes (") only, never typographic quotes.

{
  "recommendations": [
    {
      "title": "Title",
      "author": "Author",
      "year": "year",
      "sourceBook": { "title": "EXACT title from the BOOKS READ list", "author": "That book's author" },
      "reason": "Personalised explanation, tied to sourceBook.",
      "plot": "One or two sentence synopsis.",
      "categories": ["Fiction", "Mystery"],
      "pages": "320",
      "match": 92,
      "why": "Because you read [sourceBook title] by [sourceBook author]."
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
- Per OGNI libro consigliato scegli PRIMA un "sourceBook": il SINGOLO libro della lista LIBRI LETTI qui sopra che PIÙ giustifica il consiglio (massima affinità di tema, stile, autore o epoca). Copia "title" e "author" ESATTAMENTE come appaiono nella lista; non citare libri che non sono in lista.
- La "reason" deve spiegare il legame proprio con QUEL sourceBook, e "why" deve essere ESATTAMENTE "Perché hai letto " + titolo del sourceBook + " di " + autore del sourceBook + ".". Il libro citato in "why" DEVE essere lo stesso di sourceBook e lo stesso a cui si riferisce la reason — MAI un libro diverso.
- Compila inoltre, per ogni libro: "plot" (trama in 1-2 frasi, in italiano), "categories" (2-4 generi, es. "Narrativa", "Giallo", "Formazione"), "pages" (numero di pagine approssimativo come stringa numerica).
- Aggiungi "match": un INTERO da 72 a 98 — quanto fortemente QUESTO utente amerà il libro. INCLUDILO SEMPRE per ogni libro. USA TUTTA LA GAMMA e distanzia bene i cinque punteggi così che la differenza si veda: affinità quasi perfetta 95-98, forte 86-92, discreta ma più debole 74-82. NON ammassarli in pochi punti e non dare mai lo stesso valore a due libri. Reale confidenza, mai un numero generico.
- Rispondi SOLO con JSON valido nel formato sotto, senza markdown e senza testo extra. Usa esclusivamente virgolette dritte ("), mai virgolette tipografiche.

{
  "recommendations": [
    {
      "title": "Titolo",
      "author": "Autore",
      "year": "anno",
      "sourceBook": { "title": "Titolo ESATTO dalla lista LIBRI LETTI", "author": "Autore di quel libro" },
      "reason": "Spiegazione personalizzata, legata al sourceBook.",
      "plot": "Trama in una o due frasi.",
      "categories": ["Narrativa", "Giallo"],
      "pages": "320",
      "match": 92,
      "why": "Perché hai letto [titolo del sourceBook] di [autore del sourceBook]."
    }
  ]
}`;
}

// ─── Groq API (openai/gpt-oss-20b — free tier) ───────────────────────────────
//
// Migrated 2026-07 from llama-3.1-8b-instant (deprecated by Groq, decommissioned
// 2026-08-16; recommended replacement = gpt-oss-20b). History below.
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
      // gpt-oss-20b: Groq's recommended replacement for the deprecated
      // llama-3.1-8b-instant (decommissioned 2026-08-16). Reasoning model, so
      // reasoning_effort "low" keeps latency/cost down; its chain-of-thought
      // goes to a separate field, leaving `content` as the JSON we parse.
      model: "openai/gpt-oss-20b",
      messages: [{ role: "user", content: prompt }],
      reasoning_effort: "low",
      // Reserved completion budget: enough for 5 recommendations (each with
      // title+author+year+reason+plot+categories+pages+why) PLUS gpt-oss-20b's
      // low-effort reasoning tokens, which also count toward the completion.
      // The salvage parser below recovers any complete objects if a long
      // response is cut off. (Under llama-3.1-8b-instant this was 2800 to stay
      // under a 6 K TPM ceiling; gpt-oss-20b has a higher allowance.)
      max_completion_tokens: 4096,
      // Lower than 0.7 to reduce "anchor drift" — the model picking one book for
      // the blurb and an unrelated one for "why". Recs still vary day-to-day via
      // the per-call random library subset.
      temperature: 0.4,
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
    // On a rate-limit, log the status line AND Groq's own limit headers so
    // future debugging shows the real TPM ceiling we hit (e.g.
    // "x-ratelimit-limit-tokens: 6000 / remaining-tokens: 0 / reset: 12s").
    if (res.status === 429) {
      const limit  = res.headers.get("x-ratelimit-limit-tokens") ?? "?";
      const remain = res.headers.get("x-ratelimit-remaining-tokens") ?? "?";
      const reset  = res.headers.get("x-ratelimit-reset-tokens") ?? "?";
      console.error(
        `Groq 429 (${res.statusText}): tokens limit=${limit} remaining=${remain} reset=${reset} — ${errText}`,
      );
    }
    throw new Error(`Groq API ${res.status} ${res.statusText}: ${errText}`);
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

  return (list as Recommendation[]).slice(0, 5).map((r, idx) => {
    const rr = r as Record<string, unknown>;
    // Derive `why` from the model's chosen sourceBook so the cited book is
    // ALWAYS the one the recommendation is actually based on. The 8B model
    // otherwise drifts and cites an unrelated library book (e.g. recommending a
    // Russian classic "because you read Moby Dick"). Language is taken from the
    // model's own `why` prefix; defaults to Italian (the app is Italian-first).
    let why = String(rr.why ?? "");
    const sb = rr.sourceBook;
    if (sb && typeof sb === "object") {
      const sbRec = sb as Record<string, unknown>;
      const sbTitle = String(sbRec.title ?? "").trim();
      const sbAuthor = String(sbRec.author ?? "").trim();
      if (sbTitle) {
        const isEn = why.toLowerCase().startsWith("because");
        if (isEn) {
          why = sbAuthor
            ? `Because you read ${sbTitle} by ${sbAuthor}.`
            : `Because you read ${sbTitle}.`;
        } else {
          why = sbAuthor
            ? `Perché hai letto ${sbTitle} di ${sbAuthor}.`
            : `Perché hai letto ${sbTitle}.`;
        }
      }
    }
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
      match:  clampMatch(rr.match, idx),
      why,
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

  // Fast path: the response is well-formed (the common case). Accept either
  // the object wrapper or a bare array. With max_tokens at 2800 a very long
  // 5-rec response can still be truncated — the salvage path below recovers
  // whatever complete objects made it through.
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

// Per-user rate limit via the shared check_rate_limit RPC, which RAISES when
// the caller exceeds [max] events in the trailing [windowSeconds]. Returns true
// (= limited) only on that raise; fails OPEN on any other error so a limiter
// glitch never blocks a legitimate user.
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

// Netflix-style "% match": the model's per-book confidence, clamped to a
// believable 72–98 band (wide enough that 98 vs 74 reads as a real difference).
// EVERY pick gets a score — if the model omits one we derive it from the rank
// (earlier = stronger) so no recommendation is ever shown without a %.
function clampMatch(v: unknown, rankIndex = 0): number {
  const n = typeof v === "number" ? v : parseInt(String(v ?? ""), 10);
  if (Number.isFinite(n) && n > 0) {
    return Math.max(72, Math.min(98, Math.round(n)));
  }
  return Math.max(74, 94 - rankIndex * 4);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
