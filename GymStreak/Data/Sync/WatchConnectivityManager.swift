import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject, WatchSyncServicing {
    static let shared = WatchConnectivityManager()

    @Published var isReachable = false
    @Published var isPaired = false
    @Published var isWatchAppInstalled = false

    private var session: WCSession?

    /// Persistent multi-slot buffer for completed workouts that arrived before any
    /// observer (RoutinesViewModel) was ready to consume them. App-Group-backed so
    /// it survives crashes between WC delivery and SwiftData save.
    private let pendingQueue = PendingReceivedWorkoutQueue()

    private override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - Pending Workout Handling

    /// Returns all workouts currently buffered but not yet committed to SwiftData.
    /// Does NOT remove them — the consumer is responsible for calling
    /// `markPendingProcessed(id:)` after a successful save (or after detecting
    /// the workout is a duplicate of an already-saved one).
    func pendingWorkouts() -> [CompletedWatchWorkout] {
        pendingQueue.all()
    }

    /// Removes a workout from the persistent pending buffer. Call after the
    /// consumer (RoutinesViewModel) has successfully written the WorkoutSession
    /// to SwiftData, or after dedup detected an existing record.
    func markPendingProcessed(id: UUID) {
        pendingQueue.remove(id: id)
    }

    /// Sends an app-level acknowledgment to the watch confirming a completed workout
    /// has been committed to SwiftData (or recognized as already present). The watch
    /// keeps the workout in its durable retry queue until it receives this ack —
    /// WatchConnectivity's own transfer-completion callback only confirms transport
    /// delivery, not that iOS persisted the workout, so without this ack a workout can
    /// be silently lost (present in HealthKit but never in iOS history). Sent over both
    /// the sendMessage fast-path (when reachable) and transferUserInfo (guaranteed),
    /// and re-sent whenever a duplicate arrives, so delivery is self-healing.
    func acknowledgeWorkoutSaved(id: UUID) {
        guard let session = session, session.activationState == .activated else {
            return
        }
        let payload: [String: Any] = ["workoutAck": id.uuidString]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("WatchConnectivity: ack sendMessage failed — \(error.localizedDescription) (transferUserInfo will still deliver)")
            }
        }
        session.transferUserInfo(payload)
        print("WatchConnectivity: sent save-ack for workout \(id)")
    }

    /// True while WatchConnectivity may still be holding watch content it has
    /// received but not yet delivered to our delegate (or the session hasn't
    /// finished activating). `hasContentPending` is only meaningful after
    /// activation and is a *positive* signal only: it cannot see payloads the
    /// watch has queued but that haven't crossed the radio yet — callers must
    /// combine it with a grace period (see `WorkoutViewModel.reconcileWatchWorkouts`).
    var mayHaveUndeliveredContent: Bool {
        guard let session, session.activationState == .activated else {
            return true
        }
        return session.hasContentPending
    }

    // MARK: - Public Methods

    func syncRoutines(_ routines: [Routine]) {
        guard let session = session, session.activationState == .activated else {
            print("WatchConnectivity: Cannot sync - session not activated")
            return
        }

        // On simulator, isWatchAppInstalled is always false even when Watch app is running
        #if !targetEnvironment(simulator)
        guard session.isWatchAppInstalled else {
            print("WatchConnectivity: Cannot sync - Watch app not installed")
            return
        }
        #endif

        let watchRoutines = routines.map { $0.toWatchRoutine() }

        do {
            let data = try JSONEncoder().encode(watchRoutines)
            let context: [String: Any] = ["routines": data]

            try session.updateApplicationContext(context)
            print("WatchConnectivity: Synced \(routines.count) routines to Watch")
        } catch {
            print("WatchConnectivity: Failed to sync routines - \(error.localizedDescription)")
        }
    }

    func sendRoutinesIfReachable(_ routines: [Routine]) {
        guard let session = session, session.isReachable else {
            // Fall back to application context
            syncRoutines(routines)
            return
        }

        let watchRoutines = routines.map { $0.toWatchRoutine() }

        do {
            let data = try JSONEncoder().encode(watchRoutines)
            let message: [String: Any] = ["routines": data]

            session.sendMessage(message, replyHandler: nil) { error in
                print("WatchConnectivity: Failed to send message - \(error.localizedDescription)")
            }
        } catch {
            print("WatchConnectivity: Failed to encode routines - \(error.localizedDescription)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("WatchConnectivity: Activation failed - \(error.localizedDescription)")
                return
            }

            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable

            print("WatchConnectivity: Activated - paired: \(session.isPaired), installed: \(session.isWatchAppInstalled)")

            // If we already have buffered workouts (e.g. from a previous launch
            // that crashed before SwiftData save), notify any current observers
            // so they get processed.
            self.republishPendingWorkouts()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("WatchConnectivity: Session became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("WatchConnectivity: Session deactivated")
        // Reactivate session for switching watches
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            print("WatchConnectivity: Reachability changed - \(session.isReachable)")
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            print("WatchConnectivity: Watch state changed - paired: \(session.isPaired), installed: \(session.isWatchAppInstalled)")

            // Notify so RoutinesViewModel can trigger sync
            if session.isWatchAppInstalled {
                NotificationCenter.default.post(name: .watchAppBecameAvailable, object: nil)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.handleIncomingPayload(userInfo, source: "userInfo")
        }
    }

    /// Watch sends completed workouts via sendMessage as a fast-path when iOS is
    /// reachable, so we must accept them on this delegate too. transferUserInfo
    /// always also fires for the same workout — iOS-side dedupe handles duplicates.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleIncomingPayload(message, source: "message")
        }
    }

    @MainActor
    private func handleIncomingPayload(_ payload: [String: Any], source: String) {
        guard let workoutData = payload["completedWorkout"] as? Data else {
            return
        }
        do {
            let workout = try JSONDecoder().decode(CompletedWatchWorkout.self, from: workoutData)
            handleCompletedWorkout(workout, source: source)
        } catch {
            print("WatchConnectivity: Failed to decode workout (\(source)) - \(error.localizedDescription)")
        }
    }

    @MainActor
    private func handleCompletedWorkout(_ workout: CompletedWatchWorkout, source: String) {
        // Buffer to disk first. RoutinesViewModel may not yet exist (cold start)
        // or may be re-initializing. Idempotency on the consumer + a persistent
        // buffer ensures no workout is dropped between receipt and save.
        pendingQueue.add(workout)

        NotificationCenter.default.post(
            name: .watchWorkoutCompleted,
            object: nil,
            userInfo: ["workout": workout]
        )
        print("WatchConnectivity: Received completed workout from Watch (\(source)) - \(workout.routineName)")
    }

    @MainActor
    private func republishPendingWorkouts() {
        let pending = pendingQueue.all()
        guard !pending.isEmpty else { return }
        print("WatchConnectivity: Re-publishing \(pending.count) buffered workout(s) on activation")
        for workout in pending {
            NotificationCenter.default.post(
                name: .watchWorkoutCompleted,
                object: nil,
                userInfo: ["workout": workout]
            )
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let watchWorkoutCompleted = Notification.Name("watchWorkoutCompleted")
    static let watchAppBecameAvailable = Notification.Name("watchAppBecameAvailable")
    /// Posted after a watch-originated WorkoutSession has been committed to
    /// SwiftData. Lets the History tab refresh without a tab switch.
    static let workoutHistoryDidChange = Notification.Name("workoutHistoryDidChange")
    /// Posted after a routine template is mutated outside of RoutinesViewModel
    /// (e.g. editing a past workout in History). Triggers a routine re-fetch +
    /// watch sync so the corrected values reach iOS and the watch.
    static let routineTemplateDidChange = Notification.Name("routineTemplateDidChange")
}

// MARK: - Persistent buffer for incoming watch workouts

/// App-Group-backed buffer for completed workouts received from the watch but
/// not yet committed to SwiftData. Persists across iOS app crashes that occur
/// between WatchConnectivity delivery and the RoutinesViewModel save. Reuses
/// `group.com.gymstreak.shared`.
@MainActor
private final class PendingReceivedWorkoutQueue {
    private let userDefaults = UserDefaults(suiteName: "group.com.gymstreak.shared")
    private let key = "pendingReceivedWorkouts"

    func add(_ workout: CompletedWatchWorkout) {
        var current = all()
        current.removeAll { $0.id == workout.id }
        current.append(workout)
        save(current)
    }

    func remove(id: UUID) {
        var current = all()
        current.removeAll { $0.id == id }
        save(current)
    }

    func all() -> [CompletedWatchWorkout] {
        guard let userDefaults, let data = userDefaults.data(forKey: key) else {
            return []
        }
        do {
            return try JSONDecoder().decode([CompletedWatchWorkout].self, from: data)
        } catch {
            print("PendingReceivedWorkoutQueue: failed to decode — \(error.localizedDescription)")
            return []
        }
    }

    private func save(_ workouts: [CompletedWatchWorkout]) {
        guard let userDefaults else { return }
        if workouts.isEmpty {
            userDefaults.removeObject(forKey: key)
            return
        }
        do {
            let data = try JSONEncoder().encode(workouts)
            userDefaults.set(data, forKey: key)
        } catch {
            print("PendingReceivedWorkoutQueue: failed to encode — \(error.localizedDescription)")
        }
    }
}
