# Progress Charts Feature

## Purpose

The progress charts feature allows users to track their exercise performance over time in the History tab. Users can view three metrics for any exercise they've completed in workouts: Max Weight, Estimated 1RM, and Total Volume.

See also: [history-redesign.md](./history-redesign.md) — the History tab UI that hosts these charts.

## Architecture

### Data Flow

```
HistoryView (History tab)
  → FortschrittTabView ("Fortschritt" sub-tab, replaces old ExerciseProgressListView)
    → ExerciseProgressChartView (chart + controls — stat triple, metric tabs, range pills, recent-sessions list)
      → ExerciseProgressViewModel (async load + display state)
        → HistorySnapshotProviding  ── @concurrent hop ──▶  SwiftDataHistorySnapshotStore (@ModelActor)
                                                              → ExerciseProgressAggregator (pure Domain logic)
```

The screen renders exactly one boundary call, `fetchExerciseProgress(exerciseName:exerciseId:startDate:recentSessionLimit:)`,
which returns an `ExerciseProgressSnapshot` carrying both the chart series and the
recent-session list. Only immutable `Sendable` values cross back; no `@Model` and no
relationship walk survives on the main actor.

### Off-main loading (2026-08-13, audit P1.2)

Everything above the `@concurrent` line used to run **synchronously on the main actor**.
`ExerciseProgressViewModel.loadData()` had no `await` anywhere in its chain: it called
`ExerciseProgressService.fetchProgressData`, which issued an unbounded
`FetchDescriptor<WorkoutSession>` with **no** `relationshipKeyPathsForPrefetching` and
then walked `session.workoutExercisesList` → `setsList` per session (an N+1 fault per
row). It ran from `init`, on every range-pill tap and on every exercise switch. Because
nothing yielded, `isLoading = true; …; isLoading = false` could never be observed, so the
spinner was dead code. `ExerciseProgressChartView.loadRecentSessions()` added a *second*
unbounded scan by calling `workoutSessionRepository.fetchCompleted()` straight from the
View.

**Measured, not inferred:** with `@concurrent` removed from the new provider method,
`largeExerciseProgressBuildKeepsMainActorResponsive` (240 sessions × 5 exercises × 4 sets)
records a **307 ms** main-actor stall. With it, the delay stays under the 100 ms budget.
The build is green either way — see `docs/swift6-concurrency.md` §1 for why SE-0461 makes
that failure invisible to the compiler.

What changed:

- The aggregation moved verbatim into `Domain/Services/ExerciseProgressAggregator.swift`,
  isolation-agnostic so the `@ModelActor` can call it from its own executor.
- The fetch reuses `SwiftDataHistorySnapshotStore.fetchCompletedSessions()`, which is
  already prefetch-correct (it fetches `WorkoutExercise` with `[\.sets, \.workoutSession]`
  first to register the graph, then the sessions).
- `ExerciseProgressViewModel.load()` is `async`, driven by `.task(id: viewModel.loadKey)`
  in the View. Range pills and the exercise switcher now only mutate state.
- `ExerciseProgressChartView` no longer holds a repository or a progress service.
- `SessionCardView`'s `DateFormatter` and `RelativeDateTimeFormatter` were hoisted to
  `static let` (they were allocated per row per render — audit P2.7's first item, folded
  in because this change re-typed that row view anyway).

**Why the fetch is still unbounded, deliberately.** The chart window is applied in Swift
after the fetch rather than in the `FetchDescriptor`. Narrowing it would require a
comparison across the optional `WorkoutExercise.workoutSession` relationship inside the
warm-up pass's `#Predicate`. SwiftData does not document support for optional-chained
comparison or `??` in predicates, and the reported failure mode is *silently wrong
results* rather than a thrown `SwiftDataError.unsupportedPredicate` — a bad trade against
a proven fetch. The cost this finding was actually about (unbounded fetch + full
traversal *on the main actor*) is paid on the model actor's executor now. Date-bounding
the fetch remains available as a later optimisation if a large-history profile calls for it.

**Why it shares History's actor rather than getting its own.** A second `@ModelActor`
means a second `ModelContext` faulting in the same rows, and this screen is pushed from
the History tab, so that context is already warm. Sharing is safe because Swift actors
are reentrant *only at suspension points*: every method on the store is `async` but
contains no internal `await`, so each runs to completion before the next is dequeued.
That invariant is written on the store — breaking it would open an interleaving window on
the shared, non-`Sendable` `ModelContext`.

### The vs-previous comparison (2026-08-14, audit P1.6)

The other half of this file's surface — "how did this compare with last time?", shown on
the save sheet, the workout detail screen and inside the AI Coach's workout analysis — was
left on the main actor by P1.2 and is now off it too. It was the stronger candidate all
along:

```
SaveWorkoutView / WorkoutDetailView / WorkoutAnalysisViewModel
  → ExerciseProgressProviding (@MainActor)
    → ExerciseComparisonBuilder.makeLookup(workout:)          ── main actor, bounded
    → HistorySnapshotProviding  ── @concurrent hop ──▶  SwiftDataHistorySnapshotStore
                                                          → PreviousPerformanceResolver
    → ExerciseComparisonBuilder.build(workout:previousPerformances:)  ── main actor, bounded
```

What it was: `compareWithPrevious(workout:)` called `previousPerformance` **once per
exercise**, and each call issued its own unbounded `FetchDescriptor<WorkoutSession>` with
no `relationshipKeyPathsForPrefetching`, then walked every session's exercises and sets —
faulting one row at a time. Each call *also* fetched the entire `Exercise` library to
decide name uniqueness, and `compareWithPrevious` fetched it once more per exercise on top,
so an eight-exercise workout meant 8 unbounded session fetches and 16 full library scans,
synchronously on the main actor. Unlike the chart, nothing gated it: it ran every time a
workout was finished and every time a past workout was opened.

**Measured, not inferred:** with `@concurrent` removed from the new provider method,
`previousPerformanceLookupKeepsMainActorResponsive` records a **213 ms** main-actor stall
(240 sessions × 5 exercises × 4 sets, an eight-exercise lookup). With it, under the 100 ms
budget. Build green either way. Fourth case in the shared tripwire suite, third on the
History actor.

**Why the workout crosses as values, not as an id to re-fetch.** This was the reason P1.2
left the item alone: an `@ModelActor` cannot accept a main-context `@Model`, so the obvious
port — pass `WorkoutSession.id`, re-fetch inside the actor — does not work here. It was
investigated and rejected, not overlooked:

- The save sheet compares a workout the user has **not saved yet** (it is presented
  straight after `pauseForCompletion()`, and while that does call `save()` today, the
  correctness of a user-visible screen must not rest on that ordering).
- SwiftData does not document whether one `ModelContext` sees another's unsaved changes.
  An Apple DTS engineer reproduced inconsistent behaviour on forum thread 763487 and
  explicitly declined to say which is expected. `ModelContainer.mainContext` has
  `autosaveEnabled == true` (documented) but the firing *timing* is unspecified — "key
  lifecycle events" with no bound.
- `PersistentIdentifier` is the documented cross-context handle and would be the right
  tool for a saved object, but it carries the same trap from the other side:
  `PersistentIdentifier.isTemporary` is `true` until the origin context saves, and Apple
  documents that temporary ids "should not be used to create durable maps to a model".
- The failure mode is the deciding factor. A miss returns *no predecessor*, which the UI
  renders as "New exercise" — a confident false statement about the user's history, not a
  visible error.

So the split runs along the cost, not along the object: only the unbounded history scan
crosses. `PreviousPerformanceLookup` carries the workout as `Sendable` values, and the
bounded current-workout read stays with the caller, which already holds that graph faulted
in and is about to render every set of it anyway.

**Other things this closed:**

- One fetch replaces N. `PreviousPerformanceResolver` filters and sorts the candidate
  sessions once for the whole workout and counts library names once, over the shared
  prefetch-correct `CompletedSessionFetch.withFullGraph`.
- `withFullGraph` now prefetches `\.routine` as well. The resolver compares
  `session.routine?.id` per candidate, and without it the N+1 would simply have moved to
  the model actor instead of being removed.
- `ExerciseProgressService` no longer owns a `ModelContext`; it is a thin `@MainActor`
  seam over the boundary call between the two pure builders.
- `ExerciseComparisonResult` gained `workoutExerciseId`. All three callers previously
  paired results with exercises **positionally** — a `zip` in `WorkoutDetailView`, an
  index in `WorkoutAnalysisAggregator`, and `ForEach(id: \.exerciseName)` in
  `SaveWorkoutView`, which gave two rows the same identity whenever a routine trained the
  same exercise twice. All three now key on the id.
- `WorkoutAnalysisAggregator` no longer constructs `ExerciseProgressService` ad hoc,
  bypassing `AppDependencies`; it takes the resolved comparisons as a parameter.
- A failed lookup returns an **empty array**, not rows without a predecessor. The latter
  would badge every exercise "new". Pinned by
  `failedHistoryLookupYieldsNoRowsRatherThanFalseFirstTimeRows`.

**Two tradeoffs taken knowingly, so they are not re-litigated as oversights:**

- **The AI analysis resolves the comparison before its own gates.** `compareWithPrevious`
  used to sit *inside* `WorkoutAnalysisAggregator.buildInput`, after its three
  insufficient-data guards; it now runs first, in `WorkoutAnalysisViewModel`, because the
  aggregator is `@MainActor` and this is the half that must not be. A gated-out analysis
  therefore pays one off-main resolve. Acceptable: the guard that rejects most often — no
  previous same-routine session — is already evaluated by `prepareCoachState`, so the
  button the user tapped would not be visible without one.
- **`WorkoutDetailView` resolves the comparison twice** — once in `.task` for the
  per-exercise strips, once when "Ask the Coach" is tapped. Now that results are keyed by
  `workoutExerciseId`, the second could reuse the first, but only by making the analysis
  depend on a sibling `@State` load having succeeded: an empty dictionary is
  indistinguishable from "no history", so a failed strip load would silently downgrade the
  analysis to *insufficient data*. An independent resolve on an explicit tap is the safer
  trade, and the old code scanned twice as well — on the main actor.

**Deliberately not done.** `WorkoutAnalysisAggregator`'s own two unbounded main-actor
fetches (`findPreviousSession`, `detectNewPRs`) are untouched — they are audit P2.1, which
covers all four AI-coach aggregators together and is gated behind the AI opt-in.

### Components

#### iOS Target

| Component | File | Purpose |
|-----------|------|---------|
| ExerciseProgressChartView | `Views/Charts/ExerciseProgressChartView.swift` | Main chart view with timeframe picker, metric picker + info button, and interactive chart |
| ProgressChartContent | `Views/Charts/ExerciseProgressChartView.swift` | SwiftUI Charts rendering with line/point marks, axis formatting, tap overlay, and data point annotation |
| ExerciseSwitcherMenu | `Views/Charts/ExerciseProgressChartView.swift` | Toolbar dropdown to switch between exercises grouped by muscle |
| ChartTimeframePicker | `Views/Charts/ChartTimeframePicker.swift` | Segmented button row for timeframe selection (1W, 1M, 3M, 1Y, All) |
| ChartDataPointAnnotation | `Views/Charts/ChartDataPointAnnotation.swift` | Floating tooltip card showing exact value + date for a tapped data point |
| MetricInfoPopover | `Views/Charts/MetricInfoPopover.swift` | Popover explaining what the selected metric measures and how it's calculated |
| SummaryStatsView | `Views/Charts/ChartSupportViews.swift` | Three stat cards: Personal Record, Trend, Sessions |
| StatCard | `Views/Charts/ChartSupportViews.swift` | Reusable stat card with icon, value, and label |
| EmptyChartView | `Views/Charts/ChartSupportViews.swift` | Placeholder shown when no workout data exists |
| SessionCardView | `Views/Charts/ExerciseProgressChartView.swift` | One recent-session card; takes an `ExerciseRecentSession` value, never a `@Model` |
| ExerciseProgressViewModel | `ViewModels/ExerciseProgressViewModel.swift` | `async load()` behind a generation counter; owns timeframe, metric, selection and the loaded snapshot; computed display properties; owns the **P2 Pro gate** (which metric/window is locked, what a locked selection renders, which paywall it raises) |
| ChartGatingPolicy | `Domain/Services/ChartGatingPolicy.swift` | **Pure, isolation-agnostic.** Which metrics and windows the free tier may read, from `ProFeatureCaps` — plus the widest free window a lapsed user's chart clamps back to |
| ExerciseProgressModels | `Domain/Models/ExerciseProgressModels.swift` | Domain values: ChartTimeframe, ProgressMetric, ExerciseProgressDataPoint, ExerciseProgressData, **ExerciseRecentSession**, **ExerciseProgressSnapshot**, SelectedDataPoint. The four that cross the actor boundary are explicitly `Sendable`. |
| ExerciseProgressAggregator | `Domain/Services/ExerciseProgressAggregator.swift` | **Pure, isolation-agnostic** chart + recent-session aggregation. `matches(_:exerciseId:exerciseName:nameIsUnique:)` resolves workout exercises to the chart target — an exact `exerciseId` match, OR a legacy row with `exerciseId == nil` whose name matches case-insensitively **and only when the name is unique in the live library**. Without the fallback, workouts logged before `WorkoutExercise.exerciseId` existed would be invisible and progress would look frozen; without the uniqueness gate, same-named equipment variants would double-count. |
| SwiftDataHistorySnapshotStore | `Data/History/SwiftDataHistorySnapshotStore.swift` | `@ModelActor` that performs the fetch and calls the aggregator off the main actor. `SwiftDataHistorySnapshotProvider.fetchExerciseProgress` is the `@concurrent` entry point. |
| ExerciseProgressService | `Data/Progress/ExerciseProgressService.swift` | The vs-previous seam. Owns no `ModelContext`: `@MainActor` glue that runs `ExerciseComparisonBuilder` either side of one `@concurrent` boundary call. Does not feed the chart. |
| ExerciseComparisonBuilder | `Domain/Services/ExerciseComparisonBuilder.swift` | **Pure, isolation-agnostic.** `makeLookup` reduces the current workout to `Sendable` values; `build` assembles the comparison rows from it plus the resolved predecessors. Runs on the main actor because the workout may be uncommitted. |
| PreviousPerformanceResolver | `Domain/Services/PreviousPerformanceResolver.swift` | **Pure, isolation-agnostic.** Resolves every exercise of one workout against the most recent comparable session, in a single pass. Runs inside the model actor. |
| PreviousPerformanceLookup | `Domain/Models/PreviousPerformanceLookup.swift` | The `Sendable` request: `before`, `routineId`, and one `Query` per exercise. Carries the workout's identity across the actor boundary without a `@Model` or a re-fetch. |

#### watchOS Target

No progress chart feature on watchOS. Watch app has real-time workout metrics only (elapsed time, heart rate, calories via MetricsView).

## Metrics

### Counterweight-assisted exercises

Exercises can declare that their entered load is **counterweight assistance** rather than added
resistance (for example, Assisted Pull-Up). Lower assistance is progress. For a workout that has
a body-weight snapshot, effective load is `body weight − assistance`, and the normal max-load,
estimated-1RM, volume, and PR calculations use that effective value. If any point in an assisted
exercise's selected chart range lacks a snapshot, the chart safely falls back to a single
**Assistance** metric: lower is better and the trend is inverted. It never presents a fabricated
1RM or volume in that case.

| Metric | Label (EN) | Label (DE) | Calculation |
|--------|-----------|-----------|-------------|
| Max Weight | Max Weight | Max. Gewicht | Highest weight lifted in any completed set during the session |
| Est. 1RM | Est. 1RM | Gesch. 1RM | Epley formula: weight × (1 + reps ÷ 30), best across all sets |
| Total Volume | Total Volume | Gesamtvolumen | Sum of (weight × reps) across all completed sets in the session |

## Chart Interaction

- **Timeframe selection**: 1W, 1M, 3M, 1Y, All — filters data and adapts X-axis date granularity. Changing it changes `viewModel.loadKey` (via `chartTimeframe` — see "Pro gating" below), so `.task(id:)` cancels the in-flight load and starts a new one. The recent-session list is deliberately **all-time** and unaffected by the range, matching the pre-existing behaviour.
- **Metric switching**: Segmented picker switches chart data without reloading (all metrics pre-fetched)
- **Info popover**: ⓘ button next to metric picker shows metric description
- **Data point tap**: Tap on chart area finds nearest data point, shows floating annotation with exact value + date. Tap empty area to dismiss. Selection clears on metric/timeframe/exercise change.

## Axis Formatting

- **Y-axis**: Compact number formatting with "kg" unit (e.g., "85 kg", "1.2k kg")
- **X-axis**: Timeframe-adaptive date labels (days for 1W, weeks for 1M, months for 3M/1Y, months+year for All)

## Pro gating (P2)

While `ProGating.isEnabled` is `false` — which is how the app ships until ticket 15 of
`.scratch/pro-entitlements/` — **none of this is active and the screen behaves exactly as described
above**. With gating on, a free user reads max weight over 1W / 1M / 3M; estimated 1RM, total
volume, 1Y and All are Pro. The rules live in `ChartGatingPolicy` and the full rationale in
`docs/pro-subscription.md` §5d; what matters for this screen:

- The metric tabs and the range pills **stay interactive** while the chart is locked. Only the
  chart headline and the chart itself sit inside `.proLocked`, which disables what it blurs — a
  user who could not switch back would be trapped behind the blur.
- Selecting a Pro-only metric or window still *selects* it (the tab/pill highlights) and raises
  `.chartMetric` / `.chartWindow`. Locked options carry an `OnyxProBadge(style: .icon)` so the gate
  is honest before the tap.
- **A locked window is previewed, never fetched.** `loadKey` and `load()` key off
  `chartTimeframe`, not `selectedTimeframe`: while a Pro-only window is selected the chart keeps
  drawing the last window the user is entitled to, so the blurred preview costs exactly what the
  free path costs. A locked *metric* costs nothing either — every `ExerciseProgressDataPoint`
  already carries all three values from the one fetch.
- The PR and Trend stat cards fall back to the free metric while the selected one is locked, so no
  Pro number is printed in plain text beside the blurred chart.
- Entitlement changes are live: the gate reads the `@Observable` provider during `body`, so a
  purchase unblurs the chart and reloads the wider window through the existing `.task(id:)` with no
  refresh gesture, and a lapse blurs it and clamps the rendered window back to 3M. No workout,
  session or set is ever hidden in any entitlement state.
