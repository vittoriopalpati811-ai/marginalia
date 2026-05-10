"use client";

import { useState, useEffect } from "react";
import { createClient } from "@/lib/supabase/client";
import { useRouter } from "next/navigation";
import type { Book, Highlight } from "@/lib/supabase/types";

interface Props {
  jamId: string;
  userId: string;
}

export function ShareHighlightButton({ jamId, userId }: Props) {
  const [open, setOpen] = useState(false);
  const [books, setBooks] = useState<Book[]>([]);
  const [selectedBook, setSelectedBook] = useState<string>("");
  const [highlights, setHighlights] = useState<Highlight[]>([]);
  const [loading, setLoading] = useState(false);
  const router = useRouter();

  useEffect(() => {
    if (!open) return;
    const supabase = createClient();
    supabase
      .from("books")
      .select("*")
      .eq("user_id", userId)
      .order("title")
      .then(({ data }) => setBooks(data ?? []));
  }, [open, userId]);

  useEffect(() => {
    if (!selectedBook) { setHighlights([]); return; }
    const supabase = createClient();
    supabase
      .from("highlights")
      .select("*")
      .eq("book_id", selectedBook)
      .eq("user_id", userId)
      .order("added_at")
      .then(({ data }) => setHighlights(data ?? []));
  }, [selectedBook, userId]);

  async function shareHighlight(highlightId: string) {
    setLoading(true);
    const supabase = createClient();
    await supabase.from("jam_highlights").upsert(
      { jam_id: jamId, highlight_id: highlightId, shared_by: userId },
      { onConflict: "jam_id,highlight_id" }
    );
    setLoading(false);
    setOpen(false);
    router.refresh();
  }

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="text-sm text-accent hover:text-accent/80 transition-colors"
      >
        + Condividi highlight
      </button>
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-text/20 backdrop-blur-sm">
      <div className="bg-bg border border-border rounded-sm p-6 w-full max-w-md shadow-sm max-h-[80vh] flex flex-col">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-serif text-lg text-text">Scegli un highlight</h2>
          <button onClick={() => setOpen(false)} className="text-muted hover:text-text text-xl leading-none">
            ×
          </button>
        </div>

        {/* Book selector */}
        <select
          value={selectedBook}
          onChange={(e) => setSelectedBook(e.target.value)}
          className="w-full bg-surface border border-border rounded-sm px-3 py-2 text-sm text-text mb-4 focus:outline-none focus:border-accent"
        >
          <option value="">Seleziona un libro...</option>
          {books.map((b) => (
            <option key={b.id} value={b.id}>{b.title}</option>
          ))}
        </select>

        {/* Highlights list */}
        <div className="overflow-y-auto space-y-2">
          {highlights.map((h) => (
            <button
              key={h.id}
              disabled={loading}
              onClick={() => shareHighlight(h.id)}
              className="w-full text-left highlight-card hover:border-accent transition-colors"
            >
              <p className="highlight-text text-sm line-clamp-3">{h.content}</p>
              {h.location && (
                <p className="mt-1 text-xs text-muted">{h.location}</p>
              )}
            </button>
          ))}
          {selectedBook && highlights.length === 0 && (
            <p className="text-sm text-muted text-center py-6">Nessun highlight per questo libro.</p>
          )}
        </div>
      </div>
    </div>
  );
}
