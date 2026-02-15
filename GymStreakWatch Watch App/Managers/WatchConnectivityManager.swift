import Foundation
import Combine
import WatchConnectivity
import os

private let logger = Logger(subsystem: "com.jmanke.gymstreak.watch", category: "WatchConnectivity")

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var isReachable = false

    private var session: WCSession?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - Send Completed Workout to iOS

    func sendCompletedWorkout(_ workout: CompletedWatchWorkout) {
        guard let session = session, session.activationState == .activated else {
            logger.error("Cannot send workout — session not activated")
            return
        }

        do {
            let data = try JSONEncoder().encode(workout)
            let userInfo: [String: Any] = ["completedWorkout": data]

            // Use transferUserInfo for guaranteed delivery
            session.transferUserInfo(userInfo)
            logger.info("Sent completed workout to iPhone: \(workout.routineName)")
        } catch {
            logger.error("Failed to send workout: \(error.localizedDescription)")
        }
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

            self.isReachable = session.isReachable
            logger.info("Activated on Watch — reachable: \(session.isReachable)")
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            logger.info("Reachability changed: \(session.isReachable)")
        }
    }
}
