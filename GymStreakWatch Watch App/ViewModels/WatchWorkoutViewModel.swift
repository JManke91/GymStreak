import Foundation
import Combine
import WatchKit
import UserNotifications

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

    // Error handling
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let healthKitManager: WatchHealthKitManager
    private let connectivityManager: WatchConnectivityManager
    private var workoutStartTime: Date?
    private var restTimer: Timer?
    private var cancellabes = Set<AnyCancellable>()

    // MARK: - Initialization

    init(healthKitManager: WatchHealthKitManager, connectivityManager: WatchConnectivityManager) {
        self.healthKitManager = healthKitManager
        self.connectivityManager = connectivityManager
//        observeHealthKitMetrics()
        requestNotificationPermission()

        healthKitManager.$elapsedTime
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .map { interval in
                    let minutes = Int(interval) / 60
                    let seconds = Int(interval) % 60
                    return String(format: "%02d:%02d", minutes, seconds)
                }
            .assign(to: \.elapsedTimeString, on: self)
//            .sink { elapsedTime in
//                self.elapsedTime = elapsedTime
//            }
            .store(in: &cancellabes)

        healthKitManager.$heartRate
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { heartRate in
                print("wtf heartRate received: \(heartRate)")
                self.heartRate = Int(heartRate)
            }
            .store(in: &cancellabes)

        healthKitManager.$activeCalories
//            .subscribe(on: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { calories in
                print("wtf calories received: \(calories)")
            self.activeCalories = Int(calories)
        }
        .store(in: &cancellabes)

        healthKitManager.$activeCalories.compactMap { $0 }.removeDuplicates().combineLatest(healthKitManager.$heartRate.compactMap { $0 }.removeDuplicates())
        // state only needs to be set once
        // FIXME: prevents data showing in a subsequent workout
//            .prefix(1)
            .filter { _ in self.workoutState != .running }
            .sink { combined in
                print("wtf received workout metrics: \(combined.0 ?? 0), \(combined.1 ?? 0)")
                self.workoutState = .running
            }
            .store(in: &cancellabes)
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
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
        content.title = "Rest Complete"
        content.body = "Time to start your next set!"
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
        exercises = routine.exercises.map { $0.toActiveWorkoutExercise() }
        currentExerciseIndex = 0
        currentSetIndex = 0
        workoutStartTime = Date()

        // Request HealthKit authorization and start session
        let authorized = await healthKitManager.requestAuthorization()
        guard authorized else {
            errorMessage = "HealthKit authorization required"
            return
        }

        do {
            // Provide the routine name so HealthKit workout metadata includes it
            try await healthKitManager.startWorkout(routineName: routine.name)
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
        stopRestTimer()

        do {
            let (_, healthKitWorkoutId) = try await healthKitManager.endWorkout()
            await sendCompletedWorkoutToiPhone(updateTemplate: updateTemplate, healthKitWorkoutId: healthKitWorkoutId)
            isWorkoutActive = false
            workoutState = .stopped
            WKInterfaceDevice.current().play(.success)
        } catch {
            errorMessage = "Failed to save workout: \(error.localizedDescription)"
        }
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

//        exercises[r.exerciseIndex].sets[r.setIndex].isCompleted = r.newState

        if r.newState {
            exercises[r.exerciseIndex].sets[r.setIndex].completedAt = Date()
            WKInterfaceDevice.current().play(.success)

            let restTime = exercises[r.exerciseIndex].sets[r.setIndex].restTime
            if restTime > 0 {
                startRestTimer(duration: restTime)
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

    private func advanceToNextSet() {
        guard let exercise = currentExercise else { return }

        if currentSetIndex < exercise.sets.count - 1 {
            // Move to next set in current exercise
            currentSetIndex += 1
        } else if currentExerciseIndex < exercises.count - 1 {
            // Move to next exercise
            currentExerciseIndex += 1
            currentSetIndex = 0
        }
        // If we're at the last set of the last exercise, stay there
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
            Task { @MainActor in
                guard let self = self else { return }

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

    private func sendCompletedWorkoutToiPhone(updateTemplate: Bool, healthKitWorkoutId: UUID) async {
        guard let routine = currentRoutine,
              let startTime = workoutStartTime else { return }

        let completedWorkout = CompletedWatchWorkout(
            id: UUID(),
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

    // MARK: - Helper Methods

    private func resetState() {
        currentRoutine = nil
        exercises = []
        currentExerciseIndex = 0
        currentSetIndex = 0
        workoutStartTime = nil
        isResting = false
        restTimeRemaining = 0
        isPaused = false
    }
}
