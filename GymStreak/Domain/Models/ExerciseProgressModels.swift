//
//  ExerciseProgressModels.swift
//  GymStreak
//

import Foundation

// Note: String+Localization.swift extension provides .localized property

// MARK: - Chart Timeframe

enum ChartTimeframe: String, CaseIterable, Identifiable {
    case week = "1W"
    case month = "1M"
    case threeMonths = "3M"
    case year = "1Y"
    case all = "All"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .week: return "chart.timeframe.week".localized
        case .month: return "chart.timeframe.month".localized
        case .threeMonths: return "chart.timeframe.three_months".localized
        case .year: return "chart.timeframe.year".localized
        case .all: return "chart.timeframe.all".localized
        }
    }

    var axisStrideComponent: Calendar.Component {
        switch self {
        case .week: return .day
        case .month: return .weekOfYear
        case .threeMonths: return .month
        case .year: return .month
        case .all: return .month
        }
    }

    var axisStrideValue: Int {
        switch self {
        case .week: return 1
        case .month: return 1
        case .threeMonths: return 1
        case .year: return 2
        case .all: return 3
        }
    }

    var startDate: Date { startDate(from: Date()) }

    /// The window's lower bound relative to a given "now".
    ///
    /// Injectable so the rules built on it stay pure functions of their arguments —
    /// `ChartGatingPolicy.narrowestUnlockedTimeframe` compares against this, and a rule
    /// that reads the clock internally cannot be pinned at its boundaries.
    func startDate(from now: Date) -> Date {
        let calendar = Calendar.current

        switch self {
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: now) ?? now
        case .all:
            return Date.distantPast
        }
    }
}

// MARK: - Progress Metric

enum ProgressMetric: String, CaseIterable, Identifiable {
    case maxWeight
    case estimated1RM
    case volume

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .maxWeight: return "chart.metric.max_weight".localized
        case .estimated1RM: return "chart.metric.estimated_1rm".localized
        case .volume: return "chart.metric.volume".localized
        }
    }

    /// What kind of quantity the metric measures.
    ///
    /// This used to return the literal `"kg"`, which made `Domain/` the layer
    /// that decided the user's unit. It names the *quantity* now and the
    /// Presentation layer resolves the word — the same discipline
    /// `RoutineMetricsService` was put under. Both cases are masses read in the
    /// user's weight unit; they differ in magnitude, which is what decides
    /// whether the display rolls up to tonnes.
    var quantity: ProgressQuantity {
        switch self {
        case .maxWeight, .estimated1RM: return .weight
        case .volume: return .volume
        }
    }

    var localizedDescription: String {
        switch self {
        case .maxWeight: return "chart.metric.max_weight.description".localized
        case .estimated1RM: return "chart.metric.estimated_1rm.description".localized
        case .volume: return "chart.metric.volume.description".localized
        }
    }
}

/// The kind of number a `ProgressMetric` plots.
enum ProgressQuantity: Sendable {
    /// A single load — a top set, an estimated 1RM. Rendered at the unit's own
    /// display precision.
    case weight
    /// Summed weight × reps. Large enough to roll up, so it goes through
    /// `WeightFormatting.volume(_:in:)`.
    case volume
}

// MARK: - Compact Number Formatting

/// Formats a number using compact notation (e.g., 1.2k, 3.5M).
///
/// The k/M thresholds are magnitude-based, not kilogram-based, so they hold for a
/// converted pound figure too — 27 563 lb compacts to "27.6k" exactly as 12 500 kg
/// compacts to "12.5k".
///
/// Its one caller is the chart's **unit-less** y-axis. The optional `unit:` suffix
/// it used to take is gone: appending a unit word here would put back in `Domain/`
/// the decision that removing `ProgressMetric.unit` took out of it.
func formatCompactValue(_ value: Double) -> String {
    let formatted: String
    switch abs(value) {
    case 0..<1:
        formatted = String(format: "%.1f", value)
    case 1..<1_000:
        formatted = String(format: "%.0f", value)
    case 1_000..<1_000_000:
        let k = value / 1_000
        formatted = k.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0fk", k)
            : String(format: "%.1fk", k)
    default:
        let m = value / 1_000_000
        formatted = m.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0fM", m)
            : String(format: "%.1fM", m)
    }
    return formatted
}

// MARK: - Exercise Progress Data Point

struct ExerciseProgressDataPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let maxWeight: Double
    let estimated1RM: Double
    let totalVolume: Double
    let totalSets: Int
    let totalReps: Int
    let workoutSessionId: UUID

    /// Get the value for a specific metric
    func value(for metric: ProgressMetric) -> Double {
        switch metric {
        case .maxWeight: return maxWeight
        case .estimated1RM: return estimated1RM
        case .volume: return totalVolume
        }
    }
}

// MARK: - Exercise Progress Data

struct ExerciseProgressData: Sendable {
    let exerciseName: String
    let dataPoints: [ExerciseProgressDataPoint]
    let loadBehavior: ExerciseLoadBehavior
    /// Assistance workouts only expose effective-load strength metrics when
    /// every point has a stored body-mass snapshot.
    let usesEffectiveLoad: Bool

    init(
        exerciseName: String,
        dataPoints: [ExerciseProgressDataPoint],
        loadBehavior: ExerciseLoadBehavior = .resistance,
        usesEffectiveLoad: Bool = false
    ) {
        self.exerciseName = exerciseName
        self.dataPoints = dataPoints
        self.loadBehavior = loadBehavior
        self.usesEffectiveLoad = usesEffectiveLoad
    }

    /// Personal record (highest max weight achieved)
    var personalRecord: Double? {
        loadBehavior.isCounterweightAssistance && !usesEffectiveLoad
            ? dataPoints.map(\.maxWeight).min()
            : dataPoints.map(\.maxWeight).max()
    }

    /// Personal record for estimated 1RM
    var personalRecord1RM: Double? {
        dataPoints.map(\.estimated1RM).max()
    }

    /// Progress percentage comparing first and last data points for a given metric
    func progressPercentage(for metric: ProgressMetric) -> Double? {
        guard dataPoints.count >= 2,
              let first = dataPoints.first,
              let last = dataPoints.last else {
            return nil
        }

        let firstValue = first.value(for: metric)
        let lastValue = last.value(for: metric)

        guard firstValue > 0 else { return nil }

        let delta = loadBehavior.isCounterweightAssistance && !usesEffectiveLoad
            ? firstValue - lastValue
            : lastValue - firstValue
        return (delta / firstValue) * 100
    }

    /// Total number of sessions/workouts
    var sessionCount: Int {
        dataPoints.count
    }

    /// Check if there's enough data to show a chart
    var hasEnoughData: Bool {
        dataPoints.count >= 1
    }

    /// Check if there's enough data to show a trend
    var hasEnoughDataForTrend: Bool {
        dataPoints.count >= 2
    }
}

// MARK: - Exercise Recent Usage

/// One card of the exercise detail's "recent sets" list: the completed sets of **one
/// usage** within one completed workout.
///
/// A workout that trained the exercise twice — the heavy/light pairing this feature
/// exists for — contributes two of these, so a card is no longer one-to-one with a
/// session. The list is still capped by *sessions* (`recentSessionLimit`), never by cards.
///
/// A denormalized value, not a `WorkoutSession`: it is built inside
/// `SwiftDataHistorySnapshotStore`'s model actor and crosses back to the main
/// actor, so no `PersistentModel` and no relationship walk may survive in it.
struct ExerciseRecentUsage: Identifiable, Sendable {
    /// The originating `WorkoutExercise.id` — stable across reloads, and unique per
    /// card even when one workout contributes several.
    let id: UUID
    /// The workout these sets belong to. Shared by every card of the same session.
    let workoutSessionId: UUID
    let date: Date
    let usage: ExerciseUsage
    let sets: [SetEntry]
    /// How the exercise is loaded, taken from the live library by the aggregator — the
    /// same value the chart above filters and inverts on. It is here so `bestSet` can
    /// invert with it; without it the card's "Best" line named the *most*-assisted set of
    /// a counterweight-assisted exercise, i.e. the worst one, directly under a chart
    /// whose record card said the opposite.
    let loadBehavior: ExerciseLoadBehavior

    init(
        id: UUID,
        workoutSessionId: UUID,
        date: Date,
        usage: ExerciseUsage,
        sets: [SetEntry],
        loadBehavior: ExerciseLoadBehavior = .resistance
    ) {
        self.id = id
        self.workoutSessionId = workoutSessionId
        self.date = date
        self.usage = usage
        self.sets = sets
        self.loadBehavior = loadBehavior
    }

    struct SetEntry: Identifiable, Sendable {
        let id: UUID
        let weight: Double
        let reps: Int
    }

    /// The best set of this block — the heaviest, or the **least assisted** on a
    /// counterweight-assisted exercise, where a lower number on the machine is the
    /// better set. Within one card every set shares the workout's body-mass snapshot, so
    /// the least-assisted set is also the highest effective load whether or not the
    /// series is expressed as effective load.
    var bestSet: SetEntry? {
        loadBehavior.isCounterweightAssistance
            ? sets.min(by: { $0.weight < $1.weight })
            : sets.max(by: { $0.weight < $1.weight })
    }
}

// MARK: - Unattributable Legacy History

/// Completed workouts that name this exercise but carry no `exerciseId`, at a moment
/// where the name alone cannot say which library exercise they mean.
///
/// `WorkoutExercise.exerciseId` did not always exist. Rows recorded before it are
/// matched to the live library **by name**, and only while that name is unique — two
/// live "Biceps Curls" (barbell and dumbbell) make every such row ambiguous, and an
/// ambiguous row is dropped from every progress surface rather than guessed onto one
/// variant. Guessing would silently rewrite what the user trained; dropping only
/// omits it. Both are bad, but only one is recoverable.
///
/// This value is what makes the omission visible: it is non-`nil` only where rows were
/// actually dropped for ambiguity, and it carries what the screen needs to say so in a
/// sentence. Resolution is the user's — see `LegacyHistoryAttributing`.
struct UnattributedLegacyHistory: Sendable, Equatable {
    /// How many completed workouts would join the charted history once attributed.
    /// Counts **sessions holding at least one completed set**, not rows: a session
    /// whose only matching row was left uncompleted never renders anywhere, so
    /// promising it would be a second wrong number.
    let sessionCount: Int
    /// Oldest and newest of those workouts, so the copy can name a period rather than
    /// an abstract count.
    let earliest: Date
    let latest: Date

    /// A `Date.FormatStyle`, not a `DateFormatter`: this is isolation-agnostic Domain
    /// code, and a `static let DateFormatter` is not `Sendable`. Year-bearing on
    /// purpose — these workouts are old, and that is the whole point of naming them.
    private static let monthYearStyle = Date.FormatStyle.dateTime.month(.abbreviated).year()

    /// "Mär 2024 – Jul 2025", or a single month where both ends fall in one.
    ///
    /// Which period the missing workouts come from is what lets the user decide *which*
    /// exercise they were: "back then I only had the barbell". Read by the ViewModel
    /// when it composes the banner copy, never from a view body.
    var periodText: String {
        let from = earliest.formatted(Self.monthYearStyle)
        let to = latest.formatted(Self.monthYearStyle)
        return from == to ? from : "\(from) – \(to)"
    }
}

// MARK: - Exercise Progress Snapshot

/// Everything the exercise detail screen renders, built in a single pass over one
/// prefetched session graph.
///
/// The chart series and the recent-sets list are returned together deliberately:
/// they read the same fetch, and shipping them as two boundary calls would mean two
/// unbounded fetches plus a chance for the two halves of one screen to disagree.
struct ExerciseProgressSnapshot: Sendable {
    let data: ExerciseProgressData
    let recentUsages: [ExerciseRecentUsage]
    /// Every usage found in **all completed history**, newest-trained first. Drives the
    /// picker; independent of both `selectedUsage` and the charted window, so neither
    /// choosing a usage nor switching timeframe reshuffles the menu under the user.
    let availableUsages: [ExerciseUsageOption]
    /// The selection the two halves above were actually built with. The caller asks
    /// for one (or for nothing at all, on first open) and is told what it got — a
    /// requested usage is always kept, and a window holding no rows for it draws the
    /// empty chart rather than swapping the user's choice.
    let selectedUsage: ExerciseUsageSelection
    /// Legacy history this exercise's name matches but which stayed out of everything
    /// above, because the name is shared with another live exercise. `nil` whenever
    /// there is nothing being withheld — the overwhelmingly common case.
    let unattributedLegacy: UnattributedLegacyHistory?

    init(
        data: ExerciseProgressData,
        recentUsages: [ExerciseRecentUsage],
        availableUsages: [ExerciseUsageOption] = [],
        selectedUsage: ExerciseUsageSelection = .combined,
        unattributedLegacy: UnattributedLegacyHistory? = nil
    ) {
        self.data = data
        self.recentUsages = recentUsages
        self.availableUsages = availableUsages
        self.selectedUsage = selectedUsage
        self.unattributedLegacy = unattributedLegacy
    }
}

// MARK: - Selected Data Point

struct SelectedDataPoint {
    let dataPoint: ExerciseProgressDataPoint
    let displayValue: String
    let displayDate: String
}

// MARK: - Previous Exercise Performance

/// What the user did the last comparable time they performed one exercise.
///
/// `Sendable` because it is resolved inside `SwiftDataHistorySnapshotStore`'s model actor
/// and crosses back to the main actor (audit P1.6) — no `PersistentModel` and no
/// relationship walk may survive in it.
struct PreviousExercisePerformance: Sendable {
    let date: Date
    let routineName: String
    let sets: [SetPerformance]
    let effectiveTotalVolume: Double?

    struct SetPerformance: Sendable {
        let reps: Int
        let weight: Double
        let isCompleted: Bool
    }

    /// Best set by weight from the previous workout
    var bestSet: SetPerformance? {
        sets.filter(\.isCompleted).max(by: { $0.weight < $1.weight })
    }

    /// Total volume from the previous workout
    var totalVolume: Double {
        sets.filter(\.isCompleted).reduce(0) { $0 + ($1.weight * Double($1.reps)) }
    }

    /// Total completed sets
    var completedSetsCount: Int {
        sets.filter(\.isCompleted).count
    }

    /// Total reps from completed sets
    var totalReps: Int {
        sets.filter(\.isCompleted).reduce(0) { $0 + $1.reps }
    }
}

// MARK: - Exercise Comparison Result

struct ExerciseComparisonResult {
    /// The `WorkoutExercise.id` this row describes.
    ///
    /// Callers used to pair results with exercises **positionally** (a `zip`, or an
    /// index into the results array), which silently mispairs the moment the two
    /// orderings diverge, and cannot key a `ForEach` for a workout that contains the
    /// same exercise twice. Carrying the id makes the pairing explicit.
    let workoutExerciseId: UUID
    let exerciseName: String
    let loadBehavior: ExerciseLoadBehavior
    let currentPerformance: CurrentExercisePerformance
    let previousPerformance: PreviousExercisePerformance?

    struct CurrentExercisePerformance {
        let sets: [SetComparison]
        let totalVolume: Double
        let effectiveTotalVolume: Double?
        let completedSetsCount: Int
        let totalReps: Int

        struct SetComparison {
            let setNumber: Int
            let currentReps: Int
            let currentWeight: Double
            let previousReps: Int?
            let previousWeight: Double?
            let isCompleted: Bool

            var repsDelta: Int? {
                guard let previous = previousReps else { return nil }
                return currentReps - previous
            }

            var weightDelta: Double? {
                guard let previous = previousWeight else { return nil }
                return currentWeight - previous
            }
        }
    }

    /// Whether this is the first time performing this exercise
    var isFirstTime: Bool {
        previousPerformance == nil
    }

    var hasComparableVolume: Bool {
        guard let previousPerformance else { return false }
        return currentPerformance.effectiveTotalVolume != nil && previousPerformance.effectiveTotalVolume != nil
    }

    /// Volume change compared to previous
    var volumeDelta: Double? {
        guard let previous = previousPerformance,
              let currentVolume = currentPerformance.effectiveTotalVolume,
              let previousVolume = previous.effectiveTotalVolume else { return nil }
        return currentVolume - previousVolume
    }

    /// Volume change percentage
    var volumeDeltaPercentage: Double? {
        guard let previous = previousPerformance,
              let currentVolume = currentPerformance.effectiveTotalVolume,
              let previousVolume = previous.effectiveTotalVolume,
              previousVolume > 0 else { return nil }
        return ((currentVolume - previousVolume) / previousVolume) * 100
    }
}
