//
//  FortschrittExerciseRowView.swift
//  GymStreak
//

import SwiftUI

/// A single exercise row in the Fortschritt tab: muscle-group badge + name + count + sparkline + trend %.
///
/// The sparkline and the trend are **max weight** — the metric the detail chart draws by
/// default, named in the caption beside them — over that usage's whole history.
///
/// When the exercise is trained in more than one way, they describe
/// the **most recently trained** usage rather than a blend of all of them, and the row says
/// so on a full-width line beneath the rest —
/// otherwise it would present one coherent-looking progression built from two different
/// pieces of work, which is the defect this row's numbers came from. The list stays one
/// row per exercise; splitting it per usage would bury it under near-duplicate entries
/// (see `docs/progress-charts.md`).
///
/// A row whose exercise shares its display name with another library exercise also prints
/// that exercise's equipment beside the name; a uniquely named one does not.
struct FortschrittExerciseRowView: View {
    let model: FortschrittExerciseModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            // Its own full-width line, not part of the row above: a usage label is the
            // marker plus a rep goal plus a routine name, which shares a line with the
            // count and the sparkline only by truncating to "Ohne Zuordnung · 4–…".
            if let headline = model.headlineUsage {
                usageLine(headline)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.035))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var content: some View {
        HStack(spacing: 12) {
            badge
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    // Only where the name collides with another library exercise — the
                    // qualifier is what separates two rows reading "Biceps Curls".
                    if let equipment = model.equipmentQualifier {
                        equipmentChip(equipment)
                    }
                }
                HStack(spacing: 8) {
                    Text("progress.workout_count".localized(model.workoutCount))
                    if model.lastPerformed != nil {
                        Circle().fill(Color.white.opacity(0.3)).frame(width: 2, height: 2)
                        Text(relativeDate(model.lastPerformed ?? Date()))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                MiniSparkline(
                    data: model.sparkline,
                    color: trendColor
                )
                // What the curve and the percentage measure. Same caption, same wording and
                // the same assistance exception as the headline above the detail screen's
                // chart (`ExerciseProgressViewModel.title(for:)`), so the list and
                // that screen name one metric rather than two.
                Text(metricTitle.uppercased())
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Color.white.opacity(0.4))
                    .lineLimit(1)
                if let trend = model.trendPct {
                    Text(trendLabel(trend))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(trendColor)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.3))
        }
    }

    /// Which usage the sparkline and the trend describe, and how many there are in total.
    ///
    /// The label comes from the picker's own labeller (`ExerciseUsageLabeling.pickerItems`,
    /// run inside `FortschrittAggregator`), so a usage reads here as it reads in the menu,
    /// disambiguating suffix included. The one exception is the "not in a routine" marker,
    /// which the list has no live routine slots to derive — see `docs/progress-charts.md`.
    /// The picker's icon repeats here for the same reason the label is shared.
    private func usageLine(_ headline: ExerciseUsagePickerItem) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 9, weight: .semibold))
            Text("progress.row.curve_usage".localized(headline.label))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text("progress.row.usage_of_total".localized(model.usageCount))
                .foregroundStyle(Color.white.opacity(0.45))
                .layoutPriority(1)
        }
        .font(.system(size: 10, weight: .medium))
        // Metadata grey, not the tint: on device the tinted line read as a control, and
        // it is not one — the whole cell is the tap target and it already opens this very
        // usage, so a separate tap could not do anything different.
        .foregroundStyle(Color.white.opacity(0.55))
    }

    /// The equipment that tells this row apart from another exercise of the same name.
    /// Present only when `FortschrittAggregator` found that collision while building the
    /// list, so no view here scans the exercise library.
    private func equipmentChip(_ equipment: EquipmentType) -> some View {
        Text(equipment.displayName)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.65))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.1))
            .clipShape(Capsule())
            .layoutPriority(1)
    }

    /// The metric the sparkline and the trend describe. A counterweight series with no
    /// body-mass snapshot carries assistance rather than load — inverted, so that less is
    /// better — and must say so instead of claiming a max weight.
    private var metricTitle: String {
        model.chartsAssistance
            ? "exercise.assistance".localized
            : ProgressMetric.maxWeight.localizedTitle
    }

    private var badge: some View {
        Text(String(model.primaryMuscleGroup.prefix(2)).uppercased())
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .kerning(-0.3)
            .foregroundStyle(DesignSystem.Colors.textOnTint)
            .frame(width: 42, height: 42)
            .background(DesignSystem.Colors.tint)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var trendColor: Color {
        guard let trend = model.trendPct else { return DesignSystem.Colors.tint }
        return trend >= 0 ? DesignSystem.Colors.tint : Color(red: 1, green: 0.42, blue: 0.42)
    }

    private func trendLabel(_ pct: Double) -> String {
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", pct))%"
    }

    // Hoisted out of `body`: this was allocated once per row, per render
    // (docs/history-performance.md §2.7). `@MainActor` because RelativeDateTimeFormatter carries no
    // documented thread-safety guarantee, so sharing one instance is only sound while every access
    // is from a view body on the main thread.
    @MainActor
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .short
        return formatter
    }()

    private func relativeDate(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
