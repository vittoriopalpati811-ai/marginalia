import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import type { Book } from "@/lib/supabase/types";

export default async function LibraryPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  const { data: books } = await supabase
    .from("books")
    .select("*, highlights(count)")
    .eq("user_id", user!.id)
    .order("imported_at", { ascending: false });

  if (!books || books.length === 0) {
    return <EmptyLibrary />;
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-8">
        <h1 className="font-serif text-2xl text-text">Libreria</h1>
        <Link
          href="/import"
          className="text-sm text-accent hover:text-accent/80 transition-colors"
        >
          + Importa
        </Link>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        {books.map((book) => (
          <BookCard key={book.id} book={book} />
        ))}
      </div>
    </div>
  );
}

function BookCard({ book }: { book: Book & { highlights: { count: number }[] } }) {
  const count = book.highlights?.[0]?.count ?? 0;

  return (
    <Link href={`/library/${book.id}`} className="block">
      <div className="highlight-card flex gap-4 group">
        {/* Cover */}
        <div
          className="w-10 flex-shrink-0 rounded-sm"
          style={{ backgroundColor: book.cover_color, minHeight: "60px" }}
        />
        {/* Info */}
        <div className="min-w-0">
          <p className="font-serif text-text leading-snug line-clamp-2 group-hover:text-accent transition-colors">
            {book.title}
          </p>
          <p className="mt-1 text-xs text-muted">{book.author}</p>
          <p className="mt-2 text-xs text-muted">
            {count} {count === 1 ? "highlight" : "highlight"}
          </p>
        </div>
      </div>
    </Link>
  );
}

function EmptyLibrary() {
  return (
    <div className="text-center py-20">
      <p className="font-serif text-xl text-muted">La tua libreria è vuota.</p>
      <p className="mt-2 text-sm text-muted">
        Importa il file{" "}
        <code className="text-accent text-xs">My Clippings.txt</code> dal tuo Kindle.
      </p>
      <Link
        href="/import"
        className="mt-6 inline-block bg-accent text-bg px-5 py-2.5 text-sm rounded-sm hover:bg-accent/90 transition-colors"
      >
        Importa ora
      </Link>
    </div>
  );
}
