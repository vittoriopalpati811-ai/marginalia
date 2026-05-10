// Marginalia — Edge Function: parse-clippings
// Triggered via webhook when a My Clippings.txt is uploaded to Storage.
// Also callable directly via POST with { import_id: string }.
//
// Deno runtime (Supabase Edge Functions).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

Deno.serve(async (req) => {
  try {
    const { import_id } = await req.json();

    if (!import_id) {
      return new Response(JSON.stringify({ error: "import_id required" }), { status: 400 });
    }

    // Fetch import record
    const { data: importRecord, error: fetchError } = await supabase
      .from("clippings_imports")
      .select("*")
      .eq("id", import_id)
      .single();

    if (fetchError || !importRecord) {
      return new Response(JSON.stringify({ error: "import not found" }), { status: 404 });
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
      return new Response(JSON.stringify({ error: "download failed" }), { status: 500 });
    }

    const content = await fileData.text();
    const clippings = parseMyClippings(content);

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

    return new Response(
      JSON.stringify({ ok: true, booksAdded, highlightsAdded, duplicatesSkipped }),
      { status: 200 }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
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
