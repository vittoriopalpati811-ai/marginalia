import { createClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";

interface Props {
  params: Promise<{ bookId: string }>;
}

export default async function BookDetailPage({ params }: Props) {
  const { bookId } = await params;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  const { data: book } = await supabase
    .from("books")
    .select("*")
    .eq("id", bookId)
    .eq("user_id", user!.id)
    .single();

  if (!book) notFound();

  const { data: highlights } = await supabase
    .from("highlights")
    .select("*")
    .eq("book_id", bookId)
    .order("added_at", { ascending: true, nullsFirst: false });

  return (
    <div>
      {/* Header */}
      <div className="mb-8 pb-6 border-b border-border">
        <div className="flex items-start gap-4">
          <div
            className="w-12 flex-shrink-0 rounded-sm"
            style={{ backgroundColor: book.cover_color, minHeight: "72px" }}
          />
          <div>
            <h1 className="font-serif text-2xl text-text leading-snug">{book.title}</h1>
            <p className="mt-1 text-sm text-muted">{book.author}</p>
            <p className="mt-3 text-xs text-muted">
              {highlights?.length ?? 0} highlight
            </p>
          </div>
        </div>
      </div>

      {/* Highlights */}
      {!highlights || highlights.length === 0 ? (
        <p className="text-sm text-muted text-center py-10">Nessun highlight.</p>
      ) : (
        <div className="space-y-4">
          {highlights.map((h) => (
            <div key={h.id} className="highlight-card">
              <p className="highlight-text">{h.content}</p>
              <div className="mt-3 flex items-center gap-3 text-xs text-muted">
                {h.location && <span>{h.location}</span>}
                {h.added_at && (
                  <span>
                    {new Date(h.added_at).toLocaleDateString("it-IT", {
                      day: "numeric",
                      month: "long",
                      year: "numeric",
                    })}
                  </span>
                )}
              </div>
              {h.personal_note && (
                <p className="mt-3 pt-3 border-t border-border text-sm text-muted italic">
                  {h.personal_note}
                </p>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
