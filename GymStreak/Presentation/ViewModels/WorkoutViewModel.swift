import Foundation
import SwiftUI
import Combine
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
    /// Bumped whenever persisted data relevant to History changes. The History screen uses this as
    /// an invalidation token for its actor-owned read model; it deliberately does not retain or
    /// synchronously fetch the entire SwiftData history on MainActor.
    @Published private(set) var historyVersion = 0
    /// Setting or clearing this *is* "a workout is running", so the app-wide
    /// flag Rule 3 reads is kept in step here rather than at the three call
    /// sites that start, finish and discard a session.
    @Published var currentSession: WorkoutSession? {
        didSet {
            // Both instances write the one shared flag, so a nil-to-nil write on
            // the instance that owns no session must not clear the other's.
            guard currentSession != nil || oldValue != nil else { return }
            activeWorkout?.setWorkoutActive(currentSession != nil)
        }
    }
    @Published var elapsedTime: TimeInterval = 0
    @Published var currentExerciseIndex: Int = 0
    @Published var currentSetIndex: Int = 0
    @Published var isRestTimerActive = false
    @Published var restTimeRemaining: TimeInterval = 0
    @Published var restDuration: TimeInterval = 0
    @Published private(set) var restTimerReminderOutcome: RestTimerReminderOutcome?
    @Published var showingWorkoutCompletePrompt = false
    /// HealthKit-saved workouts (from this device's GymStreak iOS or watch app)
    /// that have no matching `WorkoutSession` in SwiftData. Populated by the
    /// reconciler safety-net layer of the watch sync pipeline.
    @Published var orphanedWatchWorkouts: [OrphanedWorkout] = []

    // HealthKit integration
    @Published var healthKitSyncEnabled = true
    @Published var healthKitSyncStatus: HealthKitSyncStatus = .idle
    @Published var showHealthKitAuthPrompt = false
    /// Set when a requested Apple Health delete failed for a reason other than
    /// "already gone". Purely informational — the local delete is already
    /// committed — and surfaced without blocking the user.
    @Published var healthKitDeleteFailed = false

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
    private let watchSync: WatchSyncServicing
    private let workoutHistoryCorrelation: WorkoutHistoryCorrelationProviding
    private let restTimerReminders: RestTimerReminderScheduling
    private let restTimerLiveActivity: RestTimerLiveActivityPresenting
    /// The template-writeback half of "Update routine" (audit P1.5). Bound to the
    /// same main context as the repositories above, so everything it changes
    /// commits in this ViewModel's own `save()` — the service never saves.
    private let routineTemplateSync: RoutineTemplateSyncService
    private let aiCoachCache: AICoachCaching
    private let now: () -> Date
    private var timer: Timer?
    private var restTimer: Timer?
    private var restTimerReminderTask: Task<Void, Never>?
    private var cloudSyncObserver: NSObjectProtocol?
    private var workoutHistoryObserver: NSObjectProtocol?
    private var historySourceDataObserver: NSObjectProtocol?

    // Date-based timer tracking for background persistence
    private var workoutStartTime: Date?
    private var restTimerStartTime: Date?
    private var restTimerDeadline: Date?
    private var restTimerID: UUID?
    private var hasPlayedRestCountdownHaptic = false

    // HealthKit workout manager
    let healthKitManager: HealthKitWorkoutServicing

    /// App-lifetime engine that owns incremental HealthKit discovery, the
    /// durable recovery ledger, and the conservative reconciler (ticket 09).
    /// The banner mirrors its `recoverableWorkouts`; nil in unit tests.
    private let recovery: WorkoutRecoveryCoordinating?
    private var recoverableWorkoutsObserver: NSObjectProtocol?

    /// The app-wide workout flag this ViewModel keeps up to date, so the paywall
    /// presenter can refuse to present inside a session (§8 Rule 3). Optional
    /// because unit-test instances have no app to report to.
    private let activeWorkout: (any ActiveWorkoutReporting)?

    /// §8 placement B's triggers — the third completed workout and the first
    /// automatic overload suggestion. Optional for the same reason
    /// `activeWorkout` is: unit-test instances have no app to report to.
    private let proactivePaywalls: ProactivePaywallCoordinator?

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
    /// workoutExercise.id → the new uniform template weight an applied increase
    /// produced, or nil for a nonuniform (pyramid/drop) scheme. The workout's
    /// own sets keep the performance, so the confirmed card reads the announced
    /// weight from here instead of off them.
    private var appliedOverloadWeights: [UUID: Double?] = [:]

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UI_TESTING")
    }

    // `aiCoachCache`'s default is resolved inside this @MainActor-isolated init body —
    // a `= AICoachCache.shared` default argument would be evaluated in a nonisolated
    // context (error under Swift 6 language mode).
    init(
        workoutSessionRepository: WorkoutSessionRepository,
        routineRepository: RoutineRepository,
        healthKitManager: HealthKitWorkoutServicing,
        watchSync: WatchSyncServicing,
        workoutHistoryCorrelation: WorkoutHistoryCorrelationProviding,
        restTimerReminders: RestTimerReminderScheduling,
        restTimerLiveActivity: RestTimerLiveActivityPresenting,
        routineTemplateSync: RoutineTemplateSyncService,
        recovery: WorkoutRecoveryCoordinating? = nil,
        activeWorkout: (any ActiveWorkoutReporting)? = nil,
        proactivePaywalls: ProactivePaywallCoordinator? = nil,
        aiCoachCache: AICoachCaching? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.workoutSessionRepository = workoutSessionRepository
        self.routineRepository = routineRepository
        self.healthKitManager = healthKitManager
        self.watchSync = watchSync
        self.workoutHistoryCorrelation = workoutHistoryCorrelation
        self.restTimerReminders = restTimerReminders
        self.restTimerLiveActivity = restTimerLiveActivity
        self.routineTemplateSync = routineTemplateSync
        self.recovery = recovery
        self.activeWorkout = activeWorkout
        self.proactivePaywalls = proactivePaywalls
        self.aiCoachCache = aiCoachCache ?? AICoachCache.shared
        self.now = now
        restTimerLiveActivity.dismissExpiredActivities()
        loadHealthKitPreferences()
        healthKitManager.checkAuthorizationStatus()
        observeCloudKitChanges()
        observeWorkoutHistoryChanges()
        observeHistorySourceDataChanges()
        observeRecoverableWorkouts()
    }

    private func observeCloudKitChanges() {
        cloudSyncObserver = NotificationCenter.default.addObserver(
            forName: .cloudKitDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshHistory()
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
                self?.refreshHistory()
                // A committed session may resolve a recovery candidate — let
                // the engine re-evaluate against the new history.
                self?.recovery?.reconcile()
            }
        }
    }

    /// Routine schedules and exercise metadata also contribute to History's immutable snapshots.
    /// They are invalidated explicitly after a successful save rather than watched through broad
    /// main-context queries whose hashing previously ran during SwiftUI updates.
    private func observeHistorySourceDataChanges() {
        historySourceDataObserver = NotificationCenter.default.addObserver(
            forName: .historySourceDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshHistory()
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

    /// What the Lock Screen countdown should say for the timer that is starting.
    /// The exercise name is read from the session the user is actually in;
    /// restoring after a relaunch may have no session yet, which is fine.
    private func liveActivityContent(
        startDate: Date,
        deadline: Date
    ) -> RestTimerLiveActivityContent {
        let exerciseName: String? = {
            guard let session = currentSession else { return nil }
            let exercises = session.workoutExercisesList.sorted(by: { $0.order < $1.order })
            guard currentExerciseIndex < exercises.count else { return nil }
            return exercises[currentExerciseIndex].exerciseName
        }()

        return RestTimerLiveActivityContent(
            workoutName: currentSession?.routine?.name
                ?? "live_activity.rest_timer.workout_fallback".localized,
            exerciseName: exerciseName,
            startDate: startDate,
            deadline: deadline
        )
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

                // Re-present the Lock Screen countdown. Idempotent: if this
                // process already presents this timer, the presenter leaves it
                // alone rather than requesting a second activity.
                restTimerLiveActivity.startActivity(
                    id: timerID,
                    content: liveActivityContent(startDate: restStart, deadline: deadline)
                )

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
        appliedOverloadWeights.removeAll()
        // A discarded session is still a session that ended, so a §8 A/B
        // trigger Rule 3 suppressed during it gets its safe moment here. It
        // earns nothing new — a workout that was thrown away is not a value
        // moment (docs/pro-subscription.md §5g).
        Task { await proactivePaywalls?.activeWorkoutDidEnd() }
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
            routineTemplateSync.applyPerformedValues(
                from: session,
                reconcileExerciseMembership: true
            )
        }

        save()
        refreshHistory()

        // Save to HealthKit
        saveWorkoutToHealthKit(session: session)

        currentSession = nil
        elapsedTime = 0
        overloadSnapshots.removeAll()
        appliedOverloadWeights.removeAll()
        // §8 placement B. Reported **after** `currentSession` is cleared, which
        // is what makes Rule 3 stop suppressing — this is the "safe moment after
        // the session ends" the placement is deferred to.
        Task { await proactivePaywalls?.workoutDidComplete() }
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

    /// Apply progressive overload: raises the routine template (for future workouts).
    ///
    /// It deliberately does NOT touch the sets of the workout in progress. The
    /// suggestion only appears once every set of the exercise is completed at
    /// the rep max, so there is nothing left to perform at the new weight —
    /// writing the proposal into the live sets rewrote work the user had
    /// already done and displayed numbers they never lifted. The Watch applies
    /// the same rule (`WatchWorkoutViewModel+ProgressiveOverloadApply`).
    ///
    /// plannedWeight/plannedReps still take the performance, because
    /// `progressiveOverloadApplied` makes every aggregator read the planned
    /// fields back out as the performed values.
    func applyProgressiveOverload(for workoutExercise: WorkoutExercise, weightIncrement: Double) {
        let minReps = workoutExercise.targetRepMin ?? 1

        objectWillChange.send()

        var workoutSetValues: [UUID: OverloadSnapshot.SetValues] = [:]
        var templateSetValues: [UUID: OverloadSnapshot.TemplateValues] = [:]

        let workoutSets = workoutExercise.setsList
        for set in workoutSets {
            workoutSetValues[set.id] = OverloadSnapshot.SetValues(
                plannedReps: set.plannedReps, actualReps: set.actualReps,
                plannedWeight: set.plannedWeight, actualWeight: set.actualWeight
            )
            set.plannedReps = set.actualReps
            set.plannedWeight = set.actualWeight
        }

        // Mark that progressive overload was applied
        workoutExercise.progressiveOverloadApplied = true

        // Update routine template (so it persists for future workouts). A swapped
        // exercise writes into the performed alternative's own set scheme — the
        // primary slot's sets stay untouched.
        var newTemplateWeights: [Double] = []
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
                newTemplateWeights = templateIncrease.weights
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
            newTemplateWeights = templateIncrease.weights
        }

        // The confirmed card can no longer read the new weight off the workout's
        // sets (they keep the performance), so the value it announces is
        // recorded here. Nil means the target's sets don't share one weight —
        // a pyramid or drop scheme — and the card then says "all sets adjusted"
        // instead of naming a weight that is wrong for every set but the first.
        // This mirrors what the History card reads out of the durable
        // correlation ledger for a Watch-applied increase.
        // No entry at all when nothing was written (unresolvable slot, swapped
        // exercise with no matching alternative, empty scheme) — recording one
        // would make the card announce an adjustment that never happened.
        if let first = newTemplateWeights.first {
            let isUniform = newTemplateWeights.dropFirst().allSatisfy { $0 == first }
            appliedOverloadWeights[workoutExercise.id] = isUniform ? first : nil
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

    // §8 placement B's second trigger: "the first automatic progressive-overload
    // suggestion". Two screens can show one, so there are two events — but
    // *whether a given appearance counts* is decided here, not in the views:
    // the screens report what appeared, this decides what it means.
    //
    // Both surfaces are inside a session, so these only ever arm the trigger;
    // Rule 3 defers the paywall itself to the end of the workout
    // (docs/pro-subscription.md §5g).

    /// Reported by the mid-workout prompt bar whenever the prompt it shows
    /// changes, including its first appearance.
    ///
    /// Only a `.suggestion` counts. The bar's other state is the `.applied`
    /// confirmation, which is feedback on the user's own action rather than a
    /// suggestion the app made.
    func overloadPromptDidAppear(_ prompt: OverloadPrompt?) {
        guard case .suggestion = prompt else { return }
        reportOverloadSuggestionShown()
    }

    /// Reported by the completion screen when it appears. Counts only when the
    /// "Ready for More Weight" section actually has something to offer.
    func completionOverloadSuggestionsDidAppear() {
        guard !overloadSuggestionExercises.isEmpty else { return }
        reportOverloadSuggestionShown()
    }

    private func reportOverloadSuggestionShown() {
        Task { await proactivePaywalls?.overloadSuggestionWasShown() }
    }

    func canUndoProgressiveOverload(for workoutExercise: WorkoutExercise) -> Bool {
        overloadSnapshots[workoutExercise.id] != nil
    }

    /// The weight an applied increase raised the template to, for the confirmed
    /// card. Nil when the increase came from a nonuniform scheme (or from a
    /// session this view model no longer holds a snapshot for).
    func appliedOverloadWeight(for workoutExercise: WorkoutExercise) -> Double? {
        appliedOverloadWeights[workoutExercise.id] ?? nil
    }

    /// An increase was applied, but its target's sets do not share one weight,
    /// so no single number is true of the whole exercise.
    func hasNonUniformAppliedOverload(for workoutExercise: WorkoutExercise) -> Bool {
        appliedOverloadWeights[workoutExercise.id] == .some(nil)
    }

    /// The template values an increase would start from — what the apply
    /// actually raises. The performed values can differ (the user lifted more
    /// or less than planned), and previewing those would announce a different
    /// number than the confirmation. Nil when the template target can't be
    /// resolved, in which case the caller keeps its performed-value preview.
    func overloadTemplateFirstSet(for workoutExercise: WorkoutExercise) -> (weight: Double, reps: Int)? {
        guard let routine = currentSession?.routine else { return nil }
        return overloadTemplateFirstSet(in: routine, for: workoutExercise)
    }

    /// Same resolution against a completed session's routine, for the History
    /// surfaces (which apply to the live template, not to the recorded workout).
    func overloadTemplateFirstSet(
        from session: WorkoutSession, for workoutExercise: WorkoutExercise
    ) -> (weight: Double, reps: Int)? {
        guard let routine = session.routine else { return nil }
        return overloadTemplateFirstSet(in: routine, for: workoutExercise)
    }

    private func overloadTemplateFirstSet(
        in routine: Routine, for workoutExercise: WorkoutExercise
    ) -> (weight: Double, reps: Int)? {
        let sets: [(weight: Double, reps: Int, order: Int)]
        if workoutExercise.wasSwapped {
            guard let alternative = alternativeEntry(in: routine, for: workoutExercise) else { return nil }
            sets = alternative.setsList.map { ($0.weight, $0.reps, $0.order) }
        } else {
            guard let slot = routineExercise(in: routine, for: workoutExercise) else { return nil }
            sets = slot.setsList.map { ($0.weight, $0.reps, $0.order) }
        }
        guard let first = sets.sorted(by: { $0.order < $1.order }).first else { return nil }
        return (first.weight, first.reps)
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
        appliedOverloadWeights.removeValue(forKey: workoutExercise.id)

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

    func addExerciseToWorkout(
        exercise: Exercise,
        configuredSets: [ExerciseSet],
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil
    ) {
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
        workoutExercise.targetRepMin = targetRepMin
        workoutExercise.targetRepMax = targetRepMax

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

    /// Inserts a copy of `set` directly after it, renumbering the sets behind it.
    /// The copy always starts incomplete — duplicating is a planning action, not
    /// a way to log a set that was never performed.
    func duplicateSet(_ set: WorkoutSet, in workoutExercise: WorkoutExercise) {
        guard currentSession != nil else { return }

        objectWillChange.send()

        let copy = WorkoutSet(
            plannedReps: set.plannedReps,
            actualReps: set.actualReps,
            plannedWeight: set.plannedWeight,
            actualWeight: set.actualWeight,
            restTime: set.restTime,
            order: set.order + 1
        )
        copy.workoutExercise = workoutExercise

        for existing in workoutExercise.setsList where existing.order > set.order {
            existing.order += 1
        }

        workoutExercise.sets?.append(copy)
        workoutSessionRepository.insert(copy)
        save()
    }

    /// Writes `reps`/`weight` to `set` and, when `propagating` names a field, copies
    /// only that field to every later set of the same exercise that is still
    /// incomplete.
    ///
    /// Propagating one field at a time is deliberate: a ramp-up scheme keeps its own
    /// per-set weights when the user only fixes the rep count, and vice versa.
    /// Already-logged sets are never rewritten — they record what actually happened.
    func updateSet(
        _ set: WorkoutSet,
        in workoutExercise: WorkoutExercise,
        reps: Int,
        weight: Double,
        propagating field: WorkoutSetField?
    ) {
        objectWillChange.send()
        set.actualReps = reps
        set.actualWeight = weight

        if let field {
            for following in workoutExercise.setsList
            where following.order > set.order && !following.isCompleted {
                switch field {
                case .reps: following.actualReps = reps
                case .weight: following.actualWeight = weight
                }
            }
        }

        save()
    }

    /// Pushes the running rest back by `interval`. Restarting through
    /// `startRestTimer` is what keeps the notification, the Live Activity and the
    /// persisted deadline in sync with the new end time.
    func extendRestTimer(by interval: TimeInterval) {
        guard isRestTimerActive else { return }
        startRestTimer(duration: restTimeRemaining + interval)
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
        restTimerLiveActivity.startActivity(
            id: timerID,
            content: liveActivityContent(startDate: startDate, deadline: deadline)
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

        // Cancel any pending notification and end the Lock Screen countdown.
        // Both are keyed by the timer's identity, so a second WorkoutViewModel
        // sharing these gateways can never cancel this timer's surfaces.
        if let timerID {
            restTimerReminders.cancelReminder(id: timerID)
            restTimerLiveActivity.endActivity(id: timerID)
        }

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

        // Historical edits deliberately do NOT reconcile exercise membership —
        // the routine may have changed since that older workout was recorded.
        if updateTemplate {
            routineTemplateSync.applyPerformedValues(
                from: session,
                reconcileExerciseMembership: false
            )
        }

        save()
        refreshHistory()

        // The cached AI recap/analysis for this session reflect the old values — drop them.
        aiCoachCache.invalidatePostWorkout(workoutId: session.id)
        aiCoachCache.invalidateWorkoutAnalysis(workoutId: session.id)

        // Propagate template changes to the watch (RoutinesViewModel re-fetches and syncs).
        if updateTemplate {
            NotificationCenter.default.post(name: .routineTemplateDidChange, object: nil)
        }
    }

    // MARK: - History

    func refreshHistory() {
        historyVersion += 1
    }

    func workoutSession(id: UUID) -> WorkoutSession? {
        workoutSessionRepository.findSession(id: id, healthKitWorkoutId: nil)
    }

    func deleteWorkout(_ session: WorkoutSession) {
        workoutSessionRepository.delete(session)
        save()
        refreshHistory()
    }

    /// Deletes the session locally and, when asked, its Apple Health counterpart.
    ///
    /// SwiftData is the source of truth, so the local delete happens first and is
    /// never gated on, blocked by, or rolled back for HealthKit. A HealthKit
    /// failure only raises `healthKitDeleteFailed`, which the History screen
    /// surfaces non-blockingly — the user may still see the workout in Health.
    func deleteWorkout(_ session: WorkoutSession, alsoFromHealthKit: Bool) {
        let healthKitWorkoutId = session.healthKitWorkoutId
        deleteWorkout(session)

        guard alsoFromHealthKit, let healthKitWorkoutId else { return }
        Task {
            do {
                // A `false` result means the workout was already absent from
                // HealthKit — the desired end state, not a failure.
                _ = try await healthKitManager.deleteWorkout(externalUUID: healthKitWorkoutId)
            } catch {
                print("HealthKit workout delete failed: \(error)")
                healthKitDeleteFailed = true
            }
        }
    }

    /// Clears the non-blocking Apple Health delete notice once the user has seen it.
    func dismissHealthKitDeleteNotice() {
        healthKitDeleteFailed = false
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

    /// `isolated deinit` (SE-0371): `Timer` and the `NSObjectProtocol` observer
    /// tokens are non-`Sendable`, so a nonisolated `deinit` may not read them
    /// under strict concurrency. This teardown is inherently main-actor work
    /// (invalidating main-run-loop timers), so isolating it is also the honest
    /// description of what it does.
    isolated deinit {
        timer?.invalidate()
        restTimer?.invalidate()
        restTimerReminderTask?.cancel()
        if let cloudSyncObserver {
            NotificationCenter.default.removeObserver(cloudSyncObserver)
        }
        if let workoutHistoryObserver {
            NotificationCenter.default.removeObserver(workoutHistoryObserver)
        }
        if let historySourceDataObserver {
            NotificationCenter.default.removeObserver(historySourceDataObserver)
        }
        if let recoverableWorkoutsObserver {
            NotificationCenter.default.removeObserver(recoverableWorkoutsObserver)
        }
    }
}
