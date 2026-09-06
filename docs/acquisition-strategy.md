# Acquisition Strategy — how GymStreak gets seen

**Status (2026-09-06):** Phase A in progress — lever #1 shipped, #2 and #3 cut as tickets and not
yet started. Per-lever status lives in the §3 table and is restated at the top of each §4 entry.

**This file is the single source of truth for acquisition — strategy *and* progress.** Tickets are
cut from it into `.scratch/acquisition-phase-a/issues/` and are transient; this document is not.
**When a ticket derived from a lever reaches `done`, record it here in the same change:** set the
lever's row in the §3 table, put a `**Shipped** (date)` line at the top of its §4 entry, correct any
statement the implementation proved wrong (rewrite it, never append a correction), and update §5 and
§6 if the phase or a milestone moved. A lever whose ticket is done but whose row still reads
"not started" makes this document worse than no document.

**Why this document exists.** `docs/monetization-strategy.md` §13 established that the paywall is
not the problem — **the app reaches almost nobody**. That makes acquisition the only input to
revenue that can currently be moved, and it is a different discipline from gating, pricing and
feature depth, so it gets its own file. Read §13 first for the evidence; this document assumes it.

---

## 1. The situation, in numbers

Measured 2026-09-06 (App Store Connect 7 Jun – 4 Sep; RevenueCat REST API):

| | Value | |
|---|---|---|
| **Impressionen** | **1,150 / 90 days ≈ 13/day** | The top of the funnel. Everything else is downstream. |
| Produktseitenaufrufe | 180 | 15.7% of impressions |
| **Erstmalige Downloads** | **36** | 20% of page views — a *healthy* listing |
| Chargeable installs since the paywall | ~12 | §13.1 |
| Active subscriptions / MRR | **0 / $0** | The one trial was cancelled; lapses 2026-09-10 |

**Source split** (product page views, daily average): App Store Search ≈ 1/day; Browse a thin
secondary from July; App-Referrer first appears in September; **Web-Referrer zero for ninety days.**

**Geography:** 62% DE, 28% US, 3% GB (n=100 RevenueCat customers).

### The three things this tells us

1. **The listing converts fine.** 20% page-view→download is healthy, and the 2026-08-25 ASO pass
   lifted conversion +110%. Do not spend effort rewriting the description — that half works.
2. **Reach is the whole problem.** Impressions *fell* 6.75% over the same period the conversion
   rate doubled. The ASO pass sharpened relevance without buying reach.
3. **Acquisition is the only lever on revenue, permanently.** §7's Founder grant is irrevocable, so
   the pre-2026-08-25 base can never be charged. Revenue is a function of *future installs alone*.

### What is NOT the problem (do not re-litigate)

- **The paywall machinery.** Nine placements, six gates, Customer Center, a proven production
  purchase (`environment: production`, §13.3). It works; nobody sees it.
- **The product.** 1,083 localized strings, a standalone watch app, on-device AI, supersets,
  CloudKit sync. This is a mature app with an audience of thirteen impressions a day.
- **Pricing.** Untestable at this volume and not the constraint.

---

## 2. What ranking actually depends on

Prioritization below follows from how the App Store decides to show an app at all:

- **Keyword surface.** You are only impressible for terms you are indexed on. Indexed fields are
  App Name (~30 chars), Subtitle (30), Keyword field (100, private) — **per storefront localization**.
  More localizations = more keyword fields = more impressions. This is the most mechanical lever.
- **Ranking within a term.** Driven substantially by **download velocity**, **conversion rate**, and
  **ratings volume + average**. Two of those three we currently do nothing about.
- **Browse/featuring surfaces.** Editorial and algorithmic. In-App Events and Custom Product Pages
  feed them; you cannot buy them.
- **Off-store traffic.** Doesn't add impressions directly, but adds downloads — and download
  velocity feeds ranking, so external traffic compounds back into organic reach.

**The strategic consequence: stop competing on head terms.** "workout tracker" belongs to Hevy and
Strong. GymStreak has two genuinely defensible niches with real search intent and almost no
competition:

- **Apple Watch.** A complete, free, standalone watch app. Strong paywalls theirs and is widely
  criticized for it (`monetization-strategy.md` §5). "apple watch gym tracker", "workout tracker
  watch standalone".
- **Privacy / no account / offline.** "workout tracker no account", "offline gym log", "kein konto".
  Nobody optimizes for these and the intent is high.

Every lever below should be pointed at those two niches, not at the head.

---

## 3. Prioritized levers

Ranked by expected impressions gained ÷ effort, with dependencies respected.

| # | Lever | Tier | Effort | Moves | Status |
|---|---|---|---|---|---|
| 1 | Rating prompt in-app | **P0** | ~1 day | Ranking | ✅ **shipped 2026-09-06** — `docs/rating-prompt.md` |
| 2 | Storefront metadata localization (no app translation) | **P0** | 1–2 days/locale | **Keyword surface** | 🎫 ticket cut (`03-en-gb-en-au-metadata-localizations`) |
| 3 | Niche keyword repositioning (Watch + privacy) | **P0** | ~1 day | Keyword surface | 🎫 ticket cut (`02-niche-keyword-rotation`) |
| 4 | Landing page + custom domain | **P1** | 1–2 weeks | Unlocks every off-store channel | ⬜ not started |
| 5 | In-app sharing of a workout | **P1** | 2–3 days | Web-Referrer, virality | ⬜ not started |
| 6 | Community presence (Reddit et al.) | **P1** | Ongoing | Downloads → velocity → ranking | ⬜ not started |
| 7 | In-App Events | **P2** | ~1 day/event | Browse + Search surfaces | ⬜ not started |
| 8 | Custom Product Pages | **P2** | ~1 day | Conversion on off-store traffic | ⬜ not started |
| 9 | Full app localization, 2–3 markets | **P3** | 1–2 weeks/language | Keyword surface + market fit | ⬜ blocked on `.scratch/i18n-foundation/` |
| 10 | Apple Search Ads | **P3 / optional** | Money | Impressions, and keyword data | ⬜ not started |

Status vocabulary: ⬜ not started · 🎫 ticket cut, not started · 🚧 in progress · ✅ shipped (date) ·
❌ dropped (with the reason in the §4 entry).

---

## 4. How to act on each

### 1. Rating prompt (P0)

**Why first:** ratings volume and average are direct inputs to search ranking, it compounds, and it
is the cheapest item on this page. Before this shipped there was **no `requestReview()` call anywhere
in the app** — only a manual "write a review" universal link in Settings (`SupportLinks.writeReview`),
which almost nobody will find. With ~85 real users the rating count was necessarily tiny.

**Shipped** (2026-09-06). `RequestReviewAction` via `@Environment(\.requestReview)`, fired once ever,
automatically, on the **5th completed workout**. Full mechanism, API research and Apple's throttling
semantics: `docs/rating-prompt.md`.

- **The trigger is the 5th completed workout — not the 3rd, and not a personal record.** Both of the
  options this section originally proposed were wrong for this codebase:
  - **The 3rd is already taken.** `ProactivePaywallTrigger.valueMomentWorkoutCount` is `3` and §8
    placement B is armed at exactly that count, so a rating prompt there would land beside a paywall
    — which the rule two bullets down forbids outright. A threshold strictly above 3 makes the
    ordinary collision impossible by construction; the residual case (B is *deferred*, not dropped)
    is covered by a second guard that waits while `PaywallPresenting.isEligible(.valueMoment)` is
    still true.
  - **A personal record has no seam.** Nothing on the post-workout path learns that a PR was set.
    `SaveWorkoutView` computes volume deltas; the only post-workout PR detection is a private
    hand-rolled Epley reimplementation inside `PostWorkoutRecapAggregator` that does not call
    `PersonalRecordService` and feeds AI prompt text only. Building that seam is larger than the
    whole rating feature.
- Apple throttles to 3 prompts per 365 days per device, may show nothing, and reports nothing back —
  it is never treated as guaranteed, nothing is gated on it, and no UI copy mentions it.
- **Never in an active workout, never on the watch, never next to a paywall.** Rule 3 in
  `monetization-strategy.md` §3 applies to this exactly as it applies to upsells, and a rating
  prompt stacked on a paywall poisons both. (The watch is not merely excluded by policy — the API
  has no watchOS counterpart.)
- The manual Settings link is unchanged — it serves the user who *wants* to write one.

**Success:** rating count rising at all. Anything above ~20 ratings starts to matter for ranking.
Measured in App Store Connect; the API gives the app nothing to measure.

### 2. Storefront metadata localization — the biggest mechanical win (P0)

**The key fact that makes this cheap:** App Store **metadata** localization is independent of **app**
localization. You can ship a localized App Name, Subtitle, Keyword field, screenshots and description
for a storefront without translating a single string in the app. **Each localization is a new
100-character keyword field**, which is the single most direct way to buy impressions.

**The trade-off, stated honestly:** a user who downloads in a locale the app doesn't speak may leave
a 1-star review. §10's guardrails put the App Store rating above revenue, so this is a real risk, not
a formality. Two mitigations: prefer locales whose users tolerate an English UI (Nordics, NL), and
make the localized description state the UI languages plainly.

**How:**
1. Start with **English (UK)** and **English (Australia)** — same UI language, zero risk, two extra
   keyword fields indexed in those storefronts. Pure upside; do these first.
2. Then Spanish (Mexico) / Spanish (Spain), French, Italian, Portuguese (Brazil) — metadata only,
   with an honest UI-language note.
3. Localize keywords **per market**, do not translate them. Terms differ: German lifters search
   "Trainingstagebuch" and "Trainingsplan", not a translation of "workout log".
4. Coordinate with `docs/marketing/app-store-subtitle-keywords.md` — it holds the indexing rules
   (App Name tokens must not be repeated in Subtitle or Keywords) and must be extended per locale
   rather than duplicated.

**Success:** Impressionen rising. This is the one lever with a near-mechanical relationship to it.

### 3. Niche keyword repositioning (P0)

**How:** rework Subtitle + Keyword field around the two defensible niches in §2 rather than the head
term. Concretely: Apple Watch standalone, no account, offline, privacy, superset, progressive
overload — terms where a 36-download app can plausibly rank. Update
`docs/marketing/app-store-subtitle-keywords.md` in the same change; that doc's own rule is that
subtitle and keywords ship together and then freeze.

**Note:** Apple's built-in **Product Page Optimization** A/B testing is *useless here* — it needs
far more traffic than 13 impressions/day to reach significance. Do not wait on it.

### 4. Landing page + custom domain (P1) — *separate React repo*

**Reframe this before scoping it.** SEO on a fresh domain takes 6–12 months to rank for anything
contested, so **do not justify this page by SEO**. Its immediate value is that it is the *destination
that makes every other channel possible*: Reddit posts, YouTube descriptions, review-site outreach
and press all need somewhere to point, and none of them can happen without it. It is infrastructure,
not a channel. SEO is a slow bonus that arrives later.

**How:**
- Own domain, `gymstreak`-based. Static-generated (Next.js/Astro), deployed to Vercel.
- **Fill the App Store Connect `Marketing URL` and `Support URL` fields with it.** These are
  currently the most obvious missing links between the store and the web.
- **Smart App Banner** (`<meta name="apple-itunes-app" content="app-id=6756426105">`) so a mobile
  visitor gets a native install affordance. The App Store ID is `6756426105`
  (`SupportLinks.appStoreAppID`).
- Every App Store link must carry campaign attribution so **Web-Referrer stops reading zero** and you
  can tell which off-store effort worked.
- Content that earns links, aimed at the §2 niches: an honest Apple-Watch-gym-app comparison, a
  "workout tracker without an account" page, a privacy page that says plainly that data stays in the
  user's own iCloud.
- Also host: a support/FAQ page (satisfies the Support URL requirement properly), the privacy policy,
  and a changelog fed from `CHANGELOG.md`.

**Success:** Web-Referrer > 0 in ASC → Akquise → Quellen. That single number going non-zero is the
whole first milestone.

### 5. In-app sharing (P1)

**Why:** there is **no sharing anywhere in the app today** — no `ShareLink`, no
`UIActivityViewController`, no `ImageRenderer`. Users have no way to show anyone what they did, which
means your own users cannot generate a single referral. This is the only lever that makes acquisition
partly self-sustaining.

**How:**
- A shareable **workout summary card** rendered with `ImageRenderer`, offered from the existing
  post-workout summary and from a history entry. Include the muscle map — it is the most visually
  distinctive thing the app has.
- Include a short link to the landing page (depends on #4) so shares are attributable.
- **Free, always** — `monetization-strategy.md` §3 Rule 4 (the user's own data) and Rule 1.
- Follow the rendering rules in `CLAUDE.md`: `ImageRenderer` work happens off the `body` path.

### 6. Community presence (P1)

**Why:** for lifting apps specifically this is the highest-signal free channel. Boostcamp's entire
growth loop was Reddit programs; the research in §13.6 found comparison sites and communities, not
ads, driving discovery in this category.

**How, and the way it fails:** genuine participation only. A promotional drop-in gets removed and
earns a permanent grudge. Be a lifter who built an app, answer questions about tracking, and mention
the app where it actually answers someone's problem. Target r/AppleWatch and privacy/iOS communities
first — the §2 niches — rather than the big general fitness subs where you are one of fifty trackers.
Secondary: reach out to "best Apple Watch fitness app" listicle authors, who need a free standalone
watch app to write about and cannot currently find one.

### 7. In-App Events (P2)

**Why:** free, appear in **both** Search and Browse, each carries its own indexed metadata, and they
can be featured editorially. Currently unused — greyed out in ASC.

**How:** up to 5 published at once, 10 configured. They need a genuine hook, not a fake sale — a
"New Year progressive-overload challenge", a notable feature launch. Each needs its own name, short
description and event card art. Realistically a modest lever; cheap enough to be worth it.

### 8. Custom Product Pages (P2)

**Why:** up to 35 pages, each with its own URL and its own screenshots. Lets a link from a watch-focused
Reddit post land on a page whose *first screenshot is the watch app* rather than the generic one —
which is exactly how off-store traffic converts. Currently unused.

**How:** one page per niche in §2 (Watch, privacy/no-account). Depends on having off-store traffic to
point at them, so it follows #4 and #6.

### 9. Full app localization (P3)

**Why later:** 1,083 strings per language, and it should follow the *evidence* from #2 — localize the
app for markets where metadata localization already shows traction, not on a guess.

**Prerequisite — and this is what the existing ticket set is for.** iOS is still on `.strings` files
(`GymStreak/Resources/{en,de}.lproj`), which are painful to extend to new locales; the watch is
already on `.xcstrings`. **`.scratch/i18n-foundation/issues/` tickets 03 (String Catalog migration)
and 04 (missing-key validation) are the right foundation** — 03 makes adding a locale mechanical, 04
stops a half-translated locale from shipping. Note that ticket set is *hygiene*, not language
addition: nothing in it adds a language, and it should not be mistaken for this work.

**Also:** the AI Coach runs on-device Foundation Models and its output language follows the device.
Verify quality in any new language before committing that market — a coach that answers in broken
Italian is worse than none.

### 10. Apple Search Ads (P3, optional — costs money)

**The honest case:** at 13 impressions/day even €5–10/day materially multiplies the top of the funnel,
and its keyword report is the only source of truth about which terms actually convert — which then
feeds #2 and #3 for free. **The honest counter-case:** it buys installs rather than earning them, it
stops the moment you stop paying, and with ~2% conversion at €24.99/yr the payback per install is
poor at this stage. Treat it as *paid market research* with a hard budget cap, or skip it.

---

## 5. Sequencing

**Phase A — cheap, immediate, no dependencies.** Rating prompt (#1 — ✅ shipped 2026-09-06),
English UK/AU metadata localizations (#2 step 1), niche keyword repositioning (#3). All three can
ship inside the current release cycle; tickets live in `.scratch/acquisition-phase-a/issues/`.

**Phase B — build the missing infrastructure.** Landing page + domain (#4), then in-app sharing (#5)
which depends on having a link worth sharing. Start community presence (#6) as soon as the page
exists.

**Phase C — compound it.** Additional metadata locales (#2 steps 2–3) informed by what Phase A moved,
In-App Events (#7), Custom Product Pages (#8) once there is off-store traffic to route.

**Phase D — commit to markets.** Full app localization (#9) for whichever markets Phase C proved,
after the i18n-foundation prerequisites. Reconsider Search Ads (#10).

---

## 6. What success looks like

Measure in this order — the first metric is the one that matters, and it is *not* revenue:

| Metric | Now | First milestone | Where |
|---|---|---|---|
| **Impressionen/day** | **~13** | **50** | ASC → Akquise |
| **Web-Referrer** | **0** | **any non-zero number** | ASC → Akquise → Quellen |
| Erstmalige Downloads/day | ~1.2 | 5 | ASC → Akquise |
| Ratings count | ~0 | 20 | ASC → App Store |
| Chargeable installs (cumulative) | ~12 | 141 | §13.4's significance threshold |

**"Now" column measured 2026-09-06, before any lever shipped.** Re-read it after each lever lands and
update it in place — this table is the only record of whether the strategy is working, and a stale
baseline is what makes a shipped lever look like it did nothing. Lever #1 (ratings) went out on
2026-09-06 with no data yet; App Store ratings surface slowly, so give it a release cycle before
reading the row.

**Do not read revenue as the scoreboard yet.** `monetization-strategy.md` §13.4 shows that at the
current rate the paywall does not produce a statistically meaningful signal until **2027**, and the
whole point of this document is to pull that date forward by raising the denominator. Revenue is a
lagging indicator of the top row.

**The guardrails still outrank all of it** (§10): free-user D30 retention and the App Store rating.
Localizing into a market the app cannot serve, or an aggressive rating prompt, can move the rating
against us — and the rating feeds back into ranking, so damaging it defeats the entire exercise.

---

## 7. Cross-references

- **`docs/monetization-strategy.md` §13** — the evidence base: measured numbers, the RevenueCat
  counting trap (§13.2), why the paywall is not the problem (§13.3–13.4), the source split (§13.5).
- **`docs/monetization-strategy.md` §13.9** — how to pull these numbers without a dashboard screenshot.
- **`docs/marketing/app-store-subtitle-keywords.md`** — the indexing rules and the current
  subtitle/keyword set; levers #2 and #3 both edit it.
- **`docs/marketing/app-store-description.md`** — the conversion asset (not indexed).
- **`docs/agents/mcp-servers.md`** — the `revenuecat` MCP server, for reading live numbers.
- **`.scratch/i18n-foundation/issues/`** — prerequisite hygiene for lever #9.
- **`.scratch/acquisition-phase-a/issues/`** — the live Phase A tickets (#1–#3). Transient: they are
  archived to `.scratch/_done/` once the set completes, and this document is what survives.
- **`docs/rating-prompt.md`** — lever #1 as shipped: trigger, once-ever storage, Apple's throttling
  semantics and the `RequestReviewAction` research.
