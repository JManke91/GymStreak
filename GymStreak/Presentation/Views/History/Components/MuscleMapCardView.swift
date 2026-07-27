//
//  MuscleMapCardView.swift
//  GymStreak
//
//  The muscle map on workout detail: front and back schematic bodies with the
//  regions this workout trained lit in the accent color.
//

import SwiftUI

/// Card wrapping the two schematic figures, with the primary/secondary legend in its header.
struct MuscleMapCardView: View {

    let model: MuscleMapCardModel

    /// The region the user is inspecting. Deliberately local view state: selecting a region
    /// redraws the card and nothing else — it never re-runs the aggregation behind `model`.
    @State private var selection: MuscleMapRegion?

    private static let figureWidth: CGFloat = 128

    var body: some View {
        // A workout whose exercises map to no region (only "General", or nothing completed)
        // would render an all-grey body that says nothing — the card stays away instead.
        if model.hasTraining {
            VStack(spacing: 0) {
                header
                figures
                if let detail = selectedDetail {
                    detailChip(detail)
                } else {
                    pillRow
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
        }
    }

    /// Dictionary lookup, not a scan — selecting a region must stay free of work in `body`.
    private var selectedDetail: MuscleMapDetail? {
        guard let selection else { return nil }
        return model.details[selection]
    }

    /// What the figures dim against. A selection the model no longer knows — the session was
    /// edited while the chip was open — reads as no selection rather than dimming everything.
    private var activeSelection: MuscleMapRegion? {
        selectedDetail == nil ? nil : selection
    }

    private func select(_ region: MuscleMapRegion) {
        HapticManager.shared.light()
        withAnimation(.easeInOut(duration: 0.25)) {
            selection = selection == region ? nil : region
        }
    }

    private func clearSelection() {
        HapticManager.shared.light()
        withAnimation(.easeInOut(duration: 0.25)) {
            selection = nil
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("history.detail.muscle_map.title".localized)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .kerning(-0.2)
                .foregroundStyle(Color.white)
                // The overview VoiceOver used to get from the card as a whole; the figures
                // below now expose one element per region.
                .accessibilityValue(model.accessibilitySummary)
            Spacer(minLength: 8)
            legendEntry(
                color: DesignSystem.Colors.tint,
                label: "history.detail.muscle_map.primary".localized
            )
            legendEntry(
                color: DesignSystem.Colors.tint.opacity(0.4),
                label: "history.detail.muscle_map.secondary".localized
            )
        }
    }

    private func legendEntry(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    private var figures: some View {
        HStack(alignment: .top, spacing: 6) {
            figureColumn(face: .front, caption: "history.detail.muscle_map.front".localized)
            figureColumn(face: .back, caption: "history.detail.muscle_map.back".localized)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    /// The trained regions spelled out beneath the figures: accent-tinted pills with their set
    /// count for the primary movers, muted ones for the supporting work. Tapping one selects
    /// the same region tapping its belly does.
    private var pillRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(model.pills) { pill in
                self.pillView(pill)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .transition(.opacity)
    }

    @ViewBuilder
    private func pillView(_ pill: MuscleMapPill) -> some View {
        let isPrimary = pill.engagement == .primary
        Button {
            select(pill.region)
        } label: {
            HStack(spacing: 5) {
                Text(pill.name)
                    .font(.system(size: 11.5, weight: isPrimary ? .semibold : .medium))
                    .foregroundStyle(isPrimary ? Color.white : Color.white.opacity(0.6))
                if isPrimary {
                    Text("\(pill.completedSets)")
                        .font(.system(size: 10.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(DesignSystem.Colors.tint)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isPrimary ? DesignSystem.Colors.tint.opacity(0.14) : Color.white.opacity(0.04))
            .overlay(
                Capsule()
                    .stroke(
                        isPrimary ? DesignSystem.Colors.tint.opacity(0.26) : Color.white.opacity(0.07),
                        lineWidth: 1
                    )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        // Without this the set count is spoken as a bare number after the region name.
        .accessibilityLabel(model.accessibilityLabels[pill.region] ?? pill.name)
    }

    /// Replaces the pill row while a region is selected: what it was, how hard, and what did it.
    private func detailChip(_ detail: MuscleMapDetail) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(detail.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                Text(detail.stateLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(DesignSystem.Colors.tint)
                Spacer(minLength: 8)
                Button(action: clearSelection) {
                    Text("history.detail.muscle_map.reset".localized)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.45))
                        // The label is 11 pt type at the edge of the chip: without a padded
                        // hit area of its own it is a near-unhittable tap target.
                        .padding(.vertical, 8)
                        .padding(.leading, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !detail.exercises.isEmpty {
                Text(detail.exercises)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A 9 % tint over the card, not a solid accent plate, so the white text keeps its
        // contrast and `textOnTint` does not come into play.
        .background(DesignSystem.Colors.tint.opacity(0.09))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.Colors.tint.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 8)
        .transition(.opacity)
    }

    private func figureColumn(face: MuscleMapFace, caption: String) -> some View {
        VStack(spacing: 4) {
            MuscleFigureView(
                face: face,
                highlights: model.highlights,
                width: Self.figureWidth,
                selection: activeSelection,
                regionLabels: model.accessibilityLabels,
                onSelect: select
            )
            Text(caption.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }
}

#Preview("Muscle map card") {
    let loads: [MuscleMapRegion: MuscleLoad] = [
        .chest: MuscleLoad(engagement: .primary, completedSets: 8, exerciseNames: ["Bankdrücken"]),
        .triceps: MuscleLoad(engagement: .primary, completedSets: 4, exerciseNames: ["Dips"]),
        .shoulders: MuscleLoad(engagement: .secondary, completedSets: 0, exerciseNames: ["Bankdrücken"]),
        .quadriceps: MuscleLoad(engagement: .secondary, completedSets: 0, exerciseNames: ["Dips"]),
    ]

    return ScrollView {
        MuscleMapCardView(model: .make(from: loads))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DesignSystem.Colors.background)
}
