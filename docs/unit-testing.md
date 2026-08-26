# Unit Testing (GymStreakTests)

## What this is

A native unit-test target, `GymStreakTests`, added to `GymStreak.xcodeproj` alongside the
existing UI-test targets (`GymStreakUITests`, `GymStreakWatchUITests`). It uses the
**Swift Testing** framework (`import Testing`, `@Test`, `#expect`) rather than XCTest.

- Target: `GymStreakTests` (product type `com.apple.product-type.bundle.unit-test`)
- Scheme: `GymStreakTests` (shared, `GymStreak.xcodeproj/xcshareddata/xcschemes/GymStreakTests.xcscheme`)
- Also part of the main `GymStreak` scheme's default test plan (`GymStreak.xctestplan`,
  alongside `GymStreakUITests`), so `xcodebuild test -scheme GymStreak -only-testing:GymStreakTests`
  works too. See `docs/test-execution.md` for how the plan selects tests.
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

## Current coverage

As of 2026-07-30 the target holds **383 tests across 40 suites** (8.0 s of actual execution
time — see `docs/test-execution.md` for measured timings). The three suites below are the
original ones the target launched with; the rest have grown organically alongside features
and are named after the type under test.

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
- `InMemoryModelContainer.make()` — builds an in-memory `ModelContainer` over
  `GymStreakSchema.modelTypes`, the schema list the app itself uses. Never hand-copy the list
  here; see "Schema drift" below for what happened the last time it was.
- `FileBackedModelContainer.make()` — a disposable on-disk container over the same list, for
  behaviour that depends on the store itself (row-version conflict resolution between sibling
  contexts, which an in-memory store does not perform).
- `MockWatchSyncServicing` — records calls instead of touching real WatchConnectivity.

### Schema drift (`SchemaRegistrationTests`)

Every SwiftData container in the project — the app's CloudKit-backed store, the debug
`CloudKitSchemaInitializer`, the SwiftUI previews (`PreviewModelContainer`) and both test
containers — is built from `GymStreakSchema.modelTypes`. A `@Model` that never reaches that
list produces no build error; it produces data that silently fails to persist or sync, found
on a user's second device.

`SchemaRegistrationTests` closes that gap. It walks every class in the **app binary image**
(`class_getImageName(Routine.self)` → `objc_copyClassNamesForImage`), casts each to
`any PersistentModel.Type`, and fails if one is absent from the shared list. Deriving the
expected set from the binary rather than a second list is the point — a second list would
drift the same way the first did.

Two findings worth keeping:

- **`InMemoryModelContainer` had drifted for over a month**, hand-copying a nine-type list that
  omitted `RoutineSchedule`, and no test went red.
- **`Schema` follows relationships**, so `RoutineSchedule` was pulled into the graph anyway via
  `Routine`'s edge to it: `Schema(nineTypes).entities.count` was 10. That is exactly why the
  drift was invisible — the containers kept working. `schemaGraphMatchesTheRegisteredList`
  asserts `entities.count == modelTypes.count` and catches it independently of the runtime
  scan.

Deliberate limit: `class_getImageName(Routine.self)` pins the walk to the **app executable**, so
a `@Model` introduced in the widget extension or a future framework target would be invisible to
the guardrail. Not a live concern — the widget defines no models — and the fix, if that changes,
is to scan those images too.

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
in-memory store that can never sync.

When this was first hit, the schema genuinely failed that validation:
`RoutineExerciseAlternative.exercise` had no declared inverse, which CloudKit's validator
rejects with `SwiftDataError._Error.loadIssueModelContainer` ("CloudKit integration requires
that all relationships have an inverse"). The production app hit the same error on every
launch and silently fell back to a local, non-CloudKit container (see the catch block in
`GymStreakApp.swift`'s `sharedModelContainer`), so CloudKit sync was broken in production from
the moment the alternative-exercises feature landed until the inverse
(`Exercise.alternativeUses`) was declared in `GymStreak/Domain/Models/Models.swift` — verified
by launching the app and confirming the container loads without the fallback log line.

**That gap is closed; the explicit `cloudKitDatabase: .none` is still required.** The reason is
now simply that `.automatic` runs CloudKit validation and account/container setup on a store
that can never sync, which is pure cost and a needless coupling of the test suite to the
schema's CloudKit-compatibility. Do not read `.none` in the test containers as evidence that
the schema fails validation — if it ever does again, the app itself falls back to local-only
storage, which is the CRITICAL signal, not a test-only concern.

For our in-memory test containers, being explicit is the fix:

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
