//
//  OnboardingFeatureSlideView.swift
//  GymStreak
//
//  The layout every onboarding feature slide (steps 2–6) is built from.
//  See docs/onboarding.md.
//

import SwiftUI

/// Everything a feature slide says, as data.
///
/// Declared per slide as a `static let` below, so adding step 3, 4, 5 or 6 is
/// adding an entry and a preview view — never another screen. Nothing here is a
/// literal string: the slide holds keys and the layout resolves them, which is
/// what keeps the copy in `Localizable.strings` where the translations are.
struct OnboardingFeatureSlideContent {

    /// Where in the app the feature lives, e.g. "Routines › Upper Body A".
    let breadcrumbKey: String
    let eyebrowKey: String
    /// Two lines, split with `\n` in the strings file — the line break is a
    /// typographic decision per language, not something the layout can guess.
    let titleKey: String
    let bodyKey: String
    /// Zero or more check bullets. A slide whose feature has no two crisp
    /// sub-points passes an empty array rather than padding it out.
    let bulletKeys: [String]
    /// Whether the eyebrow carries the Pro marker (steps 5 and 6).
    var showsProBadge: Bool = false
    /// See `OnboardingPlate.height` — tuned per slide so the fade lands inside
    /// the preview's content.
    var plateHeight: CGFloat = 376
    var plateFadesOutBottom: Bool = true
}

/// A preview plate above, and the explanation below.
///
/// The plate's content is supplied by the caller and is mounted inertly here,
/// once, for every slide — see `onboardingInertPreview(describing:)`. No slide
/// has to remember to do that, which is the point: the failure it prevents (a
/// haptic firing during the tour) is invisible in a screenshot and in a build.
struct OnboardingFeatureSlideView<Preview: View>: View {

    let content: OnboardingFeatureSlideContent
    private let preview: Preview

    init(content: OnboardingFeatureSlideContent, @ViewBuilder preview: () -> Preview) {
        self.content = content
        self.preview = preview()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            OnboardingPlate(
                breadcrumb: content.breadcrumbKey.localized,
                height: content.plateHeight,
                fadesOutBottom: content.plateFadesOutBottom
            ) {
                preview
                    .onboardingInertPreview(
                        describing: "onboarding.preview.accessibility"
                            .localized(content.breadcrumbKey.localized)
                    )
            }

            copy

            bullets
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Copy

    private var copy: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Text(content.eyebrowKey.localized)
                    .font(.onyxMonoLabel)
                    .tracking(1.6)
                    .foregroundStyle(DesignSystem.Colors.tint)

                if content.showsProBadge {
                    OnyxProBadge()
                }
            }

            // `.onyxTitle`, not the welcome slide's `.onyxDisplay`: the poster
            // is the only screen whose headline has the page to itself.
            Text(content.titleKey.localized)
                .font(.onyxTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(content.bodyKey.localized)
                .font(.onyxFootnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Bullets

    /// A bounded literal set — two or three per slide, declared at compile time
    /// — so a plain `VStack` is the right container.
    @ViewBuilder
    private var bullets: some View {
        if !content.bulletKeys.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                ForEach(content.bulletKeys, id: \.self) { key in
                    OnboardingCheckBullet(text: key.localized)
                }
            }
        }
    }
}
