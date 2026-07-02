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
    private var cloudSyncObserver: NSObjectProtocol?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        observeWatchWorkoutCompletions()
        processPendingWatchWorkouts()
        fetchRoutines()
        observeCloudKitChanges()
        observeWatchAvailability()
        observeRoutineTemplateChanges()
    }

    private func observeCloudKitChanges() {
        cloudSyncObserver = NotificationCenter.default.addObserver(
            forName: .cloudKitDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fetchRoutines()
            }
        }
    }

    private func observeWatchAvailability() {
        NotificationCenter.default.addObserver(
            forName: .watchAppBecameAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncRoutinesToWatch()
            }
        }
    }

    private func observeRoutineTemplateChanges() {
        NotificationCenter.default.addObserver(
            forName: .routineTemplateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Re-fetch so the in-memory list reflects the edited template, then sync to watch.
                self?.fetchRoutines()
            }
        }
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
        // Drain ALL workouts that arrived before we started observing or that
        // were buffered to disk because a prior process crashed before saving.
        // The persistent buffer is App-Group-backed so it survives app crashes;
        // entries are removed individually by `markPendingProcessed` inside
        // handleCompletedWatchWorkout once the SwiftData save succeeds (or a
        // duplicate is detected).
        let pending = watchConnectivity.pendingWorkouts()
        guard !pending.isEmpty else { return }
        print("Processing \(pending.count) pending watch workout(s)")
        for workout in pending {
            handleCompletedWatchWorkout(workout)
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
        if let index = routine.routineExercisesList.firstIndex(where: { $0.id == routineExercise.id }) {
            routine.routineExercises?.remove(at: index)
            modelContext.delete(routineExercise)
            updateRoutine(routine)
        }
    }

    func addSet(to routineExercise: RoutineExercise) {
        // Get rest time from existing sets, or default to 0 (disabled)
        let restTime = routineExercise.setsList.first?.restTime ?? 0
        // Calculate order from last set
        let lastSet = routineExercise.setsList.sorted(by: { $0.order < $1.order }).last
        let order = (lastSet?.order ?? -1) + 1
        let set = ExerciseSet(reps: 10, weight: 0.0, restTime: restTime, order: order)
        set.routineExercise = routineExercise
        routineExercise.sets?.append(set)
        if let routine = routineExercise.routine {
            updateRoutine(routine)
        }
    }

    func removeSet(_ set: ExerciseSet, from routineExercise: RoutineExercise) {
        if let index = routineExercise.setsList.firstIndex(where: { $0.id == set.id }) {
            routineExercise.sets?.remove(at: index)
            modelContext.delete(set)
            // Reorder remaining sets to maintain sequential order
            let sortedSets = routineExercise.setsList.sorted(by: { $0.order < $1.order })
            for (newOrder, remainingSet) in sortedSets.enumerated() {
                remainingSet.order = newOrder
            }
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

    func moveExerciseSets(from source: IndexSet, to destination: Int, for routineExercise: RoutineExercise) {
        var sortedSets = routineExercise.setsList.sorted(by: { $0.order < $1.order })
        sortedSets.move(fromOffsets: source, toOffset: destination)
        for (index, set) in sortedSets.enumerated() {
            set.order = index
        }
        if let routine = routineExercise.routine {
            updateRoutine(routine)
        }
    }

    // MARK: - Rep Range Management

    func updateRepRange(for routineExercise: RoutineExercise, min: Int?, max: Int?) {
        routineExercise.targetRepMin = min
        routineExercise.targetRepMax = max
        if let routine = routineExercise.routine {
            updateRoutine(routine)
        }
    }

    func applyProgressiveOverload(for routineExercise: RoutineExercise, weightIncrement: Double) {
        guard let min = routineExercise.targetRepMin else { return }
        for set in routineExercise.setsList {
            set.weight += weightIncrement
            set.reps = min
        }
        if let routine = routineExercise.routine {
            updateRoutine(routine)
        }
    }

    // MARK: - Superset Management

    /// Creates a superset from 2+ selected exercises
    func createSuperset(from exercises: [RoutineExercise], in routine: Routine) {
        guard exercises.count >= 2 else { return }

        let supersetId = UUID()

        // Assign superset ID and order within superset
        for (index, exercise) in exercises.enumerated() {
            exercise.supersetId = supersetId
            exercise.supersetOrder = index
        }

        updateRoutine(routine)
    }

    /// Adds an exercise to an existing superset
    func addExerciseToSuperset(_ exercise: RoutineExercise, supersetId: UUID, in routine: Routine) {
        // Find highest supersetOrder in this superset
        let existingMaxOrder = routine.routineExercisesList
            .filter { $0.supersetId == supersetId }
            .map(\.supersetOrder)
            .max() ?? -1

        exercise.supersetId = supersetId
        exercise.supersetOrder = existingMaxOrder + 1

        updateRoutine(routine)
    }

    /// Removes an exercise from its superset; auto-dissolves if only 1 remains
    func removeExerciseFromSuperset(_ exercise: RoutineExercise, in routine: Routine) {
        guard let supersetId = exercise.supersetId else { return }

        // Remove from superset
        exercise.supersetId = nil
        exercise.supersetOrder = 0

        // Find remaining exercises in this superset
        let remaining = routine.routineExercisesList.filter { $0.supersetId == supersetId }

        // If only 1 exercise remains, auto-dissolve the superset
        if remaining.count == 1 {
            remaining.first?.supersetId = nil
            remaining.first?.supersetOrder = 0
        } else {
            // Reorder remaining exercises
            for (index, ex) in remaining.sorted(by: { $0.supersetOrder < $1.supersetOrder }).enumerated() {
                ex.supersetOrder = index
            }
        }

        updateRoutine(routine)
    }

    /// Dissolves a superset, unlinking all exercises
    func dissolveSuperset(_ supersetId: UUID, in routine: Routine) {
        let exercises = routine.routineExercisesList.filter { $0.supersetId == supersetId }

        for exercise in exercises {
            exercise.supersetId = nil
            exercise.supersetOrder = 0
        }

        updateRoutine(routine)
    }

    /// Reorders exercises within a superset
    func reorderSuperset(_ exercises: [RoutineExercise], in routine: Routine) {
        for (index, exercise) in exercises.enumerated() {
            exercise.supersetOrder = index
        }

        updateRoutine(routine)
    }

    // MARK: - Alternative Exercise Management

    /// Adds an alternative exercise to a routine exercise, seeding its set scheme
    /// from the given sets (defaults to the primary exercise's current sets).
    /// When seeding from the primary, set count/reps/rest carry over but the
    /// weight starts at 0 — a different exercise almost always needs a different
    /// weight, so copying it would just be a wrong prefill.
    @discardableResult
    func addAlternative(
        _ exercise: Exercise,
        to routineExercise: RoutineExercise,
        copying sourceSets: [ExerciseSet]? = nil
    ) -> RoutineExerciseAlternative {
        let order = (routineExercise.alternativesList.last?.order ?? -1) + 1
        let alternative = RoutineExerciseAlternative(exercise: exercise, order: order)
        alternative.routineExercise = routineExercise
        let isSeededFromPrimary = sourceSets == nil
        let source = sourceSets ?? routineExercise.setsList
        let seededSets = source.sorted(by: { $0.order < $1.order }).enumerated().map { index, set in
            let copy = AlternativeExerciseSet(
                reps: set.reps,
                weight: isSeededFromPrimary ? 0.0 : set.weight,
                restTime: set.restTime,
                order: index
            )
            copy.alternative = alternative
            return copy
        }
        alternative.sets = seededSets
        if routineExercise.alternatives == nil { routineExercise.alternatives = [] }
        routineExercise.alternatives?.append(alternative)
        if let routine = routineExercise.routine {
            updateRoutine(routine)
        }
        return alternative
    }

    /// Removes an alternative from a routine exercise.
    func removeAlternative(_ alternative: RoutineExerciseAlternative, from routineExercise: RoutineExercise) {
        if let index = routineExercise.alternativesList.firstIndex(where: { $0.id == alternative.id }) {
            let actualIndex = routineExercise.alternatives?.firstIndex(where: { $0.id == alternative.id }) ?? index
            routineExercise.alternatives?.remove(at: actualIndex)
            modelContext.delete(alternative)
            // Reorder remaining alternatives
            for (newOrder, remaining) in routineExercise.alternativesList.enumerated() {
                remaining.order = newOrder
            }
            if let routine = routineExercise.routine {
                updateRoutine(routine)
            }
        }
    }

    /// Adds a set to an alternative, copying the rest time of its last set.
    @discardableResult
    func addSet(to alternative: RoutineExerciseAlternative) -> AlternativeExerciseSet {
        let restTime = alternative.setsList.first?.restTime ?? 0
        let order = (alternative.setsList.last?.order ?? -1) + 1
        let set = AlternativeExerciseSet(reps: 10, weight: 0.0, restTime: restTime, order: order)
        set.alternative = alternative
        if alternative.sets == nil { alternative.sets = [] }
        alternative.sets?.append(set)
        if let routine = alternative.routineExercise?.routine {
            updateRoutine(routine)
        }
        return set
    }

    /// Removes a set from an alternative and reorders the remaining sets.
    func removeSet(_ set: AlternativeExerciseSet, from alternative: RoutineExerciseAlternative) {
        if let index = alternative.sets?.firstIndex(where: { $0.id == set.id }) {
            alternative.sets?.remove(at: index)
            modelContext.delete(set)
            for (newOrder, remaining) in alternative.setsList.enumerated() {
                remaining.order = newOrder
            }
            if let routine = alternative.routineExercise?.routine {
                updateRoutine(routine)
            }
        }
    }

    /// Persists an in-place edit to an alternative's set.
    func updateSet(_ set: AlternativeExerciseSet) {
        if let routine = set.alternative?.routineExercise?.routine {
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
            // Idempotency: if this workout has already been ingested (e.g. from a
            // watch-side retry after a previously dropped transferUserInfo), skip
            // re-inserting. We match on the workout's UUID first, then on the
            // healthKitWorkoutId as a secondary key (covers cross-device cases
            // where the iOS-stored id might differ but HK metadata aligns).
            let workoutId = workout.id
            let hkId = workout.healthKitWorkoutId
            let existingDescriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { session in
                    session.id == workoutId || (hkId != nil && session.healthKitWorkoutId == hkId)
                }
            )
            if let existing = try modelContext.fetch(existingDescriptor).first {
                if existing.id != workoutId {
                    // Matched by healthKitWorkoutId under a *different* session id:
                    // this session was reconstructed from HealthKit by the recovery
                    // banner (template values guessed as actuals) before the real
                    // payload arrived. Real ingests always preserve the watch id, so
                    // an id mismatch uniquely identifies a placeholder. Replace it
                    // with the actual per-set data instead of dropping the payload —
                    // skipping here is what permanently lost the recorded values.
                    print("Replacing reconstructed placeholder session \(existing.id) with real watch payload \(workoutId)")
                    modelContext.delete(existing)
                } else {
                    print("Skipping duplicate watch workout: \(workout.routineName) (existing session id=\(existing.id))")
                    watchConnectivity.markPendingProcessed(id: workout.id)
                    // Re-ack so the watch clears it even if our first ack was lost.
                    watchConnectivity.acknowledgeWorkoutSaved(id: workout.id)
                    return
                }
            }

            // Find the routine by ID
            let descriptor = FetchDescriptor<Routine>(
                predicate: #Predicate { routine in
                    routine.id == workout.routineId
                }
            )

            let routine = try modelContext.fetch(descriptor).first

            // Create workout session — preserve the watch-generated id so retries
            // are detectable above and to keep iOS/watch in agreement on identity.
            let workoutSession = WorkoutSession(routine: routine ?? createPlaceholderRoutine(from: workout))
            workoutSession.id = workout.id
            workoutSession.startTime = workout.startTime
            workoutSession.endTime = workout.endTime
            workoutSession.didUpdateTemplate = workout.shouldUpdateTemplate
            workoutSession.routineName = workout.routineName
            workoutSession.healthKitWorkoutId = workout.healthKitWorkoutId

            // Create workout exercises
            for completedExercise in workout.exercises {
                let workoutExercise = WorkoutExercise(
                    exerciseName: completedExercise.name,
                    muscleGroups: [completedExercise.muscleGroup],
                    order: completedExercise.order,
                    exerciseId: completedExercise.exerciseId
                )
                workoutExercise.workoutSession = workoutSession
                // Copy superset fields from completed exercise
                workoutExercise.supersetId = completedExercise.supersetId
                workoutExercise.supersetOrder = completedExercise.supersetOrder
                // Copy rep range fields from completed exercise
                workoutExercise.targetRepMin = completedExercise.targetRepMin
                workoutExercise.targetRepMax = completedExercise.targetRepMax
                // Copy alternative-swap metadata (name/exerciseId already reflect what was performed)
                workoutExercise.plannedExerciseId = completedExercise.plannedExerciseId
                workoutExercise.plannedExerciseName = completedExercise.plannedExerciseName

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
                    workoutExercise.sets?.append(workoutSet)
                    modelContext.insert(workoutSet)
                }

                workoutSession.workoutExercises?.append(workoutExercise)
                modelContext.insert(workoutExercise)
            }

            modelContext.insert(workoutSession)
            try modelContext.save()
            print("Created workout session from watch workout: \(workout.routineName)")
            watchConnectivity.markPendingProcessed(id: workout.id)
            // Confirm the save back to the watch so it can drop the rich payload from
            // its durable retry queue. Until this ack arrives the watch keeps retrying.
            watchConnectivity.acknowledgeWorkoutSaved(id: workout.id)
            // Notify any view models cached on the History tab to refresh.
            NotificationCenter.default.post(name: .workoutHistoryDidChange, object: nil)

        } catch {
            // Leave the workout in the persistent pending buffer so we retry on
            // next app launch / observer registration. Do NOT call
            // markPendingProcessed here.
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
                guard let routineExercise = routine.routineExercisesList.first(where: { $0.id == completedExercise.id }) else {
                    print("Could not find routine exercise with ID: \(completedExercise.id)")
                    continue
                }

                for completedSet in completedExercise.sets {
                    guard let set = routineExercise.setsList.first(where: { $0.id == completedSet.id }) else {
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
