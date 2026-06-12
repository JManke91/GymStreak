import Foundation
import Combine
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var isReachable = false

    private var session: WCSession?
    private var routineStore: RoutineStore?

    /// Persists completed workouts that have been handed to WatchConnectivity but not
    /// yet confirmed delivered to iOS. Survives watch app suspension and termination,
    /// so we can retry on next activation if a transfer is dropped before the system
    /// commits it to its persistent queue.
    private let pendingQueue = PendingWatchWorkoutQueue()

    private override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    func setRoutineStore(_ store: RoutineStore) {
        self.routineStore = store
        // Process any context that arrived before store was set
        if let session = session, !session.receivedApplicationContext.isEmpty {
            processApplicationContext(session.receivedApplicationContext)
        }
    }

    // MARK: - Send Completed Workout to iOS

    /// Sends a completed workout to the iOS app. Always persists locally first so a
    /// dropped transfer (watch suspension, session not activated, transfer error) can
    /// be retried on next activation/reachability change. iOS deduplicates on the
    /// workout's `id`, so duplicate deliveries are safe.
    func sendCompletedWorkout(_ workout: CompletedWatchWorkout) {
        // 1. Persist BEFORE attempting transfer so a crash or suspension between
        // here and the OS queueing the transfer doesn't lose the workout.
        pendingQueue.add(workout)

        // 2. Attempt to send. If the session isn't activated yet, the activation
        // callback will retry from the persistent queue.
        attemptSend(workout)
    }

    private func attemptSend(_ workout: CompletedWatchWorkout) {
        guard let session = session else {
            print("WatchConnectivity: No WC session — workout persisted for later retry")
            return
        }

        guard session.activationState == .activated else {
            print("WatchConnectivity: Session not yet activated — workout persisted for retry on activation")
            return
        }

        let userInfo: [String: Any]
        do {
            let data = try JSONEncoder().encode(workout)
            userInfo = ["completedWorkout": data, "workoutId": workout.id.uuidString]
        } catch {
            print("WatchConnectivity: Failed to encode workout — \(error.localizedDescription)")
            return
        }

        // Fast path: if iOS is reachable, fire a sendMessage so the iOS app sees
        // the workout immediately while it's open. This does NOT replace
        // transferUserInfo — sendMessage has no persistence guarantee, so we
        // ALWAYS also queue a guaranteed-delivery transfer below.
        if session.isReachable {
            session.sendMessage(userInfo, replyHandler: nil) { error in
                print("WatchConnectivity: sendMessage fast-path failed — \(error.localizedDescription) (transferUserInfo will still deliver)")
            }
        }

        // Guaranteed-delivery path. The system persists this across watch
        // suspension and reboot once it returns. The didFinishUserInfoTransfer
        // delegate is our signal to remove from the local pending queue.
        session.transferUserInfo(userInfo)
        print("WatchConnectivity: Queued transferUserInfo for workout \(workout.id) (\(workout.routineName))")
    }

    /// Resends any workouts still sitting in the pending queue. Safe to call
    /// repeatedly — iOS dedupes on workout id.
    private func retryPendingTransfers() {
        let pending = pendingQueue.all()
        guard !pending.isEmpty else { return }

        print("WatchConnectivity: Retrying \(pending.count) pending workout transfer(s)")
        for workout in pending {
            attemptSend(workout)
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

            self.isReachable = session.isReachable
            print("WatchConnectivity: Activated on Watch")

            // Check for any pending context
            if !session.receivedApplicationContext.isEmpty {
                self.processApplicationContext(session.receivedApplicationContext)
            }

            // Retry any workouts that were queued before the session was active.
            self.retryPendingTransfers()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            print("WatchConnectivity: Reachability changed - \(session.isReachable)")

            // When iOS becomes reachable, retry pending transfers so the user
            // sees the workout appear quickly via sendMessage rather than
            // waiting for the background transferUserInfo cycle.
            if session.isReachable {
                self.retryPendingTransfers()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.processApplicationContext(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleIncoming(message)
        }
    }

    /// iOS sends the save-acknowledgment via transferUserInfo (guaranteed delivery)
    /// in addition to the sendMessage fast-path, so acks can arrive here too.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            self.handleIncoming(userInfo)
        }
    }

    /// Called when a transferUserInfo we initiated finishes — successfully or with
    /// an error. We deliberately do NOT remove the workout from the pending queue on
    /// success here: WatchConnectivity confirming a transfer only means the system
    /// delivered it to the paired device's WC daemon, NOT that the iOS *app* received
    /// or persisted it (the app may be force-quit, mid-launch after a reboot, or the
    /// transfer may be superseded). Removing on this callback is exactly what allowed
    /// workouts to be saved to HealthKit yet never reach iOS history. The workout is
    /// removed only when iOS sends an explicit app-level ack confirming the
    /// WorkoutSession was committed to SwiftData (see `handleIncoming`). On error we
    /// also keep it queued so it's retried on the next activation/reachability change.
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("WatchConnectivity: transferUserInfo failed (will retry) — \(error.localizedDescription)")
                return
            }
            print("WatchConnectivity: transferUserInfo delivered to system — awaiting iPhone save ack before clearing")
        }
    }

    /// Routes an incoming payload. An app-level workout ack removes the confirmed
    /// workout from the durable retry queue; anything else is treated as a routine sync.
    @MainActor
    private func handleIncoming(_ payload: [String: Any]) {
        if let ackString = payload["workoutAck"] as? String, let id = UUID(uuidString: ackString) {
            pendingQueue.remove(id: id)
            print("WatchConnectivity: workout \(id) acknowledged saved by iPhone — removed from pending queue")
            return
        }
        processApplicationContext(payload)
    }

    private func processApplicationContext(_ context: [String: Any]) {
        guard let routineData = context["routines"] as? Data else {
            return
        }

        do {
            let routines = try JSONDecoder().decode([WatchRoutine].self, from: routineData)
            routineStore?.updateRoutines(routines)
            print("WatchConnectivity: Received \(routines.count) routines from iPhone")
        } catch {
            print("WatchConnectivity: Failed to decode routines - \(error.localizedDescription)")
        }
    }
}

// MARK: - Pending workout persistence

/// App-Group-backed queue of workouts that have been handed to WatchConnectivity
/// but not yet confirmed delivered to iOS. Reuses the same `group.com.gymstreak.shared`
/// suite already used by `RoutineStore`.
@MainActor
private final class PendingWatchWorkoutQueue {
    private let userDefaults = UserDefaults(suiteName: "group.com.gymstreak.shared")
    private let key = "pendingCompletedWorkouts"

    func add(_ workout: CompletedWatchWorkout) {
        var current = all()
        // Replace any existing entry with the same id (e.g. user retries a send).
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
            print("PendingWatchWorkoutQueue: failed to decode — \(error.localizedDescription)")
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
            print("PendingWatchWorkoutQueue: failed to encode — \(error.localizedDescription)")
        }
    }
}
