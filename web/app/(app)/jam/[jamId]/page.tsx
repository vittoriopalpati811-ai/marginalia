import { createClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import { ShareHighlightButton } from "./ShareHighlightButton";

interface Props {
  params: Promise<{ jamId: string }>;
}

export default async function JamDetailPage({ params }: Props) {
  const { jamId } = await params;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  const { data: jam } = await supabase
    .from("jams")
    .select("*, profiles!jams_owner_id_fkey(username, display_name)")
    .eq("id", jamId)
    .single();

  if (!jam) notFound();

  // Check membership
  const { data: membership } = await supabase
    .from("jam_members")
    .select("joined_at")
    .eq("jam_id", jamId)
    .eq("user_id", user!.id)
    .single();

  if (!membership) {
    return <NotMember jam={jam} userId={user!.id} />;
  }

  // Shared highlights in this Jam
  const { data: sharedHighlights } = await supabase
    .from("jam_highlights")
    .select(`
      shared_at,
      shared_by,
      profiles!jam_highlights_shared_by_fkey(username, display_name),
      highlights(content, location, added_at, book_id, books(title, author, cover_color))
    `)
    .eq("jam_id", jamId)
    .order("shared_at", { ascending: false });

  // Members list
  const { data: members } = await supabase
    .from("jam_members")
    .select("user_id, joined_at, profiles(username, display_name)")
    .eq("jam_id", jamId);

  const isOwner = jam.owner_id === user!.id;

  return (
    <div>
      {/* Header */}
      <div className="mb-8 pb-6 border-b border-border">
        <div className="flex items-start justify-between">
          <div>
            <h1 className="font-serif text-2xl text-text">{jam.title}</h1>
            {jam.description && (
              <p className="mt-1 text-sm text-muted">{jam.description}</p>
            )}
            {jam.book_filter && (
              <p className="mt-1 text-xs text-accent-light">{jam.book_filter}</p>
            )}
          </div>
          <div className="text-right">
            <p className="text-xs text-muted">Codice invito</p>
            <p className="font-mono text-sm text-accent mt-0.5">#{jam.invite_code}</p>
          </div>
        </div>

        {/* Members */}
        <div className="mt-4 flex items-center gap-2">
          {members?.map((m: { user_id: string; profiles: { username: string; display_name: string | null } | null }) => (
            <span
              key={m.user_id}
              className="text-xs bg-surface border border-border rounded-full px-2.5 py-0.5 text-muted"
            >
              {m.profiles?.display_name ?? m.profiles?.username ?? "?"}
            </span>
          ))}
        </div>
      </div>

      {/* Action */}
      <div className="mb-6">
        <ShareHighlightButton jamId={jamId} userId={user!.id} />
      </div>

      {/* Shared highlights */}
      {!sharedHighlights || sharedHighlights.length === 0 ? (
        <div className="text-center py-12">
          <p className="text-sm text-muted">
            Nessun highlight condiviso ancora. Sii il primo.
          </p>
        </div>
      ) : (
        <div className="space-y-4">
          {sharedHighlights.map((sh, i) => {
            const h = sh.highlights as {
              content: string;
              location: string | null;
              book_id: string;
              books: { title: string; author: string; cover_color: string } | null;
            } | null;
            const profile = sh.profiles as { username: string; display_name: string | null } | null;
            if (!h) return null;

            return (
              <div key={i} className="highlight-card">
                {/* Book info */}
                {h.books && (
                  <div className="flex items-center gap-2 mb-3">
                    <div
                      className="w-3 h-4 rounded-sm flex-shrink-0"
                      style={{ backgroundColor: h.books.cover_color }}
                    />
                    <p className="text-xs text-muted">
                      <span className="text-text">{h.books.title}</span>
                      {" — "}
                      {h.books.author}
                    </p>
                  </div>
                )}

                <p className="highlight-text">{h.content}</p>

                <div className="mt-3 flex items-center justify-between text-xs text-muted">
                  <span>
                    {profile?.display_name ?? profile?.username ?? "?"}
                  </span>
                  <span>
                    {new Date(sh.shared_at).toLocaleDateString("it-IT", {
                      day: "numeric",
                      month: "short",
                    })}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function NotMember({ jam, userId }: { jam: { id: string; title: string; invite_code: string }; userId: string }) {
  return (
    <div className="text-center py-20">
      <h1 className="font-serif text-2xl text-text mb-2">{jam.title}</h1>
      <p className="text-sm text-muted mb-6">Non sei ancora membro di questa Jam.</p>
      <form action="/api/jam/join" method="POST">
        <input type="hidden" name="jam_id" value={jam.id} />
        <button
          type="submit"
          className="bg-accent text-bg px-5 py-2.5 rounded-sm text-sm hover:bg-accent/90 transition-colors"
        >
          Unisciti alla Jam
        </button>
      </form>
    </div>
  );
}
