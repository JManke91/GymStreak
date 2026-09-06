# Monetization Strategy — GymStreak Pro

**Status (2026-08-17):** strategy agreed and **implemented**. The ticket set at
`.scratch/pro-entitlements/issues/` (2026-08-15) is complete: **01–02** established the entitlement
abstraction and the Founder grant, **03** integrated the RevenueCat SDK against its Test Store so the
abstraction was validated against the real thing before anything depended on it, **04–12** built the
paywall seam and the six §4.2a gates behind a kill switch that shipped off, **13–14a** added the
subscription surfaces, real paywalls, the Customer Center and sandbox testability, and **15** flipped
gating on and rewrote the listing copy in the same change. `docs/pro-subscription.md` documents what
shipped; its §9.6 lists the launch steps that remain outside the repo (device verification, App Store
Connect, submission). Phase 3 of §9 — tuning — is what comes next.
**Purpose:** this document is the spec that ticket set picks up. It defines
*what* is gated, *why* that specific gate was chosen, *how* each gate behaves in every state
(free / trial / Pro / lapsed / grandfathered), and what must never be gated.
**Date of research:** 2026-08-13. Sources are listed in §12.

> **⚠️ Mixed inventory — §4 lists both shipped and unbuilt features.**
> The launch-ready Pro tier is **§4.2a only** (six items, all gate-only work: P1, P2, P3, P4,
> P5, P9). In **§4.2b**, P6, P8, P10 and P11 are 🚧 not built; **P7 ships already and needs only a
> gate** (corrected 2026-09-06 — see §13.5). Two free-tier items are also unbuilt: PR celebration
> and CSV export. Markers are defined at the top of §4 — check them before scoping any work or
> writing any paywall copy.

> **⚠️ Phase 3 status, 2026-09-06: the constraint is acquisition, not the paywall.**
> **36 first-time downloads in 90 days** and ~13 App Store impressions/day, which makes the
> chargeable population **~12 people** and every gating question in §4 unmeasurable until 2027.
> **Revenue is $0 and MRR is $0.** The single trial was cancelled during its trial week and lapses
> 2026-09-10. See **§13** — and **§13.2 before trusting any RevenueCat number**, which overstated
> acquisition by roughly 6× in this document's own first draft.

---

## 1. The one constraint that shapes everything

The App Store listing said, verbatim, in both storefronts, until the launch release of 2026-08-17:

> "fast, private, and **completely subscription-free**"
> "**No account, no subscription.** Your training data belongs to you."

Every existing user downloaded the app under that promise. (Non-negotiable 2 below has since been
executed: the subscription claim is gone from both storefronts and the no-account half — still true —
stayed. The copy lives in `docs/marketing/app-store-description.md`.) This is not a detail — it is the
governing constraint of the whole plan, and it produces three non-negotiables:

1. **Existing users are grandfathered permanently** (§7). Anything else is a promise broken in
   public, and the App Store review section is where that gets paid back.
2. **The listing copy must change in the same release that ships the entitlement layer.**
   Leaving "completely subscription-free" live next to a paywall is a review-guideline risk and
   a guaranteed 1-star generator.
3. **The free tier must remain a genuinely complete workout tracker**, not a demo. The app's
   differentiator was never "cheap" — it was *native, private, fast, no account*. Monetization
   has to sell **depth and capacity**, never the core loop.

---

## 2. Model decision: freemium with usage caps — not a hard paywall

| Model | Install→paid | Week-6 conversion | LTV | Fit here |
|---|---|---|---|---|
| Hard paywall (onboarding, no free use) | **10.7%** median | 15.3% | +21% | ❌ |
| Freemium | 2.1% median | **22.9%** | baseline | ✅ |

The hard paywall wins on raw conversion and LTV. **We are not using it**, for three reasons:

- It is incompatible with the promise in §1 and with an existing free install base.
- Health & Fitness has the *highest* trial-to-paid conversion of any category (35%) but the
  *lowest* first-renewal retention (30.3%). Hard paywalls front-load revenue from users who
  churn at renewal. Freemium builds the habit first, and habit is what survives renewal.
- GymStreak has no paid-acquisition engine. Its growth is organic and word-of-mouth, which a
  hard paywall strangles at the source.

**Within freemium, gate on usage caps, not feature locks.** Products that cap *usage* convert
1.5–2× better than products that lock *features*, worth +3–6pp on free-to-paid, because a cap
creates a dated, self-inflicted upgrade trigger ("I hit the wall") whereas a lock leaves the
user never understanding what they're missing. Where a pure cap isn't possible, use a
**taster cap** (N uses per month) rather than a hard lock.

---

## 3. Gating philosophy — the four rules

These are the rules the feature table in §4 is derived from. Apply them to any *future*
feature to decide its tier without re-litigating this document.

**Rule 1 — The aha moment is free, forever and unmetered.**
GymStreak's aha is: *build a routine → train it → see it logged → see the number go up.*
Every step of that is free with no cap. A user who has not yet felt that has nothing to buy.

**Rule 2 — Gates fire only after investment, and only on capacity or depth.**
The endowment and sunk-cost effects are the entire engine: the user has hand-built routines,
logged months of sets, and accumulated a training history that exists nowhere else. Loss-framed
messaging outperforms gain-framed by ~21%, and the loss only exists once there's something to
lose. So a gate must sit at the point where the user is *asking the app for more*, never at the
point where they're asking it to do its job.

**Rule 3 — Never gate inside an active workout.**
The user is at the gym, mid-set, on a rest timer. A paywall there is not a conversion
opportunity, it is a rage-uninstall. This rule alone disqualifies supersets, the rest timer,
in-workout editing, alternative-exercise swapping, and the entire watch app from ever being
Pro — regardless of how attractive they look as gates. **Competitors get this wrong** (Strong
paywalls both supersets and its Apple Watch app); that is an opportunity, not a template.

**Rule 4 — Never hold the user's own data hostage.**
No logged workout is ever deleted, hidden, or made unreadable because a subscription lapsed.
The privacy-first brand cannot survive a data-hostage gate. Analytics *windows* may narrow;
raw history never does. Raw CSV export stays free (see §5) precisely because the listing says
"your training data belongs to you" and that has to stay literally true.

---

## 4. Tier definition

> ### ⚠️ Read this before planning any work from §4
>
> **Not everything listed below exists.** This section mixes shipped features with proposed
> future ones, because the *strategy* has to describe the eventual tier — but an implementer
> must not read it as an inventory.
>
> | Marker | Meaning | Work required |
> |---|---|---|
> | ✅ **SHIPPED** | Exists today, stays free | None |
> | 🔒 **SHIPPED — NEEDS GATE** | Exists today, must be put behind the entitlement | Gate only |
> | 🚧 **NOT BUILT — FUTURE** | **Does not exist. Proposal only.** | Build the feature *first*, then gate it |
>
> **The Pro tier that can actually ship in the monetization release is §4.2a alone** — six
> items, all gate-only work. In §4.2b, P6, P8, P10 and P11 are each a separate feature project
> that must be scoped, built and documented on its own before it can be sold; **P7 is the
> exception — it ships already and needs only a gate** (§13.5). Do not put 🚧 items on a paywall,
> in App Store copy, or in a pricing comparison until they exist.

### 4.1 Free — always, unmetered

| Feature | Status | Note |
|---|---|---|
| **Up to 3 routines** | ✅ SHIPPED | The one capacity cap. See §4.4 for why 3. |
| Unlimited workout logging | ✅ SHIPPED | No session cap, ever. |
| Unlimited history *viewing* | ✅ SHIPPED | Every workout ever logged stays readable forever. |
| Full exercise library, all 20+ muscle groups | ✅ SHIPPED | Gating the library makes the free app feel broken. |
| Rest timer, Live Activity, Dynamic Island, notifications | ✅ SHIPPED | Core loop. |
| **Supersets** (round detection + gated rest timer) | ✅ SHIPPED | Rule 3. Marquee differentiator vs. Strong. |
| In-workout editing, add/remove/swap alternative exercise | ✅ SHIPPED | Rule 3. |
| **Apple Watch app — complete and standalone** | ✅ SHIPPED | Rule 3 + top-3 acquisition differentiator. |
| Progressive overload (rep ranges + Double Progression suggestion) | ✅ SHIPPED | This is the *retention* engine. Gate its analytics (§4.2a), not its function. |
| Apple Health sync + iCloud sync | ✅ SHIPPED | Platform integrations tied to the privacy promise. |
| **Apple Calendar sync of planned workouts** | ✅ SHIPPED | Added 2026-09-03. **Not free by rule** — Rule 4 governs logged history, not forward-looking plans, and the row above rests on §5's account argument, which this does not trigger. Free on funnel grounds: it is a retention surface (§10 guardrail), every §2 mechanism fails on it (no countable unit; a truncated horizon reads as broken; nothing to blur), and it is P9's funnel — a free user has only `.everyNDays`, so the calendar is where drift makes fixed-weekday scheduling sell itself. No competitor writes planned workouts to the system calendar, so it is an acquisition asset on this app's only channel — the same trade §5 accepted for the watch app. Full reasoning and research: `docs/calendar-sync.md` §14. |
| Workout summary (duration, volume, calories) | ✅ SHIPPED | |
| Per-workout muscle map | ✅ SHIPPED | Single-workout scope. |
| **Post-Workout Recap** (AI) | ✅ SHIPPED | Single-session scope — see §4.3. |
| **Workout Analysis** (AI, vs. previous session) | ✅ SHIPPED | Single-workout scope. |
| Max-weight progress chart, **3-month window** | ✅ SHIPPED | The taste of the analytics. |
| Weekly goal + simple cadence scheduling | ✅ SHIPPED | |
| PR celebration when a record is hit, **and PR history / timeline** | 🚧 **NOT BUILT — FUTURE** | Delight = retention, not revenue. **Moved here from §4.2b P8 on 2026-09-06 (§13.5):** PRs are the user's own logged achievements (Rule 4), Hevy monetizes the history *window* (our P2) rather than PRs themselves, and no evidence was found that PR history converts anyone. `PersonalRecordService` already computes them — only the timeline view is missing. |
| Raw CSV export of logged data | 🚧 **NOT BUILT — FUTURE** | Deliberate brand decision, §5. No export code exists in the repo today. |

### 4.2a Pro — shippable in the monetization release (gate-only work)

These six exist and need nothing but an entitlement check. **This is the Pro tier you can
launch with.**

| # | Pro feature | Free equivalent | Why this converts |
|---|---|---|---|
| P1 | 🔒 **Unlimited routines** | 3 **of the user's own** (the built-in example routine is not counted) | The primary usage cap. Fires exactly when a user graduates from a simple split to real programming — the clearest possible commitment signal. |
| P2 | 🔒 **Full progress analytics**: est. 1RM + training-volume metrics, and all timeframes (6M / 1Y / all-time) | Max weight only, 3-month window | The user *generated* this data. Loss aversion is maximal against your own training history, and the wall gets more painful every month you keep training. Reversible — no data deleted. |
| P3 | 🔒 **AI Coach Chat** | 5 messages / month | Highest perceived value in the app; the taster cap is what makes it convert rather than sit unnoticed. |
| P4 | 🔒 **AI Period Recap** (week / month / quarter / year) | 1 per month | Cross-session scope (§4.3). |
| P5 | 🔒 **AI Exercise Deep-Dive** | 1 per month | Cross-session scope. |
| P9 | 🔒 **Fixed-weekday schedules** | Simple every-N-days cadence | Programming depth signals a committed lifter. |

*(P9 keeps its number for cross-reference stability; it is shipped, not future.)*

**P1 counting rule (2026-08-27).** The free three are three routines the user *made*. The built-in
example routine (`docs/example-starter-routine.md`, `Routine.seedKey` non-empty) is outside the
count, permanently — editing, renaming or restructuring it never makes it start counting, and
deleting it never gives the user a slot back, because it never took one. Counting it would have
turned "3 free routines" into 2 the day that onboarding feature shipped and moved the paywall one
routine earlier for every new free user; §10's guardrails (free-user D30 retention and the App
Store rating outrank revenue) settle that against us. Duplicating the example produces an ordinary
user routine, which counts. The rule lives in `RoutineCapPolicy.countsTowardCap(_:)`; the shipped
mechanism is `docs/pro-subscription.md` §5c.

**The accepted consequence: the effective free ceiling is four routines**, not three, for a user
who keeps the example and adapts it to their own training. This is deliberate, not a leak to close
later. It is bounded at exactly **+1, once per iCloud account, and cannot be farmed**: the seeder
only runs against a store with zero routines and stamps `seedRoutineVersion` in
`NSUbiquitousKeyValueStore`, so a deleted example never returns and a second one can never exist;
duplicating it yields `seedKey == ""` and counts; and every creation path funnels through
`requestAddRoutine()` / `duplicateRoutine(_:)`, with no routine-template creation on the watch at
all. The three ways to close it are all worse — counting the example returns every new free user to
two own routines (§10), clearing `seedKey` on first edit charges the user for engaging with the
onboarding artifact and has no honest definition of "edit", and deleting the example once the user
reaches three of their own takes something away (§7 Rule 4). The error direction decides it: +1
costs at most a marginal conversion from someone who wanted exactly four routines and reshaped a
generic full-body template into their fourth split — and the gate still fires on their next
creation — while −1 would hit every new free user at the moment they judge whether the app is
generous, on the only acquisition channel this app has.

The nudge copy says "**free** routines" for this reason: the header subline counts all four and the
nudge counts the three that are the user's, so naming the allowance is what keeps the two lines from
contradicting each other (`docs/pro-subscription.md` §5c).

**P9 scope correction (2026-08-15).** An earlier draft described P9 as "fixed-weekday schedules,
multiple routines per day, plan preview". Only the first is a real gateable surface. The
"next 3 sessions" preview is part of the schedule sheet for *both* schedule types, so gating it
would only make the free sheet worse with no conversion upside; and "multiple routines per day"
is not a feature at all — each routine carries an independent schedule, so two routines can
already fall on the same day. P9 is therefore one gate, not three, and the launch bundle is
correspondingly thinner than §4.3's warning already assumed.

### 4.2b Pro — proposed, mostly not built

Recorded because the launch bundle in §4.2a is thin for users who cannot run Apple Intelligence
(§4.3), and these are the cheapest credible ways to thicken it later. Treat this as a backlog,
not a plan.

> **⚠️ Build costs corrected 2026-09-06 against the actual codebase (§13.5).** An earlier draft
> of this table rated all five "🚧 NOT BUILT — Medium" from the strategy side without checking
> the repo. Three of those ratings were wrong: **P7 already ships** and is gate-only work, **P8's
> detection engine already ships**, and **P6 is cheaper than "Medium"** because the aggregation it
> needs already exists. The "Rough build cost" column below is the corrected one. P8 also changed
> tier — it belongs in §4.1, free.

| # | Proposed Pro feature | Free equivalent | Why it would convert | Rough build cost |
|---|---|---|---|---|
| P6 | 🚧 **Muscle-balance over time** — volume per muscle group across weeks/months, with imbalance flagging | Per-workout muscle map only | Extends a beloved free feature into a genuinely new capability instead of taking one away. **Gated Pro in 4 of 5 competitors** (§13.5) — the most convergent gating decision in the market. | **Low–medium** — `MuscleLoadAggregator` already folds exercises into the 13 `MuscleMapRegion`s with primary/secondary weighting and set counts; the off-main `@ModelActor` snapshot store and the Charts surface exist. New work is the window fold + one chart surface. |
| P7 | 🔒 **SHIPPED — NEEDS GATE. Custom exercises** | 3 → **raise to 7–10, see §13.5** | Classic capacity cap; Hevy caps at 7. Only bites for users with real equipment/variation needs — and **no demand-side evidence exists** (§13.5). | **Low — gate only, ~1 day.** Creation and editing already ship (`AddExerciseView`), and `Exercise.seedKey == ""` already distinguishes user-created from seeded, exactly as `RoutineCapPolicy` uses it for routines. |
| P8 | 🚧 **PR history & timeline** — but **free**, not Pro (§13.5) | — | Rule 4 territory: PRs are the user's own logged achievements. Hevy monetizes the history *window* (your P2), not PRs. Value is retention and word-of-mouth. | **Low** — `PersonalRecordService` already computes PRs across all history and they already flow through `HistorySnapshot` (`prLifts`, `LastMonthStats.prs`). Only a timeline view is missing. |
| P10 | 🚧 **Routine folders / archive** | Flat list | Only matters once you have many routines — i.e. only to someone already past P1. **Strong ships this free; no competitor monetizes it** (§13.5). Do not build it as a gate. | Low–medium |
| P11 | 🚧 **Alternate app icons + accent themes** | Default | Near-zero build cost and zero brand risk — but the "identity goods lift perceived subscription value" claim **did not survive research** (§13.5): no RevenueCat/Adapty evidence exists and no competitor markets it standalone. Bundle sweetener, never a reason to subscribe. | Low |

### 4.3 The AI line — one sentence a user can understand

> **AI about one workout is free. AI about your training is Pro.**

This is a *conceptual* boundary, not an arbitrary list, which matters: users forgive gates they
can predict and resent gates that feel random.

- Free: Post-Workout Recap, Workout Analysis — scope is the session you just did.
- Pro: Period Recap, Exercise Deep-Dive, Coach Chat — scope is your history.

Two things make AI the strongest Pro anchor here:

- **Zero marginal cost.** All inference is on-device via Foundation Models. Unlike every
  competitor charging for a server-side LLM (HevyGPT, Jefit Elite AI, Fitbod), each Pro
  subscriber costs us nothing to serve. Pure margin.
- **It's the feature nobody expects to be free**, so gating it reads as fair.

**Hard requirement:** AI Coach needs iOS 26 + Apple Intelligence hardware. A meaningful slice
of the install base cannot run it at all. **AI must therefore never be the only reason to buy
Pro**, and the paywall must not lead with AI when `AICoachAvailability` reports unavailable.

⚠️ **This is the launch bundle's weakest point, and it is caused by §4.2b being unbuilt.** For a
user without Apple Intelligence, three of the six shippable Pro items (P3, P4, P5) are invisible
— the entire offer collapses to **P1 (unlimited routines), P2 (full analytics), P9 (advanced
planning)**. That is a thin but honest proposition at $24.99/yr, and it is the strongest argument
for building **P11 (icons/themes — low cost)** and **P7 (custom exercises)** early, since both are
device-independent. Phase 0 must measure what share of the base is Apple-Intelligence-capable
(§11 Q2) before deciding whether the non-AI paywall variant needs §4.2b reinforcement at launch.

### 4.4 Why 3 routines

| App | Free routines | Price |
|---|---|---|
| Strong | 3 | $9.99/mo · $29.99/yr |
| Hevy | 4 | $2.99/mo · $23.99/yr · $74.99 lifetime |
| **GymStreak (proposed)** | **3** | **$4.99/mo · $24.99/yr · $69.99 lifetime** |

Three is the deliberate breakpoint, not a stingy version of four:

- 1–2 routines = beginner (Full Body, or A/B). Never hits the wall. Correct — they haven't
  formed the habit yet and gating them costs retention with no conversion upside.
- 3 routines = the classic Push/Pull/Legs or Upper/Lower+accessory setup. The single most
  common intermediate split fits **exactly** inside free. This is the point: a huge share of
  users get a complete, unrestricted app and become advocates.
- The 4th routine is a real commitment signal — specialization blocks, deload variants,
  travel/home days. That user has been training for months and has months of data in the app.
  Sunk cost is maximal; €25/year against that investment is trivially justified.

Counting unit: a **saved routine template**. Starting a workout from any of them is unlimited.

**A/B test 3 vs. 4 once there is volume.** Four matches Hevy and reduces the "stingier than the
market leader" objection; three converts more. Ship 3, measure, adjust — this is the single
highest-leverage number in the document.

---

## 5. Deliberate non-gates (and what they cost us)

Recorded so they don't get "optimized" back in later by someone reading only the revenue side.

| Not gated | Why | What it costs |
|---|---|---|
| **Apple Watch app** | Rule 3, and it's a headline acquisition driver. Strong gates theirs and is widely criticized for it. | The single biggest forgone gate. Accepted. |
| **Supersets** | Rule 3 — mid-workout gate. Both Strong and Hevy gate this. | Moderate. Accepted; it's a logging primitive. |
| **Raw CSV export** 🚧 *(not built)* | The listing says "your training data belongs to you." Gating export makes that sentence a lie. Nobody subscribes *for* export anyway — it's a churn enabler with high brand value and low revenue value. **This is a decision about a feature that does not exist yet** — it constrains export *if and when* it is built, and is not a launch dependency. | Negligible. |
| **History retention** | Rule 4. Hevy caps the *analytics window* at 3 months but never deletes logs; we match that and say so explicitly in the paywall copy. | Low — the window gate (P2) captures the same intent honestly. |
| **Apple Health / iCloud sync** | Platform integrations under the privacy promise. Gating sync would require an account, which breaks the no-account pitch. | Low. |
| **Ads, ever** | Contradicts privacy-first positioning and native feel. Not a revenue line for this app. | N/A. |

---

## 6. Pricing

| SKU | Price (USD / EUR) | Role |
|---|---|---|
| **Pro Annual** | **$24.99 / €24.99** | **Primary.** 7-day free trial. |
| Pro Monthly | $4.99 / €4.99 | Anchor — makes annual read as 58% off. |
| ~~Pro Lifetime~~ | ~~$69.99 / €69.99~~ | **Not offered (decided 2026-09-06).** The product exists in RevenueCat but is not in the offering, so it is unreachable. Reasoning and how to restore: §13.8 item 3. |
| Founder Lifetime | free, granted | §7. |

Reasoning:

- **Annual is primary** because Health & Fitness annual plans are 60–68% of category
  subscription revenue — far more annual-weighted than any other category.
- **$24.99/yr** sits deliberately at the Hevy/Strong tier and well under Jefit ($69.99/yr) and
  Fitbod ($95.99/yr). The H&F monthly median is $9.70; $4.99 monthly undercuts it while making
  the annual maths obvious ($59.88 vs $24.99).
- ~~**Lifetime stays visible, not hidden.**~~ **Superseded 2026-09-06 — lifetime is not offered
  at all** (§13.8 item 3). The argument is kept because it is the case to re-open if the decision
  is revisited: standard advice is to bury lifetime as a decline-offer, because subscriptions
  produce ~4.5× the lifetime revenue per user — but that advice assumes a neutral audience, and
  GymStreak's is *selected for subscription aversion*, many having installed precisely because the
  listing said "no subscription." Fighting that selection effect with a hidden lifetime option
  converts them to nothing. If it is ever offered, price it at ~2.8× annual so a lifetime buyer is
  accretive against a median subscriber lifetime, and let them self-select.
- **7-day trial on annual only.** H&F conversion is bimodal — users buy on Day 0 or on Days
  4–7, because they want to see a result first — so the trial must span that second window. Do
  not offer a trial on the contextual gates (§8); at those moments the user already has intent
  and a trial only adds a cancellation decision.

---

## 7. Grandfathering — the "Founder" grant

**Every user who has the app installed before the cutoff build gets Pro permanently, free.**

- **Mechanism: StoreKit 2 `AppTransaction.originalAppVersion`.** See §7.1 for the verified API
  research. Pin a cutoff `CFBundleVersion` (the build number of the last fully-free build); on
  launch resolve `AppTransaction.shared` once, and if the original download predates the cutoff,
  persist a `founder` flag. No account, no server, no "restore purchases" flow.
- **Surface it loudly.** A one-time "You're a Founder — Pro, free, forever" screen. This turns
  the most dangerous moment of the whole rollout into the most positive one, and it recruits
  exactly the cohort that writes reviews and tells friends. **Shipped as
  `FounderCelebrationView` + `FounderCelebrationCoordinator` (ticket 12, 2026-08-15)** — see
  `docs/pro-subscription.md` §5h for the four rules that decide when it appears, including why it
  stays inert until the kill switch flips (so the release that starts gating is the one that
  thanks the user) and why an undecided grant never shows a retractable version of it.
- **Cost is bounded and shrinking.** The pre-monetization base is the smallest it will ever be.
  Precedent (e.g. Anova) shows a clean permanent grant defuses the backlash entirely, whereas
  time-limited grandfathering just delays it.
- **Ship the listing-copy change in the same release** — remove "completely subscription-free"
  / "ganz ohne Abo" and "Kein Konto, kein Abo" from both storefronts. Replace with an honest
  free-tier statement (e.g. "Track unlimited workouts free. Pro unlocks unlimited routines and
  full analytics." / "Kein Konto. Track unbegrenzt viele Workouts kostenlos.").
  **✅ Done 2026-08-17 (ticket 15)** — both descriptions and every promotional-text variant, in
  `docs/marketing/`. Pasting them into App Store Connect is part of the submission itself
  (`docs/pro-subscription.md` §9.6).

### 7.1 Founder detection — verified API research

Researched 2026-08-13 via `ios-api-researcher`. **Read this before implementing; four of these
findings are traps that produce a silently wrong grant.**

**Why `AppTransaction` and not local state.** It is the App Store's signed record of the *app
download itself*, held server-side against the Apple Account — not an IAP receipt. It therefore
works for an app that has never had any in-app purchase (confirmed; this is the exact migration
Apple demonstrates in [WWDC22 session 10007](https://developer.apple.com/videos/play/wwdc2022/10007/?time=794)),
and it is the only candidate that survives the case that matters most: *user deleted the app
before the paywall existed, then reinstalled after.*

| Signal | Survives delete + reinstall | Survives new device from backup | Survives iCloud off |
|---|---|---|---|
| **`AppTransaction.originalAppVersion`** | ✅ | ✅ | ✅ |
| SwiftData `createdAt` | ❌ | only if backed up | ❌ if sync off |
| Documents dir creation date | ❌ | only if backed up | n/a |
| `NSUbiquitousKeyValueStore` stamp | ✅ *if iCloud on* | ✅ *if iCloud on* | ❌ |

*(Survivability rows for the three alternatives are synthesized from standard platform
behavior, not a single Apple source.)*

**The four traps:**

1. **On iOS it returns `CFBundleVersion` — the BUILD number**, not `MARKETING_VERSION`
   (macOS returns `CFBundleShortVersionString`; iOS does not). The cutoff constant must be a
   build number. [Docs](https://developer.apple.com/documentation/storekit/apptransaction/originalappversion)
2. **Sandbox, TestFlight and Xcode always return `"1.0"`** — so *every* debug and TestFlight run
   falsely looks pre-cutoff. Guard on `appTransaction.environment == .production` (iOS 16+);
   do not try to special-case the string.
3. **Compare as `Int`, not as a string.** `CURRENT_PROJECT_VERSION` is a flat integer in this
   project, so parse it. `.compare(_:options:.numeric)` silently falls back to lexicographic
   ordering on a non-numeric component and returns a wrong answer with no error.

4. **`AppTransaction.shared` is `async throws` and may need the network** — it can fail on a
   true first-launch-offline. Resolve once and cache the *decision*; on throw, leave the
   decision undecided and retry next launch rather than recording `false`.

**Trap 5 — this project had no usable build number (found 2026-08-15).** The scheme above
assumes a monotonically increasing `CFBundleVersion`. This project did not have one:
`CURRENT_PROJECT_VERSION` was `1` at every production site in the Xcode project, and the `/release`
command bumped only `MARKETING_VERSION` — so every shipped version appears in App Store Connect as
`1.1.x (1)`, confirmed against ASC. **Every pre-existing install therefore reports
`originalAppVersion == "1"`.**

The fix, and the scheme ticket 02 implemented: bump `CURRENT_PROJECT_VERSION` to **1000** across
the production targets and set `cutoffBuild = 1000`. Everything already in the wild reads
`1 < 1000` and is granted Founder. `/release` must increment the build number every cycle —
**if a future release ever ships as build `1` again, every new paying user is silently granted
Founder forever**, and the bug is invisible until the revenue is missing. Done: `/release` step 6b
and `merge-testflight-to-store` step 9b both bump it and report it, and
`FounderStatusTests.shippingBuildIsNotBelowCutoff` fails if the shipped build ever drops below the
cutoff.

**What `1000` actually means, and the open decision it creates.** The cutoff is the first build
carrying the entitlement layer — *not* the first build that charges anyone. Gating ships off
(§9 Phase 1) and flips on in a later release (ticket 15), and the build number increments every
release cycle in between, so the paywall arrives on build `1000 + k`. Anyone installing during
that ungated window reads `1000 + j >= 1000` and is **not** granted Founder, even though they
installed while the listing still said "completely subscription-free" and never saw a paywall.
It fails in the safe direction — it under-grants and leaks no revenue — but it is narrower than
§7's promise. **Decide before ticket 15** whether that rollout-window cohort is intentionally
excluded, or whether ticket 15 must re-pin `cutoffBuild` to the build that actually turns gating
on (which also means shipping the listing-copy change in exactly that release, as §7 requires).

**Verification:** grant only on `.verified`. `.unverified` is the exact vector for forging a
pre-cutoff transaction to unlock Pro, so fail closed. *(Apple's explicit guidance here covers
purchase consumption rather than grants; this is the conservative reading.)*

**Persistence:** plain `UserDefaults` is sufficient. `AppTransaction` is itself the durable
cross-reinstall source of truth, so mirroring the flag to `NSUbiquitousKeyValueStore` adds
nothing — an earlier draft of this document called for KVS mirroring and was wrong.

**Concurrency:** `AppTransaction` is `Sendable` with no main-actor requirement, so a
`@MainActor final class FounderStatusService` wired through `AppDependencies` can await it
directly — no `nonisolated` hop or boundary projection needed (Concurrency rule 5).

**Shipped as `FounderStatusService` in `Data/Purchases/` (ticket 02, 2026-08-15).** The sketch
that used to sit here has been replaced by the real implementation — see
`docs/pro-subscription.md` §3a for how each trap is closed, why the `UserDefaults` flag
(`pro.isFounder`) is three-valued, and why the StoreKit fetch sits behind a protocol seam
(`AppTransaction` has no public initializer, so the decision branches are otherwise untestable).

**Resolved on 2026-08-15** (previously flagged as not independently verified): Apple's
documentation confirms `AppTransaction`, `VerificationResult` and `AppStore.Environment` all
conform to `Sendable`, `AppTransaction.originalAppVersion` is a non-optional `String`,
`static var shared: VerificationResult<AppTransaction> { get async throws }` carries no
main-actor requirement, and `AppTransaction` exposes no public initializer of any kind.

### Lapse behavior (a Pro subscriber who stops paying)

Specified explicitly because it's the easiest place to accidentally violate Rule 4.

| Asset | On lapse |
|---|---|
| Routines beyond 3 | **Kept, fully usable, trainable.** Creating a *new* routine is blocked until back under 3 or resubscribed. Never auto-delete. |
| Workout history | Untouched. Fully viewable. |
| Chart window | Narrows to 3 months. Data intact; resubscribing restores instantly. |
| Custom exercises beyond 3 | Kept and usable; creating new ones blocked. |
| Advanced schedules | Kept and honored; editing into a Pro-only shape blocked. |
| AI Pro surfaces | Return to the free monthly taster caps. |

---

## 8. Paywall placement

**No onboarding hard paywall.** Contradicts §1 and kills the freemium funnel.

| # | Placement | Trigger | Offer |
|---|---|---|---|
| A | **End of onboarding — soft, dismissible** | Once, after first routine created | Annual + 7-day trial. Onboarding paywalls *with a trial* produce the highest install-to-paid rate in the category (1.78% avg). Must be one tap to dismiss. |
| A′ | **End of the first-run tour — soft, dismissible** (`onboarding`, shipped 2026-09-05) | Once, on the last step of the first-run tour, before the tab bar (`docs/onboarding.md`) | The dashboard-authored paywall, on the same terms as A: one tap to dismiss, and dismissing lands the user in the **whole free app** — the tour records itself complete either way. Absent entirely for a Pro user, a Founder, a run with gating off, and once it has fired; the tour is then six steps, not seven with a dead one. Its free residue is the entire app, so §10's guardrails carry no extra risk beyond the second paywall in one session that §8's frequency note now names. |
| B | **Value-moment paywall** | After the 3rd completed workout, or the first automatic progressive-overload suggestion — whichever lands first | The endowed-progress screen: "You've logged N workouts, X sets, Y kg of volume." Then the offer. Paywalls triggered after a measurable value moment see **2.1× the trial-start rate** of immediate hard paywalls. This is the highest-value placement in the app. |
| C | **Contextual gates** | Tap "New routine" at 3 · tap the 1RM or volume chart tab · scrub the chart past 3 months · open Coach Chat at 0 remaining · open Period Recap / Deep-Dive at 0 remaining · create 4th custom exercise | Direct purchase, no trial. Must name the specific thing being unlocked in the headline, not "Go Pro". |
| D | **Cap-approach nudge** (not a paywall) | At 2 of 3 routines; on the metered AI surfaces from **zero consumed** ("5 of 5 Coach messages left this month", and the recap/deep-dive's single free generation) | An inline, non-blocking hint. This is the endowed-progress effect: showing consumed proportion of an allowance measurably lifts conversion, and it removes the surprise from placement C. The AI hint appears from the first unit rather than the last (corrected 2026-09-03) precisely because a meter that first appears near full is never seen filling. The **routine cap is deliberately unchanged** — it stays at 2 of 3, where its own nudge already shows the meter mid-fill. |

**Absolute prohibition:** no paywall, upsell, or Pro badge anywhere inside an active workout
session, on the watch app, or on the rest-timer Live Activity. Rule 3.

**Frequency cap:** placements A, A′ and B fire once each, ever. Placement C fires on genuine intent
only. No recurring interstitials, no launch-time paywalls.

**A and A′ can both land in a first session** — the tour's offer on launch, and A again once the
user creates their first routine. That is two soft paywalls in one session and it is the one thing
about A′ worth watching: §10's free-user D30 retention and the App Store rating are measured against
their pre-tour baseline, and the rollback is one line — drop `.offer` from `OnboardingStep`, leaving
the six value slides (`docs/onboarding.md`).

---

## 9. Rollout sequence

Do not ship gates and entitlements in one step.

- **Phase 0 — Instrument. ❌ Skipped, deliberately (decided 2026-08-15).**
  The intent was to measure the routine-count distribution, chart-tab usage, AI surface usage per
  user per month, and D1/D7/D30 retention before writing any purchase code, so the 3-routine cap
  stopped being a guess. **The app has no analytics backend to instrument into** — that is a
  direct consequence of the no-account, privacy-first position in §1, not an oversight — so the
  measurement this phase describes is not available at any reasonable cost.
  The mitigation: **every cap ships as a named constant in one place**, so retuning the routine
  cap, the chat allowance or the chart window is a one-line diff and a release rather than a
  refactor. The open questions in §11 stay open; they get answered by post-launch App Store
  Connect and RevenueCat data instead of by pre-launch instrumentation.
- **Phase 1 — Entitlement layer, gates OFF. ✅ Built, and never released as its own version.**
  StoreKit 2 + entitlement + Founder grant (mechanism and traps: **§7.1**) ship silently.
  **Pin the cutoff `CFBundleVersion` at this release** — it is the build number Founder
  detection compares against forever, so it must be recorded before the next bump. Gates
  evaluate and log "would have
  blocked" without blocking. Validates grant logic and produces a real forecast of who the cap
  would hit, at zero user-facing risk.
  In the event Phase 1 and Phase 2 landed in the **same** App Store release: the entitlement layer
  was built, tested and merged with the switch off, but no build carrying it was ever submitted, so
  the two phases were separated in the repo rather than on the store. That is what makes the
  `cutoffBuild = 1000` pin exactly right with nobody in between — see `docs/pro-subscription.md` §3a.
- **Phase 2 — Gates ON for post-cutoff installs only. ✅ Flipped 2026-08-17 (ticket 15).**
  Founders never see a gate. Listing copy updated in this same release.
- **Phase 3 — Tune. ← current phase.**
  A/B the routine cap (3 vs 4), paywall B's trigger threshold, and trial length (7 vs 3 days —
  shorter trials often convert better because the user hasn't forgotten the charge).

### Implementation notes (fit with this repo's architecture)

> **Purchase infrastructure decision (2026-08-15): RevenueCat, not StoreKit directly.**
> An earlier draft of this section assumed a hand-rolled StoreKit 2 layer, and assumed integration
> had to wait for Apple to approve the pending subscriptions. **Neither holds.** The project has a
> RevenueCat **Test Store** key, so the entire purchase flow — configure, fetch offerings,
> purchase, entitlement activation, restore — is integrable and testable now; only the swap to the
> production `appl_` key is gated on Apple. What changes:
> product identifiers, prices and the subscription group move to the RevenueCat dashboard, so
> §6's pricing table is configuration rather than code; paywall *content* is dashboard-authored
> via **Placements**, which map one-to-one onto the §8 A/B/C/D triggers, so changing a paywall
> stops requiring a release; and **Customer Center** provides restore, manage-subscription,
> refund requests and cancellation surveys instead of us building them.
> Anonymous app user IDs keep the no-account promise in §1 intact — but note that the **Lifetime
> SKU must be a non-consumable, not a non-renewing subscription**, because only the former
> restores from the store receipt without an account system.
> The full integration runbook lives in `docs/pro-subscription.md`.

- One protocol, `ProEntitlementProviding`, in `Domain/Interfaces/`. Entitlement state plus its
  **source** (none / founder / subscription / lifetime), and per-cap counters. `@MainActor`,
  modelled on the existing `AICoachAvailabilityProviding`.
- The implementation lives in `Data/Purchases/` — the only place permitted to import RevenueCat,
  `RevenueCatUI` or StoreKit. Wired in `App/AppDependencies.swift` (Hard rule 5).
- **The Founder grant stays local and SDK-independent.** It is resolved from `AppTransaction`
  (§7.1), it wins over any RevenueCat state, and it never round-trips to RevenueCat's servers —
  a grandfathered user must not depend on a network call to keep what they were promised.
- ViewModels take the protocol via init (Hard rule 2). **No `.shared` access in views.**
- Monthly taster counters: month-keyed counts in App Group `UserDefaults`, mirrored to iCloud
  KVS so they don't reset on reinstall.
- Watch target: reads a mirrored boolean through the existing WatchConnectivity DTO **only if**
  a watch-side gate ever exists. Per §4.1 none does — so the preferred answer is that the watch
  target stays entirely unaware of entitlements.
- Chart-window and routine-cap gates touch list/rendering surface → the
  `architecture-reviewer` pass is mandatory on those diffs.
- Full feature documentation for the shipped implementation goes in `docs/pro-subscription.md`;
  this file stays the strategy rationale.

---

## 10. Success metrics

| Metric | Target | Category reference |
|---|---|---|
| Install → paid (freemium) | 2–5% | 2.1% freemium median |
| Week-6 cumulative conversion | >20% | 22.9% freemium median |
| Trial → paid | >35% | 35.0% H&F median |
| **First renewal retention** | **>35%** | **30.3% H&F — the category's weakest number and the one to beat** |
| Annual share of subscription revenue | >60% | 60–68% H&F |
| Revenue per install, D60 | >$0.50 | $0.66 H&F median |
| **D30 retention, free users** | **must not fall vs. pre-paywall baseline** | Guardrail |
| App Store rating | must not fall below pre-paywall | Guardrail |

The two guardrails matter as much as the revenue targets. Aggressive gating reliably converts
users into churn rather than subscribers, and it damages word-of-mouth — which is this app's
only acquisition channel. If D30 or rating moves against the baseline in Phase 2, loosen before
optimizing.

**The first-run tour moves both baselines, so both are re-based on it (2026-09-05).** A′ (§8) puts a
soft paywall at the end of the tour, which means a first session can now contain two soft paywalls —
A′ on launch, A once the user creates their first routine — and the tour itself now stands between a
new install and the tab bar. Free-user **D30 retention** and the **App Store rating** are therefore
measured against their **pre-tour** baseline, not the pre-paywall one; the pre-paywall figures stay
the baseline for every gate that predates the tour. Rating is the more sensitive of the two here,
because a tour is the first thing a new user meets and a paywall at the end of it is the last.

**The rollback is one line**, and it is deliberately smaller than removing the feature: drop
`.offer` from `OnboardingStep`, which leaves the six value slides, a six-segment progress bar that
sizes itself from the same list, and the `onboarding` placement simply never raised. The tour keeps
working; only the offer goes. Removing the tour as well is a second, separate step — delete the
`.fullScreenCover` in `ContentView` that binds `FirstRunCoverOrder`'s `.onboarding` case — and
should not be needed to answer a rating dip caused by the offer. See `docs/onboarding.md`.

---

## 11. Open questions for Phase 0

Phase 0 was skipped deliberately (§9) — the app has no analytics backend, which is a consequence of
§1's no-account position rather than an oversight. These therefore get answered from **post-launch**
App Store Connect and RevenueCat data instead of from pre-launch instrumentation.

**Status at the launch flip (2026-08-17): all five still open, and none of them blocks the launch.**
Each is a Phase 3 tuning input, and every cap they would move is a named constant in
`ProFeatureCaps` — a one-line diff and a release, which is exactly the mitigation Phase 0's skip was
traded for. Re-check this section once the launch build has been live for a full 30-day window, which
is the earliest any of the retention-shaped answers exists.

| # | Question | Decides | Where the answer will come from |
|---|---|---|---|
| 1 | What is the actual routine-count distribution? | 3 vs 4 vs 5 routines | **Not directly observable** — no analytics backend, and routine data lives in the user's own CloudKit database. Proxy: how often the routine-cap placement fires, from RevenueCat Placement impressions. |
| 2 | What fraction of the base is Apple-Intelligence-capable? | How much revenue weight AI can carry; whether the paywall needs two variants | App Store Connect → Analytics → device-model breakdown, against the Apple Intelligence hardware list. |
| 3 | How large is the pre-cutoff base granted Founder status? | Bounds the forgone revenue | Bounded above by total downloads before the launch build (App Store Connect → Sales & Trends). Unlike the others this one is **fixed forever the moment the launch build ships** — the cohort cannot grow. |
| 4 | Does the 3-month chart window bite? | Whether P2 converts anyone, or the window should shorten to 1 month | RevenueCat impressions on the `chart-window` placement vs. `chart-metric`. If the window placement barely fires, the median user has under 3 months of history and it converts nobody. |
| 5 | Which existing free users already exceed 3 routines? | Whether the cap is placed right or is too tight | `routine-cap` placement impressions in the first weeks, which is dominated by exactly that cohort — Founders never see it. |

Two of the §10 guardrails are read on the same cadence and outrank all five: **D30 retention for
free users** and the **App Store rating**, both against their pre-paywall baselines. If either moves
against the baseline, loosen before optimizing.

---

## 12. Sources

- [RevenueCat — State of Subscription Apps 2026](https://www.revenuecat.com/state-of-subscription-apps) (115k+ apps, $16B revenue): H&F monthly median $9.70; annual = 60.6% of H&F revenue; subscriptions ≈4.5× one-time LTV.
- [Adapty — Health & Fitness subscription benchmarks](https://adapty.io/blog/health-fitness-app-subscription-benchmarks/): H&F trial-to-paid 35.0% (highest of any category), first-renewal retention 30.3% (lowest); Day 0 / Day 4–7 bimodal conversion.
- [Airbridge — Hard paywall vs. freemium 2026](https://www.airbridge.io/en/blog/hard-paywall-vs-freemium-2026) and [Hard vs. soft paywalls](https://www.airbridge.io/en/blog/hard-vs-soft-paywalls): 10.7% vs 2.1% install→paid; freemium week-6 22.9% vs 15.3%; hard paywall +21% LTV.
- [RocketShip HQ — Adapty benchmark: fitness apps should rethink hard paywalls](https://www.rocketshiphq.com/paywall-optimization-fitness-apps/) and [paywall timing](https://www.rocketshiphq.com/adapty-subscription-app-benchmark-2025-summary/): post-value-moment paywalls see 2.1× trial starts; onboarding paywalls with trials 1.78% install→paid.
- [Artisan Strategies — Feature gating economics](https://www.artisangrowthstrategies.com/blog/feature-gating-economics-how-saas-companies-decide-what-goes-free-vs-paid) and [State of Freemium 2026](https://www.artisangrowthstrategies.com/blog/state-of-freemium-2026-conversion-rates-revenue-share-failure-modes): usage caps convert 1.5–2× better than feature locks (+3–6pp); aggressive gating drives churn and damages virality.
- [Adapty — freemium-to-premium conversion techniques](https://adapty.io/blog/freemium-to-premium-conversion-techniques/): 17% of subscribers convert on trial expiry, driven by loss aversion.
- [FasterCapital — Psychology behind freemium models](https://fastercapital.com/content/The-Psychology-Behind-Successful-Freemium-Models.html): loss-framed messaging +21% vs gain-framed; endowed progress effect via consumed-allowance display; endowment effect from user-created content.
- [Airbridge — Subscription vs. one-time purchase](https://www.airbridge.io/en/blog/subscription-vs-one-time-purchase-app): lifetime-as-second-offer captures otherwise-lost value; one-time framing avoids annualized-cost loss aversion.
- Competitor pricing/limits, verified 2026-08: [Hevy Pro vs Free](https://repreturn.com/hevy-pro-vs-free/) ($2.99/mo, $23.99/yr, $74.99 lifetime; free = 4 routines, 7 custom exercises, 3-month analytics window with logs retained), [Strong review](https://repreturn.com/strong-app-review/) ($9.99/mo, $29.99/yr; free = 3 routines, no supersets, no Apple Watch app), [Fitbod / Jefit pricing](https://www.sensai.fit/blog/fitness-app-pricing-free-tier-comparison) (Fitbod $15.99/mo, $95.99/yr; Jefit Elite $12.99/mo, $69.99/yr).
- [Apple subscription price grandfathering](https://appsops.store/blog/apple-subscription-price-grandfathering) and [Anova's permanent grandfathering precedent](https://anovaculinary.com/blogs/blog/update-existing-users-grandfathered-in-new-users-will-pay-a-small-app-subscription-fee): permanent grants defuse backlash; time-limited grants defer it.

---

## 13. Phase 3 reality check — the constraint is acquisition, not the paywall (2026-09-06)

**The question this section answers:** the app had, at the time of asking, no subscribers roughly
three weeks after gating flipped on. Which unbuilt Pro feature fixes that?

**The answer:** none of them. The paywall has been seen by almost nobody, because **almost nobody
has downloaded the app** — 36 first-time downloads in ninety days, against ~13 App Store impressions
per day, from a single acquisition channel. Every monetization question in §4 and §6 is downstream
of a number that no feature in §4.2b can move.

> **⚠️ Revision note.** An earlier draft of this section (same day) built its conclusions on
> RevenueCat's "New Customers" chart and reported ~7 new users/day, 30–80 chargeable installs and a
> mid-October decision date. **All three were wrong by roughly a factor of six.** §13.2 records the
> misreading and why it happened; it is kept rather than deleted because the same trap will catch
> the next reader of that dashboard.

### 13.1 What is actually known

Sources: App Store Connect → Analyse, 2026-09-06, window **7 Jun – 4 Sep 2026** (90 days).

| Metric | Value | Note |
|---|---|---|
| **Erstmalige Downloads** | **36** | ~0.4/day averaged; ~1–2/day in the last week |
| Erneute Downloads | 9 | Reinstalls |
| Aktualisierungen | **85** (+1,320%) | The update wave — see §13.2 |
| Impressionen | **1,150** (−6.75%) | **~13/day. This is the top of the funnel.** |
| Produktseitenaufrufe | 180 (+42.9%) | 15.7% of impressions |
| Konversionsrate | 6.01% daily avg (+110%) | Listing conversion, materially improved |
| In-App-Käufe / Aktive Abos | **1 / 1** | See §13.3 |

**Chargeable population.** §7's Founder grant is permanent and irrevocable
(`FounderStatusService.cutoffBuild = 1000`; every pre-monetization release shipped as build `1`,
real Xcode Cloud numbers 63–66 — `docs/pro-subscription.md` §9.8 Fault 3), so only installs after the
paywall went live can ever pay. 1.1.9 was rejected 2026-08-18, 1.1.10 rejected 2026-08-23, and
1.1.11 (build 1004) went in for a third review on 2026-08-23 — so the first gating build reached
users around **2026-08-25**. Downloads from the ASC daily table, Aug 27 – Sep 4: 1, 0, 0, 1, 1, 2, 3,
2, 1 = **11**, plus whatever landed Aug 25–26.

> **The chargeable population is ~12 people. Total. Ever.**

**Measured via the RevenueCat REST API, 2026-09-06** (`/v2/projects/projfc4b2027/metrics/overview`,
28-day window):

| Metric | Value |
|---|---|
| Active Trials | 1 |
| **Active Subscriptions** | **0** |
| **MRR** | **$0** |
| **Revenue (28d)** | **$0** |
| New Customers (28d) | 114 |
| Active Users (28d) | 114 |

**A quarter of that 114 is not App Store users at all.** Version spread across the customer base
(n=100 of 114) is 1.1.15: **29**, 1.1.14: 18, 1.1.13: 16, 1.1.9: 13, 1.1.12: 10, 1.1.11: 8,
1.1.10: 6. **1.1.15 has never been on the App Store** — it was *Ready for Review* on 2026-09-06 —
so every one of those 29 is a TestFlight install or a local build. TestFlight builds carry the SDK
and mint RevenueCat customers like any other install, and a tester who was already an App Store
user appears **twice** (separate container, separate anonymous ID). The App Store-side base is
therefore nearer **~85**, and even that is an upper bound.

**"~120 active users" was never a verified number** and should not be quoted again. It almost
certainly came from RevenueCat's customer count, which §13.2 shows was inflated by the update wave.
What can be defended is 36 first-time downloads since 7 June, with an unmeasured base before that.

### 13.2 The RevenueCat trap — read this before trusting that dashboard

RevenueCat's "New Customers" chart showed ~112 new customers in 28 days, rising to 7.3/day in the
last complete week. That was read as acquisition growth. **It was the update rollout.**

**Why.** RevenueCat mints a new anonymous app-user ID the first time a device launches a build
containing the SDK. The SDK landed in `37fe741` (2026-08-15) and first reached the App Store around
Aug 24–25, so **every pre-existing user became a brand-new "New Customer" on their first launch of
1.1.11+**. ASC confirms the size of that wave directly: **85 updates, +1,320%**, in the same window.
85 updates + 36 downloads ≈ 121, which accounts for essentially the entire RevenueCat figure.

**Why the rising shape fooled the analysis.** The reasoning was "an update backlog decays, this
rises, therefore it is growth." That is wrong twice over: update adoption *ramps* as users get round
to opening the App Store, and three releases shipped inside ten days (1.1.12 Aug 25, 1.1.13 Aug 31,
1.1.14 Sep 3), each pulling another cohort into its first SDK launch.

**The measurement confirms it exactly.** New Customers (114) and Active Users (114) are *the same
number* — every "active user" in the 28-day window is also a "new customer" in it, because
RevenueCat has seen exactly 114 customers ever and the SDK only shipped on 15 August. There is no
returning cohort in that figure because there cannot be one yet. Against ASC's 36 downloads + 85
updates ≈ 121 devices, 114 is the expected match.

**The rule:** RevenueCat "New Customers" counts SDK-identity creations, not installs. **App Store
Connect → Erstmalige Downloads is the only trustworthy install number.** Cross-check any RevenueCat
acquisition claim against it, permanently, and never quote RevenueCat customer counts as user counts.

### 13.3 The one trial was cancelled — but the purchase path is proven

Measured 2026-09-06 by scanning all 114 customers for subscription records. Exactly one exists:

```
product        gymstreak.iap.pro.yearly.sub   (Jahresabo, P1Y, P1W trial)
status         trialing            environment  production        country  DE
starts_at      2026-09-03 08:28 UTC
ends_at        2026-09-10 08:28 UTC
auto_renewal   will_not_renew      ← cancelled during the trial
gross revenue  $0.00
offering       gymstreak_sale (ofrng880c8209b0)
```

**It will not convert.** The customer turned auto-renewal off inside the trial week, so the
entitlement lapses on 2026-09-10 and the app returns to zero subscribers having collected nothing.
At n = 1 this says nothing about the paywall, the price or the feature mix — but it must not be
recorded as a conversion.

**What it does settle:** RevenueCat recorded **no transaction attempted** in either App Review
session (`docs/appstore-rejection-1.1.9.md` §3.4) and nothing anywhere recorded a successful
production purchase, so "broken checkout" and "no demand" were indistinguishable. `environment:
production` on a real German customer closes that: **the production purchase path works end to
end.** The remaining question is demand, and per §13.4 there is not yet enough traffic to ask it.

### 13.4 Zero was never going to be informative, and waiting is not a strategy

P(zero paid conversions) if the true rate were the §10 target of 2.1%:

| Chargeable installs | P(zero) |
|---|---|
| **12 (actual)** | **78%** |
| 55 | 31% |
| 141 | 5% |

Reaching **n ≈ 141** — the point at which zero would finally be evidence — takes ~117 days at the
current ~1.2 downloads/day, plus 30 days of tenure on that cohort. That lands in **February 2027**.

> **Therefore: abandon "ship a gate and measure."** At this volume no paywall change and no Pro
> feature can produce a readable signal before next year. Apple will not help either — `Erlöse`,
> `Zahlende Benutzer:innen` and all three `Download zu Kauf` cards are already suppressed as
> *Daten nicht ausreichend*, below Apple's privacy threshold.

**And engagement metrics are unavailable indefinitely.** ASC → Retention reads *Daten nicht
ausreichend* and is labelled **"Nur Opt-in"**: every ASC engagement metric (Retention, Sessions,
Active Devices) is built only from users who opted into sharing analytics, then privacy-thresholded.
At 36 downloads the opt-in subset is a handful of devices. **Kennzahlen** draws from the same pool;
Sales & Trends reports units and proceeds only. There is no route around this inside ASC at this
volume.

*(An earlier draft of this section derived a retention crisis from RevenueCat Active minus New
customers — ~4 returning users/day. That subtraction is void, because "New" was the update wave.
Engagement is currently **unmeasured**, not known to be bad. RevenueCat's "Active Customers" is the
only available signal and it counts SDK requests against a cached `CustomerInfo`, so use it as a
trend, never as a headcount.)*

### 13.5 The acquisition diagnosis — one channel, and one telling zero

ASC → Akquise → Quellen, product page views by source, 7 Jun – 4 Sep:

| Source | Daily average |
|---|---|
| **Suche im App Store** | **1** |
| Browsen im App Store | – (a thin secondary line from ~July) |
| App-Referrer | – (first appears ~Sept) |
| **Web-Referrer** | **zero, for ninety days** |

**Germany is 62% of the user base** (62 DE, 28 US, 3 GB, n=100, RevenueCat 2026-09-06) — which
makes the German keyword surface below not a hedge but the primary market.

- **Search is the only channel**, and it is capped by a keyword footprint competing against Hevy and
  Strong on every head term a lifter would type. Head terms are unwinnable; long-tail and locale
  coverage are where a small app takes share. The German storefront is the under-served one and the
  cheapest marginal keyword surface.
- **Zero web referrers is the single largest gap in this document.** Every other source is Apple
  choosing to show the app to someone. Web-Referrer is the only one under our control, and there is
  no landing page, no community presence, no video, no press. Nothing exists outside the App Store.
- **Produktseiten (custom product pages) and In-App-Events are unused** — both greyed out in ASC.
  In-App Events feed Search *and* Browse surfaces and cost nothing but the work. They are the only
  lever on *impressions* that does not require Apple to feature the app.

**The listing itself is not the problem.** 20% page-view→download and conversion up 110% after the
2026-08-25 ASO pass (`docs/marketing/app-store-subtitle-keywords.md`) is a healthy listing. Note the
split carefully, because it decides what to do next: that pass moved **conversion**, while
**impressions fell 6.75%**. ASO sharpened relevance; it did not buy reach. Reach is the open problem.

### 13.6 Feature research, 2026-09-06 — and the corrections it forced

Market evidence plus a direct audit of this repo. **Evidence caveat:** Reddit was effectively
unreachable (`site:reddit.com` returned no indexed threads), so "why users subscribe" leans on
comparison sites that appear to be built by competing indie developers — reliable for prices and
limits, weak for motivation. Competitor pricing came back inconsistent across sources (Hevy's free
routine cap reported as both 3 and 4; Strong Premium as both $4.99 and $9.99/mo); treat as
directional.

**What the market does:**

- **Muscle-group volume / weekly sets per muscle is gated Pro in 4 of 5 competitors** (Hevy, Strong,
  Boostcamp, Jefit) — the most convergent gating decision found anywhere; Jefit makes it the headline
  Elite item. Because everyone gates it, it is **parity, not differentiation** — but its absence is a
  talking point in every comparison review.
- **Custom exercises**: Hevy caps at 7, Strong locks entirely. **No demand-side evidence exists** —
  no source states how often users hit a cap. Competitors gate it on faith.
- **Routine folders**: Strong ships them **free**. Nobody monetizes them.
- **App icons / themes**: only ever a minor bundled line item inside a larger analytics paywall,
  never marketed standalone. **No RevenueCat or Adapty evidence** that cosmetics lift conversion.
  §4.2b's original "identity goods measurably lift perceived subscription value" claim was
  unsupported and has been struck.
- **Strongest signal not on the P-list: program templates / plan generator.** Alpha Progression's
  entire $79.99/yr subscription is this; Jefit leads Elite with it; Boostcamp's growth loop is free
  programs → paid analytics. Three of five competitors build their core paid value here — and unlike
  everything else on this list it is an **acquisition** asset, which per §13.5 is the actual
  constraint.

**What the repo says (this is what corrected §4.2b's build costs):**

- **P7 already ships.** `AddExerciseView.swift` provides full creation and editing, and
  `Exercise.seedKey` is empty for user-created exercises — the same discriminator
  `RoutineCapPolicy.countsTowardCap` already uses for routines. P7 is gate-only, ~1 day.
- **P8's detection engine already ships.** `PersonalRecordService` computes PRs across all history
  via Epley 1RM; they already flow through `HistorySnapshot` (`prLifts`, `LastMonthStats.prs`) and
  render in `WorkoutDetailView` / `PRRecordStrip`. Only a timeline view is missing.
- **P6 is cheaper than "Medium."** `MuscleLoadAggregator` already folds exercises into 13
  `MuscleMapRegion`s with primary/secondary weighting and set counts, for sessions and routines
  alike. Folding N sessions over a window is the same fold with a different input; the off-main
  `@ModelActor` snapshot store and the Charts surface both exist.
- **The seeded library is only 96 exercises** (`SeedExerciseCatalog.swift`) against Hevy's 400+ and
  Strong's 450+. **This is the binding constraint on P7's cap.** Three custom exercises on a
  96-exercise library bites far earlier and reads far more punitively than Hevy's 7-on-400, and §4.1
  warns explicitly that gating the library makes the free app feel broken. If P7 is gated, cap at
  **7–10**, and expand the seed catalogue first — cheap free work with real acquisition value.

### 13.7 Ranking of the §4.2b backlog

Unchanged by the acquisition finding — but note that per §13.4 none of it is measurable for months,
so build these for the product's sake, not expecting revenue to move.

| Rank | Feature | Verdict |
|---|---|---|
| 1 | **P6 — muscle volume over time** | Build and gate. Strongest competitive signal; device-independent, so it repairs §4.3's stated weak point (three of six Pro items are invisible without Apple Intelligence). Extends a free feature rather than removing one (Rule 2). Mechanism: depth gate + blurred preview against the user's own numbers. |
| 2 | **P7 — custom exercises** | Gate at **7–10**, after growing the seed library. Best §2 mechanism class (usage cap) and the cheapest build — but no demand evidence, and a tight cap on a 96-exercise library is §10 guardrail damage on this app's only acquisition channel. |
| 3 | **P8 — PR history** | Build it **free** (now §4.1). Rule 4 territory; retention and word-of-mouth beat a weak gate. |
| 4 | **P11 — icons/themes** | Bundle sweetener only. Never a reason to subscribe. |
| 5 | **P10 — folders/archive** | Don't. Strong ships it free; by construction it only matters to someone already paying. |
| — | **Program templates** *(not on the list)* | The strategic bet: the only candidate that is both a Pro anchor and an acquisition asset. Much bigger build. |

### 13.8 What actually matters now

1. **Acquisition is not the first lever, it is the only one.** At ~1.2 downloads/day nothing else
   produces a readable result — and §7's Founder grant makes it permanent, since the pre-cutoff base
   can never be charged and revenue is therefore a function of *future installs alone*.
   **→ `docs/acquisition-strategy.md` is the plan**: prioritized levers, how to act on each, and the
   sequencing. Headlines: the app has **no rating prompt and no sharing at all**, storefront metadata
   localization is the cheapest way to buy keyword surface, and a landing page is infrastructure for
   every off-store channel rather than an SEO play.
2. **Ship 1.1.15 with the first-run tour.** Confirmed 2026-09-06: `store-build` and
   `testflight-beta` both sit at `414062b` (1.1.14, 2026-09-03) while the entire tour — seven commits
   including the `onboarding` paywall step — exists only on `feature/improvements`. Every §8-C gate
   needs accumulated data, so a brand-new user's only reachable offers are the soft
   `firstRoutineCreated` prompt and the Settings row. The funnel has no front door and the door is
   built.
3. **Lifetime SKU — deliberately NOT offered (decided 2026-09-06).** §6 argued for it because this
   audience *self-selected for subscription aversion*. It is **not** being built into the offer, by
   product decision. Record of what exists so nobody re-derives it: the non-consumable
   `gymstreak.iap.pro.lifetime` **already exists in RevenueCat** (product `prodfca33c7598`, app
   `app399243b0af`, `type: non_consumable`, `state: active`, created 2026-08-17 10:50 UTC), but it
   is **not attached to the `gymstreak_sale` offering**, which carries only `$rc_annual` and
   `$rc_monthly` — so no user can reach it. An earlier draft of this section said the SKU did not
   exist, reading `RevenueCatConfiguration.appStoreProductIdentifiers` (which lists only the two
   subscriptions, and which the real paywall does not use — it reads the offering). **To restore
   it later:** add a lifetime package to the offering in the RevenueCat dashboard and confirm the
   App Store Connect non-consumable is approved. Whether that ASC product is approved was never
   checked, because the decision made it moot.
4. **Founder subscriber attribute on 1.1.16**, not 1.1.15. Its original justification (sizing the
   chargeable population) was answered directly by ASC. Its remaining justification is stronger than
   it sounds: per §13.4, ASC engagement metrics are unavailable indefinitely, so **RevenueCat is the
   only active-user signal there is**, and un-segmented it mixes Founders, TestFlight testers and
   real App Store users with no way to tell them apart (§13.1). Ticket:
   `.scratch/founder-measurement/issues/01-founder-subscriber-attribute-and-asc-baseline.md`.
   **Architectural constraint:** `RevenueCatPurchaseGateway` is the only file allowed to import
   RevenueCat, so the call goes behind `ProPurchaseGateway` — never into `FounderStatusService`.
5. **Feature work is third.** §13.7 stands, and none of it is the constraint.

### 13.9 Numbers to re-read, and how to get them

The `revenuecat` MCP server (`docs/agents/mcp-servers.md`) reads the live numbers directly, so an
agent can pull these without a dashboard screenshot. Verified working 2026-09-06.

| Metric | Where | Cadence |
|---|---|---|
| Erstmalige Downloads | ASC → Akquise (**never** RevenueCat — §13.2) | Weekly |
| Impressionen + Quellen split | ASC → Akquise → Quellen | Weekly — this is the constraint |
| Konversionsrate | ASC → Übersicht | After any listing change |
| Trials, subscriptions, MRR, revenue | RevenueCat `/v2/projects/{id}/metrics/overview` | Weekly |
| Version + country spread, per-customer subs | RevenueCat `/v2/projects/{id}/customers` (+ `/subscriptions`) | As needed |
| Placement impressions | RevenueCat **dashboard only** — see below | Once 1.1.15 is live |
| Retention / Sessions | ASC — **unavailable until volume rises** (§13.4) | Re-check quarterly |

**API notes, verified 2026-09-06.** `/v2/projects/{id}/metrics/overview`, `/customers`,
`/customers/{id}/subscriptions`, `/products`, `/offerings` and `/paywalls` all return 200 with a
scoped v2 secret key. **The Charts API does not:** both `/v2/projects/{id}/charts` and
`/v2/projects/{id}/metrics/charts` return 404, so paywall and placement impressions are **not**
retrievable this way and still need the dashboard. `next_page` comes back as a full URL, not a path
— concatenating a host onto it breaks pagination and silently truncates the result.

**Two data traps in the customer list.** One record carries a `first_seen_at` in **2013** (a
sentinel, not a real install) which will skew any date-range aggregate. And ~29 of the 114 customers
are running **1.1.15, which has never been on the App Store** — TestFlight installs and local builds
mint RevenueCat customers exactly like real ones, and a tester who is also an App Store user is
counted twice (§13.1).

§11's five open questions stay open. Q1, Q4 and Q5 need Placement impressions that cannot accumulate
until acquisition moves; Q2 (Apple-Intelligence share) is answerable now from ASC's device-model
breakdown; Q3 is fixed forever and bounded by downloads before 2026-08-25.
