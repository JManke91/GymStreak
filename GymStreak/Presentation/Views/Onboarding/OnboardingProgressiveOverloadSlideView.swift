//
//  OnboardingProgressiveOverloadSlideView.swift
//  GymStreak
//
//  Step 4 of the first-run tour: the app asks for more weight by itself.
//  See docs/onboarding.md.
//

import SwiftUI

extension OnboardingFeatureSlideContent {

    static let progressiveOverload = OnboardingFeatureSlideContent(
        breadcrumbKey: "onboarding.overload.breadcrumb",
        eyebrowKey: "onboarding.overload.eyebrow",
        titleKey: "onboarding.overload.title",
        bodyKey: "onboarding.overload.body",
        bulletKeys: [
            "onboarding.overload.bullet1",
            "onboarding.overload.bullet2"
        ],
        // The prompt is the payoff of the slide and the real screen pins it to
        // the bottom edge, so it must be whole — a fade over the thing the slide
        // is about would be the one crop that costs the reader the point. The
        // plate therefore fits its content, like step 3's, and the height is a
        // measured sum rather than a round number: the card (header, rest chip,
        // three 62 pt set rows, the dashed "Add set" button and its 14 pt
        // padding), the 10 pt gap, the prompt bar, and the panel's own
        // breadcrumb and padding. Change the set row's `minHeight` or the card's
        // padding and the prompt loses its bottom edge with no fade to admit it
        // — re-measure here when either moves.
        plateHeight: 500,
        plateFadesOutBottom: false,
        // The set row is the app's densest: a 62 pt completion zone, two value
        // chips, an optional completion time and a menu — close to truncation
        // even on a 375 pt phone in the app itself. At the default 12 pt inset
        // it truncated here into "6 W… × … kg", ellipsising the two numbers this
        // slide exists to show. Four points is still a visible margin around the
        // card, and together with the sample's missing completion time (see
        // `OnboardingSampleWorkout.completedSets()`) the row fits from the
        // smallest supported phone up.
        plateContentInset: 4
    )
}

/// The "Progressive Overload" slide: a finished exercise and the prompt it
/// triggers, above the copy.
struct OnboardingProgressiveOverloadSlideView: View {

    var body: some View {
        OnboardingFeatureSlideView(content: .progressiveOverload) {
            OnboardingOverloadPreview()
        }
    }
}

// MARK: - The preview inside the plate

/// One exercise of a running workout with every set logged at the top of its rep
/// goal, and the prompt that state produces.
///
/// Both pieces are the production views: `WorkoutExerciseCardView` with
/// `WorkoutSetRowView` inside it, and `WorkoutOverloadPromptBar` itself. The bar
/// is **not** reimplemented and not restyled — what it says is the app's own
/// message, which names the rep goal and never a next weight. The slide's copy
/// is written to that, not to a mock.
///
/// The bar sits directly under the card because that is where the workout screen
/// puts it: a bottom safe-area inset below the scrolling exercise list, not
/// something inside the card (see `WorkoutOverloadPromptBar`'s own note on why
/// it had to leave the card).
private struct OnboardingOverloadPreview: View {

    /// Plain `let`: these are value structs whose ids come from a `static let`,
    /// so the list is stable across re-renders without `@State` holding it. (The
    /// reference-type carriers step 2 hands the routine set editor do need it.)
    private let sets = OnboardingSampleWorkout.completedSets()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            card

            prompt
        }
    }

    private var card: some View {
        WorkoutExerciseCardView(
            display: OnboardingSampleWorkout.exercise,
            supersetBadge: nil,
            setRows: {
                // Three rows, fixed at compile time — a bounded literal set, so
                // the card's own plain stack is the right container.
                ForEach(sets) { set in
                    WorkoutSetRowView(
                        display: set,
                        isNext: false,
                        onToggleCompleted: {},
                        onEdit: { _ in },
                        onDuplicate: {},
                        onDelete: {}
                    )
                }
            },
            onSwap: {},
            onSwapLockedInfo: {},
            onRestTimeChange: { _ in },
            onAddSet: {},
            onRemoveExercise: {}
        )
    }

    /// The shipped prompt, with the tour's own marker pinned to its corner.
    ///
    /// Every closure is inert: the plate mounts its content with hit testing
    /// off, so neither "Increase" nor the dismiss X can be reached. The banner's
    /// success haptic is the side effect that survives a dead pointer, and it is
    /// suppressed by `\.isOnboardingPreview`, which
    /// `onboardingInertPreview(describing:)` puts in the environment.
    private var prompt: some View {
        WorkoutOverloadPromptBar(
            prompt: OnboardingSampleWorkout.prompt,
            onIncrease: {},
            onDismiss: {}
        )
        .overlay(alignment: .topTrailing) {
            // Tour chrome, in the tour's own accent rather than the banner's
            // orange, so it reads as the slide talking about the prompt instead
            // of as a control inside it. What it marks is the thing a still
            // picture cannot show: nobody asked for this bar — it appeared.
            OnboardingChromePill(
                text: "onboarding.overload.callout".localized,
                systemImage: "bolt.fill",
                color: DesignSystem.Colors.tint
            )
            // Lifted onto the bar's top-right corner, but not pushed outwards:
            // this slide's plate holds its content only 4 pt off the panel edge,
            // so a horizontal overhang would put the pill against the rounded
            // corner it has to stay clear of.
            .offset(y: -8)
        }
    }
}

#Preview {
    ScrollView {
        OnboardingProgressiveOverloadSlideView()
            .padding(DesignSystem.Spacing.xl)
    }
    .background(DesignSystem.Colors.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
