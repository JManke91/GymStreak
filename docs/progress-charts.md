# Progress Charts Feature

## Purpose

The progress charts feature allows users to track their exercise performance over time in the History tab. Users can view three metrics for any exercise they've completed in workouts: Max Weight, Estimated 1RM, and Total Volume.

## Architecture

### Data Flow

```
WorkoutHistoryView (History tab, "Progress" mode)
  → ExerciseProgressListView (lists exercises with history)
    → ExerciseProgressChartView (chart + controls)
      → ExerciseProgressViewModel (state management)
        → ExerciseProgressService (data fetching from SwiftData)
```

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
| ExerciseProgressViewModel | `ViewModels/ExerciseProgressViewModel.swift` | Manages timeframe, metric, data point selection state; computed display properties |
| ExerciseProgressModels | `Models/ExerciseProgressModels.swift` | Domain models: ChartTimeframe, ProgressMetric, ExerciseProgressDataPoint, ExerciseProgressData, SelectedDataPoint |
| ExerciseProgressService | `Services/ExerciseProgressService.swift` | Fetches and aggregates workout data from SwiftData by exercise and timeframe |

#### watchOS Target

No progress chart feature on watchOS. Watch app has real-time workout metrics only (elapsed time, heart rate, calories via MetricsView).

## Metrics

| Metric | Label (EN) | Label (DE) | Calculation |
|--------|-----------|-----------|-------------|
| Max Weight | Max Weight | Max. Gewicht | Highest weight lifted in any completed set during the session |
| Est. 1RM | Est. 1RM | Gesch. 1RM | Epley formula: weight × (1 + reps ÷ 30), best across all sets |
| Total Volume | Total Volume | Gesamtvolumen | Sum of (weight × reps) across all completed sets in the session |

## Chart Interaction

- **Timeframe selection**: 1W, 1M, 3M, 1Y, All — filters data and adapts X-axis date granularity
- **Metric switching**: Segmented picker switches chart data without reloading (all metrics pre-fetched)
- **Info popover**: ⓘ button next to metric picker shows metric description
- **Data point tap**: Tap on chart area finds nearest data point, shows floating annotation with exact value + date. Tap empty area to dismiss. Selection clears on metric/timeframe/exercise change.

## Axis Formatting

- **Y-axis**: Compact number formatting with "kg" unit (e.g., "85 kg", "1.2k kg")
- **X-axis**: Timeframe-adaptive date labels (days for 1W, weeks for 1M, months for 3M/1Y, months+year for All)
