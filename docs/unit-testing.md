# Unit Testing (GymStreakTests)

## What this is

A native unit-test target, `GymStreakTests`, added to `GymStreak.xcodeproj` alongside the
existing UI-test targets (`GymStreakUITests`, `GymStreakWatchUITests`). It uses the
**Swift Testing** framework (`import Testing`, `@Test`, `#expect`) rather than XCTest.

- Target: `GymStreakTests` (product type `com.apple.product-type.bundle.unit-test`)
- Scheme: `GymStreakTests` (shared, `GymStreak.xcodeproj/xcshareddata/xcschemes/GymStreakTests.xcscheme`)
- Also wired into the main `GymStreak` scheme's `TestAction` (alongside `GymStreakUITests`), so
  `xcodebuild test -scheme GymStreak -only-testing:GymStreakTests` works too.
- Files live under `GymStreakTests/` at the repo root, picked up automatically via a
  `PBXFileSystemSynchronizedRootGroup` (same mechanism the app/watch targets use — no manual
  "Add Files" step needed for new test files dropped into that folder).

## Running the tests

```bash
xcodebuild test -scheme GymStreakTests -destination 'platform=iOS Simulator,name=<device>'
```

or, to run just the unit tests via the main scheme:

```bash
xcodebuild test -scheme GymStreak -destination 'platform=iOS Simulator,name=<device>' -only-testing:GymStreakTests
```

## Current coverage (14 tests, 3 suites)

- `SwiftDataRoutineRepositoryTests` — `fetchAll` sort order, `fetch(id:)`, insert/delete
  round-trip, cascade-delete of child `RoutineExercise`/`ExerciseSet` records.
- `SwiftDataWorkoutSessionRepositoryTests` — `fetchCompleted` (`endTime != nil`) filter,
  `findSession(id:healthKitWorkoutId:)` dedup semantics (primary id match, HealthKit-id
  fallback match, no-match), insert/delete round-trip.
- `RoutinesViewModelTests` — `RoutinesViewModel` constructed with real in-memory repositories
  plus a recording `MockWatchSyncServicing` test double. Covers
  `createRoutine(name:pendingExercises:)` persisting the full routine → exercise → sets →
  alternatives graph, blank-name no-op, `deleteRoutine`, and that `fetchRoutines()` pushes the
  current list to `watchSync.syncRoutines`.

Shared test support lives in `GymStreakTests/Support/`:
- `InMemoryModelContainer.make()` — builds an in-memory `ModelContainer` over the full 9-model
  schema (must be kept in sync with `GymStreak/App/GymStreakApp.swift`).
- `MockWatchSyncServicing` — records calls instead of touching real WatchConnectivity.

## Non-obvious gotchas (read before touching this target)

### 1. Hosted unit tests launch the *real* app process
`GymStreakTests` is a **hosted** test bundle (`TEST_HOST`/`BUNDLE_LOADER` point at
`GymStreak.app`) — this is required because `GymStreak` is an application (not a framework),
so `@testable import GymStreak` can only resolve its symbols by dynamically loading the test
bundle into the running app process (`bundle_loader` linking). An **unhosted** bundle fails to
link with "symbol(s) not found for architecture arm64" for every `GymStreak.*` type.

The consequence: `GymStreakApp.init()` — including its real, CloudKit-backed
`sharedModelContainer`, `WatchConnectivityManager.shared`, `CloudSyncObserver.shared` — runs
for real in the same process as the tests, before any test code executes. This is normal,
expected Xcode/XCTest behavior for hosted tests, not something introduced by this test target.

### 2. `ModelConfiguration`'s in-memory initializer defaults `cloudKitDatabase` to `.automatic`
This is the gotcha that actually broke everything the first several attempts. Writing:

```swift
ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
```

does **not** opt out of CloudKit — the default `cloudKitDatabase` parameter is `.automatic`,
so SwiftData validates the schema against CloudKit's (stricter) rules even for a purely local,
in-memory store. This project's schema has a real, pre-existing gap:
`RoutineExerciseAlternative.exercise` has no declared inverse relationship, which CloudKit's
validator rejects with `SwiftDataError._Error.loadIssueModelContainer` ("CloudKit integration
requires that all relationships have an inverse"). The production app already hits this exact
error on every launch and silently fell back to a local (non-CloudKit) container (see the
catch block in `GymStreakApp.swift`'s `sharedModelContainer`) — CloudKit sync was silently
broken in production since the alternative-exercises feature landed. **This has since been
fixed** by declaring the inverse (`Exercise.alternativeUses`) in
`GymStreak/Domain/Models/Models.swift` — verified by launching the app and confirming the
CloudKit container now loads without the fallback log line. Schema change ⇒ the CloudKit
Console schema must be deployed before the next release (standing rule).

For our in-memory test containers this is fixed by being explicit:

```swift
ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
```

Without this, container creation failed *intermittently* (whether CloudKit validation ran
before failing seemed to depend on process/timing state), which is why it initially looked like
a concurrency/parallel-test-execution bug rather than a deterministic configuration issue.

### 3. Product type string
The unit-test bundle product type is `com.apple.product-type.bundle.unit-test` (singular,
no "-ing"). `com.apple.product-type.bundle.unit-testing` (matching the UI-test bundle's
`...bundle.ui-testing`) looks plausible by analogy but doesn't exist — Xcode fails with
"unable to resolve product type" if you use it.

### 4. Test parallelism is disabled for this target (conservative, can likely be relaxed)
All three suites are marked `@Suite(.serialized)` and the `TestableReference` in both schemes
has `parallelizable="NO"`. This was added while chasing gotcha #2 above (before its real cause
was understood, intermittent parallel failures looked like a concurrency bug). With the
`cloudKitDatabase: .none` fix in place this is probably no longer necessary, but it was left in
place since it costs nothing at this test count and guarantees determinism; revisit if the
suite grows large enough that serial execution becomes slow.

## Verification performed when this target was added

- `xcodebuild test -scheme GymStreakTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
  — 14/14 tests passing, run 3 times consecutively with no flakes (after the fixes above).
- `xcodebuild test -scheme GymStreak ... -only-testing:GymStreakTests` — same 14/14 passing.
- `xcodebuild -scheme GymStreak -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
  — app still builds standalone (unaffected by the new target).
