import Foundation

/// Everything an exercise card's header (or sorting row) draws, resolved once
/// per card instead of per render. Building it up front keeps the relationship
/// walks — `setsList`, `alternativesList`, and the `exercise` hop per
/// alternative — and the set-summary formatting out of the row's `body`.
///
/// The header renders from this struct alone: it carries the slot's `id` (the
/// superset connector anchor) and the two menu-label facts that used to be read
/// straight off the `RoutineExercise`. The memberwise initializer exists so a
/// caller with no model — the onboarding slides — can build one.
struct RoutineExerciseCardDisplay {
    struct AvatarValues {
        let muscleGroups: [String]
        let equipmentType: EquipmentType
    }

    /// The `RoutineExercise.id` of the slot this card shows. Identifies the
    /// header's connector anchor inside a superset group.
    let id: UUID
    let name: String
    let avatar: AvatarValues?
    let setSummary: String
    let alternativeAvatars: [AvatarValues]
    let isInSuperset: Bool
    /// Every alternative on the slot, including ones whose library exercise is
    /// missing — so it is not `alternativeAvatars.count`, which drops those.
    let alternativesCount: Int

    var hasAlternatives: Bool { alternativesCount > 0 }

    init(
        id: UUID,
        name: String,
        avatar: AvatarValues?,
        setSummary: String,
        alternativeAvatars: [AvatarValues] = [],
        isInSuperset: Bool = false,
        alternativesCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.setSummary = setSummary
        self.alternativeAvatars = alternativeAvatars
        self.isInSuperset = isInSuperset
        self.alternativesCount = alternativesCount
    }

    /// - Parameter unit: the unit the card renders weights in, read from
    ///   `\.weightUnit` by the view that builds this display.
    init(_ routineExercise: RoutineExercise, in unit: WeightUnit) {
        id = routineExercise.id
        name = routineExercise.exercise?.name ?? "Unknown"
        avatar = routineExercise.exercise.map {
            AvatarValues(muscleGroups: $0.muscleGroups, equipmentType: $0.equipmentType)
        }

        let sets = routineExercise.setsList
        setSummary = SetSummaryFormatting.text(
            reps: sets.map(\.reps),
            weights: sets.map(\.weight),
            in: unit
        )

        let alternatives = routineExercise.alternativesList
        alternativeAvatars = alternatives.compactMap { alternative in
            alternative.exercise.map {
                AvatarValues(muscleGroups: $0.muscleGroups, equipmentType: $0.equipmentType)
            }
        }
        alternativesCount = alternatives.count
        isInSuperset = routineExercise.isInSuperset
    }
}

extension RoutineExerciseCardDisplay {
    /// A Create-Routine draft row, drawn by the same card as a saved exercise.
    /// The draft is a value type, so there is no relationship walk to hoist —
    /// only the set-summary formatting, same as the model initializer.
    init(_ pending: PendingRoutineExercise, in unit: WeightUnit) {
        self.init(
            id: pending.id,
            name: pending.exercise.name,
            avatar: AvatarValues(
                muscleGroups: pending.exercise.muscleGroups,
                equipmentType: pending.exercise.equipmentType
            ),
            setSummary: SetSummaryFormatting.text(
                reps: pending.sets.map(\.reps),
                weights: pending.sets.map(\.weight),
                in: unit
            ),
            alternativeAvatars: pending.alternatives.map {
                AvatarValues(muscleGroups: $0.exercise.muscleGroups, equipmentType: $0.exercise.equipmentType)
            },
            isInSuperset: pending.supersetId != nil,
            alternativesCount: pending.alternatives.count
        )
    }
}
