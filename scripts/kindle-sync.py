#!/usr/bin/env python3
"""
Marginalia Kindle Sync — Windows / macOS
Rileva automaticamente il Kindle collegato via USB e carica My Clippings.txt
su Supabase. La Edge Function parse-clippings si occupa del parsing.

Uso:
  1. pip install -r requirements.txt
  2. Copia .env.example in .env e compilalo
  3. python kindle-sync.py

Su Windows: gira in background. Collega il Kindle e aspetta il messaggio.
Su Mac: stessa cosa, funziona allo stesso modo.
"""

import os
import sys
import time
import uuid
import hashlib
from datetime import datetime
from pathlib import Path

try:
    import psutil
except ImportError:
    sys.exit("Errore: installa le dipendenze con: pip install -r requirements.txt")

try:
    from supabase import create_client, Client
except ImportError:
    sys.exit("Errore: installa le dipendenze con: pip install -r requirements.txt")

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent / ".env")
except ImportError:
    pass  # dotenv opzionale, le variabili possono essere già nell'ambiente


SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")  # service role per bypass RLS
SUPABASE_USER_ID = os.environ.get("SUPABASE_USER_ID", "")       # il tuo user ID da Supabase

KINDLE_FILENAME = "My Clippings.txt"
POLL_INTERVAL_SECONDS = 5


def log(msg: str):
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}")


def find_kindle() -> Path | None:
    """Cerca My Clippings.txt su tutti i drive montati."""
    for partition in psutil.disk_partitions(all=False):
        candidate = Path(partition.mountpoint) / KINDLE_FILENAME
        if candidate.exists() and candidate.is_file():
            return candidate
    return None


def file_hash(path: Path) -> str:
    """SHA-256 del file per rilevare cambiamenti."""
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def upload_and_trigger(supabase: Client, clippings_path: Path) -> bool:
    """Carica il file su Storage e triggera la Edge Function di parsing."""
    if not SUPABASE_USER_ID:
        log("ERRORE: SUPABASE_USER_ID non configurato nel .env")
        return False

    import_id = str(uuid.uuid4())
    file_path = f"{SUPABASE_USER_ID}/{import_id}.txt"

    log(f"Upload di {clippings_path} → {file_path}")

    # Crea record import
    supabase.table("clippings_imports").insert({
        "id": import_id,
        "user_id": SUPABASE_USER_ID,
        "file_path": file_path,
        "status": "pending",
    }).execute()

    # Upload file
    with open(clippings_path, "rb") as f:
        content = f.read()

    try:
        supabase.storage.from_("clippings").upload(
            file_path,
            content,
            {"content-type": "text/plain; charset=utf-8"},
        )
    except Exception as e:
        log(f"ERRORE upload: {e}")
        supabase.table("clippings_imports").update({
            "status": "error",
            "error_message": str(e),
        }).eq("id", import_id).execute()
        return False

    log("Upload completato. Avvio parsing server-side...")

    # Triggera Edge Function
    try:
        result = supabase.functions.invoke(
            "parse-clippings",
            invoke_options={"body": {"import_id": import_id}},
        )
        log(f"Edge Function risposta: {result}")
    except Exception as e:
        log(f"ERRORE Edge Function: {e}")
        return False

    # Polling risultato
    for _ in range(60):
        time.sleep(2)
        row = (
            supabase.table("clippings_imports")
            .select("status, highlights_added, books_added, duplicates_skipped, error_message")
            .eq("id", import_id)
            .single()
            .execute()
        )
        data = row.data
        if data["status"] == "done":
            log(
                f"✓ Import completato: {data['highlights_added']} nuovi highlight, "
                f"{data['books_added']} libri, {data['duplicates_skipped']} duplicati saltati."
            )
            return True
        if data["status"] == "error":
            log(f"ERRORE parsing: {data.get('error_message')}")
            return False

    log("Timeout: il server non ha risposto in 120s.")
    return False


def main():
    if not SUPABASE_URL or not SUPABASE_KEY:
        sys.exit(
            "ERRORE: configura SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY nel file .env\n"
            "Vedi scripts/.env.example"
        )

    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

    log("Marginalia Kindle Sync avviato. In attesa del Kindle...")
    log(f"Cerco '{KINDLE_FILENAME}' su tutti i drive ogni {POLL_INTERVAL_SECONDS}s.")
    log("Premi Ctrl+C per uscire.")
    print()

    last_seen_hash: str | None = None

    while True:
        try:
            kindle_path = find_kindle()

            if kindle_path:
                current_hash = file_hash(kindle_path)
                if current_hash != last_seen_hash:
                    log(f"Kindle rilevato: {kindle_path}")
                    success = upload_and_trigger(supabase, kindle_path)
                    if success:
                        last_seen_hash = current_hash
                        log("Sync completato. In attesa di modifiche future...")
                    else:
                        log("Sync fallito. Riproverò al prossimo rilevamento.")
                        last_seen_hash = None  # riprova
            else:
                if last_seen_hash is not None:
                    log("Kindle scollegato.")
                    last_seen_hash = None

            time.sleep(POLL_INTERVAL_SECONDS)

        except KeyboardInterrupt:
            log("Uscita.")
            break
        except Exception as e:
            log(f"Errore inatteso: {e}")
            time.sleep(POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    main()
