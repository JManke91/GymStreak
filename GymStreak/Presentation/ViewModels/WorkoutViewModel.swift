import Foundation
import SwiftUI
import Combine
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
    @Published private(set) var restTimerReminderOutcome: RestTimerReminderOutcome?
    @Published var workoutHistory: [WorkoutSession] = []
    @Published var showingWorkoutCompletePrompt = false
    /// HealthKit-saved workouts (from this device's GymStreak iOS or watch app)
    /// that have no matching `WorkoutSession` in SwiftData. Populated by the
    /// reconciler safety-net layer of the watch sync pipeline.
    @Published var orphanedWatchWorkouts: [OrphanedWorkout] = []

    // HealthKit integration
    @Published var healthKitSyncEnabled = true
    @Published var healthKitSyncStatus: HealthKitSyncStatus = .idle
    @Published var showHealthKitAuthPrompt = false

    var restTimerReminderWarning: String? {
        switch restTimerReminderOutcome {
        case .authorizationDenied:
            return "rest_timer.reminder.authorization_denied".localized
        case .alertsUnavailable:
            return "rest_timer.reminder.alerts_unavailable".localized
        case .failed:
            return "rest_timer.reminder.failed".localized
        case .scheduled, .deadlinePassed, .cancelled, nil:
            return nil
        }
    }

    private let workoutSessionRepository: WorkoutSessionRepository
    private let routineRepository: RoutineRepository
    private let exerciseRepository: ExerciseRepository
    private let watchSync: WatchSyncServicing
    private let workoutHistoryCorrelation: WorkoutHistoryCorrelationProviding
    private let restTimerReminders: RestTimerReminderScheduling
    private let aiCoachCache: AICoachCaching
    private let now: () -> Date
    private var timer: Timer?
    private var restTimer: Timer?
    private var restTimerReminderTask: Task<Void, Never>?
    private var cloudSyncObserver: NSObjectProtocol?
    private var workoutHistoryObserver: NSObjectProtocol?

    // Date-based timer tracking for background persistence
    private var workoutStartTime: Date?
    private var restTimerStartTime: Date?
    private var restTimerDeadline: Date?
    private var restTimerID: UUID?
    private var hasPlayedRestCountdownHaptic = false

    // Live Activity for rest timer
    private var currentRestActivity: Activity<RestTimerAttributes>?

    // HealthKit workout manager
    let healthKitManager: HealthKitWorkoutServicing

    /// App-lifetime engine that owns incremental HealthKit discovery, the
    /// durable recovery ledger, and the conservative reconciler (ticket 09).
    /// The banner mirrors its `recoverableWorkouts`; nil in unit tests.
    private let recovery: WorkoutRecoveryCoordinating?
    private var recoverableWorkoutsObserver: NSObjectProtocol?

    /// Pre-apply values captured when progressive overload is applied, keyed by
    /// WorkoutExercise.id, so the completion screen can offer Undo. In-memory
    /// only — undo is available while the session is still open.
    private struct OverloadSnapshot {
        struct SetValues {
            let plannedReps: Int
            let actualReps: Int
            let plannedWeight: Double
            let actualWeight: Double
        }
        struct TemplateValues {
            let reps: Int
            let weight: Double
        }
        let workoutSetValues: [UUID: SetValues]
        let templateSetValues: [UUID: TemplateValues]
    }
    private var overloadSnapshots: [UUID: OverloadSnapshot] = [:]

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UI_TESTING")
    }

    // `aiCoachCache`'s default is resolved inside this @MainActor-isolated init body —
    // a `= AICoachCache.shared` default argument would be evaluated in a nonisolated
    // context (error under Swift 6 language mode).
    init(
        workoutSessionRepository: WorkoutSessionRepository,
        routineRepository: RoutineRepository,
        exerciseRepository: ExerciseRepository,
        healthKitManager: HealthKitWorkoutServicing,
        watchSync: WatchSyncServicing,
        workoutHistoryCorrelation: WorkoutHistoryCorrelationProviding,
        restTimerReminders: RestTimerReminderScheduling,
        recovery: WorkoutRecoveryCoordinating? = nil,
        aiCoachCache: AICoachCaching? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.workoutSessionRepository = workoutSessionRepository
        self.routineRepository = routineRepository
        self.exerciseRepository = exerciseRepository
        self.healthKitManager = healthKitManager
        self.watchSync = watchSync
        self.workoutHistoryCorrelation = workoutHistoryCorrelation
        self.restTimerReminders = restTimerReminders
        self.recovery = recovery
        self.aiCoachCache = aiCoachCache ?? AICoachCache.shared
        self.now = now
        fetchWorkoutHistory()
        cleanupStaleActivities()
        loadHealthKitPreferences()
        healthKitManager.checkAuthorizationStatus()
        observeCloudKitChanges()
        observeWorkoutHistoryChanges()
        observeRecoverableWorkouts()
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

    /// Refreshes the cached workout history when an external producer (e.g.
    /// the watch-sync path in RoutinesViewModel) commits a new WorkoutSession
    /// to SwiftData. Without this, HistoryView would display stale data until
    /// the user leaves and re-enters the tab.
    private func observeWorkoutHistoryChanges() {
        workoutHistoryObserver = NotificationCenter.default.addObserver(
            forName: .workoutHistoryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fetchWorkoutHistory()
                // A committed session may resolve a recovery candidate — let
                // the engine re-evaluate against the new history.
                self?.recovery?.reconcile()
            }
        }
    }

    /// Mirrors the recovery engine's published candidates into
    /// `orphanedWatchWorkouts` so the History banner stays in sync.
    private func observeRecoverableWorkouts() {
        orphanedWatchWorkouts = recovery?.recoverableWorkouts ?? []
        recoverableWorkoutsObserver = NotificationCenter.default.addObserver(
            forName: .recoverableWorkoutsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.orphanedWatchWorkouts = self?.recovery?.recoverableWorkouts ?? []
            }
        }
    }

    // MARK: - Watch Workout Reconciliation

    /// Triggers a fresh incremental HealthKit drain + reconcile in the recovery
    /// engine and mirrors its current candidates. Called from HistoryView's
    /// scenePhase observer when the app becomes active; the engine also drains
    /// at launch and on HealthKit background wake-ups.
    func reconcileWatchWorkouts() async {
        recovery?.refresh()
        orphanedWatchWorkouts = recovery?.recoverableWorkouts ?? []
    }

    /// Reconstructs SwiftData `WorkoutSession`s from HealthKit workouts the watch
    /// recorded but never delivered to iOS. The rich per-set payload is gone by this
    /// point, so we rebuild from the matched routine template as a best-effort and tag
    /// the session as recovered. Called when the user confirms recovery from the
    /// History banner. The placeholder is history-only and is marked provisional in
    /// the recovery ledger, so it never mutates a routine and a later rich payload
    /// atomically replaces it (the ingestion path keys off the shared external UUID).
    func recoverOrphanedWorkouts() async {
        let orphans = orphanedWatchWorkouts
        guard !orphans.isEmpty else { return }

        var existingHKIds: Set<UUID>
        do {
            existingHKIds = try workoutHistoryCorrelation.healthKitWorkoutIDs()
        } catch {
            print("Watch workout recovery skipped: committed history unavailable — \(error.localizedDescription)")
            return
        }
        var didInsert = false
        var savedPlaceholders: [(external: UUID, sessionId: UUID)] = []

        for orphan in orphans where !existingHKIds.contains(orphan.id) {
            let routine = matchRoutine(for: orphan)

            // For an unmatched workout the session stays routine-less — no
            // phantom routine is persisted; the denormalized routineName
            // drives display. A FRESH session id (distinct from any watch id)
            // is what lets a later rich payload be detected as a replacement.
            let session = WorkoutSession(routine: routine)
            session.id = UUID()
            session.healthKitWorkoutId = orphan.id
            session.startTime = orphan.startDate
            session.endTime = orphan.endDate
            session.routineName = orphan.routineName
            session.notes = "history.pendingSync.recoveredNote".localized

            // Reconstruct exercises/sets from the matched routine template (planned
            // values used as actuals — we don't have the real per-set data).
            if let routine {
                for routineExercise in routine.routineExercisesList.sorted(by: { $0.order < $1.order }) {
                    let workoutExercise = WorkoutExercise(
                        exerciseName: routineExercise.exercise?.name ?? orphan.routineName,
                        muscleGroups: [routineExercise.exercise?.primaryMuscleGroup ?? "General"],
                        order: routineExercise.order,
                        exerciseId: routineExercise.exercise?.id,
                        routineExerciseId: routineExercise.id,
                        loadBehavior: routineExercise.exercise?.loadBehavior ?? .resistance
                    )
                    workoutExercise.workoutSession = session
                    workoutExercise.supersetId = routineExercise.supersetId
                    workoutExercise.supersetOrder = routineExercise.supersetOrder

                    for exerciseSet in routineExercise.setsList.sorted(by: { $0.order < $1.order }) {
                        let workoutSet = WorkoutSet(
                            plannedReps: exerciseSet.reps,
                            actualReps: exerciseSet.reps,
                            plannedWeight: exerciseSet.weight,
                            actualWeight: exerciseSet.weight,
                            restTime: exerciseSet.restTime,
                            order: exerciseSet.order
                        )
                        workoutSet.isCompleted = true
                        workoutSet.completedAt = orphan.endDate
                        workoutSet.workoutExercise = workoutExercise
                        workoutExercise.sets?.append(workoutSet)
                        workoutSessionRepository.insert(workoutSet)
                    }

                    session.workoutExercises?.append(workoutExercise)
                    workoutSessionRepository.insert(workoutExercise)
                }
            }

            workoutSessionRepository.insert(session)
            existingHKIds.insert(orphan.id)
            savedPlaceholders.append((orphan.id, session.id))
            didInsert = true
        }

        guard didInsert else { return }

        do {
            try workoutSessionRepository.save()
        } catch {
            print("Error saving recovered workouts: \(error)")
            return
        }

        // Mark each placeholder provisional in the ledger (records its session
        // id for later replacement detection); this also re-reconciles and
        // republishes, dropping the now-resolved candidates from the banner.
        for placeholder in savedPlaceholders {
            recovery?.markPlaceholderSaved(externalUUID: placeholder.external, sessionId: placeholder.sessionId)
        }

        fetchWorkoutHistory()
        orphanedWatchWorkouts = recovery?.recoverableWorkouts ?? []
        NotificationCenter.default.post(name: .workoutHistoryDidChange, object: nil)
    }

    /// Finds the routine a recovered HealthKit workout belongs to: an exact id match
    /// when the workout embedded `RoutineId` metadata, otherwise a name match.
    private func matchRoutine(for orphan: OrphanedWorkout) -> Routine? {
        if let routineId = orphan.routineId, let match = routineRepository.fetch(id: routineId) {
            return match
        }
        return routineRepository.fetch(name: orphan.routineName)
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

    // MARK: - Live Activity Management

    private func cleanupStaleActivities() {
        Task {
            for activity in Activity<RestTimerAttributes>.activities {
                // Check if timer has expired
                if activity.content.state.timerRange.upperBound < now() {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    private func startRestTimerLiveActivity(
        startDate: Date,
        deadline: Date
    ) {
        // Check if Live Activities are enabled
        let authInfo = ActivityAuthorizationInfo()
        print("Live Activity Authorization Status: \(authInfo.areActivitiesEnabled)")
        print("Live Activity Frequent Updates Enabled: \(authInfo.frequentPushesEnabled)")

        guard authInfo.areActivitiesEnabled else {
            print("⚠️ Live Activities not enabled by user")
            return
        }

        let timerRange = startDate...deadline

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
            let content = ActivityContent(
                state: initialContentState,
                staleDate: deadline
            )
            let activity = try Activity<RestTimerAttributes>.request(
                attributes: attributes,
                content: content,
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

            let content = ActivityContent(
                state: finalState,
                staleDate: nil
            )
            await activity.end(
                content,
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
        if let restStart = restTimerStartTime,
           let deadline = restTimerDeadline,
           let timerID = restTimerID,
           restDuration > 0 {
            UserDefaults.standard.set(restStart, forKey: "restTimerStartTime")
            UserDefaults.standard.set(restDuration, forKey: "restDuration")
            UserDefaults.standard.set(deadline, forKey: "restTimerDeadline")
            UserDefaults.standard.set(timerID.uuidString, forKey: "restTimerID")
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
            let persistedDeadline = UserDefaults.standard.object(
                forKey: "restTimerDeadline"
            ) as? Date
            let deadline = persistedDeadline ?? restStart.addingTimeInterval(duration)
            let persistedID = UserDefaults.standard.string(forKey: "restTimerID")
                .flatMap(UUID.init(uuidString:))
            let timerID = persistedID ?? UUID()
            let remaining = ceil(max(0, deadline.timeIntervalSince(now())))

            if remaining > 0 {
                // Timer still running
                restTimeRemaining = remaining
                isRestTimerActive = true
                restTimerStartTime = restStart
                restTimerDeadline = deadline
                restTimerID = timerID
                restDuration = duration

                // Restart Live Activity if not already active
                if currentRestActivity == nil {
                    startRestTimerLiveActivity(
                        startDate: restStart,
                        deadline: deadline
                    )
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
        UserDefaults.standard.removeObject(forKey: "restTimerDeadline")
        UserDefaults.standard.removeObject(forKey: "restTimerID")
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

        workoutSessionRepository.insert(session)
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
            workoutSessionRepository.delete(session)
            save()
        }

        currentSession = nil
        elapsedTime = 0
        currentExerciseIndex = 0
        currentSetIndex = 0
        healthKitSyncStatus = .idle
        overloadSnapshots.removeAll()
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
            updateRoutineTemplate(session: session, reconcileExerciseMembership: true)
        }

        save()
        fetchWorkoutHistory()

        // Save to HealthKit
        saveWorkoutToHealthKit(session: session)

        currentSession = nil
        elapsedTime = 0
        overloadSnapshots.removeAll()
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

    func updateBodyWeight(_ bodyWeightKg: Double?) {
        guard let session = currentSession else { return }
        objectWillChange.send()
        session.bodyWeightKg = bodyWeightKg
        save()
    }

    func updateRestTimeForExercise(_ workoutExercise: WorkoutExercise, restTime: TimeInterval) {
        objectWillChange.send()
        for set in workoutExercise.setsList {
            set.restTime = restTime
        }
        save()
    }

    /// Apply progressive overload: updates both the active workout sets (for immediate UI feedback)
    /// and the routine template (for future workouts).
    /// plannedWeight/plannedReps are preserved as the actual pre-overload performance for history/comparison.
    func applyProgressiveOverload(for workoutExercise: WorkoutExercise, weightIncrement: Double) {
        let minReps = workoutExercise.targetRepMin ?? 1

        objectWillChange.send()

        var workoutSetValues: [UUID: OverloadSnapshot.SetValues] = [:]
        var templateSetValues: [UUID: OverloadSnapshot.TemplateValues] = [:]

        // Snapshot current actual performance into planned values (for comparison/history accuracy),
        // then update actual values with overloaded values for UI display
        let workoutSets = workoutExercise.setsList
        let increase = ProgressiveOverloadService.applyIncrease(
            toWeights: workoutSets.map(\.actualWeight),
            increment: weightIncrement,
            targetRepMin: minReps,
            loadBehavior: workoutExercise.loadBehavior
        )
        for (set, newWeight) in zip(workoutSets, increase.weights) {
            workoutSetValues[set.id] = OverloadSnapshot.SetValues(
                plannedReps: set.plannedReps, actualReps: set.actualReps,
                plannedWeight: set.plannedWeight, actualWeight: set.actualWeight
            )
            set.plannedReps = set.actualReps
            set.plannedWeight = set.actualWeight
            set.actualWeight = newWeight
            set.actualReps = increase.reps
        }

        // Mark that progressive overload was applied
        workoutExercise.progressiveOverloadApplied = true

        // Update routine template (so it persists for future workouts). A swapped
        // exercise writes into the performed alternative's own set scheme — the
        // primary slot's sets stay untouched.
        if workoutExercise.wasSwapped {
            if let alternative = alternativeEntry(for: workoutExercise) {
                let templateSets = alternative.setsList
                let templateIncrease = ProgressiveOverloadService.applyIncrease(
                    toWeights: templateSets.map(\.weight),
                    increment: weightIncrement,
                    targetRepMin: minReps,
                    loadBehavior: workoutExercise.loadBehavior
                )
                for (set, newWeight) in zip(templateSets, templateIncrease.weights) {
                    templateSetValues[set.id] = OverloadSnapshot.TemplateValues(reps: set.reps, weight: set.weight)
                    set.weight = newWeight
                    set.reps = templateIncrease.reps
                }
            }
        } else if let routineExercise = routineExercise(for: workoutExercise) {
            let templateSets = routineExercise.setsList
            let templateIncrease = ProgressiveOverloadService.applyIncrease(
                toWeights: templateSets.map(\.weight),
                increment: weightIncrement,
                targetRepMin: minReps,
                loadBehavior: workoutExercise.loadBehavior
            )
            for (set, newWeight) in zip(templateSets, templateIncrease.weights) {
                templateSetValues[set.id] = OverloadSnapshot.TemplateValues(reps: set.reps, weight: set.weight)
                set.weight = newWeight
                set.reps = templateIncrease.reps
            }
        }

        overloadSnapshots[workoutExercise.id] = OverloadSnapshot(
            workoutSetValues: workoutSetValues,
            templateSetValues: templateSetValues
        )

        save()
    }

    /// Resolves the routine-template slot a workout exercise originated from,
    /// swapped or not: by the stable routineExerciseId first, then via the
    /// originally-planned exercise (mirroring updateRoutineTemplate).
    func routineExercise(for workoutExercise: WorkoutExercise) -> RoutineExercise? {
        guard let routine = currentSession?.routine else { return nil }
        return routineExercise(in: routine, for: workoutExercise)
    }

    /// Same slot resolution against an explicit routine — lets a completed
    /// (historical) session reach its still-live template via `session.routine`,
    /// not just the active `currentSession`.
    func routineExercise(in routine: Routine, for workoutExercise: WorkoutExercise) -> RoutineExercise? {
        if let slotId = workoutExercise.routineExerciseId,
           let slot = routine.routineExercisesList.first(where: { $0.id == slotId }) {
            return slot
        }
        let originId = workoutExercise.plannedExerciseId ?? workoutExercise.exerciseId
        let originName = workoutExercise.plannedExerciseName ?? workoutExercise.exerciseName
        return routine.routineExercisesList.first { candidate in
            if let originId, let candidateId = candidate.exercise?.id {
                return candidateId == originId
            }
            return candidate.exercise?.name == originName
        }
    }

    /// The alternative entry whose set scheme a swapped exercise's values
    /// belong to (the primary's sets stay untouched, as in updateRoutineTemplate).
    private func alternativeEntry(for workoutExercise: WorkoutExercise) -> RoutineExerciseAlternative? {
        guard let routine = currentSession?.routine else { return nil }
        return alternativeEntry(in: routine, for: workoutExercise)
    }

    private func alternativeEntry(in routine: Routine, for workoutExercise: WorkoutExercise) -> RoutineExerciseAlternative? {
        guard workoutExercise.wasSwapped,
              let slot = routineExercise(in: routine, for: workoutExercise) else { return nil }
        return slot.alternativesList.first { $0.exercise?.id == workoutExercise.exerciseId }
    }

    /// The live library exercise that was actually performed — the alternative's
    /// exercise for swapped workout exercises. For display surfaces.
    func performedExercise(for workoutExercise: WorkoutExercise) -> Exercise? {
        if workoutExercise.wasSwapped {
            return alternativeEntry(for: workoutExercise)?.exercise
        }
        return routineExercise(for: workoutExercise)?.exercise
    }

    /// Exercises the completion screen offers an overload suggestion for: rep
    /// goal maxed AND either already applied or a template target to persist to
    /// (the slot's sets, or the alternative's set scheme for swaps).
    var overloadSuggestionExercises: [WorkoutExercise] {
        (currentSession?.workoutExercisesList ?? [])
            .filter { $0.allCompletedSetsAtUpperLimit }
            .filter { $0.progressiveOverloadApplied || hasOverloadTemplateTarget(for: $0) }
            .sorted { $0.order < $1.order }
    }

    private func hasOverloadTemplateTarget(for workoutExercise: WorkoutExercise) -> Bool {
        workoutExercise.wasSwapped
            ? alternativeEntry(for: workoutExercise) != nil
            : routineExercise(for: workoutExercise) != nil
    }

    func canUndoProgressiveOverload(for workoutExercise: WorkoutExercise) -> Bool {
        overloadSnapshots[workoutExercise.id] != nil
    }

    /// Reverts an overload applied during this session: restores the sets'
    /// pre-apply planned/actual values and the routine template's set scheme.
    func undoProgressiveOverload(for workoutExercise: WorkoutExercise) {
        guard let snapshot = overloadSnapshots.removeValue(forKey: workoutExercise.id) else { return }

        objectWillChange.send()

        for set in workoutExercise.setsList {
            guard let values = snapshot.workoutSetValues[set.id] else { continue }
            set.plannedReps = values.plannedReps
            set.actualReps = values.actualReps
            set.plannedWeight = values.plannedWeight
            set.actualWeight = values.actualWeight
        }
        workoutExercise.progressiveOverloadApplied = false

        if workoutExercise.wasSwapped {
            if let alternative = alternativeEntry(for: workoutExercise) {
                for set in alternative.setsList {
                    guard let values = snapshot.templateSetValues[set.id] else { continue }
                    set.reps = values.reps
                    set.weight = values.weight
                }
            }
        } else if let routineExercise = routineExercise(for: workoutExercise) {
            for set in routineExercise.setsList {
                guard let values = snapshot.templateSetValues[set.id] else { continue }
                set.reps = values.reps
                set.weight = values.weight
            }
        }

        save()
    }

    // MARK: - Progressive overload from history (after-the-fact)

    /// The live library exercise actually performed, resolved from a completed
    /// (historical) session's still-live `routine`. Nil once the routine is gone.
    /// History surface — the active `currentSession` is irrelevant here.
    func performedExercise(in session: WorkoutSession, for workoutExercise: WorkoutExercise) -> Exercise? {
        guard let routine = session.routine else { return nil }
        if workoutExercise.wasSwapped {
            return alternativeEntry(in: routine, for: workoutExercise)?.exercise
        }
        return routineExercise(in: routine, for: workoutExercise)?.exercise
    }

    /// Whether an increase applied from this completed session can still reach a
    /// live routine-template target (the slot's own sets, or the alternative's
    /// set scheme for swaps). False if the routine/exercise was edited or deleted.
    func hasResolvableOverloadTemplate(from session: WorkoutSession, for workoutExercise: WorkoutExercise) -> Bool {
        overloadTemplateSetCount(from: session, for: workoutExercise) > 0
    }

    private func overloadTemplateSetCount(from session: WorkoutSession, for workoutExercise: WorkoutExercise) -> Int {
        guard let routine = session.routine else { return 0 }
        if workoutExercise.wasSwapped {
            return alternativeEntry(in: routine, for: workoutExercise)?.setsList.count ?? 0
        }
        return routineExercise(in: routine, for: workoutExercise)?.setsList.count ?? 0
    }

    /// Applies a weight increase to the LIVE routine template only, resolved from
    /// a completed (historical) session. The historical `WorkoutExercise`/
    /// `WorkoutSet` are never mutated — history is denormalized and immutable by
    /// design. Returns the new template weight, or nil (no-op) when the source
    /// routine or exercise no longer exists.
    @discardableResult
    func applyProgressiveOverloadFromHistory(
        from session: WorkoutSession,
        for workoutExercise: WorkoutExercise,
        weightIncrement: Double
    ) -> Double? {
        guard let routine = session.routine else { return nil }
        let minReps = workoutExercise.targetRepMin ?? 1

        objectWillChange.send()
        let newWeight: Double?
        if workoutExercise.wasSwapped {
            guard let alternative = alternativeEntry(in: routine, for: workoutExercise) else { return nil }
            newWeight = applyOverloadToTemplateSets(
                alternative.setsList, weightKey: \.weight, repsKey: \.reps,
                increment: weightIncrement, minReps: minReps, loadBehavior: workoutExercise.loadBehavior
            )
        } else {
            guard let slot = routineExercise(in: routine, for: workoutExercise) else { return nil }
            newWeight = applyOverloadToTemplateSets(
                slot.setsList, weightKey: \.weight, repsKey: \.reps,
                increment: weightIncrement, minReps: minReps, loadBehavior: workoutExercise.loadBehavior
            )
        }
        guard newWeight != nil else { return nil }
        save()
        return newWeight
    }

    /// Bumps a set of template sets in place via the shared overload service and
    /// returns the new (first) weight. Generic over the two template set types
    /// (`ExerciseSet`, `AlternativeExerciseSet`), which share `weight`/`reps`.
    private func applyOverloadToTemplateSets<S: AnyObject>(
        _ sets: [S],
        weightKey: ReferenceWritableKeyPath<S, Double>,
        repsKey: ReferenceWritableKeyPath<S, Int>,
        increment: Double,
        minReps: Int,
        loadBehavior: ExerciseLoadBehavior
    ) -> Double? {
        guard !sets.isEmpty else { return nil }
        let increase = ProgressiveOverloadService.applyIncrease(
            toWeights: sets.map { $0[keyPath: weightKey] },
            increment: increment,
            targetRepMin: minReps,
            loadBehavior: loadBehavior
        )
        for (set, newWeight) in zip(sets, increase.weights) {
            set[keyPath: weightKey] = newWeight
            set[keyPath: repsKey] = increase.reps
        }
        return increase.weights.first
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

        workoutSessionRepository.insert(newSet)
        save()
    }

    func addExerciseToWorkout(exercise: Exercise, configuredSets: [ExerciseSet]) {
        guard let session = currentSession else { return }

        objectWillChange.send()

        let workoutSets = configuredSets.enumerated().map { index, set in
            WorkoutSet(from: set, order: index)
        }

        // Determine the order for the new exercise
        let nextOrder = (session.workoutExercisesList.map(\.order).max() ?? -1) + 1

        // Create a workout exercise from the library exercise
        let workoutExercise = WorkoutExercise(
            exerciseName: exercise.name,
            muscleGroups: exercise.muscleGroups,
            order: nextOrder,
            exerciseId: exercise.id,
            loadBehavior: exercise.loadBehavior
        )
        workoutExercise.workoutSession = session

        for set in workoutSets {
            set.workoutExercise = workoutExercise
            workoutExercise.sets?.append(set)
        }

        session.workoutExercises?.append(workoutExercise)
        workoutSessionRepository.insert(workoutExercise)
        for set in workoutSets {
            workoutSessionRepository.insert(set)
        }
        save()
    }

    func removeSetFromExercise(_ set: WorkoutSet, from workoutExercise: WorkoutExercise) {
        guard currentSession != nil else { return }

        objectWillChange.send()

        if let index = workoutExercise.setsList.firstIndex(where: { $0.id == set.id }) {
            workoutExercise.sets?.remove(at: index)
            workoutSessionRepository.delete(set)
            save()
        }
    }

    // MARK: - Alternative Exercise Swapping

    /// A candidate the user can switch the current exercise to during a workout.
    struct SwapTarget: Identifiable {
        let id: UUID            // the target Exercise's id
        let exercise: Exercise
        let isOriginal: Bool    // true if this is the originally-planned exercise (revert option)
        let setScheme: String?  // compact scheme summary, e.g. "3×10 · 20kg"
    }

    /// Compact scheme summary for swap-picker rows, e.g. "3×10", "4×8–12 · 20kg".
    /// Delegates to the shared `RoutineMetricsService.setSchemeSummary` so the
    /// in-workout Swap picker and the routine browse sheet stay identical.
    private func setScheme(from sets: [(reps: Int, weight: Double)]) -> String? {
        RoutineMetricsService.setSchemeSummary(reps: sets.map(\.reps), weights: sets.map(\.weight))
    }

    /// Finds the routine exercise a workout exercise originated from, using the
    /// originally-planned exercise id (falls back to current id when not swapped).
    private func originRoutineExercise(for workoutExercise: WorkoutExercise) -> RoutineExercise? {
        guard let routine = currentSession?.routine else { return nil }
        if let routineExerciseId = workoutExercise.routineExerciseId,
           let exactSlot = routine.routineExercisesList.first(where: { $0.id == routineExerciseId }) {
            return exactSlot
        }
        let originId = workoutExercise.plannedExerciseId ?? workoutExercise.exerciseId
        return routine.routineExercisesList.first { $0.exercise?.id == originId }
    }

    /// Swap targets available for a workout exercise: its alternatives plus the
    /// originally-planned exercise (when currently swapped), excluding the active one.
    /// Returns an empty array if the exercise has no alternatives configured.
    func swapTargets(for workoutExercise: WorkoutExercise) -> [SwapTarget] {
        guard let origin = originRoutineExercise(for: workoutExercise), origin.hasAlternatives else {
            return []
        }
        var targets: [SwapTarget] = []
        // The originally-planned exercise (acts as the revert option once swapped)
        if let primary = origin.exercise {
            let scheme = setScheme(from: origin.setsList.sorted { $0.order < $1.order }
                .map { ($0.reps, $0.weight) })
            targets.append(SwapTarget(id: primary.id, exercise: primary, isOriginal: true, setScheme: scheme))
        }
        // Each configured alternative
        for alternative in origin.alternativesList {
            if let exercise = alternative.exercise {
                let scheme = setScheme(from: alternative.setsList.map { ($0.reps, $0.weight) })
                targets.append(SwapTarget(id: exercise.id, exercise: exercise, isOriginal: false, setScheme: scheme))
            }
        }
        // Exclude whatever is currently active
        return targets.filter { $0.id != workoutExercise.exerciseId }
    }

    /// True if the exercise can still be swapped (no set completed yet and targets exist).
    func canSwap(_ workoutExercise: WorkoutExercise) -> Bool {
        workoutExercise.completedSetsCount == 0 && !swapTargets(for: workoutExercise).isEmpty
    }

    /// Swaps a workout exercise for one of its alternatives (or back to the original).
    /// Only allowed before any set is completed; rebuilds the sets from the target's own scheme.
    func swapExercise(_ workoutExercise: WorkoutExercise, to target: SwapTarget) {
        guard workoutExercise.completedSetsCount == 0 else { return }
        guard let origin = originRoutineExercise(for: workoutExercise) else { return }

        objectWillChange.send()

        // Record the originally-planned exercise on the first swap only.
        if workoutExercise.plannedExerciseId == nil {
            workoutExercise.plannedExerciseId = workoutExercise.exerciseId
            workoutExercise.plannedExerciseName = workoutExercise.exerciseName
        }

        // Update identity to the actually-performed exercise.
        workoutExercise.exerciseId = target.exercise.id
        workoutExercise.exerciseName = target.exercise.name
        workoutExercise.muscleGroups = target.exercise.muscleGroups
        workoutExercise.loadBehavior = target.exercise.loadBehavior

        // Reverting to the originally-planned exercise clears the swap metadata.
        if target.isOriginal {
            workoutExercise.plannedExerciseId = nil
            workoutExercise.plannedExerciseName = nil
        }

        // Rebuild the sets from the chosen target's own set scheme, and adopt the
        // target's own rep-range goal (the original's on revert, else the
        // alternative's own — each alternative can define its own range).
        let templateSets: [(reps: Int, weight: Double, rest: TimeInterval)]
        if target.isOriginal {
            templateSets = origin.setsList.sorted(by: { $0.order < $1.order })
                .map { ($0.reps, $0.weight, $0.restTime) }
            workoutExercise.targetRepMin = origin.targetRepMin
            workoutExercise.targetRepMax = origin.targetRepMax
        } else if let alternative = origin.alternativesList.first(where: { $0.exercise?.id == target.exercise.id }) {
            templateSets = alternative.setsList.map { ($0.reps, $0.weight, $0.restTime) }
            workoutExercise.targetRepMin = alternative.targetRepMin
            workoutExercise.targetRepMax = alternative.targetRepMax
        } else {
            templateSets = []
            workoutExercise.targetRepMin = nil
            workoutExercise.targetRepMax = nil
        }

        // Replace existing sets (none completed, safe to discard).
        for set in workoutExercise.setsList {
            workoutSessionRepository.delete(set)
        }
        let newSets: [WorkoutSet] = templateSets.enumerated().map { index, template in
            let set = WorkoutSet(
                plannedReps: template.reps,
                actualReps: template.reps,
                plannedWeight: template.weight,
                actualWeight: template.weight,
                restTime: template.rest,
                order: index
            )
            set.workoutExercise = workoutExercise
            return set
        }
        workoutExercise.sets = newSets

        save()
    }

    func removeExerciseFromWorkout(_ workoutExercise: WorkoutExercise) {
        guard let session = currentSession else { return }

        objectWillChange.send()

        // Remove all sets associated with this exercise
        for set in workoutExercise.setsList {
            workoutSessionRepository.delete(set)
        }

        // Remove the exercise from the session
        if let index = session.workoutExercisesList.firstIndex(where: { $0.id == workoutExercise.id }) {
            session.workoutExercises?.remove(at: index)
        }

        workoutSessionRepository.delete(workoutExercise)
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

        let startDate = now()
        let deadline = startDate.addingTimeInterval(duration)
        let timerID = UUID()

        restTimeRemaining = duration
        isRestTimerActive = true
        restTimerReminderOutcome = nil
        hasPlayedRestCountdownHaptic = false

        // The identity and absolute deadline are authoritative across all timer surfaces.
        restTimerStartTime = startDate
        restTimerDeadline = deadline
        restTimerID = timerID
        restDuration = duration
        saveTimerState()

        restTimerReminderTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await restTimerReminders.scheduleReminder(
                id: timerID,
                deadline: deadline
            )
            guard !Task.isCancelled, restTimerID == timerID else { return }
            restTimerReminderOutcome = outcome
        }

        // Start Live Activity for Lock Screen display
        startRestTimerLiveActivity(
            startDate: startDate,
            deadline: deadline
        )

        // Start UI update timer
        startRestTimerUI()
    }

    private func startRestTimerUI() {
        restTimer?.invalidate()

        let newRestTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let deadline = self.restTimerDeadline else { return }

                let previousRemaining = self.restTimeRemaining
                let remaining = ceil(max(0, deadline.timeIntervalSince(self.now())))
                if remaining > 0 {
                    self.restTimeRemaining = remaining

                    if !self.hasPlayedRestCountdownHaptic,
                       previousRemaining > 3,
                       remaining <= 3 {
                        self.hasPlayedRestCountdownHaptic = true
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
        let timerID = restTimerID
        restTimer?.invalidate()
        restTimer = nil
        restTimerReminderTask?.cancel()
        restTimerReminderTask = nil
        isRestTimerActive = false
        restTimeRemaining = 0
        restTimerReminderOutcome = nil

        // Clear rest timer state
        restTimerStartTime = nil
        restTimerDeadline = nil
        restTimerID = nil
        restDuration = 0
        hasPlayedRestCountdownHaptic = false

        // Cancel any pending notification
        if let timerID {
            restTimerReminders.cancelReminder(id: timerID)
        }

        // End Live Activity
        endRestTimerLiveActivity()

        // Clear saved state
        UserDefaults.standard.removeObject(forKey: "restTimerStartTime")
        UserDefaults.standard.removeObject(forKey: "restDuration")
        UserDefaults.standard.removeObject(forKey: "restTimerDeadline")
        UserDefaults.standard.removeObject(forKey: "restTimerID")
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

    // MARK: - Editing Past Workouts

    /// Persists user edits to a completed (past) workout. The edit screen passes value-type
    /// drafts so that cancelling never mutates the `@Model` objects. Mirrors the active-workout
    /// completion flow: optionally pushes the corrected values back to the routine template and
    /// triggers a watch routine sync so the next workout (iOS + watch) starts from them.
    func saveEditedWorkout(
        _ session: WorkoutSession,
        exerciseDrafts: [WorkoutExerciseDraft],
        updateTemplate: Bool
    ) {
        objectWillChange.send()

        for draft in exerciseDrafts {
            guard let workoutExercise = session.workoutExercisesList.first(where: { $0.id == draft.id }) else {
                continue
            }

            // 1. Delete sets the user removed in the editor
            let keptIds = Set(draft.sets.compactMap(\.existingSetId))
            for set in workoutExercise.setsList where !keptIds.contains(set.id) {
                workoutExercise.sets?.removeAll { $0.id == set.id }
                workoutSessionRepository.delete(set)
            }

            // 2. Update kept sets and insert newly added ones, in draft order
            let completedAt = session.endTime ?? Date()
            for (index, setDraft) in draft.sets.enumerated() {
                if let existingId = setDraft.existingSetId,
                   let set = workoutExercise.setsList.first(where: { $0.id == existingId }) {
                    // Write back to whichever field is displayed (planned values are shown
                    // when progressive overload was applied — see WorkoutDetailExerciseBlock).
                    if draft.usePlanned {
                        set.plannedReps = setDraft.reps
                        set.plannedWeight = setDraft.weight
                    } else {
                        set.actualReps = setDraft.reps
                        set.actualWeight = setDraft.weight
                    }
                    set.restTime = setDraft.restTime
                    set.isCompleted = setDraft.isCompleted
                    set.completedAt = setDraft.isCompleted ? (set.completedAt ?? completedAt) : nil
                    set.order = index
                } else {
                    let newSet = WorkoutSet(
                        plannedReps: setDraft.reps,
                        actualReps: setDraft.reps,
                        plannedWeight: setDraft.weight,
                        actualWeight: setDraft.weight,
                        restTime: setDraft.restTime,
                        order: index
                    )
                    newSet.isCompleted = setDraft.isCompleted
                    newSet.completedAt = setDraft.isCompleted ? completedAt : nil
                    newSet.workoutExercise = workoutExercise
                    workoutExercise.sets?.append(newSet)
                    workoutSessionRepository.insert(newSet)
                }
            }
        }

        session.didUpdateTemplate = updateTemplate

        if updateTemplate {
            updateRoutineTemplate(session: session, reconcileExerciseMembership: false) // also calls save()
        } else {
            save()
        }

        fetchWorkoutHistory()

        // The cached AI recap/analysis for this session reflect the old values — drop them.
        aiCoachCache.invalidatePostWorkout(workoutId: session.id)
        aiCoachCache.invalidateWorkoutAnalysis(workoutId: session.id)

        // Propagate template changes to the watch (RoutinesViewModel re-fetches and syncs).
        if updateTemplate {
            NotificationCenter.default.post(name: .routineTemplateDidChange, object: nil)
        }
    }

    // MARK: - Template Update

    /// Pushes a session's performed values back onto its routine template. Active-workout
    /// completion also reconciles exercise membership; historical edits deliberately do not,
    /// because a routine may have changed since that older workout was recorded.
    private func updateRoutineTemplate(
        session: WorkoutSession,
        reconcileExerciseMembership: Bool
    ) {
        guard let routine = session.routine else { return }

        let routineExercises = routine.routineExercisesList.sorted { $0.order < $1.order }
        let workoutExercises = session.workoutExercisesList.sorted { $0.order < $1.order }
        let allowsLegacyFallback = !reconcileExerciseMembership
            && workoutExercises.allSatisfy { $0.routineExerciseId == nil }
        var claimedRoutineExerciseIds: Set<UUID> = []
        let matches: [(workout: WorkoutExercise, routine: RoutineExercise?)] = workoutExercises.map {
            workoutExercise in
            let match = matchingRoutineExercise(
                for: workoutExercise,
                in: routineExercises,
                excluding: claimedRoutineExerciseIds,
                allowsLegacyFallback: allowsLegacyFallback
            )
            if let match {
                claimedRoutineExerciseIds.insert(match.id)
            }
            return (workoutExercise, match)
        }

        if reconcileExerciseMembership {
            for removedExercise in routineExercises where !claimedRoutineExerciseIds.contains(removedExercise.id) {
                routine.routineExercises?.removeAll { $0.id == removedExercise.id }
                for set in removedExercise.setsList {
                    removedExercise.sets?.removeAll { $0.id == set.id }
                    routineRepository.delete(set)
                }
                routineRepository.delete(removedExercise)
            }

            for (order, routineExercise) in routine.routineExercisesList
                .sorted(by: { $0.order < $1.order })
                .enumerated() {
                routineExercise.order = order
            }
        }

        for match in matches {
            guard let routineExercise = match.routine else {
                if reconcileExerciseMembership {
                    appendRoutineExercise(from: match.workout, to: routine)
                }
                continue
            }

            // Swapped exercises write their values back into the performed
            // alternative's own set scheme — the primary's sets stay untouched.
            if match.workout.wasSwapped {
                if let alternative = routineExercise.alternativesList.first(where: { $0.exercise?.id == match.workout.exerciseId }) {
                    updateAlternativeTemplateSets(alternative, from: match.workout)
                }
                continue
            }

            updatePrimaryTemplateSets(routineExercise, from: match.workout)
        }

        routine.updatedAt = Date()
        save()
    }

    private func matchingRoutineExercise(
        for workoutExercise: WorkoutExercise,
        in candidates: [RoutineExercise],
        excluding claimedIds: Set<UUID>,
        allowsLegacyFallback: Bool
    ) -> RoutineExercise? {
        if let slotId = workoutExercise.routineExerciseId {
            return candidates.first { $0.id == slotId && !claimedIds.contains($0.id) }
        }

        guard allowsLegacyFallback else { return nil }
        let originId = workoutExercise.plannedExerciseId ?? workoutExercise.exerciseId
        let originName = workoutExercise.plannedExerciseName ?? workoutExercise.exerciseName
        return candidates.first { candidate in
            guard !claimedIds.contains(candidate.id) else { return false }
            if let originId, let candidateId = candidate.exercise?.id {
                return candidateId == originId
            }
            return candidate.exercise?.name == originName
        }
    }

    private func appendRoutineExercise(from workoutExercise: WorkoutExercise, to routine: Routine) {
        guard let exerciseId = workoutExercise.exerciseId,
              let exercise = exerciseRepository.fetch(id: exerciseId) else { return }

        let routineExercise = RoutineExercise(order: routine.routineExercisesList.count)
        routineRepository.insert(routineExercise)
        routineExercise.exercise = exercise
        routineExercise.routine = routine
        if !routine.routineExercisesList.contains(where: { $0.id == routineExercise.id }) {
            routine.routineExercises?.append(routineExercise)
        }

        for (order, workoutSet) in workoutExercise.setsList
            .sorted(by: { $0.order < $1.order })
            .enumerated() {
            let routineSet = ExerciseSet(
                reps: workoutSet.actualReps,
                weight: workoutSet.actualWeight,
                restTime: workoutSet.restTime,
                order: order
            )
            routineRepository.insert(routineSet)
            routineSet.routineExercise = routineExercise
            if !routineExercise.setsList.contains(where: { $0.id == routineSet.id }) {
                routineExercise.sets?.append(routineSet)
            }
        }

        workoutExercise.routineExerciseId = routineExercise.id
    }

    private func updatePrimaryTemplateSets(
        _ routineExercise: RoutineExercise,
        from workoutExercise: WorkoutExercise
    ) {
        let exerciseRestTime = workoutExercise.setsList.first?.restTime ?? 60.0
        let workoutSets = workoutExercise.setsList.sorted(by: { $0.order < $1.order })
        var routineSets = routineExercise.setsList.sorted(by: { $0.order < $1.order })

        if routineSets.count > workoutSets.count {
            for routineSet in routineSets[workoutSets.count...] {
                routineExercise.sets?.removeAll { $0.id == routineSet.id }
                routineRepository.delete(routineSet)
            }
            routineSets = Array(routineSets[..<workoutSets.count])
        }

        for (index, routineSet) in routineSets.enumerated() {
            routineSet.order = index
            routineSet.restTime = exerciseRestTime
            let workoutSet = workoutSets[index]
            if workoutSet.isCompleted {
                routineSet.reps = workoutSet.actualReps
                routineSet.weight = workoutSet.actualWeight
            }
        }

        if workoutSets.count > routineSets.count {
            for index in routineSets.count..<workoutSets.count {
                let workoutSet = workoutSets[index]
                let newRoutineSet = ExerciseSet(
                    reps: workoutSet.actualReps,
                    weight: workoutSet.actualWeight,
                    restTime: exerciseRestTime,
                    order: index
                )
                routineRepository.insert(newRoutineSet)
                newRoutineSet.routineExercise = routineExercise
                if !routineExercise.setsList.contains(where: { $0.id == newRoutineSet.id }) {
                    routineExercise.sets?.append(newRoutineSet)
                }
            }
        }
    }

    /// Mirrors the primary-set template update for a performed alternative:
    /// reps/weight from completed sets, rest time from the exercise, and the
    /// alternative's set count reconciled to the session's.
    private func updateAlternativeTemplateSets(_ alternative: RoutineExerciseAlternative, from workoutExercise: WorkoutExercise) {
        let exerciseRestTime = workoutExercise.setsList.first?.restTime ?? 60.0
        let workoutSets = workoutExercise.setsList.sorted(by: { $0.order < $1.order })
        var alternativeSets = alternative.setsList

        // Remove surplus template sets beyond the session's set count
        if alternativeSets.count > workoutSets.count {
            for alternativeSet in alternativeSets[workoutSets.count...] {
                alternative.sets?.removeAll { $0.id == alternativeSet.id }
                routineRepository.delete(alternativeSet)
            }
            alternativeSets = Array(alternativeSets[..<workoutSets.count])
        }

        // Update existing template sets in order
        for (index, alternativeSet) in alternativeSets.enumerated() {
            alternativeSet.order = index
            alternativeSet.restTime = exerciseRestTime
            let workoutSet = workoutSets[index]
            if workoutSet.isCompleted {
                alternativeSet.reps = workoutSet.actualReps
                alternativeSet.weight = workoutSet.actualWeight
            }
        }

        // Append new template sets for extra session sets
        if workoutSets.count > alternativeSets.count {
            for index in alternativeSets.count..<workoutSets.count {
                let workoutSet = workoutSets[index]
                let newSet = AlternativeExerciseSet(
                    reps: workoutSet.actualReps,
                    weight: workoutSet.actualWeight,
                    restTime: exerciseRestTime,
                    order: index
                )
                newSet.alternative = alternative
                if alternative.sets == nil { alternative.sets = [] }
                alternative.sets?.append(newSet)
            }
        }
    }

    // MARK: - History

    func fetchWorkoutHistory() {
        workoutHistory = workoutSessionRepository.fetchAll()
    }

    func deleteWorkout(_ session: WorkoutSession) {
        workoutSessionRepository.delete(session)
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
            try workoutSessionRepository.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }

    deinit {
        timer?.invalidate()
        restTimer?.invalidate()
        restTimerReminderTask?.cancel()
        if let recoverableWorkoutsObserver {
            NotificationCenter.default.removeObserver(recoverableWorkoutsObserver)
        }
    }
}
