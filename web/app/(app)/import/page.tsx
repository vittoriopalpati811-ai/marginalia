"use client";

import { useState, useRef } from "react";
import { createClient } from "@/lib/supabase/client";

type Status = "idle" | "uploading" | "parsing" | "done" | "error";

interface ImportResult {
  booksAdded: number;
  highlightsAdded: number;
  duplicatesSkipped: number;
}

export default function ImportPage() {
  const [status, setStatus] = useState<Status>("idle");
  const [result, setResult] = useState<ImportResult | null>(null);
  const [error, setError] = useState("");
  const [dragOver, setDragOver] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  async function handleFile(file: File) {
    if (!file.name.endsWith(".txt")) {
      setError("Seleziona un file .txt (My Clippings.txt)");
      return;
    }

    setStatus("uploading");
    setError("");
    setResult(null);

    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    // Create import record
    const { data: importRecord, error: insertError } = await supabase
      .from("clippings_imports")
      .insert({ user_id: user.id, file_path: null })
      .select("id")
      .single();

    if (insertError || !importRecord) {
      setStatus("error");
      setError("Errore creazione record import.");
      return;
    }

    // Upload file to Storage
    const filePath = `${user.id}/${importRecord.id}.txt`;
    const { error: uploadError } = await supabase.storage
      .from("clippings")
      .upload(filePath, file, { contentType: "text/plain" });

    if (uploadError) {
      setStatus("error");
      setError("Errore upload: " + uploadError.message);
      return;
    }

    // Update file path
    await supabase
      .from("clippings_imports")
      .update({ file_path: filePath })
      .eq("id", importRecord.id);

    setStatus("parsing");

    // Trigger Edge Function
    const { error: fnError } = await supabase.functions.invoke("parse-clippings", {
      body: { import_id: importRecord.id },
    });

    if (fnError) {
      setStatus("error");
      setError("Errore parsing: " + fnError.message);
      return;
    }

    // Poll for completion
    for (let i = 0; i < 30; i++) {
      await delay(1000);
      const { data: updated } = await supabase
        .from("clippings_imports")
        .select("status, books_added, highlights_added, duplicates_skipped")
        .eq("id", importRecord.id)
        .single();

      if (updated?.status === "done") {
        setResult({
          booksAdded: updated.books_added,
          highlightsAdded: updated.highlights_added,
          duplicatesSkipped: updated.duplicates_skipped,
        });
        setStatus("done");
        return;
      }
      if (updated?.status === "error") {
        setStatus("error");
        setError("Errore durante il parsing sul server.");
        return;
      }
    }

    setStatus("error");
    setError("Timeout. Riprova tra qualche minuto.");
  }

  function handleDrop(e: React.DragEvent) {
    e.preventDefault();
    setDragOver(false);
    const file = e.dataTransfer.files[0];
    if (file) handleFile(file);
  }

  return (
    <div className="max-w-lg mx-auto">
      <h1 className="font-serif text-2xl text-text mb-2">Importa highlight</h1>
      <p className="text-sm text-muted mb-8">
        Collega il Kindle al PC, apri il drive e trascina qui il file{" "}
        <code className="text-accent">My Clippings.txt</code>.
      </p>

      {/* Drop zone */}
      <div
        onClick={() => inputRef.current?.click()}
        onDrop={handleDrop}
        onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
        onDragLeave={() => setDragOver(false)}
        className={`
          border-2 border-dashed rounded-sm p-12 text-center cursor-pointer transition-colors
          ${dragOver ? "border-accent bg-accent/5" : "border-border hover:border-accent-light"}
          ${status === "uploading" || status === "parsing" ? "pointer-events-none opacity-60" : ""}
        `}
      >
        <input
          ref={inputRef}
          type="file"
          accept=".txt"
          className="hidden"
          onChange={(e) => e.target.files?.[0] && handleFile(e.target.files[0])}
        />

        {status === "idle" && (
          <>
            <p className="text-muted text-sm">Trascina qui il file</p>
            <p className="mt-1 text-xs text-muted">oppure clicca per selezionarlo</p>
          </>
        )}
        {status === "uploading" && <Spinner label="Upload in corso..." />}
        {status === "parsing" && <Spinner label="Analisi highlight..." />}
      </div>

      {/* Result */}
      {status === "done" && result && (
        <div className="mt-6 bg-surface border border-border rounded-sm p-5">
          <p className="text-sm font-medium text-text mb-3">Import completato</p>
          <div className="space-y-1 text-sm text-muted">
            <p>Libri: <span className="text-text">{result.booksAdded}</span></p>
            <p>Highlight nuovi: <span className="text-text">{result.highlightsAdded}</span></p>
            <p>Duplicati saltati: <span className="text-text">{result.duplicatesSkipped}</span></p>
          </div>
          <button
            onClick={() => { setStatus("idle"); setResult(null); }}
            className="mt-4 text-xs text-accent hover:underline"
          >
            Importa un altro file
          </button>
        </div>
      )}

      {/* Error */}
      {status === "error" && (
        <div className="mt-4 text-sm text-red-600">
          {error}{" "}
          <button onClick={() => setStatus("idle")} className="underline">Riprova</button>
        </div>
      )}

      {/* Instructions */}
      <div className="mt-10 text-xs text-muted space-y-2">
        <p className="font-medium text-muted">Come trovare il file:</p>
        <ol className="list-decimal list-inside space-y-1">
          <li>Collega il Kindle al PC tramite USB</li>
          <li>Apri il Kindle come drive (Esplora file o Finder)</li>
          <li>Il file è nella cartella root del Kindle: <code>My Clippings.txt</code></li>
        </ol>
        <p className="pt-2">
          Oppure usa lo{" "}
          <a href="/scripts/kindle-sync-README" className="text-accent hover:underline">
            script di sync automatico
          </a>{" "}
          per Windows / Mac.
        </p>
      </div>
    </div>
  );
}

function Spinner({ label }: { label: string }) {
  return (
    <div className="flex flex-col items-center gap-2">
      <div className="w-5 h-5 border-2 border-accent border-t-transparent rounded-full animate-spin" />
      <p className="text-xs text-muted">{label}</p>
    </div>
  );
}

function delay(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}
