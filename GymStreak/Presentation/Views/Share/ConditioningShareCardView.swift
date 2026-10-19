//
//  ConditioningShareCardView.swift
//  GymStreak
//
//  The conditioning share card: a 1080 × 1920 story image built from the approved
//  design's `ConditioningCard.dc.html` (docs/workout-sharing.md). Same visual system
//  and tokens as `WorkoutShareCardView`; one point is one pixel.
//

import SwiftUI

struct ConditioningShareCardView: View {

    let model: ConditioningShareCardModel

    private static let green = DesignSystem.Colors.tint
    private static let label = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.6)
    private static let hairline = Color.white.opacity(0.08)
    private static let restFill = Color.white.opacity(0.16)
    /// The zones differ in lightness, not only hue: Z1 is grey, Z2–Z5 ever brighter green.
    private static let zoneFills: [Color] = [
        Color.white.opacity(0.22), green.opacity(0.26), green.opacity(0.46), green.opacity(0.72), green
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 56) {
                header
                if let heading = model.stripHeading {
                    rounds(heading: heading)
                }
                if !model.zones.isEmpty {
                    zones
                }
                if !model.stats.isEmpty {
                    stats
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 56)
            footer
        }
        .padding(EdgeInsets(top: 250, leading: 80, bottom: 300, trailing: 80))
        .frame(width: WorkoutShareCardView.size.width, height: WorkoutShareCardView.size.height, alignment: .top)
        .background(Color.black)
        .foregroundStyle(.white)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.eyebrow)
                .font(.system(size: 24, weight: .semibold))
                .tracking(3)
                .textCase(.uppercase)
                .foregroundStyle(Self.label)
            Text(model.title)
                .font(.system(size: 120, weight: .heavy))
                .tracking(-3)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(model.subtitle)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Self.label)
                .lineLimit(2)
                .padding(.top, 8)
        }
    }

    private func rounds(heading: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel(heading)
                Spacer()
                Text(model.stripValue)
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
            }
            .padding(.horizontal, 8)
            HStack(spacing: model.blockSpacing) {
                ForEach(model.blocks) { block in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(fill(for: block.kind))
                        .frame(width: block.width, height: model.stripHeight)
                        .overlay(alignment: .bottom) {
                            if let label = block.label {
                                Text(label)
                                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                                    .foregroundStyle(block.kind == .missedWork ? Self.label : Color.black)
                                    .padding(.bottom, 16)
                            }
                        }
                }
            }
            if let legend = model.legend {
                HStack(spacing: 40) {
                    legendItem(legend.work, fill: Self.green)
                    legendItem(legend.rest, fill: Self.restFill)
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func fill(for kind: ConditioningShareCardModel.Block.Kind) -> Color {
        switch kind {
        case .work: Self.green
        case .missedWork: Self.green.opacity(0.18)
        case .rest: Self.restFill
        }
    }

    private func legendItem(_ text: String, fill: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(fill)
                .frame(width: 16, height: 16)
            Text(text)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Self.label)
        }
    }

    private var zones: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("share_card.conditioning.zones_title".localized)
                .padding(.horizontal, 8)
            VStack(spacing: 20) {
                ForEach(model.zones) { zone in
                    HStack(spacing: 24) {
                        Text(zone.name)
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(zone.id >= 3 ? Self.green : Self.label)
                            .frame(width: 56, alignment: .leading)
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Self.zoneFills[min(zone.id, Self.zoneFills.count - 1)])
                                .frame(width: proxy.size.width * zone.fraction)
                        }
                        .frame(height: 32)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(zone.time)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .frame(width: 104, alignment: .trailing)
                    }
                }
            }
            .padding(40)
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 48, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 2)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            ForEach(model.stats) { stat in
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(stat.value)
                            .font(.system(size: 72, weight: .heavy, design: .rounded))
                            .tracking(-1)
                            .monospacedDigit()
                        if !stat.unit.isEmpty {
                            Text(stat.unit)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(Self.label)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    sectionLabel(stat.label)
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    if stat.id > 0 {
                        Self.hairline.frame(width: 2)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 16) {
                Circle()
                    .fill(Self.green)
                    .frame(width: 20, height: 20)
                Text(model.wordmark)
                    .font(.system(size: 44, weight: .heavy))
                    .tracking(-1)
            }
            Spacer()
            Text(model.tagline)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Self.label)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .bold))
            .tracking(3)
            .textCase(.uppercase)
            .foregroundStyle(Self.label)
    }
}
