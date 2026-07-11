import Foundation
import Combine

@MainActor
final class RoutineStore: ObservableObject {
    @Published var routines: [WatchRoutine] = []
    @Published var isLoading = false
    @Published var lastSyncDate: Date?

    private let userDefaults: UserDefaults?
    private let routinesKey = "syncedRoutines"
    private let lastSyncKey = "lastSyncDate"

    init() {
        // Use App Group for shared storage
        self.userDefaults = UserDefaults(suiteName: "group.com.gymstreak.shared")
        loadRoutines()
    }

    // MARK: - Public Methods

    func updateRoutines(_ newRoutines: [WatchRoutine]) {
        routines = newRoutines
        lastSyncDate = Date()
        saveRoutines()
    }

    func routine(for id: UUID) -> WatchRoutine? {
        routines.first { $0.id == id }
    }

    /// Applies modified workout values back to the stored routine template.
    /// Returns `true` if the routine was found and updated.
    @discardableResult
    func applyWorkoutChanges(routineId: UUID, exercises: [ActiveWorkoutExercise]) -> Bool {
        guard let routineIndex = routines.firstIndex(where: { $0.id == routineId }) else {
            print("RoutineStore: Could not find routine \(routineId) for local update")
            return false
        }

        let routine = routines[routineIndex]

        let updatedExercises = routine.exercises.map { watchExercise -> WatchExercise in
            guard let activeExercise = exercises.first(where: { $0.id == watchExercise.id }) else {
                return watchExercise
            }

            // A swapped exercise's active sets carry the alternative's own set ids,
            // so the modified values belong to that alternative's scheme — the
            // primary's sets stay untouched.
            var updatedSets = watchExercise.sets
            var updatedAlternatives = watchExercise.alternatives

            if activeExercise.wasSwapped {
                updatedAlternatives = watchExercise.alternatives?.map { alternative -> WatchExerciseAlternative in
                    guard alternative.exerciseId == activeExercise.exerciseId else { return alternative }
                    return WatchExerciseAlternative(
                        id: alternative.id,
                        exerciseId: alternative.exerciseId,
                        name: alternative.name,
                        muscleGroup: alternative.muscleGroup,
                        sets: alternative.sets.map { watchSet -> WatchSet in
                            guard let activeSet = activeExercise.sets.first(where: { $0.id == watchSet.id }),
                                  activeSet.wasModified else {
                                return watchSet
                            }
                            return WatchSet(
                                id: watchSet.id,
                                reps: activeSet.actualReps,
                                weight: activeSet.actualWeight,
                                restTime: watchSet.restTime
                            )
                        },
                        order: alternative.order,
                        loadBehaviorRaw: alternative.loadBehaviorRaw
                    )
                }
            } else {
                updatedSets = watchExercise.sets.map { watchSet -> WatchSet in
                    guard let activeSet = activeExercise.sets.first(where: { $0.id == watchSet.id }),
                          activeSet.wasModified else {
                        return watchSet
                    }

                    return WatchSet(
                        id: watchSet.id,
                        reps: activeSet.actualReps,
                        weight: activeSet.actualWeight,
                        restTime: watchSet.restTime
                    )
                }
            }

            return WatchExercise(
                id: watchExercise.id,
                name: watchExercise.name,
                muscleGroup: watchExercise.muscleGroup,
                sets: updatedSets,
                order: watchExercise.order,
                supersetId: watchExercise.supersetId,
                supersetOrder: watchExercise.supersetOrder,
                targetRepMin: watchExercise.targetRepMin,
                targetRepMax: watchExercise.targetRepMax,
                exerciseId: watchExercise.exerciseId,
                loadBehaviorRaw: watchExercise.loadBehaviorRaw,
                alternatives: updatedAlternatives
            )
        }

        routines[routineIndex] = WatchRoutine(
            id: routine.id,
            name: routine.name,
            exercises: updatedExercises
        )

        saveRoutines()
        print("RoutineStore: Locally updated routine '\(routine.name)' with workout changes")
        return true
    }

    // MARK: - Persistence

    private func loadRoutines() {
        isLoading = true
        defer { isLoading = false }

        guard let userDefaults = userDefaults else {
            print("RoutineStore: UserDefaults not available")
            return
        }

        if let data = userDefaults.data(forKey: routinesKey) {
            do {
                routines = try JSONDecoder().decode([WatchRoutine].self, from: data)
                print("RoutineStore: Loaded \(routines.count) routines")
            } catch {
                print("RoutineStore: Failed to decode routines - \(error.localizedDescription)")
            }
        }

        if let syncDate = userDefaults.object(forKey: lastSyncKey) as? Date {
            lastSyncDate = syncDate
        }
    }

    private func saveRoutines() {
        guard let userDefaults = userDefaults else {
            print("RoutineStore: UserDefaults not available")
            return
        }

        do {
            let data = try JSONEncoder().encode(routines)
            userDefaults.set(data, forKey: routinesKey)
            userDefaults.set(lastSyncDate, forKey: lastSyncKey)
            print("RoutineStore: Saved \(routines.count) routines")
        } catch {
            print("RoutineStore: Failed to encode routines - \(error.localizedDescription)")
        }
    }
}
