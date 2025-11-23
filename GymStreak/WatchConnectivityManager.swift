import Foundation
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var isReachable = false
    @Published var isPaired = false
    @Published var isWatchAppInstalled = false

    private var session: WCSession?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - Public Methods

    func syncRoutines(_ routines: [Routine]) {
        guard let session = session, session.activationState == .activated else {
            print("WatchConnectivity: Session not activated")
            return
        }

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

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // Handle completed workouts sent back from Watch
        if let workoutData = userInfo["completedWorkout"] as? Data {
            do {
                let workout = try JSONDecoder().decode(CompletedWatchWorkout.self, from: workoutData)
                Task { @MainActor in
                    self.handleCompletedWorkout(workout)
                }
            } catch {
                print("WatchConnectivity: Failed to decode workout - \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func handleCompletedWorkout(_ workout: CompletedWatchWorkout) {
        // Post notification for the app to handle
        NotificationCenter.default.post(
            name: .watchWorkoutCompleted,
            object: nil,
            userInfo: ["workout": workout]
        )
        print("WatchConnectivity: Received completed workout from Watch")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let watchWorkoutCompleted = Notification.Name("watchWorkoutCompleted")
}
