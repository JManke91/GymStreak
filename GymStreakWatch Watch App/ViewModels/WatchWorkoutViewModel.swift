import Foundation
import Combine
import WatchKit
import UserNotifications

@MainActor
final class WatchWorkoutViewModel: ObservableObject {
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

    enum RestTimerState {
        case running
        case completed
    }

    // HealthKit Metrics
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var elapsedTime: TimeInterval = 0

    // Error handling
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let healthKitManager: WatchHealthKitManager
    private let connectivityManager: WatchConnectivityManager
    private var workoutStartTime: Date?
    private var restTimer: Timer?

    // MARK: - Initialization

    init(healthKitManager: WatchHealthKitManager, connectivityManager: WatchConnectivityManager) {
        self.healthKitManager = healthKitManager
        self.connectivityManager = connectivityManager
        observeHealthKitMetrics()
        requestNotificationPermission()
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
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
            try await healthKitManager.startWorkout()
            isWorkoutActive = true
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
            _ = try await healthKitManager.endWorkout()
            await sendCompletedWorkoutToiPhone(updateTemplate: updateTemplate)
            isWorkoutActive = false
            WKInterfaceDevice.current().play(.success)
        } catch {
            errorMessage = "Failed to save workout: \(error.localizedDescription)"
        }
    }

    func discardWorkout() {
        stopRestTimer()
        healthKitManager.discardWorkout()
        isWorkoutActive = false
        resetState()
    }

    // MARK: - Set Management

    func toggleSetCompletion(_ setId: UUID, in exerciseId: UUID) {
        guard let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            return
        }

        // Toggle completion status
        let wasCompleted = exercises[exerciseIndex].sets[setIndex].isCompleted
        exercises[exerciseIndex].sets[setIndex].isCompleted.toggle()

        if exercises[exerciseIndex].sets[setIndex].isCompleted {
            // Just completed
            exercises[exerciseIndex].sets[setIndex].completedAt = Date()
            WKInterfaceDevice.current().play(.success)

            // Start rest timer if applicable
            let restTime = exercises[exerciseIndex].sets[setIndex].restTime
            if restTime > 0 {
                startRestTimer(duration: restTime)
            }
        } else {
            // Just uncompleted
            exercises[exerciseIndex].sets[setIndex].completedAt = nil
            WKInterfaceDevice.current().play(.directionDown)
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
        exercise.sets[currentSetIndex].isCompleted = true
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

                    // Stop timer BEFORE playing haptic
                    self.stopRestTimer()

                    // Play haptic ONCE
                    WKInterfaceDevice.current().play(.success)

                    // Auto-dismiss after 2 seconds
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        self.isResting = false
                        self.restTimerState = .running
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

    private func observeHealthKitMetrics() {
        // Observe HealthKit manager's published properties
        // In a real app, you'd use Combine or observation
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.heartRate = self.healthKitManager.heartRate
                self.activeCalories = self.healthKitManager.activeCalories
                self.elapsedTime = self.healthKitManager.elapsedTime
            }
        }
        // Add timer to common run loop mode so it continues during scrolling
        RunLoop.current.add(timer, forMode: .common)
    }

    // MARK: - Sync to iPhone

    private func sendCompletedWorkoutToiPhone(updateTemplate: Bool) async {
        guard let routine = currentRoutine,
              let startTime = workoutStartTime else { return }

        let completedWorkout = CompletedWatchWorkout(
            id: UUID(),
            routineId: routine.id,
            routineName: routine.name,
            startTime: startTime,
            endTime: Date(),
            exercises: exercises.map { $0.toCompletedExercise() },
            shouldUpdateTemplate: updateTemplate
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
