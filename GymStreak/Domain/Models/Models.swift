import Foundation
import SwiftData

@Model
final class Routine {
    var id: UUID = UUID()
    var name: String = ""
    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    var routineExercises: [RoutineExercise]? = []
    @Relationship(inverse: \WorkoutSession.routine)
    var workoutSessions: [WorkoutSession]? = []
    /// Optional training plan driving the dynamic weekly goal (see
    /// docs/workout-planning.md). Nil ⇒ the routine is unplanned.
    @Relationship(deleteRule: .cascade, inverse: \RoutineSchedule.routine)
    var schedule: RoutineSchedule? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.routineExercises = []
        self.workoutSessions = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // Convenience accessor for non-optional usage
    var routineExercisesList: [RoutineExercise] {
        routineExercises ?? []
    }

    /// Groups exercises by superset for display purposes.
    /// Returns arrays where standalone exercises are single-element arrays
    /// and superset exercises are grouped together in order.
    var exercisesGroupedBySupersets: [[RoutineExercise]] {
        let sorted = routineExercisesList.sorted { $0.order < $1.order }
        var groups: [[RoutineExercise]] = []
        var processedSupersetIds: Set<UUID> = []

        for exercise in sorted {
            if let supersetId = exercise.supersetId {
                // Skip if we've already processed this superset
                guard !processedSupersetIds.contains(supersetId) else { continue }
                processedSupersetIds.insert(supersetId)

                // Gather all exercises in this superset, sorted by supersetOrder
                let supersetExercises = sorted
                    .filter { $0.supersetId == supersetId }
                    .sorted { $0.supersetOrder < $1.supersetOrder }
                groups.append(supersetExercises)
            } else {
                // Standalone exercise
                groups.append([exercise])
            }
        }

        return groups
    }
}

@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""
    var muscleGroups: [String] = ["General"]
    var equipmentTypeRaw: String = EquipmentType.dumbbell.rawValue
    /// Defines whether set weights add resistance or are a counterweight that
    /// assists the user. Defaults preserve existing exercise data.
    var loadBehaviorRaw: String = ExerciseLoadBehavior.resistance.rawValue
    /// Stable identity of a built-in (seeded) exercise — the catalog row's key,
    /// e.g. "seed.exercise.bench_press". Empty for user-created exercises.
    /// CloudKit can't enforce uniqueness, so multi-device seeding is instead kept
    /// duplicate-free by deduplicating on this key (see DefaultContentSeeder).
    var seedKey: String = ""
    @Relationship(inverse: \RoutineExercise.exercise)
    var routineExercises: [RoutineExercise]? = []
    // Inverse for RoutineExerciseAlternative.exercise — CloudKit integration
    // requires EVERY relationship to have a declared inverse; without this the
    // ModelContainer fails to load at launch and the app silently falls back
    // to local-only storage (no iCloud sync).
    @Relationship(inverse: \RoutineExerciseAlternative.exercise)
    var alternativeUses: [RoutineExerciseAlternative]? = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// The equipment type for this exercise
    var equipmentType: EquipmentType {
        get { EquipmentType(rawValue: equipmentTypeRaw) ?? .dumbbell }
        set { equipmentTypeRaw = newValue.rawValue }
    }

    var loadBehavior: ExerciseLoadBehavior {
        get { ExerciseLoadBehavior(rawValue: loadBehaviorRaw) ?? .resistance }
        set { loadBehaviorRaw = newValue.rawValue }
    }

    init(
        name: String,
        muscleGroups: [String] = ["Chest"],
        equipmentType: EquipmentType = .dumbbell,
        loadBehavior: ExerciseLoadBehavior = .resistance
    ) {
        self.id = UUID()
        self.name = name
        self.muscleGroups = muscleGroups
        self.equipmentTypeRaw = equipmentType.rawValue
        self.loadBehaviorRaw = loadBehavior.rawValue
        self.routineExercises = []
        self.alternativeUses = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Convenience computed property for backwards compatibility and display
    var primaryMuscleGroup: String {
        muscleGroups.first ?? "Chest"
    }

    /// Formatted string for displaying all muscle groups
    var muscleGroupsDisplay: String {
        muscleGroups.joined(separator: ", ")
    }
}

@Model
final class RoutineExercise {
    var id: UUID = UUID()
    var routine: Routine?
    var exercise: Exercise?
    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.routineExercise)
    var sets: [ExerciseSet]? = []
    var order: Int = 0

    // Superset fields - iCloud compatible with default values
    var supersetId: UUID? = nil  // Nil if not in superset; shared UUID groups exercises
    var supersetOrder: Int = 0    // Order within superset (0 = first, 1 = second, etc.)

    // Rep range goal - iCloud compatible with default values
    var targetRepMin: Int? = nil   // e.g., 8
    var targetRepMax: Int? = nil   // e.g., 12

    // Alternative exercises - iCloud compatible (nil default, new relationship)
    // The user performs only ONE of: this exercise or one of its alternatives.
    @Relationship(deleteRule: .cascade, inverse: \RoutineExerciseAlternative.routineExercise)
    var alternatives: [RoutineExerciseAlternative]? = nil

    init(exercise: Exercise, order: Int) {
        self.id = UUID()
        self.exercise = exercise
        self.sets = []
        self.order = order
    }

    /// Creates an unattached slot for insertion before SwiftData relationships
    /// are wired to already-persisted models.
    init(order: Int) {
        self.id = UUID()
        self.exercise = nil
        self.sets = []
        self.order = order
    }

    // Convenience accessor for non-optional usage
    var setsList: [ExerciseSet] {
        sets ?? []
    }

    var alternativesList: [RoutineExerciseAlternative] {
        (alternatives ?? []).sorted { $0.order < $1.order }
    }

    var hasAlternatives: Bool {
        !(alternatives ?? []).isEmpty
    }

    var isInSuperset: Bool {
        supersetId != nil
    }

    var hasRepRangeGoal: Bool {
        targetRepMin != nil && targetRepMax != nil
    }

    var allSetsAtUpperLimit: Bool {
        ProgressiveOverloadService.templateQualifiesForIncrease(
            reps: setsList.map(\.reps),
            targetRepMax: targetRepMax
        )
    }
}

@Model
final class ExerciseSet {
    var id: UUID = UUID()
    var reps: Int = 0
    var weight: Double = 0.0
    var restTime: TimeInterval = 60
    var isCompleted: Bool = false
    var order: Int = 0
    var routineExercise: RoutineExercise?

    init(reps: Int, weight: Double, restTime: TimeInterval, order: Int = 0) {
        self.id = UUID()
        self.reps = reps
        self.weight = weight
        self.restTime = restTime
        self.isCompleted = false
        self.order = order
    }
}

@Model
final class RoutineExerciseAlternative {
    var id: UUID = UUID()
    var routineExercise: RoutineExercise?   // the "primary" slot this is an alternative for
    var exercise: Exercise?                  // the alternative exercise
    var order: Int = 0                        // display order among alternatives
    @Relationship(deleteRule: .cascade, inverse: \AlternativeExerciseSet.alternative)
    var sets: [AlternativeExerciseSet]? = []  // this alternative's own set scheme

    // Rep range goal - iCloud compatible with default values (mirrors RoutineExercise).
    // Independent of the primary's goal: an alternative can target its own range.
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil

    init(exercise: Exercise, order: Int) {
        self.id = UUID()
        self.exercise = exercise
        self.order = order
        self.sets = []
    }

    // Convenience accessor for non-optional usage
    var setsList: [AlternativeExerciseSet] {
        (sets ?? []).sorted { $0.order < $1.order }
    }

    var hasRepRangeGoal: Bool {
        targetRepMin != nil && targetRepMax != nil
    }
}

@Model
final class AlternativeExerciseSet {
    var id: UUID = UUID()
    var reps: Int = 0
    var weight: Double = 0.0
    var restTime: TimeInterval = 60
    var order: Int = 0
    var alternative: RoutineExerciseAlternative?

    init(reps: Int, weight: Double, restTime: TimeInterval, order: Int = 0) {
        self.id = UUID()
        self.reps = reps
        self.weight = weight
        self.restTime = restTime
        self.order = order
    }
}

// Data structure to hold exercise information before creating the actual exercise
struct ExerciseData {
    let name: String
    let numberOfSets: Int
    let repsPerSet: Int
    let weightPerSet: Double
    let restTime: TimeInterval
}

// MARK: - Workout Recording Models

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var routine: Routine?
    var routineName: String = "" // Denormalized for history display
    var startTime: Date = Date()
    var endTime: Date?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workoutSession)
    var workoutExercises: [WorkoutExercise]? = []
    var notes: String = ""
    var didUpdateTemplate: Bool = false
    /// The UUID used as HKMetadataKeyExternalUUID when the workout was saved to HealthKit.
    /// Used to correlate this SwiftData record with its HealthKit counterpart.
    var healthKitWorkoutId: UUID?
    /// Optional body mass recorded for this workout. It lets counterweight
    /// exercises calculate the actual load moved (body mass - assistance).
    var bodyWeightKg: Double? = nil

    init(routine: Routine) {
        self.id = UUID()
        self.routine = routine
        self.routineName = routine.name
        self.startTime = Date()
        self.endTime = nil
        self.workoutExercises = []
        self.notes = ""
        self.didUpdateTemplate = false
    }

    // Convenience accessor for non-optional usage
    var workoutExercisesList: [WorkoutExercise] {
        workoutExercises ?? []
    }

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    var completedSetsCount: Int {
        workoutExercisesList.flatMap(\.setsList).filter(\.isCompleted).count
    }

    var totalSetsCount: Int {
        workoutExercisesList.flatMap(\.setsList).count
    }

    var completionPercentage: Int {
        guard totalSetsCount > 0 else { return 0 }
        return Int((Double(completedSetsCount) / Double(totalSetsCount)) * 100)
    }

    var totalVolume: Double {
        workoutExercisesList.reduce(0) { total, exercise in
            let completedSets = exercise.setsList.filter(\.isCompleted)
            return total + completedSets.reduce(0) { subtotal, set in
                let enteredWeight = exercise.progressiveOverloadApplied ? set.plannedWeight : set.actualWeight
                let reps = exercise.progressiveOverloadApplied ? set.plannedReps : set.actualReps
                let weight = ExerciseLoadMetrics.effectiveWeight(
                    enteredWeight: enteredWeight,
                    behavior: exercise.loadBehavior,
                    bodyWeightKg: bodyWeightKg
                ) ?? 0
                return subtotal + (weight * Double(reps))
            }
        }
    }

    /// Groups workout exercises by superset for display purposes.
    var exercisesGroupedBySupersets: [[WorkoutExercise]] {
        let sorted = workoutExercisesList.sorted { $0.order < $1.order }
        var groups: [[WorkoutExercise]] = []
        var processedSupersetIds: Set<UUID> = []

        for exercise in sorted {
            if let supersetId = exercise.supersetId {
                guard !processedSupersetIds.contains(supersetId) else { continue }
                processedSupersetIds.insert(supersetId)

                let supersetExercises = sorted
                    .filter { $0.supersetId == supersetId }
                    .sorted { $0.supersetOrder < $1.supersetOrder }
                groups.append(supersetExercises)
            } else {
                groups.append([exercise])
            }
        }

        return groups
    }
}

@Model
final class WorkoutExercise {
    var id: UUID = UUID()
    var workoutSession: WorkoutSession?
    var exerciseName: String = "" // Denormalized for history display
    var muscleGroups: [String] = []
    var exerciseId: UUID? = nil // Links back to Exercise library for reliable filtering
    /// Stable identity of the source slot in a routine. This is a denormalized
    /// UUID rather than a relationship so history survives routine edits/deletion.
    /// Nil marks legacy history and exercises added ad hoc during a workout.
    var routineExerciseId: UUID? = nil
    /// Snapshot of the source exercise's load behavior. Historical workouts
    /// must not change meaning when the library exercise is edited later.
    var loadBehaviorRaw: String = ExerciseLoadBehavior.resistance.rawValue
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workoutExercise)
    var sets: [WorkoutSet]? = []
    var order: Int = 0

    // Superset fields - denormalized from RoutineExercise for history
    var supersetId: UUID? = nil  // iCloud compatible - must have default
    var supersetOrder: Int = 0    // iCloud compatible - must have default

    // Rep range goal - denormalized from RoutineExercise for history
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil

    // Alternative-exercise swap tracking - iCloud compatible (nil = no swap occurred).
    // exerciseId/exerciseName/muscleGroups always describe what was ACTUALLY performed;
    // these two fields preserve what was originally planned for display/history only.
    var plannedExerciseId: UUID? = nil
    var plannedExerciseName: String? = nil

    // Progressive overload tracking - when true, plannedWeight/plannedReps on sets
    // represent the actual performance (before overload was applied to actual values)
    var progressiveOverloadApplied: Bool = false

    init(from routineExercise: RoutineExercise, order: Int) {
        self.id = UUID()
        self.exerciseId = routineExercise.exercise?.id
        self.routineExerciseId = routineExercise.id
        self.exerciseName = routineExercise.exercise?.name ?? "Unknown"
        self.muscleGroups = routineExercise.exercise?.muscleGroups ?? ["General"]
        self.loadBehaviorRaw = routineExercise.exercise?.loadBehavior.rawValue ?? ExerciseLoadBehavior.resistance.rawValue
        self.order = order
        // Copy superset fields from routine
        self.supersetId = routineExercise.supersetId
        self.supersetOrder = routineExercise.supersetOrder
        // Copy rep range fields from routine
        self.targetRepMin = routineExercise.targetRepMin
        self.targetRepMax = routineExercise.targetRepMax
        // Copy sets from routine, sorted by order
        self.sets = routineExercise.setsList.sorted(by: { $0.order < $1.order }).enumerated().map { index, set in
            WorkoutSet(from: set, order: index)
        }
    }

    init(
        exerciseName: String,
        muscleGroups: [String],
        order: Int,
        exerciseId: UUID? = nil,
        routineExerciseId: UUID? = nil,
        loadBehavior: ExerciseLoadBehavior = .resistance
    ) {
        self.id = UUID()
        self.exerciseId = exerciseId
        self.routineExerciseId = routineExerciseId
        self.exerciseName = exerciseName
        self.muscleGroups = muscleGroups
        self.loadBehaviorRaw = loadBehavior.rawValue
        self.order = order
        self.sets = []
    }

    // Convenience accessor for non-optional usage
    var setsList: [WorkoutSet] {
        sets ?? []
    }

    /// Stable key for grouping/filtering this exercise across sessions.
    /// Prefers exerciseId (links to Exercise library) with fallback to lowercased name for legacy data.
    var stableKey: String {
        exerciseId?.uuidString ?? exerciseName.lowercased()
    }

    var loadBehavior: ExerciseLoadBehavior {
        get { ExerciseLoadBehavior(rawValue: loadBehaviorRaw) ?? .resistance }
        set { loadBehaviorRaw = newValue.rawValue }
    }

    /// Convenience computed property for backwards compatibility
    var primaryMuscleGroup: String {
        muscleGroups.first ?? "General"
    }

    var completedSetsCount: Int {
        setsList.filter(\.isCompleted).count
    }

    var isInSuperset: Bool {
        supersetId != nil
    }

    /// True if this exercise was swapped for an alternative during the workout.
    var wasSwapped: Bool {
        plannedExerciseId != nil
    }

    var hasRepRangeGoal: Bool {
        targetRepMin != nil && targetRepMax != nil
    }

    var allCompletedSetsAtUpperLimit: Bool {
        ProgressiveOverloadService.workoutQualifiesForIncrease(
            sets: setsList.map { .init(reps: $0.actualReps, isCompleted: $0.isCompleted) },
            targetRepMax: targetRepMax,
            overloadAlreadyApplied: progressiveOverloadApplied
        )
    }
}

@Model
final class WorkoutSet {
    var id: UUID = UUID()
    var plannedReps: Int = 0
    var actualReps: Int = 0
    var plannedWeight: Double = 0.0
    var actualWeight: Double = 0.0
    var restTime: TimeInterval = 60
    var isCompleted: Bool = false
    var completedAt: Date?
    var order: Int = 0
    var workoutExercise: WorkoutExercise?

    init(from exerciseSet: ExerciseSet, order: Int) {
        self.id = UUID()
        self.plannedReps = exerciseSet.reps
        self.actualReps = exerciseSet.reps
        self.plannedWeight = exerciseSet.weight
        self.actualWeight = exerciseSet.weight
        self.restTime = exerciseSet.restTime
        self.isCompleted = false
        self.completedAt = nil
        self.order = order
    }

    init(plannedReps: Int, actualReps: Int, plannedWeight: Double, actualWeight: Double, restTime: TimeInterval, order: Int) {
        self.id = UUID()
        self.plannedReps = plannedReps
        self.actualReps = actualReps
        self.plannedWeight = plannedWeight
        self.actualWeight = actualWeight
        self.restTime = restTime
        self.isCompleted = false
        self.completedAt = nil
        self.order = order
    }
}
