//
//  OnboardingSampleWorkout.swift
//  GymStreak
//
//  The one mid-workout moment the onboarding tour shows. See docs/onboarding.md.
//

import Foundation

/// What the "Progressive Overload" slide previews, as plain values: one exercise
/// of a running workout whose three sets are all logged at the top of its rep
/// goal — the state that makes the app ask for more weight.
///
/// **This is copy, not data**, on exactly the terms `OnboardingSampleRoutine`
/// sets out: nothing here is inserted, seeded or synced, and the plate that
/// renders it is not interactive.
///
/// The exercise is named by its `SeedExerciseCatalog` key so the tour cannot
/// advertise it under a different name than the library the user lands in uses;
/// its muscle groups and equipment are restated here because `Presentation` does
/// not reach into `Data/Seeding`, and
/// `OnboardingFlowTests.sampleWorkoutAvatarMatchesTheCatalog` is what keeps that
/// copy honest.
enum OnboardingSampleWorkout {

    static let seedKey = "seed.exercise.deadlift"
    static let muscleGroups = ["Lower Back", "Glutes", "Hamstrings"]
    static let equipmentType: EquipmentType = .barbell

    /// A short name in **both** languages ("Deadlift" / "Kreuzheben"), which is
    /// the constraint step 3 already ran into: the plate is narrower than the
    /// real workout screen by the slide's margins, and a single long German word
    /// cannot wrap — it truncates, teaching the user that the app clips names.
    static var name: String { seedKey.localized }

    /// The rep goal. The slide's whole point is that every set landed on
    /// `targetRepMax`, which is what `OverloadPromptCandidate` reports.
    static let targetRepMin = 4
    static let targetRepMax = 6

    /// A heavy compound's rest. Rendered by the card's own chip, so it reads in
    /// the app's format ("2m 30s"), not in a number this file chooses.
    static let restTime: TimeInterval = 150

    /// Canonical kilograms, like everything the store holds — the plate renders
    /// them in the user's own unit through `WeightFormatting`.
    static let kilograms: Double = 90
    static let reps = 6
    static let setCount = 3

    /// Stable for the life of the process; nothing persists it.
    private static let exerciseId = UUID()

    /// The exercise as the active-workout card draws it, with every set done.
    ///
    /// `canSwap` and `isSwapLocked` are both **false**, and that is production
    /// behaviour rather than a simplification: a swap is only offered while the
    /// slot has alternatives *and* no set is logged yet. Three completed sets is
    /// exactly the state in which the real card offers no swap at all, so a
    /// slide showing one would be showing a card the app cannot produce. It also
    /// gives the name and the "3/3 · 4–6" meta line — the two things this slide
    /// actually needs read — the width the plate cannot otherwise spare.
    static let exercise = WorkoutExerciseDisplay(
        id: exerciseId,
        name: name,
        muscleGroups: muscleGroups,
        equipmentType: equipmentType,
        completedSets: setCount,
        totalSets: setCount,
        leadWeight: kilograms,
        isAssistance: false,
        restTime: restTime,
        targetRepMin: targetRepMin,
        targetRepMax: targetRepMax,
        swappedFromName: nil,
        canSwap: false,
        isSwapLocked: false,
        isInSuperset: false
    )

    /// The three logged sets, all at the top of the rep goal.
    ///
    /// **No completion times**, and that is a width decision rather than an
    /// oversight. `WorkoutSetRowView` shows the time a set was checked off at
    /// the right-hand end of the row, and the row is the app's densest: with the
    /// time in it the reps and the weight — the two numbers this whole slide is
    /// about — truncated to "6 W… × … kg" inside the plate. `completedAt` is
    /// optional in production (a set ingested from the Watch can arrive without
    /// one), so a completed row with no time is a row the app itself draws.
    static func completedSets() -> [WorkoutSetDisplay] {
        (0..<setCount).map { index in
            WorkoutSetDisplay(
                id: setIds[index],
                number: index + 1,
                reps: reps,
                weight: kilograms,
                plannedReps: reps,
                plannedWeight: kilograms,
                isCompleted: true,
                completedAt: nil,
                isAssistance: false,
                targetRepMin: targetRepMin,
                targetRepMax: targetRepMax
            )
        }
    }

    /// Stable row identities, so a re-render of the slide does not hand the
    /// set list three new ids to diff.
    private static let setIds = (0..<setCount).map { _ in UUID() }

    /// The prompt the workout screen would be showing at this moment.
    ///
    /// A `.suggestion`, never `.applied`: the slide teaches that the app *asks*.
    /// Note what the bar renders from it — the target rep count, and no weight.
    /// The slide's copy may not promise one either.
    static let prompt = OverloadPrompt.suggestion(
        OverloadPromptCandidate(
            exerciseId: exerciseId,
            exerciseName: name,
            targetRepMax: targetRepMax,
            isAssistance: false
        )
    )
}
