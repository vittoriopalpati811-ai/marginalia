"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<"idle" | "loading" | "sent" | "error">("idle");
  const [errorMessage, setErrorMessage] = useState("");

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setStatus("loading");
    setErrorMessage("");

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`,
      },
    });

    if (error) {
      setStatus("error");
      setErrorMessage(error.message);
    } else {
      setStatus("sent");
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center px-4">
      <div className="w-full max-w-sm">
        {/* Logo */}
        <div className="mb-10 text-center">
          <h1 className="font-serif text-3xl text-text tracking-tight">Marginalia</h1>
          <p className="mt-2 text-sm text-muted">Riscopri i tuoi highlight Kindle</p>
        </div>

        {status === "sent" ? (
          <div className="bg-surface border border-border rounded-sm p-6 text-center">
            <p className="text-sm text-text">
              Controlla la tua email.
            </p>
            <p className="mt-1 text-sm text-muted">
              Abbiamo inviato un link magico a <strong>{email}</strong>.
            </p>
            <button
              onClick={() => setStatus("idle")}
              className="mt-4 text-xs text-accent hover:underline"
            >
              Usa un'altra email
            </button>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label htmlFor="email" className="block text-xs text-muted mb-1.5">
                Email
              </label>
              <input
                id="email"
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="tu@esempio.com"
                className="w-full bg-surface border border-border rounded-sm px-3 py-2.5 text-sm text-text placeholder:text-muted focus:outline-none focus:border-accent transition-colors"
              />
            </div>

            {status === "error" && (
              <p className="text-xs text-red-600">{errorMessage}</p>
            )}

            <button
              type="submit"
              disabled={status === "loading"}
              className="w-full bg-accent hover:bg-accent/90 text-bg rounded-sm py-2.5 text-sm font-medium transition-colors disabled:opacity-50"
            >
              {status === "loading" ? "Invio..." : "Continua con email"}
            </button>

            <p className="text-center text-xs text-muted">
              Nessuna password. Ti inviamo un link di accesso.
            </p>
          </form>
        )}
      </div>
    </div>
  );
}
