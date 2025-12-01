import Foundation
import SwiftData
import SwiftUI

@MainActor
class RoutinesViewModel: ObservableObject {
    @Published var routines: [Routine] = []
    @Published var showingAddRoutine = false
    @Published var selectedRoutine: Routine?

    private var modelContext: ModelContext
    private let watchConnectivity = WatchConnectivityManager.shared

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchRoutines()
        observeWatchWorkoutCompletions()
        processPendingWatchWorkouts()
    }

    private func observeWatchWorkoutCompletions() {
        NotificationCenter.default.addObserver(
            forName: .watchWorkoutCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let workout = notification.userInfo?["workout"] as? CompletedWatchWorkout else {
                return
            }
            Task { @MainActor in
                self?.handleCompletedWatchWorkout(workout)
            }
        }
    }

    private func processPendingWatchWorkouts() {
        // Check for any workouts that arrived before we started observing
        if let pendingWorkout = watchConnectivity.processPendingWorkout() {
            print("Processing pending watch workout: \(pendingWorkout.routineName)")
            handleCompletedWatchWorkout(pendingWorkout)
        }
    }

    func updateModelContext(_ newContext: ModelContext) {
        self.modelContext = newContext
        fetchRoutines()
    }

    func fetchRoutines() {
        let descriptor = FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        do {
            routines = try modelContext.fetch(descriptor)
            syncRoutinesToWatch()
        } catch {
            print("Error fetching routines: \(error)")
        }
    }

    // MARK: - Watch Connectivity

    private func syncRoutinesToWatch() {
        watchConnectivity.syncRoutines(routines)
    }
    
    func addRoutine(name: String) {
        let routine = Routine(name: name)
        modelContext.insert(routine)
        save()
        fetchRoutines()
    }
    
    func updateRoutine(_ routine: Routine) {
        routine.updatedAt = Date()
        save()
        fetchRoutines()
    }
    
    func deleteRoutine(_ routine: Routine) {
        modelContext.delete(routine)
        save()
        fetchRoutines()
    }
    
    func removeRoutineExercise(_ routineExercise: RoutineExercise, from routine: Routine) {
        if let index = routine.routineExercises.firstIndex(where: { $0.id == routineExercise.id }) {
            routine.routineExercises.remove(at: index)
            modelContext.delete(routineExercise)
            updateRoutine(routine)
        }
    }
    
    func addSet(to routineExercise: RoutineExercise) {
        // Get rest time from existing sets, or default to 0 (disabled)
        let restTime = routineExercise.sets.first?.restTime ?? 0
        let set = ExerciseSet(reps: 10, weight: 0.0, restTime: restTime)
        set.routineExercise = routineExercise
        routineExercise.sets.append(set)
        if let routine = routineExercise.routine {
            updateRoutine(routine)
        }
    }
    
    func removeSet(_ set: ExerciseSet, from routineExercise: RoutineExercise) {
        if let index = routineExercise.sets.firstIndex(where: { $0.id == set.id }) {
            routineExercise.sets.remove(at: index)
            modelContext.delete(set)
            if let routine = routineExercise.routine {
                updateRoutine(routine)
            }
        }
    }

    func updateSet(_ set: ExerciseSet) {
        // SwiftData will automatically track changes to the set
        if let routine = set.routineExercise?.routine {
            updateRoutine(routine)
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }

    // MARK: - Watch Workout Handling

    private func handleCompletedWatchWorkout(_ workout: CompletedWatchWorkout) {
        print("Received completed watch workout: \(workout.routineName)")

        // Step 1: Create WorkoutSession to appear in history
        do {
            // Find the routine by ID
            let descriptor = FetchDescriptor<Routine>(
                predicate: #Predicate { routine in
                    routine.id == workout.routineId
                }
            )

            let routine = try modelContext.fetch(descriptor).first

            // Create workout session
            let workoutSession = WorkoutSession(routine: routine ?? createPlaceholderRoutine(from: workout))
            workoutSession.startTime = workout.startTime
            workoutSession.endTime = workout.endTime
            workoutSession.didUpdateTemplate = workout.shouldUpdateTemplate
            workoutSession.routineName = workout.routineName

            // Create workout exercises
            for completedExercise in workout.exercises {
                let workoutExercise = WorkoutExercise(
                    exerciseName: completedExercise.name,
                    muscleGroup: completedExercise.muscleGroup,
                    order: completedExercise.order
                )
                workoutExercise.workoutSession = workoutSession

                // Create workout sets
                for completedSet in completedExercise.sets {
                    let workoutSet = WorkoutSet(
                        plannedReps: completedSet.plannedReps,
                        actualReps: completedSet.actualReps,
                        plannedWeight: completedSet.plannedWeight,
                        actualWeight: completedSet.actualWeight,
                        restTime: completedSet.restTime,
                        order: completedSet.order
                    )
                    workoutSet.isCompleted = completedSet.isCompleted
                    workoutSet.completedAt = completedSet.completedAt
                    workoutSet.workoutExercise = workoutExercise
                    workoutExercise.sets.append(workoutSet)
                    modelContext.insert(workoutSet)
                }

                workoutSession.workoutExercises.append(workoutExercise)
                modelContext.insert(workoutExercise)
            }

            modelContext.insert(workoutSession)
            try modelContext.save()
            print("Created workout session from watch workout: \(workout.routineName)")

        } catch {
            print("Error creating workout session from watch workout: \(error)")
        }

        // Step 2: Optionally update routine template
        guard workout.shouldUpdateTemplate else {
            print("Not updating template - user chose not to update")
            return
        }

        // Find the routine by ID
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { routine in
                routine.id == workout.routineId
            }
        )

        do {
            guard let routine = try modelContext.fetch(descriptor).first else {
                print("Could not find routine with ID: \(workout.routineId)")
                return
            }

            print("Updating template for routine: \(routine.name)")
            var updatedAny = false

            // Update each routine exercise's sets with the actual values
            for completedExercise in workout.exercises {
                guard let routineExercise = routine.routineExercises.first(where: { $0.id == completedExercise.id }) else {
                    print("Could not find routine exercise with ID: \(completedExercise.id)")
                    continue
                }

                for completedSet in completedExercise.sets {
                    guard let set = routineExercise.sets.first(where: { $0.id == completedSet.id }) else {
                        print("Could not find set with ID: \(completedSet.id)")
                        continue
                    }

                    // Only update if the set was modified
                    if completedSet.actualReps != completedSet.plannedReps ||
                       completedSet.actualWeight != completedSet.plannedWeight {
                        set.reps = completedSet.actualReps
                        set.weight = completedSet.actualWeight
                        updatedAny = true
                        print("Updated set: \(completedSet.actualWeight)lbs × \(completedSet.actualReps) reps")
                    }
                }
            }

            if updatedAny {
                updateRoutine(routine)
                print("Template updated successfully - \(workout.modifiedSetsCount) sets modified")
            } else {
                print("No sets were actually modified")
            }

        } catch {
            print("Error updating routine template: \(error)")
        }
    }

    // Helper method to create a placeholder routine if the original was deleted
    private func createPlaceholderRoutine(from workout: CompletedWatchWorkout) -> Routine {
        let routine = Routine(name: workout.routineName)
        routine.id = workout.routineId
        return routine
    }
}
