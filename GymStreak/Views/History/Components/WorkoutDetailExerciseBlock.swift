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
    let exercise: WorkoutExercise
    let isPR: Bool
    let comparison: ExerciseComparisonResult?

    private var sortedSets: [WorkoutSet] {
        exercise.setsList.sorted(by: { $0.order < $1.order })
    }

    private var setComparisons: [ExerciseComparisonResult.CurrentExercisePerformance.SetComparison] {
        comparison?.currentPerformance.sets ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleRow
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
            Text(exercise.exerciseName)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .kerning(-0.2)
                .foregroundStyle(Color.white)
                .lineLimit(1)
            if isPR {
                prBadge
            }
            Spacer()
            Text("history.card.sets".localized(exercise.setsList.count))
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
        .foregroundStyle(Color(red: 1, green: 0.8, blue: 0))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color(red: 1, green: 0.8, blue: 0).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var setsGrid: some View {
        let sets = sortedSets
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

    private func setCell(index: Int, set: WorkoutSet) -> some View {
        let usePlanned = exercise.progressiveOverloadApplied
        let weight = usePlanned ? set.plannedWeight : set.actualWeight
        let reps = usePlanned ? set.plannedReps : set.actualReps
        let weightText = weight > 0
            ? String(format: "%gkg", weight)
            : "history.detail.bw".localized
        let isCompleted = set.isCompleted
        let setComparison = setComparisons.indices.contains(index) ? setComparisons[index] : nil
        let delta = SetDeltaChip.Delta(comparison: setComparison, isCompleted: isCompleted, hasPreviousSession: comparison?.previousPerformance != nil)

        return VStack(spacing: 4) {
            Text(String(format: "history.detail.set_n".localized, index + 1))
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.white.opacity(0.4))
            Text(weightText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .kerning(-0.3)
                .monospacedDigit()
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
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(isCompleted ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(format: "history.detail.set_n".localized, index + 1)))
        .accessibilityValue(accessibilityValue(weight: weight, weightText: weightText, reps: reps, delta: delta))
    }

    private func accessibilityValue(weight: Double, weightText: String, reps: Int, delta: SetDeltaChip.Delta?) -> Text {
        let deltaPhrase = delta?.accessibilityPhrase ?? ""
        let valueString = weight > 0 ? weightText : "history.detail.bw".localized
        let formatted = String(format: "history.detail.a11y.set_value_with_delta".localized,
                               valueString, reps, deltaPhrase)
        return Text(formatted)
    }
}

// MARK: - Comparison strip

struct ExerciseComparisonStrip: View {
    let comparison: ExerciseComparisonResult
    let previous: PreviousExercisePerformance

    private var topWeightDelta: SetDeltaChip.Delta {
        let currentTop = comparison.currentPerformance.sets
            .filter(\.isCompleted)
            .map(\.currentWeight)
            .max() ?? 0
        let previousTop = previous.bestSet?.weight ?? 0
        return SetDeltaChip.Delta.fromWeight(current: currentTop, previous: previousTop)
    }

    private var volumeDelta: SetDeltaChip.Delta {
        SetDeltaChip.Delta.fromVolume(
            current: comparison.currentPerformance.totalVolume,
            previous: previous.totalVolume
        )
    }

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("d. MMM")
        return fmt.string(from: previous.date)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(String(format: "history.detail.vs_date".localized, dateString))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.4))
            metricGroup(label: "history.detail.top_weight".localized, delta: topWeightDelta)
            metricGroup(label: "history.detail.volume_short".localized, delta: volumeDelta)
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
        case gain(String)
        case loss(String)
        case neutral
        case new

        static func fromWeight(current: Double, previous: Double) -> Delta {
            let diff = current - previous
            if abs(diff) < 0.01 { return .neutral }
            let formatted = String(format: "%@%g kg", diff > 0 ? "+" : "−", abs(diff))
            return diff > 0 ? .gain(formatted) : .loss(formatted)
        }

        static func fromVolume(current: Double, previous: Double) -> Delta {
            guard previous > 0 else {
                return current > 0 ? .gain("+100%") : .neutral
            }
            let pct = ((current - previous) / previous) * 100
            if abs(pct) < 0.5 { return .neutral }
            let formatted = String(format: "%@%.0f%%", pct > 0 ? "+" : "−", abs(pct))
            return pct > 0 ? .gain(formatted) : .loss(formatted)
        }

        static func fromReps(current: Int, previous: Int) -> Delta {
            let diff = current - previous
            if diff == 0 { return .neutral }
            let formatted = "\(diff > 0 ? "+" : "−")\(abs(diff)) \("history.detail.reps".localized)"
            return diff > 0 ? .gain(formatted) : .loss(formatted)
        }

        init?(comparison: ExerciseComparisonResult.CurrentExercisePerformance.SetComparison?, isCompleted: Bool, hasPreviousSession: Bool) {
            guard isCompleted, hasPreviousSession else { return nil }
            guard let c = comparison else { return nil }
            if c.previousWeight == nil && c.previousReps == nil {
                self = .new
                return
            }
            if let prevWeight = c.previousWeight {
                let weightDelta = c.currentWeight - prevWeight
                if abs(weightDelta) >= 0.01 {
                    self = Delta.fromWeight(current: c.currentWeight, previous: prevWeight)
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
            case .gain(let s), .loss(let s): return s
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
            case .gain(let s):
                return s.contains("kg")
                    ? String(format: "history.detail.a11y.delta_up_weight".localized, numericPart(of: s))
                    : String(format: "history.detail.a11y.delta_up_reps".localized, numericInt(of: s))
            case .loss(let s):
                return s.contains("kg")
                    ? String(format: "history.detail.a11y.delta_down_weight".localized, numericPart(of: s))
                    : String(format: "history.detail.a11y.delta_down_reps".localized, numericInt(of: s))
            case .neutral: return "history.detail.a11y.delta_equal".localized
            case .new: return "history.detail.a11y.delta_new".localized
            }
        }

        private func numericPart(of s: String) -> String {
            s.replacingOccurrences(of: "+", with: "")
             .replacingOccurrences(of: "−", with: "")
             .replacingOccurrences(of: "kg", with: "")
             .trimmingCharacters(in: .whitespaces)
        }

        private func numericInt(of s: String) -> Int {
            Int(numericPart(of: s).components(separatedBy: " ").first ?? "0") ?? 0
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
