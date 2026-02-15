import Foundation
import Combine
import WatchConnectivity

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
            print("WatchConnectivity: Session not activated")
            return
        }

        do {
            let data = try JSONEncoder().encode(workout)
            let userInfo: [String: Any] = ["completedWorkout": data]

            // Use transferUserInfo for guaranteed delivery
            session.transferUserInfo(userInfo)
            print("WatchConnectivity: Sent completed workout to iPhone")
        } catch {
            print("WatchConnectivity: Failed to send workout - \(error.localizedDescription)")
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
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            print("WatchConnectivity: Reachability changed - \(session.isReachable)")
        }
    }
}
