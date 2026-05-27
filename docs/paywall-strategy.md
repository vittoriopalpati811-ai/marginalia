# Marginalia Premium — paywall strategy

Recommendation only. **No paywall gates implemented in the code.** Use this
to align before wiring `SubscriptionService.isPremium()` checks into the UI.

Pricing already set: **€19.99 / year** (per `paywallPrice` l10n key).

---

## Principle: paywall the rituals, not the data

Marginalia's pitch is "rediscover what you've read" — the highlights data
**belongs to the user** and must never sit behind a paywall. We charge for
*intelligence on top of that data* and for *social weight*.

Three buckets, in order of how I'd ship them:

---

### 🔒 BUCKET A — ship behind paywall from day one

**1. Unlimited highlights import**
- Free plan: cap at 100 highlights total (already documented in `paywallFreeTierHighlights`)
- Premium: unlimited
- Why: this is the strongest single conversion hook. Power users with 1k+ Kindle highlights will upgrade on day one. Free-plan users with <100 highlights still get the full experience and can convert later.
- **Implementation cost**: trivial — gate the import service with a count check.

**2. AI book recommendations (the "Picked for you" section)**
- Free plan: 1 batch of 3 recs every 7 days
- Premium: refresh on demand + 5 recs + reason text per book
- Why: this is the single most "magic" feature in the app — the WOW that converts. Capping refresh rate without removing entirely lets free users *see* what they're missing.
- Already partially supported by the existing `libraryRecommendationsProvider` cache.

**3. Reading stats deep dive**
- Free plan: goal + streak + this-month minutes (3 tiles)
- Premium: 12-month bar chart, genre breakdown, fastest reads, average length, mood, time-of-day patterns
- Why: stats are addictive once you have data. Free tier gives a taste, premium unlocks the rabbit hole.
- The whole stats screen is already built; gate just the deeper sections.

**4. iOS Home / Lock screen widget**
- Already documented in `paywallFeatureWidget` / `paywallFreeTierWidget`
- Why: widgets are an "out of app" presence — high perceived value, low marginal cost.

---

### 🔒 BUCKET B — add to paywall after launch (Month 2-3)

**5. Create & moderate unlimited Jams**
- Free: can join 1 Jam, view-only
- Premium: create unlimited Jams, moderate, set themes, polls, book-of-the-month
- Why: Jams are the social hook. Free users get pulled in by friends' invites; the *creators* (your most engaged users) pay for power.
- Already documented in `paywallFeatureJams` / `paywallFreeTierJams`.

**6. Direct messages**
- Free: read-only DMs, can reply to people who message you first
- Premium: initiate new conversations
- Why: classic LinkedIn-style asymmetric paywall — frictionless inbound, paid outbound. Drives social pressure without breaking the app.

**7. Personal book notes (the `book_notes` table)**
- Free: 3 books with notes
- Premium: unlimited notes + export
- Why: the kind of feature avid users pay for once they get hooked.

**8. Spaced-repetition daily highlight digest (push notification)**
- Free: weekly digest only
- Premium: daily, personalized timing, highlight-type filters
- Why: retention loop. The more it nudges them, the more they remember they paid.

---

### 🟢 BUCKET C — keep forever free

These build the funnel; charging for them kills network effects.

- **Kindle highlights import** (parser/Amazon sync) — the data is theirs
- **Search across all highlights** — basic discovery
- **Read / favorite / share highlights** — share = free marketing
- **Profile + follow / follower** — social graph growth
- **Public post on feed** (text + image) — user-generated content
- **Comment on others' posts** — engagement
- **Reading goal + currently-reading state** — base motivation loop
- **One reading session log per day** (free) — try-before-buy for the stats deep dive
- **One Jam join** — invite-driven activation
- **Sign in / sign up / account management** — table stakes
- **Onboarding** — must be free
- **Privacy controls + data export** — required by GDPR anyway

---

## Conversion mechanics

**Default upsell triggers** (where to show the paywall sheet):

| Trigger | Frequency | Conversion expectation |
|---|---|---|
| User hits 100-highlight free cap | Once | High — they've already invested |
| User opens "Picked for you" while throttled | Every 7d | Medium — visual reminder |
| User taps "create Jam" while free | Once per session | Medium |
| User taps "send message" to new person | Once per session | Low (DM is niche) |
| User opens stats deep-dive sections | Once per week | Medium |
| Day-30 in-app modal "Premium for 50% off" | Once | High |

Run a **7-day free trial** for first-time paywall hit. Standard mobile-app
mechanic; raises ARPU significantly.

---

## Pricing tiers — when to add

For now: single tier **Premium €19.99/year**. Don't fragment until you
hit 10k MAU. At that point consider:

- **Lite** (€9.99/yr) — unlimited highlights only, no AI / no widget
- **Premium** (€19.99/yr) — current tier
- **Marginalia for Book Clubs** (€49.99/yr) — for power Jam organizers,
  bulk-add members, custom branding, member analytics

---

## What I'd build NEXT before paywall flips on

1. **Onboarding paywall slide** — show Premium benefits at signup, "Try free for 7 days"
2. **Free-tier highlight counter** — chip "X / 100" on library screen so users *see* the limit approaching
3. **Smart upsell timing** — never show paywall during a creative action (e.g. mid-import), only after success states
4. **Subscription lifecycle UI** — manage / cancel / view receipt screens
5. **Server-side entitlement check** — don't trust client; query RevenueCat from edge function before serving AI recs

These are all paywall-adjacent and need to ship before the gates actually
turn on.

---

Last updated: 2026-05-27. No paywall checks in code yet.
