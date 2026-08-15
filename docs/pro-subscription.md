# Pro subscription — entitlement core, Founder grant and RevenueCat

**Status (2026-08-15):** tickets 01, 02, 03, 04 and 05 of `.scratch/pro-entitlements/issues/` are
implemented. The app knows whether the current user is Pro, every future gate can ask that
question through one abstraction, users who installed before monetization are permanently granted
Pro, the entitlement is now backed by **RevenueCat** — purchases against the Test Store work
end to end — anything in the app can ask for a paywall at a named placement without knowing
what a paywall looks like, and the three visual treatments the gates share exist as design-system
components. But **nothing is gated yet**, no shipping code raises a paywall, nothing yet uses the
lock kit, the only purchase entry point is DEBUG-only, and the global gating switch ships **off**.
In a release build the shipped app behaves exactly as it did before.

`docs/monetization-strategy.md` is the *why* (what gets gated, at which cap, and the promises in
§1 that constrain all of it). This file is the *how* — the shipped implementation. It grows with
ticket 13 (the full runbook) and ticket 14 (the paywall).

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
| The stand-in paywall | `PaywallPlaceholderView` | `Presentation/Views/Pro/` |
| Blurred preview lock (+ `.proLocked` modifier) | `OnyxProLockOverlay` | `Presentation/Views/DesignSystem/` |
| Pro marker for gated entry points | `OnyxProBadge` | `Presentation/Views/DesignSystem/` |
| §8 placement D allowance hint | `OnyxCapNudge` | `Presentation/Views/DesignSystem/` |
| Debug placement section | `DebugPaywallSectionView` (`#if DEBUG`) | `Presentation/Views/Settings/Components/` |
| Tests | `ProEntitlementTests`, `FounderStatusTests`, `PaywallPlacementTests`, `PaywallPresentationTests` | `GymStreakTests/` |

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

**`1000` is the first build carrying the entitlement layer — not the first build that charges.**
Gating ships off and flips on in ticket 15, and the build number increments every release cycle in
between, so the paywall actually arrives on build `1000 + k`. Anyone installing during that
ungated window is therefore *not* a Founder despite never seeing a paywall. This fails in the safe
direction — it under-grants and leaks no revenue — but it is narrower than `monetization-strategy.md`
§7's promise, and **it is an open decision for ticket 15**: either accept the exclusion, or re-pin
`cutoffBuild` to the build that turns gating on. See §7 below.

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

The shipped key is `test_IjLklyuZDXOVrXMjaURxfwJnWxk`. **The `test_` prefix is load-bearing**: it
routes the SDK to RevenueCat's **Simulated Store** (`Store.testStore`), where offerings, purchases,
entitlements and restore all work in the simulator with no App Store Connect products and no
StoreKit configuration file. That is what let the whole purchase path ship *before* Apple approved
the real subscriptions. Production Apple keys begin with `appl_`; `appStoreAPIKey` is an empty
placeholder until ticket 15 fills it in and points `apiKey` at it.

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

`RevenueCatPurchaseGateway.entitlement(in:)` reduces a customer record to
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

This is why ticket 01's noted follow-up — "`resolveIfNeeded()` has no in-flight guard, so ticket
03's foreground refresh must add one" — **did not materialise**: no scene-phase refresh was added,
because the stream already keeps the entitlement current. `refresh()` still runs exactly once per
launch. If a foreground refresh is ever added anyway, the in-flight guard comes with it.

The modern async surface is used throughout — `customerInfoStream` rather than the
`PurchasesDelegate` callback, `customerInfo()`, `purchase(package:)`, `restorePurchases()`.

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
- `entitlement(in:)` is `nonisolated static` because it is pure and runs inside the relay.

### Every failure degrades to the free tier

No method on `ProPurchaseGateway` throws — the seam converts failures into "no purchase seen", so
no gate can crash or hang because RevenueCat is unreachable.

| Failure | Behaviour |
|---|---|
| `customerInfo()` throws (offline, backend down) | `.none` — *not seen*, never *revoked*, never persisted; the next stream emission corrects it |
| Offerings/products fetch fails | `[]` products → the purchase surface shows "no products" rather than an empty sheet |
| `purchase(…)` throws | `.failed(message)`, surfaced as text |
| User dismisses the purchase sheet | `.cancelled` — **not an error**, no alert. It arrives on *two* paths: the async API returns normally with `userCancelled == true`, and some paths still throw `ErrorCode.purchaseCancelledError`; both are handled |
| Entitlement never resolved | Treated as not entitled, and nothing is written down |
| Network entirely unavailable | The Founder path is untouched — it never calls this gateway |

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

`ProGating.isEnabled` is a single global flag that ships `false`.

One flag, not one per gate: §9's rollout ships the entitlement layer silently in Phase 1 and flips
gating on in Phase 2 (ticket 15). A per-gate flag set would make "is gating live?" un-answerable
at a glance and would allow a half-gated release. A gate reads the switch *and* the entitlement —
with the switch off, nothing blocks. The paywall presenter reads it too (§5a), so "no gate blocks
but a paywall still appears" is impossible.

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
   inline, so the eligibility logic stays testable while the shipped switch is off. With the flag
   baked in, every test would pass for the wrong reason.
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
`pendingPlacement`, and the host reports `didPresent(_:)` from the sheet's `onAppear`. The
once-ever fire is recorded **there**, not at raise time — a paywall nobody saw does not spend
placement B, and a request suppressed by Rule 3 is not burned either. For the same reason, the
"don't swap a sheet mid-presentation" guard keys off *presented*, not *pending*: a placement the
host could not show is replaced by the next request instead of wedging the seam for the rest of
the session. This matters concretely for ticket 08 — `.coachChat` is by definition raised from
inside the coach-chat cover.

**Where "a workout is running" comes from.** There are two `WorkoutViewModel` instances (Routines
and History), each owning its own HealthKit session, so no ViewModel can answer that question for
the app. `ActiveWorkoutRegistry` holds the single flag; `WorkoutViewModel` keeps it in step from
`currentSession`'s `didSet` — that property *is* the session's lifetime, so the three call sites
that start, finish and discard a workout cannot forget. The registry is deliberately not
`@Observable`: nothing renders from it, the presenter asks at the instant a paywall is requested.

**Hosting.** `ContentViewInternal` owns the one `.sheet(item:)` bound to the presenter's
`pendingPlacement`, so a gate anywhere raises a paywall without its screen owning a sheet. A
second request while one is **on screen** is ignored rather than swapping the sheet's contents (a
request that never appeared is replaced instead — see above). What it shows
today is `PaywallPlaceholderView` — headline, no offer, dismiss — because there is no purchase
surface in a shipping build until ticket 14 replaces this view with a RevenueCat paywall. No
caller changes when it does.

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
- The section footer states whether `ProGating.isEnabled` is on, because with gating off a
  simulated entitlement changes nothing visible and that is otherwise indistinguishable from a
  broken picker.
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
kill switch is off — which is how the app ships until ticket 15 — so the ordinary path would draw
nothing during development. It bypasses the switch, the entitlement and the once-ever cap;
**Rule 3 still holds**. Each one-shot row states whether the record says it already fired, since
otherwise "nothing happened" and "already spent" look identical — and that row updating the moment
the sheet appears is exactly what the in-memory fired set in §5a exists for.

## 7. Known follow-ups for the gate tickets

- **The gate tickets (06–11) must call `paywalls.present(_:)`**, not build their own sheet. The
  presenter is where §8's prohibitions are enforced; a screen-owned paywall sheet re-opens every
  hole §5a closes.
- **The gate tickets must reuse the §5b kit** rather than hand-rolling a blur, a badge or a hint.
  Each gate still owns its own nudge copy (`OnyxCapNudge` takes localized text), so a gate that
  adds a cap nudge adds one en + de string pair with it. **What a gate blurs must be a precomputed
  preview**, never a live-aggregating chart body — see the contract in §5b.
- **Ticket 11 owns the *triggers* for A and B**, not their suppression: `hasPresented(_:)` and the
  automatic once-ever record already exist, so ticket 11 only has to decide *when* "first routine
  created" and "third completed workout / first overload suggestion" have happened.
- **The placement `rawValue`s must exist as Placements in the RevenueCat dashboard** before ticket
  14 fetches offerings for them, or every placement silently serves the default offering.
- **`PaywallPlaceholderView` ships in release builds** but is unreachable there while the kill
  switch is off. Ticket 14 replaces its body with a RevenueCat paywall; the host, the binding and
  every caller stay as they are.
- **A paywall raised while a workout is running is dropped, not deferred.** That is the intended
  reading of Rule 3 (§8 has no "show it afterwards" clause), but it means a contextual gate hit
  during a session produces no upsell at all. If a queue is ever wanted, it belongs in the
  presenter — never at a call site.
- **A paywall raised from inside a full-screen cover is deferred, not dropped.** SwiftUI will not
  put the root's sheet on screen while the coach-chat or opt-in cover is up, but the placement
  stays in `pendingPlacement`, so the likely on-device behaviour is that the paywall appears once
  the cover closes — not that nothing happens. (Contrast Rule 3, which genuinely drops the
  request: `show(_:)` returns without setting anything.) **Ticket 08 must check what `.coachChat`
  actually does on device.** If deferral reads badly there, host a second sheet inside the cover —
  the presenter stays exactly as it is, a second host just reads the same `pendingPlacement`.
- `ProGating.isEnabled` being a `static let false` does **not** produce unreachable-branch
  warnings at a gate call site — verified with `swiftc -swift-version 6 -typecheck` on
  `if ProGating.isEnabled { … }` (2026-08-15). Swift only warns on a literal `if false`, not on
  reading a constant declaration. The zero-warning build is safe; no gate needs a workaround.
- No SwiftData `@Model`, property or relationship changed by tickets 01 or 02, so neither needs a
  **CloudKit Console schema deploy**. The monthly taster counters in tickets 08/09 must stay out
  of SwiftData (App Group `UserDefaults` mirrored to iCloud KVS, per §9) for the same reason.
- Ticket 12's Founder celebration screen is what makes the grant *visible*. Until it ships, a
  Founder is silently Pro — correct, but unannounced, and §7 is explicit that surfacing it loudly
  is most of its value.
- **Nothing in a release build can purchase or restore yet.** The store surface is DEBUG-only. The
  gateway's `restorePurchases()` is production-ready code with no shipping caller — ticket 13
  promotes it to a Settings row, and until then a user who reinstalls has no way to get a purchase
  back. Harmless while nothing can be bought; a release blocker the moment gating flips.
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
- **Privacy manifest and App Store nutrition labels are untouched.** The app now links a
  third-party SDK that talks to RevenueCat's servers at launch, and this repo still has no
  `PrivacyInfo.xcprivacy` of its own. The SDK ships its own manifest, but the *app's* declared data
  collection has to be reviewed before the store listing changes — ticket 15's release, alongside
  the listing copy. Ticket 13's runbook is where the reviewed answer belongs.
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

- `bundle exec fastlane test_unit` (iOS + watchOS) — green, 2026-08-15, zero Swift warnings. The
  watch suite passing is also the check that the watch target still builds without RevenueCat.
- The Pro lock kit (§5b) carries **no unit tests, deliberately**: three presentational views with
  no logic beyond a clamped fraction. Its evidence is the Debug simulator build, the previews, and
  `fastlane test_unit_ios` (75 suites, green 2026-08-15, no new warnings). The watch suite was not
  re-run for it — the components live in `GymStreak/Presentation/` and the watch target links none
  of them. The one framework behaviour the kit depends on (an `.overlay` attached after
  `.disabled(true)` stays enabled) was verified with a throwaway hosting-controller probe and then
  deleted; the result is recorded in §5b so it does not have to be re-measured.
- Release-configuration build of the `GymStreak` scheme — succeeds, i.e. the DEBUG-only surface
  (picker, store section *and* placement section) compiles out cleanly. Re-verified 2026-08-15
  after the paywall seam landed, zero Swift warnings.
- `PaywallPlacementTests` + `PaywallPresentationTests` (18 tests, green 2026-08-15) cover the
  taxonomy and all four
  eligibility rules: every placement has a localized headline key that actually resolves; only A
  and B are one-shot; **nothing presents during an active workout, including on the debug bypass**;
  a one-shot suppressed by Rule 3 is not spent; with gating off no placement presents; a Pro user
  and a Founder are never paywalled; a one-shot fires once and the record survives a relaunch
  (a fresh presenter over the same defaults); contextual gates repeat; a second request does not
  swap a sheet already on screen, but one that never appeared is replaced rather than wedging the
  seam, and a one-shot raised without appearing is not spent.
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
  and never re-reads; restore surfaces a purchase made elsewhere.
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
- `FounderStatusTests` covers each branch that can grant or withhold a permanent entitlement:
  pre-cutoff grants; the cutoff build itself and anything above it does not; sandbox and Xcode
  environments do not and stay undecided; `.unverified` does not; a non-numeric version does not;
  a throw persists nothing and is retried (and can still grant on the retry); a settled decision is
  never re-asked, including across a new service instance; and the app's own shipping build number
  is not below the cutoff.
