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

**Still on the main actor, deliberately out of scope — tracked as P1.6 in
`docs/architecture-audit-2026-08.md`, which is the entry point for doing it:**
`ExerciseProgressService`'s
`compareWithPrevious(workout:)` (used by `SaveWorkoutView`, `WorkoutDetailView` and
`WorkoutAnalysisAggregator`) takes a caller-supplied main-context `WorkoutSession`, so it
cannot cross an actor boundary unchanged. It performs one unbounded fetch *per exercise*
via `previousPerformance` and is a stronger candidate than the chart ever was — but it is
a different call shape and a different fix.

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
| ExerciseProgressViewModel | `ViewModels/ExerciseProgressViewModel.swift` | `async load()` behind a generation counter; owns timeframe, metric, selection and the loaded snapshot; computed display properties |
| ExerciseProgressModels | `Domain/Models/ExerciseProgressModels.swift` | Domain values: ChartTimeframe, ProgressMetric, ExerciseProgressDataPoint, ExerciseProgressData, **ExerciseRecentSession**, **ExerciseProgressSnapshot**, SelectedDataPoint. The four that cross the actor boundary are explicitly `Sendable`. |
| ExerciseProgressAggregator | `Domain/Services/ExerciseProgressAggregator.swift` | **Pure, isolation-agnostic** chart + recent-session aggregation. `matches(_:exerciseId:exerciseName:nameIsUnique:)` resolves workout exercises to the chart target — an exact `exerciseId` match, OR a legacy row with `exerciseId == nil` whose name matches case-insensitively **and only when the name is unique in the live library**. Without the fallback, workouts logged before `WorkoutExercise.exerciseId` existed would be invisible and progress would look frozen; without the uniqueness gate, same-named equipment variants would double-count. |
| SwiftDataHistorySnapshotStore | `Data/History/SwiftDataHistorySnapshotStore.swift` | `@ModelActor` that performs the fetch and calls the aggregator off the main actor. `SwiftDataHistorySnapshotProvider.fetchExerciseProgress` is the `@concurrent` entry point. |
| ExerciseProgressService | `Data/Progress/ExerciseProgressService.swift` | No longer feeds the chart. Retains the main-actor comparison surface (`compareWithPrevious`, `previousPerformance`) used by the workout summary and detail screens. |

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

- **Timeframe selection**: 1W, 1M, 3M, 1Y, All — filters data and adapts X-axis date granularity. Changing it changes `viewModel.loadKey`, so `.task(id:)` cancels the in-flight load and starts a new one. The recent-session list is deliberately **all-time** and unaffected by the range, matching the pre-existing behaviour.
- **Metric switching**: Segmented picker switches chart data without reloading (all metrics pre-fetched)
- **Info popover**: ⓘ button next to metric picker shows metric description
- **Data point tap**: Tap on chart area finds nearest data point, shows floating annotation with exact value + date. Tap empty area to dismiss. Selection clears on metric/timeframe/exercise change.

## Axis Formatting

- **Y-axis**: Compact number formatting with "kg" unit (e.g., "85 kg", "1.2k kg")
- **X-axis**: Timeframe-adaptive date labels (days for 1W, weeks for 1M, months for 3M/1Y, months+year for All)
