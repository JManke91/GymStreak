# History (Verlauf) Redesign

## What it is
A full redesign of the History tab that replaces the previous segmented list view with an editorial layout: a "this week" hero, month-grouped workout cards, a calendar view, a redesigned exercise progress section, and two redesigned detail screens.

Target: **iOS app only** (`GymStreak`). No changes to the watch target.

## How it works
- Tab 3 ("Verlauf") now renders `HistoryView` instead of the old `WorkoutHistoryView`. The old file was deleted.
- `HistoryView` hosts two sub-sections via a custom segmented control:
  - **Trainings** — `TrainingsTabView`: WeekHero + List / Calendar toggle + month-grouped workout cards.
  - **Fortschritt** — `FortschrittTabView`: Search + horizontal muscle-group pills + grouped exercise rows.
- All data is derived from existing SwiftData models (`WorkoutSession`, `WorkoutExercise`, `WorkoutSet`). **No schema migration.**
- Selecting a recorded workout pushes `WorkoutDetailView` through the tab's `NavigationStack`. The detail keeps the system navigation bar available with a transparent background, so iOS provides both its standard Back button and the leading-edge swipe-back gesture. The trailing toolbar item is an ellipsis menu holding **Edit** and a destructive **Delete** — see [Delete a Recorded Workout](./delete-workout.md).

### Navigation research

The fix uses SwiftUI's [`toolbar(_:for:)`](https://developer.apple.com/documentation/swiftui/view/toolbar(_:for:)) and [`toolbarBackground(_:for:)`](https://developer.apple.com/documentation/swiftui/view/toolbarbackground(_:for:)) APIs, both available from iOS 16. The app target is iOS 18.5+, so no availability fallback is needed. Restoring the destination navigation bar preserves the `NavigationStack` system Back control and its [`UINavigationController` interactive-pop gesture](https://developer.apple.com/documentation/uikit/uinavigationcontroller/interactivepopgesturerecognizer); a custom drag gesture or UIKit delegate workaround is deliberately not used.

### Derived concepts

Four new concepts were introduced to make the new UI meaningful on top of existing data:

| Concept | Source of truth | Where computed |
|---|---|---|
| **Workout type** (Push / Pull / Legs / Core / Full Body / Upper / Lower / Cardio / Other) | `Routine.name` — classified by substring match (EN+DE keywords). Drives the card chip color and the calendar dot color. No data stored. | `WorkoutType.classify(routineName:)` in `Models/WorkoutType.swift` |
| **Intensity** (0–100, "RPE ring") | `WorkoutSession.completionPercentage` (reused) — "how much of the planned work was actually completed." | Model computed property |
| **Weekly goal** (X of Y) | `UserDefaults` key `history.weeklyGoal`, defaults to **4**. | `HistoryStatsService.weeklyGoal` |
| **Personal Record** (per exercise, per session) | Computed on the fly from the full session history: a session earns a PR for exercise E if its max estimated 1RM (Epley) for E exceeds every earlier session's max for E. | `PersonalRecordService.computePRs(sessions:)` |
| **Exercise identity** (`exerciseId: UUID?`) | `WorkoutExercise.exerciseId` — links each workout exercise back to its `Exercise` library entry by ID. Used as the primary grouping/filtering key across all progress services (`stableKey`). Falls back to `exerciseName.lowercased()` for legacy data without an `exerciseId`. | `WorkoutExercise.stableKey` computed property |
| **Routine-slot identity** (`routineExerciseId: UUID?`) | Denormalized snapshot of the source `RoutineExercise.id`. Distinguishes repeated uses of the same exercise within one routine (for example a heavy slot and a later high-rep slot) without linking history back to the live template. Nil for legacy history and exercises added ad hoc during a workout. | `WorkoutExercise.routineExerciseId` |
| **Load behavior** | `Exercise.loadBehavior`, snapshotted on `WorkoutExercise`. `.resistance` means larger kg is harder; `.counterweightAssistance` means larger kg gives more help. | `ExerciseLoadMetrics` |

### New services
- `HistoryStatsService` — WeekHero aggregation (completed count, volume, volume trend, streak weeks, PR count), month grouping, week-day strip, monthly totals. All pure functions on `[WorkoutSession]`.
- `PersonalRecordService` — Walks the session history chronologically and records a PR whenever a new per-exercise estimated-1RM maximum is reached. Returns `session.id → prCount` plus `session.id → {WorkoutExercise.id → PRDetail}`. PR calculation remains exercise-wide, but the detail is keyed by the concrete workout occurrence containing the winning set so a repeated exercise renders the banner on only one card. `PRDetail` carries the occurrence id, achieving set id, weight, reps, new estimated 1RM, and previous best (nil on first-ever performance — a first performance counts as a PR). Consumers: `HistoryView` (counts for the list badges) and `WorkoutDetailView` (details).
- `FortschrittAggregator` — Builds the Fortschritt list row models (`FortschrittExerciseModel`) by joining completed sessions with the **live `Exercise` library**. Inputs: `(sessions, liveExercises)`. Each `WorkoutExercise` is resolved to a live exercise by `exerciseId` (preferred) or by case-insensitive name (fallback for legacy data without an `exerciseId`). The name fallback is **only** used when the name is unique in the live library — if two live exercises share a name (e.g. "Biceps Curls" with dumbbell and barbell variants), an untagged legacy row is ambiguous and is dropped from both rows rather than misattributed. WorkoutExercises that don't resolve to any live entry are dropped — this is what keeps deleted exercises from leaking into the Progress tab. Per-exercise output: workout count, last performed date, trend % (first-to-last est-1RM), and a sparkline of session max-est-1RM values.
- `ExerciseProgressAggregator.matches(_:exerciseId:exerciseName:nameIsUnique:)` — Shared exercise-level matcher used by charts and comparison candidate selection. (Moved out of `ExerciseProgressService` on 2026-08-13 with audit P1.2, so the pure `Domain/` aggregation can be called from the History model actor; see [progress-charts.md](./progress-charts.md).) When an `exerciseId` is provided it accepts either an exact id match or, only if `nameIsUnique` is true, a legacy row whose `exerciseId` is `nil` and whose name matches case-insensitively. The companion `isNameUnique(_:in:)` decides that from the live `Exercise` library, ensuring same-named variants (different equipment) keep their progress separate. `PreviousPerformanceResolver` then narrows those candidates by exact `routineExerciseId`; legacy nil-id rows fall back to the ordered occurrence among matching exercises in the same routine. (That resolver replaced `ExerciseProgressService.previousPerformance` on 2026-08-14 with audit P1.6, moving the scan onto the History model actor; it also gained a value-level `matches(candidateExerciseId:candidateExerciseName:...)` overload so the same rule applies to the current workout's exercises, which reach the actor as values.)

### Repeated exercises and historical repair (2026-07-12)

Workout-detail comparisons have two identity levels: `exerciseId` identifies the library exercise/equipment variant, while `routineExerciseId` identifies its programming slot. The root cause of the production `+7 kg` error was that history stored only `exerciseId`; when that exercise appeared twice, `previousPerformance` called `.first` on both matching rows and both current cards compared against the same previous occurrence. Relationship array order is not an identity and is not relied on.

New iPhone workouts snapshot `RoutineExercise.id` when creating `WorkoutExercise`. Watch payloads required no wire-format change: `WatchExercise.id` / `CompletedWatchExercise.id` already preserve that source slot UUID, and `WatchWorkoutIngestionService` now copies it into history. Swapping to an alternative preserves the slot UUID while `exerciseId` continues to describe what was actually performed.

Existing history cannot be safely backfilled because the live routine may have been reordered or edited. It is repaired at read time: candidates still require the correct exercise UUID/load behavior, then legacy rows are sorted by `order` and matched by occurrence index within the same routine. `WorkoutSession.routine.id` proves that routine context, so duplicate routine names stay separate and renames keep continuity. If the routine relationship no longer survives, name equality is not treated as identity and the comparison stays empty. Likewise, if a legacy row has no exercise UUID and its name is shared by multiple library exercises, it is excluded rather than guessed. Deliberately rejected: routine/exercise name keys (editable and non-unique display metadata), position as the permanent identity (breaks on reorder), and a destructive one-time backfill.

`routineExerciseId` is an additive optional SwiftData/CloudKit attribute with a nil default, so existing stores use lightweight migration and old records remain readable. Release requires initializing the Development CloudKit schema and deploying the added field to Production before shipping code that writes it. Sources: [Apple SwiftData CloudKit sync](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices), [automatic model migration](https://developer.apple.com/documentation/coredata/migrating-your-data-model-automatically).

### Data flow
```
ContentView
 └─ HistoryView (@ObservedObject WorkoutViewModel for lightweight invalidation/UI actions,
                 @State HistoryViewModel)
     ├─ .task(id: historyVersion) → HistorySnapshotProviding
     │   └─ SwiftDataHistorySnapshotProvider (detached off-main construction)
     │       └─ SwiftDataHistorySnapshotStore (@ModelActor, own ModelContext)
     │       ├─ prefetches completed session/exercise/set graph
     │       ├─ PersonalRecordService + HistorySnapshotBuilder → Sendable HistorySnapshot
     │       └─ FortschrittAggregator → Sendable [FortschrittExerciseModel]
     ├─ publishes values on MainActor; no @Model arrays cross the actor boundary
     ├─ TrainingsTabView
     │    ├─ WeekHeroView (precomputed values)
     │    ├─ HistoryCalendarView (precomputed cards/totals)
     │    └─ Month-grouped native NavigationLink<UUID> rows containing WorkoutCardView
     └─ FortschrittTabView
          └─ Grouped list of FortschrittExerciseRowView → NavigationLink<ExerciseWithHistory>

Navigation destinations (same stack):
 ├─ UUID (session.id) → WorkoutDetailView (redesigned)
 └─ ExerciseWithHistory → ExerciseProgressChartView (redesigned)
```

## Architecture

### Files added
```
GymStreak/Models/WorkoutType.swift
GymStreak/Services/HistoryStatsService.swift
GymStreak/Services/PersonalRecordService.swift
GymStreak/Services/FortschrittAggregator.swift
GymStreak/Views/History/HistoryView.swift
GymStreak/Views/History/TrainingsTabView.swift
GymStreak/Views/History/FortschrittTabView.swift
GymStreak/Views/History/WeekHeroView.swift
GymStreak/Views/History/WorkoutCardView.swift
GymStreak/Views/History/HistoryCalendarView.swift
GymStreak/Views/History/MusclePillView.swift
GymStreak/Views/History/FortschrittExerciseRowView.swift
GymStreak/Views/History/Components/WorkoutTypeChip.swift
GymStreak/Views/History/Components/HistoryRings.swift
GymStreak/Views/History/Components/MiniSparkline.swift
docs/history-redesign.md
```

### Files modified
```
GymStreak/ContentView.swift              — WorkoutHistoryView → HistoryView
GymStreak/WorkoutDetailView.swift        — Rewritten with new layout; now loads per-exercise comparison data
GymStreak/Views/History/Components/WorkoutDetailExerciseBlock.swift — Exercise block + ExerciseComparisonStrip + SetDeltaChip + FirstSessionBadge
GymStreak/Views/Charts/ExerciseProgressChartView.swift — Rewritten with new layout
GymStreak/Views/ExerciseProgressListView.swift         — Trimmed to the ExerciseWithHistory struct only
GymStreak/Resources/de.lproj/Localizable.strings       — New history.* keys
GymStreak/Resources/en.lproj/Localizable.strings       — New history.* keys
```

### Files deleted
```
GymStreak/WorkoutHistoryView.swift   — Replaced by HistoryView
```

### Components

**Reusable primitives (under `Views/History/Components/`):**
- `WorkoutTypeChip` — Uppercased pill chip colored by `WorkoutType`.
- `IntensityRing` — 0–100 ring with numeric value & "RPE" label. Used on workout cards.
- `MiniActivityRing` — Small goal ring used in WeekHero (behind the flame icon).
- `MiniSparkline` — Canvas-based line+area sparkline used on exercise rows.

**Trainings tab:**
- `WeekHeroView` — Hero card: "Diese Woche", completed/goal headline, weekday strip with done/today/empty states, streak/volume/PR stats.
- `WorkoutCardView` — Date block + routine name + type chip + optional PR badge + metrics row + intensity ring. Tapping pushes `WorkoutDetailView`.
- `HistoryCalendarView` — Month grid (Monday-first, German locale). Prev/next navigation, dots colored by `WorkoutType`, today ring, selected-day fill, selected-day detail card below.
- `TrainingsTabView` — Composes WeekHero, list/calendar segmented toggle, and month-grouped list.

**Rendering: the screen renders a precomputed snapshot (2026-07-26).** `HistoryViewModel` owns a
`HistorySnapshot` fetched through the injected `HistorySnapshotProviding` boundary.
`SwiftDataHistorySnapshotStore` is a Data-layer `@ModelActor`: it fetches and aggregates on its
own model executor and returns only immutable `Sendable` values. It must be reached through
`SwiftDataHistorySnapshotProvider`, whose detached task constructs only the stable actor outside
inherited MainActor isolation; constructing the model actor in MainActor-isolated
`AppDependencies` ran this workload on the UI thread in testing. `TrainingsTabView`,
`WorkoutCardView` and `HistoryCalendarView` render values and derive nothing. The binding rules,
each of which this screen violated and hung because of it — see
[history-performance.md](./history-performance.md):

- **Rows take `WorkoutCardModel`, never `WorkoutSession`.** Reading `totalVolume`,
  `completedSetsCount` or `completionPercentage` off the `@Model` walks the whole
  `workoutExercises → sets` graph; those three reads were four traversals per card, re-paid on
  every lazy re-realisation. Use `WorkoutSession.aggregates` (one pass) if you need them at all.
- **The Trainings list is ONE flat `LazyVStack`** over pre-interleaved `HistoryListRow`s. Do not
  nest a `LazyVStack` inside a `LazyVStack` — undocumented, with reported stutter and a
  reproducible hang. No `Section`/`pinnedViews`, so month dividers stay inline.
- **Nothing fetches or aggregates on MainActor.** Anything that walks the session list belongs
  behind `SwiftDataHistorySnapshotStore`, triggered by the section-specific `.task(id:)` calls.
- **Fortschritt's UI projection is cached.** `FortschrittListViewModel` rebuilds search results,
  group statistics, navigation payloads and flat rows only when its exercise snapshot, query or
  selected group changes; those collection operations never execute from SwiftUI `body`.
- **No SwiftData model crosses the actor boundary.** Navigation and deletion carry a session UUID;
  the main-context repository resolves that one model only at the action boundary.
- The snapshot token includes the current local day and is updated both at the next day boundary
  and whenever the app becomes active, keeping week/calendar/month-derived values current.
- AI-coach preferences, availability and proactive prompt state enter through injected Domain
  protocols; `HistoryView` and `TrainingsTabView` do not reach Data-layer singletons.
- Every `DateFormatter` / `RelativeDateTimeFormatter` here is a `static let`.
- `List` was reconsidered and deferred, not rejected — see history-performance.md §6.

**Fortschritt tab:**
- `FortschrittExerciseRowView` — Muscle-group badge + name + count + last date + sparkline + trend %. Taps push `ExerciseProgressChartView`.
- `MusclePillView` — Horizontal-scroll filter pills with trend %.
- `FortschrittTabView` — Search bar + pills + grouped exercise rows.

**Detail views (redesigned):**
- `WorkoutDetailView` — System Back button with native leading-edge swipe-back, type chip + date, routine name title, the muscle map card (see [Muscle Map](./muscle-map.md)), 4-metric stat grid, optional Apple Health banner (reads kcal async from HealthKit via `HKMetadataKeyExternalUUID`), notes section, per-exercise blocks via `WorkoutDetailExerciseBlock`. The transparent navigation bar keeps the editorial canvas while preserving the native navigation interaction; the trailing toolbar item is an ellipsis **Menu** holding Edit and a destructive Delete (see [Delete a Recorded Workout](./delete-workout.md)). On appear, loads PR details (`[WorkoutExercise.id: PRDetail]` for this session) + HealthKit kcal + a `[UUID: ExerciseComparisonResult]` dictionary via `await ExerciseProgressService.compareWithPrevious(workout:)`, both keyed by the concrete `WorkoutExercise.id` — the comparison dictionary now from each result's own `workoutExerciseId` rather than a positional `zip` (audit P1.6). This prevents one exercise-wide PR from rendering on every repeated occurrence.
- `MuscleMapCardView` (`Views/History/Components/`) — "Trainierte Muskelgruppen": front and back schematic bodies with this workout's trained regions lit in the accent, plus a primary/secondary legend. Sits between the header and the stat grid. Takes a finished `MuscleMapCardModel` that `WorkoutDetailView` builds once in `loadMuscleMap()`; the aggregation walks `workoutExercises → sets` and must never run from `body`. The `ScrollView`'s `.defaultScrollAnchor(.top)` exists because of this card — see [Muscle Map](./muscle-map.md).
- `WorkoutDetailExerciseBlock` (`Views/History/Components/`) — Per-exercise card. Takes `prDetail: PersonalRecordService.PRDetail?`. Renders: title row (exercise name + optional PR/trophy badge + set count). When `prDetail` is present, a gold **PR record banner** (`PRRecordStrip`, own file in `Views/History/Components/`) follows: trophy + "New record: 87.5 kg × 8" / "Neuer Rekord: …" plus a secondary line "est. 1RM 111 kg · previous best 105 kg" (previous part omitted on first-ever performance). Then either a comparison strip (when previous session exists) or a "First session" badge. Then the sets grid: each set cell shows set number + weight (kg or "BW"/"KG") + reps, plus a `SetDeltaChip` below; the **set that achieved the PR** gets a gold treatment (mini trophy next to the set label, gold-tinted background + border, VoiceOver appends "new personal record"). Note: an older tinted "best set" decoration was removed as cryptic (chat2 feedback) — the PR-set highlight is different and deliberate: it marks only genuine records and is explained by the adjacent record banner (user request 2026-07-08). PR gold is the shared `DesignSystem.Colors.pr` token (also used by `WorkoutCardView`).
- `ExerciseComparisonStrip` — Inline strip rendered between exercise title and sets grid. Shows `vs. <prev date>` + `Top` delta chip (top-weight kg delta vs `previousPerformance.bestSet.weight`) + `Volume` delta chip (percentage delta vs `previousPerformance.totalVolume`). The previous performance comes from the same routine slot; legacy workouts use the conservative same-routine occurrence fallback above.
- `SetDeltaChip` — Capsule chip with SF Symbol arrow + value. Four states: `.gain("+2.5 kg")` (success green), `.loss("−5 kg")` (destructive red), `.neutral` (= symbol, no label), `.new` (sparkles + "New"/"Neu" for set positions with no previous counterpart). Weight delta wins over reps delta; reps delta only shown if weight matched exactly. Values use `.contentTransition(.numericText())` for animated number changes. Each set cell exposes VoiceOver via `accessibilityLabel` ("Set 2") + `accessibilityValue` ("85 kg, 8 reps, up 2.5 kilograms from last time") so the chip itself stays decorative.
- `FirstSessionBadge` — Small indigo capsule with sparkles icon + localized "First session" / "Erste Session" label, shown when `ExerciseComparisonResult.isFirstTime` is true.
- `ExerciseProgressChartView` — Back + switch-exercise menu, muscle-group label + exercise name, 3-stat triple (PR/Trend/Workouts), chart card (metric tabs + headline + line chart + range selector pills), "Letzte Sätze" session list.

### User decisions baked in
- **Workout type**: classified by routine name only (substring match, EN+DE keywords).
- **Intensity**: `WorkoutSession.completionPercentage`.
- **Weekly goal**: hardcoded 4 (overridable via `UserDefaults.history.weeklyGoal`).
- **Week strip**: past = filled-if-workout, today = ring, future = empty. No "planned" / "rest" distinction.
- **PRs**: computed on the fly; no new stored fields.
- **Notes**: per-session notes only (existing `WorkoutSession.notes`), no per-exercise notes.

### HealthKit integration
`WorkoutDetailView` reads `activeEnergyBurned` back from HealthKit using the stored `WorkoutSession.healthKitWorkoutId` via `HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, ...)`. If the read fails or no value is found, the banner falls back to showing just the minutes.

### Navigation notes
Navigation uses `UUID`-based destinations to avoid requiring `@Model` classes to be `Hashable`. The stack is **path-bound** — `NavigationStack(path: $path)` over a type-erased `NavigationPath`, because the Trainings list cards push programmatically (see below) while everything else pushes by link. Every destination is value-based; do not add an `.navigationDestination(isPresented:)` here, since an `isPresented` push is not represented in the path and the two views of the same stack can then disagree. `HistoryView` registers:
- `.navigationDestination(for: UUID.self)` → `WorkoutDetailView`
- `.navigationDestination(for: ExerciseWithHistory.self)` → `ExerciseProgressChartView`
- `.navigationDestination(for: PeriodRecapDestination.self)` → `PeriodRecapView`

(The AI Coach settings destination was removed in 2026-08 together with the header's gear
button — those settings now live in the Settings tab, see [Settings Tab](./settings-tab.md).)

Cards use `NavigationLink(value: ...)` and lightweight values. Trainings rows navigate with `UUID`; `HistoryView` resolves the `WorkoutSession` at the destination boundary. This restores native navigation, focus and accessibility semantics and avoids the custom per-row swipe interaction that caused the post-1.1.5 responsiveness regression. The list keeps a long-press context-menu delete shortcut, while the workout detail screen provides the visible delete route. See [Delete a Recorded Workout](./delete-workout.md).

### Localization
New keys live under the `history.*` prefix (plus `history.type.*` for workout-type labels). Both `de.lproj` and `en.lproj` are kept in sync.

## Watch target
**Unchanged.** This redesign is iOS-only. The watch app continues to use `WatchRoutinesViewModel` / `RoutineStore` for routine sync and `WatchConnectivity.transferUserInfo` to push completed workouts to iOS, where they become the `WorkoutSession` rows the new History tab renders.
