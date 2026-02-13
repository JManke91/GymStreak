import Foundation
import SwiftData
import SwiftUI
import Combine
import UserNotifications
import ActivityKit
import HealthKit

// MARK: - HealthKit Sync Status

enum HealthKitSyncStatus: Equatable {
    case idle
    case syncing
    case success
    case failed(String)

    var isComplete: Bool {
        switch self {
        case .success, .failed:
            return true
        default:
            return false
        }
    }
}

@MainActor
class WorkoutViewModel: ObservableObject {
    @Published var currentSession: WorkoutSession?
    @Published var elapsedTime: TimeInterval = 0
    @Published var currentExerciseIndex: Int = 0
    @Published var currentSetIndex: Int = 0
    @Published var isRestTimerActive = false
    @Published var restTimeRemaining: TimeInterval = 0
    @Published var restDuration: TimeInterval = 0
    @Published var workoutHistory: [WorkoutSession] = []
    @Published var showingWorkoutCompletePrompt = false

    // HealthKit integration
    @Published var healthKitSyncEnabled = true
    @Published var healthKitSyncStatus: HealthKitSyncStatus = .idle
    @Published var showHealthKitAuthPrompt = false

    private var modelContext: ModelContext
    private var timer: Timer?
    private var restTimer: Timer?
    private var cloudSyncObserver: NSObjectProtocol?

    // Date-based timer tracking for background persistence
    private var workoutStartTime: Date?
    private var restTimerStartTime: Date?

    // Live Activity for rest timer
    private var currentRestActivity: Activity<RestTimerAttributes>?

    // HealthKit workout manager
    let healthKitManager = HealthKitWorkoutManager()

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UI_TESTING")
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchWorkoutHistory()
        // Skip notification permission during UI testing to avoid alert in screenshots
        if !isUITesting {
            requestNotificationPermission()
        }
        cleanupStaleActivities()
        loadHealthKitPreferences()
        healthKitManager.checkAuthorizationStatus()
        observeCloudKitChanges()
    }

    private func observeCloudKitChanges() {
        cloudSyncObserver = NotificationCenter.default.addObserver(
            forName: .cloudKitDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fetchWorkoutHistory()
            }
        }
    }

    // MARK: - HealthKit Preferences

    private func loadHealthKitPreferences() {
        healthKitSyncEnabled = UserDefaults.standard.object(forKey: "healthKitSyncEnabled") as? Bool ?? true
    }

    func setHealthKitSyncEnabled(_ enabled: Bool) {
        healthKitSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "healthKitSyncEnabled")
    }

    func requestHealthKitAuthorization() async {
        do {
            try await healthKitManager.requestAuthorization()
        } catch {
            print("HealthKit authorization failed: \(error)")
        }
    }

    func updateModelContext(_ newContext: ModelContext) {
        self.modelContext = newContext
        fetchWorkoutHistory()
    }

    // MARK: - Notification Permission

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
            if granted {
                print("Notification permission granted")
            } else {
                print("Notification permission denied")
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
            identifier: "restTimer",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling rest timer notification: \(error)")
            }
        }
    }

    private func cancelRestTimerNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["restTimer"])
    }

    // MARK: - Live Activity Management

    private func cleanupStaleActivities() {
        Task {
            for activity in Activity<RestTimerAttributes>.activities {
                // Check if timer has expired
                if activity.contentState.timerRange.upperBound < Date() {
                    await activity.end(dismissalPolicy: .immediate)
                }
            }
        }
    }

    private func startRestTimerLiveActivity(duration: TimeInterval) {
        // Check if Live Activities are enabled
        let authInfo = ActivityAuthorizationInfo()
        print("Live Activity Authorization Status: \(authInfo.areActivitiesEnabled)")
        print("Live Activity Frequent Updates Enabled: \(authInfo.frequentPushesEnabled)")

        guard authInfo.areActivitiesEnabled else {
            print("⚠️ Live Activities not enabled by user")
            return
        }

        let endDate = Date().addingTimeInterval(duration)
        let timerRange = Date.now...endDate

        // Get current exercise name if available
        let exerciseName: String? = {
            guard let session = currentSession else { return nil }
            let exercises = session.workoutExercisesList.sorted(by: { $0.order < $1.order })
            guard currentExerciseIndex < exercises.count else { return nil }
            return exercises[currentExerciseIndex].exerciseName
        }()

        let initialContentState = RestTimerAttributes.ContentState(
            timerRange: timerRange,
            exerciseName: exerciseName,
            completionMessage: nil
        )

        let attributes = RestTimerAttributes(
            workoutName: currentSession?.routine?.name ?? "Workout"
        )

        do {
            let activity = try Activity<RestTimerAttributes>.request(
                attributes: attributes,
                contentState: initialContentState,
                pushType: nil
            )
            currentRestActivity = activity
            print("✅ Started Live Activity: \(activity.id)")
        } catch {
            // Check for specific error messages in the error description
            let errorDescription = error.localizedDescription
            if errorDescription.contains("unsupportedTarget") {
                print("❌ Live Activity Error: unsupportedTarget - NSSupportsLiveActivities must be set to YES in Info.plist")
            } else if errorDescription.contains("activitiesDisabled") {
                print("❌ Live Activity Error: User has disabled Live Activities")
            } else if errorDescription.contains("activityLimitExceeded") {
                print("❌ Live Activity Error: Too many active Live Activities")
            } else {
                print("❌ Live Activity Error: \(errorDescription)")
            }
        }
    }

    private func endRestTimerLiveActivity() {
        guard let activity = currentRestActivity else { return }

        Task {
            // Show "Rest Complete" for 3 seconds then dismiss
            let finalState = RestTimerAttributes.ContentState(
                timerRange: Date.now...Date.now,
                exerciseName: nil,
                completionMessage: "Rest Complete! 💪"
            )

            await activity.end(
                using: finalState,
                dismissalPolicy: .after(Date.now.addingTimeInterval(3))
            )
        }

        currentRestActivity = nil
    }

    // MARK: - Background Timer Persistence

    func saveTimerState() {
        // Save workout timer state
        if let startTime = workoutStartTime {
            UserDefaults.standard.set(startTime, forKey: "workoutStartTime")
        }

        // Save rest timer state
        if let restStart = restTimerStartTime, restDuration > 0 {
            UserDefaults.standard.set(restStart, forKey: "restTimerStartTime")
            UserDefaults.standard.set(restDuration, forKey: "restDuration")
        }
    }

    func restoreTimerState() {
        // Restore workout timer
        if let startTime = UserDefaults.standard.object(forKey: "workoutStartTime") as? Date {
            let elapsed = Date().timeIntervalSince(startTime)
            elapsedTime = elapsed
            workoutStartTime = startTime
        }

        // Restore rest timer
        if let restStart = UserDefaults.standard.object(forKey: "restTimerStartTime") as? Date,
           let duration = UserDefaults.standard.object(forKey: "restDuration") as? TimeInterval {
            let elapsed = Date().timeIntervalSince(restStart)
            let remaining = max(0, duration - elapsed)

            if remaining > 0 {
                // Timer still running
                restTimeRemaining = remaining
                isRestTimerActive = true
                restTimerStartTime = restStart
                restDuration = duration

                // Restart Live Activity if not already active
                if currentRestActivity == nil {
                    startRestTimerLiveActivity(duration: remaining)
                }

                // Restart the UI update timer
                startRestTimerUI()
            } else {
                // Timer has completed while in background
                stopRestTimer()
            }
        }
    }

    private func clearTimerState() {
        UserDefaults.standard.removeObject(forKey: "workoutStartTime")
        UserDefaults.standard.removeObject(forKey: "restTimerStartTime")
        UserDefaults.standard.removeObject(forKey: "restDuration")
    }

    // MARK: - Workout Session Management

    func startWorkout(routine: Routine) {
        let session = WorkoutSession(routine: routine)

        // Create workout exercises from routine (sorted by order to maintain routine sequence)
        let sortedRoutineExercises = routine.routineExercisesList.sorted(by: { $0.order < $1.order })
        for (index, routineExercise) in sortedRoutineExercises.enumerated() {
            let workoutExercise = WorkoutExercise(from: routineExercise, order: index)
            workoutExercise.workoutSession = session
            session.workoutExercises?.append(workoutExercise)
        }

        currentSession = session
        elapsedTime = 0
        currentExerciseIndex = 0
        currentSetIndex = 0
        healthKitSyncStatus = .idle

        modelContext.insert(session)
        save()

        startTimer()

        // Start HealthKit workout session
        startHealthKitSession()
    }

    private func startHealthKitSession() {
        // Skip HealthKit during UI testing to avoid authorization alert in screenshots
        guard !isUITesting, healthKitSyncEnabled, healthKitManager.isHealthKitAvailable else {
            return
        }

        Task {
            // Check if we need authorization
            if !healthKitManager.isAuthorized {
                do {
                    try await healthKitManager.requestAuthorization()
                } catch {
                    print("HealthKit authorization failed: \(error)")
                    return
                }
            }

            // Start the workout session
            if healthKitManager.isAuthorized {
                do {
                    try await healthKitManager.startWorkoutSession()
                    print("HealthKit workout session started successfully")
                } catch {
                    print("Failed to start HealthKit session: \(error)")
                    // Continue with workout even if HealthKit fails
                }
            }
        }
    }

    func cancelWorkout() {
        stopTimer()
        stopRestTimer()

        // Cancel HealthKit session without saving
        healthKitManager.cancelWorkoutSession()

        if let session = currentSession {
            modelContext.delete(session)
            save()
        }

        currentSession = nil
        elapsedTime = 0
        currentExerciseIndex = 0
        currentSetIndex = 0
        healthKitSyncStatus = .idle
    }

    func pauseForCompletion() {
        guard let session = currentSession else { return }

        // Stop timers and set end time when user clicks "Finish Workout"
        stopTimer()
        stopRestTimer()
        session.endTime = Date()
        save()
    }

    func completeWorkout(updateTemplate: Bool, notes: String) {
        guard let session = currentSession else { return }

        // Update workout details
        session.notes = notes
        session.didUpdateTemplate = updateTemplate

        if updateTemplate {
            updateRoutineTemplate(session: session)
        }

        save()
        fetchWorkoutHistory()

        // Save to HealthKit
        saveWorkoutToHealthKit(session: session)

        currentSession = nil
        elapsedTime = 0
    }

    private func saveWorkoutToHealthKit(session: WorkoutSession) {
        guard healthKitSyncEnabled && healthKitManager.isHealthKitAvailable else {
            healthKitSyncStatus = .idle
            return
        }

        healthKitSyncStatus = .syncing

        Task {
            do {
                // Calculate estimated calories burned
                let estimatedCalories = healthKitManager.estimateCaloriesBurned(
                    durationInSeconds: session.duration
                )

                // Create metadata for the workout
                var metadata: [String: Any] = [:]

                // Use routine name as the workout brand name (displayed in Fitness app)
                // Fall back to "GymStreak" if no routine name available
                if let routineName = session.routine?.name, !routineName.isEmpty {
                    metadata[HKMetadataKeyWorkoutBrandName] = routineName
                    metadata["RoutineName"] = routineName
                } else {
                    metadata[HKMetadataKeyWorkoutBrandName] = "GymStreak"
                }

                if !session.notes.isEmpty {
                    metadata["Notes"] = session.notes
                }

                let healthKitWorkoutId: UUID

                // Try to end the active session first
                if healthKitManager.isWorkoutActive {
                    let result = try await healthKitManager.endWorkoutSession(
                        totalEnergyBurned: estimatedCalories,
                        metadata: metadata
                    )
                    healthKitWorkoutId = result.healthKitWorkoutId
                } else {
                    // Fall back to direct save if no active session
                    let result = try await healthKitManager.saveWorkoutDirectly(
                        startDate: session.startTime,
                        endDate: session.endTime ?? Date(),
                        totalEnergyBurned: estimatedCalories,
                        metadata: metadata
                    )
                    healthKitWorkoutId = result.healthKitWorkoutId
                }

                // Store the HealthKit workout ID in the session for correlation
                session.healthKitWorkoutId = healthKitWorkoutId
                save()

                healthKitSyncStatus = .success
                print("Workout synced to HealthKit successfully with ID: \(healthKitWorkoutId)")

            } catch {
                healthKitSyncStatus = .failed(error.localizedDescription)
                print("Failed to sync workout to HealthKit: \(error)")
            }
        }
    }

    // MARK: - Set Management

    func completeSet(workoutExercise: WorkoutExercise, set: WorkoutSet) {
        guard currentSession != nil else { return }

        objectWillChange.send()
        set.isCompleted = true
        set.completedAt = Date()
        save()

        // Check if there's any more work to do in the workout
        let hasMoreWork = findNextIncompleteSet() != nil

        // For superset exercises, use interleaving logic with round-based rest
        if workoutExercise.isInSuperset {
            if findNextIncompleteSetForSuperset(after: set, in: workoutExercise) != nil {
                // More sets in superset - only start rest timer if this completes a round
                // (i.e., all exercises at this set level are now complete)
                if isEndOfSupersetRound(completedSet: set, in: workoutExercise) {
                    let restTime = supersetRoundRestTime(for: set, in: workoutExercise)
                    if restTime > 0 {
                        startRestTimer(duration: restTime)
                    }
                }
                // Navigation is handled by findNextIncompleteSet() which ActiveWorkoutView uses
            } else if hasMoreWork {
                // Superset complete, but more exercises remain - trigger rest for final round
                let restTime = supersetRoundRestTime(for: set, in: workoutExercise)
                if restTime > 0 {
                    startRestTimer(duration: restTime)
                }
                moveToNextExercise()
            } else {
                // Workout complete
                moveToNextExercise()
                pauseForCompletion()
                showingWorkoutCompletePrompt = true
            }
        } else {
            // Standard (non-superset) behavior
            if findNextIncompleteSet(after: set, in: workoutExercise) != nil {
                // More sets in same exercise - start rest timer if configured
                if set.restTime > 0 {
                    startRestTimer(duration: set.restTime)
                }
            } else if hasMoreWork {
                // No more sets in current exercise, but more exercises remain
                if set.restTime > 0 {
                    startRestTimer(duration: set.restTime)
                }
                moveToNextExercise()
            } else {
                // Workout complete - no more work to do
                moveToNextExercise()
                pauseForCompletion()
                showingWorkoutCompletePrompt = true
            }
        }
    }

    func uncompleteSet(_ set: WorkoutSet) {
        guard currentSession != nil else { return }

        objectWillChange.send()
        set.isCompleted = false
        set.completedAt = nil
        save()
    }

    func updateSet(_ set: WorkoutSet, reps: Int, weight: Double) {
        objectWillChange.send()
        set.actualReps = reps
        set.actualWeight = weight
        save()
    }

    func updateRestTimeForExercise(_ workoutExercise: WorkoutExercise, restTime: TimeInterval) {
        objectWillChange.send()
        for set in workoutExercise.setsList {
            set.restTime = restTime
        }
        save()
    }

    func addSetToExercise(_ workoutExercise: WorkoutExercise) {
        guard currentSession != nil else { return }

        objectWillChange.send()

        // Get the last set to copy its values
        let lastSet = workoutExercise.setsList.sorted(by: { $0.order < $1.order }).last

        // Create new workout set using the last set's values (or defaults if no sets exist)
        let newSet = WorkoutSet(
            plannedReps: lastSet?.plannedReps ?? 10,
            actualReps: lastSet?.actualReps ?? 10,
            plannedWeight: lastSet?.plannedWeight ?? 0.0,
            actualWeight: lastSet?.actualWeight ?? 0.0,
            restTime: lastSet?.restTime ?? 60.0,
            order: (lastSet?.order ?? -1) + 1
        )
        newSet.workoutExercise = workoutExercise
        workoutExercise.sets?.append(newSet)

        modelContext.insert(newSet)
        save()
    }

    func addExerciseToWorkout(exercise: Exercise) {
        guard let session = currentSession else { return }

        objectWillChange.send()

        // Determine the order for the new exercise
        let nextOrder = (session.workoutExercisesList.map(\.order).max() ?? -1) + 1

        // Create a workout exercise from the library exercise
        let workoutExercise = WorkoutExercise(
            exerciseName: exercise.name,
            muscleGroups: exercise.muscleGroups,
            order: nextOrder
        )
        workoutExercise.workoutSession = session

        // Add default set
        let defaultSet = WorkoutSet(
            plannedReps: 10,
            actualReps: 10,
            plannedWeight: 0.0,
            actualWeight: 0.0,
            restTime: 60.0,
            order: 0
        )
        defaultSet.workoutExercise = workoutExercise
        workoutExercise.sets?.append(defaultSet)

        session.workoutExercises?.append(workoutExercise)
        modelContext.insert(workoutExercise)
        modelContext.insert(defaultSet)
        save()
    }

    func removeSetFromExercise(_ set: WorkoutSet, from workoutExercise: WorkoutExercise) {
        guard currentSession != nil else { return }

        objectWillChange.send()

        if let index = workoutExercise.setsList.firstIndex(where: { $0.id == set.id }) {
            workoutExercise.sets?.remove(at: index)
            modelContext.delete(set)
            save()
        }
    }

    func removeExerciseFromWorkout(_ workoutExercise: WorkoutExercise) {
        guard let session = currentSession else { return }

        objectWillChange.send()

        // Remove all sets associated with this exercise
        for set in workoutExercise.setsList {
            modelContext.delete(set)
        }

        // Remove the exercise from the session
        if let index = session.workoutExercisesList.firstIndex(where: { $0.id == workoutExercise.id }) {
            session.workoutExercises?.remove(at: index)
        }

        modelContext.delete(workoutExercise)
        save()
    }

    func skipSet(workoutExercise: WorkoutExercise, set: WorkoutSet) {
        // Move to next set without marking complete
        if let nextSet = findNextIncompleteSet(after: set, in: workoutExercise) {
            // Update current set index
            if let index = workoutExercise.setsList.firstIndex(where: { $0.id == nextSet.id }) {
                currentSetIndex = index
            }
        } else {
            moveToNextExercise()
        }
    }

    // MARK: - Timer Management

    private func startTimer() {
        timer?.invalidate()

        // Save workout start time for background persistence
        workoutStartTime = Date()
        saveTimerState()

        let newTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let startTime = self.workoutStartTime else { return }
                // Calculate elapsed time from start date for accuracy
                self.elapsedTime = Date().timeIntervalSince(startTime)
            }
        }

        // Add timer to RunLoop with .common mode to ensure it fires during scrolling
        RunLoop.current.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        workoutStartTime = nil
        clearTimerState()
    }

    func pauseWorkout() {
        stopTimer()
    }

    func resumeWorkout() {
        startTimer()
    }

    func startRestTimer(duration: TimeInterval) {
        stopRestTimer()

        restTimeRemaining = duration
        isRestTimerActive = true

        // Save rest timer start time and duration for background persistence
        restTimerStartTime = Date()
        restDuration = duration
        saveTimerState()

        // Schedule notification for when rest timer completes
        scheduleRestTimerNotification(duration: duration)

        // Start Live Activity for Lock Screen display
        startRestTimerLiveActivity(duration: duration)

        // Start UI update timer
        startRestTimerUI()
    }

    private func startRestTimerUI() {
        restTimer?.invalidate()

        let newRestTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if self.restTimeRemaining > 0 {
                    self.restTimeRemaining -= 1

                    // Haptic feedback at 3 seconds
                    if self.restTimeRemaining == 3 {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } else {
                    self.stopRestTimer()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }

        // Add timer to RunLoop with .common mode to ensure it fires during scrolling
        RunLoop.current.add(newRestTimer, forMode: .common)
        restTimer = newRestTimer
    }

    func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        isRestTimerActive = false
        restTimeRemaining = 0

        // Clear rest timer state
        restTimerStartTime = nil
        restDuration = 0

        // Cancel any pending notification
        cancelRestTimerNotification()

        // End Live Activity
        endRestTimerLiveActivity()

        // Clear saved state
        UserDefaults.standard.removeObject(forKey: "restTimerStartTime")
        UserDefaults.standard.removeObject(forKey: "restDuration")
    }

    // MARK: - Workout Completion Check

    var isWorkoutComplete: Bool {
        guard let session = currentSession else { return false }
        return session.completedSetsCount == session.totalSetsCount && session.totalSetsCount > 0
    }

    func resumeAfterCompletionPrompt() {
        // Restart timer if workout is still active
        if currentSession != nil {
            startTimer()
        }
    }

    // MARK: - Navigation Helpers

    private func findNextIncompleteSet(after currentSet: WorkoutSet, in workoutExercise: WorkoutExercise) -> WorkoutSet? {
        let sets = workoutExercise.setsList
        guard let currentIndex = sets.firstIndex(where: { $0.id == currentSet.id }) else {
            return nil
        }

        // Find next incomplete set in same exercise
        for index in (currentIndex + 1)..<sets.count {
            let set = sets[index]
            if !set.isCompleted {
                currentSetIndex = index
                return set
            }
        }

        return nil
    }

    /// Finds the next incomplete set following superset interleaving logic.
    /// For supersets, alternates between exercises: A1 → B1 → A2 → B2 → A3 → B3
    /// For standalone exercises, returns the next incomplete set in that exercise.
    func findNextIncompleteSetForSuperset(
        after currentSet: WorkoutSet,
        in workoutExercise: WorkoutExercise
    ) -> (exercise: WorkoutExercise, set: WorkoutSet)? {
        guard let session = currentSession,
              let supersetId = workoutExercise.supersetId else {
            // Not in a superset - fall back to standard behavior
            if let nextSet = findNextIncompleteSet(after: currentSet, in: workoutExercise) {
                return (workoutExercise, nextSet)
            }
            return nil
        }

        // Get all exercises in this superset, sorted by supersetOrder
        let supersetExercises = session.workoutExercisesList
            .filter { $0.supersetId == supersetId }
            .sorted { $0.supersetOrder < $1.supersetOrder }

        guard supersetExercises.count > 1 else {
            // Single exercise in "superset" - treat as standalone
            if let nextSet = findNextIncompleteSet(after: currentSet, in: workoutExercise) {
                return (workoutExercise, nextSet)
            }
            return nil
        }

        // Find current exercise's position in the superset
        guard let currentExerciseIdx = supersetExercises.firstIndex(where: { $0.id == workoutExercise.id }) else {
            return nil
        }

        let currentSetOrder = currentSet.order
        let maxSets = supersetExercises.map { $0.setsList.count }.max() ?? 0

        // Interleaving pattern: for set level N, go through all exercises before moving to N+1
        // Starting from current position, find the next incomplete set
        for setLevel in currentSetOrder..<maxSets {
            // Determine starting exercise index for this set level
            let startIdx = (setLevel == currentSetOrder) ? (currentExerciseIdx + 1) : 0

            for offset in 0..<supersetExercises.count {
                let exerciseIdx = (startIdx + offset) % supersetExercises.count

                // For the current set level, skip exercises we've already passed
                if setLevel == currentSetOrder && exerciseIdx <= currentExerciseIdx {
                    continue
                }

                let exercise = supersetExercises[exerciseIdx]
                let sets = exercise.setsList.sorted { $0.order < $1.order }

                if let set = sets.first(where: { $0.order == setLevel && !$0.isCompleted }) {
                    return (exercise, set)
                }
            }
        }

        return nil
    }

    func findNextIncompleteSet() -> (exercise: WorkoutExercise, set: WorkoutSet)? {
        guard let session = currentSession else { return nil }

        // Use superset-aware ordering: iterate through grouped exercises
        for group in session.exercisesGroupedBySupersets {
            if group.count > 1 {
                // Superset group - interleave sets (A1 → B1 → A2 → B2 → ...)
                let maxSets = group.map { $0.setsList.count }.max() ?? 0
                for setLevel in 0..<maxSets {
                    for exercise in group {
                        let sets = exercise.setsList.sorted { $0.order < $1.order }
                        if let set = sets.first(where: { $0.order == setLevel && !$0.isCompleted }) {
                            return (exercise, set)
                        }
                    }
                }
            } else if let exercise = group.first {
                // Standalone exercise - sequential sets
                for set in exercise.setsList.sorted(by: { $0.order < $1.order }) {
                    if !set.isCompleted {
                        return (exercise, set)
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Superset Round Detection

    /// Determines if completing this set ends a superset round (should trigger rest timer).
    /// A round ends when ALL sets at the completed set's level are complete across all superset exercises.
    /// For example, in superset [A, B]: A1→B1 is round 1, A2→B2 is round 2, etc.
    private func isEndOfSupersetRound(
        completedSet: WorkoutSet,
        in workoutExercise: WorkoutExercise
    ) -> Bool {
        guard let session = currentSession,
              let supersetId = workoutExercise.supersetId else {
            // Not in a superset - always trigger rest (standard behavior)
            return true
        }

        // Get all exercises in this superset, sorted by supersetOrder
        let supersetExercises = session.workoutExercisesList
            .filter { $0.supersetId == supersetId }
            .sorted { $0.supersetOrder < $1.supersetOrder }

        guard supersetExercises.count > 1 else {
            // Single exercise "superset" - treat as standalone
            return true
        }

        let completedSetLevel = completedSet.order

        // Check if ALL sets at this level are now complete
        for exercise in supersetExercises {
            if let setAtLevel = exercise.setsList.first(where: { $0.order == completedSetLevel }) {
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
    private func supersetRoundRestTime(
        for completedSet: WorkoutSet,
        in workoutExercise: WorkoutExercise
    ) -> TimeInterval {
        guard let session = currentSession,
              let supersetId = workoutExercise.supersetId else {
            // Not in a superset - use the set's own rest time
            return completedSet.restTime
        }

        let supersetExercises = session.workoutExercisesList
            .filter { $0.supersetId == supersetId }
            .sorted { $0.supersetOrder < $1.supersetOrder }

        guard supersetExercises.count > 1 else {
            // Single exercise "superset" - use set's own rest time
            return completedSet.restTime
        }

        let completedSetLevel = completedSet.order

        // Find the last exercise that has a set at this level and get its rest time
        for exercise in supersetExercises.reversed() {
            if let setAtLevel = exercise.setsList.first(where: { $0.order == completedSetLevel }) {
                return setAtLevel.restTime
            }
        }

        // Fallback to the completed set's rest time
        return completedSet.restTime
    }

    private func moveToNextExercise() {
        guard let session = currentSession else { return }

        let sortedExercises = session.workoutExercisesList.sorted(by: { $0.order < $1.order })

        if currentExerciseIndex < sortedExercises.count - 1 {
            currentExerciseIndex += 1
            currentSetIndex = 0
        }
    }

    // MARK: - Template Update

    private func updateRoutineTemplate(session: WorkoutSession) {
        guard let routine = session.routine else { return }

        for workoutExercise in session.workoutExercisesList {
            // Find corresponding routine exercise
            if let routineExercise = routine.routineExercisesList.first(where: {
                $0.exercise?.name == workoutExercise.exerciseName
            }) {
                // Get the rest time from the first set (all sets should have same rest time)
                let exerciseRestTime = workoutExercise.setsList.first?.restTime ?? 60.0

                // Update all routine sets with the exercise rest time and completed set data
                let workoutSets = workoutExercise.setsList
                for (index, routineSet) in routineExercise.setsList.enumerated() {
                    // Always update rest time for all sets
                    routineSet.restTime = exerciseRestTime

                    // Update reps and weight only for completed sets
                    if index < workoutSets.count {
                        let workoutSet = workoutSets[index]
                        if workoutSet.isCompleted {
                            routineSet.reps = workoutSet.actualReps
                            routineSet.weight = workoutSet.actualWeight
                        }
                    }
                }
            }
        }

        routine.updatedAt = Date()
        save()
    }

    // MARK: - History

    func fetchWorkoutHistory() {
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        do {
            workoutHistory = try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching workout history: \(error)")
        }
    }

    func deleteWorkout(_ session: WorkoutSession) {
        modelContext.delete(session)
        save()
        fetchWorkoutHistory()
    }

    // MARK: - Helper Methods

    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }

    deinit {
        timer?.invalidate()
        restTimer?.invalidate()
    }
}
