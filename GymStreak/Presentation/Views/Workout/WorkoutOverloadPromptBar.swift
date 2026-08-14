//
//  WorkoutOverloadPromptBar.swift
//  GymStreak
//
//  The mid-workout progressive-overload prompt, as a screen-level surface.
//
//  It used to live inside the expanded exercise card, which made it unreachable:
//  completing the last set is both what qualifies an exercise and what collapses
//  its card, so the banner mounted and unmounted in the same animation. Detached
//  from the card it no longer has the exercise in context, so it names it.
//  Which exercise it belongs to is decided by `OverloadPromptPolicy`.
//

import SwiftUI

struct WorkoutOverloadPromptBar: View {
    let prompt: OverloadPrompt
    let onIncrease: () -> Void
    let onDismiss: () -> Void

    /// The name is the only context the detached prompt has, so it scales with
    /// Dynamic Type and gets a second line at accessibility sizes instead of
    /// truncating — matching how the banner below it restacks.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("rep_range.prompt.for_exercise".localized(prompt.exerciseName))
                .font(.caption2.weight(.bold))
                .kerning(0.7)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.4))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .padding(.horizontal, 4)

            switch prompt {
            case .suggestion(let candidate):
                ProgressiveOverloadBanner(
                    targetRepMax: candidate.targetRepMax,
                    isAssistance: candidate.isAssistance,
                    onIncrease: onIncrease,
                    onDismiss: onDismiss
                )
                // Identity per exercise, so the banner's success haptic
                // (`onAppear`) fires once per prompt and not on every pass of
                // the screen's body — the container itself stays mounted while
                // one prompt hands over to the next.
                .id(candidate.exerciseId)
            case .applied(_, let applied):
                appliedConfirmation(applied)
            }
        }
    }

    /// What the apply moved the *template* to — the workout's own sets keep the
    /// performance and can differ whenever the user went off-plan.
    private func appliedConfirmation(_ applied: AppliedOverload) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.success)

            Text(applied.weight.map {
                "rep_range.routine_updated".localized(String(format: "%.1f", $0), applied.reps)
            } ?? "rep_range.overload_card.next_workout_no_weight".localized(applied.setCount, applied.reps))
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("action.dismiss".localized)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DesignSystem.Colors.success.opacity(0.3), lineWidth: 1)
        )
    }
}
