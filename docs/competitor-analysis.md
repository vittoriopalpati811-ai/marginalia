# Competitor analysis — reading apps

Survey of the main competitors in the reading-tracker space, with explicit recommendations on what Marginalia should adopt, weighted against opinions from @diseaseofbooks_ TikTok (3 min, IT).

Last updated: 2026-05-27

---

## TL;DR — recommended additions to Marginalia

In priority order (highest ROI first):

1. **Reading goal annuale** (Goodreads/Fable/Storygraph) — already partially scaffolded in onboarding photos. **Build now.**
2. **Currently reading state** (every app has this) — onboarding photo 2 + persistent state on profile. **Build now.**
3. **Reading sessions with timer** (Bookly) — manual + auto entry, drives the stats page. **Build now.**
4. **Daily reading reminder** (Bookly) — local notification at user-chosen time. **Build after #3.**
5. **Barcode scanner** to add books (Storygraph/Goodreads) — camera + ISBN lookup. **Build after onboarding is shipped.**
6. **Genre tagging + stats** (Storygraph) — derive from book metadata, show in stats. **Build with stats page.**
7. **Public profile sharable URL** (Fable/Goodreads) — already partial in Marginalia (`/user/:id`). Just needs share button.

**Explicitly NOT recommended** (deliberate omissions):
- Star ratings (Goodreads/Fable) — Marginalia is about *what stuck with you*, not 5-star reviews. Highlights are the rating.
- Book clubs as separate construct (Fable) — Jams already cover this.
- Reading challenges with templates (Goodreads) — adds bloat; goal is enough.

---

## App-by-app review

### 1. Goodreads (Amazon)

**Strengths the creator highlights:**
- Most widespread (everyone has an account → easy to import/export)
- Massive book database with cover scanner

**Weaknesses (verbal + general):**
- UI is dated (2013-era)
- Owned by Amazon → conflict of interest
- Slow performance
- No real reading-habit metrics

**What Marginalia should steal:** the wide DB. We don't need to build one — we can use OpenLibrary or Google Books API for cover/metadata lookup when user adds a book manually.

**Differentiation:** our highlights focus + AI recommendations is a category Goodreads can't compete in.

---

### 2. Fable

**Strengths the creator highlights:**
- Beautiful interface (Gen-Z friendly aesthetic)
- Multiple statistics views
- Direct import from Kindle / Goodreads

**Weaknesses she calls out:**
- "Poco fornita" — limited book database (smaller than Goodreads)
- Recent monetization push

**What Marginalia should steal:**
- The **reading goal onboarding** UX (the screenshot you shared is Fable). Crisp, single-purpose, with reassuring copy ("Don't worry — you can always adjust later").
- The **currently-reading state at start of onboarding**. Sets up context for everything else.
- **Book clubs feature** — already overlaps with our Jams, but their UX is worth studying (active discussions, weekly prompts).

**Differentiation:** Our editorial Lora-serif aesthetic is more "literary" than Fable's bright pop look. Stick to that — it's what justifies €25/year.

---

### 3. Storygraph

**Strengths the creator highlights:**
- Well organized
- Direct import from Kindle / Goodreads
- Barcode scanner to add books
- Many statistics (mood, pace, genre, length)

**Weaknesses (general knowledge):**
- UI feels spreadsheet-ish (more data than narrative)
- Free tier is generous but premium ($50/year) overlaps with our pricing

**What Marginalia should steal:**
- **Barcode scanner** — easy win once we have camera permission. Lookup via OpenLibrary `/api/books?bibkeys=ISBN:xxx`.
- **Stats categories**: pages read over time, genres distribution, fastest reads, average length, mood breakdown. We should pick 4–5 of these and visualize them, not all.

**Differentiation:** Storygraph is for data nerds. Marginalia is for the literary aesthete. Our stats should feel **editorial**, not analytical: serif numbers, narrative captions ("You read 12% faster on Sundays"), not bar charts everywhere.

---

### 4. Bookly

**Strengths the creator highlights:**
- "Molto immediata" — fast to start using
- TANTE funzionalità — feature-rich
- Reading timer (frame: 00:00:01 counter, "Lettura...", pause button, page count 0/361)
- Daily reading reminder ("Promemoria — vi informeremo all'ora designata per buone abitudini di lettura", 08:00 picker)

**Weaknesses:**
- "Probabilmente svantaggio…" (she trails off — likely about price; Bookly is freemium with aggressive paywalls)

**What Marginalia should steal:**
- **Reading timer**: tap start when you sit down with a book, tap stop when you put it down. Logs a `reading_session` (start, end, duration, book_id, pages_read optional). Powers everything in the stats page.
- **Daily reminder**: simple local notification, "Hai 12 minuti per leggere oggi?" at the user's chosen time. Critical for retention.

**Differentiation:** Bookly's UI is functional but visually loud (lots of blue, glossy buttons, big timer). Ours should be quiet: a small timer chip in the book detail screen, expandable to fullscreen on tap, with a hushed monochrome counter.

---

## Features NOT in the video but worth considering

### Literal (older app, declining)
- Friend-based feed of currently-reading and highlights — we already do this via Jams
- *Skip*

### BookSloth (Gen-Z app)
- Genre quizzes for recommendations — interesting alternative to our AI recs
- Daily highlight reveal animation — we already have `_DailyCard`
- *Worth studying the visual style only*

### Readwise (most direct competitor for highlights)
- Spaced repetition of highlights via daily email — we should do this, in-app instead of email
- Highlight tagging / search by tag — solid feature, build later
- Mastery score per highlight — too complex for our positioning
- *Worth building: spaced repetition surfaced via widget (already partial) + push notification*

---

## Proposed roadmap impact

If we adopt these in the right order, the next 3 milestones look like:

**Milestone 1: Onboarding overhaul (1 week)**
- Annual reading goal screen
- Currently reading screen
- DB: `reading_goals`, `currently_reading` tables (the latter exists, formalize it)

**Milestone 2: Reading habit infrastructure (2 weeks)**
- Reading sessions (manual + timer)
- Daily reminder (local notification)
- DB: `reading_sessions` table
- Stats page v1: goal progress, streak, total pages, recent sessions

**Milestone 3: Stats deep dive + scanner (2 weeks)**
- Barcode scanner with OpenLibrary lookup
- Stats deep dive: genres, monthly chart, fastest reads, average length
- Genre auto-tagging via book metadata

After these, Marginalia has feature parity with all four competitors on the basics, while keeping our unique angle (Kindle highlights + AI + Jams + €25/year aesthetic premium).

---

## Sources
- @diseaseofbooks_ TikTok review (frame analysis from `Desktop/c1/frames*`)
- Personal knowledge of Goodreads, Fable, Storygraph, Bookly, Readwise as of 2026-05
- Fable onboarding screenshots provided by user
