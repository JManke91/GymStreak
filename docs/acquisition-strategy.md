# Acquisition & Retention Strategy — how GymStreak gets seen, and why nobody comes back

**Status (2026-09-09):** **Phase A complete** (levers #1–#3, all entered in App Store Connect;
#2 and #3 are metadata bound to a version submission, so they take effect when that version is
released — independently confirmed still-not-live on 2026-09-09, see §1.3). **Phase B has been
redefined.** It was "landing page → sharing → community". It is now **instrument the funnel → stop
asking for money on first launch → give people a reason to come back**, because §1a measured that
**89% of everyone who has ever launched this app launched it exactly once.** Per-lever status lives
in the §3 table and is restated at the top of each §4 entry.

**This file is the single source of truth for acquisition *and* activation — strategy *and*
progress.** Tickets are cut from it into `.scratch/<phase>/issues/` and are transient — Phase A's
are already archived to `.scratch/_done/acquisition-phase-a/`; this document is not transient.
**When a ticket derived from a lever reaches `done`, record it here in the same change:** set the
lever's row in the §3 table, put a `**Shipped** (date)` line at the top of its §4 entry, correct any
statement the implementation proved wrong (rewrite it, never append a correction), and update §5 and
§6 if the phase or a milestone moved. A lever whose ticket is done but whose row still reads
"not started" makes this document worse than no document.

**Lever numbers are stable IDs, not rankings.** `#1`–`#10` are referenced from
`monetization-strategy.md`, the two `marketing/` documents and the archived Phase A tickets, so they
are never renumbered. **Row order in the §3 table is the priority**; new levers are appended as
`#11`+ and sorted into place. Never renumber to reorder.

**Why this document exists, and how its thesis changed.** `docs/monetization-strategy.md` §13
established that the paywall is not the problem — **the app reaches almost nobody** — and this file
was created to treat acquisition as the one movable input to revenue. **That framing was necessary
but incomplete, and §1a corrects it:** reach is one of *two* broken multipliers. Roughly 15% of
users ever open the app a second time, so installs alone cannot produce a subscriber. Read §13 for
the reach evidence and §1a for the return evidence; the levers in §3 now serve both.

---

## 1. The situation, in numbers

App Store Connect figures measured 2026-09-06 (window 7 Jun – 4 Sep). **RevenueCat figures re-pulled
2026-09-09 via the `revenuecat` MCP server** and superseding the 09-06 pull:

| | Value | |
|---|---|---|
| **Impressionen** | **1,150 / 90 days ≈ 13/day** | ASC, 09-06. The top of the funnel. Everything else is downstream. |
| Produktseitenaufrufe | 180 | 15.7% of impressions |
| **Erstmalige Downloads** | **36** | 20% of page views — a *healthy* listing |
| Chargeable installs since the paywall | ~12 | §13.1 |
| **Active subscriptions / MRR / Revenue (28d)** | **0 / €0 / €0** | RC, 09-09. Unchanged since gating went live. |
| Active trials | 1 | The same cancelled DE trial; `will_not_renew`, lapses 2026-09-10 |
| RevenueCat customers, total ever | **125** | RC, 09-09 (was 114 on 09-06). **Not a user count — see §1.1** |
| **Ever launched the app twice** | **13 of 87 (15%)** | RC, 09-09. **The number that matters — §1a** |

**Source split** (product page views, daily average): App Store Search ≈ 1/day; Browse a thin
secondary from July; App-Referrer first appears in September; **Web-Referrer zero for ninety days.**

**Geography** (n=125 RevenueCat customers, 09-09): DE 72 (58%), US 38 (30%), GB 3, IQ 2, then one
each from AT, BE, BH, CA, CH, IE, IN, LB, SA. Platform is 100% iOS. This is consistent with the
09-06 reading of 62/28/3 and confirms Germany as the primary market.

**RevenueCat's own benchmarks return nothing usable.** Initial conversion and conversion-to-paying
both read `0` in the `0-10` percentile bucket with `is_eligible_for_benchmarking: false` — the
sample is too small to compare against the health-and-fitness peer group. Do not quote them.

### 1.1 The customer count is contaminated twice over — correcting §13.2

`monetization-strategy.md` §13.2 established that RevenueCat "New Customers" counts SDK identity
creations rather than installs, and attributed the inflation to **the update wave**. That is right
in kind but **understated in degree, because there is a second and now larger source: this
project's own simulator and local builds.**

- **38 of the 125 customers (30%) are on 1.1.15 (33) or 1.1.16 (5)** — builds that were never on the
  App Store.
- Nearly all are **DE**, on simulator-typical runtimes (`26.5 / 23F77`, `26.1 / 23B86`), minted in
  **working-hours bursts**: nine fresh anonymous IDs between 09:19 and 10:11 on 09-06, four more on
  1.1.16 between 16:06 and 16:11 the same afternoon, fourteen across 09-05. Every one of them
  pinged exactly once.
- That is what a `simctl erase` cycle looks like from the server side: each erase mints a new
  anonymous app-user ID (see the `seed-catalog-kvs-flag` note — erasing is the *documented* way to
  re-run seeding here, so this will keep happening).

**Consequence: the New Customers curve is not growth.** Weekly it reads 11 → 9 → 29 → 51 → 24, with
daily peaks of 14 on 09-05 and 20 on 09-06. §6 warns that "at 13/day a single good day looks like a
trend when it is not" — this is precisely that failure mode, and the curve would otherwise be read
as Phase A working. **It is mostly the developer's own machine.**

**The rule, extending §13.2's:** before reading any RevenueCat volume chart, exclude customers whose
`last_seen_app_version` was never released. The permanent fix is a build-channel subscriber
attribute — considered and deliberately deferred in §13.4, and §4.11 now supersedes that deferral.

### 1.2 What is NOT the problem (do not re-litigate)

- **The paywall machinery.** Nine placements, six gates, Customer Center, a proven production
  purchase (`environment: production`, §13.3). It works; almost nobody sees it.
- **The listing.** 20% page-view→download, conversion +110% after the 2026-08-25 ASO pass. Do not
  spend effort rewriting the description — that half works.
- **The product's depth.** 1,083 localized strings, a standalone watch app, on-device AI, supersets,
  CloudKit sync. Depth is not what is missing.

### 1.3 Phase A is confirmed still not live — by a second, independent route

Segmenting New Customers on `external_subscriber_attributes:founder` puts **all 125 customers in the
empty bucket**: not one has ever reported the attribute. The `founder` attribute ships in **1.1.16**
(§13.4), so this proves 1.1.16 has reached no real user, and therefore that levers **#2 and #3 are
still committed-but-not-live** exactly as their §4 entries claim. Re-run this segment as the cheapest
possible check on whether the carrying version has actually gone out.

---

## 1a. The second constraint: almost nobody comes back (measured 2026-09-09)

**`monetization-strategy.md` §13.4 states that "engagement is currently unmeasured, not known to be
bad". That is no longer true. It is measurable, it was measured, and it is bad.** §13.4's paragraph
is corrected accordingly; this section is the evidence.

### The measurement, and why it is trustworthy

RevenueCat exposes `first_seen_at` and `last_seen_at` per customer. Two facts make the difference
between them readable as *"did this person ever open the app again?"*:

1. **The SDK is configured on every launch, unconditionally.**
   `RevenueCatPurchaseGateway.init()` calls `Purchases.configure` from the composition root, which
   runs in `GymStreakApp.init()` — before any UI exists. It is not lazy, not behind onboarding, and
   not behind a paywall.
2. **RevenueCat refreshes `CustomerInfo` on every app restart**, even when the cache is younger than
   its 5-minute foreground TTL ([RevenueCat caching docs](https://www.revenuecat.com/docs/test-and-launch/debugging/caching)).

So a second launch on a later day *must* advance `last_seen_at`. It does not.

### What it says

| | Value |
|---|---|
| Customers whose `last_seen_at` is within ~15 ms of `first_seen_at` | **111 of 125 (89%)** — one launch, ever |
| Ever launched twice, all customers | 14 of 125 (11%) |
| **Ever launched twice, excluding the 38 unreleased-build records (§1.1)** | **13 of 87 (15%)** |
| **Ever launched twice, US customers only** | **0 of 38** |
| Seen at all in the last 7 days | **6** — one of which is a development device |

**The US column is the cleanest read in this document.** The developer is in Germany, so no
simulator noise reaches it: 38 real App Store customers accumulated steadily across 1.1.9 → 1.1.15,
and **not one of them opened the app a second time.** If the true second-launch rate were 20%,
observing 0 of 38 has probability 0.8³⁸ ≈ 0.02%.

For calibration: a *good* health-and-fitness app retains ~20% at **day one**
([Business of Apps](https://www.businessofapps.com/data/health-fitness-app-benchmarks/),
[UXCam](https://uxcam.com/blog/mobile-app-retention-benchmarks/)). 15% *ever*, across a window of up
to three and a half weeks, is materially worse than that benchmark — not marginally below it.

**Caveats, stated so they are not rediscovered as objections:**
- A launch made entirely offline does not ping. It would ping on the next online launch, so this
  cannot explain 89%.
- This only covers SDK-carrying builds (1.1.9+, since 2026-08-15). Users who never updated past
  1.1.8 are invisible here — which makes the measured population *more* engaged than average, not
  less, since it is skewed toward people who update.
- `last_seen_at` tells us a launch happened. It does not tell us whether a workout was logged. That
  gap is exactly what lever **#11** exists to close.

### What this does to the strategy

The funnel, end to end:

```
13 impressions/day → 1.2 downloads/day → ~0.15 second launches/day → ~0 logged workouts → 0 purchases
```

1. **"Acquisition is the only lever on revenue" is no longer the right conclusion.** It is still
   true that the Founder grant (§7 of the monetization strategy) makes revenue a function of future
   installs alone — but an install that never returns is not a future customer. At a 15%
   second-launch rate, **10× the installs is still approximately zero subscribers.** Reach and
   return are two multipliers on the same product, and today both are broken.
2. **Return is the cheaper one to fix, and it gates the value of fixing reach.** Levers #11–#13
   total roughly a week. Lever #4 alone is one to two weeks and buys nothing if the traffic it
   sends leaks out on first launch. **Fix the leak before opening the tap.**
3. **§6's "141 chargeable installs → February 2027" significance target is void as written.** It
   assumes installs convert at something like the §10 target of 2.1%. A cohort with a 15%
   second-launch rate cannot support that prior, so reaching n=141 would not make zero informative
   either. Restated in §6.
4. **Two things in the app are directly implicated, and both are cheap to change.** The first-run
   tour ends in a paywall before the user has logged a single set (#12), and the only
   `UNUserNotificationCenter` use anywhere in the codebase is the rest timer — there is no reason to
   come back, in an app called Gym Streak (#13).

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
  is far more established. **This paragraph deliberately attached no recommendation. §4.15 now
  attaches one** — price a rename and decide it, before #4 and #6 spend weeks building assets under
  a name that may change.
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

**Row order is the priority. The `#` column is a stable ID and never changes** (see the header
note). Ranked by expected effect on *revenue* ÷ effort, with dependencies respected — which after
§1a means return-rate levers outrank reach levers, because reach multiplied by a broken return rate
is still zero.

### Open — in the order to do them

| Order | # | Lever | Tier | Effort | Moves | Status |
|---|---|---|---|---|---|---|
| 1 | 11 | **Funnel instrumentation** (anonymous RC subscriber attributes) | **P0** | ~1 day | **Measurement — unblocks every row below** | ⬜ not started |
| 2 | 12 | **Remove the paywall from first-run onboarding** | **P0** | ~1 day | Return rate, first-session trust | ⬜ not started |
| 3 | 13 | **Re-engagement + streak notifications** | **P0** | 2–3 days | **Return rate** | ⬜ not started |
| 4 | 5 | In-app sharing of a workout | **P1** | 2–3 days | Web-Referrer, virality | ⬜ not started — **un-gated from #4**, see §4.5 |
| 5 | 15 | **Decide the app name** (rename or commit) | **P1 / decision** | ~1 day to decide | Brand-query traffic, word-of-mouth | ⬜ **not decided — gates #4 and #6** |
| 6 | 4 | Landing page + custom domain | **P1** | 1–2 weeks | Unlocks every off-store channel | ⬜ not started — blocked on #15 |
| 7 | 6 | Community presence (Reddit et al.) | **P1** | Ongoing | Downloads → velocity → ranking | ⬜ not started — blocked on #15 |
| 8 | 14 | **Lifetime / one-time purchase option** | **P1 / decision** | ~1 day to build | Revenue per converting user | ⬜ **needs a Monetization Gate discussion first** |
| 9 | 2 | Storefront metadata localization, steps 2–3 | **P2** | 1–2 days/locale | Keyword surface | ⬜ gated on the first search-term report |
| 10 | 7 | In-App Events | **P2** | ~1 day/event | Browse + Search surfaces | ⬜ not started |
| 11 | 8 | Custom Product Pages | **P2** | ~1 day | Conversion on off-store traffic | ⬜ not started — follows #4 and #6 |
| 12 | 9 | Full app localization, 2–3 markets | **P3** | 1–2 weeks/language | Keyword surface + market fit | ⬜ blocked on `.scratch/i18n-foundation/` |
| 13 | 10 | Apple Search Ads | **P3 / deferred** | Money | Impressions, and keyword data | ⬜ **deferred until #13 moves the return rate** — see §4.10 |

### Shipped

| # | Lever | Tier | Status |
|---|---|---|---|
| 1 | Rating prompt in-app | **P0** | ✅ **shipped 2026-09-06** — `docs/rating-prompt.md` |
| 3 | Niche keyword repositioning (Watch + privacy) | **P0** | ✅ **shipped 2026-09-06** — both fields entered in ASC, rides **1.1.16** (`marketing/app-store-connect-actions.md`). Confirmed not yet live, §1.3 |
| 2 | Storefront metadata localization, step 1 | **P0** | ✅ **shipped 2026-09-09** — en-GB + en-AU localizations entered in ASC (`marketing/app-store-connect-actions.md` §7). Steps 2–3 are row 9 above |

Status vocabulary: ⬜ not started · 🎫 ticket cut, not started · 🚧 in progress · ✅ shipped (date) ·
❌ dropped (with the reason in the §4 entry).

**Why the order changed on 2026-09-09.** Phase A's ranking was "expected *impressions* gained ÷
effort", which was correct while reach was believed to be the only broken multiplier. §1a showed it
is not. Three cheap levers (#11–#13, about a week in total) sit on the step where 89% of users are
lost; #4 alone is one to two weeks and pours traffic into that leak. Nothing already shipped is
invalidated — #1–#3 remain correct and stay committed — but everything unbuilt was resorted.

---

## 4. How to act on each

**Entry order:** §4.11–§4.15 come first because they are the current Phase B work and the top five
rows of the §3 table. Entries §4.1–§4.10 follow in stable-ID order. Each of §4.11–§4.15 is written
to be **extractable as a ticket without further design work** — goal, seams, acceptance criteria and
(where it applies) the Monetization Gate verdict are all stated. Run `/to-tickets` against them when
starting the phase; the granularity question is whether #13 splits into two slices, not whether the
work is specified.

### 11. Funnel instrumentation — anonymous subscriber attributes (P0, ~1 day)

**Why first:** every other decision on this page is currently a guess about *where* users are lost.
§1a proves they leave, and proves nothing about which screen loses them. RevenueCat sees only "the
app launched". Whether the drop is at the tour, at the starter routine, at the first logged set or
after the first completed workout changes which lever is worth building — and #12 and #13 are both
partly bets until this exists. It also permanently fixes the §1.1 contamination that made the
New Customers chart unreadable.

**The mechanism is already in the codebase.** `RevenueCatPurchaseGateway` line ~259 already calls
`Purchases.shared.attribution.setAttributes([...])` for the `founder` flag (`pro-subscription.md`
§3c). This lever adds siblings to that one call site — no new dependency, no new file, no new layer.

**What to report** — anonymous, non-identifying, bucketed so no attribute can single out a person:

| Attribute | Values | Answers |
|---|---|---|
| `onboardingCompleted` | `"true"` / `"false"` | Do they finish the seven-step tour, or bail inside it? |
| `workoutsCompleted` | `"0"` / `"1"` / `"2-4"` / `"5+"` | **The activation question.** Does anyone reach the value moment? |
| `routinesCreated` | `"0"` / `"1"` / `"2+"` | Does the starter routine carry them, or do they build their own? |
| `buildChannel` | `"appstore"` / `"other"` | Kills the §1.1 simulator/TestFlight contamination permanently |

**Constraints, and why they are not negotiable:**
- **Buckets, never raw counts.** A precise workout count plus a country plus a first-seen timestamp
  is re-identifying. Buckets are not, and they answer the question just as well.
- **Nothing is ever read back.** These are analytics only, exactly as `founder` is — no gate, no
  entitlement and no UI may branch on them, or the no-account promise starts leaking into behaviour.
- **`setAttributes` records locally and syncs on the next SDK request**, so it costs no extra
  network call and cannot block a launch.
- **This supersedes §13.4's deferral** of a build-channel attribute. That deferral said "decide it
  on evidence that the TestFlight/local-build population is actually distorting a reading". §1.1 is
  that evidence: 30% of all customers.

```
Monetization verdict — anonymous funnel attributes
  Tier          Free
  Derivation    §3 Rule 4 — it reads the user's own logged data, and is not user-facing at all
  Mechanism     n/a — nothing is gated
  Placement     none
  Nudge         none
  Free residue  the entire feature
  Founder note  n/a — analytics, not a capability
```

**Acceptance:** the four attributes appear on a fresh install in the RevenueCat dashboard; every
§3 chart can be segmented on `buildChannel`; no non-analytics code path reads any of them.

**Success:** within two weeks, §6's "where they leave" row stops reading *unknown*.

### 12. Remove the paywall from first-run onboarding (P0, ~1 day)

**Why it is the second thing:** the first-run tour is six explanatory slides followed by
`PaywallPlacement.onboarding` — **a purchase request before the user has logged a single set**, in
exactly the session that 89% of users never return from (§1a). It is the cheapest change on this
page, its downside is bounded, and it is the most directly implicated thing in the measured failure.

**The evidence that it costs nothing to remove:** the onboarding placement has produced **zero
purchases, ever**. The one production trial this app has seen came from the `gymstreak_sale`
offering on 2026-09-03, well after any first run (§13.3). There is nothing to lose.

**It also contradicts two positions the project already holds.** `monetization-strategy.md` §3
Rule 1 protects the aha path — build a routine → train it → see it logged → see the number go up —
and this places a paywall *before the first step of it*. The 2026 indie-monetization consensus says
the same: move the first ask after one completed core action
([tesseract.academy](https://tesseract.academy/how-to-monetize-a-fitness-app-proven-strategies-for-2026/),
[theswiftk.it](https://theswiftk.it.com/blog/how-to-monetize-ios-app-indie-developer)) — users pay
when an app has proved useful, not on the promise that it will be.

**The seam is one line.** `OnboardingFlowViewModel.steps` (line ~64) already filters `.offer` out of
`OnboardingStep.allCases` when the paywall seam refuses it; this makes that filter unconditional.
Then: delete `.offer` from `OnboardingStep`, delete `OnboardingStep.offer`'s CTA string key, retire
`PaywallPlacement.onboarding`, and remove the tour's own paywall sheet host (`docs/onboarding.md`,
"Step 7 — the offer") which exists solely for it.

**The first ask then falls to placements that already exist and are better placed:**
`.firstRoutineCreated` (§8 A) and `.valueMoment` at the 3rd completed workout (§8 B).
**Check the rating-prompt interaction while in here:** `docs/rating-prompt.md` deliberately triggers
on the 5th workout to stay clear of the value-moment paywall at 3. Removing a *different* placement
does not disturb that, but the guard is worth re-reading rather than assumed.

**Open question worth deciding in the same ticket, but separable:** six slides before the app opens
is a lot, and `docs/example-starter-routine.md` states the seeded routine already teaches rep
ranges, supersets and per-set rest — the subjects of slides 2, 3 and 4. Cutting the tour to two or
three slides is plausibly a second retention win. **It is not part of this ticket** — do it after
#11 reports `onboardingCompleted`, so the decision is made on where people actually bail.

**This is a gating change**, so when it lands it updates `monetization-strategy.md` §4 and
`docs/pro-subscription.md` (a placement is being retired), plus `docs/onboarding.md`.

**Acceptance:** a fresh install reaches the tab bar without ever seeing a paywall; the tour is six
steps with six progress segments; `PaywallPlacement.onboarding` no longer exists; the iOS suite and
the onboarding tests pass.

### 13. Re-engagement and streak notifications (P0, 2–3 days)

**Why:** this is the largest single hole in the product. **The only `UNUserNotificationCenter` use
in the entire codebase is the rest timer** (`GymStreak/Data/Notifications/UserNotificationRestTimerScheduler.swift`).
There is no workout reminder, no scheduled-session nudge, and **no streak reminder in an app called
Gym Streak.** A streak is the most notification-native mechanic that exists, the app is named after
it, and it is doing no work at all. §1a says the problem is that people do not come back; this is
the only lever on this page that *asks* them to.

**What to build:**
- **A planned-session reminder.** The app already has weekday scheduling — `PaywallPlacement`
  carries a `weekdaySchedule` case, so the planning data exists. Fire on the morning of a planned
  training day.
- **A streak-at-risk nudge.** One notification when a streak the user has actually built is about to
  lapse. Never on day one of no activity, and never to someone with no streak to lose.
- **A hard cap on frequency**, decided in the ticket and written into the code, not left to
  judgement later. This is the mechanism most able to damage §10's App Store-rating guardrail.

**Where to ask for permission — and this decides whether the lever works at all.** Not at launch,
and not during the tour. Ask **after the first completed workout**, when the app has earned the
request and the user has something worth being reminded about. A permission prompt on first launch,
in the session 89% never return from, converts a retention lever into another reason to leave.

**Rules that apply:** never during an active workout, never on the watch, never adjacent to a
paywall (`monetization-strategy.md` §3 Rule 3 — the same constraint `docs/rating-prompt.md` obeys).
Reuse the `RestTimerNotificationCenter` protocol pattern in `Data/Notifications/` rather than
inventing a second abstraction over `UNUserNotificationCenter`; a sibling protocol in the same
folder, injected via `AppDependencies`, matches how the rest timer already does it.

```
Monetization verdict — workout and streak reminders
  Tier          Free
  Derivation    §3 Rule 1 — it is the aha path (train → log → see the number go up)
  Mechanism     n/a — nothing is gated
  Placement     none
  Nudge         none
  Free residue  the entire feature
  Founder note  gating this would convert nobody. It exists to make a free user return at all,
                and a user who does not return is not a Pro prospect. Free is not a concession here.
```

**Splitting:** if `/to-tickets` wants two slices, the seam is *planned-session reminder* (needs the
schedule data) and *streak-at-risk nudge* (needs the streak calculation) — the notification
plumbing, permission flow and frequency cap are shared and belong in whichever ships first.

**Acceptance:** a user with a planned Tuesday session and notification permission receives exactly
one reminder that Tuesday morning; a user with no streak and no plan receives nothing; the
permission prompt cannot appear before a completed workout; the watch is untouched.

**Success:** §6's second-launch row moves. This is the lever that row exists to measure.

### 14. Lifetime / one-time purchase option (P1 — discussion before build)

**This entry does not authorize a change.** Pricing and packaging changes are a
`monetization-strategy.md` Monetization Gate matter and the gate says: **when the verdict touches
Pro, stop and discuss before building.** What follows is the case to discuss, not a decision.

**Today's ladder:** yearly (`gymstreak.iap.pro.yearly.sub`, P1Y, with a P1W trial) and monthly
(`gymstreak.iap.pro.monthly.sub`, no trial). Both under the `gymstreak_sale` offering.

**Three arguments for adding a lifetime tier:**
1. **A one-time option alongside subscriptions lifts total conversion 15–25%** in 2026 indie data
   ([theswiftk.it](https://theswiftk.it.com/blog/how-to-monetize-ios-app-indie-developer)).
2. **It matches this app's own positioning, which is the stronger argument.** §2's defensible niche
   and `monetization-strategy.md` §1's no-account promise attract the privacy / offline / own-your-
   data cohort — precisely the people most hostile to renting access to their own training log. The
   app's differentiator and its pricing model currently point in opposite directions.
3. **The app-side cost is near zero.** `RevenueCatPurchaseGateway` already handles the non-expiring
   case and documents it: *"Lifetime is the non-expiring grant. A subscription always carries an
   `expirationDate` … the one-time purchase carries none."* The work is an App Store Connect
   product, a RevenueCat package, and paywall copy.

**A separate, smaller question to settle at the same time:** monthly carries **no trial** while
yearly does. That is a confusing ladder — the cheaper commitment is the riskier one to try. Either
give monthly a trial or drop the monthly tier.

**Sequencing:** this is row 8, not row 1, deliberately. With a 15% second-launch rate there is
almost nobody reaching a paywall for packaging to act on. Fix the funnel first; then this is worth a
morning.

### 15. Decide the app name — rename or commit (P1, decision, gates #4 and #6)

**§2 measured the problem and deliberately attached no recommendation. This entry attaches one:
price a rename, and decide before spending money or weeks on brand-carrying assets.**

**The facts, from §2:** **"GymStreak Ltd"** is an established developer whose **"GymStreak: AI
Personal Trainer"** (App ID `1371187280`, **5,118 ratings, 4.6★**, on the store since 2018) ranks
**first** for the query *gymstreak* in the US, UK, AU and DE storefronts. `GymStreak – Workout
Tracker` ranks **#14 (US), #29 (GB), #78 (AU)**, #2 (DE). Two further apps also carry the name.

**Why this is a decision and not an ASO footnote:**
- **Word-of-mouth is this app's only acquisition channel** (`monetization-strategy.md` §10). The
  mechanism of that channel is: someone is told the name, and searches it. Today that search hands
  the person to a competitor with 5,118 ratings. **The one channel the strategy relies on leaks
  directly to an incumbent**, and no amount of keyword work fixes a brand query.
- **It gates #4 and #6, which is why it sits above them.** A landing page on a `gymstreak` domain
  and a Reddit presence built under the name are both expensive and both discarded by a later
  rename. Deciding after building them means paying twice.
- **There is trademark exposure** in sharing a name with an established commercial developer in the
  same category. Not assessed here; it belongs in the decision.

**What the decision needs** (this is the ticket): the cost of a rename priced honestly — App Store
listing and all four metadata localizations, the `marketing/` keyword derivations (which are
name-token-dependent, `app-store-subtitle-keywords.md` §2), app icon and screenshots, the 1,083
localized strings that mention the name, the watch app, the domain, and the loss of the existing
ratings history — set against the measured cost of keeping it. **Decide it either way and record the
decision here**; an undecided name is what blocks #4 and #6.

**Not urgent this week** — #11–#13 come first and none of them touch the name. But it must not stay
unrecommended, because every acquisition euro spent under this name partly funds the incumbent.

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

**Blocked on two things as of 2026-09-09.** On Phase B (#11–#13): this page sends traffic into a
funnel that currently loses 89% of it on the first launch, and it is the most expensive unbuilt item
on this page. And on the **name decision (#15)** — the domain, the copy and the brand are all
discarded by a later rename, so deciding after building means paying twice.

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

**Un-gated from #4 on 2026-09-09.** This entry used to depend on the landing page existing, so that
shares could carry an attributable link. That gate is not worth its cost: an **App Store link with a
campaign token** is attributable today, needs no landing page, and turns Web-Referrer non-zero on
its own. Ship the card against an App Store link now and swap the URL when #4 exists.

**How:**
- A shareable **workout summary card** rendered with `ImageRenderer`, offered from the existing
  post-workout summary and from a history entry. Include the muscle map — it is the most visually
  distinctive thing the app has.
- Include a short attributable link — an App Store link with a campaign token today, the landing
  page once #4 exists.
- **Free, always** — `monetization-strategy.md` §3 Rule 4 (the user's own data) and Rule 1.
- Follow the rendering rules in `CLAUDE.md`: `ImageRenderer` work happens off the `body` path.

### 6. Community presence (P1)

**Blocked on the name decision (#15).** Reputation in a community accrues to a name, and it is the
one asset here that cannot be migrated: posts, comment history and the goodwill attached to them all
stay under whatever name made them. Decide #15 before introducing the app to anyone.

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

### 10. Apple Search Ads (P3 — deferred, not optional-but-available)

**Deferred on 2026-09-09, and the reason is §1a, not budget.** This entry previously read "treat it
as paid market research with a hard budget cap, or skip it". That was written when the funnel below
the install was assumed to work. It does not: **0 of 38 US customers ever opened the app a second
time.** Paying for installs into that funnel does not buy market research, it buys a per-euro
measurement of a leak that #11 measures for free and #13 is meant to close.

**The case for it survives and is unchanged in kind:** at 13 impressions/day even €5–10/day
materially multiplies the top of the funnel, and its keyword report is the only source of truth
about which terms actually convert, which then feeds #2 and #3. **The counter-case is now
quantitative:** it buys installs rather than earning them, it stops the moment you stop paying, and
the conversion assumption that made the payback arithmetic work (~2% at €24.99/yr) is not supported
by a cohort with a 15% second-launch rate.

**Revisit when** §6's second-launch row has moved after #13 — not before, and not on the argument
that impressions are cheap.

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
(`marketing/app-store-connect-actions.md` §5 and §7.6). That report is also the gate on Phase D's
step-2 locales. Use §1.3's `founder`-attribute segment as the cheap check on whether the carrying
version has actually shipped.

**Phase B — stop the leak (≈1 week). This is the next thing to do, and it replaces the old Phase B.**
Funnel instrumentation (#11) first, because it is the prerequisite for reading everything after it.
Then remove the onboarding paywall (#12), a one-day change on the exact session where users are
lost. Then re-engagement and streak notifications (#13), the only lever that asks a user to return.
**Do not start Phase C until §6's second-launch row has been read at least once after #13 ships** —
that reading is the whole point of Phase B, and Phase C's cost is only justified if the funnel
below it holds.

*Why this replaces "landing page → sharing → community":* §1a. Reach multiplied by a 15%
second-launch rate is still zero, #4 alone is one to two weeks, and #11–#13 together are about a
week. Fix the leak before opening the tap.

**Phase C — earn traffic, once it can be kept.** In-app sharing (#5) first, now un-gated from the
landing page (§4.5). **Decide the name (#15) before the two brand-carrying items** — a landing page
and a community presence are both discarded by a later rename, which is why the decision sits above
them rather than beside them. Then the landing page + domain (#4), then community presence (#6) as
soon as the page exists. The lifetime/one-time packaging discussion (#14) belongs at the end of this
phase, when there is finally a population reaching a paywall for it to act on.

**Phase D — compound it.** Additional metadata locales (#2 steps 2–3) informed by what Phase A
moved, In-App Events (#7), Custom Product Pages (#8) once there is off-store traffic to route.

**Phase E — commit to markets.** Full app localization (#9) for whichever markets Phase D proved,
after the i18n-foundation prerequisites. Reconsider Search Ads (#10) — and only once #13 has moved
the second-launch row (§4.10).

---

## 6. What success looks like

Measure in this order — the first metric is the one that matters, and it is *not* revenue:

**The order changed on 2026-09-09.** Return metrics now sit above reach metrics, because §1a showed
reach is the *second* broken multiplier, not the only one. Revenue remains last.

### Return — the Phase B scoreboard

| Metric | Now (2026-09-09) | First milestone | Where |
|---|---|---|---|
| **Ever launched twice** (released builds) | **15%** (13 of 87) | **30%** | RC customer records, `last_seen_at` > `first_seen_at` — method in §1a |
| **Ever launched twice, US only** | **0 of 38** | **any non-zero number** | Same, filtered to US — the read with no simulator noise |
| Customers seen in the last 7 days | **6** (one a dev device) | 25 | RC → Active Customers |
| **Where they leave** | **unknown** | *measurable at all* | Blocked on #11 — this row is the point of that lever |
| Completed ≥1 workout | **unknown** | 40% of installs | Blocked on #11 (`workoutsCompleted`) |

### Reach

| Metric | Now | First milestone | Where |
|---|---|---|---|
| **Impressionen/day** | **~13** | **50** | ASC → Akquise — and **by territory** once #2 is live |
| **Web-Referrer** | **0** | **any non-zero number** | ASC → Akquise → Quellen |
| Erstmalige Downloads/day | ~1.2 | 5 | ASC → Akquise |
| Ratings count | ~0 | 20 | ASC → App Store |

### Revenue — a lagging indicator of both tables above

| Metric | Now | First milestone | Where |
|---|---|---|---|
| Active subscriptions / MRR | **0 / €0** | 1 renewing subscriber | RC overview |
| Chargeable installs (cumulative) | ~12 | see the correction below | §13.4 |

**§13.4's "141 chargeable installs → February 2027" target is void as written.** That arithmetic
asks how many installs are needed before *zero conversions* becomes evidence against the §10 target
rate of 2.1%. It assumes installs behave like a normal cohort. A cohort with a 15% second-launch
rate does not: most of those 141 would never see a paywall at all, so reaching the number would not
make zero informative. **Do not recompute the threshold until Phase B has moved the second-launch
row** — the denominator that matters is *activated* users, not installs, and #11 is what will first
make that denominator countable.

**Reading rules.** "Now" columns are dated per table and re-read after each lever lands — a stale
baseline is what makes a shipped lever look like it did nothing. The reach rows were measured
2026-09-06 before any lever was live; lever #1 (ratings) went out that day with no data yet, and App
Store ratings surface slowly, so give it a release cycle. **Before reading any RevenueCat volume
row, apply §1.1** and exclude customers on builds that were never released — until #11's
`buildChannel` attribute makes that automatic.

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
  counting trap (§13.2 — **extended by §1.1 here**), why the paywall is not the problem
  (§13.3–13.4), the source split (§13.5). **§13.4's "engagement is unmeasured" claim is superseded
  by §1a here**, and §13.4 has been corrected in place to point at it.
- **`docs/monetization-strategy.md` §13.9** — how to pull these numbers without a dashboard screenshot.
- **`docs/monetization-strategy.md` §3** — Rule 1 (the aha path) and Rule 3, which decide the free
  verdicts on levers #12 and #13.
- **`docs/onboarding.md`** — the seven-step first-run tour and its step-7 paywall host; lever #12
  edits it.
- **`docs/pro-subscription.md` §3c** — the `founder` subscriber attribute, the mechanism lever #11
  extends and the one §1.3 reads to check whether a version is live.
- **`docs/rest-timer-notifications.md`** — the only notification code in the app today, and the
  protocol pattern lever #13 should follow rather than reinvent.
- **`docs/example-starter-routine.md`** — what a first-run user actually finds; relevant to the tour
  -length question parked in §4.12.
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
