//
//  OnboardingSampleCoach.swift
//  GymStreak
//
//  The one coach exchange the onboarding tour shows. See docs/onboarding.md.
//

import Foundation

/// What the "AI Coach" slide previews, as plain values: one coach answer about
/// the routine the tour has been building, and the follow-up question a user
/// would ask it.
///
/// **This is copy, not data**, on the terms `OnboardingSampleRoutine` sets out:
/// nothing here is inserted, seeded or synced, no coach request is ever issued,
/// and the plate that renders it is not interactive. The slide is a teaser —
/// the Apple Intelligence opt-in stays its own screen, after the tour.
///
/// **It talks about the tour's own routine.** Steps 2 and 3 build "Upper Body A"
/// out of a lat pulldown plus a pec-deck/hammer-curl superset, and step 5 shows
/// one session of it. So the answer names *those* exercises: the one whose block
/// the reader just watched gain weight, and the one that has not moved. A coach
/// answer about exercises the tour never mentioned would read as a screenshot of
/// somebody else's training.
enum OnboardingSampleCoach {

    // MARK: - Whose numbers these are

    /// The routine the answer is about — step 2's own key, so the tour names it
    /// once and cannot drift.
    static var routineName: String { "onboarding.routines.sample.routine_name".localized }

    /// The exercise carrying the growth: the lat pulldown whose block step 5
    /// shows adding 2.5 kg and 24 % volume. Borrowed from that slide's key
    /// rather than restated.
    static var growingExerciseName: String { OnboardingSampleHistory.seedKey.localized }

    /// The exercise that has not moved: the pec deck from step 3's superset.
    /// Named by its `SeedExerciseCatalog` key, like every exercise the tour
    /// shows, so the tour and the library the user lands in agree.
    static let stagnatingSeedKey = "seed.exercise.pec_deck"

    static var stagnatingExerciseName: String { stagnatingSeedKey.localized }

    /// The weight the pec deck has been stuck at — the weight step 3's superset
    /// card actually plans for it, in canonical kilograms so the plate prints it
    /// in the reader's own unit.
    ///
    /// Restated here rather than reached for across the sample files, matching
    /// how the avatars restate their muscle groups.
    /// `OnboardingFlowTests.coachSampleStagnatesAtTheRoutinesWeight` compares it
    /// against `OnboardingSampleRoutine`, so the two cannot disagree silently.
    static let stagnatingKilograms: Double = 37.5

    // MARK: - The exchange

    /// The answer, with `**…**` around the one figure the surface accents. The
    /// emphasis lives in the string because which figure carries a sentence is a
    /// translation decision, and `OnboardingAICoachSlideView` colours whatever
    /// the translator marked — the same thing `ProgressiveOverloadCard` does.
    static func answer(weightLabel: String) -> String {
        "onboarding.coach.sample.answer".localized(
            routineName,
            growingExerciseName,
            stagnatingExerciseName,
            weightLabel
        )
    }

    /// The follow-up the user bubble asks. It picks up the answer's own loose
    /// end, which is what makes the two read as one conversation.
    static var question: String {
        "onboarding.coach.sample.question".localized(stagnatingExerciseName)
    }

    // MARK: - What the free tier gets

    /// The allowance line under the exchange.
    ///
    /// **The number is read from `ProFeatureCaps`, never typed.** Retuning a
    /// taster cap is meant to be a one-line diff (monetization §4), and a slide
    /// carrying its own copy of the figure would start lying the day that line
    /// changes. It resolves here rather than in the view so
    /// `OnboardingFlowTests.coachAllowanceLineFollowsTheCap` can assert on the
    /// finished sentence.
    static var allowanceLine: String {
        "onboarding.coach.allowance".localized(ProFeatureCaps.freeCoachChatMessagesPerMonth)
    }
}
