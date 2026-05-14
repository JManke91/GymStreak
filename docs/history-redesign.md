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

### Derived concepts

Four new concepts were introduced to make the new UI meaningful on top of existing data:

| Concept | Source of truth | Where computed |
|---|---|---|
| **Workout type** (Push / Pull / Legs / Core / Full Body / Upper / Lower / Cardio / Other) | `Routine.name` — classified by substring match (EN+DE keywords). Drives the card chip color and the calendar dot color. No data stored. | `WorkoutType.classify(routineName:)` in `Models/WorkoutType.swift` |
| **Intensity** (0–100, "RPE ring") | `WorkoutSession.completionPercentage` (reused) — "how much of the planned work was actually completed." | Model computed property |
| **Weekly goal** (X of Y) | `UserDefaults` key `history.weeklyGoal`, defaults to **4**. | `HistoryStatsService.weeklyGoal` |
| **Personal Record** (per exercise, per session) | Computed on the fly from the full session history: a session earns a PR for exercise E if its max estimated 1RM (Epley) for E exceeds every earlier session's max for E. | `PersonalRecordService.computePRs(sessions:)` |
| **Exercise identity** (`exerciseId: UUID?`) | `WorkoutExercise.exerciseId` — links each workout exercise back to its `Exercise` library entry by ID. Used as the primary grouping/filtering key across all progress services (`stableKey`). Falls back to `exerciseName.lowercased()` for legacy data without an `exerciseId`. | `WorkoutExercise.stableKey` computed property |

### New services
- `HistoryStatsService` — WeekHero aggregation (completed count, volume, volume trend, streak weeks, PR count), month grouping, week-day strip, monthly totals. All pure functions on `[WorkoutSession]`.
- `PersonalRecordService` — Walks the session history chronologically and records a PR whenever a new per-exercise estimated-1RM maximum is reached. Returns `session.id → {prCount, prExerciseNames}`.
- `FortschrittAggregator` — Builds the Fortschritt list row models (`FortschrittExerciseModel`) by joining completed sessions with the **live `Exercise` library**. Inputs: `(sessions, liveExercises)`. Each `WorkoutExercise` is resolved to a live exercise by `exerciseId` (preferred) or by case-insensitive name (fallback for legacy data without an `exerciseId`). The name fallback is **only** used when the name is unique in the live library — if two live exercises share a name (e.g. "Biceps Curls" with dumbbell and barbell variants), an untagged legacy row is ambiguous and is dropped from both rows rather than misattributed. WorkoutExercises that don't resolve to any live entry are dropped — this is what keeps deleted exercises from leaking into the Progress tab. Per-exercise output: workout count, last performed date, trend % (first-to-last est-1RM), and a sparkline of session max-est-1RM values.
- `ExerciseProgressService.matches(_:exerciseId:exerciseName:nameIsUnique:)` — Shared static matcher used by `fetchProgressData`, `previousPerformance`, and `ExerciseProgressChartView.loadRecentSessions`. When an `exerciseId` is provided it accepts either an exact id match or, only if `nameIsUnique` is true, a legacy row whose `exerciseId` is `nil` and whose name matches case-insensitively. The companion instance method `isLiveNameUnique(_:)` queries the live `Exercise` table to compute the flag, ensuring same-named variants (different equipment) keep their progress separate.

### Data flow
```
ContentView
 └─ HistoryView (@ObservedObject viewModel: WorkoutViewModel,
                 @Query allExercises: [Exercise])
     ├─ loads viewModel.workoutHistory (already populated on app launch)
     ├─ refresh()  ← retriggered when sessions count OR exercise library changes
     │   ├─ PersonalRecordService.computePRs(sessions:) → [UUID: Int]
     │   └─ FortschrittAggregator.build(sessions:liveExercises:) → [FortschrittExerciseModel]
     │       (drops workout exercises that don't resolve to any live Exercise)
     ├─ TrainingsTabView
     │    ├─ WeekHeroView (HistoryStatsService.weekStats, weekDayStatuses)
     │    ├─ HistoryCalendarView (uses same session set)
     │    └─ Month-grouped list of WorkoutCardView → NavigationLink<UUID>
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

**Fortschritt tab:**
- `FortschrittExerciseRowView` — Muscle-group badge + name + count + last date + sparkline + trend %. Taps push `ExerciseProgressChartView`.
- `MusclePillView` — Horizontal-scroll filter pills with trend %.
- `FortschrittTabView` — Search bar + pills + grouped exercise rows.

**Detail views (redesigned):**
- `WorkoutDetailView` — Back button, type chip + date, routine name title, 4-metric stat grid, optional Apple Health banner (reads kcal async from HealthKit via `HKMetadataKeyExternalUUID`), notes section, per-exercise blocks via `WorkoutDetailExerciseBlock`. On appear, loads PRs + HealthKit kcal + a `[UUID: ExerciseComparisonResult]` dictionary via `ExerciseProgressService.compareWithPrevious(workout:)`, keyed by `WorkoutExercise.id`.
- `WorkoutDetailExerciseBlock` (`Views/History/Components/`) — Per-exercise card. Renders: title row (exercise name + optional PR/trophy badge + set count). Then either a comparison strip (when previous session exists) or a "First session" / "Erste Session" badge (when this is the user's first time performing the exercise). Then the sets grid: each set cell shows set number + weight (kg or "BW"/"KG") + reps, plus a `SetDeltaChip` below showing the change vs. the same set position last time. **No top-set highlight** — chat2 feedback called the previous tinted "best set" decoration cryptic; the comparison strip + per-set deltas are more actionable.
- `ExerciseComparisonStrip` — Inline strip rendered between exercise title and sets grid. Shows `vs. <prev date>` + `Top` delta chip (top-weight kg delta vs `previousPerformance.bestSet.weight`) + `Volume` delta chip (percentage delta vs `previousPerformance.totalVolume`).
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
Navigation uses `UUID`-based destinations to avoid requiring `@Model` classes to be `Hashable`. `HistoryView` registers:
- `.navigationDestination(for: UUID.self)` → `WorkoutDetailView`
- `.navigationDestination(for: ExerciseWithHistory.self)` → `ExerciseProgressChartView`

Cards wrap their content in `NavigationLink(value: ...)` and fire a light haptic via a `simultaneousGesture`.

### Localization
New keys live under the `history.*` prefix (plus `history.type.*` for workout-type labels). Both `de.lproj` and `en.lproj` are kept in sync.

## Watch target
**Unchanged.** This redesign is iOS-only. The watch app continues to use `WatchRoutinesViewModel` / `RoutineStore` for routine sync and `WatchConnectivity.transferUserInfo` to push completed workouts to iOS, where they become the `WorkoutSession` rows the new History tab renders.
