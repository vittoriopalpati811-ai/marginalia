// Marginalia — Edge Function: parse-clippings
// Triggered via webhook when a My Clippings.txt is uploaded to Storage.
// Also callable directly via POST with { import_id: string }.
//
// Deno runtime (Supabase Edge Functions).

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

const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  SERVICE_ROLE_KEY
);

// ─── Auth ───────────────────────────────────────────────────────────────────
//
// This function processes an import row for that row's user_id using the
// service-role key. It can be invoked two legitimate ways:
//   1. A Storage webhook / server-side caller using the service-role key.
//   2. (Future) the owner directly, with their user JWT.
// Previously it had NO auth at all — anyone could POST an arbitrary import_id
// and trigger processing of another user's import. We now require ONE of:
//   • the service-role key in the Authorization header (webhook path), or
//   • a valid user JWT whose id matches the import row's user_id.
//
// Returns:
//   { kind: "service" }                — trusted service-role caller
//   { kind: "user", userId }           — verified end user
//   null                               — missing/invalid credentials (401)

async function authenticate(
  req: Request,
): Promise<{ kind: "service" } | { kind: "user"; userId: string } | null> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;

  // Service-role key → trusted server-side caller (storage webhook).
  if (token === SERVICE_ROLE_KEY) return { kind: "service" };

  // Otherwise treat it as a user JWT and verify it via the anon client.
  const authClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: `Bearer ${token}` } } },
  );
  const { data, error } = await authClient.auth.getUser(token);
  if (error || !data?.user) return null;
  return { kind: "user", userId: data.user.id };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── Auth: trusted service-role caller OR verified user ───────────────────
    const auth = await authenticate(req);
    if (!auth) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }

    const { import_id } = await req.json();

    if (!import_id) {
      return jsonResponse({ error: "import_id required" }, 400);
    }

    // Fetch import record
    const { data: importRecord, error: fetchError } = await supabase
      .from("clippings_imports")
      .select("*")
      .eq("id", import_id)
      .single();

    if (fetchError || !importRecord) {
      return jsonResponse({ error: "import not found" }, 404);
    }

    // A user JWT may only process their OWN import rows. Service-role bypasses
    // this check (it is the trusted webhook path).
    if (auth.kind === "user" && importRecord.user_id !== auth.userId) {
      return jsonResponse({ error: "forbidden" }, 403);
    }

    // Mark as processing
    await supabase
      .from("clippings_imports")
      .update({ status: "processing" })
      .eq("id", import_id);

    // Download file from Storage
    const { data: fileData, error: downloadError } = await supabase.storage
      .from("clippings")
      .download(importRecord.file_path);

    if (downloadError || !fileData) {
      await markError(import_id, "Failed to download file: " + downloadError?.message);
      return jsonResponse({ error: "download failed" }, 500);
    }

    // Reject oversized payloads (a My Clippings.txt is normally well under 1 MB;
    // cap before materialising the string so a huge upload can't exhaust memory).
    const MAX_FILE_BYTES = 5_000_000; // 5 MB
    if (fileData.size > MAX_FILE_BYTES) {
      await markError(import_id, "File too large (max 5 MB)");
      return jsonResponse({ error: "file too large" }, 413);
    }

    const content = await fileData.text();
    // Bound the work even if the file slipped under the byte cap with many tiny
    // entries — process at most this many clippings.
    const MAX_CLIPPINGS = 20000;
    const clippings = parseMyClippings(content).slice(0, MAX_CLIPPINGS);

    let booksAdded = 0;
    let highlightsAdded = 0;
    let duplicatesSkipped = 0;

    const userId = importRecord.user_id;

    for (const clipping of clippings) {
      if (clipping.type !== "highlight" && clipping.type !== "note") continue;

      // Upsert book
      const { data: book, error: bookError } = await supabase
        .from("books")
        .upsert(
          { user_id: userId, title: clipping.title, author: clipping.author },
          { onConflict: "user_id,title,author", ignoreDuplicates: false }
        )
        .select("id")
        .single();

      if (bookError || !book) continue;

      const contentHash = await sha256(`${book.id}${clipping.content}`);

      const { error: highlightError } = await supabase
        .from("highlights")
        .insert({
          user_id: userId,
          book_id: book.id,
          content: clipping.content,
          location: clipping.location ?? null,
          added_at: clipping.addedAt ?? null,
          content_hash: contentHash,
        });

      if (highlightError) {
        if (highlightError.code === "23505") {
          // unique violation = duplicate
          duplicatesSkipped++;
        }
        // other errors: skip silently for now
        continue;
      }

      highlightsAdded++;
    }

    // Update import record
    await supabase
      .from("clippings_imports")
      .update({
        status: "done",
        books_added: booksAdded,
        highlights_added: highlightsAdded,
        duplicates_skipped: duplicatesSkipped,
      })
      .eq("id", import_id);

    return jsonResponse({ ok: true, booksAdded, highlightsAdded, duplicatesSkipped }, 200);
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500);
  }
});

// ─────────────────────────────────────────────
// Parser (TypeScript mirror del parser Swift)
// ─────────────────────────────────────────────

interface ParsedClipping {
  title: string;
  author: string;
  type: "highlight" | "note" | "bookmark";
  location: string | null;
  addedAt: string | null; // ISO date string
  content: string;
}

function parseMyClippings(raw: string): ParsedClipping[] {
  // Normalize line endings
  const text = raw.replace(/\r\n/g, "\n").replace(/\r/g, "\n");

  // Strip BOM if present
  const cleaned = text.startsWith("﻿") ? text.slice(1) : text;

  // Split on separator lines (exactly 10 = chars)
  const blocks = cleaned.split(/\n={10}\n?/).map((b) => b.trim()).filter(Boolean);

  const clippings: ParsedClipping[] = [];

  for (const block of blocks) {
    const lines = block.split("\n");
    if (lines.length < 2) continue;

    const titleLine = lines[0].trim();
    const metaLine = lines[1].trim();
    const content = lines.slice(3).join("\n").trim(); // skip empty line after meta

    const { title, author } = parseTitleLine(titleLine);
    const { type, location, addedAt } = parseMetaLine(metaLine);

    if (!title || !type) continue;

    clippings.push({ title, author, type, location, addedAt, content });
  }

  return deduplicateHighlights(clippings);
}

function parseTitleLine(line: string): { title: string; author: string } {
  // Format: "Book Title (Author Name)" or "Book Title (Author, Name)"
  const match = line.match(/^(.+?)\s*\(([^)]+)\)\s*$/);
  if (match) {
    return { title: match[1].trim(), author: match[2].trim() };
  }
  return { title: line.trim(), author: "Unknown" };
}

function parseMetaLine(line: string): {
  type: "highlight" | "note" | "bookmark";
  location: string | null;
  addedAt: string | null;
} {
  const lower = line.toLowerCase();

  let type: "highlight" | "note" | "bookmark" = "highlight";
  if (
    lower.includes("your note") ||
    lower.includes("la tua nota") ||
    lower.includes("votre note")
  ) {
    type = "note";
  } else if (
    lower.includes("bookmark") ||
    lower.includes("segnalibro") ||
    lower.includes("signet")
  ) {
    type = "bookmark";
  }

  // Location: "location 123-456" or "posizione 123-456"
  const locationMatch = line.match(/(?:location|posizione|emplacement)\s+([\d\-]+)/i);
  const location = locationMatch ? locationMatch[1] : null;

  // Date: "Added on Saturday, January 2, 2021 3:00:00 PM" (EN)
  //       "Aggiunto mercoledì 4 gennaio 2021 14:30:00" (IT)
  const dateMatch = line.match(
    /(?:added on|aggiunto|ajouté le)\s+.+?,?\s+(\w+\s+\d+,?\s+\d{4}(?:\s+[\d:]+\s*[AP]M?)?)/i
  );

  let addedAt: string | null = null;
  if (dateMatch) {
    const parsed = new Date(dateMatch[1]);
    if (!isNaN(parsed.getTime())) {
      addedAt = parsed.toISOString();
    }
  }

  return { type, location, addedAt };
}

// Kindle sometimes saves the same highlight multiple times as you extend the selection.
// Keep the longest version of overlapping highlights (same book + overlapping location).
function deduplicateHighlights(clippings: ParsedClipping[]): ParsedClipping[] {
  const seen = new Map<string, ParsedClipping>();

  for (const c of clippings) {
    const key = `${c.title}|||${c.author}|||${c.location ?? ""}`;
    const existing = seen.get(key);
    if (!existing || c.content.length > existing.content.length) {
      seen.set(key, c);
    }
  }

  return Array.from(seen.values());
}

async function sha256(text: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(text);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function markError(importId: string, message: string) {
  await supabase
    .from("clippings_imports")
    .update({ status: "error", error_message: message })
    .eq("id", importId);
}
