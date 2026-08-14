# Watch unit-test target (`GymStreakWatchTests`)

**Status:** live since 2026-08-13. Implements **P1.1** of
`docs/architecture-audit-2026-08.md` ("Stand up a watch unit-test target
*before* any watch structural work" — the audit's highest-leverage finding).

---

## 1. What this is and why it exists

`GymStreakWatchTests` is a **watchOS unit-test bundle** hosted by the
`GymStreakWatch Watch App` target. Before it existed the project had exactly one
unit-test target (`GymStreakTests`, iOS-only) and the watch target had **zero**
unit tests — `GymStreakWatchUITests` is fastlane screenshot generation, not
assertions (see `docs/watch-screenshots.md`).

The gap mattered because of how this repo shares code between the two targets.
iOS↔watch code sharing is done by **per-target file copies**, not a shared
module (see `docs/architecture.md` and §2 of the audit — the decision to keep
duplicating rather than extract a local Swift package was deliberately
reaffirmed). Pure-logic watch files therefore had headers like:

> "Unit coverage lives against the iOS original … there is no watch unit-test
> target."

Testing the iOS copy proves nothing about the copy that actually ships on the
watch. Audit item **P1.4** is the proof: a real, undocumented wire-schema drift
(`loadBehaviorRaw` optional on iOS, non-optional on watch) survived in ~4,600
duplicated lines precisely because only one side was ever asserted on. It was
fixed 2026-08-13, and the test that prevents its return lives here.

So this target's job is two-fold:

1. **Anti-drift coverage** — assert the *watch* copies of duplicated pure logic,
   with assertions kept deliberately identical to their iOS twins so a
   behavioural divergence fails here.
2. **Unblock watch structural work** — audit item **P2.9** (extracting the
   Combine metric-projection pipeline and the rest-timer/Crown state machine out
   of the 1682-line `WatchWorkoutViewModel`) is explicitly gated on this target
   existing, because there is a live `// FIXME` next to the metrics code and the
   behaviour must be pinned before it moves.

---

## 2. Structure

```
GymStreakWatchTests/
├── ProgressiveOverloadServiceTests.swift        twin of GymStreakTests/ProgressiveOverloadServiceTests
├── WatchWorkoutInteractionPolicyTests.swift     twin of GymStreakTests/WatchWorkoutInteractionPolicyTests
├── WatchWorkoutStructuralReducerTests.swift     twin of GymStreakTests/WatchWorkoutStructuralReducerTests
├── WatchModelsWireCompatibilityTests.swift      twin of GymStreakTests/WatchModelsWireCompatibilityTests
└── Support/
    └── WatchWorkoutStructuralTestFixtures.swift twin of GymStreakTests/Support/…
```

`WatchModelsWireCompatibilityTests` arrived later, with audit item P1.4 (see
§ "Deliberately deferred, and since landed"). The seed coverage described next
is the other three files.

Seed coverage is 28 tests across **2** suites from **3** files: as in the iOS
twin, `WatchWorkoutInteractionPolicyTests.swift` declares no type of its own but
hangs its `@Test`s off `WatchWorkoutStructuralReducerTests` via an extension, so
that both share the fixtures. Consequence worth knowing: `--filter
WatchWorkoutInteractionPolicyTests` selects nothing — filter on
`WatchWorkoutStructuralReducerTests` or on the individual test name instead.

Coverage is over the watch copies of
`ProgressiveOverloadService` / `ProgressiveOverloadIncrement`,
`WatchWorkoutStructuralReducer` (+ `WatchWorkoutStructuralBaseline`,
`WatchExerciseConfigurationDraft`, `WatchExerciseSelection`) and
`WatchWorkoutInteractionPolicy`.

Two assertions exist here that have no iOS twin, because they cover the
watch-only half of a copied file:

- `unknownOrAbsentLoadBehaviorRawDegradesToResistance` — the watch's
  `ExerciseLoadBehavior.from(raw:)`, the single place a bad or absent wire value
  could silently *reverse* the direction of a weight change.
- `restOnlyChangesOfferTheTemplateUpdateButAreSubsumedByStrongerSignals` — the
  `hasRestChanges` parameter of the finish-dialog policy.

The target uses **Swift Testing** (`import Testing`, `@Test`, `#expect`), not
XCTest. It is fully supported on watchOS at our `WATCHOS_DEPLOYMENT_TARGET =
26.0` (Swift Testing requires Swift 6.0 / Xcode 16+, with `watchOS` a
first-class platform in Apple's API availability lists). `GymStreakTests` mixes
XCTest and Swift Testing for legacy reasons; **new watch tests should be Swift
Testing only**.

---

## 3. Build settings (and why each one is what it is)

Target: `GymStreakWatchTests`, product type
`com.apple.product-type.bundle.unit-test`, one
`PBXFileSystemSynchronizedRootGroup` over `GymStreakWatchTests/` (matching every
other target in this project — files are included by directory, not by explicit
build-file entries), and a `PBXTargetDependency` on `GymStreakWatch Watch App`.

```
TEST_HOST            = "$(BUILT_PRODUCTS_DIR)/GymStreakWatch Watch App.app/GymStreakWatch Watch App"
BUNDLE_LOADER        = "$(TEST_HOST)"
SDKROOT              = watchos
SUPPORTED_PLATFORMS  = "watchos watchsimulator"
TARGETED_DEVICE_FAMILY = 4
WATCHOS_DEPLOYMENT_TARGET = 26.0
PRODUCT_BUNDLE_IDENTIFIER = com.shotat24fps.GymStreakWatchTests
```

### 3.1 Hosted, not "test without host" — measured, not assumed

The modern single-target watch app has a **flat** bundle layout like an iOS app,
so the test host is `…/X.app/X`. The obsolete WatchKit-extension form
(`…/PlugIns/X.appex/X`) does not apply — there is no `.appex` in this
architecture.

**Discarded approach: a non-hosted ("test without host application") bundle.**
It is attractive — no watch app process, faster launch, and no app-launch side
effects (see §3.4) — and it is what generic advice recommends. It was tried and
**it does not link**:

```
$ xcodebuild build-for-testing -scheme GymStreakWatchTests … TEST_HOST="" BUNDLE_LOADER=""
Undefined symbols for architecture arm64:
clang: error: linker command failed with exit code 1
```

The reason is structural, not watchOS-specific: the module under test is an
**application** target, whose symbols live in the app executable. Without
`-bundle_loader` (which `BUNDLE_LOADER` supplies) the linker has nothing to
resolve `@testable import GymStreakWatch_Watch_App` against. A target dependency
alone is enough only for framework/library targets. **Do not re-try this.**

### 3.2 Module name

The product name contains spaces, so Swift's module name substitutes
underscores for every non-identifier character:

```swift
@testable import GymStreakWatch_Watch_App
```

`ENABLE_TESTABILITY` needs no per-target change: it is already `YES` in the
**project-level Debug** configuration and cascades to the watch app. It is *not*
set for Release — so if a test action is ever pointed at the Release
configuration (Xcode Cloud included), `@testable` will fail until an explicit
override is added.

### 3.3 Actor isolation — the one thing to get right here

The watch app module builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
(watch-target-only; see `docs/swift6-concurrency.md` §1 for why it is *not*
applied to the iOS module). Under SE-0466 that setting is a **per-module
compilation** setting: it changes what isolation is inferred for declarations
*inside* the watch module. Those inferred annotations are then baked into the
symbols' signatures, so an importing module sees them as genuinely `@MainActor`
— including plain value types. `WatchExercise.exerciseId`, for instance, is
exported as `@MainActor internal var exerciseId: UUID?`.

**This test target deliberately does NOT set
`SWIFT_DEFAULT_ACTOR_ISOLATION`.** It stays at the language default
(`nonisolated`), matching `GymStreakTests`. Consequences and the rule that
follows:

- **Annotate suites `@MainActor`.** Every suite and every fixture extension in
  this target carries it. This is a deliberate choice over setting the module
  default: it keeps the isolation boundary *visible at each use site* rather
  than inferring it away, so a future test that genuinely needs to be off-main
  (a stall probe, say) is written as an explicit exception instead of silently
  losing the distinction.
- Omitting `@MainActor` does not produce a subtle runtime problem — it is a hard
  compile error (`main actor-isolated property 'x' can not be referenced from a
  nonisolated context`), which is exactly the failure mode we want.
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` is set at project level and is
  inherited here. Per `docs/swift6-concurrency.md` rule 1 this means a
  `nonisolated async` helper written in this target runs on the **caller's**
  actor and does *not* hop off-main; anything that must actually leave the main
  actor needs `@concurrent` on the concrete method.
- Swift Testing avoids the `@MainActor` XCTest trap recorded in CLAUDE.md
  concurrency rule 7 (`setUpWithError()`/`tearDownWithError()` being
  `nonisolated` and silently stripping a class's isolation) — there are no
  `setUp`/`tearDown` overrides to get wrong. This is a second reason to keep new
  watch tests on Swift Testing.

### 3.4 Known caveat: the host app really launches

Because the bundle is hosted, running the suite boots the real watch app —
`GymStreakWatchApp` `@main`, `WatchAppDelegate`, and the `AppState` container,
which constructs `RoutineStore` (App Group `UserDefaults`),
`WatchConnectivityManager.shared` and `WatchHealthKitManager`. This is
unavoidable for a hosted unit-test bundle against an application target, and is
the same shape of hazard the audit flags as **P2.6** on the iOS side.

Practical rule: **tests in this target must not depend on, or assert against,
App Group state**, since the host app touches it on launch. Keep the seam
Foundation-only pure logic. Anything needing `WCSession`, `HKWorkoutSession` or
SwiftUI needs a protocol seam first — which is the work P2.9 will do.

---

## 4. Running it

**Preferred — fastlane lanes** (`fastlane/Fastfile`), because the two platforms
need two invocations and a suite nobody runs cannot detect drift:

```bash
bundle exec fastlane test_unit          # iOS + watchOS, the pre-merge command
bundle exec fastlane test_unit_watch    # watchOS only
bundle exec fastlane test_unit_ios      # iOS only
```

**Run `test_unit` before merging anything that touches watch code.** The whole
point of this target is that it asserts on the *watch* copies of duplicated
logic; skipping it is exactly how a drift like P1.4 ships.

Direct `xcodebuild` equivalents:

```bash
# Full suite on the watch simulator
xcodebuild test -scheme GymStreakWatchTests -sdk watchsimulator \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.0'

# Compile-only check
xcodebuild build-for-testing -scheme GymStreakWatchTests -sdk watchsimulator \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.0'
```

No paired-iPhone destination is needed: the destination addresses the watchOS
simulator directly and `xcodebuild`/`simctl` handle the underlying pairing. This
matches the existing watch UI-test invocation in `docs/watch-screenshots.md`.

### Scheme and test-plan wiring

`GymStreakWatchTests` gets its **own shared scheme**
(`xcshareddata/xcschemes/GymStreakWatchTests.xcscheme`), mirroring the existing
per-test-target scheme convention (`GymStreakTests.xcscheme`,
`GymStreakWatchUITests.xcscheme`).

It is deliberately **not** added to the root `GymStreak.xctestplan`.

**Discarded approach: one unified iOS + watchOS test plan.** Tested 2026-08-13
by actually adding `GymStreakWatchTests` to `GymStreak.xctestplan` and running
it both ways. Do not re-try it — it is worse than two plans in three separate
ways:

1. **Attached to the iOS `GymStreak` scheme, it produces a false green.** The
   run builds and links the watchOS test bundle (wasted work), then declines to
   run it with a single informational line —
   `Cannot test target "GymStreakWatchTests" on "iPhone 17 Pro":
   GymStreakWatchTests does not support iPhone 17 Pro's platform:
   com.apple.platform.iphonesimulator` — and still reports `** TEST SUCCEEDED **`
   with **exit code 0**. Verified: the watch-only assertion
   `unknownOrAbsentLoadBehaviorRawDegradesToResistance` never executed. A plan
   that reports success while silently skipping the watch suite is strictly more
   dangerous than no plan at all, because the drift detection it exists for is
   gone while the dashboard stays green.
2. **The iOS scheme cannot even be given a watchOS destination.** Passing
   `-destination 'platform=watchOS Simulator,…'` fails with *"Unable to find a
   destination matching the provided destination specifier"* — the scheme offers
   iOS destinations only. Adding a watchOS target to its plan does not expand
   that set.
3. **Attached to the `GymStreakWatch Watch App` scheme, destination resolution
   breaks entirely** — for *both* platforms. That scheme does legitimately offer
   iOS and watchOS destinations (its build action contains both apps, so the
   watch app can install onto a paired iPhone). But once the plan spans
   platforms, even the plain watch destination fails with *"multiple devices
   matched the request"*, because the composite paired iPhone+Watch simulators
   become candidates and make the specifier ambiguous. No destination works.

The underlying reason is documented in `man xcodebuild`, under *Testing on
Multiple Destinations*: **"All enabled tests in the scheme or xctestrun file are
run on each destination."** Multiple `-destination` flags mean *every* test on
*every* destination — a fan-out, not a routing table. There is no mechanism that
maps "this testable belongs to that platform". That model is simply the wrong
shape for cross-platform test targets, which is why Xcode Cloud likewise scopes
one platform per test action.

Two schemes, one per platform, is the correct arrangement — and it is the one
this repo already proved out for the watch UI tests. The single-command
convenience a unified plan was supposed to buy is provided instead by the
`fastlane test_unit` lane, which simply runs both invocations in order and fails
if either does.

Verified 2026-08-13: the seed coverage above is 28 tests in 2 suites, all passing,
build warning-free. The target now stands at **34 tests in 3 suites** — P1.4 added
`WatchModelsWireCompatibilityTests` the same day (see below).

---

## 5. Adding tests here

1. Put the file in `GymStreakWatchTests/` (folder-synchronized — no pbxproj edit
   needed).
2. `import Testing` + `@testable import GymStreakWatch_Watch_App`.
3. Mark the suite `@MainActor`.
4. If it is a twin of an iOS test, say so in the header and keep the assertions
   identical — that identity *is* the drift detector.

### Follow-up work this unblocks

- **P2.9** — extract the Combine metric-projection pipeline (3 of 5 `.sink`s are
  display glue, with a live `// FIXME` beside them), then the rest-timer/Crown
  state machine. Pin behaviour with tests here *first*. Note the Crown path
  deliberately avoids re-rendering per detent; a naive extraction would
  reintroduce that cost.
- Coverage for `WatchRoutineTemplateFold`, `WatchSummaryOverloadPolicy`,
  `WatchTemplateTransactionModels` and `WatchWirePayload` — all currently
  asserted only through their iOS twins.
- `WatchSyncStateStore` (942 lines, byte-identical across targets) is an
  explicit **P3 hold** — do not restructure it; adding characterisation tests
  against the watch copy is still welcome.

### Deliberately deferred, and since landed

**P1.4**, the real `loadBehaviorRaw` optionality drift between the two
`WatchModels.swift` copies, was *not* fixed by this change: the audit asks for it
as a deliberate standalone change, and folding it into the target stand-up would
have buried it. The seed suite asserted nothing about `CompletedWatchExercise`
decode optionality either way, so it needed no editing when P1.4 landed.

It landed **2026-08-13** and added a fourth *file* — and a third *suite*, per the
file-vs-suite distinction in §2 — `WatchModelsWireCompatibilityTests`, with an iOS
twin in `GymStreakTests`. It is
the first suite in this target that exists to catch a *schema* drift rather
than a behavioural one: a wire field that is non-optional in only one copy
compiles cleanly on both targets, so nothing but a decode assertion can find it.
The rule it pins and the reason the watch copy was the side that had to widen are
in `docs/watch-sync.md` ("Wire schema evolution rule").
