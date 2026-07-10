# ──────────────────────────────────────────────────────────────────────────
# Scripta — deploya la Edge Function "recommend-books" aggiornata (Groq).
#
# PERCHE': Groq ha deprecato i vecchi modelli Llama (spenti il 16/08/2026).
# Il codice e' gia' aggiornato a "openai/gpt-oss-20b" nel repo; questa function
# va ri-deployata perche' la versione LIVE usa ancora il modello vecchio.
# (La funzione "pick-daily-highlight", quella della frase del giorno, l'ho gia'
#  aggiornata e VERIFICATA live io — questa e' l'unica rimasta.)
#
# Perche' lo fai TU e non io: deployare da qui legge il file da disco (nessun
# rischio di rovinare gli accenti), ma serve il TUO login Supabase — una
# credenziale che per sicurezza non gestisco al posto tuo.
#
# COME: tasto destro -> "Esegui con PowerShell" (oppure lancialo da terminale).
# Ti si aprira' il browser per il login Supabase la prima volta; poi deploya.
#
# NON URGENTE: i modelli vecchi funzionano fino al 16/08/2026, e intanto la
# sezione consigli degrada in modo pulito (non crasha). Ma meglio farlo presto.
# ──────────────────────────────────────────────────────────────────────────

Set-Location -Path $PSScriptRoot
$ref = "ibucvloawkfwobaelwbr"

Write-Host "1/2  Login Supabase (si apre il browser la prima volta)..." -ForegroundColor Cyan
npx --yes supabase login

Write-Host "2/2  Deploy di recommend-books dal file su disco..." -ForegroundColor Cyan
npx --yes supabase functions deploy recommend-books --project-ref $ref

Write-Host ""
Write-Host "Fatto. Se vedi 'Deployed Function recommend-books' sopra, e' tutto ok." -ForegroundColor Green
Write-Host "Se npx e' troppo lento a scaricare la CLI, dimmelo e ti do un'alternativa." -ForegroundColor Yellow
