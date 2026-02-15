import Foundation
import WatchConnectivity
import os

private let logger = Logger(subsystem: "com.jmanke.gymstreak", category: "WatchConnectivity")

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var isReachable = false
    @Published var isPaired = false
    @Published var isWatchAppInstalled = false

    private var session: WCSession?
    private var pendingWorkout: CompletedWatchWorkout?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - Pending Workout Handling

    func processPendingWorkout() -> CompletedWatchWorkout? {
        defer { pendingWorkout = nil }
        return pendingWorkout
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                logger.error("Activation failed: \(error.localizedDescription)")
                return
            }

            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable

            logger.info("Activated — paired: \(session.isPaired), watchAppInstalled: \(session.isWatchAppInstalled)")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        logger.info("Session became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        logger.info("Session deactivated — reactivating")
        // Reactivate session for switching watches
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            logger.info("Reachability changed: \(session.isReachable)")
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            logger.info("Watch state changed — paired: \(session.isPaired), watchAppInstalled: \(session.isWatchAppInstalled)")
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
                logger.error("Failed to decode workout: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func handleCompletedWorkout(_ workout: CompletedWatchWorkout) {
        // Store for later processing in case no one is observing yet
        pendingWorkout = workout

        // Post notification for the app to handle
        NotificationCenter.default.post(
            name: .watchWorkoutCompleted,
            object: nil,
            userInfo: ["workout": workout]
        )
        logger.info("Received completed workout from Watch: \(workout.routineName)")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let watchWorkoutCompleted = Notification.Name("watchWorkoutCompleted")
}
