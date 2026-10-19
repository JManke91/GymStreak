//
//  WorkoutShareCardView.swift
//  GymStreak
//
//  The strength share card: a 1080 × 1920 story image built from the approved design's
//  `Main.dc.html` (docs/workout-sharing.md). One point is one pixel; `ImageRenderer` renders
//  it at scale 1, the preview sheet and the entry row show it scaled down.
//

import SwiftUI

struct WorkoutShareCardView: View {

    let model: WorkoutShareCardModel

    static let size = CGSize(width: 1080, height: 1920)

    // Design tokens of the card. Fixed point sizes: the image must not follow Dynamic Type.
    private static let green = DesignSystem.Colors.tint
    private static let label = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.6)
    private static let leader = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.3)
    private static let hairline = Color.white.opacity(0.08)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 56) {
                header
                stage
                if let recordsLabel = model.recordsLabel {
                    records(label: recordsLabel)
                }
                if !model.stats.isEmpty {
                    stats
                }
                if let exerciseLine = model.exerciseLine {
                    Text(exerciseLine)
                        .font(.system(size: 34, weight: .medium))
                        .lineSpacing(10)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Self.label)
                        .padding(.horizontal, 40)
                        .frame(maxWidth: .infinity)
                }
            }
            // Like the design, tall content runs into the bottom story margin rather than
            // shrinking the title and stats to fit.
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 56)
            footer
        }
        .padding(EdgeInsets(top: 250, leading: 80, bottom: 300, trailing: 80))
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background(Color.black)
        .foregroundStyle(.white)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.dateLine)
                .font(.system(size: 24, weight: .semibold))
                .tracking(3)
                .textCase(.uppercase)
                .foregroundStyle(Self.label)
            Text(model.title)
                .font(.system(size: 120, weight: .heavy))
                .tracking(-3)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private var stage: some View {
        let stage = model.stage
        return ZStack(alignment: .topLeading) {
            MuscleFigureView(face: .front, highlights: model.highlights, width: stage.figureWidth)
                .offset(x: stage.frontX)
            MuscleFigureView(face: .back, highlights: model.highlights, width: stage.figureWidth)
                .offset(x: stage.backX)
            ForEach(model.callouts) { callout in
                leaderLine(callout.placement)
                calloutLabel(callout)
            }
        }
        .frame(width: WorkoutShareCalloutLayout.stageWidth, height: stage.height, alignment: .topLeading)
    }

    private func leaderLine(_ placement: WorkoutShareCalloutLayout.Callout) -> some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: placement.anchor)
                path.addLine(to: placement.elbow)
                path.addLine(to: placement.end)
            }
            .stroke(Self.leader, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            Circle()
                .fill(Self.green)
                .stroke(Color.black, lineWidth: 3)
                .frame(width: 18, height: 18)
                .position(placement.anchor)
        }
    }

    private func calloutLabel(_ callout: WorkoutShareCardModel.Callout) -> some View {
        let isLeft = callout.placement.isLeftColumn
        return VStack(alignment: isLeft ? .trailing : .leading, spacing: 8) {
            Text(callout.name)
                .font(.system(size: 24, weight: .bold))
                .tracking(3)
                .textCase(.uppercase)
                .foregroundStyle(Self.label)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 12) {
                if isLeft { recordTag(isShown: callout.hasRecord) }
                Text(callout.sets)
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .fixedSize()
                if !isLeft { recordTag(isShown: callout.hasRecord) }
            }
        }
        .frame(width: model.stage.labelWidth, alignment: isLeft ? .trailing : .leading)
        .offset(x: callout.placement.labelOrigin.x, y: callout.placement.labelOrigin.y)
    }

    @ViewBuilder
    private func recordTag(isShown: Bool) -> some View {
        if isShown {
            Text("share_card.pr_tag".localized)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(DesignSystem.Colors.textOnTint)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Self.green, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func records(label: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel(label)
                .padding(.horizontal, 8)
            VStack(spacing: 0) {
                ForEach(model.records) { record in
                    if record.id > 0 {
                        Self.hairline.frame(height: 2)
                    }
                    recordRow(record)
                }
            }
            .background(DesignSystem.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: 48, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 48, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 2)
            }
        }
    }

    private func recordRow(_ record: WorkoutShareCardModel.RecordRow) -> some View {
        HStack(spacing: 24) {
            Image(systemName: "trophy")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Self.green)
                .frame(width: 56, height: 56)
                .background(Self.green.opacity(0.14), in: Circle())
            Text(record.exercise)
                .font(.system(size: 34, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(record.value)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(Self.green)
                .fixedSize()
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
    }

    private var stats: some View {
        HStack(spacing: 0) {
            ForEach(model.stats) { stat in
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(stat.value)
                            .font(.system(size: 72, weight: .heavy, design: .rounded))
                            .tracking(-1)
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
