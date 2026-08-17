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
> P5, P9). Everything in **§4.2b is 🚧 NOT BUILT** (P6, P7, P8, P10, P11) and each is a separate
> feature project that must be built before it can be sold. Two free-tier items are also
> unbuilt: PR celebration and CSV export. Markers are defined at the top of §4 — check them
> before scoping any work or writing any paywall copy.

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
> items, all gate-only work. Everything in §4.2b is a separate feature project that must be
> scoped, built, and documented on its own before it can be sold. Do not put 🚧 items on a
> paywall, in App Store copy, or in a pricing comparison until they exist.

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
| Workout summary (duration, volume, calories) | ✅ SHIPPED | |
| Per-workout muscle map | ✅ SHIPPED | Single-workout scope. |
| **Post-Workout Recap** (AI) | ✅ SHIPPED | Single-session scope — see §4.3. |
| **Workout Analysis** (AI, vs. previous session) | ✅ SHIPPED | Single-workout scope. |
| Max-weight progress chart, **3-month window** | ✅ SHIPPED | The taste of the analytics. |
| Weekly goal + simple cadence scheduling | ✅ SHIPPED | |
| PR celebration when a record is hit | 🚧 **NOT BUILT — FUTURE** | Delight = retention, not revenue. |
| Raw CSV export of logged data | 🚧 **NOT BUILT — FUTURE** | Deliberate brand decision, §5. No export code exists in the repo today. |

### 4.2a Pro — shippable in the monetization release (gate-only work)

These six exist and need nothing but an entitlement check. **This is the Pro tier you can
launch with.**

| # | Pro feature | Free equivalent | Why this converts |
|---|---|---|---|
| P1 | 🔒 **Unlimited routines** | 3 | The primary usage cap. Fires exactly when a user graduates from a simple split to real programming — the clearest possible commitment signal. |
| P2 | 🔒 **Full progress analytics**: est. 1RM + training-volume metrics, and all timeframes (6M / 1Y / all-time) | Max weight only, 3-month window | The user *generated* this data. Loss aversion is maximal against your own training history, and the wall gets more painful every month you keep training. Reversible — no data deleted. |
| P3 | 🔒 **AI Coach Chat** | 5 messages / month | Highest perceived value in the app; the taster cap is what makes it convert rather than sit unnoticed. |
| P4 | 🔒 **AI Period Recap** (week / month / quarter / year) | 1 per month | Cross-session scope (§4.3). |
| P5 | 🔒 **AI Exercise Deep-Dive** | 1 per month | Cross-session scope. |
| P9 | 🔒 **Fixed-weekday schedules** | Simple every-N-days cadence | Programming depth signals a committed lifter. |

*(P9 keeps its number for cross-reference stability; it is shipped, not future.)*

**P9 scope correction (2026-08-15).** An earlier draft described P9 as "fixed-weekday schedules,
multiple routines per day, plan preview". Only the first is a real gateable surface. The
"next 3 sessions" preview is part of the schedule sheet for *both* schedule types, so gating it
would only make the free sheet worse with no conversion upside; and "multiple routines per day"
is not a feature at all — each routine carries an independent schedule, so two routines can
already fall on the same day. P9 is therefore one gate, not three, and the launch bundle is
correspondingly thinner than §4.3's warning already assumed.

### 4.2b Pro — proposed, NOT BUILT

🚧 **None of the following exists. Each is a feature project in its own right** — scope, build,
document in `docs/`, *then* gate. They are recorded here because the launch bundle in §4.2a is
thin for users who cannot run Apple Intelligence (§4.3), and these are the cheapest credible
ways to thicken it later. Treat this as a backlog, not a plan.

| # | Proposed Pro feature | Free equivalent | Why it would convert | Rough build cost |
|---|---|---|---|---|
| P6 | 🚧 **Muscle-balance over time** — volume per muscle group across weeks/months, with imbalance flagging | Per-workout muscle map only | Extends a beloved free feature into a genuinely new capability instead of taking one away. | Medium — new aggregation + chart surface |
| P7 | 🚧 **Custom exercises** | 3 | Classic capacity cap; Hevy caps at 7. Only bites for users with real equipment/variation needs. | Medium — creation flow, schema, watch-sync impact |
| P8 | 🚧 **PR history & timeline** | PR celebration (itself unbuilt) | Depth on top of a free delight. | Medium — depends on the free PR feature landing first |
| P10 | 🚧 **Routine folders / archive** | Flat list | Only matters once you have many routines — i.e. only to someone already past P1. | Low–medium |
| P11 | 🚧 **Alternate app icons + accent themes** | Default | Near-zero build cost, zero brand risk, and identity goods measurably lift perceived subscription value. | **Low — best effort-to-value ratio of the five** |

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
| Pro Lifetime | $69.99 / €69.99 | Secondary, always visible. |
| Founder Lifetime | free, granted | §7. |

Reasoning:

- **Annual is primary** because Health & Fitness annual plans are 60–68% of category
  subscription revenue — far more annual-weighted than any other category.
- **$24.99/yr** sits deliberately at the Hevy/Strong tier and well under Jefit ($69.99/yr) and
  Fitbod ($95.99/yr). The H&F monthly median is $9.70; $4.99 monthly undercuts it while making
  the annual maths obvious ($59.88 vs $24.99).
- **Lifetime stays visible, not hidden.** Standard advice is to bury lifetime as a
  decline-offer, because subscriptions produce ~4.5× the lifetime revenue per user. That advice
  assumes a neutral audience. GymStreak's audience is *selected for subscription aversion* —
  many installed precisely because the listing said "no subscription." Fighting that selection
  effect with a hidden lifetime option converts them to nothing. Price it at ~2.8× annual so a
  lifetime buyer is accretive against a median subscriber lifetime, and let them self-select.
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
| B | **Value-moment paywall** | After the 3rd completed workout, or the first automatic progressive-overload suggestion — whichever lands first | The endowed-progress screen: "You've logged N workouts, X sets, Y kg of volume." Then the offer. Paywalls triggered after a measurable value moment see **2.1× the trial-start rate** of immediate hard paywalls. This is the highest-value placement in the app. |
| C | **Contextual gates** | Tap "New routine" at 3 · tap the 1RM or volume chart tab · scrub the chart past 3 months · open Coach Chat at 0 remaining · open Period Recap / Deep-Dive at 0 remaining · create 4th custom exercise | Direct purchase, no trial. Must name the specific thing being unlocked in the headline, not "Go Pro". |
| D | **Cap-approach nudge** (not a paywall) | At 2 of 3 routines, 1 of 5 chat messages remaining | An inline, non-blocking hint. This is the endowed-progress effect: showing consumed proportion of an allowance measurably lifts conversion, and it removes the surprise from placement C. |

**Absolute prohibition:** no paywall, upsell, or Pro badge anywhere inside an active workout
session, on the watch app, or on the rest-timer Live Activity. Rule 3.

**Frequency cap:** placement A and B fire once each, ever. Placement C fires on genuine intent
only. No recurring interstitials, no launch-time paywalls.

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
