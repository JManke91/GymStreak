//
//  WorkoutDetailExerciseBlock.swift
//  GymStreak
//
//  Exercise block for the workout history detail view.
//  Shows the per-set breakdown plus a comparison strip vs. the previous
//  time the user performed the same exercise (top-weight & volume deltas),
//  per-set delta chips, and a "First session" badge for first-timers.
//

import SwiftUI

struct WorkoutDetailExerciseBlock: View {
    /// Pre-resolved block content — see WorkoutDetailExerciseDisplay. The block
    /// draws from this alone; it never reads a `WorkoutExercise`.
    let display: WorkoutDetailExerciseDisplay
    let prDetail: PersonalRecordService.PRDetail?
    let comparison: ExerciseComparisonResult?
    @Environment(\.weightUnit) private var weightUnit

    private var setComparisons: [ExerciseComparisonResult.CurrentExercisePerformance.SetComparison] {
        comparison?.currentPerformance.sets ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleRow
            if let prDetail {
                PRRecordStrip(detail: prDetail)
            }
            if let comparison, let previous = comparison.previousPerformance {
                ExerciseComparisonStrip(comparison: comparison, previous: previous)
            } else if comparison?.isFirstTime == true {
                FirstSessionBadge()
            }
            setsGrid
        }
        .padding(14)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(display.name)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .kerning(-0.2)
                .foregroundStyle(Color.white)
                .lineLimit(1)
            if prDetail != nil {
                prBadge
            }
            Spacer()
            Text("history.card.sets".localized(display.sets.count))
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    private var prBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 9, weight: .bold))
            Text("history.detail.pr".localized)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(DesignSystem.Colors.pr)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(DesignSystem.Colors.pr.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var setsGrid: some View {
        let sets = display.sets
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 6),
            count: max(1, min(sets.count, 6))
        )
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                setCell(index: index, set: set)
            }
        }
    }

    private func setCell(index: Int, set: WorkoutDetailExerciseDisplay.SetValues) -> some View {
        let weight = set.weight
        let reps = set.reps
        let weightText = weight > 0
            ? WeightFormatting.label(weight, in: weightUnit)
            : "history.detail.bw".localized
        // The written forms are abbreviations — "49,6 lb", "Körper". A screen
        // reader has to say the words: "49,6 pounds", "Körpergewicht".
        let spokenWeightText = weight > 0
            ? WeightFormatting.spokenLabel(weight, in: weightUnit)
            : "history.detail.bw.spoken".localized
        let isCompleted = set.isCompleted
        let isPRSet = set.id == prDetail?.setId
        let setComparison = setComparisons.indices.contains(index) ? setComparisons[index] : nil
        let delta = SetDeltaChip.Delta(
            comparison: setComparison,
            isCompleted: isCompleted,
            hasPreviousSession: comparison?.previousPerformance != nil,
            loadBehavior: display.loadBehavior,
            unit: weightUnit
        )

        return VStack(spacing: 4) {
            HStack(spacing: 3) {
                if isPRSet {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.pr)
                }
                Text(String(format: "history.detail.set_n".localized, index + 1))
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(isPRSet ? DesignSystem.Colors.pr : Color.white.opacity(0.4))
            }
            Text(weightText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .kerning(-0.3)
                .monospacedDigit()
                // At six sets each cell is ~47pt wide inside its padding, and
                // "21,5 kg" measures more than that. Scaling down beats wrapping,
                // which would silently make one grid row taller than its
                // neighbours. Tight before the seam added a space; not a regression,
                // but this is the ticket that made the string longer.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isCompleted ? Color.white : Color.white.opacity(0.4))
            Text("\(reps) \("history.detail.reps".localized)")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.55))
            if let delta {
                SetDeltaChip(delta: delta)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(isPRSet ? DesignSystem.Colors.pr.opacity(0.08) : Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignSystem.Colors.pr.opacity(isPRSet ? 0.4 : 0), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(isCompleted ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(format: "history.detail.set_n".localized, index + 1)))
        .accessibilityValue(accessibilityValue(spokenWeight: spokenWeightText, reps: reps, delta: delta, isPRSet: isPRSet))
    }

    private func accessibilityValue(spokenWeight: String, reps: Int, delta: SetDeltaChip.Delta?, isPRSet: Bool) -> Text {
        let deltaPhrase = delta?.accessibilityPhrase ?? ""
        var formatted = String(format: "history.detail.a11y.set_value_with_delta".localized,
                               spokenWeight, reps, deltaPhrase)
        if isPRSet {
            formatted += ", " + "history.detail.a11y.pr_set".localized
        }
        return Text(formatted)
    }
}

// MARK: - Comparison strip

struct ExerciseComparisonStrip: View {
    let comparison: ExerciseComparisonResult
    let previous: PreviousExercisePerformance
    @Environment(\.weightUnit) private var weightUnit

    private var topWeightDelta: SetDeltaChip.Delta {
        let currentTop = comparison.currentPerformance.sets
            .filter(\.isCompleted)
            .map(\.currentWeight)
            .max() ?? 0
        let previousTop = previous.bestSet?.weight ?? 0
        return SetDeltaChip.Delta.fromWeight(
            current: currentTop,
            previous: previousTop,
            loadBehavior: comparison.loadBehavior,
            unit: weightUnit
        )
    }

    private var volumeDelta: SetDeltaChip.Delta {
        SetDeltaChip.Delta.fromVolume(
            current: comparison.currentPerformance.effectiveTotalVolume ?? 0,
            previous: previous.effectiveTotalVolume ?? 0
        )
    }

    // Hoisted out of `body`'s read path: this allocated a DateFormatter per strip
    // per render (CLAUDE.md rendering rule 2), and every history detail screen
    // renders one strip per exercise. `Locale.current` is already the default.
    // `@MainActor` because a shared mutable formatter is only safe while every
    // access comes from a view body.
    @MainActor
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("d. MMM")
        return fmt
    }()

    private var dateString: String {
        Self.dateFormatter.string(from: previous.date)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(String(format: "history.detail.vs_date".localized, dateString))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.4))
            metricGroup(label: "history.detail.top_weight".localized, delta: topWeightDelta)
            if comparison.hasComparableVolume {
                metricGroup(label: "history.detail.volume_short".localized, delta: volumeDelta)
            }
            Spacer(minLength: 0)
        }
    }

    private func metricGroup(label: String, delta: SetDeltaChip.Delta) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.2)
                .foregroundStyle(Color.white.opacity(0.55))
            SetDeltaChip(delta: delta, compact: true)
        }
    }
}

// MARK: - First-session badge

struct FirstSessionBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .bold))
            Text("history.detail.first_session".localized)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(DesignSystem.Colors.info)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(DesignSystem.Colors.info.opacity(0.14))
        .clipShape(Capsule())
    }
}

// MARK: - Delta chip

struct SetDeltaChip: View {
    enum Delta: Equatable {
        /// What the change is actually measured in, carried alongside the label.
        ///
        /// It used to be *recovered* from the label instead: `s.contains("kg")`
        /// chose between the weight and the rep-count phrasing and
        /// `numericPart(of:)` stripped `"kg"` to get the number back. That is
        /// build-green, test-green and wrong the moment the label reads
        /// "+5 lb" — VoiceOver then describes a weight change as a rep change.
        /// A volume delta, whose label is a percentage, already fell through to
        /// the rep branch and was read out as "up 0 reps". Adding `"lb"` to the
        /// substring check would have moved the same defect one unit further
        /// out, so the kind is passed explicitly and the parsing helpers are
        /// gone.
        enum Quantity: Equatable {
            /// A weight change, carrying the spoken form of the same figure —
            /// "2,5 kilograms" — so the phrase never has to parse the label.
            case weight(spoken: String)
            case reps(Int)
            case percentage(Int)
        }

        case gain(String, Quantity)
        case loss(String, Quantity)
        case neutral
        case new

        /// `current`/`previous` are canonical kilograms; the *difference* is what
        /// gets converted, which is exact for a linear unit and keeps the rule
        /// that nothing is ever derived from an already-converted number.
        static func fromWeight(
            current: Double,
            previous: Double,
            loadBehavior: ExerciseLoadBehavior = .resistance,
            unit: WeightUnit
        ) -> Delta {
            let diff = ExerciseLoadMetrics.signedEnteredWeightDelta(
                current: current,
                previous: previous,
                behavior: loadBehavior
            )
            if abs(diff) < 0.01 { return .neutral }
            let sign = diff > 0 ? "+" : "−"
            let formatted = sign + WeightFormatting.label(abs(diff), in: unit)
            let quantity = Quantity.weight(
                spoken: WeightFormatting.spokenLabel(abs(diff), in: unit)
            )
            return diff > 0 ? .gain(formatted, quantity) : .loss(formatted, quantity)
        }

        static func fromVolume(current: Double, previous: Double) -> Delta {
            guard previous > 0 else {
                return current > 0 ? .gain("+100%", .percentage(100)) : .neutral
            }
            let pct = ((current - previous) / previous) * 100
            if abs(pct) < 0.5 { return .neutral }
            let magnitude = Int(abs(pct).rounded())
            let formatted = String(format: "%@%.0f%%", pct > 0 ? "+" : "−", abs(pct))
            return pct > 0
                ? .gain(formatted, .percentage(magnitude))
                : .loss(formatted, .percentage(magnitude))
        }

        static func fromReps(current: Int, previous: Int) -> Delta {
            let diff = current - previous
            if diff == 0 { return .neutral }
            let formatted = "\(diff > 0 ? "+" : "−")\(abs(diff)) \("history.detail.reps".localized)"
            let quantity = Quantity.reps(abs(diff))
            return diff > 0 ? .gain(formatted, quantity) : .loss(formatted, quantity)
        }

        init?(
            comparison: ExerciseComparisonResult.CurrentExercisePerformance.SetComparison?,
            isCompleted: Bool,
            hasPreviousSession: Bool,
            loadBehavior: ExerciseLoadBehavior = .resistance,
            unit: WeightUnit
        ) {
            guard isCompleted, hasPreviousSession else { return nil }
            guard let c = comparison else { return nil }
            if c.previousWeight == nil && c.previousReps == nil {
                self = .new
                return
            }
            if let prevWeight = c.previousWeight {
                let weightDelta = c.currentWeight - prevWeight
                if abs(weightDelta) >= 0.01 {
                    self = Delta.fromWeight(
                        current: c.currentWeight,
                        previous: prevWeight,
                        loadBehavior: loadBehavior,
                        unit: unit
                    )
                    return
                }
            }
            if let prevReps = c.previousReps {
                let repsDelta = c.currentReps - prevReps
                if repsDelta != 0 {
                    self = Delta.fromReps(current: c.currentReps, previous: prevReps)
                    return
                }
            }
            self = .neutral
        }

        var symbol: String {
            switch self {
            case .gain: return "arrow.up"
            case .loss: return "arrow.down"
            case .neutral: return "equal"
            case .new: return "sparkles"
            }
        }

        var label: String {
            switch self {
            case .gain(let s, _), .loss(let s, _): return s
            case .neutral: return ""
            case .new: return "history.detail.set_new".localized
            }
        }

        var color: Color {
            switch self {
            case .gain: return DesignSystem.Colors.success
            case .loss: return DesignSystem.Colors.destructive
            case .neutral: return DesignSystem.Colors.textSecondary
            case .new: return DesignSystem.Colors.info
            }
        }

        var accessibilityPhrase: String {
            switch self {
            case .gain(_, let quantity): return Self.phrase(for: quantity, rising: true)
            case .loss(_, let quantity): return Self.phrase(for: quantity, rising: false)
            case .neutral: return "history.detail.a11y.delta_equal".localized
            case .new: return "history.detail.a11y.delta_new".localized
            }
        }

        private static func phrase(for quantity: Quantity, rising: Bool) -> String {
            switch quantity {
            case .weight(let spoken):
                let key = rising
                    ? "history.detail.a11y.delta_up_weight"
                    : "history.detail.a11y.delta_down_weight"
                return String(format: key.localized, spoken)
            case .reps(let count):
                let key = rising
                    ? "history.detail.a11y.delta_up_reps"
                    : "history.detail.a11y.delta_down_reps"
                return String(format: key.localized, count)
            case .percentage(let percent):
                let key = rising
                    ? "history.detail.a11y.delta_up_percent"
                    : "history.detail.a11y.delta_down_percent"
                return String(format: key.localized, percent)
            }
        }
    }

    let delta: Delta
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: delta.symbol)
                .font(.system(size: compact ? 8 : 9, weight: .bold))
            if !delta.label.isEmpty {
                Text(delta.label)
                    .font(.system(size: compact ? 9 : 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .foregroundStyle(delta.color)
        .padding(.horizontal, compact ? 5 : 6)
        .padding(.vertical, compact ? 1 : 2)
        .background(delta.color.opacity(0.14), in: Capsule())
    }
}
