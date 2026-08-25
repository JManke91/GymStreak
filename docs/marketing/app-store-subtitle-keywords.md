# App Store Subtitle, Keyword Field & Promotional Text

ASO copy for the three **indexed / above-the-fold** App Store fields that were still missing from
`docs/marketing/`. The App Name and the Description are finalized elsewhere:

- App Name — **not** in this doc, see the "Title constraint" section for the strings in use
- Description → `docs/marketing/app-store-description.md` (conversion asset, **not indexed**)
- Promotional Text → earlier variants live in `docs/marketing/app-store-promotional-text.md`; this
  doc adds a set coordinated with the subtitle/keyword pass below

Created 2026-08-25 against app version **1.1.12**.

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
2. **Therefore every repeated word is a wasted character.** A token indexed by the title must never
   be bought again in the subtitle or the keyword field.

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

### 4.2 Keyword Field — 98/100 characters

```
lifting,weight,bodybuilding,hypertrophy,powerlifting,muscle,exercise,routine,split,progress,1rm,ai
```

Compliance check: no spaces, no plurals, no competitor brand, no title word (`workout`, `tracker`,
`gym`, `streak` all absent), no subtitle word (`strength`, `training`, `plan`, `log` all absent).

Per-token intent:

| Token | Buys |
| --- | --- |
| `lifting`, `weight` | weight lifting, weight training, lifting log, weight tracker |
| `bodybuilding`, `powerlifting`, `hypertrophy` | the exact audience; high intent, far lower competition than head fitness terms |
| `muscle` | muscle gain / muscle tracker intent, feeds the 19-muscle-group library and muscle map |
| `exercise` | exercise log / exercise tracker — a real second head term |
| `routine` | *workout routine*, one of the highest-volume queries in the category |
| `split` | workout split, push pull legs split — planning intent |
| `progress` | progress tracker, training progress — the charts |
| `1rm` | 3 characters for a high-intent, low-competition term the app genuinely computes |
| `ai` | 2 characters for *ai workout tracker* / *ai coach* traffic; on-trend and true |

**The 2 unused characters are deliberate.** The shortest addition costs 3 (comma + a 2-letter
token), and no remaining 2-letter token is worth more than the tokens above. Do not pad with a
filler; `…,routine,planner,progress,1rm,ai` hits exactly 100 if you prefer `planner` over `split`
(also captures *workout planner*, and prefix-matching means it covers `plan` queries too).

Swap bench, if a term underperforms in App Store Connect's search-term report: `dumbbell`,
`barbell`, `timer`, `journal`, `volume`, `superset`, `pr`, `fitness`. `fitness` is intentionally
omitted — highest volume in the category and hopeless to rank for from this position; its only value
is combination coverage, which the tokens above already provide more cheaply.

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

### 5.2 Keyword Field — 100/100 characters

```
krafttraining,muskelaufbau,bodybuilding,hantel,übung,gewicht,fitness,kraftsport,log,app,1rm,ki,timer
```

**German is not a translation of the English field.** Apple does not split German compounds, so a
compound query only matches an indexed *compound* — `training` + `plan` does not rank you for
"trainingsplan". Compounds must be bought whole, which is why the German field spends 13 characters
on `krafttraining` and 12 on `muskelaufbau` where English gets away with single words.

Per-token intent: `krafttraining` and `muskelaufbau` are the two German head terms for this app's
purpose; `kraftsport` is the audience noun; `bodybuilding` carries over unchanged; `hantel` buys
equipment queries ("hantel training"); `übung` and `gewicht` are the core objects the app manipulates;
`log` completes *workout log* with the subtitle's `workout`; `app` completes the very common German
pattern *fitness app / workout app / trainings app*; `fitness` for combination coverage; `1rm` and
`ki` are 3 and 2 characters for the estimated-1RM chart and the AI coach; `timer` for the rest timer.

Compliance: no spaces, no plurals (`übung` not `übungen` — Apple's German stemming handles the
plural), no competitor brand, no title token, and no subtitle token (`workout`, `tracker`,
`trainingsplan` all absent).

Swap bench: `trainingstagebuch` (a real query, but 17 characters — roughly two other tokens; only
buy it if the search-term report proves the traffic), `gewichtheben`, `hanteltraining`,
`pausentimer`, `fortschritt`, `hypertrophie`, `satz`, `wiederholung`, `studio`.

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

## 6. Other storefronts

Apple indexes each *localization*, not each country. The app ships **English + German only**
(`GymStreak/Resources/en.lproj`, `de.lproj`; watch `Localizable.xcstrings` has exactly `en`, `de`),
so today en-US serves every English storefront and de-DE serves DE/AT/CH.

Cheap future win, no code and no translation: adding an **en-GB** (and/or **en-AU**) *metadata*
localization in App Store Connect gives another private 100-character keyword field for those
storefronts. Clone the en-US subtitle, then vary the keyword field toward terms this one had to drop
(`dumbbell`, `barbell`, `journal`, `fitness`) rather than duplicating it.

---

## 7. Deliberate omissions

- **`gym`, `streak`, `workout`, `tracker`** — title-indexed per locale (§2). Never re-buy.
- **`widget`** — the widget target is still Xcode boilerplate; claiming it invites a one-star review.
- **Competitor brand names** — excluded by policy and by App Review Guideline 2.3.7. Do not add
  them to the swap benches.
- **Plurals** — omitted wherever the singular is indexed; Apple stems both languages adequately.
- **"Apple Watch" in the subtitle** — 11 of 30 characters for a token the App Store already
  advertises with an automatic supported-device badge, and a trademarked phrase in metadata. It
  belongs in the promotional text and description, where it is used.
- **"AI" in the subtitle** — kept in the keyword field (`ai` / `ki`) and the promotional text, where
  the on-device/hardware qualifier fits. See §3.
- **`fitness` (en only)** — see §4.2.

## 8. Maintenance

- Re-derive both fields whenever the **App Name** changes in either storefront (§2).
- Subtitle and keyword-field edits ride a **version submission**; schedule them with a release, not
  as a hotfix.
- After ~4 weeks live, read App Store Connect → Analytics → **search terms** and rotate the weakest
  tokens against the swap benches in §4.2 / §5.2.
- Keep the free-vs-Pro wording in §3 in sync with `Domain/Models/Pro/ProFeatureCaps.swift` and
  `docs/pro-subscription.md`. A cap change can silently make "Track unlimited, free" false.
