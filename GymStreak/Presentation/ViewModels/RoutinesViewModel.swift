import Foundation
import SwiftUI

@MainActor
class RoutinesViewModel: ObservableObject {
    @Published var routines: [Routine] = []
    @Published var showingAddRoutine = false
    @Published var selectedRoutine: Routine?
    /// Most recent completed-session start date per routine id (nil = never trained).
    @Published var lastPerformedByRoutine: [UUID: Date] = [:]

    private let routineRepository: RoutineRepository
    private let workoutSessionRepository: WorkoutSessionRepository
    private let watchSync: WatchSyncServicing
    private let watchWorkoutIngestionService: WatchWorkoutIngestionService
    private var cloudSyncObserver: NSObjectProtocol?

    init(
        routineRepository: RoutineRepository,
        workoutSessionRepository: WorkoutSessionRepository,
        watchSync: WatchSyncServicing
    ) {
        self.routineRepository = routineRepository
        self.workoutSessionRepository = workoutSessionRepository
        self.watchSync = watchSync
        self.watchWorkoutIngestionService = WatchWorkoutIngestionService(
            routineRepository: routineRepository,
            workoutSessionRepository: workoutSessionRepository
        )
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
            guard let workout = notification.userInfo?["workout"] as? IncomingWatchWorkout else {
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
        let pending = watchSync.pendingWorkouts()
        guard !pending.isEmpty else { return }
        print("Processing \(pending.count) pending watch workout(s)")
        for workout in pending {
            handleCompletedWatchWorkout(workout)
        }
    }

    func fetchRoutines() {
        routines = routineRepository.fetchAll()
        refreshLastPerformedDates()
        syncRoutinesToWatch()
    }

    /// Rebuilds the routine → last-trained lookup from completed workout history.
    /// Drives the "Als Nächstes" hero (least recently trained) and the relative
    /// dates on routine cards.
    private func refreshLastPerformedDates() {
        var dates: [UUID: Date] = [:]
        for session in workoutSessionRepository.fetchCompleted() {
            guard let routineId = session.routine?.id else { continue }
            if let existing = dates[routineId], existing >= session.startTime { continue }
            dates[routineId] = session.startTime
        }
        lastPerformedByRoutine = dates
    }

    /// The routine surfaced as the "Als Nächstes" hero card. When any routine is
    /// planned, this is the soonest-due one (overdue plans sort first). Otherwise
    /// it falls back to the least-recently-trained routine.
    var upNextRoutine: Routine? {
        guard !routines.isEmpty else { return nil }

        // Prefer the soonest-due planned routine.
        var soonest: (routine: Routine, due: Date)?
        for routine in routines {
            guard let schedule = routine.schedule, schedule.isActive,
                  let due = WorkoutPlanningService.nextDue(
                    for: schedule,
                    lastCompleted: lastPerformedByRoutine[routine.id]
                  ) else { continue }
            if let current = soonest {
                if due < current.due { soonest = (routine, due) }
            } else {
                soonest = (routine, due)
            }
        }
        if let soonest { return soonest.routine }

        // No plans: least-recently-trained (never-trained wins).
        guard routines.count > 1 else { return routines.first }
        return routines.min { lhs, rhs in
            let lhsDate = lastPerformedByRoutine[lhs.id] ?? .distantPast
            let rhsDate = lastPerformedByRoutine[rhs.id] ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    /// The next date a routine is due, or nil if unplanned. Uses the *live* last
    /// completion so it updates as soon as a workout is finished.
    func nextDueDate(for routine: Routine) -> Date? {
        guard let schedule = routine.schedule, schedule.isActive else { return nil }
        return WorkoutPlanningService.nextDue(
            for: schedule,
            lastCompleted: lastPerformedByRoutine[routine.id]
        )
    }

    // MARK: - Watch Connectivity

    /// Syncs routines to the watch with the "Als Nächstes" routine first, so the
    /// watch list surfaces the same up-next routine as the iOS Routinen tab.
    private func syncRoutinesToWatch() {
        var ordered = routines
        if let hero = upNextRoutine,
           let index = ordered.firstIndex(where: { $0.id == hero.id }), index > 0 {
            ordered.remove(at: index)
            ordered.insert(hero, at: 0)
        }
        watchSync.syncRoutines(ordered)
    }

    func addRoutine(name: String) {
        let routine = Routine(name: name)
        routineRepository.insert(routine)
        save()
        fetchRoutines()
    }

    /// Persists a brand-new routine along with its pending exercises, sets and
    /// alternatives — the full transaction previously performed inline by
    /// CreateRoutineView.
    func createRoutine(name: String, pendingExercises: [PendingRoutineExercise]) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let routine = Routine(name: trimmedName)
        routineRepository.insert(routine)

        for pending in pendingExercises {
            let routineExercise = RoutineExercise(exercise: pending.exercise, order: pending.order)
            routineExercise.routine = routine

            for (index, set) in pending.sets.enumerated() {
                let newSet = ExerciseSet(
                    reps: set.reps,
                    weight: set.weight,
                    restTime: set.restTime,
                    order: index
                )
                newSet.routineExercise = routineExercise
                routineExercise.sets?.append(newSet)
            }

            routine.routineExercises?.append(routineExercise)

            // Materialize picked alternatives with their own set schemes.
            for (altOrder, pendingAlt) in pending.alternatives.enumerated() {
                let alternative = RoutineExerciseAlternative(exercise: pendingAlt.exercise, order: altOrder)
                alternative.routineExercise = routineExercise

                let seededSets = pendingAlt.sets.enumerated().map { setIndex, set in
                    let altSet = AlternativeExerciseSet(
                        reps: set.reps,
                        weight: set.weight,
                        restTime: set.restTime,
                        order: setIndex
                    )
                    altSet.alternative = alternative
                    return altSet
                }
                alternative.sets = seededSets
                if routineExercise.alternatives == nil { routineExercise.alternatives = [] }
                routineExercise.alternatives?.append(alternative)
            }
        }

        save()
        fetchRoutines()
    }

    func updateRoutine(_ routine: Routine) {
        routine.updatedAt = Date()
        save()
        fetchRoutines()
    }

    /// Deep-copies a routine (exercises, sets, rep ranges, supersets and
    /// alternatives with their set schemes) under a "(name Copy)" title.
    @discardableResult
    func duplicateRoutine(_ routine: Routine) -> Routine {
        let copy = Routine(name: String(format: "routine.duplicate.name_format".localized, routine.name))
        routineRepository.insert(copy)

        // Superset ids must not be shared across routines — remap per duplicate.
        var supersetIdMap: [UUID: UUID] = [:]

        for source in routine.routineExercisesList.sorted(by: { $0.order < $1.order }) {
            guard let exercise = source.exercise else { continue }
            let target = RoutineExercise(exercise: exercise, order: source.order)
            target.routine = copy
            target.targetRepMin = source.targetRepMin
            target.targetRepMax = source.targetRepMax
            if let supersetId = source.supersetId {
                let mapped = supersetIdMap[supersetId] ?? UUID()
                supersetIdMap[supersetId] = mapped
                target.supersetId = mapped
                target.supersetOrder = source.supersetOrder
            }

            for (index, set) in source.setsList.sorted(by: { $0.order < $1.order }).enumerated() {
                let newSet = ExerciseSet(reps: set.reps, weight: set.weight, restTime: set.restTime, order: index)
                newSet.routineExercise = target
                target.sets?.append(newSet)
            }

            for (altOrder, alternative) in source.alternativesList.enumerated() {
                guard let altExercise = alternative.exercise else { continue }
                let newAlternative = RoutineExerciseAlternative(exercise: altExercise, order: altOrder)
                newAlternative.routineExercise = target
                newAlternative.sets = alternative.setsList.enumerated().map { setIndex, set in
                    let altSet = AlternativeExerciseSet(reps: set.reps, weight: set.weight, restTime: set.restTime, order: setIndex)
                    altSet.alternative = newAlternative
                    return altSet
                }
                if target.alternatives == nil { target.alternatives = [] }
                target.alternatives?.append(newAlternative)
            }

            copy.routineExercises?.append(target)
        }

        save()
        fetchRoutines()
        return copy
    }

    func deleteRoutine(_ routine: Routine) {
        routineRepository.delete(routine)
        save()
        fetchRoutines()
    }

    func removeRoutineExercise(_ routineExercise: RoutineExercise, from routine: Routine) {
        if let index = routine.routineExercisesList.firstIndex(where: { $0.id == routineExercise.id }) {
            routine.routineExercises?.remove(at: index)
            routineRepository.delete(routineExercise)
            updateRoutine(routine)
        }
    }

    /// Appends a new set (seeded from the last set) and returns it so callers
    /// can expand its inline editor immediately.
    @discardableResult
    func addSet(to routineExercise: RoutineExercise) -> ExerciseSet {
        // Seed reps/weight/rest from the last set so a new set continues the scheme
        let lastSet = routineExercise.setsList.sorted(by: { $0.order < $1.order }).last
        let set = ExerciseSet(
            reps: lastSet?.reps ?? 10,
            weight: lastSet?.weight ?? 0.0,
            restTime: lastSet?.restTime ?? 0,
            order: (lastSet?.order ?? -1) + 1
        )
        set.routineExercise = routineExercise
        routineExercise.sets?.append(set)
        if let routine = routineExercise.routine {
            updateRoutine(routine)
        }
        return set
    }

    func removeSet(_ set: ExerciseSet, from routineExercise: RoutineExercise) {
        if let index = routineExercise.setsList.firstIndex(where: { $0.id == set.id }) {
            routineExercise.sets?.remove(at: index)
            routineRepository.delete(set)
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

    // MARK: - Schedule / Planning

    /// Creates or updates a routine's training plan. Passing the mode + both
    /// sets of parameters keeps the call site simple; only the fields relevant
    /// to `type` are actually used by `WorkoutPlanningService`.
    func setSchedule(
        for routine: Routine,
        type: RoutineScheduleType,
        intervalDays: Int,
        weekdays: Set<Int>,
        referenceDate: Date
    ) {
        let schedule: RoutineSchedule
        if let existing = routine.schedule {
            schedule = existing
        } else {
            schedule = RoutineSchedule()
            schedule.routine = routine
            routine.schedule = schedule
            routineRepository.insert(schedule)
        }
        schedule.type = type
        schedule.intervalDays = max(1, intervalDays)
        schedule.weekdays = weekdays
        // Reference date is the "start fresh" anchor for the cadence; the last
        // completed workout takes over once one lands on or after it.
        schedule.startDate = referenceDate
        schedule.isActive = true
        updateRoutine(routine)
    }

    /// Clears a routine's plan entirely.
    func removeSchedule(from routine: Routine) {
        guard let schedule = routine.schedule else { return }
        routine.schedule = nil
        routineRepository.delete(schedule)
        updateRoutine(routine)
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

    // MARK: - Superset Edit Mode (set-algebra)

    /// Whether the "Done" action in the superset editor should be enabled.
    func canApplySupersetEdit(_ mode: SupersetEditMode?, selection: Set<UUID>) -> Bool {
        SupersetEditor.canApplyEdit(mode, selection: selection)
    }

    /// Applies a pending superset edit (create or modify) by asking
    /// `SupersetEditor` to diff the current selection against the superset's
    /// existing membership, then issuing the resulting link/unlink/create/
    /// dissolve operations via this ViewModel's own persistence methods.
    func applySupersetEdit(_ mode: SupersetEditMode?, selection: Set<UUID>, in routine: Routine) {
        switch SupersetEditor.decideEdit(mode, selection: selection, in: routine) {
        case .dissolve(let supersetId):
            dissolveSuperset(supersetId, in: routine)
        case .modify(let supersetId, let toAdd, let toRemove):
            for exercise in routine.routineExercisesList where toRemove.contains(exercise.id) {
                removeExerciseFromSuperset(exercise, in: routine)
            }
            for exercise in routine.routineExercisesList where toAdd.contains(exercise.id) {
                addExerciseToSuperset(exercise, supersetId: supersetId, in: routine)
            }
        case .create(let exercises):
            createSuperset(from: exercises, in: routine)
        case .none:
            break
        }
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
            routineRepository.delete(alternative)
            // Reorder remaining alternatives
            for (newOrder, remaining) in routineExercise.alternativesList.enumerated() {
                remaining.order = newOrder
            }
            if let routine = routineExercise.routine {
                updateRoutine(routine)
            }
        }
    }

    /// Adds a set to an alternative, seeded from its last set (same behavior
    /// as addSet(to: RoutineExercise) so both variants feel identical).
    @discardableResult
    func addSet(to alternative: RoutineExerciseAlternative) -> AlternativeExerciseSet {
        let lastSet = alternative.setsList.sorted(by: { $0.order < $1.order }).last
        let set = AlternativeExerciseSet(
            reps: lastSet?.reps ?? 10,
            weight: lastSet?.weight ?? 0.0,
            restTime: lastSet?.restTime ?? 0,
            order: (lastSet?.order ?? -1) + 1
        )
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
            routineRepository.delete(set)
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

    /// Sets (or clears) an alternative's own rep-range goal, independent of the
    /// primary exercise's goal. Mirrors `updateRepRange(for:min:max:)`.
    func updateRepRange(for alternative: RoutineExerciseAlternative, min: Int?, max: Int?) {
        alternative.targetRepMin = min
        alternative.targetRepMax = max
        if let routine = alternative.routineExercise?.routine {
            updateRoutine(routine)
        }
    }

    private func save() {
        do {
            try routineRepository.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }

    // MARK: - Watch Workout Handling

    /// Delegates ingestion (dedup, materialization, save, template update) to
    /// `WatchWorkoutIngestionService`, then applies the two side effects that
    /// stay ViewModel-owned: acking with the watch and refreshing the
    /// published `routines` list if the template changed.
    private func handleCompletedWatchWorkout(_ workout: IncomingWatchWorkout) {
        let result = watchWorkoutIngestionService.ingest(workout)

        if result.shouldAcknowledge {
            watchSync.markPendingProcessed(id: workout.id)
            // Confirm the save back to the watch so it can drop the rich payload from
            // its durable retry queue. Until this ack arrives the watch keeps retrying.
            watchSync.acknowledgeWorkoutSaved(id: workout.id)
        }

        if result.templateWasUpdated {
            fetchRoutines()
        }
    }
}
