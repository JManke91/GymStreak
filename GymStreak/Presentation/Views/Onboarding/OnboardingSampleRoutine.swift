//
//  OnboardingSampleRoutine.swift
//  GymStreak
//
//  The one routine the onboarding tour shows. See docs/onboarding.md.
//

import Foundation

/// What the "Routines" and "Supersets" slides preview, as plain values: one
/// expanded exercise slot (step 2) and one two-member superset (step 3), both
/// from the same sample routine.
///
/// **This is copy, not data.** It is written here for the same reason the
/// slide's headline is written in `Localizable.strings`: it is what onboarding
/// *says*, and the tour has no store, no model context and no business reason to
/// fabricate persisted objects. Nothing here is ever inserted, seeded or synced,
/// and the plate that renders it is not interactive — so there is no path from
/// these numbers into the user's library.
///
/// The exercise and its alternative are named by their `SeedExerciseCatalog`
/// keys rather than by literals, so the tour cannot advertise an exercise under
/// a different name than the library the user lands in uses. Their muscle groups
/// and equipment are repeated here rather than read from the catalog, because
/// `Presentation` does not reach into `Data`. That copy is held honest by
/// `OnboardingFlowTests.sampleRoutineAvatarsMatchTheCatalog`, which compares it
/// against `SeedExerciseCatalog` from the test target — otherwise the avatar's
/// colour and glyph would drift the day a catalog row changes.
enum OnboardingSampleRoutine {

    /// A planned set: the reps and the weight, in canonical kilograms exactly as
    /// the store holds them, so the plate renders in the user's own unit.
    struct PlannedSet {
        let reps: Int
        let kilograms: Double
    }

    static let restTime: TimeInterval = 90
    static let targetRepMin = 10
    static let targetRepMax = 12

    /// Three identical sets, which is what a real routine slot looks like: the
    /// uniform scheme is also what makes the header read "3 × 10 reps · 55 kg"
    /// rather than the mixed-weight fallback.
    static let plannedSets: [PlannedSet] = [
        PlannedSet(reps: 10, kilograms: 55),
        PlannedSet(reps: 10, kilograms: 55),
        PlannedSet(reps: 10, kilograms: 55)
    ]

    /// - Parameter unit: the unit the plate renders weights in, read from
    ///   `\.weightUnit` by the view that builds this display.
    static func exerciseCard(in unit: WeightUnit) -> RoutineExerciseCardDisplay {
        RoutineExerciseCardDisplay(
            id: slotId,
            name: "seed.exercise.lat_pulldown".localized,
            avatar: RoutineExerciseCardDisplay.AvatarValues(
                muscleGroups: ["Lats", "Biceps"],
                equipmentType: .cable
            ),
            setSummary: SetSummaryFormatting.text(
                reps: plannedSets.map(\.reps),
                weights: plannedSets.map(\.kilograms),
                in: unit
            ),
            // Pull-Up: a real alternative for a lat pulldown, so the avatar
            // stack in the header is teaching something true.
            alternativeAvatars: [
                RoutineExerciseCardDisplay.AvatarValues(
                    muscleGroups: ["Lats", "Biceps", "Upper Back"],
                    equipmentType: .bodyweight
                )
            ],
            alternativesCount: 1
        )
    }

    /// Stable for the life of the process, because `ExerciseHeaderView` uses it
    /// as the superset connector's anchor id. Nothing persists it.
    private static let slotId = UUID()

    // MARK: - Step 3: the superset

    /// One collapsed member card of the sample superset, as plain values.
    ///
    /// Same rules as the slot above: named by its `SeedExerciseCatalog` key,
    /// with the muscle groups and equipment restated locally because
    /// `Presentation` does not reach into `Data` — and pinned against the
    /// catalog by `OnboardingFlowTests.sampleSupersetAvatarsMatchTheCatalog`.
    struct SupersetMember: Identifiable {
        /// Stable for the life of the process: it is the id the member's header
        /// publishes its connector anchor under. Nothing persists it.
        let id = UUID()
        let seedKey: String
        let muscleGroups: [String]
        let equipmentType: EquipmentType
        let plannedSets: [PlannedSet]
        let targetRepMin: Int
        let targetRepMax: Int

        var name: String { seedKey.localized }

        /// - Parameter unit: the unit the plate renders weights in.
        func card(in unit: WeightUnit) -> RoutineExerciseCardDisplay {
            RoutineExerciseCardDisplay(
                id: id,
                name: name,
                avatar: RoutineExerciseCardDisplay.AvatarValues(
                    muscleGroups: muscleGroups,
                    equipmentType: equipmentType
                ),
                setSummary: SetSummaryFormatting.text(
                    reps: plannedSets.map(\.reps),
                    weights: plannedSets.map(\.kilograms),
                    in: unit
                ),
                isInSuperset: true
            )
        }
    }

    /// The letter the tour's group carries. "A" is not a choice: the label
    /// provider hands the first superset of a routine the first letter, and the
    /// slide shows a first-time user's first group.
    /// `OnboardingFlowTests.theFirstSupersetOfARoutineIsLabelledA` pins that.
    static let supersetLetter = "A"

    /// The whole group shares one rest time — that is the point the slide makes,
    /// and it is how the real screen resolves it (the group's rest lives on its
    /// last member and every member card shows it).
    static let supersetRestTime: TimeInterval = 90

    /// A chest machine paired with a curl: two exercises that use nothing of
    /// each other, which is exactly when a superset is worth doing. Both carry a
    /// rep range, so neither card shows the empty "set a goal" chip — a still
    /// image cannot explain an affordance nobody can tap.
    ///
    /// Both were also picked for the *length* of their names. The plate is
    /// narrower than the real screen by the slide's margins, and
    /// `ExerciseHeaderView` truncates a name to one line: the German
    /// "Fliegende (Kurzhantel)" and "Bizeps-Curls (Kurzhantel)" both ellipsised
    /// here while reading fine in the app, which teaches the user that the app
    /// clips names. These two do not.
    static let supersetMembers: [SupersetMember] = [
        SupersetMember(
            seedKey: "seed.exercise.pec_deck",
            muscleGroups: ["Chest"],
            equipmentType: .machine,
            plannedSets: [
                PlannedSet(reps: 10, kilograms: 37.5),
                PlannedSet(reps: 10, kilograms: 37.5),
                PlannedSet(reps: 10, kilograms: 37.5)
            ],
            targetRepMin: 8,
            targetRepMax: 12
        ),
        SupersetMember(
            seedKey: "seed.exercise.hammer_curl",
            muscleGroups: ["Biceps", "Forearms"],
            equipmentType: .dumbbell,
            plannedSets: [
                PlannedSet(reps: 10, kilograms: 14),
                PlannedSet(reps: 10, kilograms: 14),
                PlannedSet(reps: 10, kilograms: 14)
            ],
            targetRepMin: 8,
            targetRepMax: 12
        )
    ]
}

/// One sample set as `RoutineSetsEditor` wants it.
///
/// The editor's `AlternativeEditableSet` is a class protocol with settable
/// properties, because on the real screen the rows write straight back to the
/// `@Model` they came from. The plate never writes: it is mounted with hit
/// testing off, so no stepper, field or remove button can ever be reached. This
/// carrier exists only so the *production* set editor can be used verbatim
/// instead of the slide drawing its own set list — see docs/onboarding.md.
final class OnboardingSampleSet: AlternativeEditableSet {
    let id = UUID()
    var reps: Int
    var weight: Double
    var restTime: TimeInterval
    var order: Int

    init(_ planned: OnboardingSampleRoutine.PlannedSet, order: Int, restTime: TimeInterval) {
        self.reps = planned.reps
        self.weight = planned.kilograms
        self.order = order
        self.restTime = restTime
    }

    /// A fresh set of carriers. Not a stored constant: a mutable reference type
    /// shared across the app would be global mutable state, and these cost three
    /// allocations once per slide.
    static func sampleRoutineSets() -> [OnboardingSampleSet] {
        OnboardingSampleRoutine.plannedSets.enumerated().map { index, planned in
            OnboardingSampleSet(planned, order: index, restTime: OnboardingSampleRoutine.restTime)
        }
    }
}
