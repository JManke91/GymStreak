//
//  OnboardingRoutinesSlideView.swift
//  GymStreak
//
//  Step 2 of the first-run tour: what a routine holds.
//  See docs/onboarding.md.
//

import SwiftUI

extension OnboardingFeatureSlideContent {

    static let routines = OnboardingFeatureSlideContent(
        breadcrumbKey: "onboarding.routines.breadcrumb",
        eyebrowKey: "onboarding.routines.eyebrow",
        titleKey: "onboarding.routines.title",
        bodyKey: "onboarding.routines.body",
        bulletKeys: [
            "onboarding.routines.bullet1",
            "onboarding.routines.bullet2"
        ]
    )
}

/// The "Routines" slide: a real expanded routine exercise card above the copy.
struct OnboardingRoutinesSlideView: View {

    var body: some View {
        OnboardingFeatureSlideView(content: .routines) {
            OnboardingRoutinePreview()
        }
    }
}

// MARK: - The preview inside the plate

/// One expanded exercise card as the Routines tab draws it, fed sample values.
///
/// Four production views do the drawing: `ExerciseHeaderView`,
/// `ExerciseParameterChips`, `RoutineSetsEditor` and — through the editor —
/// `RoutineSetStepperRow` — inside the card's shared chassis
/// (`routineExerciseCardChassis()`), which the browsing card uses too.
private struct OnboardingRoutinePreview: View {

    @Environment(\.weightUnit) private var weightUnit

    /// Required by `RoutineSetsEditor`, and never entered: the plate is mounted
    /// with hit testing off, so nothing in it can take focus.
    @FocusState private var valueFocus: Bool

    /// `@State` so the carriers survive a re-render and the set list's `ForEach`
    /// ids stay stable. (The initial-value expression is still re-evaluated on
    /// every view-struct init and all but the first result discarded — three
    /// allocations, which is why it is written inline rather than hoisted.)
    @State private var sampleSets = OnboardingSampleSet.sampleRoutineSets()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            routineTitleRow

            exerciseCard
        }
    }

    private var routineTitleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.sm) {
            Text("onboarding.routines.sample.routine_name".localized)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .kerning(-0.3)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)

            Text("onboarding.routines.sample.routine_meta".localized)
                .font(.onyxMonoLabel)
                .foregroundStyle(Color.white.opacity(0.35))
                .lineLimit(1)
        }
    }

    private var exerciseCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // No `onSupersetAction` / `onEditAlternatives`: without them the
                // header draws no menu, which is both what an inert preview
                // wants and 30pt of width the exercise name gets to keep.
                ExerciseHeaderView(display: OnboardingSampleRoutine.exerciseCard(in: weightUnit))

                // The card is shown expanded, so the disclosure points up — the
                // state the user will see after their first tap.
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .rotationEffect(.degrees(180))
            }

            ExerciseParameterChips(
                restTime: OnboardingSampleRoutine.restTime,
                targetRepMin: OnboardingSampleRoutine.targetRepMin,
                targetRepMax: OnboardingSampleRoutine.targetRepMax,
                openParameter: .constant(nil)
            )
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 12) {
                Divider()
                    .overlay(Color.white.opacity(0.05))
                    .padding(.top, 12)

                RoutineSetsEditor(
                    sets: sampleSets,
                    sectionTitle: "routine.section.sets".localized,
                    targetRepMin: OnboardingSampleRoutine.targetRepMin,
                    targetRepMax: OnboardingSampleRoutine.targetRepMax,
                    valueFocus: $valueFocus,
                    onAddSet: {},
                    onRemoveSet: { _ in },
                    onSetChanged: { _ in },
                    onApplyToAll: { _, _ in }
                )
            }
        }
        .routineExerciseCardChassis()
    }
}

#Preview {
    ScrollView {
        OnboardingRoutinesSlideView()
            .padding(DesignSystem.Spacing.xl)
    }
    .background(DesignSystem.Colors.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
