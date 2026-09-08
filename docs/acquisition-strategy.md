# Acquisition Strategy — how GymStreak gets seen

**Status (2026-09-09):** **Phase A complete** — all three levers shipped and entered in App Store
Connect. Nothing is *live* yet: #2 and #3 are metadata bound to a version submission, so they take
effect when that version is released. Per-lever status lives in the §3 table and is restated at the
top of each §4 entry. Phase B (landing page → sharing → community) is the next thing to start.

**This file is the single source of truth for acquisition — strategy *and* progress.** Tickets are
cut from it into `.scratch/<phase>/issues/` and are transient — Phase A's are already archived to
`.scratch/_done/acquisition-phase-a/`; this document is not transient.
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
  **"More localizations = more keyword fields" is too loose, and lever #2 had to correct it:** a
  storefront with no localization of its own is already served by the app's *primary language*, so
  adding one **swaps** which 100 characters are indexed there rather than adding 100 more. It is
  still the most mechanical lever, but the gain is the *difference* between the new field and the
  fallback — a clone buys nothing. See §4.2 and `marketing/app-store-subtitle-keywords.md` §6.1.
- **Ranking within a term.** Driven substantially by **download velocity**, **conversion rate**, and
  **ratings volume + average**. Two of those three we currently do nothing about.
- **The App Name is a brand this app does not own, and that caps what the title field is worth.**
  Measured 2026-09-07 while deriving lever #2: **"GymStreak Ltd"** is an established developer whose
  app **"GymStreak: AI Personal Trainer"** (App ID `1371187280`, **5,118 ratings, 4.6★**, on the
  store since 2018) ranks **first** for the query *gymstreak* in the US, UK, AU and DE storefronts,
  while `GymStreak – Workout Tracker` ranks **#14 (US), #29 (GB), #78 (AU)** and **#2 (DE)**. Two
  further apps also carry the name ("GymStreak: Gym Habit Tracker", "GymStreak: Habit Tracker").
  Consequences, without a recommendation attached: brand-query traffic — normally the cheapest
  traffic an app has — largely lands on a competitor; the `gym` and `streak` tokens the title spends
  are worth even less than the exclusion-list reasoning in
  `marketing/app-store-subtitle-keywords.md` §2 assumed; and word-of-mouth, this app's only
  acquisition channel (`monetization-strategy.md` §10), is the channel most damaged by a name someone
  else already ranks for. **Measurement caveat:** the ranks above come from the public iTunes Search
  API, which is *not* the App Store's search index (it ignores the keyword field entirely — §9 of the
  keywords document), so treat the ordering as indicative of the brand query, not as exact App Store
  ranking. What it does establish beyond doubt is that the name is shared and that the other holder
  is far more established.
- **Browse/featuring surfaces.** Editorial and algorithmic. In-App Events and Custom Product Pages
  feed them; you cannot buy them.
- **Off-store traffic.** Doesn't add impressions directly, but adds downloads — and download
  velocity feeds ranking, so external traffic compounds back into organic reach.

**The strategic consequence: stop competing on head terms.** "workout tracker" belongs to Hevy and
Strong. GymStreak has two genuinely defensible niches with real search intent and almost no
competition:

- **Apple Watch — in the US storefront, and only there.** A complete, free, standalone watch app.
  Strong paywalls theirs and is widely criticized for it (`monetization-strategy.md` §5). The live
  query, per Apple's own autocomplete, is **"workout tracker apple watch"** — and the App Name
  already owns two of its four tokens. **This section previously called it "an en-only asset". That
  was wrong, and lever #2 measured it:** "apple watch workout", "apple watch gym" and "apple watch
  tracker" are **empty in the UK and Australian storefronts** (as they are in Germany), while the US
  self-suggests all three. The bare "apple watch" prefix *is* live in GB/AU — as watch faces, dials,
  games and blood-pressure apps, i.e. a device-utility cluster this app cannot serve. So `apple` is
  bought in **en-US only**; every other locale buys a cheap bare `watch` hedge
  (`marketing/app-store-subtitle-keywords.md` §6.2). Germany's defensible gap is instead its
  **native compound vocabulary** (`trainingstagebuch`, `krafttraining`, `muskelaufbau`), which the
  international category leaders ship English titles into and never buy.
- **Privacy / no account / offline.** **Smaller than this document originally claimed, and the
  correction matters.** Lever #3 probed the store's own search autocomplete and found that
  *"workout tracker no account"* — the example query this section used to name — **returns nothing at
  all**, as do "workout without account", "workout no login" and "workout tracker privacy". The
  German "ohne konto" is likewise empty. The no-account promise is real and it converts on the
  product page, but **almost nobody searches for it**, so it cannot be bought with keywords. What
  *is* searchable is **`offline`** — a live cluster with competitors named after it. See
  `marketing/app-store-subtitle-keywords.md` §4.2b and §9.

Every lever below should be pointed at those two niches, not at the head.

---

## 3. Prioritized levers

Ranked by expected impressions gained ÷ effort, with dependencies respected.

| # | Lever | Tier | Effort | Moves | Status |
|---|---|---|---|---|---|
| 1 | Rating prompt in-app | **P0** | ~1 day | Ranking | ✅ **shipped 2026-09-06** — `docs/rating-prompt.md` |
| 2 | Storefront metadata localization (no app translation) | **P0** | 1–2 days/locale | **Keyword surface** | ✅ **step 1 shipped 2026-09-09** — en-GB + en-AU localizations created and entered in ASC (`marketing/app-store-connect-actions.md` §7). Steps 2–3 remain Phase C |
| 3 | Niche keyword repositioning (Watch + privacy) | **P0** | ~1 day | Keyword surface | ✅ **shipped 2026-09-06** — both fields entered in ASC, rides **1.1.16** (`marketing/app-store-connect-actions.md`) |
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

### 2. Storefront metadata localization (P0)

**Shipped** (2026-09-09), step 1 only. en-GB and en-AU metadata localizations, each with its own
98/100-character keyword field derived against that storefront's own autocomplete. Derivation and
per-token intent: `docs/marketing/app-store-subtitle-keywords.md` §6. The strings, the
add-a-localization click path and the screenshot answer:
`docs/marketing/app-store-connect-actions.md` §7. **Both localizations were entered in App Store
Connect on 2026-09-09** and ride the version they were entered on; like lever #3 they are *committed
but not live* until that version is released, and App Store re-indexing after that is not instant.
Steps 2–3 below are unchanged and remain Phase C.

**The key fact that makes this cheap:** App Store **metadata** localization is independent of **app**
localization. You can ship a localized App Name, Subtitle, Keyword field, screenshots and description
for a storefront without translating a single string in the app. Apple even prefills most of it: only
the **description and keywords** have to be typed for a new localization, everything else — App Name,
Subtitle, promotional text, **screenshots** — defaults to the primary language's values.

**This section used to claim "each localization is a new 100-character keyword field, the single most
direct way to buy impressions". Step 1 proved that overstated, and the correction is the most useful
thing it produced:**

- A storefront with no localization of its own is **already served by the app's primary language**.
  Verified on this app: the UK and Australian storefronts return the **en-US** App Name and
  description today. So adding en-GB **swaps** which 100 characters are indexed there — it does not
  add 100 more, and **cloning the en-US string into it would buy literally nothing.**
- **The one genuine addition** is that Australia and New Zealand index **en-AU *and* en-GB**
  (unanimous across four ASO vendor tables; Apple documents none of it). Adding *both* localizations
  is therefore what buys a second indexed field — and only if the two fields share no tokens, which
  is why they deliberately don't.
- **en-GB is not a UK change.** English (U.K.) is Apple's documented default for the large majority
  of countries — Ireland, India, Singapore, South Africa, Hong Kong and a hundred-plus others, all
  serving en-US today. That is a large collateral surface, and it is why the en-GB field carries the
  strong general set while en-AU carries the complement.
- **Expect a small absolute effect.** The UK is ~3% of the customer base (§1) and Australia does not
  appear in it at all; against ~13 impressions/day the UK storefront is around half an impression a
  day. The change is worth making because it is free, reversible and risk-free — not because it is
  the biggest number on this page. The lever's real product is **evidence**: whether a metadata-only
  localization moves anything, which is what steps 2–3 need before they take a rating risk.

**The trade-off, stated honestly:** a user who downloads in a locale the app doesn't speak may leave
a 1-star review. §10's guardrails put the App Store rating above revenue, so this is a real risk, not
a formality. **Step 1 carries none of it** — en-GB and en-AU users get an English UI and English
metadata. Steps 2–3 do: mitigate by preferring locales whose users tolerate an English UI (Nordics,
NL) and by making the localized description state the UI languages plainly.

**How:**
1. ✅ **Shipped 2026-09-09** — **English (UK)** and **English (Australia)**: same UI language, zero
   rating risk. See the two marketing documents above; the remaining work is *reading the result*.
2. Then Spanish (Mexico) / Spanish (Spain), French, Italian, Portuguese (Brazil) — metadata only,
   with an honest UI-language note. **Gate this on the step-1 evidence**, not on the mechanism
   sounding plausible (`marketing/app-store-connect-actions.md` §7.6). **One input to check first,
   found while deriving step 1:** Apple's own localizations table lists the **United States** as
   English (U.S.) *plus* Arabic, Chinese, French, Korean, Portuguese (Brazil), Russian, Spanish
   (Mexico) and Vietnamese as additional supported languages — so es-MX, fr and pt-BR may add keyword
   surface **in the US storefront too**, which is a different and better case than "reach Mexico".
   Nothing is drafted for them here (`marketing/app-store-subtitle-keywords.md` §6.1).
3. Localize keywords **per market**, do not translate them. Terms differ: German lifters search
   "Trainingstagebuch" and "Trainingsplan", not a translation of "workout log" — and step 1 found the
   same thing *within* English: Australian English searches "gym program", British English also
   "gym programme", and the Apple Watch cluster exists only in the US.
4. Coordinate with `docs/marketing/app-store-subtitle-keywords.md` — it holds the indexing rules
   (App Name tokens must not be repeated in Subtitle or Keywords, and a token repeated across two
   co-indexed localizations is a wasted slot) and is extended per locale rather than duplicated.

**Success:** Impressionen rising **per territory**, and a search-term report that shows the new
tokens returning something. Read it per storefront — the four keyword fields no longer contain the
same tokens.

### 3. Niche keyword repositioning (P0)

**Shipped** (2026-09-06). New **en-US** and **de-DE** keyword fields, both 99/100 characters, derived
against each storefront's own search autocomplete. Derivation and per-token intent:
`docs/marketing/app-store-subtitle-keywords.md` §4.2, §4.2a, §4.2b, §5.2, §5.2a and §9. The strings
and the App Store Connect click path: `docs/marketing/app-store-connect-actions.md`.

**Both fields were entered in App Store Connect on 2026-09-06 and 1.1.16 is submitted.** The lever is
therefore *committed but not yet live* — it goes live with the release, and App Store re-indexing
after that is not instant. Do not read the §6 Impressionen row as a verdict until 1.1.16 has been
live a couple of weeks.

**The keyword field moved; both subtitles did not** — and this corrects what this section used to
say. It called for reworking "Subtitle + Keyword field" together, which conflates two fields with
opposite risk. The **subtitle is visible** and the 2026-08-25 ASO pass it belonged to **doubled**
page-view→download conversion (§1); rewriting it would bet a measured +110% against unproven niche
terms. The **keyword field is invisible**, cannot affect conversion at all, and only feeds ranking —
which is the only thing this lever is trying to move. So the invisible half rotates freely and the
visible half is frozen.

**What the rotation actually bought,** beyond the terms this section originally listed:
- `apple` + `watch` in en-US, settled explicitly against the earlier rejection of "Apple Watch" in
  the *subtitle* — a different field with a different cost and risk.
- `progressive` + `overload` in **both** locales: a large live cluster in the German storefront too,
  where the English loanword is what people type.
- `superset` in both — and **not** the German `supersatz`, which returns nothing.
- `calendar` in en-US: a live cluster, and **no competitor writes planned workouts to the system
  calendar**, which makes it the most defensible token in the field.
- `trainingstagebuch` and the German compounds, on the §2 reasoning above.
- **Not** `account` in either locale — see §2; the query does not exist.

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

**Phase A — done (2026-09-06 → 2026-09-09).** Rating prompt (#1 — ✅ shipped 2026-09-06), niche
keyword repositioning (#3 — ✅ entered in ASC 2026-09-06, rides **1.1.16**), English UK/AU metadata
localizations (#2 step 1 — ✅ entered in ASC 2026-09-09; it depended on #3 because both new fields are
derived as a delta against the final en-US one). All three are committed and take effect as their
versions are released. The tickets were archived to `.scratch/_done/acquisition-phase-a/` on
2026-09-09 — **this document is what survives them.**

**Phase A's remaining work is reading, not building:** the per-territory Impressionen rows and, ~4
weeks after the carrying version is live, the first search-term report
(`marketing/app-store-connect-actions.md` §5 and §7.6). That report is also the gate on Phase C's
step-2 locales.

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
| **Impressionen/day** | **~13** | **50** | ASC → Akquise — and **by territory** once #2 is entered |
| **Web-Referrer** | **0** | **any non-zero number** | ASC → Akquise → Quellen |
| Erstmalige Downloads/day | ~1.2 | 5 | ASC → Akquise |
| Ratings count | ~0 | 20 | ASC → App Store |
| Chargeable installs (cumulative) | ~12 | 141 | §13.4's significance threshold |

**"Now" column measured 2026-09-06, before any lever shipped.** Re-read it after each lever lands and
update it in place — this table is the only record of whether the strategy is working, and a stale
baseline is what makes a shipped lever look like it did nothing. Lever #1 (ratings) went out on
2026-09-06 with no data yet; App Store ratings surface slowly, so give it a release cycle before
reading the row.

**Neither number can move yet, and that is expected.** Levers #2 and #3 are **entered** but not live
— App Store metadata takes effect only when the version carrying it is released, and re-indexing
after that is not instant. Do not read the Impressionen row as a verdict on either until the carrying
version has been live for a couple of weeks, and at 13/day expect a single good day to look like a
trend when it is not. The first genuinely diagnostic artefact is the
**search-term report**, ~4 weeks after 1.1.16 goes live — it is also the first one this app will ever
have (`marketing/app-store-subtitle-keywords.md` §8), and it is what gates the step-2 locales in §4.2.

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
- **`docs/marketing/app-store-subtitle-keywords.md`** — the indexing rules, the current
  subtitle/keyword sets and the *derivation* behind them, including the autocomplete probe method
  (§9) that any future keyword work should re-run. Levers #2 and #3 both edit it.
- **`docs/marketing/app-store-connect-actions.md`** — the *execution* half of lever #3: the exact
  strings, the App Store Connect click path, and the post-change checks. Lever #2 appends to it.
- **`docs/marketing/app-store-description.md`** — the conversion asset (not indexed).
- **`docs/agents/mcp-servers.md`** — the `revenuecat` MCP server, for reading live numbers.
- **`.scratch/i18n-foundation/issues/`** — prerequisite hygiene for lever #9.
- **`.scratch/_done/acquisition-phase-a/issues/`** — the Phase A tickets (#1–#3), **archived
  2026-09-09** when the set completed. Transient by design; this document is what survives them. The
  ticket bodies still hold the blow-by-blow (probe results, discarded approaches, the deviations from
  each ticket's own acceptance criteria) if a decision here ever needs its provenance.
- **`docs/rating-prompt.md`** — lever #1 as shipped: trigger, once-ever storage, Apple's throttling
  semantics and the `RequestReviewAction` research.
