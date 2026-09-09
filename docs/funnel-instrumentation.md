# Funnel instrumentation — anonymous subscriber attributes

**Status:** shipped 2026-09-09 (iOS target only; the watch target is untouched).
**Source:** `docs/acquisition-strategy.md` §3 row 1 (lever #11, P0) and §4.11.
**Related:** `docs/pro-subscription.md` §3c (the `founder` attribute this extends),
`docs/monetization-strategy.md` §1 (the no-account promise these buckets are shaped by) and §13.4
(whose deferral of a build-channel attribute this supersedes).

---

## 1. What it does

Every install reports four **bucketed, anonymous** subscriber attributes to RevenueCat, alongside
the `founder` attribute the app already reported. They are the only thing in the app that can answer
*where* a user stopped.

| Attribute | Values | Answers |
|---|---|---|
| `onboardingCompleted` | `"true"` / `"false"` | Do they finish the tour, or bail inside it? |
| `workoutsCompleted` | `"0"` / `"1"` / `"2-4"` / `"5+"` | **The activation question.** Does anyone reach the value moment? |
| `routinesCreated` | `"0"` / `"1"` / `"2+"` | Does the starter routine carry them, or do they build their own? |
| `buildChannel` | `"appstore"` / `"other"` | Excludes the simulator/TestFlight/local population from every chart |

**Why it was the first thing built in Phase B.** `acquisition-strategy.md` §1a established that 89%
of everyone who has ever launched the app launched it exactly once, and established nothing about
which screen loses them — RevenueCat sees only "the app launched". §1.1 established the second
problem: **38 of 125 customer records (30%) came from builds 1.1.15/1.1.16, which were never on the
App Store**, so the New Customers chart could not be read at all. `buildChannel` ends that
permanently; the other three turn §6's "Where they leave" row from *unknown* into a filter.

## 2. The three rules that shape it

1. **Buckets, never raw counts.** A precise workout count plus a storefront plus a first-seen
   timestamp is re-identifying; a bucket is not, and it answers the question just as well. This is
   not a preference — the app's positioning is the no-account privacy promise, and a re-identifying
   analytics attribute would contradict it directly.
2. **Nothing is ever read back.** These are analytics exactly as `founder` is. No gate, no
   entitlement, no UI and no business rule branches on any of them. The reporting seam
   (`FunnelAttributeReporting`) has no read at all, and `FunnelAttributeTracking` has one method that
   returns nothing — so "is anything reading these?" is answerable by looking at the two protocols.
3. **Nothing waits on a report.** `setAttributes` records locally and rides the SDK's next backend
   request, so it costs no network call; every call site detaches into a `Task`, and the launch
   report is its own `.task` after the first frame.

## 3. Architecture

```
Presentation                     Domain                        Data
─────────────────────────────    ──────────────────────────    ─────────────────────────────────
OnboardingFlowViewModel  ─┐
RoutinesViewModel        ─┼─►  FunnelAttributeTracking  ◄── FunnelAttributeCoordinator
WorkoutViewModel         ─┘      (Interfaces)                      │  reads
GymStreakApp (.task)     ─┘                                        │   • OnboardingCompletionTracking
                                 FunnelAttributes                  │   • LifetimeTrainingTotalsProviding
                                   (Models — the buckets)          │   • RoutineRepository
                                                                   │   • OriginalAppDownloadReading
                                                                   ▼  writes
                                                          FunnelAttributeReporting
                                                                   ▲
                                                          RevenueCatPurchaseGateway
```

| File | Layer | Role |
|---|---|---|
| `Domain/Models/FunnelAttributes.swift` | Domain | The four bucketed strings and the **only** place the bucket vocabulary is spelled. `AppBuildChannel` lives here too. |
| `Domain/Interfaces/FunnelAttributeTracking.swift` | Domain | `reportCurrentState()` — the one call every event site makes. |
| `Data/Purchases/FunnelAttributeReporting.swift` | Data | The write seam the gateway implements. Beside `ProPurchaseGateway` for the same reason that one is not in `Domain/`: it is the purchase layer's reporting surface, and Presentation never sees it. |
| `Data/Purchases/FunnelAttributeCoordinator.swift` | Data | Gathers the four facts, memoizes the build channel, calls the reporter. |
| `Data/Purchases/RevenueCatPurchaseGateway+FunnelAttributes.swift` | Data | `report(_:)` — one `setAttributes` call, siblings of `founder`. An extension purely for file size; it logs under the `Funnel` category rather than the gateway's entitlement one. |
| `App/AppDependencies.swift` | App | Composes the coordinator over the **same** gateway instance the entitlement provider uses. |

**Why a coordinator rather than four calls in the gateway.** `RevenueCatPurchaseGateway` can answer
none of these questions, and giving it a `ModelContext` or a repository to answer them would put
persistence knowledge in the purchase layer. The gateway writes only what it is handed.

**Why one `reportCurrentState()` rather than one method per attribute.** Re-reporting all four is
idempotent and costs no network call, and it removes the class of bug where a fifth attribute is
added and one of its trigger sites is forgotten. It is the same reasoning that gives
`reportFounderStatus` no "have I already sent this" flag.

### Where it is called

| Site | Why there |
|---|---|
| `GymStreakApp`, its own `.task` | The baseline: a fresh install reports all four even if the user never finishes the tour, never builds a routine and never trains — the three cases the lever exists to count. Separate from the entitlement `.task` so neither queues behind the other. |
| `OnboardingFlowViewModel.endFlow()` | **After** `recordCompleted()`, in the same session. Waiting for the next cold launch would record a user who finishes the tour and never returns as a bail-out. |
| `RoutinesViewModel.routineWasCreated()` | The one private helper behind all three creation paths (create, create-with-exercises, duplicate), so a fourth path cannot arm §8 placement A and forget the funnel. |
| `WorkoutViewModel.completeWorkout` | Last in the task that already reports placement B and the rating prompt — analytics never queues in front of something that can appear on screen. |

## 4. The three traps, and how each is handled

### 4.1 The seeded starter routine is not a created routine

The app seeds one example routine (`docs/example-starter-routine.md`), so a raw routine count reports
`1` for a user who built nothing — the exact inverse of the question `routinesCreated` asks. The
count therefore goes through `RoutineCapPolicy.countableRoutineCount(in:)`, the same rule the free
routine cap already uses: a routine with a non-empty `seedKey` never counts, and stays uncounted
after the user renames or edits it.

### 4.2 The workout count is a counting query, not an aggregation

`LifetimeTrainingTotalsProviding.fetchCompletedWorkoutCount()` — never `fetchLifetimeTotals()`, whose
whole-history walk shares the History model actor and would queue in front of the History tab's own
refetch. **There is no counter, no `@AppStorage` and no `UserDefaults` tally**: a second count is a
second thing that can disagree with the History screen, and re-reading also makes the attribute
correct for sessions that arrived from the watch rather than from `completeWorkout`.

A count that *throws* reports nothing at all rather than reporting `"0"`. The two are
indistinguishable in the dashboard, and "nobody trains" is precisely the conclusion this lever exists
to test — writing it from a failed read would manufacture the answer.

### 4.3 `buildChannel` must fail toward `"other"`

Only a **verified** `AppTransaction` whose `environment` is `.production` reads as `"appstore"`.
Unverified, `.sandbox`, `.xcode`, a throw, and no answer at all are all `"other"`.

## 5. API research — how the build channel is detected

Researched 2026-09-09 (`ios-api-researcher`, against Apple's current StoreKit documentation), because
the choice between `AppTransaction` and the legacy receipt-path check is not obvious from the code.

**Chosen: `AppTransaction.shared` → `AppTransaction.environment` (`AppStore.Environment`).**
Available since iOS 16.0, far under this app's iOS 26.1 floor. The app already reads exactly this
transaction for the Founder grant, so the funnel reuses the existing `OriginalAppDownloadReading`
seam (`Data/Purchases/FounderStatusService.swift`), which already projects `environment` out — **no
second StoreKit API, no new dependency, and a `Sendable` projection rather than an `AppTransaction`
crossing an actor boundary** (Concurrency rule 5).

| Context | `AppTransaction.shared` | `environment` | Reported |
|---|---|---|---|
| App Store install | `.verified` | `.production` | `appstore` |
| TestFlight | `.verified` | `.sandbox` | `other` |
| Xcode → device with a Sandbox account, no `.storekit` file | `.verified` (or throws) | `.sandbox` | `other` |
| Xcode/simulator run with a `.storekit` configuration file | `.verified` | `.xcode` | `other` |
| Simulator, no StoreKit config and no Sandbox account | usually **throws** | n/a | `other` |

Note that `.xcode` means specifically "StoreKit Testing via a `.storekit` configuration file", not
"any local build" — a plain device run against a real Sandbox account reports `.sandbox`, the same
value TestFlight reports. That distinction does not matter here: the check is `== .production` versus
everything else.

**Cost and safety.** `AppTransaction.shared` is `async throws`; StoreKit keeps a local copy that it
refreshes itself, so it needs the network only when there is no valid cache yet, and it is documented
to *throw* — not block — when the user is unauthenticated or offline. `AppTransaction.refresh()` (the
explicit always-hit-the-server variant) is **never** called from this path, and neither is any
purchase API: the sandbox "Sign in to the App Store" sheet observed in the simulator is tied to
`restoreTransactions()`/`purchase()`, not to reading `AppTransaction.shared`. Apple documents no UI
for `.shared`, and that is the one point of this research without a fully authoritative citation —
which is why the read is also confined to a background task nothing on screen waits on.

**Rejected: `Bundle.main.appStoreReceiptURL` + the `sandboxReceipt` filename check.** Not formally
deprecated, but the filename convention it relies on is **not documented by Apple at all**, Apple's
current guidance steers away from receipt-based verification toward the signed `AppTransaction`, and
the property explicitly makes no guarantee that a file exists at the URL — so a correct
implementation needs a `FileManager.fileExists` check on top of an undocumented heuristic. It buys a
synchronous answer at the price of two unofficial assumptions.

**This is the app's only recurring StoreKit read.** `FounderStatusService.resolveIfNeeded()`
short-circuits on `isDecided` once the grant has been decided, so after the first successful launch
it stops asking; the funnel resolves the channel again on every launch. That is what the
never-persisted rule below buys, and it is the reason the "Apple documents no UI for `.shared`"
claim above is worth one device check with an App Store account signed out before a release.

**Resolved once per process, and deliberately never persisted.** The environment is stable for a
given install, but an install is not: a TestFlight tester who later takes the App Store build keeps
the same container, and a cached `"other"` would misreport them forever — a quieter version of the
very contamination this attribute exists to end. A resolution that *failed* is not cached either, so
an offline first launch does not pin an App Store user to `"other"` for the session.

## 6. Deliberate omissions

- **Routine deletion does not re-report.** `routinesCreated` is re-counted on creation and at every
  launch, so deleting a routine corrects itself on the next report rather than immediately. Adding a
  fourth trigger site to make a bucket transiently accurate was not worth it.
- **No `firstSeen`, storefront, device or version attribute.** RevenueCat records the ones it needs
  itself, and each additional dimension moves the bucketed set closer to re-identifying.
- **No watch-side reporting.** The watch app has no RevenueCat SDK and no purchase surface; a workout
  completed on the watch is counted when the phone ingests it, because the count is a query over
  completed sessions rather than an incrementing tally (§4.2).
- **Nothing is reported during UI tests** — every launch-time `.task` is already guarded by
  `isUITesting`, and a screenshot run must not write attributes onto a customer record.

## 7. Tests

`GymStreakTests/FunnelAttributeBucketTests.swift` (the pure bucket vocabulary),
`GymStreakTests/FunnelAttributeTests.swift` (the coordinator and the wiring) and
`GymStreakTests/Support/FunnelAttributeTestDoubles.swift` — 15 tests, iOS target. The watch target is
untouched by this feature, so the watch suite is unaffected.

- Every bucket boundary and the exact spelling of all four attributes' values — a dashboard filter
  matches the literal string, so `"2-4"` written as `"2–4"` anywhere would silently match nothing.
- A fresh install reports all four.
- The seeded starter routine reports `"0"`; a user-built routine alongside it reports `"1"` — over a
  **real** repository and in-memory store, because that is a property of `seedKey` and of the fetch,
  which a stubbed count would assert away.
- Finishing the tour reports `"true"` in the same session, driven through the real
  `OnboardingFlowViewModel`.
- The workout bucket moves across `0 → 2-4 → 5+` as the count moves.
- `buildChannel` reads `appstore` only for verified `.production`; `.sandbox`, `.xcode`, unverified
  and a thrown lookup all read `other`.
- StoreKit is asked once across three reports; a *failed* lookup is not remembered.
- A workout count that threw reports nothing at all.

## 8. Reading it in the dashboard

RevenueCat → Customer Lists / Charts → segment on the attribute name (`onboardingCompleted`,
`workoutsCompleted`, `routinesCreated`, `buildChannel`). None of the four is a reserved name (those
start with `$`). **Filter every §3 chart to `buildChannel = appstore`** — that is the whole point of
the fourth attribute, and a reading taken without it repeats the §1.1 mistake.

Attributes are written locally and sync on the SDK's next backend request, so a device that has just
launched for the first time may not appear in the dashboard for a few minutes.

## 9. Verifying it by hand

Never verified against a live customer record before this shipped — the ticket was closed on the
in-repo evidence (unit suite, architecture review, clean build). These are the steps if the reading
is ever wanted. The `Funnel` log line prints all four values at once, so Console beats a dashboard
round-trip for everything except the last two steps.

**Simulator**

1. Console.app → select the simulator → filter `Subsystem: app.gymstreak.pro`, `Category: Funnel`.
2. `xcrun simctl erase <device>`. A plain app delete is **not** enough — the seed flags live in
   iCloud KVS and survive it (`docs/example-starter-routine.md`).
3. Launch, touch nothing → `onboardingCompleted=false workoutsCompleted=0 routinesCreated=0
   buildChannel=other`.
4. Finish or skip the tour → a **new** line in the same session with `onboardingCompleted=true`.
5. Create one routine → `routinesCreated=1`, **not `2`**: the seeded starter routine must not count.
6. Train it and finish → `workoutsCompleted=1`.

**TestFlight**

7. Same Console filter against the device → `buildChannel=other`.
8. Settings → Media & Purchases → Sign Out, force-quit, relaunch → **no App Store sign-in sheet**,
   and a `Funnel` line still appears. This is the one uncited claim in §5; if a sheet ever does
   appear, cache the channel behind a first-launch-only resolution rather than reading it per launch.

**After an App Store release** — the only two steps that can prove the attributes actually land:

9. RevenueCat → Customers → any customer on the released build → Attributes: all four keys present,
   `buildChannel = appstore`. This value cannot appear in steps 1–8 by design.
10. Add the filter `buildChannel = appstore` to any `docs/acquisition-strategy.md` §3 chart. The
    customer count should drop — that drop is the §1.1 contamination finally excluded.
