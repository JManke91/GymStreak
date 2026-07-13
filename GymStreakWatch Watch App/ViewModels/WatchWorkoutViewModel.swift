import Foundation
import Combine
import WatchKit
import UserNotifications
import AppIntents

@MainActor
final class WatchWorkoutViewModel: ObservableObject {

    enum WorkoutState {
        case running
        case idle
        case started
        case stopped
    }
    // MARK: - Published Properties

    @Published var isWorkoutActive = false
    @Published var isPaused = false
    @Published var currentRoutine: WatchRoutine?
    @Published var exercises: [ActiveWorkoutExercise] = []
    @Published var currentExerciseIndex = 0
    @Published var currentSetIndex = 0

    // Rest Timer
    @Published var isResting = false
    @Published var restTimeRemaining: TimeInterval = 0
    @Published var isRestTimerMinimized = false
    @Published var restDuration: TimeInterval = 0
    @Published var restTimerState: RestTimerState = .running

    @Published var workoutState: WorkoutState = .idle


    enum RestTimerState {
        case running
        case completed
    }

    // HealthKit Metrics
    @Published var heartRate: Int? = nil
//    @Published var currentHeartRate: Int? = nil
//    @Published var currentCalories: Int? = nil

    @Published var activeCalories: Int? = nil
    @Published var elapsedTime: TimeInterval? = nil
    @Published var elapsedTimeString: String? = nil

    // Workout Summary (shown after saving)
    @Published var workoutSummary: WatchWorkoutSummary?
    @Published var templateWasUpdated = false

    /// Set by auto-finish when the final set completes on a workout with modified
    /// sets: ActiveWorkoutView observes it and surfaces the existing
    /// "Update your routine template?" confirmation dialog instead of saving
    /// directly. The view resets it once the dialog is presented.
    @Published var requestsFinishConfirmation = false

    // Error handling
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let healthKitManager: WatchHealthKitManager
    private let connectivityManager: WatchConnectivityManager
    private let routineStore: RoutineStore
    private var workoutStartTime: Date?
    /// Identity of the current workout's outgoing payload / HealthKit save,
    /// generated once per workout so a retried end (e.g. after a HealthKit
    /// failure) reuses the same ids — the durable send queue replaces entries
    /// by id and iOS dedupes on them, so stable ids prevent duplicate sessions.
    private var pendingCompletedWorkoutId: UUID?
    private var pendingHealthKitWorkoutId: UUID?
    private var restTimer: Timer?
    private var cancellabes = Set<AnyCancellable>()

    // MARK: - Initialization

    init(healthKitManager: WatchHealthKitManager, connectivityManager: WatchConnectivityManager, routineStore: RoutineStore) {
        self.healthKitManager = healthKitManager
        self.connectivityManager = connectivityManager
        self.routineStore = routineStore
//        observeHealthKitMetrics()
        requestNotificationPermission()

        // Metric pipelines dedupe on the displayed value: HealthKit delivers
        // bursts of near-identical samples, and republishing an unchanged value
        // invalidates every observing view (SwiftUI logs "tried to update
        // multiple times per frame" when several land in one frame).
        healthKitManager.$elapsedTime
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .map { interval in
                    let minutes = Int(interval) / 60
                    let seconds = Int(interval) % 60
                    return String(format: "%02d:%02d", minutes, seconds)
                }
            .removeDuplicates()
            .sink { [weak self] formatted in
                self?.elapsedTimeString = formatted
            }
            .store(in: &cancellabes)

        healthKitManager.$heartRate
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .map { Int($0) }
            .removeDuplicates()
            .sink { [weak self] heartRate in
                self?.heartRate = heartRate
            }
            .store(in: &cancellabes)

        healthKitManager.$activeCalories
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .map { Int($0) }
            .removeDuplicates()
            .sink { [weak self] calories in
                self?.activeCalories = calories
            }
            .store(in: &cancellabes)

        healthKitManager.$activeCalories.compactMap { $0 }.removeDuplicates().combineLatest(healthKitManager.$heartRate.compactMap { $0 }.removeDuplicates())
        // state only needs to be set once
        // FIXME: prevents data showing in a subsequent workout
//            .prefix(1)
            .filter { [weak self] _ in self?.workoutState != .running }
            .sink { [weak self] _ in
                self?.workoutState = .running
            }
            .store(in: &cancellabes)
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UI_TESTING")
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
        guard !isUITesting else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Watch notification permission error: \(error)")
            }
            if granted {
                print("Watch notification permission granted")
            } else {
                print("Watch notification permission denied")
            }
        }
    }

    private func scheduleRestTimerNotification(duration: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Rest Complete")
        content.body = String(localized: "Time to start your next set!")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: duration, repeats: false)
        let request = UNNotificationRequest(
            identifier: "watchRestTimer",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling watch rest timer notification: \(error)")
            }
        }
    }

    private func cancelRestTimerNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["watchRestTimer"])
    }

    // MARK: - Computed Properties

    var currentExercise: ActiveWorkoutExercise? {
        guard currentExerciseIndex < exercises.count else { return nil }
        return exercises[currentExerciseIndex]
    }

    var currentSet: ActiveWorkoutSet? {
        guard let exercise = currentExercise,
              currentSetIndex < exercise.sets.count else { return nil }
        return exercise.sets[currentSetIndex]
    }

    var totalSetsCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }

    var completedSetsCount: Int {
        exercises.reduce(0) { $0 + $1.completedSetsCount }
    }

    var progress: Double {
        guard totalSetsCount > 0 else { return 0 }
        return Double(completedSetsCount) / Double(totalSetsCount)
    }

    var formattedElapsedTime: String {
        if let elapsedTime {
            let minutes = Int(elapsedTime) / 60
            let seconds = Int(elapsedTime) % 60
            return String(format: "%02d:%02d", minutes, seconds)
        } else {
            return ""
        }
    }

    var formattedRestTime: String {
        let minutes = Int(restTimeRemaining) / 60
        let seconds = Int(restTimeRemaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var canGoToPreviousExercise: Bool {
        currentExerciseIndex > 0
    }

    var canGoToNextExercise: Bool {
        currentExerciseIndex < exercises.count - 1
    }

    var currentExerciseNumber: Int {
        currentExerciseIndex + 1
    }

    var totalExercises: Int {
        exercises.count
    }

    /// True when the currently displayed set is the last remaining incomplete
    /// set of the whole workout — completing it finishes the workout (see the
    /// auto-finish in applyToggleSetCompletion). Order-independent: derived from
    /// the total incomplete-set count, so the complete button can relabel to
    /// "Finish Workout" for any exercise/set that happens to be the final one.
    var isFinishingSet: Bool {
        guard let set = currentSet, !set.isCompleted else { return false }
        let incompleteCount = exercises.reduce(0) { count, exercise in
            count + exercise.sets.filter { !$0.isCompleted }.count
        }
        return incompleteCount == 1
    }

    var hasModifiedSets: Bool {
        exercises.contains { exercise in
            exercise.sets.contains(where: \.wasModified)
        }
    }

    var modifiedSetsCount: Int {
        exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter(\.wasModified).count
        }
    }

    // MARK: - Workout Lifecycle

    func startWorkout(with routine: WatchRoutine) async {
        currentRoutine = routine
        exercises = routine.exercises.sorted { $0.order < $1.order }.map { $0.toActiveWorkoutExercise() }
        currentExerciseIndex = 0
        currentSetIndex = 0
        workoutStartTime = Date()
        pendingCompletedWorkoutId = nil
        pendingHealthKitWorkoutId = nil

        // Skip HealthKit for UI testing - immediately set running state with mock data
        if isUITesting {
            isWorkoutActive = true
            workoutState = .running
            heartRate = 142
            activeCalories = 87
            elapsedTimeString = "12:34"
            return
        }

        // Request HealthKit authorization and start session
        let authorized = await healthKitManager.requestAuthorization()
        guard authorized else {
            errorMessage = "HealthKit authorization required"
            return
        }

        do {
            // Provide the routine name + id so HealthKit workout metadata includes them
            // (the id lets iOS reconstruct the session from HealthKit if the rich
            // WatchConnectivity payload is ever lost).
            try await healthKitManager.startWorkout(routineName: routine.name, routineId: routine.id)
            isWorkoutActive = true
            workoutState = .started
            WKInterfaceDevice.current().play(.start)
        } catch {
            errorMessage = "Failed to start workout: \(error.localizedDescription)"
        }
    }

    func pauseWorkout() {
        healthKitManager.pauseWorkout()
        isPaused = true
    }

    func resumeWorkout() {
        healthKitManager.resumeWorkout()
        isPaused = false
    }

    func endWorkout(updateTemplate: Bool = false) async {
        // Capture summary BEFORE ending HealthKit session (metrics stop updating after)
        workoutSummary = generateWorkoutSummary()

        stopRestTimer()

        // Apply template update locally on watch BEFORE syncing to iOS
        if updateTemplate, let routineId = currentRoutine?.id {
            templateWasUpdated = routineStore.applyWorkoutChanges(routineId: routineId, exercises: exercises)
        }

        let healthKitWorkoutId = pendingHealthKitWorkoutId ?? UUID()
        pendingHealthKitWorkoutId = healthKitWorkoutId

        // Hand the payload to the durable send queue BEFORE finishing the
        // HealthKit workout. The reverse order had a loss window: once HealthKit
        // had saved, a crash or termination before the payload was persisted
        // left a workout in Apple Health that iOS could only reconstruct from
        // the routine template. Sending first also preserves the actual values
        // if the HealthKit save fails outright.
        sendCompletedWorkoutToiPhone(updateTemplate: updateTemplate, healthKitWorkoutId: healthKitWorkoutId)

        do {
            _ = try await healthKitManager.endWorkout(externalId: healthKitWorkoutId)
            isWorkoutActive = false
            workoutState = .stopped
            WKInterfaceDevice.current().play(.success)
        } catch {
            errorMessage = "Failed to save workout: \(error.localizedDescription)"
        }
    }

    /// Finishes the workout automatically once its final set is completed.
    /// Waits briefly so the completing tap's "Done" celebration flash is visible
    /// before the summary/dialog appears (the delay matches the flash duration in
    /// FullScreenSetEditorView). Workouts with modified sets route through the
    /// existing "Update your routine template?" confirmation dialog (surfaced by
    /// ActiveWorkoutView) exactly like the manual End flow; unmodified workouts
    /// finish directly via endWorkout().
    private func autoFinishWorkout() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            if hasModifiedSets {
                requestsFinishConfirmation = true
            } else {
                await endWorkout()
            }
        }
    }

    func dismissSummary() {
        workoutSummary = nil
        resetState()
    }

    func discardWorkout() {
        stopRestTimer()
        healthKitManager.discardWorkout()
        isWorkoutActive = false
        workoutState = .stopped
        resetState()
    }

    @MainActor
    private func applyToggleSetCompletion(_ result: (exerciseIndex: Int, setIndex: Int, newState: Bool)?) {
        guard let r = result else { return }

        if r.newState {
            exercises[r.exerciseIndex].sets[r.setIndex].completedAt = Date()
            WKInterfaceDevice.current().play(.success)

            // Completing the final remaining incomplete set anywhere in the
            // routine (any exercise, any order, last superset round) finishes
            // the workout instead of starting a rest timer / advancing. Because
            // this lives in the shared completion path, all three entry points
            // — on-screen Complete button, Ultra Action Button, Double Tap —
            // finish identically.
            if findNextIncompleteSet() == nil {
                autoFinishWorkout()
                return
            }

            let exercise = exercises[r.exerciseIndex]

            // For superset exercises, only start rest timer at end of round
            if exercise.isInSuperset {
                if isEndOfSupersetRound(exerciseIndex: r.exerciseIndex, setIndex: r.setIndex) {
                    let restTime = supersetRoundRestTime(exerciseIndex: r.exerciseIndex, setIndex: r.setIndex)
                    if restTime > 0 {
                        startRestTimer(duration: restTime)
                    }
                }
                // Advance to next exercise in superset (or next incomplete set)
                advanceToNextSetAfterCompletion(fromExerciseIndex: r.exerciseIndex, setIndex: r.setIndex)
            } else {
                // Standard behavior for non-superset exercises
                let restTime = exercise.sets[r.setIndex].restTime
                if restTime > 0 {
                    startRestTimer(duration: restTime)
                }
                // Advance to next set in same exercise or next exercise
                advanceToNextSetAfterCompletion(fromExerciseIndex: r.exerciseIndex, setIndex: r.setIndex)
            }
        } else {
            exercises[r.exerciseIndex].sets[r.setIndex].completedAt = nil
            WKInterfaceDevice.current().play(.directionDown)
        }
    }

    private func performToggleSetCompletion(_ setId: UUID, exerciseId: UUID) async -> (exerciseIndex: Int, setIndex: Int, newState: Bool)? {
        // Heavy work only, NO UI
        guard let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            return nil
        }

        // Simulate heavy work
//        try? await Task.sleep(nanoseconds: 50_000_000)

        let newState = !exercises[exerciseIndex].sets[setIndex].isCompleted
        return (exerciseIndex, setIndex, newState)
    }

    // MARK: - Set Management

    func toggleSetCompletion(_ setId: UUID, in exerciseId: UUID) {
//        isResting = true
//        guard let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseId }),
//              let setIndex = exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
//            return
//        }
////
////        // Toggle completion status
////        let wasCompleted = exercises[exerciseIndex].sets[setIndex].isCompleted
//        exercises[exerciseIndex].sets[setIndex].isCompleted.toggle()
//
//        if exercises[exerciseIndex].sets[setIndex].isCompleted {
//            // Just completed
//            exercises[exerciseIndex].sets[setIndex].completedAt = Date()
//            WKInterfaceDevice.current().play(.success)
//
            // Start rest timer if applicable
//            let restTime = exercises[exerciseIndex].sets[setIndex].restTime
//            if restTime > 0 {
//                startRestTimer(duration: restTime)
//            }
//        } else {
//            // Just uncompleted
//            exercises[exerciseIndex].sets[setIndex].completedAt = nil
//            WKInterfaceDevice.current().play(.directionDown)
//        }

        Task {
               // --- Do background work here ---
               // (e.g. database writes, computing next rest time, logs, analytics, etc.)

               let result = await performToggleSetCompletion(setId, exerciseId: exerciseId)

               // --- Switch back to main thread for UI updates ---
               await MainActor.run {
                   applyToggleSetCompletion(result)
               }
           }
    }

    func updateSet(_ updatedSet: ActiveWorkoutSet, in exerciseId: UUID) {
        guard let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = exercises[exerciseIndex].sets.firstIndex(where: { $0.id == updatedSet.id }) else {
            return
        }

        exercises[exerciseIndex].sets[setIndex] = updatedSet
        WKInterfaceDevice.current().play(.success)
    }

    func updateRestTime(for exerciseId: UUID, newRestTime: TimeInterval) {
        guard let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseId }) else {
            return
        }

        // Update all sets in the exercise with the new rest time
        for setIndex in exercises[exerciseIndex].sets.indices {
            exercises[exerciseIndex].sets[setIndex].restTime = newRestTime
        }

        WKInterfaceDevice.current().play(.success)
        print("Updated rest time for exercise \(exercises[exerciseIndex].name) to \(newRestTime)s")
    }

    // MARK: - Alternative Exercise Swapping

    /// Swap candidates for an exercise: its alternatives plus the originally-planned
    /// exercise (as a revert option once swapped), excluding whatever is active.
    func swapTargets(for exercise: ActiveWorkoutExercise) -> [WatchExerciseAlternative] {
        var targets: [WatchExerciseAlternative] = []
        if exercise.wasSwapped,
           let plannedId = exercise.plannedExerciseId,
           let plannedName = exercise.plannedExerciseName {
            targets.append(
                WatchExerciseAlternative(
                    id: plannedId,
                    exerciseId: plannedId,
                    name: plannedName,
                    muscleGroup: exercise.originalMuscleGroup ?? exercise.muscleGroup,
                    sets: exercise.originalSets ?? [],
                    order: -1,
                    loadBehaviorRaw: exercise.originalLoadBehaviorRaw ?? exercise.loadBehaviorRaw
                )
            )
        }
        targets.append(contentsOf: exercise.alternatives.sorted { $0.order < $1.order })
        return targets.filter { $0.exerciseId != exercise.exerciseId }
    }

    /// Swaps an exercise for one of its alternatives (or back to the original).
    /// Only allowed before any set is completed; rebuilds the sets from the target scheme.
    func swapExercise(_ exerciseId: UUID, to alternative: WatchExerciseAlternative) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        var exercise = exercises[index]
        guard exercise.completedSetsCount == 0 else { return }

        let isRevert = exercise.plannedExerciseId == alternative.exerciseId

        // Capture the original identity/sets on the first swap so revert is possible.
        if exercise.plannedExerciseId == nil {
            exercise.plannedExerciseId = exercise.exerciseId
            exercise.plannedExerciseName = exercise.name
            exercise.originalMuscleGroup = exercise.muscleGroup
            exercise.originalLoadBehaviorRaw = exercise.loadBehaviorRaw
            exercise.originalSets = exercise.sets.map { set in
                WatchSet(id: set.id, reps: set.plannedReps, weight: set.plannedWeight, restTime: set.restTime)
            }
        }

        // Apply the chosen target's identity and set scheme.
        exercise.name = alternative.name
        exercise.muscleGroup = alternative.muscleGroup
        exercise.exerciseId = alternative.exerciseId
        exercise.loadBehaviorRaw = alternative.loadBehaviorRaw ?? "resistance"
        exercise.sets = alternative.sets.enumerated().map { setIndex, set in
            ActiveWorkoutSet(
                id: set.id,
                plannedReps: set.reps,
                actualReps: set.reps,
                plannedWeight: set.weight,
                actualWeight: set.weight,
                restTime: set.restTime,
                completedAt: nil,
                order: setIndex
            )
        }

        // Reverting to the original clears the swap metadata.
        if isRevert {
            exercise.plannedExerciseId = nil
            exercise.plannedExerciseName = nil
            exercise.originalMuscleGroup = nil
            exercise.originalLoadBehaviorRaw = nil
            exercise.originalSets = nil
        }

        exercises[index] = exercise

        // The set scheme was rebuilt — restart the current exercise at its first
        // set so the set index can't point past the new scheme's bounds.
        if index == currentExerciseIndex {
            currentSetIndex = 0
        }

        WKInterfaceDevice.current().play(.success)
    }

    func completeCurrentSet() {
        guard var exercise = currentExercise,
              currentSetIndex < exercise.sets.count else { return }

        // Mark set as complete
//        exercise.sets[currentSetIndex].isCompleted = true
        exercise.sets[currentSetIndex].completedAt = Date()
        exercises[currentExerciseIndex] = exercise

        // Play haptic
        WKInterfaceDevice.current().play(.success)

        // Check if we should start rest timer
        let restTime = exercise.sets[currentSetIndex].restTime
        if restTime > 0 && !isLastSet {
            startRestTimer(duration: restTime)
        }

        // Advance to next set
        advanceToNextSet()
    }

    func skipRest() {
        stopRestTimer()
        isResting = false
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - Action Button (Apple Watch Ultra)

    /// Donates the complete-set intent as the active session's next Action Button
    /// action. Called from WatchHealthKitManager once the HKWorkoutSession reaches
    /// .running — donating earlier (while the session is still starting) can fail
    /// silently. Only takes effect when the user has the Action Button assigned to
    /// GymStreak under Settings → Action Button → Workout.
    func donateActionButtonIntent() {
        guard !isUITesting else { return }
        // linkd (the donation service) doesn't run in the simulator — the call
        // always fails with XPC error 4099, and the Action Button can't be
        // tested there anyway (see docs/action-button.md).
        #if !targetEnvironment(simulator)
        Task {
            do {
                try await GymStreakStartWorkoutIntent()
                    .donate(result: .result(actionButtonIntent: GymStreakCompleteSetIntent()))
                print("Action Button: complete-set intent donated")
            } catch {
                print("Action Button intent donation failed: \(error)")
            }
        }
        #endif
    }

    /// Entry point for hardware shortcuts (Action Button press, Double Tap).
    /// Skips an active rest period, otherwise completes the current set via the
    /// same superset-aware path the on-screen complete button uses.
    func handleActionButtonPress() {
        guard isWorkoutActive else { return }

        if isResting {
            skipRest()
            return
        }

        guard let exercise = currentExercise,
              let set = currentSet,
              !set.isCompleted else { return }

        toggleSetCompletion(set.id, in: exercise.id)
    }

    // MARK: - Exercise Navigation

    func goToPreviousExercise() {
        guard canGoToPreviousExercise else { return }
        currentExerciseIndex -= 1
        // Find first incomplete set, or start at 0
        currentSetIndex = exercises[currentExerciseIndex].sets.firstIndex { !$0.isCompleted } ?? 0
        WKInterfaceDevice.current().play(.click)
    }

    func goToNextExercise() {
        guard canGoToNextExercise else { return }
        currentExerciseIndex += 1
        // Find first incomplete set, or start at 0
        currentSetIndex = exercises[currentExerciseIndex].sets.firstIndex { !$0.isCompleted } ?? 0
        WKInterfaceDevice.current().play(.click)
    }

    func goToExercise(at index: Int) {
        guard index >= 0 && index < exercises.count else { return }
        currentExerciseIndex = index
        // Find first incomplete set, or start at 0
        currentSetIndex = exercises[currentExerciseIndex].sets.firstIndex { !$0.isCompleted } ?? 0
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - Set Navigation

    private var isLastSet: Bool {
        guard let exercise = currentExercise else { return true }

        let isLastSetInExercise = currentSetIndex >= exercise.sets.count - 1
        let isLastExercise = currentExerciseIndex >= exercises.count - 1

        return isLastSetInExercise && isLastExercise
    }

    /// Gets exercises grouped by superset, mirroring the iOS WorkoutSession.exercisesGroupedBySupersets
    private var exercisesGroupedBySupersets: [[ActiveWorkoutExercise]] {
        let sorted = exercises.sorted { $0.order < $1.order }
        var groups: [[ActiveWorkoutExercise]] = []
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

    /// Finds the next incomplete set using superset-aware interleaving.
    /// For supersets: A1 → B1 → A2 → B2 → A3 → B3
    func findNextIncompleteSet() -> (exerciseIndex: Int, setIndex: Int)? {
        for group in exercisesGroupedBySupersets {
            if group.count > 1 {
                // Superset group - interleave sets
                let maxSets = group.map { $0.sets.count }.max() ?? 0
                for setLevel in 0..<maxSets {
                    for exercise in group {
                        guard let exerciseIdx = exercises.firstIndex(where: { $0.id == exercise.id }) else {
                            continue
                        }
                        let sets = exercise.sets.sorted { $0.order < $1.order }
                        if let setIdx = sets.firstIndex(where: { $0.order == setLevel && !$0.isCompleted }) {
                            return (exerciseIdx, setIdx)
                        }
                    }
                }
            } else if let exercise = group.first {
                // Standalone exercise - sequential sets
                guard let exerciseIdx = exercises.firstIndex(where: { $0.id == exercise.id }) else {
                    continue
                }
                if let setIdx = exercise.sets.firstIndex(where: { !$0.isCompleted }) {
                    return (exerciseIdx, setIdx)
                }
            }
        }

        return nil
    }

    /// Finds the next incomplete set in a superset after completing a set.
    private func findNextIncompleteSetInSuperset(
        afterSetIndex currentSetIdx: Int,
        inExerciseIndex currentExerciseIdx: Int
    ) -> (exerciseIndex: Int, setIndex: Int)? {
        let exercise = exercises[currentExerciseIdx]

        guard let supersetId = exercise.supersetId else {
            // Not in a superset - find next set in same exercise
            let sets = exercise.sets
            for setIdx in (currentSetIdx + 1)..<sets.count {
                if !sets[setIdx].isCompleted {
                    return (currentExerciseIdx, setIdx)
                }
            }
            return nil
        }

        // Get all exercises in this superset
        let supersetExercises = exercises
            .enumerated()
            .filter { $0.element.supersetId == supersetId }
            .sorted { $0.element.supersetOrder < $1.element.supersetOrder }

        guard supersetExercises.count > 1 else {
            // Single exercise in "superset" - treat as standalone
            let sets = exercise.sets
            for setIdx in (currentSetIdx + 1)..<sets.count {
                if !sets[setIdx].isCompleted {
                    return (currentExerciseIdx, setIdx)
                }
            }
            return nil
        }

        // Find current exercise's position in the superset
        guard let supersetPosition = supersetExercises.firstIndex(where: { $0.offset == currentExerciseIdx }) else {
            return nil
        }

        let currentSetOrder = exercise.sets[currentSetIdx].order
        let maxSets = supersetExercises.map { $0.element.sets.count }.max() ?? 0

        // Interleaving: for set level N, go through all exercises before moving to N+1
        for setLevel in currentSetOrder..<maxSets {
            let startIdx = (setLevel == currentSetOrder) ? (supersetPosition + 1) : 0

            for offset in 0..<supersetExercises.count {
                let supersetIdx = (startIdx + offset) % supersetExercises.count

                // Skip exercises we've already passed at current set level
                if setLevel == currentSetOrder && supersetIdx <= supersetPosition {
                    continue
                }

                let (exerciseIdx, ex) = supersetExercises[supersetIdx]
                let sets = ex.sets.sorted { $0.order < $1.order }

                if let setIdx = sets.firstIndex(where: { $0.order == setLevel && !$0.isCompleted }) {
                    return (exerciseIdx, setIdx)
                }
            }
        }

        return nil
    }

    // MARK: - Superset Round Detection (for rest timer)

    /// Determines if completing this set ends a superset round (should trigger rest timer).
    /// A round ends when ALL sets at the completed set's level are complete across all superset exercises.
    private func isEndOfSupersetRound(exerciseIndex: Int, setIndex: Int) -> Bool {
        let exercise = exercises[exerciseIndex]

        guard let supersetId = exercise.supersetId else {
            // Not in a superset - always trigger rest (standard behavior)
            return true
        }

        // Get all exercises in this superset
        let supersetExercises = exercises
            .enumerated()
            .filter { $0.element.supersetId == supersetId }

        guard supersetExercises.count > 1 else {
            // Single exercise "superset" - treat as standalone
            return true
        }

        let completedSetLevel = exercise.sets[setIndex].order

        // Check if ALL sets at this level are now complete
        for (_, ex) in supersetExercises {
            if let setAtLevel = ex.sets.first(where: { $0.order == completedSetLevel }) {
                if !setAtLevel.isCompleted {
                    // Still have an incomplete set in this round
                    return false
                }
            }
            // If exercise doesn't have a set at this level, skip it (uneven set counts)
        }

        // All sets at this level are complete - round is done
        return true
    }

    /// Gets the rest time to use for a superset round.
    /// Returns the rest time from the last exercise's set at the completed set's level.
    private func supersetRoundRestTime(exerciseIndex: Int, setIndex: Int) -> TimeInterval {
        let exercise = exercises[exerciseIndex]

        guard let supersetId = exercise.supersetId else {
            // Not in a superset - use the set's own rest time
            return exercise.sets[setIndex].restTime
        }

        let supersetExercises = exercises
            .filter { $0.supersetId == supersetId }
            .sorted { $0.supersetOrder < $1.supersetOrder }

        guard supersetExercises.count > 1 else {
            // Single exercise "superset" - use set's own rest time
            return exercise.sets[setIndex].restTime
        }

        let completedSetLevel = exercise.sets[setIndex].order

        // Find the last exercise that has a set at this level and get its rest time
        for ex in supersetExercises.reversed() {
            if let setAtLevel = ex.sets.first(where: { $0.order == completedSetLevel }) {
                return setAtLevel.restTime
            }
        }

        // Fallback to the completed set's rest time
        return exercise.sets[setIndex].restTime
    }

    private func advanceToNextSet() {
        guard let exercise = currentExercise else { return }

        // Use superset-aware navigation
        if exercise.isInSuperset {
            if let next = findNextIncompleteSetInSuperset(
                afterSetIndex: currentSetIndex,
                inExerciseIndex: currentExerciseIndex
            ) {
                currentExerciseIndex = next.exerciseIndex
                currentSetIndex = next.setIndex
            } else if let next = findNextIncompleteSet() {
                // Superset complete, find next incomplete set anywhere
                currentExerciseIndex = next.exerciseIndex
                currentSetIndex = next.setIndex
            }
            // If no more sets, stay at current position
        } else {
            // Standard behavior for non-superset exercises
            if currentSetIndex < exercise.sets.count - 1 {
                currentSetIndex += 1
            } else if currentExerciseIndex < exercises.count - 1 {
                currentExerciseIndex += 1
                currentSetIndex = 0
            }
        }
    }

    /// Advances to the next set after completing a set, using superset-aware navigation.
    /// This is called from applyToggleSetCompletion with the specific exercise/set that was just completed.
    private func advanceToNextSetAfterCompletion(fromExerciseIndex exerciseIdx: Int, setIndex setIdx: Int) {
        let exercise = exercises[exerciseIdx]

        if exercise.isInSuperset {
            // Superset: find next incomplete set in the superset interleaving pattern
            if let next = findNextIncompleteSetInSuperset(
                afterSetIndex: setIdx,
                inExerciseIndex: exerciseIdx
            ) {
                currentExerciseIndex = next.exerciseIndex
                currentSetIndex = next.setIndex
            } else if let next = findNextIncompleteSet() {
                // Superset complete, find next incomplete set anywhere in the workout
                currentExerciseIndex = next.exerciseIndex
                currentSetIndex = next.setIndex
            }
            // If no more sets, stay at current position (workout complete)
        } else {
            // Standard behavior for non-superset exercises
            let sets = exercise.sets
            // Find next incomplete set in same exercise
            for nextSetIdx in (setIdx + 1)..<sets.count {
                if !sets[nextSetIdx].isCompleted {
                    currentExerciseIndex = exerciseIdx
                    currentSetIndex = nextSetIdx
                    return
                }
            }
            // No more sets in this exercise, find next incomplete set anywhere
            if let next = findNextIncompleteSet() {
                currentExerciseIndex = next.exerciseIndex
                currentSetIndex = next.setIndex
            }
            // If no more sets, stay at current position (workout complete)
        }
    }

    // MARK: - Rest Timer

    private func startRestTimer(duration: TimeInterval) {
        print("▶️ startRestTimer called - duration: \(duration)s")

        // Cancel any existing timer first
        if isResting {
            print("⚠️ Cancelling existing timer")
            stopRestTimer()
        }

        isResting = true
        restTimeRemaining = duration
        restDuration = duration
        isRestTimerMinimized = false
        restTimerState = .running
        WKInterfaceDevice.current().play(.start)

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if self.restTimeRemaining > 0 {
                    self.restTimeRemaining -= 1
                    let remaining = Int(self.restTimeRemaining)
                    if remaining % 10 == 0 || remaining < 5 {
                        print("⏱️ Timer tick - remaining: \(remaining)s")
                    }
                } else {
                    // Prevent multiple executions
                    guard self.restTimerState == .running else { return }

                    print("✅ Timer completed naturally")

                    // Set completion state FIRST (prevents re-entry)
                    self.restTimerState = .completed
                    self.isRestTimerMinimized = false

                    // Invalidate timer (but don't reset state like stopRestTimer does)
                    self.restTimer?.invalidate()
                    self.restTimer = nil

                    // Play haptic ONCE
                    WKInterfaceDevice.current().play(.success)

                    // Auto-dismiss after 2 seconds
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        self.isResting = false
                        self.restTimerState = .running
                        self.restTimeRemaining = 0
                        self.restDuration = 0
                    }
                }
            }
        }
        // Add timer to common run loop mode so it continues during scrolling
        RunLoop.current.add(timer, forMode: .common)
        restTimer = timer
    }

    func minimizeRestTimer() {
        isRestTimerMinimized = true
        WKInterfaceDevice.current().play(.click)
    }

    func expandRestTimer() {
        isRestTimerMinimized = false
        WKInterfaceDevice.current().play(.click)
    }

    private func stopRestTimer() {
        print("⏹️ stopRestTimer called - remaining: \(restTimeRemaining)s of \(restDuration)s")
        print("⏹️ Call stack: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")

        restTimer?.invalidate()
        restTimer = nil
        restTimeRemaining = 0
        restDuration = 0
        isRestTimerMinimized = false
        restTimerState = .running
    }

    // MARK: - HealthKit Observation

//    private func observeHealthKitMetrics() {
//        // Observe HealthKit manager's published properties
//        // In a real app, you'd use Combine or observation
//        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
//            Task { @MainActor in
//                guard let self = self else { return }
//                self.heartRate = self.healthKitManager.heartRate
//                self.activeCalories = self.healthKitManager.activeCalories
//                self.elapsedTime = self.healthKitManager.elapsedTime
//            }
//        }
//        // Add timer to common run loop mode so it continues during scrolling
//        RunLoop.current.add(timer, forMode: .common)
//    }

    // MARK: - Sync to iPhone

    private func sendCompletedWorkoutToiPhone(updateTemplate: Bool, healthKitWorkoutId: UUID) {
        guard let routine = currentRoutine,
              let startTime = workoutStartTime else { return }

        let workoutId = pendingCompletedWorkoutId ?? UUID()
        pendingCompletedWorkoutId = workoutId

        let completedWorkout = CompletedWatchWorkout(
            id: workoutId,
            routineId: routine.id,
            routineName: routine.name,
            startTime: startTime,
            endTime: Date(),
            exercises: exercises.map { $0.toCompletedExercise() },
            shouldUpdateTemplate: updateTemplate,
            healthKitWorkoutId: healthKitWorkoutId
        )

        connectivityManager.sendCompletedWorkout(completedWorkout)
    }

    // MARK: - Workout Summary

    private func generateWorkoutSummary() -> WatchWorkoutSummary {
        let exerciseSummaries = exercises.sorted(by: { $0.order < $1.order }).map { exercise in
            WatchWorkoutSummary.ExerciseSummary(
                id: exercise.id,
                name: exercise.name,
                muscleGroup: exercise.muscleGroup,
                completedSets: exercise.completedSetsCount,
                totalSets: exercise.sets.count,
                isComplete: exercise.isComplete,
                repGoalAchieved: exercise.allCompletedSetsAtUpperLimit
            )
        }

        let duration: TimeInterval
        if let startTime = workoutStartTime {
            duration = Date().timeIntervalSince(startTime)
        } else {
            duration = elapsedTime ?? 0
        }

        return WatchWorkoutSummary(
            routineName: currentRoutine?.name ?? String(localized: "Workout"),
            duration: duration,
            completedSets: completedSetsCount,
            totalSets: totalSetsCount,
            completionPercentage: Int(progress * 100),
            activeCalories: activeCalories,
            exercises: exerciseSummaries
        )
    }

    // MARK: - Helper Methods

    private func resetState() {
        currentRoutine = nil
        exercises = []
        currentExerciseIndex = 0
        currentSetIndex = 0
        workoutStartTime = nil
        pendingCompletedWorkoutId = nil
        pendingHealthKitWorkoutId = nil
        isResting = false
        restTimeRemaining = 0
        isPaused = false
        templateWasUpdated = false
    }
}
