# Repository / DI Refactor (iOS target)

## What changed

Moved the four core ViewModels (`RoutinesViewModel`, `ExercisesViewModel`, `WorkoutViewModel`,
`ExerciseProgressViewModel`) off direct `ModelContext`/`FetchDescriptor` usage and onto
repository + gateway protocols, wired through a single composition root
(`GymStreak/App/AppDependencies.swift`). This is a pure refactor — no user-facing behavior
change. The watchOS/widget targets still use `ModelContext` directly (out of scope).

A follow-up architecture-review pass (see "Follow-up: six architecture-review findings" below)
extended the same DI pattern into the AI Coach ViewModels and `ExerciseProgressService`, and
fixed a Domain→Data layering violation (`PeriodRange`). The AI Coach ViewModels/Data files
still take `ModelContext` directly for aggregation — that larger migration remains out of
scope — but they no longer reach for `AICoachAvailability.shared`/`AICoachCache.shared`
directly, and `ExerciseProgressService` is now exposed to Presentation only via a protocol.

## Why

The project's CLAUDE.md documents a target Clean Architecture (Domain/Data/Presentation with
Repository protocols) that the codebase had drifted away from — ViewModels held
`private var modelContext: ModelContext` directly and built `FetchDescriptor`s inline. This
made ViewModels hard to test in isolation and coupled Presentation to SwiftData.

## Architecture

### Domain layer

- `Domain/Repositories/RoutineRepository.swift`, `ExerciseRepository.swift`,
  `WorkoutSessionRepository.swift` — `@MainActor` protocols. They return SwiftData `@Model`
  types **directly** (deliberate, permanent decision — see below), not DTOs.
- `Domain/Interfaces/WatchSyncServicing.swift`, `HealthKitWorkoutServicing.swift` — what the
  ViewModels need from `WatchConnectivityManager` / `HealthKitWorkoutManager`.

### Data layer

- `Data/Repositories/SwiftDataRoutineRepository.swift`, `SwiftDataExerciseRepository.swift`,
  `SwiftDataWorkoutSessionRepository.swift` — `@MainActor final class`, `init(modelContext:)`,
  thin wrappers around `FetchDescriptor`/`insert`/`delete`/`save`.
- `WatchConnectivityManager` and `HealthKitWorkoutManager` now conform to their respective
  Domain protocols (one-line conformance addition each — no behavior change).

### Composition root

- `App/AppDependencies.swift` — `@MainActor final class AppDependencies: ObservableObject`,
  built once in `GymStreakApp.init()` from `sharedModelContainer.mainContext`, injected via
  `.environmentObject(dependencies)` on `ContentView`.
- Owns one shared instance each of the three repositories and `ExerciseProgressService`
  (safe to share — they all wrap the same stable `mainContext`; the old per-screen
  reconstruction pattern only existed to re-point a changing context, which no longer happens).
- Owns `watchSync: WatchSyncServicing = WatchConnectivityManager.shared` — kept as the literal
  singleton because WCSession delegate identity matters (must be the instance created at app
  launch, before any queued watch payload can arrive).
- Exposes `makeHealthKitWorkoutService() -> HealthKitWorkoutServicing` as a **factory**, not a
  shared instance — see "Two independent WorkoutViewModel instances" below.

### View wiring pattern

Views must not construct repositories/services (per the design contract). Because
`@EnvironmentObject` isn't available inside a plain `struct` `init`, but `@StateObject`
ViewModels must be constructed in `init`, views that own a ViewModel use an outer/inner split:

```swift
struct RoutinesView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    var body: some View { RoutinesViewInternal(dependencies: dependencies) }
}

private struct RoutinesViewInternal: View {
    @StateObject private var viewModel: RoutinesViewModel
    init(dependencies: AppDependencies) {
        _viewModel = StateObject(wrappedValue: RoutinesViewModel(
            routineRepository: dependencies.routineRepository,
            workoutSessionRepository: dependencies.workoutSessionRepository,
            watchSync: dependencies.watchSync
        ))
    }
}
```

This pattern already existed in the codebase (`RoutinesView`, `ExercisesView`, `ContentView`
all did this with `modelContext` before); it's now reused for dependency injection. It was
additionally applied to `ExerciseProgressChartView`, which didn't have it before (it took
`ModelContext` via `@Environment` directly in a single view).

Views that only need to fetch the exercise list ad hoc (no owned ViewModel) —
`AlternativeExercisePicker`, `ExercisePickerView`, `AddExerciseToRoutineView`,
`AddExerciseToWorkoutView` — now read `@EnvironmentObject private var dependencies:
AppDependencies` and call `dependencies.exerciseRepository.fetchAll()` instead of holding
`@Environment(\.modelContext)` + building a `FetchDescriptor` inline.

## Repository method surface

Designed from what the ViewModels actually call — see the protocol files for full docs.
Notable decisions:

- **Child models managed through relationships**: `ExerciseSet`, `RoutineExerciseAlternative`,
  `AlternativeExerciseSet` (children of `Routine`/`RoutineExercise`) and `WorkoutExercise`,
  `WorkoutSet` (children of `WorkoutSession`) are normally attached via their parent's
  relationship array and cascade-insert automatically once the parent is persisted — no
  explicit repository `insert` needed for most call sites (e.g. `RoutinesViewModel.addSet`
  never called `modelContext.insert` even before this refactor). Explicit `delete` is always
  needed since removing an object from a relationship array does not delete the underlying
  record. `RoutineRepository.insert(_ set: ExerciseSet)` exists only because
  `WorkoutViewModel.updateRoutineTemplate` explicitly inserted new template sets in the
  original code; that one call site was preserved as-is for fidelity.
- **`RoutineExercise` is not a "relationship-managed child"** in the same sense — the original
  code always explicitly deleted it (`RoutinesViewModel.removeRoutineExercise`,
  `ExercisesViewModel` cross-reference cleanup when an `Exercise` is deleted), so
  `RoutineRepository.delete(_ routineExercise:)` is a first-class method. This is why
  `ExercisesViewModel` now depends on `RoutineRepository` in addition to `ExerciseRepository`.
- **`WorkoutSessionRepository.findSession(id:healthKitWorkoutId:)`** encodes the dedup lookup
  from `RoutinesViewModel.handleCompletedWatchWorkout` (match on watch-generated id, or
  secondarily on `healthKitWorkoutId`) — a semantic query, not a generic fetch.
- **`WorkoutSessionRepository.fetchCompleted()`** (`endTime != nil`, most recent first) backs
  three call sites that previously each built their own `FetchDescriptor`:
  `ExerciseProgressChartView.loadRecentSessions`, `WorkoutDetailView.loadPRs`, and (unchanged,
  Data-layer) `ExerciseProgressService`. `PersonalRecordService.computePRs` sorts its input
  internally, so the shared descending order is safe for `loadPRs` even though the original
  code didn't sort there at all.

## `WorkoutViewModel` needs two repositories

`WorkoutViewModel` depends on both `WorkoutSessionRepository` (its primary data) and
`RoutineRepository` — the latter because `updateRoutineTemplate` and `matchRoutine` (orphan
recovery) mutate/fetch `Routine`/`ExerciseSet` (the routine template), not `WorkoutSession`
data. Both repositories wrap the same underlying `ModelContext`, so calling `.save()` on
either commits everything pending — which one is called is a style choice, not a correctness
one.

## Two independent `WorkoutViewModel` instances

The app already constructs **two** separate `WorkoutViewModel` instances: one owned by
`RoutinesView` (drives the active-workout flow from "Start Workout"), one owned by
`ContentView` (drives the History tab). This was true before the refactor too. Each one
previously created its own `HealthKitWorkoutManager()`. To preserve that (rather than
accidentally collapsing both `WorkoutViewModel`s onto one shared HealthKit session),
`AppDependencies.makeHealthKitWorkoutService()` is a **factory method**, not a stored/shared
property like the repositories. `watchSync`, by contrast, *is* shared — both ViewModels
already referenced the literal same `WatchConnectivityManager.shared` singleton before this
refactor, so a shared stored property preserves that exactly.

## `updateModelContext(_:)` removed

All four ViewModels previously had an `updateModelContext(_ newContext: ModelContext)` method
that re-pointed the ViewModel at a fresh `ModelContext` and re-fetched. This existed only to
handle a context that could change out from under the ViewModel; the design decision here is
that a repository bound to `sharedModelContainer.mainContext` at app launch never needs
re-pointing, so the method (and every call site) was deleted rather than adapted:
- `RoutinesView`/`ExercisesView`/`ContentView`: were calling it with the exact same
  `modelContext` value they'd used to construct the ViewModel in the first place — a no-op
  re-fetch. Removed; `init` already fetches once.
- `HistoryView.onAppear`: replaced `viewModel.updateModelContext(modelContext)` with the two
  things it actually did — `viewModel.fetchWorkoutHistory()` and
  `Task { await viewModel.reconcileWatchWorkouts() }`.
- `CreateRoutineView.saveRoutine()`: was calling `routinesViewModel.updateModelContext(modelContext)`
  after inserting the new routine directly into `modelContext` itself — see below.
- `ExerciseProgressChartView`/`ExerciseProgressViewModel`: `updateModelContext` was actually
  `updateExercise(_:exerciseId:context:)`; `ExerciseProgressViewModel` now takes an
  `ExerciseProgressService` once at `init` (from `AppDependencies`) and `updateExercise`
  dropped its `context` parameter entirely.

## `CreateRoutineView` transaction moved into the ViewModel

`CreateRoutineView.saveRoutine()` used to build the entire `Routine` → `RoutineExercise` →
`ExerciseSet` (+ alternatives) object graph directly against `@Environment(\.modelContext)`
and call `modelContext.save()` itself — the one place a View did SwiftData work rather than a
ViewModel. Moved verbatim into `RoutinesViewModel.createRoutine(name:pendingExercises:)`; the
view now just calls it and dismisses. The view's `@Environment(\.modelContext)` was removed.

One behavior note: the original code explicitly called `modelContext.insert(...)` for the new
`RoutineExercise`, `RoutineExerciseAlternative`, and `AlternativeExerciseSet` even though they
were also attached via relationship append. `createRoutine` drops those redundant explicit
inserts and relies purely on relationship-cascade, matching the pattern already proven
elsewhere in `RoutinesViewModel` (`addSet`, `addAlternative` never explicitly inserted their
new child either). This is not a behavior change — SwiftData cascade-inserts a child the
moment it's attached to a relationship of an already-inserted parent, regardless of whether
`insert()` is also called redundantly.

## Superset edit set-algebra extracted (`RoutineDetailView` → `RoutinesViewModel`)

`RoutineDetailView.swift` (~1880 lines) contained the diffing logic for applying a superset
edit (`applySupersetEdit`, `canApplySupersetEdit`) inline as private view methods operating on
`@State` selection. This is business logic, not UI state, so it moved to
`RoutinesViewModel.applySupersetEdit(_:selection:in:)` and
`RoutinesViewModel.canApplySupersetEdit(_:selection:)`. The view now only owns
`supersetEditMode`/`supersetEditSelection` `@State` and calls the two ViewModel methods. The
`SupersetEditMode` enum moved from `RoutineDetailView.swift` to `RoutinesViewModel.swift`
since the ViewModel's method signatures now reference it. Pure display helpers
(`supersetInfo`, `supersetLabels`, `supersetColor`, `supersetLinePosition`, link-button
visibility) were deliberately left in the view — bounded change, per the refactor's scope.

## AI Coach passthrough exception

A handful of Presentation files still declare `@Environment(\.modelContext) private var
modelContext` **solely** to pass it through to AI Coach ViewModel/aggregator APIs that take
`modelContext: ModelContext` directly (out of scope for this refactor — owned separately):
`ExerciseProgressChartView` (deep-dive), `WorkoutDetailView` (workout analysis),
`SaveWorkoutView` (post-workout recap). Every other `ModelContext`/`FetchDescriptor` usage in
`GymStreak/Presentation/` was removed.

## Deliberate omissions / out of scope

- AI Coach ViewModels (`Presentation/ViewModels/AICoach/`) and Data (`Data/AICoach/`) still take
  `ModelContext`/aggregators directly for building AI inputs — a separate, larger migration.
  (Their singleton-dependency surface — availability, cache, service, preferences — is now
  fully protocol-injected; see "Follow-up" below.)
- No UseCase layer was introduced — out of scope, business logic stays in ViewModels/Services.
- ViewModels remain `ObservableObject` (not migrated to `@Observable`, except the four
  pre-existing `@Observable` AI Coach ViewModels which were already that way) — explicitly out
  of scope per the refactor brief, to avoid an unrelated ripple.
- `docs/architecture.md` §2 was updated to describe the new state; the rest of that document
  (directory tree, watch/widget sections) was left as-is — it predates this refactor and
  covers targets this refactor didn't touch.

## Follow-up: six architecture-review findings

A later architecture-review pass fixed six remaining violations, all still following the
established "protocol in `Domain/Interfaces/`, nil-defaulted init param resolved in the
`@MainActor` init body" pattern:

1. **`PeriodRange` moved Domain→Data violation fix**: the enum (with `dateInterval(now:)`,
   `label(locale:now:)`) lived in `Data/AICoach/PeriodRecapAggregator.swift`, but the Domain
   type `PeriodRecapDestination` depended on it. Moved to
   `Domain/Models/AICoach/PeriodRange.swift`, consolidating in its `Hashable`/`CaseIterable`/
   `Identifiable`/`cacheKey` extension (previously bolted onto `PeriodRecapDestination.swift`).
2. **`WorkoutViewModel` injects `AICoachCaching`**: added `aiCoachCache: AICoachCaching? = nil`
   init param (resolved to `AICoachCache.shared` in the init body), replacing two direct
   `AICoachCache.shared.invalidate…` calls in `saveEditedWorkout`.
3. **`AICoachAvailabilityProviding` extracted**: new protocol in
   `Domain/Interfaces/AICoach/AICoachAvailabilityProviding.swift` (`state`, `isAvailable`,
   `refresh()`), conformed by `AICoachAvailability`. Its `AICoachAvailabilityState` enum moved
   to `Domain/Models/AICoach/AICoachAvailabilityState.swift` (it's part of the protocol
   surface, so it can't stay in `Data/`). Injected into all four AI Coach ViewModels
   (`ExerciseDeepDiveViewModel`, `PeriodRecapViewModel`, `PostWorkoutRecapViewModel`,
   `WorkoutAnalysisViewModel`), replacing every `AICoachAvailability.shared` call inside their
   method bodies. Views that read `AICoachAvailability.shared`/`AICoachCache.shared` directly
   for **display gating only** (`ExerciseProgressChartView`, `WorkoutDetailView.isCoachVisible`,
   `TrainingsTabView`, `AICoachSettingsView`, `ContentView`) were deliberately left as-is —
   out of scope, tolerated per the review brief.
4. **`SaveWorkoutView` cache mutation moved to VM**: the Cancel button called
   `AICoachCache.shared.invalidatePostWorkout(...)` directly. Added
   `PostWorkoutRecapViewModel.discardCachedRecap(for:)` (uses the VM's already-injected
   `cache`); the view's existing `recapVM` instance now owns the call.
5. **`WorkoutDetailView.loadCoachState()` Data-layer work moved to VM**: the view constructed
   `WorkoutAnalysisAggregator()` and called `AICoachService.shared.prewarm()` directly. Added
   `WorkoutAnalysisViewModel.prepareCoachState(session:modelContext:) -> Bool`, which does the
   `hasPreviousSession` check, cache check, and conditional prewarm (via the VM's injected
   `service`), returning whether a previous session exists so the view can still drive its own
   `hasPreviousSession` state. `AICoachServicing` gained a `prewarm()` requirement so the call
   goes through the protocol instead of `AICoachService.shared`.
6. **`ExerciseProgressProviding` extracted**: new protocol in
   `Domain/Interfaces/ExerciseProgressProviding.swift` covering
   `fetchProgressData(for:exerciseId:timeframe:)`, `isLiveNameUnique(_:)`, and
   `compareWithPrevious(workout:)`. `ExerciseProgressService` now conforms;
   `AppDependencies.exerciseProgressService`, `ExerciseProgressViewModel.progressService`, and
   `ExerciseProgressChartViewInternal.progressService` all changed from the concrete type to
   the protocol. `AppDependencies` still *constructs* the concrete class — it's the composition
   root. The one static-utility call site, `ExerciseProgressService.matches(...)` in
   `ExerciseProgressChartView.loadRecentSessions`, was left referencing the concrete type
   directly since it's a pure static helper, not an injected dependency.

## Follow-up: RoutinesViewModel size reduction (two Domain services extracted)

`RoutinesViewModel` had grown to ~638 lines by accumulating two large non-UI-state sections
alongside its CRUD surface. Both were pulled out into `Domain/Services/`, following the same
"ViewModel keeps the public method signature, delegates to a pure/constructor-injected service"
pattern as the superset extraction above — zero behavior change, no view call sites touched.

- **`Domain/Services/SupersetEditor.swift`**: the `SupersetEditMode` enum and the diff/decision
  logic that used to live inline in `applySupersetEdit` moved here as a pure, stateless
  `enum SupersetEditor` with `canApplyEdit(_:selection:)` and
  `decideEdit(_:selection:in:) -> SupersetEditDecision` (a new pure result type: `.dissolve`,
  `.modify(supersetId:toAdd:toRemove:)`, `.create(exercises:)`, `.none`). `RoutinesViewModel`'s
  `canApplySupersetEdit`/`applySupersetEdit` are now thin — they call into `SupersetEditor` and
  apply the decision via the existing `createSuperset`/`addExerciseToSuperset`/
  `removeExerciseFromSuperset`/`dissolveSuperset` methods, which stay on the ViewModel because
  `RoutineDetailView` also calls them directly. Covered by `GymStreakTests/SupersetEditorTests.swift`
  (pure, no ModelContext needed — `@Model` classes can be constructed and wired in memory).
- **`Domain/Services/WatchWorkoutIngestionService.swift`**: the body of
  `handleCompletedWatchWorkout` (dedup via `findSession(id:healthKitWorkoutId:)`,
  `WorkoutSession`/`WorkoutExercise`/`WorkoutSet` materialization, save, template update, and
  the `.workoutHistoryDidChange` post) moved into an `@MainActor final class
  WatchWorkoutIngestionService`, constructor-injected with `RoutineRepository` and
  `WorkoutSessionRepository` only (both Domain protocols — no concrete Data type dependency).
  It exposes `ingest(_:) -> Result` where `Result` reports `shouldAcknowledge` (false only when
  the SwiftData save itself failed, so the watch's pending buffer keeps retrying) and
  `templateWasUpdated` (so the caller knows to refetch). `RoutinesViewModel` still owns the
  `.watchWorkoutCompleted` NotificationCenter subscription and the two `watchSync` calls
  (`markPendingProcessed`/`acknowledgeWorkoutSaved`) — those depend on `watchSync`, which the
  service deliberately does not take as a dependency, since only `RoutineRepository`/
  `WorkoutSessionRepository` were needed to reproduce the ingestion logic itself. The service is
  constructed inside `RoutinesViewModel.init` from its own already-injected repositories — no
  `AppDependencies` or view changes needed.

Result: `RoutinesViewModel.swift` is now 484 lines (down from ~638), `SupersetEditor.swift` is
80 lines, `WatchWorkoutIngestionService.swift` is 192 lines — all under the 300-line guideline.
`CompletedWatchWorkout` (the watch-sync DTO) is defined in `Data/Sync/WatchModels.swift` but
referenced directly from `Domain/Services/WatchWorkoutIngestionService.swift`; this mirrors the
pre-existing precedent in `Domain/Interfaces/WatchSyncServicing.swift` (`pendingWorkouts() ->
[CompletedWatchWorkout]`), which already treats this Codable struct as a shared sync contract
type rather than a "concrete Data type" in the architectural sense.
