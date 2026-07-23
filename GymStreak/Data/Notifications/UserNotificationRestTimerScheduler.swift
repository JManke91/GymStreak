import Foundation
import UserNotifications

@MainActor
protocol RestTimerNotificationCenter: AnyObject {
    func restTimerAuthorizationStatus() async -> UNAuthorizationStatus
    func requestRestTimerAuthorization() async throws -> Bool
    func addRestTimerRequest(_ request: UNNotificationRequest) async throws
    func removePendingRestTimerRequests(withIdentifiers identifiers: [String])
    func pendingRestTimerRequests() async -> [UNNotificationRequest]
}

extension UNUserNotificationCenter: RestTimerNotificationCenter {
    func restTimerAuthorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }

    func requestRestTimerAuthorization() async throws -> Bool {
        try await requestAuthorization(options: [.alert, .sound])
    }

    func addRestTimerRequest(_ request: UNNotificationRequest) async throws {
        try await add(request)
    }

    func removePendingRestTimerRequests(withIdentifiers identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func pendingRestTimerRequests() async -> [UNNotificationRequest] {
        await pendingNotificationRequests()
    }
}

@MainActor
final class UserNotificationRestTimerScheduler: RestTimerReminderScheduling {
    private static let requestIdentifierPrefix = "restTimer."
    private static let legacyRequestIdentifier = "restTimer"

    private let notificationCenter: any RestTimerNotificationCenter
    private let now: () -> Date
    private var activeTimerID: UUID?
    private var activeRequestIdentifier: String?
    private var generation = 0

    init(
        notificationCenter: any RestTimerNotificationCenter = UNUserNotificationCenter.current(),
        now: @escaping () -> Date = Date.init
    ) {
        self.notificationCenter = notificationCenter
        self.now = now
    }

    func scheduleReminder(
        id: UUID,
        deadline: Date
    ) async -> RestTimerReminderOutcome {
        guard !Task.isCancelled else { return .cancelled }

        generation += 1
        removeActiveRequest()

        let requestIdentifier = Self.requestIdentifierPrefix + id.uuidString
        let scheduledGeneration = generation
        activeTimerID = id
        activeRequestIdentifier = requestIdentifier

        do {
            await removeStalePersistedRequests(
                excluding: requestIdentifier,
                generation: scheduledGeneration
            )

            guard isCurrent(
                id: id,
                requestIdentifier: requestIdentifier,
                generation: scheduledGeneration
            ), !Task.isCancelled else {
                clearRequestIfCurrent(
                    id: id,
                    requestIdentifier,
                    generation: scheduledGeneration
                )
                return .cancelled
            }

            var status = await notificationCenter.restTimerAuthorizationStatus()
            if status == .notDetermined {
                let granted = try await notificationCenter.requestRestTimerAuthorization()
                guard granted else {
                    clearRequestIfCurrent(
                        id: id,
                        requestIdentifier,
                        generation: scheduledGeneration
                    )
                    return .authorizationDenied
                }
                status = .authorized
            }

            guard isCurrent(
                id: id,
                requestIdentifier: requestIdentifier,
                generation: scheduledGeneration
            ), !Task.isCancelled else {
                clearRequestIfCurrent(
                    id: id,
                    requestIdentifier,
                    generation: scheduledGeneration
                )
                return .cancelled
            }

            switch status {
            case .authorized:
                break
            case .denied:
                clearRequestIfCurrent(
                    id: id,
                    requestIdentifier,
                    generation: scheduledGeneration
                )
                return .authorizationDenied
            case .provisional, .ephemeral:
                clearRequestIfCurrent(
                    id: id,
                    requestIdentifier,
                    generation: scheduledGeneration
                )
                return .alertsUnavailable
            case .notDetermined:
                clearRequestIfCurrent(
                    id: id,
                    requestIdentifier,
                    generation: scheduledGeneration
                )
                return .alertsUnavailable
            @unknown default:
                clearRequestIfCurrent(
                    id: id,
                    requestIdentifier,
                    generation: scheduledGeneration
                )
                return .alertsUnavailable
            }

            let remaining = deadline.timeIntervalSince(now())
            guard remaining > 0 else {
                clearRequestIfCurrent(
                    id: id,
                    requestIdentifier,
                    generation: scheduledGeneration
                )
                return .deadlinePassed
            }

            let content = UNMutableNotificationContent()
            content.title = "notification.rest_timer.title".localized
            content.body = "notification.rest_timer.body".localized
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: remaining,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: requestIdentifier,
                content: content,
                trigger: trigger
            )
            try await notificationCenter.addRestTimerRequest(request)

            guard isCurrent(
                id: id,
                requestIdentifier: requestIdentifier,
                generation: scheduledGeneration
            ), !Task.isCancelled else {
                notificationCenter.removePendingRestTimerRequests(
                    withIdentifiers: [requestIdentifier]
                )
                return .cancelled
            }

            return .scheduled
        } catch is CancellationError {
            clearRequestIfCurrent(
                id: id,
                requestIdentifier,
                generation: scheduledGeneration
            )
            return .cancelled
        } catch {
            print("Rest timer notification could not be scheduled: \(error.localizedDescription)")
            clearRequestIfCurrent(
                id: id,
                requestIdentifier,
                generation: scheduledGeneration
            )
            return .failed
        }
    }

    func cancelReminder(id: UUID) {
        let requestIdentifier = Self.requestIdentifierPrefix + id.uuidString
        if activeTimerID == id {
            generation += 1
            activeTimerID = nil
            activeRequestIdentifier = nil
        }
        notificationCenter.removePendingRestTimerRequests(
            withIdentifiers: [requestIdentifier, Self.legacyRequestIdentifier]
        )
    }

    private func isCurrent(
        id: UUID,
        requestIdentifier: String,
        generation: Int
    ) -> Bool {
        self.generation == generation &&
            activeTimerID == id &&
            activeRequestIdentifier == requestIdentifier
    }

    private func clearRequestIfCurrent(
        id: UUID,
        _ requestIdentifier: String,
        generation: Int
    ) {
        guard isCurrent(
            id: id,
            requestIdentifier: requestIdentifier,
            generation: generation
        ) else { return }
        activeTimerID = nil
        activeRequestIdentifier = nil
    }

    private func removeActiveRequest() {
        let identifiers = [activeRequestIdentifier, Self.legacyRequestIdentifier]
            .compactMap { $0 }
        activeTimerID = nil
        activeRequestIdentifier = nil
        notificationCenter.removePendingRestTimerRequests(
            withIdentifiers: identifiers
        )
    }

    private func removeStalePersistedRequests(
        excluding requestIdentifier: String,
        generation: Int
    ) async {
        let pendingRequests = await notificationCenter.pendingRestTimerRequests()
        guard activeRequestIdentifier == requestIdentifier,
              self.generation == generation,
              !Task.isCancelled else { return }
        removeRestTimerRequests(
            from: pendingRequests,
            excluding: requestIdentifier
        )
    }

    private func removeRestTimerRequests(
        from pendingRequests: [UNNotificationRequest],
        excluding requestIdentifier: String? = nil
    ) {
        let identifiers = pendingRequests
            .map(\.identifier)
            .filter {
                $0 != requestIdentifier &&
                    ($0 == Self.legacyRequestIdentifier ||
                        $0.hasPrefix(Self.requestIdentifierPrefix))
            }
        guard !identifiers.isEmpty else { return }
        notificationCenter.removePendingRestTimerRequests(
            withIdentifiers: identifiers
        )
    }
}
