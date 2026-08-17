//
//  FounderCelebrationView.swift
//  GymStreak
//
//  The one-time Founder thank-you. Shown once to users who installed before
//  monetization, before they can meet anything that looks like a paywall.
//  See docs/pro-subscription.md §5h and docs/monetization-strategy.md §7.
//

import SwiftUI

/// "You're a Founder — Pro is yours, free, forever."
///
/// **It sells nothing.** No offer, no "consider supporting us", no path into a
/// paywall: the app is introducing a subscription to users who downloaded it on
/// the promise that there would never be one, and this screen is the apology and
/// the thank-you, not a marketing beat. The only action is to leave it.
///
/// Presentational by construction — it holds no dependency at all and reports
/// its dismissal through `@Environment(\.dismiss)`, so the host's binding is
/// what spends the once-ever record.
struct FounderCelebrationView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Scrolls rather than compresses: the headline, the body paragraph and
        // three rows overflow a compact screen at German lengths and at
        // accessibility type sizes, and a fixed stack resolves that overflow by
        // silently truncating the text (the mistake `AICoachOptInView` had to
        // be rebuilt to fix). The CTA is pinned below.
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.xl) {
                heroMark

                headlineGroup

                whatIsIncluded

                Text("founder.celebration.footer".localized)
                    .font(.onyxCaption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.top, DesignSystem.Spacing.xl)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // `.onyxProminent` rather than `OnyxButton`, which pins a 50pt
            // height: the label has to be allowed to grow, because this screen
            // must stay readable at accessibility type sizes. Same style the
            // Pro lock kit's CTA uses (docs/pro-subscription.md §5b), so the
            // tint-on-black / `textOnTint` contrast rule is honoured by it.
            Button {
                dismiss()
            } label: {
                Text("founder.celebration.cta".localized)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.onyxProminent)
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.background.ignoresSafeArea(edges: .bottom))
        }
    }

    // MARK: - Hero

    private var heroMark: some View {
        ZStack {
            RadialGradient(
                gradient: Gradient(colors: [
                    DesignSystem.Colors.tint.opacity(0.18),
                    Color.clear
                ]),
                center: .center,
                startRadius: 0,
                endRadius: 80
            )
            .frame(width: 132, height: 132)
            .blur(radius: 12)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.tint)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Headline

    private var headlineGroup: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Text("founder.celebration.eyebrow".localized)
                .font(.onyxCaption)
                .tracking(3.0)
                .foregroundStyle(DesignSystem.Colors.tint)

            Text("founder.celebration.headline".localized)
                .font(.onyxTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("founder.celebration.body".localized)
                .font(.onyxBody)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - What Pro includes

    /// Three rows, deliberately none of them about the AI coach: the coach needs
    /// Apple-Intelligence hardware, and telling a user on an older iPhone that
    /// an unavailable feature is now theirs would turn a thank-you into a
    /// disappointment (`monetization-strategy.md` §4.3 takes the same position
    /// for the paywall).
    ///
    /// A bounded literal set of three, so a plain `VStack` is correct here.
    private var whatIsIncluded: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            IncludedRow(
                icon: "infinity",
                title: "founder.celebration.included1.title".localized,
                detail: "founder.celebration.included1.detail".localized
            )

            IncludedRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "founder.celebration.included2.title".localized,
                detail: "founder.celebration.included2.detail".localized
            )

            IncludedRow(
                icon: "gift.fill",
                title: "founder.celebration.included3.title".localized,
                detail: "founder.celebration.included3.detail".localized
            )
        }
    }
}

// MARK: - Included Row

private struct IncludedRow: View {
    let icon: String
    let title: String
    let detail: String

    /// The glyph column keeps the three titles aligned as the symbols change
    /// width. `@ScaledMetric` rather than a plain constant: a fixed column would
    /// clip the symbol at accessibility type sizes, which is exactly the
    /// rendering this screen has to survive.
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.lg) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.tint)
                .frame(width: iconWidth, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(title)
                    .font(.onyxSubheadline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.onyxCaption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Founder celebration") {
    Color.black
        .fullScreenCover(isPresented: .constant(true)) {
            FounderCelebrationView()
        }
        .preferredColorScheme(.dark)
}

#Preview("Founder celebration — accessibility type") {
    Color.black
        .fullScreenCover(isPresented: .constant(true)) {
            FounderCelebrationView()
                .environment(\.dynamicTypeSize, .accessibility1)
        }
        .preferredColorScheme(.dark)
}
