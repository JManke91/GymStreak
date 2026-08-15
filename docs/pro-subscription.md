# Pro subscription — entitlement core, Founder grant and RevenueCat

**Status (2026-08-15):** tickets 01, 02 and 03 of `.scratch/pro-entitlements/issues/` are
implemented. The app knows whether the current user is Pro, every future gate can ask that
question through one abstraction, users who installed before monetization are permanently granted
Pro, and the entitlement is now backed by **RevenueCat** — purchases against the Test Store work
end to end. But **nothing is gated yet**, the only purchase entry point is DEBUG-only, and the
global gating switch ships **off**. In a release build the shipped app behaves exactly as it did
before.

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
| Tests | `ProEntitlementTests`, `FounderStatusTests` | `GymStreakTests/` |

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
with the switch off, nothing blocks.

## 6. The debug surfaces

Settings shows two DEBUG-only sections, both backed by the single `ProEntitlementDebugging`
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

## 7. Known follow-ups for the gate tickets

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
- Release-configuration build of the `GymStreak` scheme — succeeds, i.e. the DEBUG-only surface
  (picker *and* store section) compiles out cleanly.
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
