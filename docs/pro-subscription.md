# Pro subscription — entitlement core, Founder grant and RevenueCat

**Status (2026-08-17):** every ticket of `.scratch/pro-entitlements/issues/` — 01 through 15,
including 14a — is implemented, and **the kill switch is on**: `ProGating.shippedValue` is `true`,
so a release build now gates. What remains of ticket 15 needs a device, App Store Connect or time
after release, not code; §9.6 is the executed checklist and lists exactly what is outstanding. The app knows whether the current user is Pro, every future gate can ask that
question through one abstraction, users who installed before monetization are permanently granted
Pro, the entitlement is now backed by **RevenueCat** — purchases against the Test Store work
end to end — anything in the app can ask for a paywall at a named placement without knowing
what a paywall looks like, and the three visual treatments the gates share exist as design-system
components. Six gates are wired: the three-routine cap (§5c), progress-analytics
gating (§5d), the three metered AI surfaces — Coach Chat, the AI Period Recap and the Exercise
Deep-Dive — over one month-keyed allowance store (§5e), and fixed-weekday schedules (§5f). §8's two **proactive** placements —
the soft one after a routine is created and the endowed-progress value moment — now fire on
their own (§5g), and the Founder grant finally has a face: a one-time thank-you screen that
reaches a grandfathered user before any gate can (§5h). Settings now states which plan the user is
on and where it came from (§5i), the app declares its data usage in a **privacy manifest** for the
first time (§9.7), and everything needed to operate and ship the integration — identifiers, the
import boundary, the Test Store procedure, the App Store Connect constraints and the ordered
checklist for turning gating on — is written down in the **runbook** (§9). Ticket 14 replaced the
DEBUG-only purchase entry point with real RevenueCat paywalls and the Customer Center (§5j), 14a made
the sandbox reachable without editing constants (§9.4a), and ticket 15 flipped the switch and
rewrote both storefront listings in the same change (§9.6).

`docs/monetization-strategy.md` is the *why* (what gets gated, at which cap, and the promises in
§1 that constrain all of it). This file is the *how* — the shipped implementation, plus the runbook
in §9.

---

## 1. What exists today

| Piece | Type | Location |
|---|---|---|
| Entitlement + its source | `ProEntitlementState` | `Domain/Models/Pro/` |
| Free-tier limits | `ProFeatureCaps` | `Domain/Models/Pro/` |
| Global gating kill switch | `ProGating` | `Domain/Models/Pro/` |
| Buyable product + purchase outcome | `ProPurchaseOption`, `ProPurchaseResult` | `Domain/Models/Pro/` |
| The abstraction gates read | `ProEntitlementProviding` | `Domain/Interfaces/` |
| Debug-only entitlement surface | `ProEntitlementDebugging` (`#if DEBUG`) | `Domain/Interfaces/` |
| Entitlement implementation | `ProEntitlementProvider` | `Data/Purchases/` |
| Founder grant | `FounderStatusService` + `StoreKitOriginalAppDownloadReader` | `Data/Purchases/` |
| Purchase seam | `ProPurchaseGateway` + `PurchasedProEntitlement` | `Data/Purchases/` |
| RevenueCat implementation | `RevenueCatPurchaseGateway` | `Data/Purchases/` |
| Dashboard identifiers + API keys | `RevenueCatConfiguration` | `Data/Purchases/` |
| Debug entitlement picker | `DebugProEntitlementSectionView` (`#if DEBUG`) | `Presentation/Views/Settings/Components/` |
| Debug Test Store section | `DebugProStoreSectionView` (`#if DEBUG`) | `Presentation/Views/Settings/Components/` |
| Paywall placements (§8 A–C) | `PaywallPlacement` | `Domain/Models/Pro/` |
| The abstraction gates raise a paywall through | `PaywallPresenting` | `Domain/Interfaces/` |
| Debug-only presentation surface | `PaywallPresentationDebugging` (`#if DEBUG`) | `Domain/Interfaces/` |
| App-wide "a workout is running" flag | `ActiveWorkoutReporting` / `ActiveWorkoutRegistry` | `Domain/Interfaces/`, `Data/System/` |
| Presentation decision + one-shot record | `PaywallPresenter` | `Data/Purchases/` |
| The paywall itself | `ProPaywallView` | `Presentation/Views/Pro/` |
| Which offering a placement resolved to | `PaywallOfferingSource` | `Domain/Models/Pro/` |
| Blurred preview lock (+ `.proLocked` modifier) | `OnyxProLockOverlay` | `Presentation/Views/DesignSystem/` |
| Pro marker for gated entry points | `OnyxProBadge` | `Presentation/Views/DesignSystem/` |
| §8 placement D allowance hint | `OnyxCapNudge` | `Presentation/Views/DesignSystem/` |
| Debug placement section | `DebugPaywallSectionView` (`#if DEBUG`) | `Presentation/Views/Settings/Components/` |
| P1 — routine cap rules | `RoutineCapPolicy` | `Domain/Services/` |
| P2 — analytics gate rules | `ChartGatingPolicy` | `Domain/Services/` |
| P3/P4/P5 — the metered AI surfaces | `MeteredAISurface` | `Domain/Models/Pro/` |
| P3/P4/P5 — taster allowance rules | `AIAllowancePolicy` | `Domain/Services/` |
| The abstraction gates read a monthly count through | `MonthlyAllowanceTracking` | `Domain/Interfaces/` |
| Month-keyed counters (App Group defaults + iCloud KVS) | `MonthlyAllowanceStore` | `Data/Purchases/` |
| P3/P4/P5 — the per-surface gate | `AICoachAllowanceGate` | `Presentation/ViewModels/AICoach/` |
| P3/P4/P5 — the §8 D hint as a value | `AIAllowanceNudge` | `Presentation/ViewModels/Pro/` |
| P4 — the free-tier offer / gate card | `PeriodRecapAllowanceCard` | `Presentation/Views/AICoach/PeriodRecap/` |
| P9 — weekday-schedule gate rules | `ScheduleGatingPolicy` | `Domain/Services/` |
| §8 A/B — the two proactive triggers | `ProactivePaywallTrigger` | `Domain/Models/Pro/` |
| §8 A/B — the armed record | `ProactivePaywallTracking` / `ProactivePaywallTriggerStore` | `Domain/Interfaces/`, `Data/Purchases/` |
| §8 A/B — when a trigger has arrived, and when it is safe to say so | `ProactivePaywallCoordinator` | `Presentation/ViewModels/Pro/` |
| §8 B — the endowed figures | `LifetimeTrainingTotals`, `LifetimeTotalsAggregator`, `LifetimeTrainingTotalsProviding` | `Domain/Models/`, `Domain/Services/`, `Domain/Interfaces/` |
| Founder thank-you — when it is due | `FounderCelebrationCoordinator` | `Presentation/ViewModels/Pro/` |
| Founder thank-you — the once-ever record | `FounderCelebrationTracking` / `FounderCelebrationStore` | `Domain/Interfaces/`, `Data/Purchases/` |
| Founder thank-you — the screen | `FounderCelebrationView` | `Presentation/Views/Pro/` |
| Settings plan status — what it says | `SubscriptionStatusSummary` | `Presentation/ViewModels/Pro/` |
| Repainting legacy ViewModels on an entitlement change | `EntitlementChangeObserver` | `Presentation/ViewModels/Pro/` |
| Settings plan status — the section | `SubscriptionSettingsSectionView` | `Presentation/Views/Settings/Components/` |
| Restore / manage / cancel / refund | `CustomerCenterSettingsRow` | `Presentation/Views/Pro/` |
| What happened inside the Customer Center | `CustomerCenterEvent` | `Presentation/ViewModels/Pro/` |
| Privacy manifests | `PrivacyInfo.xcprivacy` | `GymStreak/`, `GymStreakWatch Watch App/` |
| Tests | `ProEntitlementTests`, `FounderStatusTests`, `PaywallPlacementTests`, `PaywallPresentationTests`, `RoutineCapTests`, `ChartGatingTests`, `CoachChatAllowanceTests`, `RecapDeepDiveAllowanceTests`, `ExerciseDeepDiveAllowanceTests`, `PeriodRecapAllowanceTests`, `ScheduleGatingTests`, `ProactivePaywallTests`, `FounderCelebrationTests`, `SubscriptionStatusTests`, `PaywallOfferingSourceTests`, `CustomerCenterEventTests`, `EntitlementRefreshTests` | `GymStreakTests/` |

Wiring: `AppDependencies` builds one `ProEntitlementProvider`, hands it a `FounderStatusService`
and a `RevenueCatPurchaseGateway`, and exposes it as `proEntitlements` (and, in DEBUG only, the
*same instance* as `proEntitlementDebug`). ViewModels take the protocol via init — no `.shared`, no
view constructing a provider. Constructing the gateway is what configures the RevenueCat SDK, and
because the composition root runs inside `GymStreakApp.init()` that happens once, before any UI
exists. `GymStreakApp` then calls `proEntitlements.refresh()` once per launch from its own `.task`,
deliberately not appended to the seeder's `.task` (that one waits on CloudKit, and the entitlement
must not queue behind that wait).

**The watch target is entirely unaware of entitlements**, and stays that way: per
`monetization-strategy.md` §4.1 the whole watch app is free, so there is no watch-side gate and
nothing to mirror across WatchConnectivity.

## 2. Entitlement state carries its source

```swift
enum ProEntitlementState: String, CaseIterable, Sendable {
    case free, founder, subscription, lifetime
    var isPro: Bool { self != .free }
}
```

The case *is* the source. A `Bool` was rejected: ticket 12's Founder celebration screen and
ticket 13's Settings subscription section both have to distinguish "Pro because you paid" from
"Pro because you were here first", and retrofitting the source later means touching every call
site.

**The free case is named `free`, not `none` — deliberately, and it is load-bearing.** The debug
override stores a `ProEntitlementState?`, and with a case called `none` the perfectly natural
`simulatedState = .none` resolves to `Optional.none` (i.e. "no override"), not to the free tier.
That is a silent wrong answer, and it is exactly what the first run of `ProEntitlementTests`
caught before the rename.

## 3. The provider protocol

`ProEntitlementProviding` is modelled on `AICoachAvailabilityProviding` — `@MainActor`,
`AnyObject`, an observable `state` plus an async `refresh()` — because that is this codebase's
established shape for exposing a system-provided capability to ViewModels. A gate therefore reads
like an availability check.

It imports nothing beyond Foundation and that is a hard constraint, not a coincidence: no
conformer's purchase infrastructure (StoreKit, RevenueCat) may appear in the signature. Ticket 03
swapped the conformer and **did not touch the protocol** — which was the point of the exercise: had
the SDK forced a signature change, that would have meant the protocol was shaped around the
placeholder. **`Data/Purchases/` is the only directory permitted to import a purchase framework**:
`FounderStatusService.swift` is the only file importing StoreKit, `RevenueCatPurchaseGateway.swift`
the only one importing RevenueCat, and no type from either appears above them.

`ProEntitlementProvider` keeps `resolvedState` separate from the DEBUG-only `simulatedState`, and
`state` reports `simulatedState ?? resolvedState`. Keeping the two distinct is what lets the debug
picker show *which real entitlement it is overriding* (§6). `refresh()` assigns the full state
rather than only upgrading, because a declined grant with no purchase genuinely means `.free`.

`founderStatus` is injected with **no default value**, on purpose: the only sensible default would
be the real `UserDefaults.standard`- and StoreKit-backed service, and a test that constructed the
provider without noticing would reach for `AppTransaction` from the test process.

`@Observable` + `@MainActor`, like `AICoachAvailability`: SwiftUI reads `state` directly, so an
entitlement change re-evaluates every gate with no app restart. Observation works through the
`any ProEntitlementProviding` existential — the property access still goes through the observed
accessor.

## 3a. The Founder grant

Every user who installed before monetization gets Pro permanently and free — no account, no
server, no restore flow. `FounderStatusService` decides this **at most once per install** and
caches the answer in plain `UserDefaults`.

### The build-number cutoff, and why 1000

`AppTransaction.originalAppVersion` returns the **build number** (`CFBundleVersion`) on iOS. This
project had no usable one: `CURRENT_PROJECT_VERSION` was `1` at every production site and
`/release` bumped only `MARKETING_VERSION`, so every shipped version appears in App Store Connect
as `1.1.x (1)` and every existing install reports `originalAppVersion == "1"`.

The fix, applied in this ticket: `CURRENT_PROJECT_VERSION` is now **1000** at the six production
sites (GymStreak, GymStreakWidgetsExtension, GymStreakWatch Watch App × Debug/Release). The three
test targets keep `1`, matching how `/release` already treats `MARKETING_VERSION`. Everything in
the wild reads `1 < 1000` and is granted; this build and everything after it is not (the
comparison is strictly less-than, so the cutoff build itself never grants).

**`1000` is the first build carrying the entitlement layer — not, in general, the first build that
charges.** The concern was that gating ships off, the build number increments every release cycle,
and the paywall therefore arrives on build `1000 + k` — leaving everyone who installed during that
ungated window excluded from Founder despite never seeing a paywall.

**Settled 2026-08-17 (ticket 15): the ungated window is empty, so `cutoffBuild` stays at `1000`.**
No build carrying the entitlement layer was ever released. `CURRENT_PROJECT_VERSION = 1000` was
introduced by the entitlement-layer commit itself (`37fe741`), which reached neither `store-build`
nor `testflight-beta` — both still carried `CURRENT_PROJECT_VERSION = 1` when the launch release was
prepared. Every install in the wild therefore reports `1`, and the launch build (`1000 + 1` after
`/release`'s bump) is the first the App Store has ever served at or above the cutoff. There is no
cohort between the two, so nothing had to be re-pinned and no exclusion was accepted. TestFlight
never enters this: its `AppTransaction` environment is not `.production`, so §3a's environment guard
withholds the grant there regardless of build number.

> **This invariant is load-bearing.** If any future release ever ships a build number below
> `FounderStatusService.cutoffBuild`, every new paying user is silently granted Pro forever and the
> only symptom is missing revenue, discovered months later. Three things hold it:
> the `/release` command (Phase 3 Part B step 6b) and `merge-testflight-to-store` (step 9b) both
> increment `CURRENT_PROJECT_VERSION` every cycle and report the new build; and
> `FounderStatusTests.shippingBuildIsNotBelowCutoff` reads `Bundle.main`'s actual `CFBundleVersion`
> (the suite is app-hosted) and fails the build if it ever regresses.

### The four traps, and how each is closed

All four are silent-wrong-answer bugs — none of them errors, all of them just return the wrong
grant. Research verified 2026-08-13/2026-08-15 (`monetization-strategy.md` §7.1).

| Trap | Closed by |
|---|---|
| iOS returns `CFBundleVersion`, macOS returns `CFBundleShortVersionString` | The cutoff is a build number; a macOS sample must not be copied here |
| Sandbox, TestFlight and Xcode always return `"1.0"`, so every non-production run looks pre-cutoff | `guard environment == .production` — guarding the environment, never special-casing the string |
| String comparison silently reorders — `.compare(_:options:.numeric)` falls back to lexicographic without erroring | `Int(originalAppVersion)`, compared as `Int` |
| `AppTransaction.shared` is `async throws` and may need the network, so a genuine first-launch-offline throws | On throw the decision stays **undecided** and is retried next launch; nothing is written |

Plus verification: only `.verified` can grant. `.unverified` is precisely the
forge-a-pre-cutoff-transaction vector, so it fails closed.

### Undecided is a real third state

The cached decision is three-valued — absent / `true` / `false` — not a `Bool`, because
`UserDefaults.bool(forKey:)` cannot distinguish "not resolved yet" from "resolved to
not-a-Founder". Persisting a `false` in any of the fail-closed branches would **permanently
disinherit** a Founder whose first launch merely happened to be offline, or who first ran a
TestFlight build. So: a throw, an `.unverified` result, a non-production environment, and a
non-numeric version all leave the decision absent and retry on the next launch. Only a verified
production transaction with a parseable build number ever writes anything.

A consequence worth knowing while developing: **Founder never resolves in a debug, simulator or
TestFlight run** — the environment guard makes that so by design. The DEBUG entitlement picker
(§6) is how you see the Founder branch.

### Why `AppTransaction`, and why the protocol seam

`AppTransaction` is the App Store's signed record of the *app download*, held server-side against
the Apple Account — not an IAP receipt — so it works for an app that has never had an in-app
purchase, and it is the only candidate that survives the case that decides the whole grant: the
user deleted the app before the paywall existed and reinstalled after. `monetization-strategy.md`
§7.1 has the survivability comparison against the local alternatives.

`OriginalAppDownloadReading` exists because **`AppTransaction` has no public initializer** (checked
against Apple's documentation, 2026-08-15: every value-producing path — `shared`, `refresh()` —
routes through StoreKit's real signing pipeline, and `VerificationResult` needs an `AppTransaction`
to wrap). Without the seam, none of the six decision branches could be unit-tested at all. The
protocol and its production conformer live next to the service in `Data/Purchases/`, following the
`RestTimerNotificationCenter` / `SeedCatalogVersionStore` precedent — a test-substitution seam is
not a Domain capability, and `Data/Purchases/` is the only directory permitted to import a
purchase framework.

`StoreKitOriginalAppDownloadReader` is stateless and not itself annotated `@MainActor`: it
inherits that isolation from the protocol it conforms to. It is therefore constructed explicitly
in `AppDependencies` rather than appearing as a default argument — a default argument expression
is evaluated outside the enclosing declaration's isolation and would not compile.

### Concurrency

`AppTransaction` and `VerificationResult` are both `Sendable` and neither declares a main-actor
requirement (verified 2026-08-15), so the `@MainActor` service awaits `AppTransaction.shared`
directly — Concurrency rule 5's "no escape hatch needed" case. No `nonisolated` hop, no
`@concurrent`, no boundary projection. The call is a suspending I/O round-trip, not main-thread
computation, which is why it does not need to leave the main actor the way the History aggregation
does.

### Persistence

Plain `UserDefaults` under `pro.isFounder`. No iCloud KVS mirroring: `AppTransaction` is itself
the durable cross-reinstall, cross-device source of truth, so mirroring the derived flag would add
a second thing to keep in step and buy nothing. (An earlier draft of the strategy doc called for
KVS mirroring and was wrong.) No SwiftData model changed, so **no CloudKit Console schema deploy
is needed** for this ticket.

## 3b. The RevenueCat entitlement

The second source of Pro, and the only one that can be *bought*.

### The package

`https://github.com/RevenueCat/purchases-ios-spm.git`, pinned **up-to-next-major from 5.0.0**
(resolved: **5.83.2**, `Package.resolved` is committed). This is the SPM-only mirror of
`purchases-ios` — byte-identical per tag, smaller checkout.

The package vends four products; **only `RevenueCat` is linked**, and only into the iOS app target.
`RevenueCatUI` (paywalls, Customer Center) is deliberately not added yet — ticket 14 adds it. The
watch target has no package product dependency and therefore does not link RevenueCat at all: per
`monetization-strategy.md` §4.1 the entire watch app is free, so there is no watch-side gate and
nothing to mirror over WatchConnectivity. Note that this is a *choice, not a constraint* — the
package does support watchOS 6.2+, so adding it there is a one-click mistake to watch for in review.

### Configuration

Configuring happens in `RevenueCatPurchaseGateway.init()`, i.e. from the composition root inside
`GymStreakApp.init()` — once, before any UI exists and before anything can read an entitlement:

```swift
Purchases.logLevel = .warn
Purchases.configure(
    with: Configuration.Builder(withAPIKey: RevenueCatConfiguration.apiKey)
        .with(appUserID: nil)
        .with(entitlementVerificationMode: .informational)
        .with(storeKitVersion: .storeKit2)
        .build()
)
```

- **`appUserID: nil`** makes the SDK generate and cache an anonymous identifier. That is what
  preserves the no-account promise (`monetization-strategy.md` §1). There is no login, no
  `logIn`/`logOut`, and `collectDeviceIdentifiers()` is deliberately never called — it pulls in
  `AdSupport` for attribution this app does not do.
- **`.informational` verification** never blocks access on its own; it only *surfaces* the signal,
  which the mapping below then acts on.
- The `guard !Purchases.isConfigured` at the top is not defensive noise: an app-hosted test run can
  build a second composition root in the same process, and configuring twice trips the SDK's own
  warning.

### The API keys, and why they are in the repo

Both live in `RevenueCatConfiguration` so ticket 15's swap is a one-line diff.

**RevenueCat *public SDK* keys are designed to ship inside the app binary and are not secrets** —
the repo's env-var-placeholder policy (`docs/agents/mcp-servers.md`) covers `.mcp.json` server
credentials, not this. A RevenueCat **secret** REST API key must never appear in the app.

> ⚠️ **No App Store submission may carry the Test Store key.** The SDK logs this itself on every
> launch: *"Apps submitted with a Test Store API key will be rejected during App Review."* Ticket
> 15's key swap is therefore a **release blocker**, not a cleanup — and it lands before the next
> submission, not before the next *release cycle*. TestFlight builds distributed to external
> testers go through App Review too. Internal-only TestFlight builds are unaffected, which is what
> makes shipping the integration this early safe at all.

The Debug default is `test_IjLklyuZDXOVrXMjaURxfwJnWxk`. **The `test_` prefix is load-bearing**: it
routes the SDK to RevenueCat's **Simulated Store** (`Store.testStore`), where offerings, purchases,
entitlements and restore all work in the simulator with no App Store Connect products and no
StoreKit configuration file. That is what let the whole purchase path ship *before* Apple approved
the real subscriptions. Production Apple keys begin with `appl_`; **`appStoreAPIKey` has been filled
in since ticket 14a**, and outside DEBUG `apiKey` resolves to it unconditionally while the `test_`
literal is not compiled in at all (§9.4a).

### The entitlement identifier — the highest-risk string in the integration

**Confirmed in the RevenueCat dashboard on 2026-08-15** (Product catalog → Entitlements, REST id
`entl4a899fb281`):

| Field | Value |
|---|---|
| Entitlement identifier | `Gym Streak Pro` — **spaces and capitals included** |
| Display name | Gym Streak Pro (identical, which is why this needed checking) |
| Attached Test Store products | `lifetime`, `yearly`, `monthly` |

RevenueCat entitlements are looked up by *identifier*, and here the identifier happens to be the
display name rather than the conventional lowercase slug (`pro`). Getting it wrong does not error:
`customerInfo.entitlements["…"]` simply returns `nil`, every paying user silently reads as free
tier, and **neither a build nor a test that stubs the gateway can catch it** — the stub tests below
verify the composition, not the string. The only thing that verifies it is a real Test Store
purchase flipping the entitlement, which is exactly what the debug store section (§6) exists for.

App Store Connect product IDs will differ from the Test Store ones; mapping them is dashboard
configuration, not code.

### Mapping `CustomerInfo` to an entitlement

`RevenueCatPurchaseGateway.entitlement(in:source:)` reduces a customer record to
`PurchasedProEntitlement` (`.none` / `.subscription` / `.lifetime`) on three conditions:

```swift
guard let pro = customerInfo.entitlements[RevenueCatConfiguration.proEntitlementIdentifier],
      pro.isActive,
      pro.verification != .failed
else { return .none }
return pro.expirationDate == nil ? .lifetime : .subscription
```

- **`.failed` verification never grants.** That case means the response could not be authenticated
  — the MITM/forgery vector — so it fails closed, consistent with the position §7.1 of the strategy
  doc takes on unverified `AppTransaction`s. `.verified`, `.verifiedOnDevice` and `.notRequested`
  are *not* failures and do grant; treating `.notRequested` as a failure would deny everyone the
  moment verification is ever turned off.
- **Lifetime is the non-expiring grant.** There is no `isLifetime` flag on `EntitlementInfo`. A
  subscription always carries an `expirationDate` — even once cancelled but not yet lapsed, which
  is precisely when `willRenew == false` would be the wrong test — while the one-time purchase
  carries none. (`customerInfo.nonSubscriptions` would corroborate it, but reading it as well buys
  nothing here.)

### Composition: Founder wins

`ProEntitlementProvider.recompose()` is the whole rule:

```swift
guard !founderStatus.isFounder else { resolvedState = .founder; return }
// else: .none → .free, .subscription → .subscription, .lifetime → .lifetime
```

Founder takes precedence because the grant is local, permanent and offline-durable, and it must
never depend on RevenueCat having answered — a failed lookup reports "no purchase", which is
indistinguishable from a genuine free user. `refresh()` therefore composes **twice**: once right
after the Founder grant resolves, and again after the purchase layer answers. That ordering is the
implementation of "a grandfathered user never loses access because a network call failed", and
`founderDoesNotWaitOnThePurchaseLayer` pins it with a gateway that never returns.

The accepted consequence: a Founder who somehow *also* held a subscription would read as `.founder`,
so ticket 13's Settings section would show the grandfathered source rather than the paid one. A
Founder is never shown a paywall, so nothing in the app can produce that pairing.

### Live updates, and why there is no foreground refresh

`entitlementUpdates()` wraps `Purchases.shared.customerInfoStream`, a plain
`AsyncStream<CustomerInfo>` that **yields the cached value immediately on iteration** and then
every change. A purchase, a lapse, a restore, or a subscription bought on another device all land
without an app restart, and because `state` is `@Observable` every gate re-evaluates on the spot.

⚠️ **This held all along — but it could not be observed, and two rounds of debugging went after it
anyway.** The entitlement never flipped because RevenueCat was reporting no entitlement to flip to,
and every attempt to confirm that by relaunching the app instead turned gating off entirely. **Read
§9.4b before debugging anything in this area.**

This is why ticket 01's noted follow-up — "`resolveIfNeeded()` has no in-flight guard, so ticket
03's foreground refresh must add one" — **did not materialise**: no scene-phase refresh was added,
because the stream already keeps the entitlement current. `refresh()` runs once per launch, plus
once after a purchase and once after a restore. It still has no in-flight guard, so those *can*
overlap and each one re-runs the `AppTransaction` round-trip outside production — which is exactly
what §3d had to route the entitlement read around. If a foreground refresh is ever added on top,
the guard comes with it.

The modern async surface is used throughout — `customerInfoStream` rather than the
`PurchasesDelegate` callback, `customerInfo()`, `purchase(package:)`, `restorePurchases()`.

### 3c. Making a purchase repaint the screen

**The observation this section was built on.** Buying a subscription in the sandbox left the Pro
lock on screen "until the app was relaunched", and nothing was asking SwiftUI to draw again:
`RoutinesViewModel.isRoutineCapReached` is computed live from `ProEntitlementProviding`, so a
correct value on its own does not move the screen.

⚠️ **The "until the app was relaunched" half was never real** — see §9.4b. The relaunch was not
delivering a correct entitlement; it was dropping `-PRO_GATING_ON` and turning *every* gate off,
which looks exactly like a working subscription. So the redraw bug this section describes was never
actually demonstrated, and it is likely not a bug at all: `RoutinesView`'s body reads
`viewModel.routineCapNudge`, whose getter reads the `@Observable` provider *during body evaluation*,
so SwiftUI registers the dependency transitively — the same reason the table's second row says
"Yes". The `EntitlementChangeObserver` is kept because it is correct, cheap and harmless insurance
for any consumer that reads the entitlement *outside* a body, not because it was proven necessary.

Everything below still describes the code as it stands. Read it as a design note, not as a
post-mortem — the post-mortem is §9.4b.

**Why only some surfaces broke.** There are three ways a gate ends up on screen, and only one of
them was affected:

| How the gate is drawn | Updates on purchase? |
|---|---|
| A view reading `entitlements.state` inside `body` (§5i's Settings section) | **Yes** — Observation tracks the read directly |
| An `@Observable` ViewModel whose computed property reads it (the three AI tasters' §8 D nudges, via `AICoachAllowanceGate`) | **Yes** — the read happens inside the view's tracking scope, so the dependency is registered transitively even though the gate itself is a plain class |
| A ViewModel that *stores* an entitlement-derived value (`PeriodRecapViewModel.state`) | **No** — see below; the only such case in the app |
| A legacy `class … : ObservableObject` ViewModel (`RoutinesViewModel`, `ExerciseProgressViewModel`) | **No** — the view is subscribed to `objectWillChange`, and an `@Observable` provider changing publishes nothing on it |

The last row is P1 (the routine cap and its §8 D nudge), P2 (chart metrics and windows) and P9
(weekday schedules, which lives in `RoutinesViewModel`) — i.e. every non-AI gate in the app.

**The fix.** `EntitlementChangeObserver` bridges the two worlds: it watches the provider with
`withObservationTracking` and calls back, and both legacy ViewModels install one in `init` to send
`objectWillChange`. Three details are load-bearing:

- **`withObservationTracking` is one-shot.** It reports the first change and then stops, so the
  observer re-arms itself inside its own callback. Forgetting that produces a gate that updates
  exactly once per launch — which looks fixed and is not.
- **The callback hops to the main actor before doing anything.** `onChange` is `nonisolated` and
  fires *during* the mutation, before the new value is stored; the hop is what makes the redraw see
  the value that was just written. `Task { @MainActor in … }`, never `DispatchQueue.main.async`.
- **It observes `state`, not `isPro`.** `isPro` collapses four entitlements into a `Bool`, so a
  subscription becoming lifetime would notify nothing — and §5i's Settings section names the source,
  not just the tier.

For `ExerciseProgressViewModel` the republish does more than repaint: `chartTimeframe` is part of
`loadKey`, which `.task(id:)` keys off, so the re-render is what actually re-fetches the wider
window a purchase just unlocked.

**The recap needed a different fix, and it was the worst case of the three.** `PeriodRecapViewModel`
is the one place a gate is *stored* rather than derived: `.gated` and `.offer` are steps in a flow —
the screen shows them and waits for a tap — so they are written into `state`. Republishing cannot
help, because there is nothing to re-derive. A user who bought Pro **from this screen's own paywall**
kept the lock *and* lost the way out: `unlock()` asks `PaywallPresenter`, which correctly refuses to
show a paywall to a Pro user, so the button became inert and the only escape was leaving the screen
and coming back. The fix is re-entry: `allowanceReloadKey` exposes `allowanceGate.isMetered` — live,
because it reads the `@Observable` provider — and `PeriodRecapView` keys its `.task(id:)` on it, so
ceasing to be metered re-runs `load` and streams the recap that was just paid for.
`ExerciseDeepDiveViewModel` and `CoachChatViewModel` were checked and are clean: a refusal there
leaves `state` untouched by design.

**A caveat about "it does not fire on unrelated churn".** That guarantee is not in
`EntitlementChangeObserver`, which has no dedupe and forwards every invalidation it is given. It
holds because Observation suppresses a same-value write when the property is `Equatable` — the
`@Observable` macro compares before notifying — and `ProEntitlementState` is a raw-value enum.
`idempotentStateDoesNotNotify` is the empirical proof, and it is worth keeping precisely because
this is the kind of claim that gets "corrected" from memory: it was challenged during the §3d review
on the grounds that the macro's setter notifies unconditionally, and the test settles it.

Since §3d `recompose()` no longer relies on that anyway: it computes the composed state and
**returns without writing when it equals the current one**. `refresh()` recomposes three times per
call and has three callers, so most recompositions are no-ops, and the guard means neither the
observers nor the device log see them whatever the property's conformance does later.

**One consequence of the recap's re-entry key, recorded rather than changed:** it fires on a *lapse*
too, and a lapsed user with no cached recap reaches `presentPaywallIfExhausted()` — so that screen
can now raise a paywall without a tap. It is unreachable during a workout (Rule 3's cover blocks the
root sheet) and needs a subscription to expire while the screen is open, but it is a new trigger on
an old path. The cache is checked *before* the meter, so a lapsed user whose recap is cached still
sees it (§7 Rule 4).

**Two belt-and-braces refreshes.** The stream is the designed path, but its delivery is not
something the app controls, and a purchase and a restore are the two moments where a late update is
most damaging. So `ProPaywallView.onPurchaseCompleted` and the Customer Center's `restoreCompleted`
both call `entitlements.refresh()`. Since §3d neither can degrade the entitlement it follows — a
read that *fails* now writes nothing at all, where it used to write "no purchase".

**Why the existing tests did not catch it.** `StubProEntitlements` is a plain class, so every gate
test read a stored property back and got the right answer — exactly as the shipping app did.
`EntitlementRefreshTests` therefore asserts **notification**, not value: `objectWillChange`
emissions for the legacy ViewModels, and `withObservationTracking` invalidation for the AI gate,
against an `@Observable` stub that behaves like the real provider. A value-based test here would
pass on the broken code, which is the whole lesson.

### 3d. Making a purchase actually flip the entitlement

**The bug this section exists for.** After §3c shipped, a real sandbox purchase on a device *still*
left every gate locked — and this time provably at the value, not the screen: tapping "new routine"
re-raised the paywall, and that path (`RoutinesViewModel.requestAddRoutine` →
`PaywallPresenter.present`) reads `entitlements.isPro` at tap time and renders nothing. A relaunch
fixed it, because the launch refresh reaches the purchase layer on a quiet main actor.

Three defects, all in `Data/Purchases/`:

**1. The purchase read was queued behind a StoreKit round-trip that, in development, never ends
early.** `refresh()` was written `await founderStatus.resolveIfNeeded()` *first*, so that a
grandfathered user is Pro before the network is consulted. But `resolveIfNeeded()` calls
`AppTransaction.shared`, and `FounderStatusService.resolveDecision()` returns `nil` — recording
nothing — for every non-production environment (§7.1 trap 2 guards on `environment == .production`).
So in the sandbox, in TestFlight and under Xcode the decision is *never* settled and **every single
`refresh()` re-runs the StoreKit round-trip.** A refresh fired the instant the user paid therefore
sat behind a call that takes seconds, can want an App Store sign-in sheet of its own mid-purchase,
and had a second copy of itself already in flight from the launch `.task` (there is still no
in-flight guard). The entitlement it was supposed to deliver arrived far too late or not at all.

The fix is ordering, not removal. `refresh()` now composes **three** times: once immediately (a
Founder grant already on record is live with no I/O at all — which is what the Founder-first
ordering was really protecting), then after the purchase read, then after the Founder resolution.
`purchaseDoesNotWaitOnTheFounderResolution` pins it with a resolution that never returns.

**2. "Could not ask" was indistinguishable from "no purchase", so a failed read revoked Pro.**
`currentEntitlement()` and `restorePurchases()` caught every error and returned `.none` — the same
value that legitimately means *this account holds nothing* and correctly drops the entitlement. The
gateway's own comment claimed this was "never revoked"; it was not true. Any refresh that lost the
network — including the launch one resuming after the user had already bought — wrote `.free` over
a subscription the stream had just delivered. Both reads now **throw**, and the provider writes
nothing on a throw. This is the one place the "no method throws" rule stated above is deliberately
broken, and the protocol says why. Pinned by `unreachablePurchaseLayerDoesNotRevoke` and
`unreachableRestoreDoesNotRevoke`.

⚠️ `PurchasedProEntitlement` has a `.none` case, so these must **not** be modelled as
`PurchasedProEntitlement?` — `.none` on the optional silently resolves to `Optional.none`. Same trap
`ProEntitlementState` avoids by naming its zero case `free`.

**3. The paywall did not close after a successful purchase.** `onRequestedDismissal` was assumed to
fire for a completed purchase as well as for the close button. It does not: RevenueCat deliberately
does not auto-dismiss on purchase and does not route one through that hook
([purchases-ios#3617](https://github.com/RevenueCat/purchases-ios/issues/3617),
[#3691](https://github.com/RevenueCat/purchases-ios/issues/3691)) — dismissal is the host app's job.
`ProPaywallView.onPurchaseCompleted` now calls `dismiss()` itself.

**The entitlement path is now logged**, subsystem `app.gymstreak.pro`, categories `Purchases` and
`Entitlement`. `RevenueCatPurchaseGateway.entitlement(in:source:)` records every outcome with its
source (`stream` / `read` / `restore`), and the four ways it can report `.none` — identifier absent
(with the identifiers that *were* present), inactive, failed verification, or genuinely nothing —
are now distinguishable, which §9.4a's failure table previously could not be from the outside.
`ProEntitlementProvider.recompose()` logs the transition only, never the no-op recompositions.
**This is the trail to read first** the next time a real purchase does not land; it costs nothing
and the alternative is another round of inference against a store that cannot be unit-tested.

**What was checked and left alone.** `customerInfoStream` was suspected and cleared: the SDK
registers its observer synchronously when the property is read (`CustomerInfoManager.swift`,
`bufferingPolicy: .bufferingNewest(1)`), it emits on every cache update including a purchase's, and
the gateway's relay-`Task` wrapper does not drop values. `currentEntitlement()` also deliberately
keeps the **default** `CacheFetchPolicy` (`.cachedOrFetched`) rather than `.fetchCurrent`: a
purchase is itself one of the three events that refreshes RevenueCat's cache, so the entitlement is
already there when the post-purchase read runs, while on a cold offline launch a cached answer beats
an error. If the logs ever show a `read` disagreeing with a `stream` emission, `.fetchCurrent` on
the post-purchase path is the next thing to try.

### Concurrency

- The provider owns the observation as a stored `Task` and cancels it in **`isolated deinit`**
  (SE-0371) — the same pattern as `CloudKitSyncStatusMonitor`. A plain `deinit` is `nonisolated`
  and could not read the main-actor property; a detached task would outlive the provider and keep
  iterating the stream.
- Inside the gateway, the stream is wrapped by a relay `Task` whose lifetime is tied to the
  returned `AsyncStream`: cancelling the iteration terminates the continuation, whose
  `onTermination` cancels the relay. Nothing is left running.
- **No escape hatch is needed anywhere here** (Concurrency rule 5's easy case): `CustomerInfo`,
  `Offerings` and `Package` are `Sendable`, `Purchases` is `@unchecked Sendable`, and the SDK's
  async surface declares no main-actor requirement, so the `@MainActor` gateway awaits it directly.
  No `@concurrent` either — these are suspending I/O round-trips, not main-thread computation, so
  rule 1's `SwiftDataHistorySnapshotProvider` case does not apply.
- `entitlement(in:source:)` is `nonisolated static` because it is pure and runs inside the relay.

### Every failure degrades to the free tier

No failure reaches a gate: it can neither crash nor hang because RevenueCat is unreachable. The two
*reads* throw (§3d) and the provider swallows both — everything else converts a failure into a
value at the seam.

| Failure | Behaviour |
|---|---|
| `customerInfo()` throws (offline, backend down) | Rethrown, and the provider **writes nothing** — never *revoked*, never persisted; the next stream emission corrects it. Returning `.none` here is what let an offline refresh un-buy a subscription (§3d) |
| `restorePurchases()` throws | Same: a restore that could not run is not a restore that found nothing |
| Offerings/products fetch fails | `[]` products → the purchase surface shows "no products" rather than an empty sheet |
| `purchase(…)` throws | `.failed(message)`, surfaced as text |
| User dismisses the purchase sheet | `.cancelled` — **not an error**, no alert. It arrives on *two* paths: the async API returns normally with `userCancelled == true`, and some paths still throw `ErrorCode.purchaseCancelledError`; both are handled |
| Entitlement never resolved | Treated as not entitled, and nothing is written down |
| Network entirely unavailable | The Founder path is untouched — it never calls this gateway |

**Observed on device 2026-08-17**, in the airplane-mode pass: `Entitlement read failed, keeping none
— … OFFLINE_CONNECTION_ERROR`. That is row 1 of the table doing its job — "keeping none" is the
provider declining to *write*, not a revocation. It reads as free tier here only because the run was
a fresh install with nothing cached; RevenueCat serves a cached `CustomerInfo` on any install that
has resolved once, so an existing subscriber going offline keeps Pro.

### Buying: offerings, with a products fallback

`availableProducts()` reads `offerings().current?.availablePackages` first — the path ticket 14's
paywall will use — and falls back to `Purchases.shared.products(["lifetime", "yearly", "monthly"])`.
The fallback exists because an entitlement can be fully configured with its products *before*
anyone builds an Offering around them, and a purchase surface that shows nothing in that state is
indistinguishable from a broken integration. Whichever path ran, the resolved store object is
cached by identifier so `purchase(_:)` can name it without a RevenueCat type crossing the seam.

Note the Simulated Store serialises purchases — one at a time — so the debug section disables its
buttons while a purchase is in flight.

## 4. Caps live in one place

`ProFeatureCaps` holds every free-tier limit as a named constant: 3 routines, 5 coach-chat
messages/month, 1 period recap/month, 1 exercise deep-dive/month, `.maxWeight` as the only free
chart metric, and `[.week, .month, .threeMonths]` as the free chart windows.

This is the direct mitigation for §9's **deliberately skipped Phase 0**: the app has no analytics
backend (a consequence of the no-account position in §1), so these numbers could not be measured
before launch and will be tuned from post-launch App Store Connect / RevenueCat data instead.
§4.4 expects a 3-vs-4 A/B test on the routine cap specifically. Retuning any cap must stay a
one-line diff — never re-derive a limit at a call site.

`ProEntitlementTests` asserts the literal values, so a silent retune fails the suite and has to be
a conscious edit in both the code and `monetization-strategy.md`.

## 5. The kill switch

`ProGating.isEnabled` is a single global flag. **`ProGating.shippedValue` is `true` since the
Phase 2 launch release (ticket 15, 2026-08-17)**; it shipped `false` through Phase 1.

One flag, not one per gate: §9's rollout ships the entitlement layer silently in Phase 1 and flips
gating on in Phase 2 (ticket 15). A per-gate flag set would make "is gating live?" un-answerable
at a glance and would allow a half-gated release. A gate reads the switch *and* the entitlement —
with the switch off, nothing blocks. The paywall presenter reads it too (§5a), so "no gate blocks
but a paywall still appears" is impossible.

**Flipping it back is the rollback**, and it is a real one rather than a stated intention: every
gate was built to leave existing routines, schedules and history intact and editable (§5c, §5d, §7's
Rule 4), so turning gating off restores the pre-monetization app in one release without touching
data. Two things travel with it — the storefront copy (§9.6, `docs/marketing/app-store-description.md`)
must be reverted in the same release, and the `gatingShipsOn` assertion in `ProEntitlementTests`
has to be flipped, which is deliberate: the constant should not be changeable without a
second, obviously-intentional edit.

Since the shipped value is `true`, the Debug-only **`-PRO_GATING_OFF`** launch argument is the only
way to see the pre-monetization app again — including to verify that rollback claim. It is the
counterpart to `-PRO_GATING_ON`, which was the useful direction before the flip and is a no-op now
(§9.4a). `-PRO_GATING_OFF` wins if both are passed.

## 5a. The paywall presentation seam

A gate says `paywalls.present(.routineCap)` and is done. It never learns whether a paywall
appeared, what it looked like, or who drew it.

**Placements, not booleans.** `PaywallPlacement` enumerates the `monetization-strategy.md` §8
triggers: `firstRoutineCreated` (A), `valueMoment` (B), and the seven contextual gates (C)
`routineCap`, `chartMetric`, `chartWindow`, `coachChat`, `periodRecap`, `exerciseDeepDive`,
`weekdaySchedule`. The enum exists in this shape because RevenueCat's **Placements** feature keys
dashboard-authored paywalls off exactly this kind of identifier
(`offerings.currentOffering(forPlacement:)`), so ticket 14 hands the case straight to the SDK and
paywall *content* becomes a dashboard concern while paywall *triggering* stays in code.
Consequence worth knowing: **`rawValue` is a wire string** (`"routine-cap"`, …). Renaming a case
without renaming the dashboard Placement does not fail — it silently falls back to the default
offering.

Each case carries `kind` (§8 row), `isOneShot`, and a `headlineKey`. The headline lives on the
placement because §8 C demands a gate name the specific thing being unlocked — "Unlimited
routines", never "Go Pro" — and passing that copy in from the call site would spread one decision
across nine places. The strings are localized (`paywall.headline.*`, en + de).

Two §8 entries deliberately have **no** case: **placement D** (the cap-approach nudge) is not a
paywall but an inline hint owned by the screen showing it, and **P7** (custom exercises beyond 3)
is not a shipped gate — there is no cap constant for it and no gate ticket. Conversely
`weekdaySchedule` is the one case §8's C row does not spell out: it is P9 in §5's gate matrix, a
shipped gate, and a contextual placement in every respect.

**All four eligibility rules live in `PaywallPresenter`, not at the call sites:**

1. **The kill switch** — `ProGating.isEnabled`, injected via `isGatingEnabled` rather than read
   inline, so the eligibility logic stays testable whichever way the shipped switch is pinned. With
   the flag baked in, every test would pass for the wrong reason.
2. **Rule 3, absolute** — no paywall, upsell or Pro badge inside an active workout session (§8).
   Checked in the one place a presentation can happen, because the failure mode is a
   rage-uninstall and nine call sites each remembering is not a mechanism. The **debug bypass does
   not lift it either** — bypassing it would prove the wrong thing.
3. **The entitlement** — a Pro user, Founder included, is never shown a paywall.
4. **§8's frequency cap** — A and B fire once each, ever, recorded in `UserDefaults.standard`
   under `pro.paywallPresented.<identifier>`. Not the App Group suite and not mirrored to iCloud
   KVS: this is device-local presentation history that neither the widget nor the watch can use,
   and a reinstall showing the soft placement A once more is the benign outcome.
   The presenter also keeps the fired set **in memory**, seeded from the defaults at init, and
   `hasPresented(_:)` answers from that. Not redundancy — `UserDefaults` is not observable, so
   while the query read it directly, a view rendering from the answer (the debug section's
   "already fired") only updated on the next launch. Any future UI keyed off a one-shot inherits
   the fix.

**Raised is not presented, and the difference is load-bearing.** The app root also hosts two
full-screen covers (the coach chat, the AI opt-in), and a `.sheet` raised while one of them is up
never reaches the screen. So the presenter tracks the two states separately: `present(_:)` sets
`pendingPlacement`, and the host reports back when the sheet arrives. A request suppressed by Rule 3
or lost behind a cover is therefore never burned. The "don't swap a sheet mid-presentation" guard
keys off *presented*, not *pending*: a placement the host could not show is replaced by the next
request instead of wedging the seam for the rest of the session. This matters concretely for ticket
08 — `.coachChat` is by definition raised from inside the coach-chat cover.

**The host reports back twice, and the split is not pedantry.** `sheetDidAppear()` says the sheet is
on screen; `didPresent(_:)` says an actual *offer* is. They are different moments because the paywall
inside the sheet fetches its offering over the network and may end on "couldn't be loaded" (§5j):

- The **swap guard** keys off the first. The user is looking at the sheet from the moment it
  appears, loading and retry states included, so nothing may replace it after that.
- The **once-ever fire** is spent on the second. A placement A or B raised offline would otherwise
  burn itself on a sheet that showed no offer — permanently, since the record survives relaunches.

Collapsing them into one report breaks whichever half it is tied to; `doesNotReplaceASheetStillLoading`
pins the case where that shows.

**Where "a workout is running" comes from.** There are two `WorkoutViewModel` instances (Routines
and History), each owning its own HealthKit session, so no ViewModel can answer that question for
the app. `ActiveWorkoutRegistry` holds the single flag; `WorkoutViewModel` keeps it in step from
`currentSession`'s `didSet` — that property *is* the session's lifetime, so the three call sites
that start, finish and discard a workout cannot forget. The registry is deliberately not
`@Observable`: nothing renders from it, the presenter asks at the instant a paywall is requested.

**Hosting.** `ContentViewInternal` owns the one `.sheet(item:)` bound to the presenter's
`pendingPlacement`, so a gate anywhere raises a paywall without its screen owning a sheet. A
second request while one is **on screen** is ignored rather than swapping the sheet's contents (a
request that never appeared is replaced instead — see above). What it shows is `ProPaywallView`,
the RevenueCat paywall for that placement (§5j). It replaced ticket 04's `PaywallPlaceholderView`
without a single caller, gate or eligibility rule changing — which is the whole thing the seam was
built to make true.

## 5b. The Pro lock UI kit

Three components in `Presentation/Views/DesignSystem/`, so the nine gates of tickets 06–11 look
like one product decision rather than nine improvisations. All of them are **presentational**:
they take values and a callback, never a ViewModel, never `ProEntitlementProviding`, never
`PaywallPresenting`. The caller decides *whether* to lock and what unlocking does — in practice
`{ paywalls.present(.chartMetric) }`.

**`OnyxProLockOverlay` / `.proLocked(_:placement:onUnlock:)` — the blurred preview.** The real
content keeps rendering behind a blur, a scrim and a lock card. **Blur rather than hide** is the
point, not a style choice: §3 Rule 2's engine is loss aversion against data the user generated
themselves, and a hidden feature produces no loss while a blurred chart of *your own numbers*
does. Blurred content is `allowsHitTesting(false)` and `accessibilityHidden(true)`; the card takes
its headline from `placement.headlineKey`, so §8 C's "name the specific capability" rule is
honoured by construction rather than re-decided per gate. The CTA uses `.onyxProminent`
(tint background, `textOnTint` label — never white on tint).

**Locked content must be cheap to render — this is a contract, not a preference.** Because the
content keeps rendering, its `body` is still evaluated on every invalidation, now with an
offscreen blur pass on top, all of it invisible. So a gate locks a *precomputed preview*: value
structs, no live aggregation in `body`, no formatter allocation, no SwiftData relationship reads.
`docs/history-performance.md`'s measured 630 ms hang came from exactly the shape that is tempting
here — a chart view that aggregates while it draws — and blurring it makes it cost the same while
showing nothing.

Four behaviours worth knowing before reusing it:

- **The scrim is an `overlay`, not a `ZStack` sibling.** A bare `Color` is infinitely greedy, so
  as a stack sibling it sizes the lock to the *proposal* rather than to the content, and the
  locked branch would occupy more space than the unlocked one inside an `HStack`, a grid cell or
  any `maxHeight: .infinity` parent. As an overlay the scrim inherits the content's geometry and
  `.proLocked(true)` / `.proLocked(false)` stay layout-identical.
- **The blurred content is `disabled(true)` as well as `allowsHitTesting(false)`.**
  `allowsHitTesting` silences only that subtree's own hit testing; it does nothing about an
  *enclosing* `NavigationLink` or `Button` — which is exactly the shape the chart-tab and
  Deep-Dive gates will have — so without `disabled` a tap on the blur would carry through to the
  gated screen, and Full Keyboard Access would still reach the hidden controls.
  **Modifier order is load-bearing here, and it was measured, not assumed** (throwaway
  `UIHostingController` probe reading `@Environment(\.isEnabled)`, 2026-08-15): an overlay
  attached *after* `.disabled(true)` reports `isEnabled == true`, one attached *before* it
  reports `false`. So the lock card's CTA works precisely because both `.overlay`s come after
  the `.disabled`. Moving `.disabled` below them would dim the CTA to 50 % (that is
  `OnyxProminentButtonStyle`'s disabled opacity) and make it untappable.

- **Reduce Transparency replaces the blur with an opaque scrim** (`accessibilityReduceTransparency`
  is read in the overlay). A blur is a legibility hazard for exactly the users who turn that
  setting on, and the lock card sits on top of it.
- **The lock card is a single VoiceOver element** (`children: .ignore`, label "Locked: <headline>",
  hint "Unlock with Gym Streak Pro", `.isButton`, plus an `accessibilityAction`). A blur conveys
  nothing to a VoiceOver user, and the content behind it is deliberately out of the tree — so
  without this the locked region would be silent.

The modifier's unlocked branch returns `self` unchanged, i.e. there is **no** wrapper view and no
`.id()` on either branch (an explicit `.id()` on both branches of a conditional inside a
`LazyVStack` freezes the swap — a bug this project has already paid for once).

**`OnyxProBadge`** — a tint capsule with a lock glyph and the "PRO" wordmark (`.icon` style drops
the wordmark for tight rows). Typography is `onyxCaption2`, so it scales with Dynamic Type instead
of staying a fixed 10pt. **§8's absolute prohibition covers the badge, not just paywalls**: no Pro
badge inside an active workout session, on the watch app, or on the rest-timer Live Activity.

**`OnyxCapNudge`** — §8 placement D. An inline "2 of 3 routines used" hint with a linear meter; it
turns `warning`-coloured at the cap. It is **not a paywall**: no CTA, and `allowsHitTesting(false)`
so it cannot swallow a tap meant for the content beside it. It takes its `text` **already
localized from the caller** rather than formatting one generic string, because each gate phrases
its allowance differently ("2 of 3 routines used" vs. "1 message left today") and a single format
string does not survive German translation; `used`/`limit` (clamped) drive only the meter and the
colour.

Strings: `pro.lock.*` and `pro.badge.*` in en + de. Every component has previews in dark, light and
at `.accessibility1`. Note that the Onyx palette is **fixed dark** — `DesignSystem.Colors` are
literal values, not asset-catalog appearances — so the light previews confirm the components do
not depend on the environment's colour scheme, not that a light theme exists.

## 5c. P1 — the three-routine cap

The first shipped gate (`monetization-strategy.md` §4.2a P1, §4.4). A free user may hold
`ProFeatureCaps.freeRoutineLimit` saved routine templates; asking for another raises
`.routineCap`.

**What is counted, and what is never counted.** The unit is a **saved routine template**.
Starting a workout from any routine is unlimited, always — the cap is on programming, never on
training. This is why the gate lives at the *creation entry points* and nowhere near
`WorkoutViewModel`: there is no cap check anywhere on the workout path, by construction.

**Lapse behaviour is the load-bearing rule** (§7's table, Rule 4). A user who built six routines
as a subscriber and then lapsed keeps all six, fully usable, editable and trainable. Nothing is
auto-deleted, hidden, made read-only, or reordered. `isRoutineCapReached` is
`count >= limit`, so it is simply `true` for that user — and *only* the two creation paths
consult it. `RoutineCapTests` asserts the six routines survive the entitlement dropping to
`.free`, that one of them can still be renamed and saved afterwards, and that creation is the
only thing refused.

**Where the decision lives.** Split in two. The *rules* are `Domain/Services/RoutineCapPolicy.swift`
— pure functions over three scalars (`routineCount`, `isPro`, `isGatingEnabled`) plus an
overridable `limit`, returning `isCapReached` and a `NudgeState` (`.approaching` / `.reached` /
`nil`). It produces **no user-facing text**: copy is Presentation's, and `Domain/` holds no
localization keys. Being pure is what lets the boundary math — including the retune §4.4 expects —
be asserted without a SwiftData container.

The *inputs and the copy* are `RoutinesViewModel`'s: it already holds the routine list, so the
count is free, and per Hard rule 3 a view does not get to decide whether persistence is allowed.
It takes `ProEntitlementProviding` and `PaywallPresenting` by init from `AppDependencies` (never
`.shared`), plus `isGatingEnabled` defaulted to `ProGating.isEnabled` — injected for the same
reason `PaywallPresenter` injects it: with the shipped flag baked in, every cap test would pass by
proving the gate is inert rather than that it is correct.

**Three affordances, one entry point.** The list header's "+", the dashed create tile and the
empty state all call `requestAddRoutine()`, which either opens the create flow or calls
`paywalls.present(.routineCap)`. **Duplication is creation**, so the check sits *inside*
`duplicateRoutine(_:)` — which now returns `Routine?` — rather than in a wrapper the two menu
call sites could forget to use. `RoutineDetailView`'s menu consequently fires its success haptic
*after* a non-`nil` result: a success haptic for a blocked action is a lie.

**The gate fires before the work, not at the save.** Refusing a routine the user has just spent
five minutes building is a worse experience than never opening the flow, so nothing in the
creation path itself is gated: `createRoutine(name:pendingExercises:)` always saves. A user who
entered the flow under the cap and crossed it mid-flight (watch sync, iCloud) keeps their work —
covered by `inFlightCreationIsNeverLost`.

**The nudge (§8 placement D).** `routineCapNudge` returns a `RoutineCapNudge` value struct —
finished string, `used`, `limit` — or `nil`. It appears on the last free slot ("2 of 3 routines
used") and *stays* once the cap is reached, which is exactly what removes the surprise from the
gate. The at-cap copy (`routines.cap.nudge.reached`) is deliberately **number-free**: a lapsed
user can be at 6 of 3, and "all 3 used" would be a visible lie. At the cap the dashed create tile
also carries an `OnyxProBadge(style: .icon)`, so the gate is honest before the tap.

It is a **computed** property, not stored state refreshed in `fetchRoutines()`. Reading the
`@Observable` entitlement provider inside it — during the list's `body` evaluation — is what makes
a purchase or a lapse remove or restore the nudge live, with no refetch; stored state would go
stale until the next fetch. It stays inside the main-thread rules because it counts nothing
(`routines.count` on an array the ViewModel already holds), allocates no formatter, and touches no
SwiftData relationship. `nudgeFollowsTheEntitlement` is the regression test for the live half.

**With the kill switch off nothing changes** — no nudge, no badge, no gate, no paywall — which is
its own test (`killSwitchOffBehavesAsBefore`) rather than an inspection.

Strings: `routines.cap.nudge` and `routines.cap.nudge.reached`, en + de.

## 5d. P2 — progress analytics gating

The second shipped gate (`monetization-strategy.md` §4.2a P2, §3 Rule 2, §5 history retention,
§7 lapse behaviour). A free user charts `ProFeatureCaps.freeChartMetric` (max weight) over
`ProFeatureCaps.freeChartTimeframes` (1W / 1M / 3M). Estimated 1RM, total volume, 1Y and All render
as a **blurred preview of the user's own real data** with an unlock CTA, and raise `.chartMetric` /
`.chartWindow` respectively. The one surface is the exercise detail screen
(`ExerciseProgressChartView`) — `docs/progress-charts.md` documents the screen itself.

**Nothing is hidden, ever.** This gate narrows an *analytics view* and touches no persistence:
every workout, session and set stays readable in the History tab and in the recent-sessions list
below the chart, in every entitlement state. That is Rule 4 and §5's history-retention position —
Hevy caps the analytics window at three months but never deletes logs, and so do we.

**Where the decision lives.** Split like P1. The *rules* are `Domain/Services/ChartGatingPolicy.swift`
— pure functions over `isPro` and `isGatingEnabled` plus overridable caps, returning `isMetricLocked`,
`isTimeframeLocked` and `widestFreeTimeframe()`. No user-facing text: the lock copy comes from
`PaywallPlacement.headlineKey`, so this gate added **no new localized strings at all**.
The *inputs* are `ExerciseProgressViewModel`'s — it takes `ProEntitlementProviding`,
`PaywallPresenting` and an injected `isGatingEnabled` (defaulted to `ProGating.isEnabled`) by init
from `AppDependencies`, threaded through `ExerciseProgressChartView`'s public wrapper. The gate
predicates are read during the chart's `body`, deliberately: `proEntitlements` is `@Observable`, so
a purchase or a lapse re-evaluates the whole gate with no refetch and no app restart.

**A locked window is previewed, not fetched — this is the load-bearing rule.** §5b's contract says
locked content must be cheap to render, because a blur keeps paying the full render cost while
showing nothing, and this screen is the one that already produced a measured 630 ms hang
(`docs/history-performance.md`). So the view model separates the *selection* from the *rendered
window*:

- `selectedTimeframe` is what the pills highlight — a Pro-only window really is selected.
- `chartTimeframe` is what the chart draws, and it is what `loadKey` (and therefore the screen's
  `.task(id:)`) keys off. While a Pro-only window is selected it stays on `lastUnlockedTimeframe`,
  so tapping 1Y issues **no fetch at all** and blurs the window the user is entitled to.
- After a lapse `lastUnlockedTimeframe` can itself be Pro-only (it was picked while entitled), so it
  is clamped to `ChartGatingPolicy.widestFreeTimeframe()` — otherwise a lapsed user's chart would
  keep fetching a year of history purely to blur it. "Widest" reads `ChartTimeframe.allCases` as
  narrowest-first; `widestFreeWindowIsThreeMonths` pins that so reordering the enum cannot silently
  narrow every lapsed chart.

A locked **metric** costs nothing by construction: `ExerciseProgressDataPoint` already carries
`maxWeight`, `estimated1RM` and `totalVolume` from the single aggregation pass, so switching to a
locked metric selects a value that was computed either way — no second series, no second fetch.

**What is locked, and what must not be.** Only the chart headline and the chart content sit inside
`.proLocked`. The metric tabs and the range pills stay outside it, because `.proLocked` *disables*
what it blurs (§5b) — locking the whole card would leave a user unable to switch back off a
Pro-only selection and trapped behind the blur. Locked options carry `OnyxProBadge(style: .icon)`,
so the gate is honest before the tap rather than only after it.

**The stat triple falls back to the free metric.** PR and Trend are metric-derived, and printing an
estimated-1RM personal record in plain text directly above its own blurred chart would hand over
the number the gate is selling. `statMetric` returns the free metric while the selection is locked,
which for a free user on a free selection is simply the selection — i.e. unchanged from before the
gate existed. The third card (workout count) is metric-independent and untouched.

**With the kill switch off nothing changes** — no badge, no blur, no paywall, and `chartTimeframe`
is exactly `selectedTimeframe` — which is its own test (`killSwitchOffBehavesAsBefore`) rather than
an inspection.

**Deliberately not built:** no cap nudge (§8 placement D) for this gate. There is no allowance to
count down — a metric or a window is either readable or blurred — and the badge on the locked
option already removes the surprise.

**Known cosmetic consequences, both accepted.** On a *selected* locked range pill the badge's tint
capsule sits on the pill's own tint background, so the capsule shape disappears and only the black
lock glyph reads (contrast is unaffected — it is `textOnTint` on tint either way). And a locked
pill highlights as selected while the chart under the blur is the last unlocked window, so the
visible selection and the previewed data disagree; that is the price of not widening the fetch, and
the blur is what makes it invisible.

## 5e. P3, P4 and P5 — the metered AI surfaces

Three surfaces share one taster mechanic: a free user gets N generations per **calendar month**,
the N+1th raises the surface's placement, and everything already generated stays readable forever.
The machinery below is built once (ticket 08) and instantiated three times (ticket 09).

**The line all three enforce**, from `monetization-strategy.md` §4.3:

> AI about one workout is free. AI about your training is Pro.

Post-Workout Recap and Workout Analysis are scoped to the single session just finished — they are
**free and unmetered**, take no allowance gate, and have no `PaywallPlacement`. Coach Chat, the
Period Recap and the Exercise Deep-Dive reach across the user's history, so they carry a taster.
That boundary is the product promise; `singleWorkoutSurfacesAreNotMetered` pins it as an assertion
rather than a convention.

| Surface | Cap | Counting unit | Placement |
|---|---|---|---|
| P3 Coach Chat | `freeCoachChatMessagesPerMonth` (5) | a sent message | `.coachChat` |
| P4 Period Recap | `freePeriodRecapsPerMonth` (1) | a fresh generation | `.periodRecap` |
| P5 Exercise Deep-Dive | `freeExerciseDeepDivesPerMonth` (1) | a fresh generation | `.exerciseDeepDive` |

### P3 — the Coach Chat monthly taster

The third shipped gate (`monetization-strategy.md` §4.2a P3, §4.3, §7 lapse, §8 C/D). A free user
sends `ProFeatureCaps.freeCoachChatMessagesPerMonth` (5) chat messages per **calendar month**; the
sixth raises `.coachChat`. This ticket also builds the month-keyed allowance store that P4 and P5
(ticket 09) reuse without touching any of the logic below.

**Availability is checked before the entitlement, and that ordering is the rule, not an
optimisation.** Coach Chat needs iOS 26 and Apple-Intelligence hardware, and §4.3 is explicit that
the paywall must not lead with AI when availability reports unavailable: a device that *cannot run
the model* must never be shown a price for it. So `AICoachAllowanceGate` asks
`AICoachAvailabilityProviding` first and, on an unavailable device, allows every request, meters
nothing and raises nothing — the chat's existing unavailable state is what the user sees.
Unavailable is a disappointment, not a conversion opportunity.

**What consumes, and what never does.** The unit is a **sent message**:

- Consumption happens when a turn actually *starts* — not when the screen opens. A user who opens
  the chat, reads it and backs out has spent nothing.
- **A failed generation refunds the unit.** Charging for an error is indefensible. So does a turn
  that never started (empty input, a turn already running, an unavailable model) and a cancellation
  that produced no text at all — the user got no answer either way.
- **Reading the existing conversation is always free and never blocked**, in every entitlement
  state. That is §7's Rule 4 over the user's own data: `onAppear` still restores and renders the
  persisted conversation when the allowance is spent, and only the paywall is raised on top.
- The DEBUG Phase 0 drill bypasses the gate entirely (it never goes through `send`), so a
  40-turn diagnostic costs the developer's simulator nothing.

**Where the decision lives.** Split three ways, one layer each:

- **The arithmetic** is `Domain/Services/AIAllowancePolicy.swift` — pure, isolation-agnostic
  functions over `consumed`, `limit`, `isPro` and `isGatingEnabled`, returning `isMetered`,
  `remaining`, `isExhausted` and a `NudgeState` (`.lastRemaining` / `.exhausted` / `nil`). Like
  `RoutineCapPolicy` it produces **no user-facing text**. It is shared by all three metered
  surfaces, because the taster mechanic is identical and only the limit differs.
- **The counters** are `Data/Purchases/MonthlyAllowanceStore.swift` behind
  `Domain/Interfaces/MonthlyAllowanceTracking.swift` (three verbs: `consumedCount(for:)`,
  `consume(_:)`, `refund(_:)`).
- **The decision and its consequences** are `AICoachAllowanceGate`
  (`Presentation/ViewModels/AICoach/`): availability → entitlement → allowance, then either consume
  and hand back a `Ticket`, or raise the placement. It is built by
  `AppDependencies.makeAICoachAllowanceGate(for:)` — a gate is a cheap, stateless composition of
  app-lifetime collaborators, and the composition root is the only place that names them.

The gate is its own type rather than three methods on `CoachChatViewModel` for a testability reason
worth recording: the ViewModel holds `CoachChatService` **concretely** (Observation cannot see
`@Observable` reads through an existential — see `docs/ai-coach.md`), and that service is a
singleton over an on-device model that is unavailable in a test process. A ViewModel-level test of
"five messages then the wall" is therefore impossible. The gate takes no service, so every
acceptance criterion is assertable directly against it — and ticket 09 instantiates the same type
with `.periodRecap` / `.exerciseDeepDive`.

**`Ticket` exists so a refund cannot invent allowance.** `requestGeneration()` returns
`Ticket?` — `nil` means blocked (the paywall was raised) — and the ticket carries `didConsume`.
Unmetered requests (Pro, gating off, no Apple Intelligence) return a ticket that consumed nothing,
so the refund path is a no-op for them. A plain `Bool` would have made a refund after an unmetered
request hand the user a free message.

**The store: month-keyed, mirrored, and hostile to a rolled-back clock.**

- The key is a **calendar month** (`"2026-08"`), not a rolling 30 days, because a user can reason
  about "it resets on the 1st". It is built from `DateComponents` and `String(format:)`, never a
  `DateFormatter` — this is read on a path a view body evaluates (main-thread rule 2).
- Month and count are one record under one key (`pro.allowance.<surface>` → `"2026-08:3"`). A torn
  write that updated one and not the other would either hand out a free allowance or charge for a
  month never used.
- It writes **App Group `UserDefaults` and iCloud KVS** (§9), the latter behind `AllowanceCloudStore`
  for the same reason `SeedCatalogVersionStore` exists: `NSUbiquitousKeyValueStore` has one usable
  instance whose contents outlive deleting the app, so a test that wrote it would stamp the
  developer's simulator permanently. The mirror is the deliberate difference from the Founder flag
  (§3a), which needs none because `AppTransaction` is itself durable — a counter has no such
  backing and would otherwise be reset by deleting the app.
- Reading merges both stores with `MonthlyAllowanceRecord.newer` (later month wins; on a tie the
  larger count wins), so **neither store can lower the other** and a count only moves forward
  within a month.
- The active month is `max(current, stored)`. A device date moved **backwards** therefore keeps
  losing to the month already consumed, which closes the "reset the clock, get five more messages"
  hole. Rolling *forward* is not defended against and does not need to be: it spends the next
  month's allowance early and permanently forfeits the current one — a worse deal than waiting.
- Records are cached in memory after the first read per surface. That is a contract: the count is
  read from a computed property a view body evaluates, and `synchronize()` on every render would
  put file I/O on the main thread. The consequence, accepted: a KVS change arriving from another
  device mid-session is not observed until the next launch.
- **The cache is `[MeteredAISurface: MonthlyAllowanceRecord?]` — doubly optional, and that is the
  bug that nearly shipped.** Assigning `nil` to a `Dictionary` subscript *removes* the key, so with
  a singly-optional value the "no record yet" answer is never cached and every read falls through
  to `UserDefaults` **and** `NSUbiquitousKeyValueStore.synchronize()`. That is precisely the state
  of every free user before their first message — and, while the kill switch is off, of every user
  there is — on a path re-evaluated on each keystroke and each streamed token.
  `absentRecordIsCachedLikeAPresentOne` pins one backing read per surface, ever.
- `AICoachAllowanceGate.nudgeState` checks `isMetered` **before** touching `consumedCount`, so a
  Pro user and a kill-switch-off build never reach the store from a view body at all
  (`unmeteredUsersNeverTouchTheStore`).
- `UbiquitousAllowanceCloudStore.record(forKey:)` calls `synchronize()` before reading, mirroring
  `UbiquitousSeedCatalogVersionStore`. Kept for that parity now that the cache bounds it to one
  call per surface per process; it is a pull-latest-from-disk on a cold read, not a render-path
  cost.
- `MonthlyAllowanceRecord.newer` takes the **larger** count on a month tie, so a refund that has
  propagated to KVS can be re-raised by a second device still holding the pre-refund count. Bounded
  at one unit and it fails toward the business rather than against the user — the alternative,
  letting the smaller count win, would make a stale device able to hand out free messages.

**The nudge (§8 placement D).** `CoachChatViewModel.allowanceNudge` returns a
`CoachChatAllowanceNudge` value struct — finished string, `used`, `limit` — rendered as
`OnyxCapNudge` directly above the input bar, so it is on screen *before* the send that hits the
wall. It appears on the last free message ("1 of 5 Coach messages left this month") and *stays*
once the allowance is spent, which is exactly what removes the surprise from the gate. It is
computed, not stored: the gate reads the `@Observable` entitlement provider inside it, so a
purchase or a lapse removes or restores the hint with no reload, and the count refreshes because
sending changes `messages`, which the same body already reads.

**A blocked send keeps the user's text.** `startTurn(with:)` clears `inputText` only after a turn
actually starts, so hitting the gate does not also delete what they typed.

**The refund closure captures the gate, never `self`.** The dominant cancellation path is the
cover's `onDismiss` calling `CoachChatService.shared.cancel()` — which runs *after* the chat view
and its `@State`-owned ViewModel are gone. A `[weak self]` capture would be nil exactly then, and
the unit for a cancelled-with-no-answer turn would be silently kept. The gate holds only
app-lifetime collaborators, so capturing it strongly neither leaks nor cycles.

**The paywall is raised at most once per opening.** `onAppear` fires again every time the pushed
AI-coach settings screen is popped back to the chat, and returning from settings is not the
"opened Coach Chat at 0 remaining" intent §8 C gates on. The ViewModel is `@State` inside the
cover's content, so the once-flag resets the next time the chat is opened.

**Two paywall hosts, and why.** §5a predicted this: a sheet raised from the root cannot reach the
screen while a full-screen cover is up, and `.coachChat` is by definition raised from *inside* the
coach-chat cover. Left alone, the paywall would have appeared only after the user left the chat —
a paywall arriving out of nowhere. So the cover hosts its own `.sheet(item:)` reading the **same**
`pendingPlacement`, exactly as §5a's follow-up sanctioned, and the root host is suppressed while
`showingCoachChat` is true so the two never both attempt a presentation. **The presenter is
unchanged** — one source of truth, two hosts, and whichever shows the placement clears it for the
other. Second-order effect, accepted: while the chat cover is up, *any* placement raised from
elsewhere now surfaces inside the chat, where previously it could not appear at all. Nothing but
the chat raises one from in there today, and the §8 A/B one-shots are recorded on `didPresent`
either way.

**With the kill switch off nothing changes** — no nudge, no meter, no paywall, and `send` behaves
exactly as it did before monetization — which is its own test (`killSwitchOffBehavesAsBefore`)
rather than an inspection.

**Lapse behaviour.** A lapsed subscriber returns to five messages a month with their chat history
fully readable. Nothing was counted while they were Pro, so the taster starts whole rather than
retroactively spent (`lapseReturnsToTheTaster`).

Strings: `ai_coach.chat.allowance.nudge` and `ai_coach.chat.allowance.nudge.exhausted`, en + de.

**Deliberately not built:** no Pro badge on the send button or the chat entry point. The nudge
already removes the surprise, and a badge on the composer would read as an upsell in the middle of
a conversation.

### P4 and P5 — the recap and deep-dive monthly tasters

Ticket 09 adds no new machinery: it instantiates `AICoachAllowanceGate` twice more via
`AppDependencies.makeAICoachAllowanceGate(for:)` and threads the ticket through the two existing
generation pipelines. What is genuinely new is where a *fresh* generation begins on each screen,
and what happens when it may not.

**A cap of one changes the UX problem.** Five chat messages can be metered invisibly: the user
sends four before anything is at stake. One recap a month cannot. At a cap of one, the first
generation is also the last — so §8 D's nudge is on screen from the very first render
(`nudgeIsVisibleBeforeTheOnlyFreeGeneration`), and, on the recap, generation stopped being
automatic.

**The recap does not generate on arrival for a metered user.** `PeriodRecapState` gained two cases,
both unreachable for a Pro user and while the kill switch is off:

- `.offer(HeadlineMetrics?)` — allowance left. The screen shows the stat strip (the user's own
  numbers, never gated), the nudge, and a "Generate recap" button. `generateNow(modelContext:)` is
  the **only** path that spends P4's single unit.
- `.gated(HeadlineMetrics?)` — nothing left. The paywall is raised on arrival (§8 C's "open the
  surface at 0 remaining"), and what stays behind it is the stat strip plus an unlock CTA, so the
  screen is not a dead end once the sheet is dismissed.

Both render `PeriodRecapAllowanceCard` (`Presentation/Views/AICoach/PeriodRecap/`) — one
presentational view with an `offer`/`gated` mode, taking a finished `AIAllowanceNudge` and a
callback and seeing neither the entitlement nor the presenter. One card for both states is
deliberate: the gate should read as the continuation of the offer, not as a different screen.

This is the ticket's "a proactive prompt cannot consume an allowance without the user choosing to
generate", implemented structurally rather than by special-casing the prompt. The proactive
month-boundary card is a `NavigationLink` into this screen, and `load`/`setRange` are navigation,
not intent: **tapping a range chip must not be able to spend the month's recap on a period the user
was only browsing.** A per-entry-point flag would have left the chip hole open.

An unmetered user is unaffected — `admitGeneration` returns a non-consuming ticket and streams
immediately, which is what `killSwitchOffGeneratesOnOpen` and `proUserGeneratesOnOpen` assert
against the *state* (`.unavailable`, never `.offer`).

**The deep-dive was already explicit**, so it needed no new state: `CoachDeepDiveButton` is the
intent. `generate`/`regenerate` now return `Bool`, and on `false` the ViewModel leaves its state
alone so the button stays put instead of collapsing into an empty surface behind the paywall — the
same "don't take away what the user was looking at" rule as the chat keeping typed text.

**What consumes, and what never does.**

- The unit is a **fresh generation**, reserved at the start and refunded on every exit that did not
  produce a narrative: an unavailable model, a preference switched off mid-flight, too little data
  (`insufficientDataRefunds`), a guardrail violation, an error, a cancellation, and a stream
  superseded by a range switch. Both pipelines thread the ticket into `run(…)` and hold it in a
  `defer` that refunds unless the stream reports success — an exit path added later cannot silently
  forget to refund.
- **Opening a cached result consumes nothing and is never blocked, in any entitlement state**
  (§7 Rule 4). The gate sits *after* the cache lookup in both pipelines, so a hit returns before the
  meter is reached. `ExerciseDeepDiveViewModel.checkCache` never touches the gate at all.
- **`regenerate` asks the gate before invalidating the cache.** Getting this order wrong is the one
  way this ticket could have destroyed something the user already paid an allowance for: a refused
  regeneration would have deleted the cached narrative on its way to the paywall.
  `refusedRegenerationKeepsTheCachedNarrative` pins the ordering.
- The start task captures the **gate** strongly alongside `[weak self]`, for the reason §5e already
  records for the chat: if the `@State`-owned ViewModel is gone before the task body runs, the
  reserved unit still has to find its way back.

**Availability first, as everywhere.** A device that cannot run Apple Intelligence sees the existing
unavailable state and is never metered or paywalled — the gate's own ordering, asserted per surface
(`unavailableDeviceIsNeverPaywalled`).

**The nudge is now shared.** `AIAllowanceNudge` (`Presentation/ViewModels/Pro/`) replaces ticket
08's `CoachChatAllowanceNudge`: one value struct — finished string, `used`, `limit` — built from
`AIAllowancePolicy.NudgeState` with per-surface copy passed in. The copy strings are `@autoclosure`
because the initializer is called from a computed property a view `body` reads, and in the common
case (no hint due) no bundle lookup should happen at all. It renders as `OnyxCapNudge`: above the
recap's Generate button, above the deep-dive's "Ask the Coach" button, and (unchanged) above the
chat's input bar.

**Two rendering fixes the review caught, worth not re-introducing.** `admitGeneration` takes the
headline metrics step 3 already computed rather than recomputing them — `buildHeadlineMetrics` is a
`FetchDescriptor<WorkoutSession>` plus a relationship walk on the main actor, and every free-tier
open would otherwise have paid for it twice over a period as wide as "This Year". And
`PeriodRange.label(locale:)` no longer builds a `DateFormatter`: the offer card reads it from a
body, and `Domain/` is isolation-agnostic so there is no actor to cache a formatter on. It uses
`Date.FormatStyle` — a `Sendable` value that allocates no formatter and still honours the
locale it is handed, which is load-bearing because `PeriodRecapAggregator` calls the same function
with an explicit locale to build the model's prompt. (A hardcoded English/German month table was
written first and reverted: it would have silently degraded every other locale, prompt included.)

**Testing.** `RecapDeepDiveAllowanceTests` covers the gate for both surfaces (one free, then the
placement; independence of all three counters; Pro/lifetime/Founder unmetered; lapse; unavailable
device; kill switch off; refund). `ExerciseDeepDiveAllowanceTests` and `PeriodRecapAllowanceTests`
drive the real ViewModels over an in-memory `ModelContainer` with fake service/cache/preferences —
which is possible only because both already took protocol-shaped dependencies (docs/ai-coach.md).
The fake `AICoachServicing` returns `nil` from every stream: that is production's "surface disabled
or device not eligible" answer and the only generation outcome a test process can produce, since
`LanguageModelSession.ResponseStream` cannot be constructed without the on-device model. Both
ViewModels expose a `#if DEBUG waitForCurrentGeneration()` hook so a test can await the
fire-and-forget task instead of polling `Task.yield()`.

Strings: `ai_coach.period_recap.allowance.nudge{,.exhausted}`, `ai_coach.period_recap.offer.{title,
subtitle,cta}` and `ai_coach.deep_dive.allowance.nudge{,.exhausted}`, en + de. The `.gated` card
reuses `PaywallPlacement.periodRecap.headlineKey` and `pro.lock.cta`.

**Deliberately not built:** no `OnyxProLockOverlay` blur on either surface. The lock kit's blur
exists to show the user their *own data* behind glass (§3 Rule 2); an ungenerated narrative is not
data the user has — there is nothing to blur, and faking one would be inventing content. The stat
strip stays fully readable instead, which is the real data on that screen.

## 5f. P9 — fixed-weekday schedules

A routine is planned either on a rolling cadence (*every N days*) or on a fixed weekly split
(*Mon · Wed · Fri*) — see `docs/workout-planning.md`. **The cadence is free; the weekly split is
Pro.** That is the whole of P9.

**§4.2a claimed more than exists, and was corrected.** It described P9 as "fixed-weekday
schedules, multiple routines per day, plan preview". Only the first is a gateable surface. The
*plan preview* ("next 3 sessions") is shown for both schedule types and is not a separate
capability — gating it would only make the free schedule sheet worse for no conversion gain.
*Multiple routines per day* is not a feature at all: every routine carries its own independent
schedule, so two routines already fall on the same day and there is nothing to gate. If the launch
tier needs more weight, that is an argument for building something from §4.2b, not for inventing a
gate here.

**`ScheduleGatingPolicy` answers exactly one question**, `isScheduleTypeLocked(_:isPro:isGatingEnabled:)`,
and it takes the **requested** type rather than the stored one. That is what collapses all three
routes into weekday shape — creating a plan that way, switching an interval plan into one, editing
an existing weekday plan's days — into a single check.

**The planner never asks.** `WorkoutPlanningService` computes occurrences for whatever schedule it
is handed and does not import or reference the policy, the entitlement or the paywall. This is the
mechanism behind §7's Rule 4 rather than a promise about it: a weekday plan built while subscribed
keeps driving the planned week, the weekly goal, the day-strip markers and the up-next ordering
forever, because there is no place in that path where an entitlement could be consulted.
`lapsedWeekdayPlanStillPlansTheWeek` pins it.

**One gate, three intent points.** `RoutinesViewModel.requestWeekdaySchedule()` is asked when the
user picks the weekday mode and when they touch a weekday chip; `setSchedule(...)` re-checks and
returns `false` at save, so no call site can bypass the gate by writing the schedule directly. Both
refuse **before** any mutation, which is what makes "a refused edit leaves the existing schedule
intact" true by construction (`refusedEditLeavesExistingPlanIntact`). Moving *out* of weekday shape
back to the cadence is allowed — the gate is on the Pro shape, not on the routine. **Removing a
plan is never gated**: Rule 4 constrains what a user may build, and removing only gives capability
back.

**Why the schedule sheet closes itself on a refusal.** The paywall is hosted at the app root, and
SwiftUI supports one presentation per context: a root `.sheet` raised while `SchedulePlanningSheet`
is up is **queued, not dropped** — SwiftUI logs *"only presenting a single sheet is supported. The
next sheet will be presented when the currently presented sheet gets dismissed"* and presents it
the moment the inner sheet goes away. Leaving the sheet open would therefore mean a paywall
arriving out of nowhere later. Dismissing on refusal is also exactly what Apple's HIG prescribes —
["If something people do within a sheet results in another sheet appearing, close the first sheet
before displaying the new one"](https://developer.apple.com/design/human-interface-guidelines/sheets) —
so the dismiss-and-raise-together action gets the correct sequencing for free, with no `onDismiss`
timing code. Nothing is lost by closing: a refusal writes nothing.

**Deliberately *not* a second paywall host.** §5e added one inside the coach-chat cover because a
full-screen cover blocks the root host for as long as the user stays in the chat. A sheet does not:
it is dismissed by the same action that raises the paywall, so the deferral lasts one animation.
Adding a host here would put two `.sheet` modifiers on the same `pendingPlacement` in one
presentation context — the configuration §5a's follow-up warns about, whose behaviour depends on
which modifier SwiftUI attaches first. (Researched 2026-08-15 against Apple's `sheet(item:)`,
`modal-presentations` and HIG *Sheets* docs; the ancestor/descendant queuing path itself is
described only by the console message, not by Apple prose, so the dismiss→auto-present handoff is
listed as unverified-on-device in §7.)

**Reminders do not exist yet, and that is why nothing needs to be done to them.** Planned-routine
notifications are deferred to phase 2 of `docs/workout-planning.md` — the app schedules only rest
timers. The acceptance criterion "notification scheduling contains no entitlement checks" is
therefore satisfied by absence, and it stays a **binding constraint on the phase-2 work**: when
per-weekday reminders are built, `WorkoutReminderScheduling` must fire an existing weekday plan's
reminders regardless of entitlement, exactly as the planner does.

**The watch was not touched and could not be.** Schedules are not part of the watch-sync DTO — the
watch has no plan data at all — so §9's "the watch never learns about entitlements" holds without a
line of watch code. The one schedule-derived thing it does receive is the ordering of the routine
payload (up-next first), which is computed from the same unaware planner.

**With the kill switch off, planning behaves exactly as it did before monetization** — no badge, no
refusal, no paywall (`killSwitchOffBehavesAsBefore`).

**No new strings.** The gate reuses `paywall.headline.weekday_schedule` (already localized with the
rest of the placements in ticket 04) and `OnyxProBadge`'s existing copy.

**Two bugs this gate produced while being built**, both worth knowing because neither is specific to
P9:

- `previewWeekday(_:)` / `previewDay(_:)` allocated a `DateFormatter` **per preview cell**, from a
  computed property that `body` reads — main-thread rule 2, in the exact shape the rule describes.
  Fixed by hoisting to two `private static let` formatters. A weekday picker is a bounded set, so it
  never showed up as a hang; it was caught by review, not by a symptom.
- Tapping the **already-selected** weekday segment raised a paywall. The gate asked "is this the
  locked mode?" without asking "is this a change?", so a free user re-tapping their current selection
  was charged a placement. Fixed with `guard target != mode`. Any gate attached to a segmented
  control needs the same guard — the no-op tap is easy to miss because it never occurs while testing
  the feature itself, only while poking at it.

## 5g. Placements A and B — the two paywalls that fire on their own

Everything in §5c–§5f is a **contextual gate**: the user taps something, it is refused, a paywall
appears. §8's rows A and B are the opposite — nothing is refused and the user asked for nothing.
The app decides the moment has arrived.

- **A — soft, after a routine is created.** Dismissible in one tap. Once, ever.
- **B — the value moment.** After the third completed workout **or** the first automatic
  progressive-overload suggestion, whichever lands first. It shows what the user has accumulated —
  "You've logged 7 workouts, 143 sets and 24,313 kg of volume" — and then the offer. Once, ever.

§8 calls B the highest-value placement in the app: a paywall after a measurable value moment sees
roughly 2.1× the trial-start rate of an immediate hard paywall. **The endowed figures are the whole
mechanism**, which makes their correctness a product requirement rather than a nicety — a
placeholder or an off-by-one total does more damage than showing nothing.

There is no onboarding flow in this app, so A hooks the routine-creation event rather than an
onboarding host. That is how §8 words the trigger anyway.

### Armed, presented, and why they are different facts

`PaywallPresenter` already records what has been **shown** — once ever, written on `didPresent`
(§5a). What it cannot record is a condition that became **true** at a moment when nothing may be
shown. Rule 3 is exactly that moment, and §8 B is exactly the trigger most likely to arrive there:
the third workout completes *inside* a workout, and an overload suggestion appears mid-set. The
presenter drops such a request — `show(_:)` returns without setting anything — and because the
once-ever record is written on presentation, nothing is spent. But without a second record the
condition itself would be forgotten and placement B would never fire again for that user.

So `ProactivePaywallTracking` / `ProactivePaywallTriggerStore` holds one durable flag per trigger:
**armed**. Arming is one-way and nothing ever disarms it (outside the debug reset); the presenter's
once-ever record is what ends a trigger's life. That pair — armed here, presented there — is the
whole mechanism behind "a suppressed trigger is deferred, not consumed", and
`deferredTriggerSurvivesRelaunch` pins it across a process boundary.

Storage is plain `UserDefaults.standard` under `pro.trigger.<id>`, matching the presenter's
`pro.paywallPresented.<id>` rather than the allowance store's App Group + iCloud KVS pair. Not the
App Group suite: neither the widget nor the watch can act on a paywall trigger, and per §4.1 the
watch never learns about entitlements. Not mirrored to iCloud: mirroring one half of the
armed/presented pair would let a reinstalled device believe a placement is still owed after it was
already shown elsewhere.

### Where the decision lives

`ProactivePaywallCoordinator` (`Presentation/ViewModels/Pro/`) — the same shape as
`AICoachAllowanceGate` (§5e) and for the same testability reason: the ViewModels that report the
events are untestable in isolation (HealthKit, a live `ModelContext`), while every acceptance
criterion here is about *what is armed and what is raised*. It takes no repository and no service.

**It re-implements none of the four eligibility rules.** The kill switch, the entitlement, Rule 3
and the once-ever cap are still enforced once, in `PaywallPresenter`. What the coordinator adds is
a *guard on the work*: it asks the same three cheap questions before arming or fetching, because
otherwise every workout completion of every user — including all of them while the kill switch is
off — would run an unbounded aggregation over their whole history to feed a paywall that can never
appear. `killSwitchOffFiresNothing` asserts the read count is zero, not just that no paywall
appeared.

It also asks `ActiveWorkoutReporting` before raising, for the same reason and not as a second copy
of Rule 3: an overload suggestion appearing between two sets would otherwise trigger a
whole-history aggregation inside the one part of the app where nothing may compete for resources.
Arming is *not* guarded that way — arming mid-workout is precisely the case the deferral exists for.

**One placement per safe moment.** `flushOrder` puts `.valueMoment` first. Raising both back to
back would silently drop the first: the presenter replaces a request that has not yet reached the
screen (§5a). Whatever is not raised stays armed for the next safe moment
(`onlyOnePlacementPerSafeMoment`).

### The event hooks, and where each one sits

| Event | Reported by | Effect |
|---|---|---|
| A routine template was saved | `RoutinesViewModel.addRoutine` / `createRoutine` / `duplicateRoutine` | Arms A, then raises |
| A workout was completed | `WorkoutViewModel.completeWorkout`, **after** `currentSession = nil` | Counts completed workouts; arms B at the threshold; raises |
| The mid-workout overload prompt changed | `ActiveWorkoutView`'s prompt bar → `WorkoutViewModel.overloadPromptDidAppear(_:)` | Arms B **if the prompt is a `.suggestion`** (always suppressed here — it is inside a session) |
| The completion screen appeared | `SaveWorkoutView`'s `.task` → `WorkoutViewModel.completionOverloadSuggestionsDidAppear()` | Arms B **if the "Ready for More Weight" list is non-empty** (likewise suppressed) |
| A workout was discarded | `WorkoutViewModel.cancelWorkout`, after `currentSession = nil` | Raises only; a thrown-away workout earns nothing |

The completion hook sits **after** the session is cleared, which is what makes Rule 3 stop
suppressing — that ordering *is* "the safe moment after the session ends".

**The screens report what appeared; the ViewModel decides what it means.** That inversion is
deliberate — deciding which appearances count is trigger policy, and Hard rule 3 keeps it out of
views. `WorkoutViewModel.overloadPromptDidAppear(_:)` takes the `OverloadPrompt?` and applies the
`case .suggestion` test itself, because the bar's other state is an `.applied` confirmation —
feedback on the user's own action rather than a suggestion the app made.
`completionOverloadSuggestionsDidAppear()` applies the non-empty test against
`overloadSuggestionExercises`. Both funnel into one private `reportOverloadSuggestionShown()`, so
the two surfaces cannot drift apart. Neither view reaches into the composition root.

The hooks themselves: the prompt bar uses **`.onChange(of: prompt, initial: true)`** rather than
`.onAppear` — `initial: true` covers the first appearance, and the change form also catches a
hand-off from a confirmation to the next exercise's suggestion, which leaves that container
mounted. The completion screen reports from its **existing `.task`**, before the first `await`,
deliberately *not* from an `.onAppear` on the `Section`: a modifier attached to a `Section` inside a
`Form` is not a reliable appearance hook. Both are idempotent — arming twice is a no-op — so a
container that unmounts and remounts costs nothing.

**A is armed by the first creation event this install observes, not by "the user's first routine".**
§8 words the trigger as the creation event, and the narrower `count == 1` reading would leave A
permanently dead for everyone who already had routines when gating flipped on — which, since the
switch shipped off until ticket 15, was the entire existing user base at the flip. Duplication counts as creation
here exactly as it does for the cap (§5c).

**Watch-originated workouts do not fire B.** The watch path never touches `WorkoutViewModel`
(`WatchWorkoutIngestionService` writes history on an isolated context), so a workout recorded on the
watch and synced over increments the count but raises nothing until the next iPhone-side completion
— at which point the count is read fresh and the threshold is met. This is the correct outcome for
§8's prohibition ("no paywall on the watch app") rather than a gap: the paywall must appear on the
phone, at a phone-side safe moment.

### The figures

`LifetimeTrainingTotals` (workout count, completed sets, volume in kg) comes from
`LifetimeTrainingTotalsProviding` — a **second, narrow read boundary conformed to by the same
`SwiftDataHistorySnapshotProvider`**. A separate protocol rather than a sixth requirement on
`HistorySnapshotProviding` (this is a different question with a different consumer, and the
existing five requirements each exist for one screen), but the same concrete type, so there is still
exactly one `@ModelActor` and one `ModelContext` warming the completed-session graph — the
constraint that argued against a second boundary in the first place.

**The boundary has two methods, and the split is the load-bearing part.**
`fetchCompletedWorkoutCount()` is a `fetchCount` over the completed-session predicate: it
materializes nothing and faults no relationship. `fetchLifetimeTotals()` is the aggregation. The
trigger question — "have three workouts happened?" — is asked after **every** completed workout,
including the first two, which provably cannot meet the threshold; answering it with the
aggregation put a whole-history walk on the shared History actor *in front of the History tab's own
post-workout refetch*, which `completeWorkout()` invalidates a few lines before reporting the
event. The aggregation now runs exactly once, at the moment B is raised.
`belowThresholdCostsOnlyACount` pins that, and `completedWorkoutCountAgreesWithTheAggregation`
pins that the cheap read is not merely cheaper but returns the same number. The two reads are
milliseconds apart and can only disagree if another workout lands in between (watch sync), which
makes the shown figures more current, never wrong.

- `@concurrent` on the concrete method is load-bearing, like the five beside it. This is the widest
  read in the app: no date window at all. `lifetimeTotalsKeepMainActorResponsive` joins the shared
  tripwire suite in `SwiftDataHistorySnapshotStoreTests` (`docs/swift6-concurrency.md` §1).
- The aggregation is `LifetimeTotalsAggregator`, a pure function over `[WorkoutSession]` like
  `FortschrittAggregator`. It sums `WorkoutSession.aggregates` — the one place the volume formula
  lives — so the paywall's numbers are derived from exactly the graph the History tab renders, and
  **completed** sets, not planned ones.
- **The count that decides the trigger and the numbers shown are the same read**, so they cannot
  disagree.
- A completed workout **invalidates** the cached read (`completionInvalidatesCachedFigures`).
  Without that, the read taken at workout two would be what the paywall showed at workout three.
- A failed read **defers** rather than showing zeroes or placeholders: B stays armed and is retried
  at the next safe moment (`failedReadDefersTheValueMoment`).

The figures are rendered by `ProPaywallView`, which takes them as an optional value struct and
ignores them for every placement other than `.valueMoment`. The number formatter is a `static let`
— main-thread rule 2 applies to every view body, not only to the ones inside a list.

**They are drawn by the app, above the RevenueCat paywall, and that is deliberate.** A
dashboard-authored paywall cannot know the user's own totals: RevenueCat's paywall variables cover
prices and periods, not "you have logged 148 sets". Dropping the line would have quietly deleted the
one thing that distinguishes B from every other placement — §8 B *is* the endowed-progress moment —
so the strip stays in code and the offer below it stays in the dashboard. The consequence to know
when designing B's paywall: leave room at the top, because one line of app-drawn text sits above it.

Strings: `paywall.value_moment.figures`, en + de.

### With the kill switch off, nothing happens at all

No trigger arms, no placement raises, and the history read never runs — asserted rather than
inspected (`killSwitchOffFiresNothing`). Because nothing is armed while the switch is off, flipping
it on in ticket 15 does not retroactively fire A or B for anyone: the next routine creation and the
next workout completion are what arm them.

**Deliberately not built:** no launch-time flush. §8 forbids launch-time paywalls outright, so a
trigger armed inside a workout waits for the next session end rather than for the next app start.
The consequence is recorded as a follow-up in §7.

## 5h. The Founder celebration

The one screen in the Pro surface that sells nothing. A user who installed before the cutoff sees,
once, that they are a Founder and that Pro is theirs free, forever — and they see it **before**
anything that could read as bad news.

**Why it is the most important screen here.** The shipped App Store listing promises the app is
"completely subscription-free" / "Kein Konto, kein Abo". Every existing user downloaded on that
promise, so introducing a paywall is the most dangerous moment in the app's life. This screen is
what turns it around, and it reaches exactly the cohort that writes reviews. Ordering is the whole
point: a Founder who trips over a Pro badge first and only later learns they were never going to be
charged has already had the bad experience. So the tone is a thank-you, not a marketing beat — no
offer, no "consider supporting us", no path into a paywall. It says what happened and gets out of
the way.

### Four rules, one place

`FounderCelebrationCoordinator` (`Presentation/ViewModels/Pro/`) is the counterpart to
`PaywallPresenter` for the screen that is not a paywall — same shape (an observable flag the app
root renders from, every rule in one place), opposite content.

1. **The kill switch.** With `ProGating.isEnabled` off, nothing in the app is gated, so there is
   nothing to reassure anyone about — and showing the screen early would *spend* it, leaving the
   release that actually turns gating on with nobody left to thank. This is the rule that makes the
   screen arrive on the launch of the build that flips the switch (ticket 15), which is what the
   ticket asks for. `killSwitchOffShowsNothing` asserts both halves: nothing shows, and nothing is
   written down, so a coordinator built with gating on afterwards still owes it.
2. **The entitlement source — `.founder` and nothing else.** Free, subscription and lifetime users
   see nothing. **The undecided case falls out of the entitlement rather than needing its own
   branch**: `FounderStatusService` leaves the decision absent on a first-launch-offline or an
   unverified transaction (§3a), so the provider reports `.free` and re-resolves next launch. The
   screen therefore never appears in a provisional, retractable form — telling someone they are a
   Founder and taking it back is worse than telling them a launch late.
3. **Rule 3.** Nothing about Pro inside an active workout session (§8). **Deferred, not dropped**:
   the record is written on dismissal, so a suppressed screen is still owed and the next foreground
   or the next launch raises it.
4. **Once, ever**, via `FounderCelebrationTracking` / `FounderCelebrationStore` — plain
   `UserDefaults.standard` under `pro.founderCelebrationShown`, matching `PaywallPresenter`'s
   once-ever record rather than the allowance store's App Group + iCloud KVS pair. Not the App
   Group suite (neither the widget nor the watch shows this screen) and not mirrored to iCloud: the
   worst outcome of not mirroring is thanking someone twice after a reinstall, while mirroring it
   would risk a Founder who never sees it because another device recorded it while they were not
   looking.

**The once-ever is spent on dismissal, not on the raise** — the same distinction §5a draws between
a raised and a presented placement, and for the same reason: a screen the user never actually got
(the app was killed while it was up) is still owed. `celebrationWasDismissed()` guards on
`isPresenting`, so a binding pushed to `false` while nothing is presenting records nothing.

**`hasCelebrated` is mirrored into the coordinator's observable storage**, seeded from the store at
init. Same fix as the presenter's in-memory fired set (§5a): `UserDefaults` is not observable, so
the debug row rendering "already shown" would otherwise only update on the next launch. The DEBUG
reset consequently lives on the **coordinator**, not the store — a reset that cleared only the
stored flag would leave the mirror saying "already shown" — which is also why
`FounderCelebrationTracking` declares `resetCelebration()` inside `#if DEBUG` instead of getting a
second `…Debugging` protocol the way `PaywallPresenting` does.

### When it is asked, and why not by observation

`presentIfDue()` is called at two deterministic moments, both in `GymStreakApp`:

- **Right after the launch `refresh()`** that resolves the grant. The entitlement is fully settled
  when `refresh()` returns, so this needs no observation and no ordering luck.
- **On every `scenePhase == .active`.** This is what gives a screen Rule 3 suppressed its next safe
  moment without waiting for a relaunch.

Both are idempotent and both are a cheap no-op for everyone who is not an unthanked Founder (two
boolean reads before the entitlement is even consulted). Deliberately **not** wired to a workout-end
hook the way §5g's triggers are: that would mean threading the coordinator into `WorkoutViewModel`
for a case that needs the app to launch straight into a restored session, and the foreground check
already covers it.

### The screen

`FounderCelebrationView` (`Presentation/Views/Pro/`) is presentational to the point of holding no
dependency at all: it reports its dismissal through `@Environment(\.dismiss)`, and the host's
binding is what spends the record. Hero mark, eyebrow, headline, one paragraph, three
"what's included" rows, a thank-you line, and one button that closes it. **No purchase call to
action, by construction** — there is nothing on it to route anywhere.

- **The three rows are deliberately not about the AI coach.** The coach needs
  Apple-Intelligence-capable hardware, and telling a user on an older iPhone that an unavailable
  feature is now theirs turns a thank-you into a disappointment — the same position §4.3 takes for
  the paywall. They are unlimited routines, full analytics, and everything Pro adds later.
- It **scrolls with a pinned CTA** (`ScrollView` + `safeAreaInset`), for the reason
  `AICoachOptInView` had to be rebuilt: a fixed stack resolves German-length overflow by silently
  truncating the text. Typography is the `.onyx*` scale rather than fixed point sizes, so it grows
  with Dynamic Type.
- Strings are `founder.celebration.*`, en + de, in the informal register of the German listing.

### Hosting, and the one ordering it changes

`ContentViewInternal` hosts it as a `.fullScreenCover` bound to the coordinator's `isPresenting`,
above the tabs and above both paywall hosts. **The AI-coach opt-in cover is suppressed while it is
up**: SwiftUI presents one cover per context, and this is the ordering that matters. If the opt-in
happened to be on screen already (it can only be on the one launch where both are due), its binding
goes false, it closes, the thank-you appears, and the opt-in comes back on its own afterwards.

**The one rough edge, and why it is left alone.** Dismissing the thank-you clears `isPresenting`
and un-suppresses the opt-in in the *same* state change, so the opt-in's presentation can be
attempted while the Founder cover's dismissal transition is still running — the "present while a
presentation is in progress" swallow. It is left as a derived binding rather than sequenced through
`onDismiss` because the failure mode is self-healing and lands on the right side: the opt-in
binding is `.constant(…)` over **persistent** preferences, not a one-shot, so a swallowed
presentation simply re-presents at the next body evaluation or the next launch, while the screen
that must not be lost — the thank-you, whose record is only written on dismissal — is the one that
wins. Worth an eyeball during ticket 15's launch pass all the same (§7).

Nothing else needed suppressing: a Founder is `isPro`, so no gate blocks, no nudge computes, no
badge renders and `PaywallPresenter` refuses every placement for them anyway (§5a rule 3). The
acceptance criterion "it appears before any gate, badge, nudge or paywall placement is reachable" is
therefore satisfied twice over — by the cover, and by the entitlement itself.

**The watch was not touched**, per §4.1: the whole watch app is free and has never known about
entitlements.

## 5i. The Settings subscription section

One section at the top of the Settings tab that answers a single question: *what plan am I on, and
where did it come from?* `SubscriptionSettingsSectionView` renders it,
`SubscriptionStatusSummary` decides what it says.

**Status, plus one row.** Restore, manage-subscription, cancellation surveys and refund requests are
not hand-built here — `CustomerCenterSettingsRow` opens `RevenueCatUI`'s `CustomerCenterView`, which
handles all four (§5j). There is still **no purchase affordance anywhere on this screen, for
anyone** — which is how the acceptance criterion "a Founder is offered no purchase" is met: not by a
special case for Founders, but because the section sells nothing to anybody. The paywall is reached
from a gate, never from Settings.

**The kill switch hides the section entirely** rather than softening its copy. While
`ProGating.isEnabled` is off the app has no paid tier, and a Settings section announcing "Free" — or
thanking a Founder for an entitlement nothing is yet using — is precisely the visible contradiction
`monetization-strategy.md` §7 forbids: the paywall and the listing copy ship in the same release,
and so does this. The release that flips the switch is the release this section first appears in.
`SubscriptionStatusSummary.init?` returns `nil` for that case, so the rule is one testable place
rather than an `if` in a view body, and `isGatingEnabled` is injected for the same reason
`PaywallPresenter` and `FounderCelebrationCoordinator` inject it.

**Four plans, not three.** The section reports Founder / Pro / Free as the ticket asks, but
`.subscription` and `.lifetime` keep separate copy: telling someone who paid once that they hold a
renewing subscription is a factual error about their own money, and distinguishing the two is the
entire reason `ProEntitlementState` carries its source (§2). Founder copy names the grant — "you
installed Gym Streak before Pro existed… your access never expires" — and offers nothing to do.

`SubscriptionStatusSummary` carries **keys, not localized strings**, like
`PaywallPlacement.headlineKey`: the mapping stays assertable without a bundle, and the view does the
one thing views may do with copy — look it up. The view reads `entitlements.state` straight out of
`body`, which is what makes a purchase, a restore or a lapse rewrite the section with no refetch and
no relaunch; the read is free under the main-thread rules (no collection walk, no formatter, no
SwiftData relationship).

Strings: `settings.section.subscription` and `settings.subscription.<plan>.{title,detail,footer}`,
en + de.

**A consequence worth knowing:** a Founder who somehow also held a subscription reads as `.founder`
(§3b), so this section would show the grandfathered source rather than the paid one. Nothing in the
app can produce that pairing — a Founder is never shown a paywall.

## 5j. The RevenueCat paywall and the Customer Center

The two shipping purchase surfaces. Ticket 04 built the seam so this ticket would be a swap, and it
was: `PaywallPlaceholderView` was deleted, `ProPaywallView` took its place in the same two hosts,
and nothing else in the presentation chain changed — not `PaywallPresenter`, not `PaywallPlacement`,
not one of the nine gates.

### The paywall

`ProPaywallView` resolves a placement to an offering and renders `PaywallView(offering:)`.

**The ladder, and the rung that matters.** `PaywallOfferingSource` names it, and it is a value in
`Domain/` rather than three lines inside a view body because the failure rung is a product decision
that must stay assertable:

| Rung | When | What the user sees |
|---|---|---|
| `placement` | `offerings.currentOffering(forPlacement: <identifier>)` returned an offering | The paywall the dashboard authored for that placement |
| `defaultOffering` | it returned `nil`, but `offerings.current` exists | The default offering's paywall — per-placement copy is lost, the offer is not |
| `unavailable` | neither resolved (offline, or nothing configured at all) | The placement's headline, "couldn't be loaded", **Try again** and **Dismiss** |

**`unavailable` never unlocks the gated capability**, and that is the deliberate answer to "a gate
that blocks with no way to unlock is worse than one that lets the action through". Letting the
action through would make airplane mode a one-tap bypass of every gate in the app. What the user
loses instead is nothing they had: every gate in §5c–§5f is *additive* — a fourth routine, a wider
chart window, one more AI call — so a paywall that cannot load leaves the free tier exactly as it
was. The sheet says so and offers a retry; it is never empty.

**A behaviour of the SDK worth knowing before debugging a fallback.** An *unknown* placement
identifier does not return `nil` — RevenueCat serves the current offering for it, so
`PaywallOfferingSource.placement` is what a placement that was never created in the dashboard
produces too. Verified in the simulator on 2026-08-16: with no Placements configured at all,
`routine-cap` logged `resolved to placement` and the paywall rendered the `default` offering. The
`defaultOffering` rung therefore covers the narrower case of a placement *configured to serve
nothing*. The consequence: the resolution log line cannot prove a Placement exists — only the
dashboard can.

**Dismissal.** `.onRequestedDismissal` handles the close button. It does **not** fire for a
completed purchase — RevenueCat deliberately does not auto-dismiss on one and does not route it
through that hook (purchases-ios #3617, #3691), so assuming otherwise left the user looking at the
paywall they had just paid on. `.onPurchaseCompleted` therefore calls `dismiss()` itself (§3d).
The entitlement flips separately: `ProEntitlementProvider` is driven by `customerInfoStream` (§3b)
with a `refresh()` from this callback as belt and braces, so every gate in the app re-evaluates
without the paywall telling anyone anything.

**Restore is the exception**, and how it is judged matters. It has no dismissal hook, and a restore
that found nothing must not read as success — so `.onRestoreCompleted` dismisses only if the user is
now Pro. It asks the injected `ProEntitlementProviding` and **ignores the `CustomerInfo` the SDK
hands it**. Reading that directly would be a second answer to "is this user Pro", and a laxer one:
the gateway additionally refuses an entitlement whose response failed verification (§3b), so a
`.failed` payload would dismiss the paywall while the provider still reported `.none` — dropping the
user back onto a gate that still blocks, with the paywall gone.

**The once-ever fire is spent on the offer, not on the sheet** — see §5a's two-report split.
`onPaywallShown` fires from the resolution, only on the two rungs that produce a paywall, so a
placement A or B raised while offline is not burned on a sheet that showed nothing.

**Every eligibility rule still lives in the presenter** (§5a) — the kill switch, Rule 3's absolute
prohibition inside a workout, the entitlement, the frequency cap. `ProPaywallView` decides nothing:
it is only ever constructed by a host binding to `pendingPlacement`, so there is no path to it that
skips them. A Founder reads as Pro (§3b) and `present(_:)` returns before anything is raised, from
any placement, including the two proactive ones. The watch and the Live Activity have no paywall
surface at all and never link the SDK (§9.2).

**Not used: `.presentPaywallIfNeeded`.** The declarative, self-dismissing modifier looks like a fit
for the proactive placements A and B, but it decides *for itself* when to present, from the
entitlement alone. The app's rules are richer than that — Rule 3, the once-ever cap, the
raised-vs-presented distinction — and a second presentation path that does not consult
`PaywallPresenter` is exactly the hole §5a exists to close. Both hosts therefore use an explicit
sheet.

### The Customer Center

`CustomerCenterSettingsRow` presents `CustomerCenterView` through
`.presentCustomerCenter(isPresented:…)`, from a row in the Settings subscription section. It covers
restore, manage subscription, change plan, cancellation with its survey, and refund requests. All of
them are things App Review expects to exist and none is worth hand-building.

- **Restore has to work** (Guideline 3.1.1). Under an anonymous app user ID it works for
  auto-renewing subscriptions and non-consumables via the store receipt — which is the concrete
  reason the Lifetime SKU must be a **non-consumable**, recorded in §9.5 as a constraint that cannot
  be fixed in code afterwards.
- **The row is offered to everyone but a Founder** (`SubscriptionStatusSummary.showsCustomerCenter`).
  A free user who reinstalled reads as free until a restore succeeds, so the path cannot be
  conditioned on the app already believing they paid. A Founder is the one exclusion: the grant is
  local and never round-trips (§9.3), so they are not a RevenueCat customer at all and the Customer
  Center would open on empty purchase history and offer to restore a purchase that never existed.
  Their footer already says there is nothing to manage.
- **Every event is wired to a log line** — `CustomerCenterEvent`, subsystem `app.gymstreak.pro`,
  category `CustomerCenter`. The Customer Center is a screen this app does not draw and cannot
  inspect; without the log, "I cancelled and it still says Pro" has no evidence behind it. The event
  is a value with a `message`, so the mapping is assertable (`CustomerCenterEventTests`) and no
  RevenueCat type reaches `Presentation/ViewModels/`.

Strings: `settings.subscription.manage.{title,subtitle}`, `paywall.unavailable.body`,
`action.retry`, en + de. `paywall.placeholder.body` was removed with the placeholder view.

### What is verified, and what is not

Verified in the simulator against the Test Store on 2026-08-16: the P1 routine-cap gate raises the
sheet, the offering resolves, and a **real** `PaywallView` renders the three Test Store packages
with a close button, Purchase and Restore; the Test Store purchase dialog opens from it.

**Verified on a real device against the App Store sandbox on 2026-08-17** (ticket 15's launch pass),
which is what the simulator could not do — driving it from the CLI is unreliable past the first few
taps:

- **Completing a purchase.** The paywall dismisses itself on success and every gate is gone
  immediately, with no relaunch — which is the acceptance test that matters, because it is what §3d
  was written to fix.
- **Restore.** On a fresh install the entitlement comes back **without the user tapping Restore and
  without seeing a paywall at all**: RevenueCat resolves the anonymous app user ID's receipt at
  configure time, and Settings reports `real: subscription` straight away. Restore remains in the
  Customer Center for the case where it does not.
- **The Customer Center**, and the Settings subscription section it hangs off.

Dark mode, large Dynamic Type and de were walked on device on 2026-08-17 and hold — including the
Settings subscription section, whose footers are the longest copy on that screen. Note that the
paywall half of that is a property of the **dashboard-authored** content rather than of this code, so
it needs re-checking whenever a paywall is redesigned, without an app release being involved.

**Designing the paywalls is dashboard work, not code work** — that is what the placement indirection
bought. §9.1's placement table is the list of Placements. A designed paywall has been live since
2026-08-17, so the "No Paywall configured" developer template no longer renders; changing what a
paywall says needs no release.

**The loading and `unavailable` states cannot be previewed or unit-tested.** `ProPaywallView` calls
the SDK directly (§9.2), so there is no stub offering to inject and no seam to fake a failure at:
only `PaywallOfferingSource`'s ladder is asserted, not the view that walks it. The states are
reachable in the simulator — airplane mode produces `unavailable` — and that is the only way to see
them. Recorded here so nobody looks for the test that would have caught a broken retry.

**Verified on device 2026-08-17.** The repro is airplane mode **before** the first launch after
install, so no offering is ever fetched — anything less and the cached offering renders (below). The
state came up as designed: the placement's own headline, an honest message, retry and close, and the
gate still closed. The retry then resolved normally once online, which is the half that had no
evidence behind it. Note that "the retry showed a different paywall" is expected when the two
attempts are different placements — resolution is per-placement, and there is only one code path.

#### The chain is placement → offering → paywall, and the payload can go missing on its own

Four things must line up for a gate to show the paywall it was designed for, and **all of the
failures are silent in a Release build**. Two are dashboard configuration; the fourth is not
configuration at all and was the one actually hit on 2026-08-17.

| What is wrong | What the user gets | The log says |
|---|---|---|
| No **Placement** for that identifier | The project's **current** offering — a real paywall, but the wrong one, and §8 C's "name the capability" is lost | `resolved to default-offering-fallback` |
| No **paywall on the offering** served | RevenueCat's **generic default template** — app icon, packages, buy, restore. Buyable, none of the authored copy | `resolved to placement … paywall none` |
| Neither resolves | Our own `unavailable` state, honest, with a retry | `resolved to unavailable` |
| The paywall exists but its **payload never arrived** | The same generic default template as row 2 — indistinguishable on screen, entirely different cause | `resolved to placement … paywall declared-but-absent` |

```
Paywall coach-chat resolved to placement — offering gymstreak_sale, paywall declared-but-absent
```

#### Row 4: the payload and the offering travel separately

**Symptom.** The same placement shows the designed paywall when presented normally, and RevenueCat's
"No Paywall configured" template when reached through our `unavailable` retry — same offering, same
placement, dashboard correct. It looks exactly like a misconfiguration and is not one. Chasing it as
one cost a round of wrong advice; the sequence is what identifies it.

**Cause, from the SDK source (5.83.2).** `OfferingsManager` decodes offerings **without** paywall
components whenever remote config is active:

```swift
var shouldCreatePaywallComponents: Bool { self.remoteConfigManager?.isDisabled ?? true }
var offeringsResponseDecodingMode: OfferingsResponse.DecodingMode {
    self.shouldCreatePaywallComponents ? .withPaywallComponents : .withoutPaywallComponents
}
```

The renderable components come from a **separate `/v1/config` request** made at SDK start-up. Launch
offline and that request fails. Come back online and tap retry: the *offerings* fetch now succeeds —
but by design it carries no components, and nothing re-issues the config request. The offering
arrives with the backend's marker that a paywall exists and no payload behind it. `PaywallView`
finds `internalPaywallComponents == nil`, falls back to `validatedPaywall`, finds no v1 data either
(the paywall is v2), and draws its default template. The SDK names this state internally —
`hasPaywallComponents && internalPaywallComponents == nil` — in a helper that repairs a *related*
case, but not this one.

**We cannot fix it by trying harder.** `offerings(fetchPolicy:)` is `internal` and there is no
public API to refresh the config, so the retry button has no stronger move available. The state is
session-scoped: relaunching while online loads the config and the designed paywall returns.

**Exposure is narrow but real**: launch offline, come online *without* relaunching, hit a gate. The
paywall still functions — correct products, correct prices, purchase works — it is simply the
generic template rather than the authored one.

**Decided 2026-08-17: leave it.** The alternative considered and rejected was to keep our own
`unavailable` screen whenever the payload is absent, so the generic template is never seen. It was
rejected because it trades a working purchase surface for an error screen in the one situation where
the user has just demonstrated intent, and because the same suppression would then also hide row 2 —
a genuine dashboard fault — behind a message that reads as a network problem. To restore that
behaviour, gate `phase = .ready` on `paywallPayloadState(of:) == "present"` in `ProPaywallView`.

**Distinguishing it is the whole point of the three-state log field**
(`ProPaywallView.paywallPayloadState`). `none` is a dashboard problem; `declared-but-absent` is this
one and needs no dashboard change at all; `present` alongside a generic template would be something
new. Without that field the two causes log identically, which is exactly how this was misdiagnosed
the first time.

#### Attaching a paywall to an offering

Not the fix for row 4 — kept because row 2 is a real failure mode and this is how it gets repaired
(dashboard steps verified against RevenueCat's docs 2026-08-17; no app release is involved, paywalls
are served dynamically):

1. **Paywalls** page → three-dot menu on an existing paywall → **Duplicate to this project**. The
   copy is created inactive.
2. Open it in the **Paywall Editor** and open the paywall's own **Settings** panel — that is where
   the **Offering** is chosen, alongside the initial step, default locale and any exit offer.
3. **Publish Paywall**. A paywall with no Offering attached cannot be published: RevenueCat's
   changelog (2025-03-25) allows unattached paywalls specifically for duplication, but "an Offering
   must still be attached to the Paywall to be able to publish it and serve it to customers".

The REST equivalent is `POST /v2/projects/{project_id}/paywalls` with `offering_id`, needing
`project_configuration:offerings:read_write`.

**Attached is not published, and published is not yet served** — drafts are never served, and
dashboard changes take minutes to propagate on top of the SDK's own offerings cache. Reinstall before
concluding a dashboard change did not work.

**One product question the mechanics hide.** An offering named for a *sale* implies its own pricing,
so a contextual gate pointed at it shows different prices than the same user sees elsewhere. Check
that is intended, and that §9.5's rule still holds: the trial is annual-only and contextual gates get
no trial at all, because at a gate the user already has intent and a trial only adds a cancellation
decision.


#### Offline is two different states, and only one of them is ours

Found on device 2026-08-17, and worth writing down because the symptom looks alarming and is neither
a bug nor ours:

**If the offering is already cached, going offline does not produce `unavailable`.** The paywall
renders — correct German copy, correct prices, working buttons — because that all comes from the
cached offering and paywall configuration. What fails is the **imagery**: RevenueCat's
dashboard-authored paywalls host every image and icon on `assets.pawwalls.com`, so offline the hero,
the feature-row icons and the package selection indicators cannot load.

In a **Debug** build each failure renders as a red box containing the full `NSURLErrorDomain
Code=-1009` dump — `RemoteImage.swift` uses `DebugErrorView(…, releaseBehavior: .emptyView)`, and
`DebugErrorView` shows its error text only under `#if DEBUG`. In **Release** the same failure renders
`Rectangle().hidden()`: invisible, but laid out at the same size, so a shipping build shows a paywall
with blank spaces where the art should be, never an error message. Verified by reading the SDK
source, not by inference.

**Why a fresh install hits it and normal use does not.** `Purchases` warms the paywall asset cache
automatically — `warmUpCaches(offerings:)` fires on every offerings fetch and dispatches
`warmUpPaywallAssetsCache`, which pre-downloads every image in every paywall, once per process. Go
offline within seconds of a first launch and that background download has not finished; any user
who has had the app open online for longer has the images on disk and sees a normal paywall offline.

**Accepted, with no code change.** The purchase cannot complete offline in any case, and suppressing
a paywall whose offering *is* cached would trade a cosmetic degradation for a worse one — a gate
that blocks with no explanation. If it ever needs fixing, the lever is warming earlier (fetch
offerings at launch rather than at first gate), not a new state in `ProPaywallView`.

**So the genuine `unavailable` state needs a stricter repro**: airplane mode **before** the first
launch after install, so no offering is ever fetched. That is the only path where
`PaywallOfferingSource`'s ladder runs out and our own retry UI appears.

## 6. The debug surfaces

Settings shows three DEBUG-only sections. The first two are backed by the single
`ProEntitlementDebugging`
protocol — one seam, because they answer one question: *what is this build reporting as Pro, and
why*.

**Debug — the entitlement picker.** Real / Free / Pro / Founder.

- The whole file, the protocol, and the `AppDependencies` property are inside `#if DEBUG`, so a
  shipping binary has no writable entitlement surface and no purchase entry point at all. Verified
  by a Release-configuration build.
- Its strings are intentionally **not localized** — they are developer-facing and never ship.
- The row subtitle **always names the really-resolved entitlement** ("Reporting real: free" /
  "Overriding subscription — real: free"), so it is never ambiguous whether the picker is showing
  RevenueCat's answer or masking it. That is what `resolvedState` on the debug protocol is for.
- **"Real" clears the override**, which matters now that there is a real state to fall back to;
  before RevenueCat there was nothing to return to and the picker was one-way.
- `.lifetime` is omitted from the picker: it is indistinguishable from `.subscription` at every
  gate, and the store section below reaches it through a real purchase.
- The section footer states whether `ProGating.isEnabled` is on **and where that came from** (the
  shipped value, or one of the two launch arguments), because with gating off a simulated
  entitlement changes nothing visible and that is otherwise indistinguishable from a broken picker.
- It is also the **only** way to see the Founder branch during development: the environment guard
  in §3a means a real Founder grant can never resolve outside a production App Store install.

**Debug — Store.** The three Test Store products with a Buy button, plus Restore.

This is the ticket-03 stand-in for the paywall (ticket 14): the purchase *path* has to be
verifiable — a real purchase flipping the entitlement is the only thing that proves the entitlement
identifier in §3b is right — while the purchase *UI* is a later ticket. It shows store-provided,
already-localized titles and prices (nothing above `Data/` ever formats a currency), disables its
buttons while a purchase is in flight, and reports a failure in the footer. **Cancelling clears the
failure instead of setting one**, which is the visible half of "`userCancelled` is not an error".

**Debug — Paywall placements.** One row per §8 placement with a Show button, plus "Reset
once-ever placements".

It goes through `presentIgnoringEligibility`, because the shipped `present(_:)` is inert while the
kill switch is off — which is how the app shipped until ticket 15 — so the ordinary path drew
nothing during development. It stays the development route after the flip: `present(_:)` now
depends on real eligibility, and a placement that has already fired once, or an entitled account,
would still draw nothing. It bypasses the switch, the entitlement and the once-ever cap;
**Rule 3 still holds**. Each one-shot row states whether the record says it already fired, since
otherwise "nothing happened" and "already spent" look identical — and that row updating the moment
the sheet appears is exactly what the in-memory fired set in §5a exists for.

The section also carries a **Founder celebration** row (§5h) — Show plus "already shown" / "not yet
shown" — because the Founder grant can never resolve outside a production App Store install (§3a),
so this and the entitlement picker are the only ways to see that screen during development at all.
Its Show button bypasses the kill switch, the entitlement and the once-ever *check*; Rule 3 still
holds there too. It does **not** bypass the once-ever *write* — dismissing a debug-raised screen
spends the record exactly as a real one does, the same way the placement rows spend theirs through
`didPresent` — which is what the Reset row beneath it is for.

The Reset button clears the fired record, **disarms the §5g triggers** (through
`ProactivePaywallTrackingDebugging`) and un-shows the Founder screen. Clearing only the first would leave both triggers armed, so
A and B would re-raise at the next routine creation or session end — which looks like the reset
worked but proves nothing about the triggers themselves. Note that a placement raised from this
section shows placement B **without figures** unless a workout has been completed in the same
process: the debug path bypasses the coordinator entirely, and the coordinator is what loads them.

## 7. Known follow-ups for the gate tickets

- **The gate tickets (06–11) must call `paywalls.present(_:)`**, not build their own sheet. The
  presenter is where §8's prohibitions are enforced; a screen-owned paywall sheet re-opens every
  hole §5a closes.
- **The gate tickets must reuse the §5b kit** rather than hand-rolling a blur, a badge or a hint.
  Each gate still owns its own nudge copy (`OnyxCapNudge` takes localized text), so a gate that
  adds a cap nudge adds one en + de string pair with it. **What a gate blurs must be a precomputed
  preview**, never a live-aggregating chart body — see the contract in §5b.
- **Gate tests reuse `GymStreakTests/Support/ProGatingTestDoubles.swift`** — `StubProEntitlements`
  (a pinned, mutable entitlement) and `RecordingPaywallPresenter` (records what a gate asked for
  and presents nothing). A gate's tests are about *what it asks for*; the eligibility rules belong
  to `PaywallPresenter` and are covered once, in `PaywallPresentationTests`, which keeps its own
  private doubles because it is testing the real presenter rather than standing in for one.
- **The routines list is still a non-lazy `VStack` + `ForEach` inside a `ScrollView`**
  (`RoutinesView.routineList`). Pre-existing and untouched by ticket 06 — the cap nudge is a
  single sibling view, not per-row work — but it violates the first main-thread rule and every row
  is a `RoutineCardView` taking a `@Model` object. It is bounded by the cap only for free users;
  a Pro user with thirty routines pays for all thirty on every render. Worth a `LazyVStack` and a
  display struct in its own change.
- **The `.proLocked` lock card is not clipped to the content it covers.** `OnyxProLockOverlay`
  applies `.clipped()` to the blurred content *before* overlaying the card, so at accessibility
  Dynamic Type sizes the card (icon + headline + subtitle + CTA + `Spacing.lg`) can be taller than
  the region it locks and spill over the neighbouring views. On the chart screen it cannot trap
  anyone — `rangeSelector` is a later sibling in the same `VStack`, so it draws on top and wins hit
  testing — but the overlap wants an eyeball at `.accessibility3+`, and every future gate inherits
  it. The fix belongs in the kit, not at a call site.
- **`ExerciseProgressChartView.swift` (819 lines) and `ExerciseProgressViewModel.swift` (306) are
  both over the 300-line convention.** Accepted for P2: the change adds only in-place edits (two
  badge insertions and one `.proLocked` wrap) and roughly half of the view model's growth is doc
  comments. The natural split, if one is ever wanted, is a `ChartCardControls` view holding the two
  lock-aware controls (`metricTabs`, `rangeSelector`) and an `ExerciseProgressViewModel+ProGate`
  extension.
- **`ChartTimeframePicker` (`Presentation/Views/Charts/`) is ungated, and currently unused.** The
  shipped range selector is `ExerciseProgressChartView.rangeSelector`; that separate segmented
  picker has no call site today. If it is ever adopted it needs the same `isTimeframeLocked` /
  badge treatment, or it becomes an unlocked back door to the 1Y and All windows. Deleting it would
  close the hole outright.
- **`AddRoutineView` (`Presentation/Views/Routines/`) is dead code and an ungated creation path.**
  Nothing presents it, and it calls `addRoutine(name:)` directly rather than going through
  `requestAddRoutine`, so it bypasses the three-routine cap entirely. Harmless only for as long as it
  stays unreachable — which is a property no test asserts. Flagged during ticket 06 as "should
  probably be deleted"; deleting it is still the right fix, since the shipped creation flow lives
  elsewhere.
- **`RoutinesViewModel` (977 lines) and `SchedulePlanningSheet` (405) are over the 300-line
  convention**, acknowledged rather than fixed by ticket 10 — both were already past it before the
  gates arrived, and splitting them was out of scope for a gating ticket. The seam if they are ever
  split: extract `RoutinesViewModel+Gating.swift` holding `isRoutineCapReached`, `routineCapNudge`,
  `isWeekdayScheduleLocked`, `requestAddRoutine` and `requestWeekdaySchedule`.
- **P2's gate is per-screen, and the exercise detail screen is the only analytics surface today.**
  Any future chart that re-derives a window or a metric has to ask `ChartGatingPolicy` rather than
  read `ProFeatureCaps` at the call site.
- **The fastlane snapshot run is now gated, and was deliberately left that way.** Snapshot tests
  launch with only `-UI_TESTING`, so since the ticket-15 flip they run with gating on — and
  `TestDataSeeder` seeds exactly three routines against a `freeRoutineLimit` of 3, so the routines
  screenshot renders the cap nudge. **Decided 2026-08-17: irrelevant**, because the fastlane
  snapshots are no longer used — App Store screenshots come from a separate app. The infrastructure
  was left in place rather than removed; if it is ever revived it needs either `-PRO_GATING_OFF` in
  its launch arguments or a seed count below the cap.
- **`WorkoutDeletionUITests.testCoachSettingsStillPushesOnThePathBoundStack()` fails
  deterministically, and predates all of this** — reproduced against a pristine `HEAD` with gating
  off. It taps the History tab and queries `ai_coach.settings.open`, a label that exists only in
  `CoachChatView`'s toolbar, a screen the test never opens; the AI Coach settings moved when the
  Settings tab shipped. Tracked separately in `.scratch/coach-settings-uitest/`. The reason it went
  unnoticed matters more than the test: **`fastlane test_unit` runs the `GymStreakTests` scheme,
  which excludes the UI test targets**, so the repo's normal green signal says nothing about that
  suite.
- **A contextual gate's paywall raised while a workout is running is still dropped, not deferred.**
  Ticket 11 changed this only for the two *proactive* placements: `ProactivePaywallCoordinator`
  keeps its own armed record and re-attempts at the next session end (§5g). The presenter itself is
  unchanged and still returns without setting anything, so a C gate hit during a session — a
  duplicate refused at the cap, a locked chart window tapped — produces no upsell at all. That
  remains the intended reading of Rule 3 (§8 has no "show it afterwards" clause). If a general
  queue is ever wanted, it belongs in the presenter, never at a call site — and §5g's armed/presented
  split is the shape it should take.
- **A trigger armed inside a workout waits for the next session end, not for the next launch.**
  §8 forbids launch-time paywalls, so there is deliberately no flush on foreground or on app start.
  The consequence: a user who arms placement A mid-workout (creating a routine from the Routines tab
  while a session runs) and then never finishes or discards another workout never sees it. Narrow —
  A is normally armed outside a session, where it raises immediately — and the record is durable, so
  nothing is lost. If it ever matters, the safe moment to add is a screen the user deliberately
  navigated to, never a launch.
- **The placement `rawValue`s must exist as Placements in the RevenueCat dashboard**, and an
  offering must have a paywall designed. Neither is true today, so every placement currently renders
  the `default` offering with RevenueCat's "No Paywall configured" template. Both are §9.6 step 4 and
  are release-blocking (§5j).
- **`ProPaywallView` ships in release builds** but is unreachable there while the kill switch is
  off — the presenter refuses every request before a host can construct it (§5a).
- **The value moment's presentation timing rests on SwiftUI's sheet queuing, and was not exercised
  on device.** `completeWorkout()` runs from `SaveWorkoutView`'s Save button, which dismisses that
  sheet and then the active-workout screen; the coordinator's raise lands a few milliseconds later
  (it is behind an `await` on the off-main totals read), so the root host's `.sheet(item:)` binding
  goes non-nil while those dismissals are in flight. SwiftUI presents it once the context is free —
  the same handoff §5f relies on, and the same one Apple documents only through a console message.
  `ProactivePaywallTests` asserts what is *raised*; nothing asserts that the sheet actually appears
  after the summary closes. Verify it during ticket 15's launch pass with `ProGating.isEnabled`
  flipped locally; if the request turns out to be dropped rather than queued, the fix is
  `.sheet(onDismiss:)` sequencing at the host, **not** a paywall sheet inside `SaveWorkoutView`.
- **`fetchLifetimeTotals()` is unbounded and gets no cheaper as history grows.** It reads the whole
  completed-session graph to produce three scalars. It is off-main (`@concurrent`), guarded so it
  never runs while gating is off or for a Pro user, never used to *decide* the trigger (§5g — that
  is `fetchCompletedWorkoutCount()`), cached for the process, and it runs **once**: at the moment B
  is raised, after which `isEligible` is false forever. Acceptable for a once-ever placement; it
  would not be acceptable for anything recurring. A future all-time-totals *screen* must not reuse
  this call on a render path.
- **`loadValueMomentTotals()` has no in-flight coalescing.** The cache is written after the `await`,
  so two overlapping raises could each start a fetch. Not reachable today — the only concurrent
  callers would be a completion and a discard of the same session — and the read is idempotent, so
  the cost of the duplicate is one wasted walk, never a wrong number. If it ever matters, hold the
  `Task` rather than the value.
- **`AppDependencies` is past the 300-line convention** (306 lines; ticket 11 added 46). Accepted:
  a composition root grows monotonically with the app, and stored properties cannot move to an
  extension, so a split would only relocate the `init` body away from the declarations it assigns.
  If it is ever done, split by feature area (`AppDependencies+Pro.swift` holding a nested `Pro`
  struct built in one call) rather than by mechanism.
- **A gate cannot tell that its request was dropped, and that leaves a silent tap.** `present(_:)`
  returns `Void` by design (§5a), so when the presenter suppresses a request — Rule 3, or a paywall
  already on screen — a gated affordance blocks with no feedback at all. On the routines list the
  cap nudge is visible and explains it, but the two *duplicate* menus (`RoutinesView` context menu,
  `RoutineDetailView` "…" menu) have no nudge beside them, so at the cap a tap can do nothing
  visible. Narrow in practice (both suppressions need a workout or a paywall already up) and
  accepted for ticket 06, because the alternative changes the shared seam for all nine gates. If it
  is ever fixed, fix it once: have `present(_:)` report whether the request was honoured, and let
  each gate fall back to an inline message — never by giving a gate its own sheet.
- **A paywall raised from inside a full-screen cover is deferred, not dropped** — and ticket 08
  took the sanctioned fix rather than living with the deferral. SwiftUI will not put the root's
  sheet on screen while the coach-chat or opt-in cover is up, but the placement stays in
  `pendingPlacement`, so the paywall would surface only once the cover closed. (Contrast Rule 3,
  which genuinely drops the request: `show(_:)` returns without setting anything.) The coach-chat
  cover now hosts its own sheet over the same `pendingPlacement` and the root host is suppressed
  while that cover is up (§5e). **The presenter did not change**, and any future placement raised
  from inside the AI opt-in cover inherits the same choice: add a host there, never a second seam.
  The in-cover host is **filtered to `.coachChat`**: it is the only placement the chat itself
  raises, and a placement the chat did not raise belongs on the screen the user came from, not
  inside a conversation they are reading. Anything else stays pending and surfaces at the root host
  once the cover closes — unreachable today (no other gate fires from in there), and the filter is
  what keeps it that way if one ever does. Neither host is exercised by a test or on device; verify
  both during ticket 15's launch pass with `ProGating.isEnabled` flipped locally.
- **`MonthlyAllowanceStore`'s *first* read per surface is synchronous I/O on a render path.**
  `consumedCount(for:)` is documented as a memory read, and it is — after the first one, which
  falls through to `UserDefaults.string` plus `NSUbiquitousKeyValueStore.synchronize()` and is
  reached from `CoachChatView`'s body via `allowanceNudge`. Bounded hard: once per surface per
  launch, and only for a metered user (the `isMetered` guard in `AICoachAllowanceGate.nudgeState`
  runs first, so a Pro user and a kill-switch-off build never touch the store at all — asserted by
  `CoachChatAllowanceTests`). Accepted for ticket 08; not the 630 ms class of fault
  (docs/history-performance.md), but it is main-thread I/O inside a `body`. If it is ever fixed,
  add a `prime(_:)` to `MonthlyAllowanceTracking` called off the render path rather than making the
  reads async. The write path calls `synchronize()` on the main actor too, but only on a
  user-initiated send. **Ticket 09 inherited exactly this shape on two more bodies**
  (`ExerciseProgressChartView`'s coach section and the recap's offer/gate cards); the bound is
  unchanged — one backing read per surface per launch, metered users only — so a fix would be one
  `prime(_:)` for all three.
- ~~**The recap's `.offer` step is new UX and was not exercised on device.**~~ **Closed — verified on
  a real device 2026-08-17** (ticket 15's launch pass), together with the metered deep-dive and the
  coach chat. It was unreachable in a release build while the kill switch shipped off, which is why
  it stood on unit tests at the ViewModel level for so long.
- **`PeriodRecapViewModel` (507 lines) and `ExerciseDeepDiveViewModel` (393) are over the 300-line
  guideline**, acknowledged rather than fixed in ticket 09. The added code is the allowance
  lifecycle, which is cohesive with the pipeline it guards. If they are ever split, the seam is the
  now three-way-duplicated "reserve a ticket → run → refund unless delivered" bookkeeping, which
  would become a small shared helper rather than a per-ViewModel `defer`.
- **The recap offer's copy assumes a cap of 1.** "Generate your AI recap" reads as a one-off
  because it is one; if §11 ever retunes `freePeriodRecapsPerMonth` upwards, the nudge below it
  already counts correctly but the title should be revisited — the offer step itself only earns its
  place at a cap low enough that a single accidental generation matters.
- **The P9 dismiss→auto-present handoff has no automated coverage.** `ScheduleGatingTests` asserts
  what the gate *asks for* and that nothing is written on a refusal; the unit tests cannot see
  whether the root's paywall sheet actually appears once `SchedulePlanningSheet` finishes
  dismissing. Apple documents the queuing behaviour only through a console message, so the design
  rested on cross-corroborated reporting plus the HIG's explicit "close the first sheet before
  displaying the new one". **Verified on a real device 2026-08-17** — the handoff works as designed,
  so the queuing reading was right. Should it ever regress to the request being dropped rather than
  queued, the fix is `.sheet(onDismiss:)` on `RoutineDetailView` — **not** a second host inside the
  schedule sheet (§5f).
- `ProGating.isEnabled` being a `static let false` does **not** produce unreachable-branch
  warnings at a gate call site — verified with `swiftc -swift-version 6 -typecheck` on
  `if ProGating.isEnabled { … }` (2026-08-15). Swift only warns on a literal `if false`, not on
  reading a constant declaration. The zero-warning build is safe; no gate needs a workaround.
- No SwiftData `@Model`, property or relationship changed by tickets 01, 02, 08, 09, 10 or 11, so
  none needs a **CloudKit Console schema deploy**. Ticket 11 in particular only *reads* completed
  sessions — `LifetimeTrainingTotals` is a plain `Sendable` struct, and the armed-trigger flags live
  in `UserDefaults`. P9 in particular reads `RoutineSchedule.type` and refuses to
  write it — the model is untouched. The monthly taster counters stayed out of SwiftData (App
  Group `UserDefaults` mirrored to iCloud KVS, per §9) for exactly that reason.
- **The allowance store does not observe `NSUbiquitousKeyValueStoreDidChangeExternallyNotification`.**
  It caches each surface's record in memory on first read (§5e — main-thread rule 2), so a count
  spent on the user's other device lands only on the next launch. Two devices can therefore each
  spend up to five messages in the same month. Accepted: the mirror exists to survive a reinstall,
  not to arbitrate concurrent devices, and the overspend is bounded by the cap itself. If it ever
  matters, observe the notification and invalidate the cache — do not move the counters to
  SwiftData/CloudKit.
- **The in-cover paywall host (§5e) has no automated coverage.** `CoachChatAllowanceTests` asserts
  what the gate *asks for*; nothing asserts that the sheet actually appears over the coach-chat
  cover, and the unit tests cannot see it. It was unreachable in a normal build while the kill
  switch shipped off, which left it standing on reasoning rather than evidence for the whole of
  ticket 08. **Verified on a real device 2026-08-17**, so it no longer does — but the coverage gap
  is structural and remains: nothing in CI would catch a regression here, and the next change to the
  cover's presentation needs the same manual check.
- **`CoachChatService.swift` is 442 lines**, past the 300-line convention and grown by ticket 08's
  turn-outcome bookkeeping. Accepted for this ticket: the addition is ~40 lines threaded through
  the existing turn lifecycle, not a new concern that can be lifted out cleanly. The natural split,
  if one is wanted, is the turn lifecycle (`beginTurn`/`endTurn`/`cancel`/outcome reporting) into
  its own type. `CoachChatView` was brought back under the ceiling instead, by moving `MessageBubble`
  to `CoachChatMessageBubble.swift`.
- **Ticket 09 must not reimplement any of §5e.** It instantiates `AICoachAllowanceGate` with
  `.periodRecap` / `.exerciseDeepDive` (the surfaces, their limits and their placements already
  exist in `MeteredAISurface`), and its only genuinely new decision is that a **cached** recap or
  deep-dive is a free re-read rather than a generation.
- **There is a narrow window at launch where a Founder is still reported `.free`.** The entitlement
  resolves inside `refresh()`, which on the very first launch of an update needs an App Store
  round-trip, and the celebration is raised right after it returns. A user who navigates into a
  gated surface during those first moments meets the gate before the thank-you. It is not specific
  to Founders — a subscriber is equally un-entitled until RevenueCat answers — and the only fix
  would be blocking the UI on a network call at launch, which is worse. The decision is cached from
  then on, so it is a first-launch-only window.
- **The Founder screen is recorded on dismissal, so killing the app while it is up re-shows it.**
  Deliberate (a screen nobody dismissed is still owed, §5h) and benign: the worst case is being
  thanked twice.
- **Nothing automated covers the Founder screen's *hosting*.** `FounderCelebrationTests` asserts
  what the coordinator decides; the unit tests cannot see whether the cover actually appears, nor
  the opt-in suppression that keeps the three root covers from fighting. Both need a local build
  with `ProGating.isEnabled` flipped **or** the debug row (§6). Check: the thank-you appears over
  the tabs, the AI opt-in follows it rather than being swallowed by its dismissal transition
  (§5h — benign and self-healing if it is, but worth seeing), and it does not come back on the next
  launch. Flagged by `architecture-reviewer` as the one thing in ticket 12 standing on reasoning
  rather than evidence.
- **A Founder who reinstalls is thanked again.** The once-ever record is device-local and not
  mirrored to iCloud (§5h), while the grant itself survives via `AppTransaction`. Accepted — the
  alternative risks a Founder who never sees it at all.
- **Nothing in a release build can purchase or restore yet.** The store surface is DEBUG-only. The
  gateway's `restorePurchases()` is production-ready code with no shipping caller: ticket 13
  deliberately did **not** promote it to a Settings row (§5i), because `CustomerCenterView` brings
  restore, manage-subscription, cancellation and refund requests together in ticket 14, and a
  hand-built restore row would be deleted a ticket later. Until then a user who reinstalls has no
  way to get a purchase back. Harmless while nothing can be bought; a release blocker the moment
  gating flips.
- **`appStoreAPIKey` is an empty string, and the app currently ships a Test Store key.** Ticket 15
  fills the key in *and* repoints `apiKey`. Doing only the first half leaves the app on the Test
  Store; doing only the second configures the SDK with `""`, which fails at launch. Both lines, one
  commit — and it must land **before any App Store submission**, because App Review rejects builds
  carrying a Test Store key (§3b).
- **The App Store Connect products and an Offering still have to exist** and be mapped to the
  `Gym Streak Pro` entitlement in the dashboard before the `appl_` key can work. That is dashboard
  configuration; no code changes with it.
- **`RevenueCatUI` is not linked.** Ticket 14 adds the second package product for paywalls and the
  Customer Center; the package itself is already resolved, so that is a target-membership change,
  not a new dependency.
- **The App Store nutrition labels are still untouched** — ticket 13 wrote the privacy *manifests*
  (§9.7) but the App Store Connect *App Privacy* questionnaire is a separate, manual form that is
  not generated from them. It has to be filled in during ticket 15's release, alongside the listing
  copy; §9.7 records exactly which answers to give.
- **Nothing verifies that the manifests stay honest.** They are hand-written, and a future change
  that adds a required-reason API — the widget reading App Group defaults, a disk-space check, a
  displayed file timestamp — will not fail any build or test. Xcode's Privacy Report (Organizer →
  Generate Privacy Report on an archive) is the only check, and it belongs in a release pass rather
  than in CI. §9.7 lists which categories were deliberately left out and why, so the next reviewer
  starts from the decisions rather than from scratch.
- **The Settings subscription section (§5i) was never on screen until the ticket-15 flip.** It was
  hidden while the kill switch shipped off, and `SubscriptionStatusTests` asserts the copy mapping,
  not the rendering. **Verified on a real device 2026-08-17** for the states reached by the launch
  pass — Founder, active subscription and free. Still worth walking, since the copy is the longest
  on the Settings screen: the remaining plan states via the debug entitlement picker, at German
  string lengths and accessibility Dynamic Type sizes, where the footers are the longest copy on the
  Settings screen.
- **A free user's Settings section states the plan and offers nothing.** That is deliberate for
  ticket 13 (§5i), but it is a dead end the moment gating is on: the one place a user goes looking
  for "how do I get Pro" says only "Free". Ticket 14 closes it with `CustomerCenterView` plus an
  upgrade entry point; if that slips, this section needs at least a CTA raising a placement before
  the switch is flipped.
- **The purchase half of the provider never type-checks in Release.** `availableProducts` /
  `purchase` / `restorePurchases` live inside `#if DEBUG`, so ticket 14 gets their first Release
  compile. When it needs them in a shipping build, split them out of `ProEntitlementDebugging`
  into a plain `ProPurchasing` protocol and leave the debug protocol holding only the override.
- **`availableProducts()` clears and repopulates its product cache across two `await`s.** Two
  overlapping fetches can interleave, dropping the first one's mapping so a `purchase(_:)` for an
  already-displayed option returns `.failed("No store product…")`. Harmless with the single debug
  caller; ticket 14's paywall should merge into the map rather than clearing it, or guard against
  a concurrent fetch.
- **Open decision for ticket 15 — who counts as pre-monetization.** `cutoffBuild = 1000` excludes
  everyone who installs during the ungated rollout window (builds `1000 … 1000+k`, i.e. while
  tickets 03–15 ship). Either accept that, or have ticket 15 re-pin `cutoffBuild` to the build
  that flips `ProGating.isEnabled` — which is also the release that must carry the listing-copy
  change, per `monetization-strategy.md` §7. Re-pinning is a one-line change plus the two literal
  assertions in `FounderStatusTests`.
- **`resolveIfNeeded()` still has no in-flight guard.** The `isDecided` check happens before the
  `await`, so two overlapping calls would each hit StoreKit. Still harmless: the one call site is
  a launch `.task`, and ticket 03 added no foreground refresh because `customerInfoStream` keeps
  the entitlement live (§3b). Any future refresh-on-foreground has to bring the guard with it.
- **A never-settling decision re-fetches every launch, by design.** In a non-production
  environment (or a production install whose verification keeps failing) nothing is ever
  persisted, so `AppTransaction.shared` is asked again on each launch. Deliberately *not*
  short-circuited in memory: a per-process "already tried" flag would also suppress the retry
  after a genuine first-launch-offline recovers, which is the case the undecided state exists for.
- **`pro.isFounder` lives in `UserDefaults.standard`, not the App Group**, so the widget extension
  cannot read it. Correct today — no widget is Pro-aware — but a Pro-aware widget would need the
  flag moved to the App Group suite.

## 8. Verification

- `bundle exec fastlane test_unit` (iOS + watchOS) — green, **2026-08-16**, re-run after §5i with
  zero Swift warnings in either target (iOS: 86 suites, 0 failures; watch: 0 failures). Previously
  green 2026-08-15 after §5e's P4/P5 (iOS: 85 suites; watch: 34 tests). The
  watch suite passing is also the check that the watch target still builds without RevenueCat, and
  for §5g it is the evidence for "neither placement fires on the watch": the whole mechanism lives
  in the iOS target and no watch type references it.
- The Pro lock kit (§5b) carries **no unit tests, deliberately**: three presentational views with
  no logic beyond a clamped fraction. Its evidence is the Debug simulator build, the previews, and
  `fastlane test_unit_ios` (75 suites, green 2026-08-15, no new warnings). The watch suite was not
  re-run for it — the components live in `GymStreak/Presentation/` and the watch target links none
  of them. The one framework behaviour the kit depends on (an `.overlay` attached after
  `.disabled(true)` stays enabled) was verified with a throwaway hosting-controller probe and then
  deleted; the result is recorded in §5b so it does not have to be re-measured.
- Release-configuration build of the `GymStreak` scheme — succeeds, i.e. the DEBUG-only surface
  (picker, store section *and* placement section) compiles out cleanly. Re-verified 2026-08-15
  after §5h landed, zero Swift warnings — which is also what proves
  `ProactivePaywallTrackingDebugging`, `FounderCelebrationTracking.resetCelebration()` and the
  resets they back are absent from a shipping binary.
- `PaywallPlacementTests` + `PaywallPresentationTests` (18 tests, green 2026-08-15) cover the
  taxonomy and all four
  eligibility rules: every placement has a localized headline key that actually resolves; only A
  and B are one-shot; **nothing presents during an active workout, including on the debug bypass**;
  a one-shot suppressed by Rule 3 is not spent; with gating off no placement presents; a Pro user
  and a Founder are never paywalled; a one-shot fires once and the record survives a relaunch
  (a fresh presenter over the same defaults); contextual gates repeat; a second request does not
  swap a sheet already on screen, but one that never appeared is replaced rather than wedging the
  seam, and a one-shot raised without appearing is not spent.
- `RoutineCapTests` (14 tests, 17 cases with parameterization, green 2026-08-15) covers P1 (§5c).
  Eleven run against the real SwiftData repositories: under the cap, at the cap, duplication,
  deleting back under, a lapsed user above the cap (routines survive, stay editable, only creation
  is refused), work already inside the create flow, subscription / lifetime / Founder, the kill
  switch off, and both nudge states including the nudge following a lapse without a refetch. Three
  exercise `RoutineCapPolicy` directly, with no container: the boundary at limit 3 **and** 4 (the
  §4.4 retune), all three nudge states including a lapsed 6-of-3, and both exemptions.
- `ChartGatingTests` (14 tests, 18 cases with parameterization, green 2026-08-15) covers P2 (§5d),
  against a stub history provider that records the cutoff every load asked for: the free metric and
  the three free windows are never locked; each Pro metric and each Pro window locks, stays
  selectable, and raises its own placement; **a locked window is previewed and not fetched** (the
  reload asks for the same one-month cutoff, not `distantPast`); a locked metric triggers no second
  fetch; the stat triple keeps reporting the free metric; Pro, lifetime and Founder see everything;
  the kill switch off behaves identically to today; resubscribing restores the year window in the
  load key with nothing migrated; a lapse blurs, clamps the rendered window back to 3M and throws
  away neither the loaded series nor the recent sessions. Three more exercise `ChartGatingPolicy`
  directly against explicit caps, for the §4.4 / §11 Q4 retune.
- `CoachChatAllowanceTests` (24 tests, 29 cases with parameterization, green 2026-08-15) covers P3
  (§5e) against the real `MonthlyAllowanceStore` over a throwaway defaults suite and a fake KVS:
  five messages then the `.coachChat` wall; the refused sixth consumes nothing; opening an
  exhausted chat raises the paywall without consuming, and opening it with messages left raises
  nothing; a failed generation refunds, including the one that hit the wall; the nudge appears at
  one remaining, stays at zero, and disappears the instant a purchase lands; subscription, lifetime
  and Founder are unmetered; a lapse returns to a whole taster; **an unavailable device is never
  paywalled and never metered**, and unavailability does not clear a count already spent; the kill
  switch off behaves exactly as before; the count resets on the 1st; **a clock moved backwards
  restores nothing**; a reinstall restores the count from the cloud store while a record from a
  month already over does not carry over; a refund never goes below zero; the three surfaces count
  independently and their keys, limits and placements are all distinct; and the policy holds at
  retuned caps of 1, 3 and 10 and clamps a count above a retuned-down cap. Two of them guard the
  render path rather than the product rule: **an absent record is cached like a present one** (one
  backing read per surface, ever) and **an unmetered gate never reads the store at all**.
- `RecapDeepDiveAllowanceTests` (9 tests, 15 cases with parameterization, green 2026-08-15) covers
  P4 and P5's gate: one free generation then the surface's own placement; **the three allowances
  are independent of each other**; subscription, lifetime and Founder unmetered on both; a lapse
  returns to a whole taster; an unavailable device is never paywalled or metered; the kill switch
  off is unmetered and silent; a failed generation refunds; at a cap of one the nudge is on screen
  *before* the generation; and §4.3's boundary itself — only three surfaces are metered, and
  neither single-workout surface has a placement to raise.
- `ExerciseDeepDiveAllowanceTests` (6 tests) and `PeriodRecapAllowanceTests` (6 tests, both green
  2026-08-15) drive the real ViewModels over an in-memory `ModelContainer` with a fake
  service/cache/preferences: a cached result loads with the allowance spent and costs nothing;
  asking with nothing left raises the paywall and leaves the screen where it was; a generation that
  never started, and one with too little data, both refund; **a refused regeneration keeps the
  cached narrative** (the gate is asked before the cache is invalidated); opening the recap offers
  rather than spends; an exhausted open gates and raises `.periodRecap`; and with the kill switch
  off — or for a Pro user — the recap still generates on open rather than offering.
- `ProactivePaywallTests` (19 tests, 22 cases with parameterization, green 2026-08-15) covers §5g
  against the **real** `PaywallPresenter` and `ActiveWorkoutRegistry` over a throwaway defaults
  suite, because the deferral and the one-shot are interactions between the coordinator's armed
  record and the presenter's suppression — a double that presents everything would assert the
  mechanism away. Creating a routine raises A; A fires once and its record survives a relaunch
  (a fresh presenter, store and coordinator over the same defaults); the third completed workout
  raises B and the first two do not; the first overload suggestion raises B before three workouts;
  B fires once and survives a relaunch; the threshold holds at retuned values of 1 and 5;
  **a trigger armed inside a workout is deferred, still armed and not spent**, including across a
  relaunch, and including a completion reported while a session is still running; only one placement
  is raised per safe moment and the other is not lost; subscription, lifetime and Founder see
  neither and never pay for the history read; **with the kill switch off nothing arms, nothing fires
  and the read count is zero**; B carries the user's real totals; a completed workout invalidates a
  cached read; a failed read defers instead of showing figure-less copy; the totals are read
  once per safe moment rather than per raise; and **a workout below the threshold costs a count
  read and never the aggregation**.
- `lifetimeTotalsKeepMainActorResponsive` (in `SwiftDataHistorySnapshotStoreTests`, the shared
  main-actor tripwire suite) proves both halves of §5g's figures against a real 240-session
  container: the aggregation does not stall the main actor, and the three totals are exactly the
  arithmetic of the seed (240 workouts, 4 800 completed sets, 2 016 000 kg).
  `completedWorkoutCountAgreesWithTheAggregation` pins the cheap trigger read against the same
  container, including that an in-progress session is not counted.
- `grep -rl "import RevenueCat"` returns exactly one file, `RevenueCatPurchaseGateway.swift`, and
  the pbxproj lists the `RevenueCat` product dependency on the `GymStreak` target only.
- The watch app genuinely does not link it: in the Release build products, `strings` finds 624
  RevenueCat occurrences in the iOS app binary and **0** in the embedded watch app binary. (Do this
  check on a *Release* build — a Debug build moves app code into a separate `__preview.dylib`, so
  the main binary looks empty either way and the check silently proves nothing.)
- Launch smoke test on the simulator (2026-08-15): the app configures the SDK, stays up, and starts
  flushing events to RevenueCat's backend. The only SDK output is its own Test Store warning — no
  invalid-key error, no configuration error. This proves the *key* works; it does not prove the
  *entitlement identifier* does (see below).
- `ProEntitlementTests` covers the composition rather than the SDK: an active purchase reports its
  own source (subscription vs. lifetime); Founder wins over a purchase; a Founder survives a
  purchase layer that reports nothing; **a Founder is Pro before the purchase layer has answered at
  all** (a gateway that never returns); a streamed change propagates live in both directions
  (grant *and* lapse); a completed purchase flips the entitlement; a cancelled one changes nothing
  and never re-reads; restore surfaces a purchase made elsewhere. Since §3d it also pins the three
  live-purchase regressions: **a purchase is reported while the Founder resolution has not
  returned** (a resolution that never returns), and **an unreachable purchase layer never revokes**
  a live entitlement, on the read path and the restore path. 21 tests, green **2026-08-17**.
- **Not covered by any automated test, by construction:** that
  `RevenueCatConfiguration.proEntitlementIdentifier` matches the dashboard. The stubbed gateway
  cannot see the string. Only a real Test Store purchase flipping the entitlement proves it —
  which is the manual step the debug store section (§6) exists for.
- **Manual Test Store run, 2026-08-15 (device, Debug build):** products load from the configured
  Offering — the rows show package identifiers `$rc_monthly` / `$rc_annual` / `$rc_lifetime`, so
  the offerings path ran and the product-id fallback was never needed. A **lifetime** purchase
  reports `lifetime`; **monthly** (on a fresh install, i.e. a new anonymous app user ID) and
  **yearly** each report `subscription`; **cancelling the purchase sheet produces no error UI**.
  **The entitlement identifier is therefore confirmed correct against the live dashboard, not just
  against the screenshot.**
- **Observed precedence, worth knowing before ticket 13:** with *both* a lifetime purchase and an
  active subscription on the same customer, RevenueCat reports the entitlement with no
  `expirationDate`, so the app reads `.lifetime`. That is the desired outcome — a permanent unlock
  must not be downgraded to "subscription" because a later sub was bought — and it is what made a
  monthly purchase briefly look misclassified during testing until the install was reset.
- `FounderCelebrationTests` (12 tests, 15 cases with parameterization, green 2026-08-15) covers
  §5h against the **real** `FounderCelebrationStore` over a throwaway defaults suite and the real
  `ActiveWorkoutRegistry`, because "deferred, not spent" is a property of what was written down and
  a double would assert it away: a Founder is thanked; the screen fires once and the record survives
  a relaunch; a screen that was raised but never dismissed is still owed, and a dismissal reported
  while nothing is presenting records nothing; free, subscription and lifetime users see nothing;
  **an undecided decision shows nothing, writes nothing and is retried once it resolves**; a workout
  in progress defers it — across a relaunch — without spending it; **with the kill switch off
  nothing shows and nothing is written, so the release that flips the switch is the one that
  thanks the user**; the debug bypass shows it to anyone but still refuses inside a workout, and the
  debug reset clears the stored record as well as the observable mirror; and every string on the
  screen resolves.
- `FounderStatusTests` covers each branch that can grant or withhold a permanent entitlement:
  pre-cutoff grants; the cutoff build itself and anything above it does not; sandbox and Xcode
  environments do not and stay undecided; `.unverified` does not; a non-numeric version does not;
  a throw persists nothing and is retried (and can still grant on the retry); a settled decision is
  never re-asked, including across a new service instance; and the app's own shipping build number
  is not below the cutoff.
- `SubscriptionStatusTests` (6 tests, 12 cases with parameterization, green 2026-08-16) covers §5i:
  **with gating off there is no section at all**, for any entitlement; with gating on every
  entitlement is described, and by its *own* source — a Founder is never described as a subscriber
  and a lifetime buyer is never told something renews; only the free tier reports `isPro == false`;
  no two plans share a detail or a footer key (the copy-paste bug this mapping is exposed to); and
  every key the section renders — including the section header — resolves in **both** `en.lproj` and
  `de.lproj`, read out of the app bundle rather than through the current locale.
- `PaywallOfferingSourceTests` (5 tests) and `CustomerCenterEventTests` (3 tests, both green
  **2026-08-16**) cover §5j's two testable values: the offering ladder prefers a placement offering,
  falls back to the default one, and ends at `unavailable` rather than at an empty sheet, with a
  distinct log label per rung; and every Customer Center event produces a distinct, non-empty message
  that carries its payload (the product id, the refund status, the survey option), so a support
  question has evidence behind it. `SubscriptionStatusTests` gained the Founder decision: everyone
  but a Founder is offered the Customer Center, and the row's copy resolves in en and de.
- **A real paywall was rendered end to end against the Test Store** (2026-08-16, iPhone 16 Pro Max
  simulator, iOS 26.5, `ProGating.isEnabled` flipped locally and reverted): the P1 routine-cap gate
  raised the sheet, `routine-cap` logged `resolved to placement`, and `PaywallView` rendered the
  three Test Store packages ($9.99 / $79.99 / $99.99) with a close button, Purchase and Restore; the
  Test Store purchase dialog opened from it. **Completing** the purchase, restore and the Customer
  Center screen were not exercised — driving the simulator from the CLI is unreliable past the first
  few taps — and are §9.6 step 8's job. What renders today is RevenueCat's "No Paywall configured"
  template, because no paywall is designed in the dashboard yet (§5j).
- `architecture-reviewer` on §5j: **PASS WITH WARNINGS** (2026-08-16), the one standing warning
  acknowledged and accepted — the offerings fetch living in the view (§9.2). Its first pass returned
  **FAIL** and both findings are worth keeping, because neither is visible in a green build:
  - `.onRestoreCompleted` originally judged the entitlement itself, reading
    `RevenueCatConfiguration` from Presentation and granting on `isActive` alone. That is a *laxer*
    rule than the gateway's, which also refuses an unverifiable response — so a `.failed` payload
    would have dismissed the paywall while `ProEntitlementProvider` still reported `.none`, dropping
    the user back onto a gate that still blocks with no paywall left. Two answers to "is this user
    Pro" is the bug; the fix is that there is one again.
  - Moving `didPresent(_:)` to `onPaywallShown` also moved the only setter of `isPresented`, silently
    disarming the "never swap a paywall under the user" guard for the whole loading phase and
    permanently on the retry screen. Hence §5a's two reports.
- `EntitlementRefreshTests` (8 tests, green **2026-08-16**) is the regression suite for §3c, and it
  asserts **notification rather than value** — a value-based test passes on the broken code, which is
  how the bug shipped past a 100-test gate suite in the first place. It covers: buying Pro repaints
  the routines list; a lapse repaints it too; the §8 D cap nudge clears on purchase; the progress
  chart repaints (and therefore re-fetches the wider window); a restore behaves like a purchase; the
  AI taster gate is tracked rather than cached; that a purchase does not strand the recap's stored
  `.gated` state; and **re-reporting the same entitlement notifies nothing**, so the fix cannot become
  a re-render on every read. The recap test pins the *contract* — the re-entry key flips when
  metering stops — not SwiftUI's `.task(id:)` behaviour itself, which no unit test can reach.
- **Both privacy manifests actually land at their bundle roots** — checked against the built
  products rather than assumed, since a synchronized root group's resource handling is the part that
  could silently fail: `GymStreak.app/PrivacyInfo.xcprivacy` and
  `GymStreak.app/Watch/GymStreakWatch Watch App.app/PrivacyInfo.xcprivacy` are both present
  (2026-08-16), alongside RevenueCat's own `RevenueCat_RevenueCat.bundle/PrivacyInfo.xcprivacy`. No
  Copy Bundle Resources editing and no membership exception was needed. Both files pass
  `plutil -lint`.
- `architecture-reviewer` on §5i and the manifests: **PASS**, no critical and no warning findings
  (2026-08-16). It confirmed three things worth keeping: reading `state` through the
  `any ProEntitlementProviding` existential still registers with Observation (the `@Observable`
  macro's `access(keyPath:)` runs inside the getter), so the live-update claim above is not
  wishful; the entitlement→copy mapping must **not** move to `Domain/Services/` beside
  `ChartGatingPolicy`, because it carries localization keys and the visibility rule is a bare guard
  inseparable from the copy it suppresses; and `PrivacyInfo.xcprivacy` at the target-folder root is
  not a Hard rule 6 violation — that rule is about Swift sources, and the root already holds
  `Info.plist`, the entitlements file and the asset catalog.
- **The required-reason declarations were verified against Apple's reason-code reference**, not
  written from memory (2026-08-16): the app's own API usage was established by grepping all three
  targets, and each code's verbatim definition was checked. §9.7 records what that produced,
  including the categories deliberately left out.

## 9. The runbook

Everything needed to work on, test, or ship the purchase integration, in one place. §1–§8 above are
the *how it is built*; this is the *how it is operated*. `docs/monetization-strategy.md` remains the
*why*.

### 9.1 The identifiers

Every string the integration depends on lives in `Data/Purchases/RevenueCatConfiguration.swift`.
Nothing else in the app names a product, a price or an entitlement.

| Thing | Value | Where it must match |
|---|---|---|
| Entitlement identifier | `Gym Streak Pro` (spaces and capitals included) | RevenueCat dashboard → Product catalog → Entitlements (REST id `entl4a899fb281`) |
| Test Store product ids | `lifetime`, `yearly`, `monthly` | Simulated Store products, attached to that entitlement |
| Test Store package ids | `$rc_lifetime`, `$rc_annual`, `$rc_monthly` | The current Offering's packages |
| Test Store SDK key | `test_IjLklyuZDXOVrXMjaURxfwJnWxk` | `RevenueCatConfiguration.testStoreAPIKey` |
| App Store SDK key | `appl_NjUvNeWpHECDnqaxDNJcFnbAhoW` (filled in by ticket 14a; the only key a Release build can select) | `RevenueCatConfiguration.appStoreAPIKey` |
| Placement identifiers | `PaywallPlacement.rawValue`: `first-routine-created`, `value-moment`, `routine-cap`, `chart-metric`, `chart-window`, `coach-chat`, `period-recap`, `exercise-deep-dive`, `weekday-schedule` | RevenueCat dashboard → Placements (ticket 14). **Each must exist *and* point at an offering that has a paywall** — both halves fail silently in a Release build (§5j) |
| URL scheme (RevenueCat) | `rc-399243b0af` | `GymStreak/Info.plist` → `CFBundleURLTypes` |

**The entitlement identifier is the single highest-risk string in the integration.** A wrong value
does not error: `customerInfo.entitlements[…]` returns `nil`, every paying user silently reads as
free tier, and no build and no stubbed test can catch it (§8). It is verified only by a real
purchase flipping the entitlement.

**Placement `rawValue`s are wire strings.** Renaming a case without renaming the dashboard Placement
does not fail either — the SDK serves the current offering for an identifier it does not know, so
the app still shows *a* paywall, just not the one that placement was meant to have (§5j).

**As of 2026-08-16 none of the nine Placements exists in the dashboard, and no offering has a
paywall designed.** Every placement therefore renders the `default` offering with RevenueCat's own
"No Paywall configured" template. Creating the Placements and designing their paywalls is dashboard
work and is a prerequisite for ticket 15's launch.

### 9.2 The SPM integration, and the import boundary

The package is already added; these are the steps, recorded so a re-add or a second target is not
guesswork.

1. Xcode → File → Add Package Dependencies → `https://github.com/RevenueCat/purchases-ios-spm.git`
   (the SPM-only mirror of `purchases-ios` — byte-identical per tag, smaller checkout).
2. Dependency rule **Up to Next Major, from 5.0.0**. Resolved at 5.83.2;
   `GymStreak.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` **is committed**,
   so every machine and Xcode Cloud build the same revision.
3. Add the **`RevenueCat`** and **`RevenueCatUI`** products, and **only to the `GymStreak` app
   target**. The package vends four; the other two (`ReceiptParser`,
   `RevenueCat_CustomEntitlementComputation`) are not used.
4. Add nothing to the watch target, the widget extension, or any test target.

**Which files may import them — this is a hard boundary, not a convention:**

| Framework | The files allowed to import it | Why that file |
|---|---|---|
| `RevenueCat` | `Data/Purchases/RevenueCatPurchaseGateway.swift` | the SDK, entitlements, buying |
| | `Presentation/Views/Pro/ProPaywallView.swift` | `PaywallView(offering:)` takes an `Offering`, so the type has to be nameable |
| `RevenueCatUI` | `Presentation/Views/Pro/ProPaywallView.swift` | `PaywallView` |
| | `Presentation/Views/Pro/CustomerCenterSettingsRow.swift` | `.presentCustomerCenter(isPresented:…)` |
| `StoreKit` | `Data/Purchases/FounderStatusService.swift` | `AppTransaction` |

Those three files are also the only ones that may **call** the SDK. `ProPaywallView` does: it runs
`Purchases.shared.offerings()` from its `.task` rather than going through a repository, and
`AppDependencies` is not involved. That is a deliberate exception to the composition-root rule, taken
because every alternative trades one crossing for a worse one — a `Domain/` protocol here could only
return an `Offering` (an SDK type in `Domain/`) or an erased `AnyObject`, and a resolver in
`Data/Purchases/` would have Presentation name a Data type. The exception is bounded to *resolving
which offering to draw*, which is a rendering input. Everything the app **decides** still goes through
the seams: the entitlement through `ProEntitlementProviding` (which is why the restore handler asks
the provider instead of reading `CustomerInfo` itself — the gateway's fail-closed verification rule
must not be duplicated, §3b), and eligibility through `PaywallPresenter`.

`grep -rl "import RevenueCat"` returning anything outside those three files is a review failure.
`Presentation/Views/Pro/` is the only folder above `Data/` on the list, and only because the two
RevenueCat surfaces *are* SwiftUI views — a paywall cannot be rendered from the Data layer. No
RevenueCat type appears in any `Domain/` signature, in any ViewModel, or in any gate: that is what
let ticket 03 swap the conformer without touching `ProEntitlementProviding` (§3) and ticket 14 swap
the paywall without touching a caller (§5j).

**The watch target must never link it.** The package does support watchOS 6.2+, so adding it there
is a one-click mistake. Per `monetization-strategy.md` §4.1 the entire watch app is free: there is
no watch-side gate and nothing to mirror over WatchConnectivity. The check that proves it is in §8
(`strings` on a **Release** build's watch binary — a Debug build moves app code into
`__preview.dylib` and the check silently proves nothing).

### 9.3 How the Founder grant composes with RevenueCat

**Founder wins, and it never round-trips.** `ProEntitlementProvider.recompose()` is the whole rule:

```swift
guard !founderStatus.isFounder else { resolvedState = .founder; return }
// else: .none → .free, .subscription → .subscription, .lifetime → .lifetime
```

The grant is decided locally from `AppTransaction` (§3a), cached in `UserDefaults`, and asked for at
most once per install. RevenueCat is never consulted for it, and no Founder is ever created in the
RevenueCat dashboard — a Founder is not a customer. `refresh()` composes **twice**, once as soon as
the Founder decision resolves and again once the purchase layer answers, so a grandfathered user is
Pro before RevenueCat has said anything and stays Pro if it never does.
`founderDoesNotWaitOnThePurchaseLayer` pins that with a gateway that never returns.

The practical consequence for support: a Founder has nothing to restore, nothing to manage and no
receipt. If a Founder ever reports losing access, the thing to check is `pro.isFounder` in
`UserDefaults` and the app's `CFBundleVersion` against `FounderStatusService.cutoffBuild` — not the
RevenueCat dashboard.

### 9.4 Testing without Apple: the Test Store

The shipped key is a Test Store key, so the entire purchase path is exercisable today, in the
simulator, with no App Store Connect product and no StoreKit configuration file.

1. Run a **Debug** build (the debug Settings sections are `#if DEBUG`).
2. Settings → *Debug* → **Simulated entitlement** flips the *reported* state between Real, Free, Pro
   and Founder. It writes `simulatedState` on the shared `@Observable` provider, so every gate
   re-evaluates instantly. This is the only way to see the Founder branch at all: the grant can
   never resolve outside a production App Store install (§3a).
3. Settings → *Debug* → **Test Store** lists the real products and buys them for real against
   RevenueCat's Simulated Store. This is the **only** thing that verifies
   `proEntitlementIdentifier` against the live dashboard.
4. The Simulated Store serialises purchases — one at a time — which is why the debug buttons disable
   while one is in flight.
5. A fresh anonymous app user ID comes from a fresh install. Re-testing "buy monthly from nothing"
   means deleting the app, not just relaunching it.
6. Gates are live in every shipping build since ticket 15, so nothing has to be turned on to
   exercise a gate, a nudge, the paywall, the Settings subscription section (§5i) or the Founder
   screen. Launch with **`-PRO_GATING_OFF`** for the opposite: the pre-monetization app. Do **not**
   edit `ProGating.shippedValue` — see §9.4a.

The Test Store and the App Store are **different backends**. A Test Store purchase proves the code
path and the entitlement identifier; it proves nothing about App Store Connect products, prices,
trials or restore. Those are verified in the sandbox — §9.4a.

### 9.4a Testing against the real App Store sandbox

The Test Store proves the code path. The sandbox is the only thing that proves the *products*: real
prices, the annual trial, restore across installs, and whether App Store Connect is configured at
all. Researched 2026-08-16; sources at the end of this section.

#### The two switches

Neither is a source edit any more, because the source edit is the thing that eventually gets
committed. Both are DEBUG-only launch arguments — Xcode → Product → Scheme → Edit Scheme → **Run →
Arguments → Arguments Passed On Launch**.

`GymStreak.xcscheme` is shared and tracked, so ticking one *is* a diff — a visible single attribute
in the scheme file, next to the `-INITIALIZE_CLOUDKIT_SCHEMA` argument that already lives there the
same way, rather than a semantic change to Swift that reads as deliberate. **What makes it safe is
that both arguments are `#if DEBUG`**: however they are left in the scheme, they cannot affect a
shipping build.

| Argument | Effect | Without it |
|---|---|---|
| `-PRO_GATING_ON` | `ProGating.isEnabled` is `true`, so every gate, the paywall, the §5i section and the Founder screen are live. **A no-op since ticket 15** — the shipped value is already `true` | `ProGating.shippedValue`, i.e. on |
| `-PRO_GATING_OFF` | `ProGating.isEnabled` is `false`: the pre-monetization app, and the only way to see it since the flip. Added by ticket 15 to make §9.6's rollback claim checkable. Wins if both gating arguments are passed | `ProGating.shippedValue`, i.e. on |
| `-REVENUECAT_APP_STORE` | the SDK configures with the `appl_` key against the real RevenueCat project, which is what makes StoreKit purchases real | the Test Store key |

Two further Debug-only arguments, `-FOUNDER_SIMULATE_PRECUTOFF` and `-FOUNDER_SIMULATE_CUTOFF`, make
the Founder grant reachable on a device at all. They are their own topic — see **§9.4c**.

**A Release build has no switch at all**: outside DEBUG `RevenueCatConfiguration.apiKey` resolves to
the `appl_` key unconditionally, and the `test_` literal is not compiled in — the whole Test Store
half of the file is `#if DEBUG`. So the key the SDK warns is an automatic App Review rejection is
absent from a shipping binary rather than merely unused by it, which is what makes §9.6's `strings`
check meaningful. `storeBackendIsStructural` pins the Debug half.

#### The device procedure

**A physical device is required.** The simulator cannot reliably sign in to a Sandbox Apple Account;
its supported paths are a local `.storekit` file or — for this app — the Test Store, which already
works. Nothing below can be done in the simulator.

1. App Store Connect → **Users and Access → Sandbox** → create a Sandbox Apple Account. Use an
   address that is not an existing Apple ID.
2. On the device: enable **Developer Mode**, then sign in under
   **Settings → Developer → Sandbox Apple Account** (iOS 18+; older iOS had it under Settings → App
   Store). If the row is missing, attempt a purchase in the app once — that makes it appear.
3. Run the Debug build from Xcode with **both** launch arguments ticked. A development-signed build
   purchases against the sandbox directly; TestFlight is not needed.
4. Hit a gate (four routines is the quickest — §5c) and buy. Then check Settings → *Debug* → the
   store section's footer names the backend, so there is no doubt which one answered.
5. Re-testing from a clean slate: **Users and Access → Sandbox → Clear Purchase History** (it is
   irreversible), and delete the app to get a fresh anonymous app user ID.
6. Subscriptions renew on an accelerated clock — **Users and Access → Sandbox → the account →
   Subscription Renewal Rate**. The default compresses a month to 5 minutes and a year to an hour,
   which is what makes lapse and renewal behaviour testable at all.
7. ⚠️ **Cancelling is not lapsing, and the gates are right to ignore it.** Turning auto-renew off
   leaves `isActive == true` with a future `expirationDate`, so the app keeps reporting
   `.subscription` — the user paid for the term and Apple requires they keep it. §7's lapse table
   applies at *expiry*. "I cancelled and Pro is still on" is therefore the correct behaviour and
   not something to debug; wait out the accelerated period (or shorten the renewal rate) and watch
   for `Entitlement subscription → free` in the log.

#### Getting back to a never-subscribed state

Researched 2026-08-17 against Apple's [Manage Sandbox Apple Account settings](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/)
and RevenueCat's [Apple App Store sandbox testing](https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store),
because the obvious moves mostly do not work.

**Deleting and reinstalling the app is not a reset.** It does mint a new anonymous app user ID —
but `autoSyncPurchases` is **on by default**, so the SDK observes the StoreKit queue and re-attaches
the sandbox account's still-current transaction to the new customer as soon as it configures. Same
reason deleting the customer in the dashboard does not help on its own: RevenueCat says outright
that it "does not automatically cancel active subscriptions from Apple", and the next sync
re-creates the entitlement. **The Apple-side transaction is the thing that has to change.**

Ranked:

1. **Wait for expiry.** The only step that reliably produces a genuinely inactive entitlement with no
   account juggling. Once auto-renew is off (the Customer Center's cancel), the subscription lapses
   at the end of its accelerated period and RevenueCat reports it inactive on its own.
2. **A brand-new sandbox Apple Account**, *plus* reinstalling the app. RevenueCat's own recipe — a
   fresh Apple ID has no transaction for auto-sync to find. Settings → Developer → **Sandbox Apple
   Account** (sign out of the old one first). Deleting the old RevenueCat customer is optional
   cleanup, never the mechanism.
3. **Clear Purchase History** (Users and Access → Sandbox → the tester). Least reliable: Apple does
   not document its effect on an *active* subscription, it can take hours, and RevenueCat staff
   report it as flaky. Never the sole mechanism.

**Subscription Renewal Rate is account-wide**, labelled by the monthly case, and scales everything:

| Real | 3 min | 5 min (default) | 30 min | 1 hr |
|---|---|---|---|---|
| 1 week | 3 min | 3 min | 10 min | 15 min |
| 1 month | 3 min | 5 min | 30 min | 1 hr |
| 6 months | 18 min | 30 min | 3 hr | 6 hr |
| **1 year** | **36 min** | **1 hr** | **6 hr** | **12 hr** |

Two things it does *not* do: Apple never states whether changing it re-times an
**already-running** subscription (unconfirmed either way — do not rely on it to cut short a
subscription already bought), and it does not lift the cap of **12 renewals** before auto-renew
switches itself off.

⚠️ **Re-subscribing with the same sandbox account consumes introductory-offer eligibility.** Let a
subscription expire and buy again and Apple treats it as a resubscribe within the same subscription
group, so the account is no longer eligible for the free trial. §9.5's annual trial therefore
**cannot be re-tested on a used sandbox account** — it needs a fresh one every time. Usefully, the
same fact is how to test the *ineligible* path deliberately.

#### Products in review are already purchasable

The two subscriptions being in App Review does not block any of this: an App Store Connect product
does not need to be approved, or even attached to a submission, to be bought in the sandbox. What it
*does* need is the configuration below.

#### When the offering is empty — the failure table

This is the failure mode to expect, and every cause produces the same symptom, because StoreKit
returns an **empty array rather than an error** for a product it cannot locate. The paywall then
shows §5j's `unavailable` state.

| Cause | How to tell |
|---|---|
| Running in the simulator | The store section's footer names the backend; the simulator cannot reach the sandbox |
| **Paid Applications Agreement not active** | App Store Connect → Business → Agreements, Tax, and Banking. Nothing is returned in sandbox *or* production until it is signed and banking is complete |
| The `appl_` key is not in use | The launch argument is not ticked; the SDK also logs its Test Store warning at launch when the test key is active |
| Product identifiers not configured in RevenueCat | RevenueCat → Product catalog. The dashboard's App Store Connect API key can import them, but that is a *dashboard* convenience — it changes nothing on the device, which asks Apple directly for the identifiers the offering names |
| No offering configured | §9.1: no Placement and no paywall exists in the dashboard yet |

#### What is still not proven by any of this

Sandbox is not production. It does not exercise real money, real App Store Server Notifications
timing, or the production receipt chain. Ask-to-buy, interrupted purchases and offer signing are
`SKTestSession`/`.storekit` territory, which this project deliberately does not set up (see ticket
14a) — the two backends it has cover everything the product needs today.

#### Sources

- [In-App Purchase statuses](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-statuses)
- [TN3186: Troubleshooting In-App Purchases availability in the sandbox](https://developer.apple.com/documentation/technotes/tn3186-troubleshooting-in-app-purchases-availability-in-the-sandbox)
- [`Product.products(for:)`](https://developer.apple.com/documentation/storekit/product/products%28for%3A%29) — invalid identifiers are excluded from the array; only system faults throw
- [Testing In-App Purchases with sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox) — "For development-signed apps on iOS and iPadOS, the sandbox account is accessible in Settings > Developer after the first purchase attempt"
- [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase) — the first item **of each type** must be submitted with a new app version
- [Manage Sandbox Apple Account settings](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings) — renewal rates, Clear Purchase History
- [App Review Guidelines 2.1(b)](https://developer.apple.com/app-store/review/guidelines/) — in-app purchases must be "visible to the reviewer and functional"
- RevenueCat: [Apple App Store sandbox testing](https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store), [iOS product setup prerequisites](https://www.revenuecat.com/docs/getting-started/entitlements/ios-products)

**Two findings are community-corroborated rather than quoted from an Apple page**, and both are worth
re-checking against the App Store Connect UI rather than trusting: that a product in *Prepare for
Submission* is already sandbox-purchasable, and that App Review purchases in the sandbox. Everything
else above is quoted from Apple documentation.

### 9.4b The two traps that made a purchase look like an app bug

Both cost a full debugging round, both are configuration rather than code, and both produce symptoms
that point convincingly at the app. Check them **first**.

#### Trap 1: relaunching the app silently changes what gating is, and one direction looks exactly like Pro

Both gating arguments live in the Xcode scheme, and scheme launch arguments are passed **only when
Xcode launches the process**. Kill the app, reopen it from the home screen, and `ProGating.isEnabled`
falls back to `shippedValue` for that run.

**Before the ticket-15 flip** that fallback was `false`: no cap nudge, no lock badge, "Neue Routine"
opens the create flow — pixel-identical to a working Pro subscription. Which is why "the gate is
gone after a restart" was read — twice, including in §3c — as *the entitlement resolves correctly on
launch, so the value is fine and the bug must be in the UI*. It was never evidence of anything about
the entitlement.

**Since the flip the fallback is `true`**, so the trap runs the other way: a `-PRO_GATING_OFF` run
being verified against the rollback silently re-arms every gate on a manual relaunch, and that reads
as "the rollback does not work". The asymmetry is worth holding on to — the pre-flip direction was
dangerous because it was *invisible*, this one at least announces itself with a paywall.

Guards now in place:

- Every launch logs `Launch: gating ON|OFF (…)` to `app.gymstreak.pro` / `Gating`, naming the
  source. `ProGating.gatingSourceDescription` says outright when an argument was not passed — and,
  since the flip, when `-PRO_GATING_ON` *was* passed but is a no-op because the shipped value is
  already on. **That description is derived from `ProcessInfo`, never from comparing `isEnabled`
  against `shippedValue`**: the comparison describes the outcome, and it goes vacuous exactly when
  the argument agrees with the shipped value, which would make the log line assert the opposite of
  the truth in the one situation this guard exists for.
- Settings → *Debug* → the entitlement section's footer says the same thing while the app is open.

⚠️ **Never compare an Xcode-launched run with a hand-launched one.** They are different products.
If gating must survive a manual relaunch, the flag has to become a persisted debug setting rather
than a launch property — deliberately not done, because the flag is a launch property by design (see
`ProGating.isEnabled`), and the log line is the cheaper fix.

#### Trap 2: a product can be bought, and grant nothing

Sandbox purchase succeeds, StoreKit shows "Dein Kauf war erfolgreich", RevenueCat records the
transaction — and `customerInfo.entitlements` is **empty**, so every gate correctly reports free
tier. The app is behaving perfectly; the product is simply attached to no entitlement in the
RevenueCat dashboard.

The Offering and the Entitlement are **two independent mappings**. A paywall that renders correct
localized prices proves only the first. Observed 2026-08-17:

```
Entitlement (read): "Gym Streak Pro" absent; entitlements: [];
  purchased: [gymstreak.iap.pro.monthly.sub, gymstreak.iap.pro.yearly.sub];
  active: [gymstreak.iap.pro.yearly.sub];
  appUserID: $RCAnonymousID:…
```

**The attachment is per *app*, and the project has two.** This is the part that makes the trap so
convincing: `Gym Streak Pro` had `monthly` / `yearly` / `lifetime` attached since 2026-08-13 — the
**Test Store** products (`RevenueCatConfiguration.testStoreProductIdentifiers`). The entitlement page
therefore looks completely configured. But the App column on every row read *Test Store*, and
`gymstreak.iap.pro.monthly.sub` / `gymstreak.iap.pro.yearly.sub` — the **Apple App Store** app's
products, the ones a sandbox purchase actually buys — were attached to nothing.

That is exactly why §9.4's Test Store run passed and proved the identifier string, while the sandbox
run granted nothing: *"the Test Store and the sandbox are different backends"* is also true of the
entitlement's product list. **Attaching the Test Store trio is not attaching the products.** Both
sets have to be attached to the same entitlement, in Product catalog → Entitlements → Gym Streak Pro
→ Attach.

`active` non-empty with `entitlements` empty is the signature, and it is the reason the log prints
the purchases next to the entitlements. Read it as:

| `purchased` / `active` | `entitlements` | Cause |
|---|---|---|
| empty | empty | RevenueCat never received the transaction — App Store Connect **In-App Purchase Key** missing from the RevenueCat project (required for StoreKit 2 validation), or the Paid Applications Agreement is not active |
| non-empty | empty | The purchased products are not attached to the entitlement. Check the **App** column on the entitlement's Associated products table — Test Store rows do nothing for a sandbox purchase |
| non-empty | lists another name | `RevenueCatConfiguration.proEntitlementIdentifier` does not match the dashboard; the log names what it should be |

Note what the empty list also *rules out*: an identifier typo, the highest-risk string in the
integration (§3b). If the entitlement existed under any name it would be printed.

### 9.4c Testing the Founder grant on a device, which is otherwise impossible

**The grant cannot be observed outside a production App Store install, and no amount of retrying
changes that.** Verified on device 2026-08-17 by installing 1.1.8 from TestFlight (and separately
1.1.7 from the App Store), then the Debug build over it: the routine cap gated, no Founder screen
appeared. That is the design working. `FounderStatusService.resolveDecision()` refuses to decide
unless `AppTransaction.environment == .production`; a TestFlight install reports `.sandbox` and an
Xcode-installed build reports `.xcode`, so the decision stays **undecided** and `isFounder` is
`false`. Those environments also report `originalAppVersion` as `"1.0"`, which is not parseable as
an `Int` and would be rejected a line later anyway. The guard is load-bearing — without it every
TestFlight tester would be granted Pro forever (§7.1 trap 2) — so it is not relaxed for testing.

Two consequences worth being precise about:

- **What was installed before does not matter.** The environment belongs to the *running* build, so
  a Debug build installed over a real App Store install still reports `.xcode`.
- **The failure is safe.** Every non-production or unparseable read returns `nil` — neither granting
  nor recording a negative — so it is retried on the next launch and nobody can be permanently
  disinherited by one bad read. A `false` is only ever written when the parse succeeded and the
  build was genuinely at or above the cutoff.

#### The simulator, and what it does and does not prove

`SimulatedOriginalAppDownloadReader` (`Data/Purchases/`, entirely `#if DEBUG`) is the other
implementation of the `OriginalAppDownloadReading` seam — the seam §3a introduced because
`AppTransaction` has no public initializer. `AppDependencies.makeFounderStatusService()` selects it
when a launch argument asks for it.

| Argument | Simulates | Expect |
|---|---|---|
| `-FOUNDER_SIMULATE_PRECUTOFF` | verified, `.production`, `originalAppVersion` `"1"` — what every pre-monetization install reports | Founder granted: the thank-you screen on first launch, then no gate anywhere, and Settings reporting Founder with no Customer Center row. **Walked on a real device 2026-08-17: all three observed, with Settings reporting a real `founder` state** |
| `-FOUNDER_SIMULATE_CUTOFF` | verified, `.production`, `originalAppVersion` = `cutoffBuild` | **No** grant — the comparison is strictly less-than. This is the boundary, deliberately, rather than a value safely past it |

It replaces the *reader*, not the decision: the environment guard, the `Int` parse, the
`< cutoffBuild` comparison, the entitlement composition (Founder wins over RevenueCat, §3c) and the
celebration all run exactly as they will in production.

**What it does not cover**, so a green simulated pass is not read as more than it is:

- **Apple's own production read** — that `AppTransaction.shared` really returns `"1"` for a
  pre-cutoff install on a real App Store update. Verifiable only after release.
- **Decide-once across launches.** The suite is wiped on every simulated launch, so the run always
  takes the resolve path and never the `guard !isDecided else { return }` short-circuit — which
  also means the grant always arrives *after* the await, never already-on-record at launch (§3d).
  Both are covered by `FounderStatusTests` instead.

A simulated run writes its decision to a **separate defaults suite** (`pro.founder.simulated`),
wiped at the start of every simulated launch. The real `pro.isFounder` key is never touched, so
removing the argument returns the device to its real state immediately, and each run re-resolves
instead of short-circuiting on `isDecided`. Without that separation a simulated grant would land in
`UserDefaults.standard` and stick **forever** — the decision is recorded once by design — leaving
the device permanently claiming Founder with no gate in sight, which is precisely the §9.4b class of
symptom that reads as a broken app.

That separation is **structural, not aspirational**: if the suite cannot be opened,
`AppDependencies` falls back to *not simulating* rather than to `.standard`, so there is no path on
which a simulated decision reaches the real key. `FounderStatusTests` asserts the suite name is
usable and that a value written through it does not appear in `.standard`, which is what keeps that
fallback unreachable.

One thing the suite does *not* cover: the celebration's own "already shown" record lives in the real
defaults, so a simulated run marks the screen as seen. Settings → Debug → paywall placements →
*Reset* un-shows it.

**The logging that makes a device pass readable.** `FounderStatusService` logs one line per outcome
to `app.gymstreak.pro` / **`Founder`**, and the reasons are what matter: `AppTransaction`
unavailable, unverified, *environment is not production*, an unparseable `originalAppVersion`, the
original build against the cutoff, and the decision itself — plus "already decided" on every later
launch. The environment line is the one to look for on a pre-release device; it is the whole
explanation for a missing Founder screen, and it names the argument that gets around it.

Alongside it, `GymStreakApp` logs `Launch: entitlement <state>` next to the gating line. That line
deliberately claims less: `ProEntitlementState` has no undecided case, so undecided and free both
print `free` — the `Founder` category is what separates them — and in DEBUG it reflects the Settings
debug override when one is set, which is a fact about the picker rather than about the grant.

`FounderStatusTests` pins the two simulated cases against `cutoffBuild` itself, so re-pinning the
cutoff cannot quietly turn the negative case into a grant.

### 9.5 App Store Connect: the two product constraints that cannot be fixed in code

1. **Lifetime must be a non-consumable, not a non-renewing subscription.** The app uses an
   **anonymous** app user ID (`appUserID: nil`) to keep the no-account promise, and RevenueCat
   cannot restore consumables or non-renewing purchases under an anonymous ID. A non-consumable
   restores from the store receipt and therefore survives a reinstall or a new device; a
   non-renewing subscription does not. Getting this wrong makes Lifetime silently unrestorable, and
   it is not fixable after the fact for anyone who already bought it.
2. **The 7-day free trial is attached to annual only** (`monetization-strategy.md` §6). Not to
   monthly, and not to the contextual-gate offerings — at a contextual gate the user already has
   intent, and a trial only adds a cancellation decision.

Both are dashboard/App Store Connect configuration. Neither is expressible in the codebase, which is
exactly why they are written down here.

### 9.6 The launch checklist, and what it did

Ticket 15 executed this on **2026-08-17**. It is kept as an executed record rather than as a plan,
because the parts that cannot be undone by a hotfix — the Founder cutoff and the storefront copy —
are worth being able to re-read afterwards.

**Done in the repo:**

1. **The API key needed no swap.** `RevenueCatConfiguration.appStoreAPIKey` was already filled in and
   a Release build resolves `apiKey` to it unconditionally (§9.4a), so this was a confirmation.
   Checked against a real `-configuration Release` binary on 2026-08-17: `strings` finds
   `appl_NjUvNeWpHECDnqaxDNJcFnbAhoW` and **zero** occurrences of the `test_…` key — the Test Store
   half of the file is `#if DEBUG`, so the literal is absent rather than merely unused. (Other
   `test_`-prefixed strings in the binary are RevenueCat SDK internals, not a key.) The same check
   finds neither `-PRO_GATING_ON` nor `-PRO_GATING_OFF`, which is the direct evidence that the
   §5 override arguments cannot affect a shipping build however the scheme is left.
2. **The Founder cutoff question was settled, not deferred: `cutoffBuild` stays at `1000`.** The
   ungated-rollout cohort the question was about turned out to be empty — no build carrying the
   entitlement layer was ever released, so no install in the wild reports a build at or above the
   cutoff. §3a records the evidence. **This is the irreversible one**: once the launch build is out,
   the pre-paywall cohort is no longer distinguishable.
3. **`ProGating.shippedValue` flipped to `true`**, with the Debug-only **`-PRO_GATING_OFF`**
   counterpart added in the same change (§5). Without it there would be no way to see the
   pre-monetization app again — which is exactly what verifying the rollback below requires.
   `ProEntitlementTests.gatingShipsOn` was flipped with it, deliberately: the constant should take
   two obviously-intentional edits to change, in either direction.
4. **Both storefront listings were rewritten** in `docs/marketing/app-store-description.md` and
   `app-store-promotional-text.md`. "completely subscription-free" / "ganz ohne Abo" and "No account,
   no subscription" / "Kein Konto, kein Abo" are gone from every variant, including the promotional
   alternatives that were not live — that field is edited without a build, so a stale variant can be
   pasted back months later. The no-**account** promise stays, because it is still true. Both
   versions carry a free-vs-Pro block and the subscription terms Guideline 3.1.2 expects; the German
   description had to be tightened elsewhere to stay under the 4,000-character limit.
5. **TestFlight `WhatToTest` written in en and de**, leading with the Founder grant rather than the
   paywall — plus the caveat that the grant cannot resolve *in TestFlight* at all (§3a's environment
   guard), so a qualifying tester still sees the locks there and should not report it as a bug.

**The largest piece of work the flip switches on** is worth knowing about: `ProactivePaywallCoordinator
.isEligible` short-circuited on `isGatingEnabled`, so `fetchLifetimeTotals()` — a walk of the entire
workout history — never ran in a shipping build. It now runs after workout completion for free users.
The boundary holds: `fetchLifetimeTotals()` is `@concurrent` on the concrete
`SwiftDataHistorySnapshotStore` and delegates to the `@ModelActor` store, so the walk stays off the
main actor (Concurrency rule 1). Nothing to fix, but it is the one place where "the flip is just a
constant" is not the whole truth.

**Confirmed outside the repo (2026-08-17).** The App Store products are attached to the
`Gym Streak Pro` entitlement and a RevenueCat paywall is live — a real sandbox purchase went through
and flipped every gate. This supersedes the warning that previously stood here: until that day only
the *Test Store* products were attached, so a successful sandbox purchase granted no entitlement at
all (§9.4b trap 2).

**"A paywall is live" is still not "every placement is configured."** Each of the nine placements is
its own dashboard mapping onto an offering that needs its own paywall, and every way that chain can
break is silent in a Release build — so the nine-placement walk in the outstanding list below is a
release blocker, not a nicety (§5j).

*(The `coach-chat` case investigated that day turned out **not** to be a configuration fault: the
paywall is attached and published, and the generic template appears only when the gate is reached
through the offline-launch retry path, because the components payload travels on a separate request
— §5j row 4. Recorded because two successive diagnoses were wrong in the same direction: the SDK's
"No Paywall configured" text describes what this client received, never what the dashboard holds.)*

**Decided: Lifetime does not ship at launch.** The SKU does not exist in App Store Connect, and a
first non-consumable must be submitted with its own app version (§9.5). It gets a later release; the
listing copy deliberately does not mention it until then.

**The device pass — done 2026-08-17.** Every gate and purchase surface was walked on real hardware
against the App Store sandbox, and all of it behaved as designed:

- **The sandbox purchase.** The paywall dismisses on success and every gate is gone without a
  relaunch (§5j).
- **Restore**, which turned out not to need a tap: a fresh install resolves the entitlement at
  configure time and never shows a paywall (§5j).
- **The Founder grant**, via `-FOUNDER_SIMULATE_PRECUTOFF` (§9.4c) — thank-you screen on first
  launch, no gate afterwards, Settings reporting a real `founder` state. The simulator exists
  because a TestFlight or Xcode install can never be granted; only Apple's production read is left
  unproven, and that is verified after release.
- **All six gates**: the routine cap including duplication-counts-as-creation, analytics gating with
  existing data still visible, the three metered AI surfaces after their allowance is spent, and
  fixed-weekday schedules.
- **Both proactive placements**, the P9 dismiss→present handoff, and the Founder cover's ordering
  against the AI opt-in.
- **Rule 3**: no paywall, upsell or Pro badge during an active workout.
- **The Customer Center** and the Settings subscription section.
- **The paywall's `unavailable` state and its retry** (§5j) — the one surface with neither a test nor
  a preview behind it.
- **The rollback**, launched with `-PRO_GATING_OFF` (§5): routines beyond the cap all present and
  editable, schedules still applied, the full chart range back, no lock badges and no Settings
  subscription section — then gated again as a free user, with those routines still there and still
  editable and only *creating* another one blocked. That last step is the one that proves a gate
  blocks creation rather than hiding content.
- **Dark mode, large Dynamic Type and German**, across a paywall, the Settings subscription section,
  the Founder screen and a cap nudge.

**Outstanding, and none of it is code** — App Store Connect, one device check, and time after
release:

- **Walk all nine placements and confirm each logs `resolved to placement … paywall present`** —
  `app.gymstreak.pro` / `Paywall`, one line per presentation, naming the offering it landed on and
  whether the paywall payload arrived. This catches a missing Placement and an offering with no
  paywall, both invisible on screen in a Release build (§5j). Present each gate **normally** for this
  walk: reaching one through the offline retry path produces §5j row 4, which looks identical and is
  not a configuration fault.
- The two App Store Connect product constraints of §9.5: the trial attached to **annual only**, and
  not to the contextual-gate offerings.
- The **privacy nutrition labels** for the purchase data RevenueCat handles (§9.7) — a separate
  manual questionnaire, not generated from the manifest.
- Pasting the new listing copy into **both storefronts**, in the same release.
- Submitting with **manual release** and App Review Notes naming the exact path to a paywall
  (Routines → a fourth routine is the shortest), because 2.1(b) puts the burden of findability on us.
- After release: Apple's production `AppTransaction` read, confirmed by updating from the App Store
  and seeing the Founder screen; the §10 guardrails — D30 retention for free users and the App Store
  rating against their pre-paywall baselines, where §10 is explicit that if either moves against the
  baseline you **loosen before optimizing**; and the §11 open questions, which Phase 0 was skipped
  for.

**The subscriptions cannot be approved before this release.** App Review Guideline 2.1(b)
requires in-app purchases to be "visible to the reviewer and functional", and the first
auto-renewable subscription — and, separately, the first non-consumable — must each be submitted
*with a new app version*. A build with the kill switch off has no reachable paywall, so it could not
be the build that got the products approved. The submission carrying the flipped switch is the
submission that gets them approved; there is no earlier one.

**Shipping the copy in the same release was release-blocking, not optional.**
`monetization-strategy.md` §1 and §7 both require it: leaving a "subscription-free" claim live next
to a paywall is a review-guideline risk and, per §1, a guaranteed one-star generator. The listing
change and the gating flip are **one release or neither** — which also means the rollback below is
not complete without reverting the copy.

**Rollback.** The kill switch is the rollback: setting `ProGating.shippedValue` back to `false`
restores the free app in one release, touches no data, and takes nothing away — every gate was built
to leave existing routines, schedules and history intact and editable (§5c, §5d, §7's Rule 4). Three
things travel with it: the listing copy, the `gatingShipsOn` assertion, and the nutrition labels if
purchases are withdrawn entirely.

**This is no longer a claim — it was checked on device on 2026-08-17.** A `-PRO_GATING_OFF` launch
left nothing in a degraded state: routines beyond the cap all present and editable, weekday schedules
still applied, the full chart range back, no lock badge and no Settings subscription section. The
step that carries the weight is the one after: gated again as a *free* user, those same routines are
still there and still editable, and only creating another one is blocked — which is what
distinguishes a gate that blocks creation from one that hides content. Re-run it the same way if the
switch is ever flipped back, and note trap 1 in §9.4b while you do: a manual relaunch drops the
argument and re-arms every gate, which reads as "the rollback does not work".

### 9.7 Privacy: the manifest and the nutrition labels

This is not a formality for this app. Its brand position was "fast, private, and completely
subscription-free… your training data belongs to you" — ticket 15 removed the subscription half of
that claim from both listings and kept the privacy half, which is still true — and RevenueCat
introduced a third-party network flow at launch that did not previously exist. Ticket 03 added the
flow; ticket 13 declared it.

#### The manifests

The repo had **no privacy manifest at all** before ticket 13. There are now two:

| File | Bundle | Why |
|---|---|---|
| `GymStreak/PrivacyInfo.xcprivacy` | iOS app | `UserDefaults` + one file-timestamp read + the RevenueCat flow |
| `GymStreakWatch Watch App/PrivacyInfo.xcprivacy` | watchOS app | `UserDefaults` only — it ships as its own bundle and is scanned separately |

**The widget extension deliberately has none.** It makes no required-reason API call (`UserDefaults`,
file timestamps, disk space, boot time, active keyboards — verified by grep across the target) and
collects nothing. A manifest declaring nothing would be noise; re-check this if the widget ever
becomes Pro-aware, because that would mean reading the App Group defaults.

Both files sit at the **top level of their target's folder**, which is a
`PBXFileSystemSynchronizedRootGroup`: the file is picked up automatically as an ordinary resource
and copied flat to the bundle root, which is where Apple requires it. No Copy Bundle Resources
editing, no membership exception. §8 records the check that it actually landed there.

#### What is declared, and why

- **`NSPrivacyTracking` is `false`** and `NSPrivacyTrackingDomains` is omitted. No IDFA, no
  `AdSupport`, no attribution SDK, and RevenueCat's `collectDeviceIdentifiers()` is deliberately
  never called (§3b).
- **`NSPrivacyAccessedAPICategoryUserDefaults` — `CA92.1` *and* `1C8F.1`.** They cover different
  things and both apply: `CA92.1` is "information only accessible to the app itself"
  (`UserDefaults.standard`), `1C8F.1` is "information accessible to the apps, app extensions and
  App Clips that are members of the same App Group". One `1C8F.1` covers the widget extension *and*
  the watch app — App Group membership is not per-member.
- **`NSPrivacyAccessedAPICategoryFileTimestamp` — `C617.1`**, for `PeriodRecapViewModel`'s
  `attributesOfItem(atPath:)[.modificationDate]` read of its own recap cache file. `C617.1` is the
  in-container code; `DDA9.1` would be the one to use if that timestamp were ever *displayed* to the
  user, and `3B52.1`/`0A2A.1` do not apply here.
- **`NSPrivacyCollectedDataTypePurchaseHistory`** — not linked to identity, never used for tracking,
  purposes App Functionality **and** Analytics. Analytics is not optional politeness: RevenueCat's
  own dashboard (Customer History, Charts, Experiments) is an analytics use of that data, and it
  applies whether or not the app user ID is anonymous.

**Nothing else is declared, and each absence is a decision:**

- `NSUbiquitousKeyValueStore` (iCloud KVS) is **not** a required-reason API. Apple defines exactly
  five categories — UserDefaults, file timestamp, system boot time, disk space, active keyboards —
  and KVS is in none of them.
- HealthKit, SwiftData, CloudKit, WatchConnectivity, ActivityKit and FoundationModels need no
  category either: the required-reason system targets specific low-level APIs, not whole frameworks.
- Health, fitness and workout data is **not a collected data type**: it never reaches a server the
  developer controls. It lives in HealthKit and in the user's *own* CloudKit private database, which
  the developer cannot read. This is the same fact §1 of the strategy doc is a promise about.
- The AI Coach adds nothing: FoundationModels runs on device, and no prompt or response leaves it.

#### The nutrition labels — a separate, manual thing

The App Store Connect *App Privacy* questionnaire is filled in by hand and is **not** generated from
the manifest. It has to be updated in the same release that turns purchases on (§9.6 step 12):

- Add **Purchases** → *Purchase History*.
- Purposes: **App Functionality** and **Analytics** (RevenueCat's dashboard, as above).
- Linked to the user's identity: **No** — anonymous app user ID, no accounts.
- Used to track you: **No** — no IDFA, no cross-app advertising use.

#### Where the SDK's own manifest fits

RevenueCat ships its own `PrivacyInfo.xcprivacy` inside the package, declaring `UserDefaults`
(`CA92.1`) and the same unlinked, untracked Purchase History entry. Xcode **merges every linked
SDK's manifest with the app's** into one Privacy Report at archive time, so the app's manifest does
not strictly need to repeat the purchase entry. It repeats it anyway, deliberately: the app's own
declaration should be readable on its own, and this file is what a reviewer of *this repo* reads.
