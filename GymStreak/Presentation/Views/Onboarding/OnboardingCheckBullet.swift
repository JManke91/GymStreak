//
//  OnboardingCheckBullet.swift
//  GymStreak
//
//  One "the app does this" line, shared by every onboarding slide.
//  See docs/onboarding.md.
//

import SwiftUI

/// A tinted check chip and a label.
///
/// A chip with a thin check rather than a solid `checkmark.circle.fill`: three
/// filled accent discs stacked in a column pull the eye off the headline, which
/// is what the slide is actually selling.
struct OnboardingCheckBullet: View {

    let text: String

    /// The chip scales with the label beside it. Fixed sizes here would leave an
    /// 18pt disc next to text 2.5× that size at AX5 — the mistake
    /// `FounderCelebrationView` already solves the same way.
    @ScaledMetric(relativeTo: .footnote) private var chipSize: CGFloat = 18
    @ScaledMetric(relativeTo: .footnote) private var glyphSize: CGFloat = 9
    @ScaledMetric(relativeTo: .footnote) private var baselineInset: CGFloat = 4

    var body: some View {
        // `alignmentGuide`'s `computeValue` is `@Sendable` and `nonisolated` in the
        // SDK — SwiftUI runs it during layout, off this view's actor. Reading
        // `baselineInset` (a MainActor-isolated `@ScaledMetric` on `self`) from
        // inside it captures `self` across that boundary. Snapshotting the CGFloat
        // here, on the main actor, is what the closure is meant to receive: it then
        // captures a `Sendable` value and nothing else. See CLAUDE.md §4a —
        // outbound closure boundaries are where a green build still traps at runtime.
        let scaledBaselineInset = baselineInset

        return HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.tint.opacity(0.14))
                    .overlay {
                        Circle().strokeBorder(DesignSystem.Colors.tint.opacity(0.34), lineWidth: 1)
                    }

                Image(systemName: "checkmark")
                    .font(.system(size: glyphSize, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.tint)
            }
            .frame(width: chipSize, height: chipSize)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - scaledBaselineInset }

            Text(text)
                .font(.onyxFootnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
