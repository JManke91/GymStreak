//
//  CompactActionBar.swift
//  GymStreakWatch Watch App
//
//  Fused bottom action row: round set-navigation chevrons flanking a glass
//  "Complete" capsule whose fill and mini segments show set progress.
//

import SwiftUI

struct CompactActionBar: View {
    let isCompleted: Bool
    let currentSetIndex: Int
    let totalSets: Int
    let completedSets: [Bool]
    /// Momentary "exercise finished" celebration state driven by the parent.
    let showDoneFlash: Bool
    let onComplete: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let metrics = WorkoutScreenMetrics.current
    private let accent = OnyxWatch.Colors.accentGreen

    private var completedCount: Int {
        completedSets.filter { $0 }.count
    }

    private var progress: CGFloat {
        guard totalSets > 0 else { return 0 }
        return CGFloat(completedCount) / CGFloat(totalSets)
    }

    private var hasPrevious: Bool {
        currentSetIndex > 0
    }

    private var hasNext: Bool {
        currentSetIndex < totalSets - 1
    }

    private var fillAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)
    }

    var body: some View {
        if totalSets > 1 {
            HStack(spacing: metrics.fusedRowGap) {
                navigationButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: "Previous set",
                    isEnabled: hasPrevious,
                    action: onPrevious
                )

                completionButton

                navigationButton(
                    systemImage: "chevron.right",
                    accessibilityLabel: "Next set",
                    isEnabled: hasNext,
                    action: onNext
                )
            }
        } else {
            completionButton
        }
    }

    // MARK: - Completion Button

    private var completionButton: some View {
        // Haptics for complete/undo are played by WatchWorkoutViewModel, which
        // also serves the exercise list and the Action Button intent.
        Button {
            onComplete()
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: showDoneFlash || !isCompleted ? "checkmark" : "arrow.uturn.backward")
                        .font(.system(size: metrics.completeLabelSize + 1.5, weight: .heavy))
                        .foregroundStyle(showDoneFlash ? OnyxWatch.Colors.textOnDone : accent)
                        .symbolEffect(.bounce, value: completedCount)

                    Text(completionLabel)
                        .font(.system(size: metrics.completeLabelSize, weight: .bold))
                        .foregroundStyle(showDoneFlash ? OnyxWatch.Colors.textOnDone : OnyxWatch.Colors.glassLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                if totalSets > 1 {
                    miniSegments
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.completeButtonHeight)
            .background { capsuleBackground }
            .overlay {
                if !showDoneFlash {
                    Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 1)
                }
            }
            .shadow(
                color: accent.opacity(showDoneFlash ? 0.35 : 0.25),
                radius: 12,
                y: 3
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .frame(height: OnyxWatch.Dimensions.minTouchTarget)
        .handGestureShortcut(.primaryAction)
        .accessibilityLabel(completionAccessibilityLabel)
    }

    private var completionLabel: String {
        if showDoneFlash {
            return String(localized: "Done")
        }
        return isCompleted ? String(localized: "Undo") : String(localized: "Complete")
    }

    private var capsuleBackground: some View {
        ZStack {
            if showDoneFlash {
                Capsule().fill(
                    LinearGradient(
                        colors: OnyxWatch.Colors.doneGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            } else {
                Capsule().fill(.ultraThinMaterial)

                // Green glass tint, brightest above the top edge
                Capsule().fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: accent.opacity(0.45), location: 0),
                            .init(color: accent.opacity(0.12), location: 0.55),
                            .init(color: accent.opacity(0.08), location: 1)
                        ]),
                        center: UnitPoint(x: 0.5, y: -0.4),
                        startRadius: 0,
                        endRadius: 170
                    )
                )

                progressFill

                // Light edge along the top of the capsule
                Capsule().fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .white.opacity(0.22), location: 0),
                            .init(color: .white.opacity(0), location: 0.45)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .clipShape(Capsule())
        .animation(fillAnimation, value: progress)
    }

    private var progressFill: some View {
        GeometryReader { geo in
            if progress > 0 {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.34), accent.opacity(0.14)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: geo.size.width * progress)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(accent.opacity(0.5)).frame(width: 1.5)
                    }
            }
        }
    }

    private var miniSegments: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<totalSets, id: \.self) { index in
                Capsule()
                    .fill(segmentColor(for: index))
                    .frame(height: 2.5)
            }
        }
        .frame(width: metrics.segmentsWidth)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8).delay(0.08), value: completedCount)
        .accessibilityHidden(true)
    }

    private func segmentColor(for index: Int) -> Color {
        if showDoneFlash {
            return OnyxWatch.Colors.textOnDone
        }
        if index < completedSets.count && completedSets[index] {
            return accent
        }
        // Slightly brighter pending segment marks the currently displayed set,
        // since the chevrons navigate sets (deviation from the mockup, which
        // had no position indicator).
        return index == currentSetIndex ? .white.opacity(0.45) : .white.opacity(0.22)
    }

    private var completionAccessibilityLabel: Text {
        if totalSets > 1 {
            return isCompleted
                ? Text("Undo set \(currentSetIndex + 1) of \(totalSets)")
                : Text("Complete set \(currentSetIndex + 1) of \(totalSets)")
        }
        return isCompleted ? Text("Undo set") : Text("Complete set")
    }

    // MARK: - Navigation Buttons

    private func navigationButton(
        systemImage: String,
        accessibilityLabel: LocalizedStringKey,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: metrics.chevronIconSize, weight: .bold))
                .foregroundStyle(isEnabled ? OnyxWatch.Colors.chipText : OnyxWatch.Colors.textTertiary)
        }
        .buttonStyle(ChevronCircleStyle(diameter: metrics.chevronDiameter))
        .disabled(!isEnabled)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text("Set \(currentSetIndex + 1) of \(totalSets)"))
    }

}

// MARK: - Preview

#Preview("Set progress states") {
    ZStack {
        OnyxWatch.Colors.background.ignoresSafeArea()

        VStack(spacing: 12) {
            CompactActionBar(
                isCompleted: false,
                currentSetIndex: 1,
                totalSets: 3,
                completedSets: [true, false, false],
                showDoneFlash: false,
                onComplete: {},
                onPrevious: {},
                onNext: {}
            )

            CompactActionBar(
                isCompleted: true,
                currentSetIndex: 2,
                totalSets: 3,
                completedSets: [true, true, true],
                showDoneFlash: true,
                onComplete: {},
                onPrevious: {},
                onNext: {}
            )
        }
        .padding(.horizontal, 8)
    }
}
