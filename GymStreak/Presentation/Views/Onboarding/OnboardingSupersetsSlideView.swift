//
//  OnboardingSupersetsSlideView.swift
//  GymStreak
//
//  Step 3 of the first-run tour: what a superset is.
//  See docs/onboarding.md.
//

import SwiftUI

extension OnboardingFeatureSlideContent {

    static let supersets = OnboardingFeatureSlideContent(
        // The same breadcrumb key as step 2, deliberately: both slides show the
        // same sample routine, and the tour would be lying if it sent the user
        // to two different places for one screen.
        breadcrumbKey: "onboarding.routines.breadcrumb",
        eyebrowKey: "onboarding.supersets.eyebrow",
        titleKey: "onboarding.supersets.title",
        bodyKey: "onboarding.supersets.body",
        bulletKeys: [
            "onboarding.supersets.bullet1",
            "onboarding.supersets.bullet2"
        ],
        // The group ends inside the plate, so there is nothing below it to
        // imply — this is the whole superset, which is the slide's point.
        //
        // Without the fade the plate hard-clips, so the height is a measured fit
        // rather than a round number: two 97 pt collapsed cards, the 28 pt seam,
        // their 4 pt vertical padding, the caption and the panel's own padding,
        // leaving ~20 pt of slack. Change the card padding, the chip strip or
        // `SupersetSeamSpacer.height` and the second card loses its bottom edge
        // with no fade to admit it — re-measure here when any of those move.
        plateHeight: 330,
        plateFadesOutBottom: false
    )
}

/// The "Supersets" slide: two collapsed exercise cards joined by the real
/// connector, above the copy.
struct OnboardingSupersetsSlideView: View {

    var body: some View {
        OnboardingFeatureSlideView(content: .supersets) {
            OnboardingSupersetPreview()
        }
    }
}

// MARK: - The preview inside the plate

/// One superset as the Routines tab draws it, fed sample values.
///
/// The connector is `SupersetGroupContainer` itself — the production component,
/// not a line drawn to look like it. It owns the stroke, the end dots and the
/// unlink control at the seam, and it positions all three from anchors the
/// member headers publish, so the geometry here is the shipped geometry. Its
/// `onUnlink` is inert, like everything else inside a plate.
private struct OnboardingSupersetPreview: View {

    @Environment(\.weightUnit) private var weightUnit

    private var members: [OnboardingSampleRoutine.SupersetMember] {
        OnboardingSampleRoutine.supersetMembers
    }

    /// The production mapping from the group's letter to its colour, so the tour
    /// and the Routines screen tint the first superset identically.
    private var color: Color {
        SupersetLabelProvider.color(for: OnboardingSampleRoutine.supersetLetter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OnboardingChromePill(
                text: "superset.label".localized(OnboardingSampleRoutine.supersetLetter),
                color: color
            )

            group
        }
    }

    private var group: some View {
        SupersetGroupContainer(
            members: members.map { SupersetGroupContainer.Member(id: $0.id, name: $0.name) },
            color: color,
            onUnlink: { _ in }
        ) {
            // Two members, declared at compile time: a bounded literal set, so
            // a plain stack is the right container. The seam between them is
            // where the container draws its unlink control.
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                memberCard(member, position: index + 1)
                    .padding(.vertical, 4)

                if index < members.count - 1 {
                    SupersetSeamSpacer(memberAboveId: member.id)
                }
            }
        }
    }

    /// A member card in its collapsed state — header, disclosure chevron and the
    /// chip strip, which the real card shows whether or not it is expanded.
    private func memberCard(
        _ member: OnboardingSampleRoutine.SupersetMember,
        position: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // No `onSupersetAction` / `onEditAlternatives`, so no overflow
                // menu — same call as step 2, for the same reasons.
                ExerciseHeaderView(
                    display: member.card(in: weightUnit),
                    supersetPosition: position,
                    supersetTotal: members.count,
                    supersetColor: color,
                    isSupersetMember: true
                )

                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }

            ExerciseParameterChips(
                restTime: OnboardingSampleRoutine.supersetRestTime,
                targetRepMin: member.targetRepMin,
                targetRepMax: member.targetRepMax,
                openParameter: .constant(nil)
            )
            .padding(.top, 10)
            // The header keeps the connector lane free; everything below it has
            // to clear the same channel, or the group's line runs straight
            // through the chip strip.
            .padding(.leading, ExerciseHeaderView.connectorLaneWidth)
        }
        .routineExerciseCardChassis(color: color)
    }
}

// MARK: - Onboarding chrome

/// A caption the *tour* adds above a preview. **Not a piece of the Routines
/// screen** — the app draws no pill like this anywhere, and the user will not
/// find one.
///
/// It exists because a still image of two linked cards does not say what the
/// link is called. Its text is therefore production's own name for the group
/// (`superset.label` → "Superset A"), never an invented label: a slide that
/// captions a feature with words the app never uses sends the user looking for
/// something that is not there.
private struct OnboardingChromePill: View {

    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "link")
                .font(.system(size: 9, weight: .bold))

            Text(text.uppercased())
                .font(.onyxMonoLabel)
                .tracking(1.3)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(color.opacity(0.38), lineWidth: 1))
    }
}

#Preview {
    ScrollView {
        OnboardingSupersetsSlideView()
            .padding(DesignSystem.Spacing.xl)
    }
    .background(DesignSystem.Colors.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
