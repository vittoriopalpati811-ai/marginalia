import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { CreateJamButton } from "./CreateJamButton";
import type { Jam } from "@/lib/supabase/types";

export default async function JamPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  // Jam dove sono owner
  const { data: myJams } = await supabase
    .from("jams")
    .select("*, jam_members(count)")
    .eq("owner_id", user!.id)
    .eq("is_active", true)
    .order("created_at", { ascending: false });

  // Jam dove sono membro (non owner)
  const { data: joinedJams } = await supabase
    .from("jam_members")
    .select("jams(*)")
    .eq("user_id", user!.id)
    .neq("jam_id", myJams?.map((j) => j.id).join(",") ?? ""); // esclude le proprie

  const joined = joinedJams?.map((jm: { jams: Jam | null }) => jm.jams).filter(Boolean) as Jam[];

  return (
    <div>
      <div className="flex items-center justify-between mb-8">
        <div>
          <h1 className="font-serif text-2xl text-text">Jam</h1>
          <p className="mt-1 text-sm text-muted">
            Cerchie di lettura permanenti — condividi highlight con chi vuoi.
          </p>
        </div>
        <CreateJamButton />
      </div>

      {/* Le mie Jam */}
      {myJams && myJams.length > 0 && (
        <section className="mb-8">
          <h2 className="text-xs uppercase tracking-widest text-muted mb-3">Le mie Jam</h2>
          <div className="space-y-3">
            {myJams.map((jam) => (
              <JamCard key={jam.id} jam={jam} isOwner />
            ))}
          </div>
        </section>
      )}

      {/* Jam a cui ho aderito */}
      {joined && joined.length > 0 && (
        <section className="mb-8">
          <h2 className="text-xs uppercase tracking-widest text-muted mb-3">Jam condivise</h2>
          <div className="space-y-3">
            {joined.map((jam) => (
              <JamCard key={jam.id} jam={jam} isOwner={false} />
            ))}
          </div>
        </section>
      )}

      {/* Empty state */}
      {(!myJams || myJams.length === 0) && (!joined || joined.length === 0) && (
        <div className="text-center py-20">
          <p className="font-serif text-xl text-muted">Nessuna Jam ancora.</p>
          <p className="mt-2 text-sm text-muted">
            Crea una cerchia di lettura e invita chi vuoi.
          </p>
        </div>
      )}

      {/* Join via codice */}
      <JoinByCode />
    </div>
  );
}

function JamCard({ jam, isOwner }: { jam: Jam; isOwner: boolean }) {
  return (
    <Link href={`/jam/${jam.id}`} className="block">
      <div className="highlight-card group">
        <div className="flex items-start justify-between gap-4">
          <div>
            <p className="font-medium text-text group-hover:text-accent transition-colors">
              {jam.title}
            </p>
            {jam.description && (
              <p className="mt-0.5 text-sm text-muted line-clamp-1">{jam.description}</p>
            )}
            {jam.book_filter && (
              <p className="mt-1 text-xs text-accent-light">{jam.book_filter}</p>
            )}
          </div>
          {isOwner && (
            <span className="flex-shrink-0 text-xs bg-accent/10 text-accent px-2 py-0.5 rounded-full">
              Owner
            </span>
          )}
        </div>
        <p className="mt-2 text-xs text-muted font-mono">#{jam.invite_code}</p>
      </div>
    </Link>
  );
}

function JoinByCode() {
  return (
    <div className="mt-10 pt-8 border-t border-border">
      <p className="text-sm text-muted mb-3">Hai un codice invito?</p>
      <form action="/api/jam/join" method="POST" className="flex gap-2">
        <input
          name="code"
          placeholder="Codice Jam"
          maxLength={8}
          className="bg-surface border border-border rounded-sm px-3 py-2 text-sm text-text placeholder:text-muted focus:outline-none focus:border-accent font-mono w-32"
        />
        <button
          type="submit"
          className="bg-accent text-bg px-4 py-2 rounded-sm text-sm hover:bg-accent/90 transition-colors"
        >
          Unisciti
        </button>
      </form>
    </div>
  );
}
