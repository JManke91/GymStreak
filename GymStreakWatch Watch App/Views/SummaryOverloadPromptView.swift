//
//  SummaryOverloadPromptView.swift
//  GymStreakWatch Watch App
//
//  The post-workout recap's progressive-overload prompt (ticket 05): the
//  actionable form of the rep-goal trophy the summary used to show passively.
//
//  Presentation only. It renders one pre-resolved `WatchSummaryOverloadRow` and
//  reports a single intent; the picker, the math, the transaction and the
//  transport are all the mid-workout flow's, unchanged.
//

import SwiftUI

struct SummaryOverloadPromptView: View {
    let state: WatchSummaryOverloadRow.State
    let onTap: () -> Void

    var body: some View {
        switch state {
        case .actionable:
            actionable
        case .applied(let newWeight, let isAssistance):
            applied(newWeight: newWeight, isAssistance: isAssistance)
        case .superseded:
            superseded
        }
    }

    // MARK: - Actionable

    private var actionable: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("Increase weight", comment: "Post-workout recap action to raise a routine's working weight")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(OnyxWatch.Colors.textOnWarning)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(OnyxWatch.Colors.warning, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(
            "Raises this exercise's weight in your routine from the next workout.",
            comment: "VoiceOver hint for the post-workout recap's weight-increase action"
        ))
    }

    // MARK: - Applied

    /// Deliberately says "next workout", not "saved on iPhone": the change is
    /// durable on THIS Watch, and while the phone is unreachable it has not
    /// converged yet. Claiming otherwise is the one thing this surface must not
    /// do.
    private func applied(newWeight: Double?, isAssistance: Bool) -> some View {
        statusRow(
            systemImage: "checkmark.circle.fill",
            tint: OnyxWatch.Colors.accentGreen,
            text: appliedText(newWeight: newWeight, isAssistance: isAssistance)
        )
    }

    private func appliedText(newWeight: Double?, isAssistance: Bool) -> Text {
        guard let newWeight else {
            // A pyramid or drop scheme has no single "new weight" — naming one
            // would misstate every other set, so the copy states the scope of
            // the change instead of a number.
            return Text(
                "All sets adjusted for your next workout",
                comment: "Recap confirmation when a target's sets do not share one weight"
            )
        }
        let weight = ProgressiveOverloadFormat.weight(newWeight)
        return isAssistance
            ? Text(
                "Assistance now \(weight) next workout",
                comment: "Recap confirmation for counterweight-assistance exercises; parameter is the new weight"
            )
            : Text(
                "Now \(weight) next workout",
                comment: "Recap confirmation for an applied weight increase; parameter is the new weight"
            )
    }

    // MARK: - Superseded

    /// iOS ruled on the transaction and kept its own value. Shown rather than
    /// quietly restoring the button: repeating an action whose outcome was
    /// never reported is exactly what makes a user apply the same increase
    /// twice. The routine can still be edited on iPhone.
    private var superseded: some View {
        statusRow(
            systemImage: "iphone.gen3",
            tint: OnyxWatch.Colors.textMuted,
            text: Text(
                "Not applied — changed on iPhone",
                comment: "Recap state when iOS rejected the weight increase because its template had changed"
            )
        )
    }

    // MARK: - Shared

    private func statusRow(systemImage: String, tint: Color, text: Text) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            text
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OnyxWatch.Colors.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
