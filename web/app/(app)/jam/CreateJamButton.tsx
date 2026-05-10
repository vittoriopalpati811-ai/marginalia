"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { useRouter } from "next/navigation";

export function CreateJamButton() {
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [bookFilter, setBookFilter] = useState("");
  const [loading, setLoading] = useState(false);
  const router = useRouter();

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);

    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    const { data, error } = await supabase
      .from("jams")
      .insert({
        owner_id: user.id,
        title: title.trim(),
        description: description.trim() || null,
        book_filter: bookFilter.trim() || null,
      })
      .select("id")
      .single();

    if (!error && data) {
      // Owner è automaticamente un membro
      await supabase.from("jam_members").insert({ jam_id: data.id, user_id: user.id });
      router.push(`/jam/${data.id}`);
      router.refresh();
    }

    setLoading(false);
    setOpen(false);
  }

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        className="text-sm text-accent hover:text-accent/80 transition-colors"
      >
        + Crea Jam
      </button>
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-text/20 backdrop-blur-sm">
      <div className="bg-bg border border-border rounded-sm p-6 w-full max-w-sm shadow-sm">
        <h2 className="font-serif text-lg text-text mb-4">Nuova Jam</h2>
        <form onSubmit={handleCreate} className="space-y-3">
          <div>
            <label className="block text-xs text-muted mb-1">Nome *</label>
            <input
              required
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="es. Libri di Calvino"
              className="w-full bg-surface border border-border rounded-sm px-3 py-2 text-sm text-text focus:outline-none focus:border-accent"
            />
          </div>
          <div>
            <label className="block text-xs text-muted mb-1">Descrizione (opzionale)</label>
            <input
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Una riga descrittiva"
              className="w-full bg-surface border border-border rounded-sm px-3 py-2 text-sm text-text focus:outline-none focus:border-accent"
            />
          </div>
          <div>
            <label className="block text-xs text-muted mb-1">Libro specifico (opzionale)</label>
            <input
              value={bookFilter}
              onChange={(e) => setBookFilter(e.target.value)}
              placeholder="es. Se una notte d'inverno un viaggiatore"
              className="w-full bg-surface border border-border rounded-sm px-3 py-2 text-sm text-text focus:outline-none focus:border-accent"
            />
          </div>
          <div className="flex gap-2 pt-2">
            <button
              type="button"
              onClick={() => setOpen(false)}
              className="flex-1 border border-border rounded-sm py-2 text-sm text-muted hover:text-text transition-colors"
            >
              Annulla
            </button>
            <button
              type="submit"
              disabled={loading}
              className="flex-1 bg-accent text-bg rounded-sm py-2 text-sm hover:bg-accent/90 transition-colors disabled:opacity-50"
            >
              {loading ? "Creazione..." : "Crea"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
