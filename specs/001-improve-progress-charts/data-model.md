# Data Model: Improve Progress Charts UX

**Branch**: `001-improve-progress-charts` | **Date**: 2026-04-18

## Modified Entities

### ProgressMetric (enum — existing)

No new cases. Two new computed properties added:

| Property | Type | Description |
|----------|------|-------------|
| `localizedTitle` | `String` | **UPDATED** — "Max Weight", "Est. 1RM", "Total Volume" (EN); "Max. Gewicht", "Gesch. 1RM", "Gesamtvolumen" (DE) |
| `localizedDescription` | `String` | **NEW** — Brief explanation of what the metric measures and how it's calculated |
| `unit` | `String` | Unchanged — "kg" for all metrics |
| `axisLabel` | `String` | **NEW** — Y-axis label including unit, e.g., "kg" |

### ChartTimeframe (enum — existing)

One new computed property:

| Property | Type | Description |
|----------|------|-------------|
| `dateFormatStyle` | `Date.FormatStyle` | **NEW** — Returns locale-appropriate date format for X-axis labels based on timeframe |
| `axisStrideComponent` | `Calendar.Component` | **NEW** — Returns the appropriate Calendar.Component for axis mark stride |
| `axisStrideValue` | `Int` | **NEW** — Returns stride multiplier for the component |

## New Entities

### SelectedDataPoint (value type)

Represents the user's currently selected data point on the chart for tooltip display.

| Field | Type | Description |
|-------|------|-------------|
| `dataPoint` | `ExerciseProgressDataPoint` | The selected data point reference |
| `displayValue` | `String` | Pre-formatted display string (e.g., "85 kg", "1.2k kg") |
| `displayDate` | `String` | Pre-formatted date string (locale-aware) |

**Lifecycle**: Created on data point tap, replaced on new tap, set to `nil` on dismiss.

**Location**: Lives as `@Published var selectedDataPoint: SelectedDataPoint?` on `ExerciseProgressViewModel`.

## Unchanged Entities

- **ExerciseProgressDataPoint**: No changes. Already contains all metric values needed for tooltip display.
- **ExerciseProgressData**: No changes. Already provides `personalRecord`, `progressPercentage`, etc.
- **ExerciseProgressService**: No changes needed. Data fetching logic is unaffected.

## Localization Changes

### New Keys

| Key | EN | DE |
|-----|----|----|
| `chart.metric.max_weight` | "Max Weight" | "Max. Gewicht" |
| `chart.metric.estimated_1rm` | "Est. 1RM" | "Gesch. 1RM" |
| `chart.metric.volume` | "Total Volume" | "Gesamtvolumen" |
| `chart.metric.max_weight.description` | "The heaviest weight lifted in a single set during the session." | "Das schwerste Gewicht, das in einem einzelnen Satz während der Einheit gehoben wurde." |
| `chart.metric.estimated_1rm.description` | "Estimated one-rep max — the maximum weight you could lift once, calculated using the Epley formula (weight × (1 + reps ÷ 30))." | "Geschätztes Einer-Maximum — das maximale Gewicht, das du einmal heben könntest, berechnet mit der Epley-Formel (Gewicht × (1 + Wdh. ÷ 30))." |
| `chart.metric.volume.description` | "Total work performed — the sum of weight × reps across all sets in the session." | "Gesamte geleistete Arbeit — die Summe aus Gewicht × Wiederholungen über alle Sätze der Einheit." |
| `chart.tooltip.date_label` | "Date" | "Datum" |

### Updated Keys

| Key | Old EN | New EN | Old DE | New DE |
|-----|--------|--------|--------|--------|
| `chart.metric.volume` | "Volume" | "Total Volume" | "Volumen" | "Gesamtvolumen" |

Note: `chart.metric.max_weight` and `chart.metric.estimated_1rm` remain the same in EN. Only the Volume label changes.
