import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import Link from "next/link";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  return (
    <div className="min-h-screen flex flex-col">
      <nav className="border-b border-border bg-bg sticky top-0 z-10">
        <div className="max-w-4xl mx-auto px-4 h-14 flex items-center justify-between">
          <Link href="/library" className="font-serif text-lg text-text tracking-tight">
            Marginalia
          </Link>
          <div className="flex items-center gap-6">
            <NavLink href="/library">Libreria</NavLink>
            <NavLink href="/jam">Jam</NavLink>
            <NavLink href="/import">Importa</NavLink>
          </div>
        </div>
      </nav>

      <main className="flex-1 max-w-4xl mx-auto w-full px-4 py-8">
        {children}
      </main>
    </div>
  );
}

function NavLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="text-sm text-muted hover:text-text transition-colors"
    >
      {children}
    </Link>
  );
}
