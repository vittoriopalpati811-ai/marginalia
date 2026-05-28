#!/usr/bin/env python3
"""
Generate a realistic My Clippings.txt with 1000 highlights spread over
the last 12 months, weighted heavily toward the last 60 days so the
"this month" stats actually show data.

Output: assets/demo/My Clippings.txt
"""
import random
import datetime
from pathlib import Path

random.seed(42)  # deterministic for reproducible demo data

# ─── Books (40 mostly Italian + international classics & nonfiction) ─────────

BOOKS = [
    ("Il Nome della Rosa", "Umberto Eco"),
    ("Il Pendolo di Foucault", "Umberto Eco"),
    ("Se questo è un uomo", "Primo Levi"),
    ("La tregua", "Primo Levi"),
    ("Il sistema periodico", "Primo Levi"),
    ("Il Gattopardo", "Giuseppe Tomasi di Lampedusa"),
    ("La Coscienza di Zeno", "Italo Svevo"),
    ("Uno, nessuno e centomila", "Luigi Pirandello"),
    ("Le città invisibili", "Italo Calvino"),
    ("Il barone rampante", "Italo Calvino"),
    ("Lessico famigliare", "Natalia Ginzburg"),
    ("Le otto montagne", "Paolo Cognetti"),
    ("La solitudine dei numeri primi", "Paolo Giordano"),
    ("L'amica geniale", "Elena Ferrante"),
    ("1984", "George Orwell"),
    ("La fattoria degli animali", "George Orwell"),
    ("Mrs Dalloway", "Virginia Woolf"),
    ("Il vecchio e il mare", "Ernest Hemingway"),
    ("Cent'anni di solitudine", "Gabriel Garcia Marquez"),
    ("Il Maestro e Margherita", "Michail Bulgakov"),
    ("Anna Karenina", "Lev Tolstoj"),
    ("Delitto e castigo", "Fedor Dostoevskij"),
    ("Il Grande Gatsby", "Francis Scott Fitzgerald"),
    ("Sulla strada", "Jack Kerouac"),
    ("Il giovane Holden", "Jerome David Salinger"),
    ("Sapiens. Da animali a dèi", "Yuval Noah Harari"),
    ("Homo Deus", "Yuval Noah Harari"),
    ("Pensieri lenti e veloci", "Daniel Kahneman"),
    ("Atomic Habits", "James Clear"),
    ("Antifragile", "Nassim Nicholas Taleb"),
    ("Il cigno nero", "Nassim Nicholas Taleb"),
    ("Meditazioni", "Marco Aurelio"),
    ("Lettere a Lucilio", "Seneca"),
    ("Cosmos", "Carl Sagan"),
    ("Breve storia del tempo", "Stephen Hawking"),
    ("L'eleganza del riccio", "Muriel Barbery"),
    ("La verità sul caso Harry Quebert", "Joël Dicker"),
    ("Open", "Andre Agassi"),
    ("Educata", "Tara Westover"),
    ("Stoner", "John Williams"),
]

# ─── Quote pool — ~160 literary fragments (Italian) ──────────────────────────
# Mix of original phrasings inspired by real literature + common philosophical
# observations. Not exact quotes (to avoid copyright); style matches Kindle
# highlights of careful readers.

QUOTES = [
    "Il tempo non è una linea ma un dimensione: esiste solo perché ce ne ricordiamo.",
    "Si vive con quello che si riceve, ma si ha una vita per quello che si dà.",
    "Ogni separazione è un anticipo di morte, ogni incontro un anticipo della resurrezione.",
    "Le parole non sono lo strumento della verità. Sono lo strumento della menzogna.",
    "I libri non si fanno per crederci, ma per essere sottoposti a indagine.",
    "Forse il nostro compito è imparare a perdere bene.",
    "La memoria non è ciò che ricordiamo, ma quello che ci ricorda.",
    "Tutto cambia perché nulla cambi.",
    "Il dolore non si comunica, si attraversa.",
    "La felicità non è uno stato ma una direzione.",
    "Chi pensa solo a sé stesso non sa cosa pensa.",
    "La libertà non è uno spazio libero, libero non è uno spazio.",
    "Si scrive per non morire, anche se si sa che si morirà comunque.",
    "Il viaggio non finisce mai. Solo i viaggiatori finiscono.",
    "Ogni vita è insufficiente per quella di un altro.",
    "L'inferno dei viventi non è qualcosa che sarà; se ce n'è uno, è quello che è già qui.",
    "Le città sono come i sogni: tutto l'immaginabile può essere sognato.",
    "Il futuro è già qui, è solo distribuito in modo non uniforme.",
    "La saggezza non è altro che vedere le cose come sono.",
    "Vivere è la cosa più rara al mondo. La maggior parte delle persone esiste, e basta.",
    "Si invecchia molto in fretta nei luoghi dove si è felici.",
    "Non si guarisce dall'infanzia. Si impara solo a portarsela addosso.",
    "Ciò che siamo è il risultato di quello che abbiamo pensato.",
    "La paura è figlia di una scarsa attenzione al presente.",
    "Non esistono fatti, esistono solo interpretazioni.",
    "Un libro che non ci scuote, perché lo leggiamo?",
    "Una conversazione vale dieci anni di studio dei libri.",
    "Vivere è la cosa più rara al mondo.",
    "La lettura è una conversazione con i più grandi uomini del passato.",
    "Le idee che sopravvivono sono quelle che resistono al gelo dell'inverno.",
    "Tutto ciò che avviene una volta non avviene mai. Tutto ciò che avviene due volte avverrà inevitabilmente una terza.",
    "Senza la musica la vita sarebbe un errore.",
    "Ciò che non ti uccide ti rende più forte, ma anche più stanco.",
    "L'uomo è la misura di tutte le cose.",
    "La pazienza è il coraggio del filosofo.",
    "Le abitudini sono ciò che permette al genio di esistere.",
    "Non si può non comunicare.",
    "L'inferno sono gli altri solo quando ci dimentichiamo di noi stessi.",
    "Per essere veramente liberi, bisogna prima essere veramente soli.",
    "Le grandi vite non si fanno per grandi gesti, ma per migliaia di piccoli accordi.",
    "Le parole sono il vero corpo dei nostri pensieri.",
    "Si comincia a invecchiare quando si sostituiscono i sogni con i ricordi.",
    "La gratitudine cambia ciò che abbiamo in ciò che basta.",
    "L'arte è la menzogna che ci permette di vedere la verità.",
    "L'amore non si comanda; si sceglie ogni giorno.",
    "Ogni uomo deve decidere se camminerà nella luce dell'altruismo creativo o nelle tenebre dell'egoismo distruttivo.",
    "Le risposte cambiano, le domande no.",
    "Il silenzio è la lingua di Dio. Tutto il resto è cattiva traduzione.",
    "Vivere è soffrire, sopravvivere è trovare un significato nella sofferenza.",
    "La maggior parte delle persone vive una vita di silenziosa disperazione.",
    "L'unica cosa che davvero ci appartiene è il modo in cui spendiamo il nostro tempo.",
    "Quello che facciamo nella vita riecheggia nell'eternità.",
    "Le scelte mostrano chi siamo, molto più delle nostre capacità.",
    "Ciò che è essenziale è invisibile agli occhi.",
    "Si vede bene solo col cuore. L'essenziale è invisibile agli occhi.",
    "Chi domina sé stesso non ha bisogno di dominare il mondo.",
    "La vita è ciò che ti accade mentre fai progetti.",
    "Non importa quanto vai piano, l'importante è non fermarsi.",
    "La conoscenza è potere, ma il carattere è di più.",
    "Le persone non si ricordano di ciò che dici; si ricordano di come le hai fatte sentire.",
    "Non tutti quelli che vagano sono persi.",
    "Le piccole cose, le occasioni quotidiane, sono il nostro vero terreno.",
    "Un pessimista vede la difficoltà in ogni opportunità; un ottimista vede l'opportunità in ogni difficoltà.",
    "Anche un viaggio di mille miglia comincia con un singolo passo.",
    "Il modo migliore per predire il futuro è inventarlo.",
    "Non c'è vento favorevole per il marinaio che non sa dove andare.",
    "Conosci te stesso. È l'unica vera ricchezza.",
    "Vive bene chi vive in modo da poter morire con onestà.",
    "L'unica costante è il cambiamento.",
    "La pace non è l'assenza di guerra. È una virtù.",
    "Quando il maestro è pronto, l'allievo appare.",
    "Quando l'allievo è pronto, il maestro appare.",
    "Coraggio non è assenza di paura, ma il giudizio che qualcosa è più importante della paura.",
    "Il successo è una pessima maestra. Seduce le persone intelligenti a pensare di non poter perdere.",
    "Esercitate la solitudine: troverete che è un'arte come un'altra.",
    "Le abitudini formano il carattere, e il carattere il destino.",
    "Niente è particolarmente difficile se lo divido in piccoli lavori.",
    "Concentrati sul processo, non sull'evento.",
    "Si diventa quel che si fa ripetutamente.",
    "L'eccellenza non è un atto, ma un'abitudine.",
    "Le parole sono i nemici della verità.",
    "Chi non legge, a settant'anni avrà vissuto una sola vita: la propria.",
    "Chi legge avrà vissuto cinquemila anni: c'era quando Caino uccise Abele.",
    "Il vero viaggio di scoperta non consiste nel cercare nuove terre, ma nell'avere occhi nuovi.",
    "Lavora sulla tua mente, non sul mondo. Il mondo cambia da sé.",
    "Tutto quello che sei oggi è il risultato delle tue scelte di ieri.",
    "Non esistono problemi, solo situazioni da osservare.",
    "Le pause sono parte della musica.",
    "Si insegna meglio ciò che si è desiderato imparare di più.",
    "La gentilezza è un linguaggio che il sordo può udire e il cieco può vedere.",
    "Più ne sai, più sai di non sapere.",
    "Niente è impossibile per l'uomo che non deve farlo lui stesso.",
    "Crediamo a quello che vediamo perché vediamo quello in cui crediamo.",
    "Una mente cresce nuova mai più ritorna alla sua dimensione originale.",
    "Lo scopo della vita è una vita di scopo.",
    "Non sprecate tempo a litigare su come dovrebbe essere un uomo buono. Siatelo.",
    "L'ostacolo è la via.",
    "Hai potere sulla tua mente, non sugli eventi esterni. Realizzalo, e troverai la forza.",
    "La nostra vita è ciò che i nostri pensieri ne fanno.",
    "Sopporta e rinuncia.",
    "Se vuoi un futuro diverso, devi creare un presente diverso.",
    "Possiedi solo ciò che non puoi perdere in un naufragio.",
    "Vivi come se dovessi morire domani. Impara come se dovessi vivere per sempre.",
    "Felicità non significa che tutto sia perfetto. Significa che hai deciso di guardare oltre le imperfezioni.",
    "Solo coloro che osano fallire grandemente possono raggiungere grandemente.",
    "La vita comincia alla fine della tua zona di comfort.",
    "Il viaggio di mille miglia inizia con un passo.",
    "L'unica persona che sei destinato a diventare è la persona che decidi di essere.",
    "Tra lo stimolo e la risposta c'è uno spazio. In quello spazio è il nostro potere di scegliere la risposta.",
    "Non possiamo dirigere il vento, ma possiamo regolare le vele.",
    "Le radici dell'educazione sono amare, ma i frutti sono dolci.",
    "Chi cerca di evitare ogni rischio finisce per correre il rischio peggiore: quello di non aver mai vissuto davvero.",
    "Ciò che ottieni raggiungendo i tuoi obiettivi non è importante quanto ciò che diventi raggiungendoli.",
    "Il sogno di chi crede nei sogni non finisce mai.",
    "Sappi distinguere ciò che dipende da te da ciò che non dipende da te.",
    "Tutti i tramonti sono diversi, e tutti uguali. Come gli uomini.",
    "Il dolore è inevitabile. La sofferenza è una scelta.",
    "Il modo migliore per uscire da un problema è attraversarlo.",
    "La vita non ha un significato. Tu glielo dai.",
    "Le difficoltà rivelano il carattere, non lo creano.",
    "L'ottimismo è una forma intelligente di coraggio.",
    "Non smettere mai di imparare, perché la vita non smette mai di insegnare.",
    "Chi semina vento raccoglie tempesta.",
    "Saper aspettare è il segreto di chi sa vivere.",
    "L'arte di vivere consiste nel non rovinare il presente coi rimpianti del passato o coi timori del futuro.",
    "La vera scoperta non consiste nel trovare nuove terre, ma nell'avere occhi nuovi.",
    "I tempi difficili creano uomini forti. Gli uomini forti creano tempi belli.",
    "Il fallimento è solo l'opportunità di ricominciare in modo più intelligente.",
    "Il modo in cui passiamo i nostri giorni è ovviamente il modo in cui passiamo le nostre vite.",
    "La distanza tra i sogni e la realtà si chiama disciplina.",
    "Solo chi rischia di andare troppo lontano scopre fino a dove si può andare.",
    "Le cose semplici sono le più rare a trovarsi e le più difficili da fare.",
    "Il dubbio è il principio della saggezza.",
    "Più studio le persone, più amo il mio cane.",
    "Il presente è il dono che diamo a noi stessi quando smettiamo di rimpiangere il passato.",
    "Si insegna ciò che si è, e si è ciò che si insegna.",
    "Non è l'altezza a fare un uomo, ma il modo in cui lo ha attraversato.",
    "Le grandi anime hanno volontà, le deboli hanno solo desideri.",
    "Il viaggio importante non è esterno; è quello che fai dentro.",
    "Non aspettare il momento giusto. Crealo.",
    "Ogni uomo è la somma delle sue scelte.",
    "Vivere senza filosofare è propriamente come tenere gli occhi chiusi senza tentar mai di aprirli.",
    "L'arte non è quello che vedi, ma quello che fai vedere agli altri.",
    "La pazienza è amara, ma i suoi frutti sono dolci.",
    "Ogni risposta porta una nuova domanda.",
    "Il talento ti porta dove la fortuna ti consente.",
    "Non rimandare a domani ciò che puoi fare oggi.",
    "Conoscere è una virtù attiva; non aspetta la verità, la cerca.",
    "Il rispetto si conquista, non si pretende.",
    "Non c'è vento più contrario di quello del proprio destino.",
    "La pioggia non rovina la giornata: la cambia.",
    "Il sapere è come un'arma: chi non la sa usare si fa male.",
    "Il successo non è la chiave della felicità. La felicità è la chiave del successo.",
    "L'eccezione conferma la regola.",
    "Ci vogliono anni per costruire una buona reputazione, ma bastano cinque minuti per rovinarla.",
    "Saper ascoltare è una delle più grandi arti della vita.",
    "La vera sapienza è sapere quello che non si sa.",
    "Il merito principale di un'idea è di farne nascere altre.",
    "Si finisce sempre per somigliare alle persone con cui passiamo il tempo.",
    "L'eternità è innamorata delle opere del tempo.",
    "Si scrive per essere amati, si è amati per come si scrive.",
    "Le idee che si nutrono di se stesse sono le più potenti.",
    "L'arte di vivere è più simile a quella della lotta che a quella della danza.",
    "Tutto fluisce, niente è permanente.",
    "Il fiume in cui entri non è lo stesso, e tu non sei lo stesso uomo.",
    "Si tace per non distruggere ciò che le parole hanno costruito.",
    "Ogni cosa ha un suo tempo, e ogni tempo ha le sue cose.",
    "Le emozioni che proviamo per la prima volta ci abitano per sempre.",
    "Il tempo che ci sembra perso è spesso il più prezioso.",
    "La nostalgia non è solo il dolore del ritorno: è la consapevolezza di non poter tornare.",
]

# ─── Date distribution ──────────────────────────────────────────────────────
# Today's reference. Weighted toward recent so "this month" stats populate.
TODAY = datetime.datetime(2026, 5, 28, 0, 0, 0)


def random_date():
    """Returns a datetime weighted heavily toward the last 60 days."""
    # 35% in last 30 days (THIS MONTH heavy)
    # 25% in 30-90 days ago
    # 25% in 90-180 days ago
    # 10% in 180-365 days ago
    # 5% older
    bucket = random.random()
    if bucket < 0.35:
        days_ago = random.randint(0, 30)
    elif bucket < 0.60:
        days_ago = random.randint(30, 90)
    elif bucket < 0.85:
        days_ago = random.randint(90, 180)
    elif bucket < 0.95:
        days_ago = random.randint(180, 365)
    else:
        days_ago = random.randint(365, 730)

    base = TODAY - datetime.timedelta(days=days_ago)
    # Random hour/minute/second during the day — bias toward evening reading
    hour = random.choices(
        list(range(24)),
        weights=[1, 1, 1, 1, 1, 1, 2, 3, 3, 2, 2, 2, 3, 3, 3, 3, 4, 5, 8, 12, 14, 14, 10, 4],
    )[0]
    minute = random.randint(0, 59)
    second = random.randint(0, 59)
    return base.replace(hour=hour, minute=minute, second=second)


WEEKDAYS_EN = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
MONTHS_EN   = ["January", "February", "March", "April", "May", "June",
               "July", "August", "September", "October", "November", "December"]


def kindle_date(dt: datetime.datetime) -> str:
    """Kindle US-locale date string: 'Friday, May 28, 2026 7:42:15 PM'."""
    wd = WEEKDAYS_EN[dt.weekday()]
    mo = MONTHS_EN[dt.month - 1]
    h12 = dt.hour % 12
    if h12 == 0:
        h12 = 12
    ampm = "AM" if dt.hour < 12 else "PM"
    return f"{wd}, {mo} {dt.day}, {dt.year} {h12}:{dt.minute:02d}:{dt.second:02d} {ampm}"


# ─── Generation ─────────────────────────────────────────────────────────────

def generate(n: int) -> str:
    """Build the .txt body with `n` highlights."""
    entries = []
    # Pre-allocate "book schedule": some books get more highlights, some less.
    # Skewed Pareto distribution so the user has ~10 "heavily-highlighted"
    # books + a long tail of lightly-annotated ones.
    book_weights = [random.paretovariate(1.5) for _ in BOOKS]
    total_w = sum(book_weights)
    book_quotas = [int(round(w / total_w * n)) for w in book_weights]
    # Top up to exactly `n`
    while sum(book_quotas) < n:
        book_quotas[random.randint(0, len(BOOKS) - 1)] += 1
    while sum(book_quotas) > n:
        idx = random.randint(0, len(BOOKS) - 1)
        if book_quotas[idx] > 0:
            book_quotas[idx] -= 1

    used = []  # (book_idx, datetime, location, quote)
    for book_idx, quota in enumerate(book_quotas):
        for _ in range(quota):
            dt = random_date()
            # Location numbers grow with read order; pretend they're page-like.
            loc_start = random.randint(50, 7800)
            loc_end   = loc_start + random.randint(0, 3)
            quote = random.choice(QUOTES)
            used.append((book_idx, dt, loc_start, loc_end, quote))

    # Sort by date so the file reads like an actual chronological export
    used.sort(key=lambda t: t[1])

    for book_idx, dt, ls, le, quote in used:
        title, author = BOOKS[book_idx]
        loc_range = f"{ls}-{le}" if le > ls else f"{ls}"
        entries.append(
            f"{title} ({author})\n"
            f"- Your Highlight on Location {loc_range} | Added on {kindle_date(dt)}\n"
            f"\n"
            f"{quote}\n"
            f"=========="
        )

    return "\n".join(entries) + "\n"


# ─── Write ──────────────────────────────────────────────────────────────────

def main():
    repo_root = Path(__file__).resolve().parent.parent
    out_path  = repo_root / "assets" / "demo" / "My Clippings.txt"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    content = generate(1000)
    # Kindle exports use a BOM + UTF-8.
    out_path.write_bytes(b"\xef\xbb\xbf" + content.encode("utf-8"))

    # Sanity check
    blocks = content.count("==========")
    print(f"Wrote {out_path}")
    print(f"  highlights: {blocks}")
    print(f"  size: {out_path.stat().st_size:,} bytes")
    # Date span
    dates = []
    for line in content.splitlines():
        if line.startswith("- Your Highlight on Location"):
            # e.g. "... | Added on Friday, May 28, 2026 7:42:15 PM"
            try:
                tail = line.split("| Added on ", 1)[1].strip()
                dates.append(tail)
            except IndexError:
                pass
    print(f"  oldest: {dates[0] if dates else 'n/a'}")
    print(f"  newest: {dates[-1] if dates else 'n/a'}")


if __name__ == "__main__":
    main()
