import Foundation

/// Everything an exercise card's header (or sorting row) draws, resolved once
/// per card instead of per render. Building it up front keeps the relationship
/// walks — `setsList`, `alternativesList`, and the `exercise` hop per
/// alternative — and the set-summary formatting out of the row's `body`.
struct RoutineExerciseCardDisplay {
    struct AvatarValues {
        let muscleGroups: [String]
        let equipmentType: EquipmentType
    }

    let name: String
    let avatar: AvatarValues?
    let setSummary: String
    let alternativeAvatars: [AvatarValues]

    init(_ routineExercise: RoutineExercise) {
        name = routineExercise.exercise?.name ?? "Unknown"
        avatar = routineExercise.exercise.map {
            AvatarValues(muscleGroups: $0.muscleGroups, equipmentType: $0.equipmentType)
        }

        let sets = routineExercise.setsList
        setSummary = SetSummaryFormatting.text(
            reps: sets.map(\.reps),
            weights: sets.map(\.weight)
        )

        alternativeAvatars = routineExercise.alternativesList.compactMap { alternative in
            alternative.exercise.map {
                AvatarValues(muscleGroups: $0.muscleGroups, equipmentType: $0.equipmentType)
            }
        }
    }
}
