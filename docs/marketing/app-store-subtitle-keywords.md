# App Store Subtitle, Keyword Field & Promotional Text

ASO copy for the three **indexed / above-the-fold** App Store fields that were still missing from
`docs/marketing/`. The App Name and the Description are finalized elsewhere:

- App Name — **not** in this doc, see the "Title constraint" section for the strings in use
- Description → `docs/marketing/app-store-description.md` (conversion asset, **not indexed**)
- Promotional Text → earlier variants live in `docs/marketing/app-store-promotional-text.md`; this
  doc adds a set coordinated with the subtitle/keyword pass below

Created 2026-08-25 against app version **1.1.12**. **Keyword fields rotated 2026-09-06** onto the
defensible niches for **1.1.16** (`acquisition-strategy.md` §3 lever #3) — §4.2 and §5.2 hold the new
sets and the derivation, §9 holds the evidence they were derived from. **Two more English
localizations, en-GB and en-AU, were derived 2026-09-07 and entered in App Store Connect 2026-09-09**
(§6, lever #2) — four keyword fields now, no two of them alike. **All subtitles are
unchanged and deliberately so** (§4.1, §5.1, §6.4, and §4 of the playbook below).

The strings to type into App Store Connect, with the click path, live in
[`app-store-connect-actions.md`](./app-store-connect-actions.md) — this document is the *derivation*,
that one is the *execution*. Do not change one without the other.

---

## 1. How Apple indexing works (why the fields below look the way they do)

On the Apple App Store only three fields feed the search index: **App Name (~30)**, **Subtitle
(30)**, **Keyword Field (100, private)**. The Description is *not* indexed — it converts, it does
not rank. (In-app-purchase display names are also indexed, which is a separate lever: GymStreak's
IAPs are named "GymStreak Pro …" and spend no useful keyword surface.)

Two consequences drive every decision here:

1. **Tokens combine across fields, order-free.** Apple builds query candidates from the union of all
   indexed tokens, so `strength` in the subtitle plus `training` anywhere else already matches the
   query "strength training". Adjacency and word order are not worth paying characters for.
   Apple does not document the mechanics; the vendor consensus is unanimous and specific (AppTweak,
   Gummicube, App Radar, AppDrift all describe the same recombination, and Gummicube's *"the App
   Store does not index phrases as-is"* is the clearest statement of it).
   **Two limits that matter here:** combinations are formed **only within one locale** — an English
   token and a German one never combine — and a query matches only if **every** one of its tokens is
   indexed somewhere, which is the whole argument for §4.2a.
2. **Therefore every repeated word is a wasted character.** A token indexed by the title must never
   be bought again in the subtitle or the keyword field.
3. **Stop words are stripped, so never buy one.** `no`, `not`, `for`, `the`, `and` are on every
   published English stop-word list — Apple accounts for them when matching, and spending characters
   on them is waste. `without` is *not* a stop word. **No German stop-word list has ever been
   published**, and a Radaso experiment found that removing a Spanish preposition broke indexing
   outright, so do not assume `ohne`/`mit`/`für` are free — target the noun (`konto`) instead.

**Operational asymmetry — this matters for iteration speed:**

| Field | Editable without a new build? |
| --- | --- |
| Subtitle | ❌ requires a new version submission |
| Keyword Field | ❌ requires a new version submission |
| Promotional Text | ✅ any time, no build, no review |

So the subtitle + keyword field ship with the next version and are then frozen; the promotional text
is the field to A/B and to rotate seasonally.

---

## 2. Title constraint (the single most important input)

The two storefronts run **different** App Names, so they get **different** exclusion lists. This is
not a symmetry to "fix" — the German title's spare surface is genuine free inventory.

| Locale | App Name in App Store Connect | Tokens already indexed by the title | Must be excluded from subtitle + keywords |
| --- | --- | --- | --- |
| en-US | `GymStreak – Workout Tracker` | gym, streak, workout, tracker | **workout, tracker, gym, streak** |
| de-DE | `GymStreak` | gym, streak | **gym, streak** |

Consequences:

- The **English** subtitle may not say "Workout Tracker" — it is already the highest-weighted field's
  content. English pivots to the `strength / training / plan / log` cluster instead.
- The **German** subtitle *should* buy `Workout` and `Tracker`: German users search the English
  loanwords heavily ("workout tracker", "workout app"), and nothing in the de title covers them.
- `gym` and `streak` are excluded in both locales. This is a deliberate acceptance of a small loss:
  Apple's tokenizer does not reliably split the compound `GymStreak`, so "gym" coverage rests on
  compound splitting we cannot verify. Re-buying `gym` would cost 4 of 100 characters on a token
  that is very probably already indexed — not worth it while cheaper untapped tokens remain.
- **If the title ever changes, both fields below must be re-derived.** A title that drops
  "Workout Tracker" instantly makes the English keyword field wrong (it would then be missing the
  two highest-volume tokens in the category).

---

## 3. Feature basis — what the copy is allowed to claim

Verified against the shipped code, not the roadmap (v1.1.12).

**The three core features that carry the positioning:**

1. **On-device AI Coach across five surfaces** — post-workout recap, period review (6 ranges),
   exercise deep-dive, workout-vs-previous-session analysis, and a multi-turn chat that queries the
   user's own history through three data tools. Apple **FoundationModels**; nothing leaves the
   device (`Data/AICoach/Chat/`, `docs/ai-coach.md`).
2. **Double-progression progressive overload that writes back to the routine template** — hit the
   top of the rep range across all sets and the app proposes the weight jump at four points,
   including mid-workout *on the watch* and in the watch recap, then merges it into the iPhone
   template over a durable offline queue (`Domain/Services/ProgressiveOverloadService.swift`,
   `docs/rep-range-progressive-overload.md`).
3. **A genuinely standalone, hardware-native Apple Watch app** — live `HKWorkoutSession` with heart
   rate and active energy, Action Button (Ultra) / Double Tap set completion, auto-finish after the
   final set, crash- and jetsam-recoverable sessions, supersets synced bidirectionally
   (`docs/watch-auto-finish.md`, `docs/watch-workout-recovery.md`, `docs/action-button.md`).

**Supporting substance:** 96 seeded exercises across 19 muscle groups
(`Data/Seeding/SeedExerciseCatalog.swift`), progress charts (max weight / estimated 1RM / volume ×
1W-1M-3M-1Y-All), tappable muscle map, rest timer with Live Activity + Dynamic Island, HealthKit
write-back, iCloud/CloudKit sync, and no account, ever.

**Truth constraints the copy respects** (each of these is a rejection or one-star risk):

- **No widget claim.** `GymStreakWidgets.swift` is still unmodified Xcode boilerplate — only the
  Live Activity is real. Hence no `widget` keyword.
- **No "no subscription" claim** anywhere. Pro gating is live (`ProGating.shippedValue = true`);
  the no-**account** promise is untouched and still true.
- **AI Coach needs Apple Intelligence** (iOS 26+, supported hardware) and does **not** exist on the
  watch. The promo text therefore says "private on-device AI" as a property, never "every user gets
  an AI coach", and the AI claim is kept out of the subtitle — a 30-character field cannot carry the
  hardware qualifier, and an unqualified "AI" there sets an expectation older iPhones cannot meet.
- **Free vs Pro:** unlimited workout tracking and history, 3 routines, max-weight chart, 1W/1M/3M
  ranges and the **entire watch app** are free. "Track unlimited, free" is accurate; "unlimited
  routines" would not be.

---

## 4. en-US

### 4.1 Subtitle — 28/30 characters

```
Strength Training Plan & Log
```

Rationale: buys the four highest-value tokens still unspent by the title — `strength`, `training`,
`plan`, `log`. In combination with the title this ranks the app for *workout log*, *gym log*,
*strength training*, *strength tracker*, *training log*, *workout plan* and *training plan* without
repeating a single character of `GymStreak – Workout Tracker`. It also states the value proposition
literally: you plan the training, then you log it.

Alternates (all measured, pick one — do not run two):

| Variant | Chars | Trade |
| --- | --- | --- |
| `Strength Training Log & Plan` | 28 | Same tokens, log-first emphasis. Pure A/B. |
| `Lifting, Strength Plan & Log` | 28 | Swaps `training` → `lifting`; then move `training` into keywords and drop `lifting` from them. |
| `Weight Lifting & Strength Log` | 29 | Equipment/lifter framing, loses `plan` and `training`. |
| `Strength Log, Plan & Progress` | 29 | Buys `progress` into the higher-weighted field, loses `training`. |

### 4.2 Keyword Field — 99/100 characters

```
apple,watch,offline,private,superset,progressive,overload,lifting,weight,routine,calendar,1rm,ai,pr
```

**Rotated 2026-09-06** (`acquisition-strategy.md` §3 lever #3), replacing
`lifting,weight,bodybuilding,hypertrophy,powerlifting,muscle,exercise,routine,split,progress,1rm,ai`
(98). The old set was the generic strength-training cluster — accurate, and pointed straight at the
terms Hevy and Strong own. This one re-weights onto the niches §2 of `acquisition-strategy.md` calls
defensible, plus the two mechanics no competitor's metadata claims. Every choice below is backed by a
storefront autocomplete probe; the method and the raw results are §9.

Per-token intent:

| Token | Buys | Evidence (§9) |
| --- | --- | --- |
| `apple`, `watch` | ***workout tracker apple watch*** — the title already owns `workout` and `tracker`, so 12 characters complete a four-token query two of whose tokens are free. Also *apple watch workout app*, *watch workout log*. | Apple suggests "workout tracker apple watch" itself. See §4.2a |
| `offline` | *offline workout tracker*, *offline workout log*, *offline gym log* | A live cluster with competitors named after it — and the **only** searchable half of the privacy niche |
| `private` | *private workout logger*, *private workout tracker* | Thin (one suggestion) but the sole remaining carrier of the privacy positioning. On probation — §4.2a |
| `superset` | *superset gym log*, *superset workout tracker* | A live cluster; the app ships supersets on both iPhone and watch and no rival's metadata claims them |
| `progressive`, `overload` | ***progressive overload tracker***, *progressive overload app*, *progressive overload workout* | ~10 suggestions incl. dedicated apps. 21 characters, the field's biggest single spend, and the app genuinely ships double progression |
| `calendar` | *workout calendar*, *workout tracker calendar*, *gym tracker calendar* | 10 suggestions. **No competitor writes planned workouts to the system calendar** (Strong, Hevy, Fitbod, Jefit, Boostcamp, Alpha Progression — researched 2026-09-03, `app-store-description.md`), and the feature is free |
| `lifting`, `weight` | *weight lifting tracker*, *weight lifting log*, *lifting tracker* | Both live; the pair is what makes "weight lifting" reachable at all |
| `routine` | *workout routine*, *workout routine tracker*, *workout routine planner* | Among the highest-volume queries in the category, and cheap |
| `1rm` | *1rm log*, *1rm tracker* | A live cluster; 3 characters for a term the app genuinely computes |
| `ai` | *ai workout tracker*, *ai gym coach* | 2 characters, on-trend, and true (on-device AI Coach) |
| `pr` | *gym pr tracker*, *gym pr* | 2 characters; the app tracks personal records (`PersonalRecordService`) |

Compliance check (§1–§3): no spaces, no plurals, no competitor brand name, no `widget` token, no
title word (`workout`, `tracker`, `gym`, `streak` all absent), no subtitle word (`strength`,
`training`, `plan`, `log` all absent). `apple` is addressed on its own terms in §4.2a.

**One thing to watch:** `1rm` ranks the app for a metric that is **Pro-gated** — estimated 1RM is not
in `ProFeatureCaps.freeChartMetric`. A user arriving on "1rm tracker" meets a gate rather than the
feature. It is kept because 3 characters is a trivial bet and the free tier is otherwise generous,
but if the search-term report shows it converting into installs that churn, drop it first.

**Swap bench** — every token dropped from the previous set, with the reason, so a later rotation can
put it back against evidence rather than from memory:

| Dropped | Reason |
| --- | --- |
| `bodybuilding` | 13 characters for a cluster dominated by `bodybuilding.com` and general-fitness apps. Unrankable from 13 impressions/day. |
| `hypertrophy` | 12 characters, and the cluster is real but audience-narrow and already served by established apps (RP, Stimuli). The most defensible of the drops — first back on if the report is thin. |
| `powerlifting` | Its cluster is **calculator** and **federation** intent ("powerlifting calculator", "usa powerlifting"), not tracking. |
| `muscle` | Brand-dominated ("muscle booster", "musclewiki", "muscle monster"); "muscle tracker" is not a real query shape. |
| `exercise` | Plausible but unevidenced, and it lost a direct contest for characters with `superset` and `calendar`, which are evidenced *and* uniquely true of this app. |
| `split` | *workout split tracker* is live, so this is a genuine loss — dropped only because `private` had to carry the privacy niche and cost 8 characters. **First candidate to trade `private` for** if privacy shows nothing in the report. |
| `progress` | *gym progress tracker* is live, but `pr` buys an overlapping cluster for 6 fewer characters. |

Also on the bench, untested: `dumbbell`, `barbell`, `journal`, `volume`, `timer`, `rest`, `planner`,
`fitness`. `fitness` stays deliberately unbought in both locales (§7).

**The 1 unused character is deliberate** — the shortest possible addition is a comma plus a two-letter
token, and no unbought two-letter token is worth more than what is already there.

### 4.2a The `apple` and `watch` tokens — settled

This was the single highest-value open question of the rotation, and §7 already contains a rejection
that looks like it settles it. **It does not** — §7 rejected *"Apple Watch" in the subtitle*, which
is a different field, a different cost and a different risk. The distinction matters enough to write
down, because the next reader will otherwise "fix" this by deleting the tokens.

**Verdict: buy both, in the keyword field only.** §7's rejection stands for the subtitle unchanged.

| | Subtitle (rejected, §7) | Keyword field (bought) |
| --- | --- | --- |
| Cost | 11 of **30** visible characters | 12 of **100** invisible ones |
| Visible to the user? | Yes — it is the field that converts | **No.** It cannot affect conversion at all |
| What it competes with | `strength`, `training`, `plan`, `log` — the four tokens that doubled conversion | `bodybuilding`, `hypertrophy` — tokens the app cannot rank for anyway |

**Why both tokens, not just `watch`.** Tokens combine order-free across fields (§1), so the title's
`workout` + `tracker` plus a keyword `watch` already reaches *"workout tracker watch"*. But the query
Apple's own autocomplete suggests is **"workout tracker apple watch"** — and a query only matches if
*every* one of its tokens is indexed. Buying `watch` alone would miss the exact phrase the store says
people type. `apple` is 6 characters to complete it, and it is the cheapest high-intent token in the
field: two of the four tokens are already paid for by the App Name.

**On the supported-device badge.** §7 argued the App Store "already advertises" the watch app with an
automatic badge. That badge is a *product-page display* affordance — it tells a user who has already
found the listing that the app runs on their watch. **It is not a search-index entry.** Apple's own
App Store Search page enumerates what text relevance matches on — *"your app's title, subtitle,
keywords, and primary category"* — and **names no supported-device or platform signal at all**. The
one place a device facet does exist is the App Store *on the watch itself*, which filters to
watch-capable apps; that filter does not exist in iPhone search. There is also no separate watchOS
keyword field — the watch listing shares the iOS app's. So shipping a watchOS target buys **no**
"apple watch" indexing, and the tokens must be bought like any others. Treating a display badge as a
ranking signal was the reasoning error in §7's original framing; it is corrected here.

**On trademark (App Review Guideline 2.3.7) — researched, not assumed.**

- **What 2.3.7 actually prohibits** is metadata *"packed … with trademarked terms, popular app names,
  pricing information, or other irrelevant phrases **just to game the system**"*. Both operative
  conditions — gaming intent *and* irrelevance — fail here: the app genuinely ships a standalone
  watchOS target, so the token is relevant and truthful.
- **The other guidelines people cite do not apply.** 5.2.5 ("Apple Products") is entirely about UI
  confusability — Finder, Messages, Activity rings — and says nothing about metadata. 5.2.1 scopes to
  the app bundle and developer name, not the keyword field.
- **`watch` is an ordinary dictionary word** and no source flags it. `apple` is the token worth
  thinking about, and **no Apple primary source and no documented rejection ties either token in the
  private keyword field to a review failure.** That is *undocumented*, not *confirmed safe*.
- **The phrase problem cannot arise here.** The two sources that claim "Apple Watch" is disallowed in
  keywords are unsourced and date from the original Watch-Store era, and they are about the
  contiguous *phrase*. The keyword field is a comma-separated token list which Apple recombines
  itself, so `apple,watch` are two generic single words. **Never write `apple watch` as a phrase.**
- **The realistic downside is not rejection.** 2.3.7 ends *"Apple may modify inappropriate keywords
  at any time"*, and the documented enforcement pattern (Apple Developer Forums thread 112986,
  third-party marks like Scrabble and Boggle) is Apple **silently stripping** the keyword, not
  refusing the build. The asymmetry — 6 characters at risk versus the field's best query — makes this
  a cheap bet rather than a gamble.

If 1.1.16 is nonetheless rejected on 2.3.7 grounds, drop `apple`, keep `watch`, put the 6 characters
into `split`, and record the rejection here so it is never re-tried.

### 4.2b The privacy niche is much smaller than the strategy assumed

`acquisition-strategy.md` §2 lists "privacy / no account / offline" as one of two defensible niches
and names *"workout tracker no account"* as a target query. **That query does not exist.** Autocomplete
returns nothing for "workout no account", "workout without account", "workout no login", "no sign up
workout" or "workout tracker privacy" (§9).

**And the failure is demand, not reachability** — worth separating, because the two have different
fixes. `no` is a **stop word**: it appears on every published English stop-word list, so Apple strips
it from the query and owning `account` alone *would* have been enough to match "workout tracker no
account". The token was reachable for 8 characters. Nobody types the query. (`without`, by contrast,
is *not* a stop word and would have to be bought — moot, since that query is empty too.)

The no-account promise is still true, still worth stating in the description and promotional text
where it *converts*, and still a genuine differentiator. It is simply **not something people search
for**, so it cannot be bought with keywords. What remains searchable of that niche is `offline` —
a real cluster with competitors named after it — and, thinly, `private`. Both are bought; `account`
is not, and was never in a shipped set.

The strategy document has been corrected to say this rather than leaving the claim standing.

### 4.3 Promotional Text — 165/170 characters

```
Stop guessing your next weight. GymStreak spots when you've earned the jump, coaches you with private on-device AI, and tracks every set from your wrist. No account.
```

Leads with the actual pain (what do I load next?), names the differentiator that answers it
(double progression), then the privacy and watch hooks. No subscription claim, no unqualified AI
promise, no feature the app doesn't ship.

Alternates:

```
Every set, on iPhone and Apple Watch — plus a private on-device AI coach that reads your own numbers and says when to add weight. Unlimited tracking, free. No account.
```
(167 — leads with the free-tier reassurance instead of the pain)

```
Hit the top of your rep range and GymStreak proposes the next weight itself. Private on-device AI, standalone Apple Watch tracking, no account. Track unlimited, free.
```
(166 — most concrete about the mechanism; best for an audience that already knows double progression)

---

## 5. de-DE

### 5.1 Subtitle — 30/30 characters

```
Workout Tracker, Trainingsplan
```

Rationale: the German title spends nothing on the loanwords, so the subtitle buys all three top
German queries for this category — `workout`, `tracker`, `trainingsplan`. Note `Workout Tracker &
Trainingsplan` is **31** characters and does not fit; the comma is what makes it work. The listy
reading is standard on the German App Store and is the right trade for three head tokens.

Alternates:

| Variant | Chars | Trade |
| --- | --- | --- |
| `Krafttraining, Workout-Tracker` | 30 | Straight swap of `trainingsplan` → `krafttraining` (both 13 chars); audience framing instead of planning intent. Then move `trainingsplan` into the keyword field and drop `krafttraining` from it. |
| `Trainingsplan & Workout-Log` | 27 | Reads more naturally, gives up `tracker` (which then costs 8 keyword characters). |
| `Krafttraining & Workout-Log` | 27 | Same, audience-framed. |
| `Krafttraining & Trainingsplan` | 29 | Both compounds, no loanwords — only sensible if the de title later gains "Workout Tracker". |

### 5.2 Keyword Field — 99/100 characters

```
krafttraining,trainingstagebuch,muskelaufbau,superset,progressive,overload,offline,watch,ki,1rm,app
```

**Rotated 2026-09-06** (`acquisition-strategy.md` §3 lever #3), replacing
`krafttraining,muskelaufbau,bodybuilding,hantel,übung,gewicht,fitness,kraftsport,log,app,1rm,ki,timer`
(100). Derived independently of en-US against the **German** storefront's own autocomplete (§9), not
translated from it — and the evidence says the two locales want genuinely different fields (§5.2a).

**German is not a translation of the English field.** Compounds must be bought **whole**: assume that
`training` + `plan` does *not* rank you for "trainingsplan", and that `hantel` does *not* rank you for
"hanteltraining". That is why this field spends 17 characters on a single token and still ends up
with three fewer tokens than the English one — the compound tax is the defining constraint here.

**How certain is that?** Apple documents nothing about German compound splitting, and the vendor
claim that it "indexes compound words both as whole units and as their component parts" is templated
advice repeated across sites with **no experiment behind it**. The only published tokenization
experiment on the question (Radaso, on CJK scripts) found the App Store did *not* recombine
separately-listed words back into a compound — each variant had to be entered explicitly. So the
conservative reading is also the evidenced one: **buy the compound you want to rank for, and never
assume the parts imply it.** The Fugen-s specifically (Training**s**plan) is documented nowhere at
all.

Per-token intent:

| Token | Buys | Evidence (§9) |
| --- | --- | --- |
| `krafttraining` | *krafttraining tracker*, *krafttraining workout tracker* — completed by the subtitle's `workout`/`tracker` | 10 suggestions; a German head term |
| `trainingstagebuch` | the German "workout log" — *trainingstagebuch*, *gym trainingstagebuch* | 10 suggestions, several competitors named after it. **The single biggest German term this app was not indexed on** |
| `muskelaufbau` | *muskelaufbau trainingsplan app* — completed by the subtitle's `trainingsplan` | 10 suggestions |
| `superset` | *superset app*, *superset gym workout tracker* | Real in the **German** storefront — German lifters use the English loanword |
| `progressive`, `overload` | *progressive overload*, *progressive overload training* | 9 suggestions in the German storefront; the shipped German description already uses the English phrase as a heading |
| `offline` | *offline-training* — the only searchable half of the privacy niche in German | Thin (§5.2a) |
| `watch` | *watch trainingsplan*, and a hedge on Apple Watch intent the German store does not yet show | Weak — bought as a 6-character option, not a conviction (§5.2a) |
| `ki` | 2 characters for *ki trainingsplan* / *ki fitness app*; completed by the subtitle's `trainingsplan` | On-trend, and true (on-device AI Coach) |
| `1rm` | the estimated-1RM chart; high intent, tiny cost | — |
| `app` | completes the very common German pattern *fitness app* / *trainings app* / *workout app* | 10 suggestions on "fitness app" |

Compliance check (§1–§3): no spaces, no plurals, no competitor brand, no `widget`, no title token
(`gym`, `streak` both absent), no subtitle token (`workout`, `tracker`, `trainingsplan` all absent),
and every compound bought whole rather than assembled from parts.

**Swap bench** — every token dropped from the previous set, with the reason, so a later rotation can
put it back against the search-term report rather than from memory:

| Dropped | Reason |
| --- | --- |
| `bodybuilding` | The German cluster is brand- and general-fitness-dominated; 13 characters for traffic this app cannot rank against. |
| `hantel` | Autocomplete shows the demand sits on the **compound** `hanteltraining`, which `hantel` cannot match. Buy `hanteltraining` (14) or nothing — this token was buying almost nothing. |
| `übung` | The plural `übungen` is what users actually type, and **Apple's plural dedup is documented for English only** — German umlaut/ablaut plurals are undocumented across every source, so `übung` cannot be assumed to reach `übungen`. Buying it properly means buying `übungen` (7 chars), and the surviving suggestions ("gym übungen") lead with `gym`, which is title-locked. Not worth it at this budget. |
| `gewicht` | Its German cluster is **weight-loss/BMI/calorie** intent ("gewicht tracker & bmi", "gewicht tracker - kalorien") — the wrong audience, and a wrong-audience install is a one-star risk under §10's guardrails. |
| `fitness` | Highest volume in the category, hopeless to rank for from 13 impressions/day; its only value was combination coverage, now carried by `app`. |
| `kraftsport` | Only three suggestions, one of them a sports club. Far thinner than assumed when it was bought. |
| `log` | The German query is `trainingstagebuch`, which is now bought whole. `log` was an anglicism doing the same job worse. |
| `timer` | **Cannot match `pausentimer`** — the compound is the actual German query. Superseded, see below. |

**On the bench and newly evidenced** — candidates for the next rotation, strongest first:

| Candidate | Chars | Why it is worth knowing about |
| --- | --- | --- |
| `pausentimer` | 11 | A real German cluster of its own ("pausentimer gym krafttraining", "restbeat: gym pausentimer") that the old `timer` token could never reach. The app's rest timer with Live Activity is genuinely competitive here. **The strongest single thing this field could not afford.** |
| `hanteltraining` | 14 | Where the `hantel` demand actually lives. |
| `fortschritt` | 11 | Untested; the German counterpart to `progress`. |
| `hypertrophie`, `gewichtheben`, `studio`, `satz` | — | Untested, carried over from the previous bench. |
| `datenschutz` | 11 | **Do not buy.** Its German cluster is privacy-*tool* apps with no fitness intent at all (§9) — the token reads as on-strategy and is not. |
| `supersatz` | 9 | **Do not buy.** Zero autocomplete suggestions; German lifters search the English `superset`, which is what this field bought instead. |
| `konto`, `ohne` | — | **Do not buy.** "ohne konto" returns nothing at all (§9). See §5.2a. |

### 5.2a Why the German field is not the English one translated

The two locales' evidence diverges sharply, and the fields diverge with it. This is the concrete
form of §2's "the German title's spare surface is genuine free inventory" — the inventory is *German
compounds*, not German versions of the English tokens.

- **The Apple Watch niche barely exists in the German storefront.** "apple watch training", "workout
  apple watch", "apple watch gym" and "smartwatch training" all return **nothing**, and bare "apple
  watch" returns watch faces, games and step counters — no training intent whatsoever. en-US buys
  `apple`+`watch` on hard evidence (§4.2a); de-DE buys only the 6-character `watch` as a hedge and
  spends nothing on `apple`. If the search-term report shows German watch traffic, `apple` is the
  first thing to add.
- **The privacy/no-account niche is weaker still.** "ohne konto" returns nothing, and `datenschutz`
  belongs to privacy utilities. Only `offline` survives, and thinly.
- **What German has instead is compound vocabulary the international competitors do not buy.** The
  German App Store titles of the category leaders — "hevy – gym tracker workout log", "alpha
  progression gym tracker" — are English strings shipped unchanged into a German storefront. They do
  not contain `trainingstagebuch`, `krafttraining` or `muskelaufbau`. **That, not the watch, is the
  defensible German gap**, and this field is now pointed at it.

This refines `acquisition-strategy.md` §2: the two niches named there are real *in English*. In
German the defensible niche is the native compound vocabulary, and the strategy document has been
corrected to say so.

### 5.3 Promotional Text — 163/170 characters

```
Nie wieder raten, welches Gewicht als Nächstes kommt: GymStreak erkennt fällige Steigerungen, coacht dich privat auf dem Gerät und trackt jeden Satz am Handgelenk.
```

Alternates:

```
Jeder Satz auf iPhone & Apple Watch – dazu ein privater KI-Coach, der deine eigenen Zahlen liest und dir sagt, wann mehr Gewicht drauf kommt. Unbegrenzt tracken, gratis.
```
(169)

```
Oberes Ende deines Wiederholungsbereichs erreicht? GymStreak schlägt das nächste Gewicht selbst vor. Privater KI-Coach auf dem Gerät, Apple-Watch-Tracking, ohne Konto.
```
(167)

German uses ß and umlauts (de-DE storefront) and stays on the informal "du", consistent with the
Description and the in-app strings.

---

## 6. en-GB and en-AU — the English storefronts

**Derived 2026-09-07** (`acquisition-strategy.md` §3 lever #2, ticket
`03-en-gb-en-au-metadata-localizations`), against each storefront's own autocomplete by the §9
method. This section used to be a one-paragraph sketch that proposed the idea and guessed at the
answer; it is now the executed record, and where the sketch was wrong it is corrected rather than
left standing. The strings to type and the App Store Connect click path are §7 of
[`app-store-connect-actions.md`](./app-store-connect-actions.md).

Apple indexes each *localization*, not each country. The app ships **English + German only**
(`GymStreak/Resources/en.lproj`, `de.lproj`; watch `Localizable.xcstrings` has exactly `en`, `de`),
and **metadata localization is independent of app localization** — a storefront can carry its own App
Name, Subtitle, Keyword field, description and screenshots without a single translated string in the
binary. That is what makes en-GB and en-AU free of the one-star risk that makes the step-2 locales
(es-MX, es-ES, fr, it, pt-BR) a different decision: the UI those users get is the UI the metadata
promises.

### 6.1 The mechanic that decides everything else: a swap, not an addition

The old sketch said adding these localizations "gives another private 100-character keyword field for
those storefronts". **That is the wrong model, and getting it right changes what the fields should
contain.**

**What Apple documents** (App Store Connect Help, *Localize app information* and the *App Store
localizations* reference) is which localization each territory **displays** — never a word about
search indexing. Its table assigns localizations to territories, not the reverse: **English (U.K.) is
the default language for the vast majority of countries**, **English (Australia)** is the default for
**Australia and New Zealand**, **English (U.S.)** is the default for the **United States** alone
(Japan defaults to Japanese and lists English (U.S.) as an additional language), and English (Canada)
for Canada.

**Verified on this app, 2026-09-07.** `itunes.apple.com/lookup?id=6756426105&country=gb` and
`…&country=au` both return the **en-US** App Name (`GymStreak – Workout Tracker`) and the English
description, while `country=de` returns the de-DE name (`GymStreak`). So the UK and Australian
storefronts are served today by the app's **primary language**, standing in for a localization that
does not exist yet.

**What the ASO vendors add** — unanimously, and this is the part Apple does not state — is that the
same per-territory lists govern **search indexing**, not just display: a storefront indexes its
default localization plus its additional ones, and **en-US is on neither the UK's nor Australia's
list.** en-US reaches those storefronts only by *substitution*, because the slot is empty. Three
consequences follow, and all three are load-bearing:

1. **Adding en-GB is a swap.** Once en-GB exists it takes the slot and en-US drops out of those
   storefronts. The indexed keyword surface there stays at 100 characters. **So cloning the en-US
   keyword string into en-GB would buy exactly nothing** — the entire gain is the *delta* between the
   two fields. This is the real answer to the question the old sketch left open, and it is a stronger
   answer than the "portfolio" reasoning it was reaching for.
2. **The only genuine +100 comes from adding *both*, and Apple's own table says exactly where it
   applies.** The *App Store localizations* reference has a column titled **"Additional supported
   language(s)"**, and the relevant rows are unambiguous:

   | ISO | Country or region | Default language | Additional supported language(s) |
   | --- | --- | --- | --- |
   | AUS | Australia | English (Australia) | **English (U.K.)** |
   | NZL | New Zealand | English (Australia) | **English (U.K.)** |
   | GBR | United Kingdom | English (U.K.) | *(empty)* |
   | IRL | Ireland | English (U.K.) | *(empty)* |

   So **Australia and New Zealand carry two English localizations and the UK and Ireland carry one.**
   That asymmetry is the whole design: en-AU can be a pure complement because en-GB is present
   alongside it in both of its territories, while en-GB has to stand alone in the UK, Ireland and
   every other fallback storefront. The vendors' contribution is the claim that this display-language
   list also governs **indexing**, and that the two fields are then **two independent term pools**
   rather than one 200-character pool — a query matches inside one pool or not at all — so **a token
   repeated across the two fields is a wasted slot.** §6.2 and §6.3 share none.

   *(This settles a real vendor disagreement rather than papering over it: AppTweak and MobileAction
   list English (Australia) as a UK secondary; AppFollow and aso.dev list none. Apple's table agrees
   with the latter, so nothing may be routed into en-AU expecting the UK to see it.)*
3. **en-GB is not "the UK field" — it is the rest-of-the-English-speaking-world field.** It is
   Apple's documented default for the large majority of countries: Ireland, India, Singapore, South
   Africa, Hong Kong and on the order of a hundred-plus other storefronts, all of which serve en-US
   today and will serve en-GB the moment it exists. That is a large collateral surface, and it is the
   reason for the division of labour below — **en-GB carries the strong standalone set, en-AU carries
   the complement** — and a second reason to clone the App Name, Subtitle and Description verbatim
   (§6.5): it makes the collateral change invisible to every one of those storefronts.

**One input this leaves for Phase C, recorded because it is free and easy to miss.** The same Apple
table lists the **United States** as `English (U.S.)` **plus** *Arabic, Chinese (Simplified), Chinese
(Traditional), French, Korean, Portuguese (Brazil), Russian, Spanish (Mexico), Vietnamese* as
additional supported languages. If the vendors are right that the column governs indexing, then
es-MX, fr and pt-BR metadata — three of the five step-2 locales in `acquisition-strategy.md` §4.2 —
would each add a keyword field **indexed in the US storefront as well** as in their own. That
reframes step 2 from "reach Mexico and France" to "buy US keyword surface in another language", which
is a materially different case. It is **not** decided here and no step-2 field is drafted; it is the
first thing to check when that ticket is cut.

**Confidence, stated so a future reader weights this correctly.** **Apple-documented:** the
territory/fallback table (including the AUS/NZL/GBR rows above and the US list), and the
field-inheritance rule in §6.5 — both quoted from primary sources and re-verified 2026-09-07.
**Vendor consensus:** that the same lists govern *search indexing* and not merely which language is
displayed. **Inference:** that populating en-GB *removes* en-US from those storefronts' index — no
vendor says it in those words; it follows from the consensus model plus AppFollow's explicit
substitution wording for the fr-FR→fr-CA case. Sources in §9.

### 6.2 en-GB — Keyword Field, 98/100 characters

```
progressive,overload,superset,calendar,routine,planner,journal,progress,lifting,weight,watch,ai,pr
```

**This is the strong standalone set**, because most of the storefronts it serves index nothing else
(§6.1 consequence 3). Read it as a **delta against en-US** (§4.2), because that is mechanically what
it is: 22 characters of tokens that are **dead in these storefronts** are swapped for 22 characters
that are **live** in them. Ten of the fourteen en-US tokens survive the move unchanged.

| | Tokens | Chars |
| --- | --- | --- |
| **Out** (dead or poor-fit here) | `apple`, `offline`, `private`, `1rm` | 22 |
| **In** (live here, unaffordable in en-US) | `planner`, `journal`, `progress` | 22 |
| **Kept** | `progressive`, `overload`, `superset`, `calendar`, `routine`, `lifting`, `weight`, `watch`, `ai`, `pr` | — |

**What comes out, and on what evidence** (all probes GB `143444` / AU `143460`, §9):

| Dropped | Why |
| --- | --- |
| `apple` (6) | **The Apple Watch *fitness* cluster is a US-storefront phenomenon, not an English-language one.** "apple watch workout", "apple watch gym", "apple watch tracker" and "watch gym" are **all empty** in GB and AU while US self-suggests every one of them. The bare "apple watch" prefix is live in both — as *faces, dials, games, blood pressure, golf*. Buying `apple` there pays 6 characters into a device-utility cluster the app cannot serve. This is the single biggest en-US↔en-GB divergence and it corrects `acquisition-strategy.md` §2, which generalized a US probe into "English storefronts". |
| `offline` (7) | The niche §4.2b already shrank is thinner still here. "offline gym" and "workout log offline" are empty in both; "offline workout" returns **two** app names in GB/AU against **five** in US, where the bare query itself is suggested and one competitor is literally named *owt – offline workout tracker*. The bare `offline` prefix in GB/AU is games, music and maps. Seven characters for two app names lost a direct contest with `planner` (10 suggestions) and `journal` (10) — it moves to en-AU (§6.3), where the strong tokens are already covered. |
| `private` (7) | "private workout", "private gym log" and "workout privacy" are **all empty** in both storefronts — thinner than the single US suggestion that already put `private` on probation in §4.2. The privacy positioning survives where it converts (description, promotional text); it is not searchable here, in any field. |
| `1rm` (3) | §4.2 kept it as a cheap bet while flagging it **"drop it first"** — it ranks the app for a **Pro-gated** metric, and both storefronts' cluster is *calculator* intent ("1rm calculator", "1rm percentage calculator"). This field acts on that flag; en-AU picks it up as a marginal bet (§6.3). |

**What goes in:**

| Added | Buys | Evidence (§9) |
| --- | --- | --- |
| `planner` (7) | ***workout planner***, *gym workout planner*, *workout planner and tracker* — 10 suggestions, and **both partner tokens are already free** (`workout` and `gym` are title-indexed) | 10 GB, 10 AU — and 10 in **US**, where it has never been bought (bench note for the next US rotation) |
| `journal` (7) | ***workout journal*** — 10 suggestions, many of them competitors' own names — plus *gym journal* (5). Again a query the title completes for free | 10 GB, 10 AU |
| `progress` (8) | ***gym progress tracker***, *gym progress*, *track gym progress* — 10 suggestions with `gym` and `tracker` both free | 10 GB, 10 AU |

`pr` is **kept**, and it is worth saying why, because the first probe argued for dropping it: the
*"gym pr"* prefix that US self-suggests as "gym pr tracker" returns only `pro…`/`progress…`/
`program…` completions in GB and AU — but the *"pr tracker"* prefix returns **10 suggestions in all
three storefronts**, most of them gym PR-tracker apps. Two characters, and `tracker` is free from the
title. The lesson generalizes into a method rule: **one dead prefix is not evidence that a token is
dead** (§9).

`watch` is kept on the same reasoning de-DE uses (§5.2a): the GB/AU fitness-watch clusters are thin
("watch workout" returns 3–4 app names and no self-suggested query; "watch tracker" is a *watch
collection* cluster), but five characters is cheap insurance on the app's largest genuine
differentiator, and if the semantic layer described in §9 ever relates "apple watch" queries to a
bare `watch` token, this is where that lands.

**Compliance check (§1–§3):** 98 characters, no spaces, commas only, 13 tokens, no duplicates, no
plurals, no competitor brand, no `widget`; no title token (`workout`, `tracker`, `gym`, `streak`) and
no subtitle token (`strength`, `training`, `plan`, `log`) — the App Name and Subtitle are cloned from
en-US (§6.5), so both exclusion lists carry over unchanged. Verified programmatically, not by eye.

**Two tokens carry a documented risk of being wasted characters.** `planner` sits next to the
subtitle's `plan`, and `progress` next to this field's own `progressive`. Apple documents token
deduplication for **singular/plural only** (§7); derivational pairs like plan→planner and
progress→progressive are undocumented everywhere. If Apple's stemmer does unify them, 15 characters
are wasted. The bet is taken because the clusters are the two largest in the field and the failure is
cheap — but it is the **first thing to test against the search-term report**: if neither token returns
impressions, the stemmer unified them and those 15 characters go to `hypertrophy`.

**The 2 unused characters are deliberate** — the shortest useful addition is a comma plus a two-letter
token, and none is left unbought.

### 6.3 en-AU — Keyword Field, 98/100 characters, deliberately disjoint

```
hypertrophy,timer,rest,coach,program,split,diary,exercise,offline,volume,powerlifting,1rm,dumbbell
```

**Design rule: this field shares not one token with §6.2.** Australia and New Zealand index en-AU
*and* en-GB (§6.1 consequence 2), so a token repeated here would buy a slot the other pool already
owns. Every character is therefore spent on the best *unbought* clusters — which is also why this
field reads as a lower-fit set than en-GB: it is not competing with it, it is completing it.

| Token | Chars | Buys | Evidence |
| --- | --- | --- | --- |
| `hypertrophy` | 11 | *hypertrophy log*, *hypertrophy: gym workout log*, and the dedicated trackers (Stimuli, RP Hypertrophy) | 10 suggestions in both storefronts, with genuine **tracker** intent — the best unbought token there was |
| `timer`, `rest` | 5 + 4 | ***gym timer*** (10), ***rest timer*** (10), *gym rest timer*, *gym rest timer between sets* — `gym` is free from the title | Two 10-suggestion clusters for nine characters, and the app genuinely ships a rest timer with a Live Activity |
| `coach` | 5 | ***gym coach*** (10) — `gym` is free from the title, so five characters buy the whole query | Live in both; the app ships the AI Coach (§3's hardware qualifier lives in the description, never in a keyword) |
| `program` | 7 | *gym program*, *gym program free* — `gym` free | **The one measured GB↔AU vocabulary difference that survived** (§6.4): Australian English uses *program*, and this is the field where it belongs |
| `split` | 5 | *gym split*, *workout split*, *muscle building workout split* | Self-suggested in both; en-US dropped it only for characters (§4.2 bench) |
| `diary` | 5 | *gym diary*, *workout diary* | Live in all three storefronts (§6.4 — it is **not** a British preference, just an unbought one) |
| `exercise` | 8 | *exercise log* (`log` free from the subtitle), *exercise tracker* | Thin (3–4) but on-strategy and cheap in a complement field; en-US called it "plausible but unevidenced" |
| `offline` | 7 | *offline workout*, *offline workout log* | The privacy pillar's only searchable half (§4.2b). Too thin to earn a slot in en-GB, worth a marginal bet here |
| `volume` | 6 | *volume tracker*, *workout volume tracker* | Thin (2–3), truthful (the app charts volume) |
| `powerlifting` | 12 | *powerlifting ai: gym coach*, *gymlog powerlifting tracker*, *grind – powerlifting programs* | The field's second-biggest spend. en-US dropped it because its **US** cluster is calculator- and federation-intent; the AU list carries noticeably more *tracker* apps. A genuine locale difference, and a genuine bet |
| `1rm` | 3 | *1rm calculator*, *1rm weight lifting rep max* | Calculator intent and a Pro-gated metric — exactly why it left en-GB. Three characters in the complement field is the right size for that bet |
| `dumbbell` | 8 | *dumbbell workout*, *dumbbell exercises* | **The weakest token in either field, and knowingly so.** The cluster is home-workout-guide intent (§6.6), and it is bought only because en-AU's characters would otherwise sit idle. **First to drop.** |

**Compliance check (§1–§3):** 98 characters, no spaces, 13 tokens, no duplicates, no title or
subtitle token, no competitor brand, no `widget`, no plural anywhere — including no plural *of an
en-GB token*, which is why `weights` is benched despite Australia leaning to it (§6.6). Zero overlap
with §6.2 verified programmatically.

**What the split costs, stated plainly.** Because the two pools do not combine (§6.1), a query whose
tokens land in *different* fields is reachable from neither. Each token above still combines freely
with the App Name and Subtitle, which are cloned into both localizations — so `coach` reaches "gym
coach", `program` reaches "gym program", `exercise` reaches "exercise log". What is forfeited is the
cross-pool phrase: **"ai gym coach" is unreachable in Australia and New Zealand**, because `ai` is in
en-GB and `coach` is in en-AU. `ai` stays where it is deliberately — it also buys *ai workout
tracker* for the hundred-plus territories that see en-GB **alone**, and those matter more than one
query in two small storefronts.

**The one way this field can be wrong**, now that Apple's own table confirms en-GB is a supported
language in both of en-AU's territories (§6.1), is if that column governs only which language is
*displayed* and not what is *indexed*. In that case Australia and New Zealand would be indexed on
this complement alone and would lose `progressive overload`, `superset` and `calendar`. The fix is
one edit and one submission — **paste the §6.2 string into en-AU** — and the downside is bounded to
two storefronts that between them account for none of the current customer base
(`acquisition-strategy.md` §1, n=100). That asymmetry is why the disjoint design is worth running now
rather than waiting for proof that will never arrive at this volume.

### 6.4 UK and Australian search vocabulary — what was actually tested

The two fields differ for **coverage** reasons (§6.1), not vocabulary ones. But the vocabulary work
still had to be done — the ticket that cut this section required the UK and Australian markets to be
assessed rather than assumed, *including whether they differ from each other* — and it is what put
`program` in one field and not the other. Findings, in full, including the ones that came back
negative:

| Hypothesis | Result | Verdict |
| --- | --- | --- |
| **`programme` (UK) vs `program` (AU/US)** | **Real.** GB self-suggests **"gym programme"** and returns a full ten-item list for the "workout programme" prefix; AU returns "gym program"/"gym program free" and **no** `programme` form — matching Australian English's official adoption of *program*. | Acted on: **`program` is in en-AU** (§6.3). `programme` (9) lost to `journal` (7) for a much larger cluster and sits at the top of the en-GB bench. |
| **`-ise` vs `-ize`** | **Real.** "personalised workout" returns suggestions in GB (3) and AU (2); **"personalized workout" is empty in both.** | Not bought: 12 characters for a 3-suggestion cluster, and "personalised workout" implies an app that writes the plan for you — a claim §3 does not allow. Recorded because the axis is real and the next English locale should re-test it. |
| **`diary` (UK) vs `journal` (US)** | **False.** Both are live in **all three** storefronts — "workout journal" returns 10 everywhere, "gym diary" 4–5 everywhere. There is no UK preference for *diary*. | Both bought, in different pools, on cluster size alone — not on nationality. |
| **AU-specific vernacular** (`sesh`, `gym session`) | **Dead.** "gym session" returns one app name in both; "sesh" is dominated by unrelated apps. | Not bought. |
| **`weights` plural (AU)** | **Real but unusable.** AU ranks "weights tracker" and "weights workout tracker log" first for that prefix where GB ranks "weights workout". | Not bought: it is the plural of en-GB's `weight`, and Apple's documented English plural dedup (§7) means the en-GB pool very likely already covers it in AU/NZ. |
| **Everything else in both fields** | GB and AU returned the same clusters at comparable depth. | No divergence to act on. |

The honest summary: for the queries this app can serve, **the UK and Australian storefronts are
almost the same market**, and exactly one spelling difference was worth spending characters on.
Manufacturing more difference to look thorough would have cost real characters.

### 6.5 App Name, Subtitle, Description, Promotional Text — all cloned, and why

**Apple prefills most of this for you.** App Store Connect Help, *Localize app information*: *"When
you add a language to your app, screenshots and the properties for the new language default to those
of the primary language, **except for the description and keywords**."* So "clone" means *leave the
prefilled value alone* for the App Name, Subtitle, Promotional Text and screenshots, and **only the
Description and the Keyword field have to be entered by hand** — which is convenient, because the
keyword field is the entire point of the exercise.

| Field | Decision | Reason |
| --- | --- | --- |
| **App Name** | Clone `GymStreak – Workout Tracker` | Both keyword fields' exclusion lists are computed from it (§2). Varying it per storefront would mean re-deriving each field against a different exclusion list, for no evidenced gain — and it would change the listing in the hundred-plus territories en-GB serves (§6.1). |
| **Subtitle** | Clone `Strength Training Plan & Log` (28/30) | **The subtitle is the field that converts** — the 2026-08-25 pass it belonged to doubled page-view→download conversion (`acquisition-strategy.md` §1). Nothing in the GB/AU probes suggests a different subtitle would convert better, and both keyword fields' exclusions assume it. Same freeze as §4.1 and §5.1. |
| **Description** | Clone verbatim from **App Store Connect's own en-US field**, including the US spelling "analyzes" | Not indexed — it converts, it does not rank (§1) — so cloning costs nothing in search. A spelling pass was run anyway: **"analyzes" is the only Americanism in all 3,898 characters.** Anglicizing it would create two more copies of a 3,900-character text to keep in sync through every future edit, and the divergence, not the word, is the risk. If it is ever varied, `analyses` is the entire change. **Copy from App Store Connect, not from `app-store-description.md`** — that document deliberately stages unpublished copy (the calendar-sync paragraph). |
| **Promotional Text** | Clone (Apple prefills it) | The one field editable **without** a version submission (§1), so it is never blocked on a release. That makes it the right field to vary per storefront **later**, once there is data to vary against — not now, on a guess. |

### 6.6 Swap benches

Everything probed and not bought, so a later rotation argues with evidence instead of memory.

**en-GB bench** — what the standalone field could not afford:

| Token | Chars | Evidence | Note |
| --- | --- | --- | --- |
| `hypertrophy` | 11 | 10 suggestions, tracker-intent apps | Bought in **en-AU** instead (§6.3). If the dual-index claim fails, this is the first token to move into en-GB. |
| `programme` | 9 | GB self-suggests "gym programme"; AU does not | Top of this bench, and **it can only ever live in en-GB itself**: Apple's table gives the UK and Ireland *no* additional supported language (§6.1), so routing it through en-AU would never reach a British searcher. Buying it means giving up `journal` (7) or `progress` (8). |
| `split`, `diary`, `timer`, `rest`, `coach`, `offline`, `exercise`, `volume`, `1rm` | — | See §6.3 | All bought in en-AU. Listed here so the next reader does not "discover" them twice. |
| `personalised` | 12 | GB 3 / AU 2; `-ized` empty | Real but unaffordable, and a §3 truth stretch. |
| `weights` | 7 | AU leans plural | Plural of en-GB's `weight` (§6.4). |
| `fitness` | 7 | Highest volume in the category | Deliberately unbought in every locale (§7). |

**en-AU bench** — what the complement field turned down:

| Token | Chars | Evidence | Note |
| --- | --- | --- | --- |
| `barbell` | 7 | 10 suggestions — plate calculators, gyms, podcasts, one home-workout app | Lost to `dumbbell` on cluster size; both are weak. |
| `bodybuilding`, `muscle` | 13 / 6 | Brand-dominated in GB and AU exactly as in US (`bodybuilding.com`, "muscle nation", "muscle republic", "muscle chef") | Confirms §4.2's drops generalize. **Do not re-buy them here on the theory that they are "en-US rejects".** |
| `calisthenics` | 12 | 10 suggestions, all workout-guide intent | Wrong audience for a logger. |
| `conditioning` | 12 | *Air* conditioning, plus S&C gym brands | Looks on-strategy, is not. |
| `bench`, `squat`, `deadlift`, `exercise library` | — | 1–3 suggestions each | Exercise-name queries are not a cluster worth buying. |
| `gym session`, `sesh` | — | One app name / unrelated apps | Not bought. |
| `private`, `apple` | 7 / 6 | Empty and wrong-intent respectively, in both storefronts (§6.2) | Dead in every English storefront but the US. |

**A note on the sketch this section replaced.** It proposed varying these fields "toward terms
[en-US] had to drop (`dumbbell`, `barbell`, `journal`, `fitness`)". Tested: `journal` was right and
is bought; `dumbbell` and `barbell` are home-workout-guide intent and only one is bought, last and
weakest; `fitness` remains unbuyable in every locale. **The reasoning behind the sketch was the
part that was wrong** — en-US's rejects are not a shortlist for another storefront, because most of
them were rejected for reasons that travel (brand-dominated clusters, wrong intent). Only the ones
en-US dropped for *characters* came back.

---

## 7. Deliberate omissions

- **`gym`, `streak`, `workout`, `tracker`** — title-indexed per locale (§2). Never re-buy.
- **`widget`** — the widget target is still Xcode boilerplate; claiming it invites a one-star review.
- **Competitor brand names** — excluded by policy and by App Review Guideline 2.3.7. Do not add
  them to the swap benches.
- **Plurals** — omitted wherever the singular is indexed. **This is safe in English only.** Apple
  documents plural dedup with an English example ("climbs"/"climb" are "considered duplicates") and
  says nothing about other languages; AppTweak's test of 100 pairs found even the English behaviour
  is inconsistent, and **German umlaut plurals (`übung`→`übungen`, `satz`→`sätze`) are undocumented
  everywhere**. For German, buy the form users actually type rather than trusting the stemmer —
  which is one of the reasons `übung` was dropped (§5.2).
- **"Apple Watch" in the *subtitle*** — 11 of 30 visible characters, and the subtitle is the field
  that converts (§4.1). Still rejected in every locale. **This is not the same question as the
  `apple`/`watch` tokens in the private keyword field**, which en-US now buys deliberately — see
  §4.2a, which settles the distinction.
- **`apple` outside en-US** — the Apple Watch *fitness* cluster only exists in the **US** storefront's
  autocomplete. GB, AU and DE all return nothing for "apple watch workout"/"apple watch gym", so
  en-US is the only field that buys `apple`; de-DE and en-GB buy a bare 5-character `watch` hedge
  instead (§5.2a, §6.2). The niche is a **US** asset, not an English-language one.
- **`private` everywhere but en-US** — "private workout", "private gym log" and "workout privacy" are
  empty in GB and AU, and the German equivalents are empty too (§5.2). The privacy pillar stays where
  it converts, in the description and promotional text; it is not searchable. `offline` is the one
  searchable fragment of it and is bought in en-US and en-AU (§4.2b, §6.3).
- **`personalised`, `programme`, `weights`** — genuine British/Australian forms with genuine demand,
  priced out rather than dismissed; the Australian `program` **is** bought, in en-AU (§6.4). The
  benches in §6.6 carry the reasons and the conditions under which each comes back.
- **`konto` / `ohne` / `datenschutz` (de)** — the German no-account and privacy queries do not exist
  in the store's own autocomplete, and `datenschutz` belongs to privacy utilities (§5.2, §5.2a).
- **`supersatz` (de)** — zero autocomplete suggestions; German lifters search the English `superset`.
- **"AI" in the subtitle** — kept in the keyword field (`ai` / `ki`) and the promotional text, where
  the on-device/hardware qualifier fits. See §3.
- **`fitness`** — highest volume in the category and hopeless to rank for from 13
  impressions/day, in either locale. See §4.2 and §5.2.

## 8. Maintenance

- **There are now four keyword fields: en-US, de-DE, en-GB, en-AU.** Re-derive a field whenever the
  **App Name** of its storefront changes (§2). The two new English fields **inherit the en-US App
  Name and Subtitle verbatim** (§6.4), so a change to *either* of those invalidates **all three**
  English keyword fields at once, not just en-US.
- Subtitle and keyword-field edits ride a **version submission**; schedule them with a release, not
  as a hotfix — and so does **adding a localization**, which is why en-GB/en-AU are bound to a
  release too. `app-store-connect-actions.md` holds the current target and the click paths.
- **When the next rotation is due, and why the clock restarted.** The original rule here was "after
  ~4 weeks live, read the search-term report and rotate". That never happened for the 2026-08-25 set:
  the keyword half was rotated again on **2026-09-06**, before four weeks had elapsed, because the
  invisible field costs nothing to move and impressions were falling (`acquisition-strategy.md` §1).
  **No search-term report has ever been read for this app.** The first one becomes available roughly
  four weeks after **1.1.16 goes live**, and *that* is the input to the next rotation — read it
  against the swap benches in §4.2, §5.2 and §6.5 before touching any field again — and read it
  **per storefront**, because the four fields no longer contain the same tokens.
- **Rotate the invisible field freely; leave the visible one alone.** The keyword field cannot affect
  conversion, so a bad set costs only the characters. The subtitle drove a measured **+110%**
  page-view→download conversion and is not a place to experiment (§4.1, §5.1).
- Keep the free-vs-Pro wording in §3 in sync with `Domain/Models/Pro/ProFeatureCaps.swift` and
  `docs/pro-subscription.md`. A cap change can silently make "Track unlimited, free" false.

---

## 9. Evidence — how the keyword sets were derived

The pre-2026-09-06 sets were derived from category reasoning. Every set since has been derived from **Apple's own
search autocomplete**, per storefront, which is the closest thing to free query-demand data that
exists without a paid ASO tool: the suggestions are Apple's, ranked by popularity, and they are
storefront-specific.

```
curl -s "https://search.itunes.apple.com/WebObjects/MZSearchHints.woa/wa/hints?clientApplication=Software&term=<url-encoded>" \
  -H "X-Apple-Store-Front: <id>-1,29" -H "User-Agent: iTunes-iPhone/12.0 (5; 16GB)"
```

Storefront IDs: **US `143441`**, **DE `143443`**, GB `143444`, AU `143460`. Without the
`X-Apple-Store-Front` header the response is an empty suggestion list, which looks like "no demand"
and is not — that is the trap to avoid when re-running this.

**How to read it.** A prefix returning ten suggestions is a live, popular query cluster. A prefix
returning **nothing** is strong evidence that no *popular* query starts that way — it is not proof of
zero volume, but it is enough to refuse to spend characters. Several tokens that read as obviously
on-strategy returned nothing at all, which is the single most useful thing this exercise produced.

| Probe | Result | Consequence |
| --- | --- | --- |
| `workout tracker` (US) | suggests **"workout tracker apple watch"** and **"workout tracker calendar"** | The two tokens en-US added that it already half-owned (§4.2a) |
| `progressive overload` (US **and DE**) | ~10 suggestions each, incl. dedicated apps | Justified 21 characters in *both* fields |
| `offline workout` (US) | competitors literally named "offline workout tracker" / "offline workout log" | `offline` is the searchable half of the privacy niche |
| `trainingstagebuch` (DE) | 10 suggestions, several competitors named after it | The biggest German term the app was not indexed on |
| `pausentimer` (DE) | 8 suggestions | `timer` cannot match the compound — see §5.2 bench |
| `workout no account`, `workout without account`, `workout no login`, `workout tracker privacy` (US) | **all empty** | The "no account" *query* does not exist — see §4.2a |
| `ohne konto`, `apple watch training`, `apple watch gym`, `smartwatch training` (DE) | **all empty** | Drove the whole en/de asymmetry in §5.2a |
| `supersatz` (DE) | **empty** | German uses the English `superset` |
| `gewicht tracker` (DE) | BMI / calorie / diet apps | Wrong audience — dropped (§5.2) |
| `datenschutz` (DE) | privacy utilities, no fitness intent | Looks on-strategy, is not |
| `bodybuilding`, `muscle`, `powerlifting` (US) | brand- and calculator-dominated | Dropped (§4.2) |

**The en-GB / en-AU probes (2026-09-07, §6).** Same method, storefronts `143444` and `143460`. Run
against **both** so the two locales could be compared with each other, not just with en-US.

| Probe (GB and AU unless noted) | Result | Consequence |
| --- | --- | --- |
| `apple watch workout`, `apple watch gym`, `apple watch tracker`, `watch gym`, `apple watch log` | **all empty in GB and AU**; US self-suggests the first three | **The Apple Watch fitness cluster is US-only.** Dropped `apple`; corrects `acquisition-strategy.md` §2 |
| `apple watch` (bare) | 10 in both — faces, dials, games, blood pressure, golf | Live prefix, wrong intent: a device-utility cluster the app cannot serve |
| `watch workout` | GB 3 / AU 4 app names, no self-suggested query | `watch` kept as a 5-character hedge only (§6.2) |
| `pr tracker` | **10 in GB, AU and US**, mostly gym PR-tracker apps | `pr` **kept** — the dead prefix was "gym pr", not the token (§6.2) |
| `gym pr`, `gym pr tracker` | `pro…`/`progress…`/`program…` completions only; US self-suggests "gym pr tracker" | The finding that nearly cost `pr` its place |
| `workout planner` | 10 in GB, AU **and US** | Bought in both new fields; **unbought in en-US** — bench note for the next US rotation |
| `workout journal` / `gym journal` | 10 / 5 in both | Bought (`journal`) |
| `gym progress` | 10 in both | Bought (`progress`), replacing nothing — en-US spends those characters on `1rm` |
| `offline workout` | **GB 2 / AU 2** app names vs **US 5** incl. the bare query and *owt – offline workout tracker* | Dropped `offline` outside en-US (§6.2) |
| `offline gym`, `workout log offline` | empty in both | Same |
| `offline` (bare) | games, music, maps | Same |
| `private workout`, `private gym log`, `workout privacy` | **all empty in both** | Dropped `private` outside en-US |
| `1rm` | 10 in both — "1rm calculator", "1rm percentage calculator" | Calculator intent + Pro-gated metric → dropped (§6.2) |
| `gym programme` / `programme` (bare) | GB self-suggests **"gym programme"**, and it appears in GB's bare-`programme` top ten; AU returns `program` forms only | The one real GB↔AU difference; unaffordable (§6.3) |
| `personalised workout` / `personalized workout` | GB 3 / AU 2 — vs **empty in both** for the `-ize` spelling | The `-ise`/`-ize` axis is real; not bought (§6.3) |
| `gym diary`, `workout diary`, `workout journal` | live in **all three** storefronts | No UK "diary" preference — the sketch's assumption tested and refuted (§6.3) |
| `gym timer`, `rest timer` | 10 each in both | Live, poor fit, benched (§6.5) |
| `hypertrophy` | 10 in both, with tracker-intent apps | First token back on the bench (§6.5) |
| `dumbbell`, `barbell` | 10 each — home-workout guides, gyms, plate calculators | The §6 sketch's own suggestions, refuted |
| `bodybuilding`, `muscle`, `powerlifting` (GB, AU) | brand- and calculator-dominated exactly as in US | §4.2's drops generalize; do not re-buy as "en-US rejects" |
| `gym session`, `sesh`, `conditioning`, `calisthenics`, `volume tracker` | 0–3 relevant, or unrelated (air conditioning) | Not bought |
| `gym coach` | 10 in both | Bought (`coach`) in en-AU — `gym` is free from the title |
| `bench press`, `squat tracker`, `deadlift`, `exercise library` | 1–4 each | Exercise-name queries are not a buyable cluster |
| `gym programme` (bare `programme` too) | GB self-suggests "gym programme" and carries it in the bare-prefix top ten; AU returns `program` forms only | The one GB↔AU difference acted on: `program` → en-AU (§6.4) |

**One method caveat learned here.** A single empty prefix is **not** evidence that a token is dead:
`pr` looked dead on "gym pr" and is live on "pr tracker". Probe every prefix a token plausibly
appears in before reallocating its characters.

**The public iTunes Search API is not the App Store search index and must not be used for this.**
It was tried: it returns nothing for `hypertrophy` in the US storefront even while that token was in
the live en-US keyword field, and it *does* match description text (it returns the app in the DE
storefront for `hypertrophy`, a word the German keyword field has never contained). It is useful for
exactly one thing — reading back **which localization a storefront is currently serving**
(`https://itunes.apple.com/lookup?id=6756426105&country=gb`), which is how §6.1 was verified.

**Caveats, stated so the next reader weights this correctly.** Autocomplete shows *prefix* popularity,
not volume, not competition, and not conversion. It says a query exists and is typed; it does not say
the app can rank for it. It is the best available input **until the first search-term report exists**
(§8) — at which point real impression data outranks everything in this section.

**One moving part underneath all of it.** AppTweak dates a significant App Store search change to
**5 June 2025**, toward balancing multiple plausible intents and evaluating keywords "in groups
rather than as isolated terms", and Apple's own copy now says people "can use natural, everyday
language when performing a search". Nothing documents exact-token eligibility being *replaced* — the
semantic layer appears to sit on top of it, which is why this document still budgets tokens. But if a
future rotation finds token-level reasoning predicting badly, this is the first thing to suspect.

**Sources for the mechanics asserted in §1, §4.2a and §5.2** (the demand claims above are the probes
themselves): Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
2.3.7, [App Store Search](https://developer.apple.com/app-store/search/),
[Marketing Resources and Identity Guidelines](https://developer.apple.com/app-store/marketing/guidelines/),
[Guidelines for Using Apple Trademarks](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html),
[Developer Forums thread 112986](https://developer.apple.com/forums/thread/112986) (keyword
stripping); [Appfigures stop-word list](https://appfigures.com/resources/guides/keyword-optimization-app-store-connect),
[Radaso stop-word](https://radaso.com/asomythbusters-experiments/experiment-free-words-in-metadata-how-do-stop-words-work-in-the-app-store)
and [tokenization](https://radaso.com/asomythbusters-experiments/experiment-aso-for-asian-scripts-do-you-need-to-duplicate-keywords-from-title-and-split-phrases-into-words)
experiments, [AppTweak singular/plural](https://www.apptweak.com/en/aso-blog/do-singular-or-plural-keywords-rank-differently-in-aso)
and [June 2025 algorithm change](https://www.apptweak.com/en/aso-blog/ai-reshaping-app-store-relevance),
[Gummicube keyword rules](https://www.gummicube.com/blog/app-store-keyword-rules-to-remember).

**Sources for the localization mechanics in §6.1 and §6.5.** Apple, for the parts that are
documented: [Localize app information](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information/)
(the field-inheritance rule quoted in §6.5, and the primary-language screenshot trap),
[App Store localizations reference](https://developer.apple.com/help/app-store-connect/reference/app-store-localizations/)
(which localization serves which territory) and
[Version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
(which fields are required per localization). For the per-storefront *index* lists, which Apple does
not document at all: [AppTweak](https://www.apptweak.com/en/aso-blog/how-to-benefit-from-cross-localization-on-the-app-store),
[MobileAction](https://www.mobileaction.co/blog/app-store-cross-localization/),
[aso.dev](https://aso.dev/metadata/cross-localization/),
[AppFollow](https://appfollow.io/app-store-keywords-localizations) and
[Phiture](https://phiture.com/asostack/increasing-the-number-of-keywords-in-app-store-optimization-by-localization-daa02ffd8946/).
The vendor tables disagreed about whether the UK has a secondary localization at all; **Apple's own
reference settles it** (GBR and IRL have an empty "additional supported language(s)" cell, AUS and
NZL both list English (U.K.)). §6.1 states which parts of the design rest on Apple's wording and
which on the vendors' claim that the same lists govern indexing.
