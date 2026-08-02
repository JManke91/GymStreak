//
//  WorkoutRestBar.swift
//  GymStreak
//
//  The default rest-timer surface: a bar that sits above the workout's action
//  buttons instead of taking over the screen. Rest no longer interrupts — you
//  can keep logging while it runs, and tap the bar to get the large timer.
//
//  It replaces the former top-inset `CompactRestTimer` and inherits its role in
//  the large↔compact morph: the ring and the time label are the shared
//  `matchedGeometryEffect` elements, so they travel between here and
//  `RestTimerView`. Both variants must stay in the same view tree for that to
//  work — see the note in `ActiveWorkoutView`.
//

import SwiftUI

struct WorkoutRestBar: View {
    let remaining: TimeInterval
    let total: TimeInterval
    /// Shared namespace with `RestTimerView`.
    let namespace: Namespace.ID
    let onExpand: () -> Void
    let onExtend: () -> Void
    let onSkip: () -> Void

    /// Elapsed share of the rest, used as the bar's fill.
    private var elapsedFraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, max(0, CGFloat(1 - remaining / total)))
    }

    /// Remaining share, used by the shared ring.
    private var remainingFraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(remaining / total)
    }

    var body: some View {
        HStack(spacing: 12) {
            RestTimerRing(progress: remainingFraction)
                .matchedGeometryEffect(id: RestTimerMorph.ringID, in: namespace)
                .frame(width: RestTimerMorph.compactRingDiameter, height: RestTimerMorph.compactRingDiameter)

            VStack(alignment: .leading, spacing: 0) {
                Text("rest_timer.title".localized)
                    .font(.system(size: 10.5, weight: .bold))
                    .kerning(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.white.opacity(0.4))

                Text(WorkoutValueFormatting.clock(remaining))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .fixedSize()
                    .contentTransition(.identity)
                    .matchedGeometryEffect(id: RestTimerMorph.timeLabelID, in: namespace, properties: .position)
            }

            Spacer(minLength: 0)

            Button(action: onExtend) {
                Text("rest_timer.extend".localized)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onSkip) {
                Text("rest_timer.next".localized)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textOnTint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(DesignSystem.Colors.tint)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 11)
        .background(alignment: .leading) {
            // Fill grows left-to-right as the rest runs down, so the bar itself
            // reads as the progress indicator.
            GeometryReader { proxy in
                DesignSystem.Colors.tint.opacity(0.09)
                    .frame(width: proxy.size.width * elapsedFraction)
                    .animation(.linear(duration: 1), value: elapsedFraction)
            }
        }
        .background(DesignSystem.Colors.cardElevated.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DesignSystem.Colors.tint.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // The bar resolves as one unit so the morph is not re-interpolated
        // against the surrounding layout pass.
        .geometryGroup()
        .contentShape(Rectangle())
        .onTapGesture(perform: onExpand)
        .accessibilityElement(children: .contain)
        .accessibilityHint("rest_timer.expand_hint".localized)
    }
}

// MARK: - Footer actions

/// Cancel and finish, the two things you can do to the workout as a whole.
struct WorkoutFooterActions: View {
    let completedSets: Int
    let totalSets: Int
    let onCancel: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: 52, height: 52)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("workout.cancel".localized)

            Button(action: onFinish) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                    Text("workout.finish_with_progress".localized(completedSets, totalSets))
                        .font(.system(size: 15.5, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(DesignSystem.Colors.textOnTint)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(DesignSystem.Colors.tint)
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("workout.finish".localized)
        }
    }
}
