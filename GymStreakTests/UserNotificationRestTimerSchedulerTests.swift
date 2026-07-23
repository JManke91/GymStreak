import Foundation
import Testing
import UserNotifications
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct UserNotificationRestTimerSchedulerTests {
    private final class ControllableNotificationCenter: RestTimerNotificationCenter {
        private var suspendedAddContinuation: CheckedContinuation<Void, Never>?
        private var shouldSuspendNextAdd: Bool

        var authorizationStatus: UNAuthorizationStatus
        var authorizationGranted: Bool
        private(set) var authorizationRequestCount = 0
        private(set) var suspendedRequestIdentifier: String?
        private(set) var completedAddIdentifiers: Set<String> = []
        private(set) var pendingRequests: [String: UNNotificationRequest] = [:]

        init(
            authorizationStatus: UNAuthorizationStatus = .authorized,
            authorizationGranted: Bool = true,
            shouldSuspendNextAdd: Bool = true
        ) {
            self.authorizationStatus = authorizationStatus
            self.authorizationGranted = authorizationGranted
            self.shouldSuspendNextAdd = shouldSuspendNextAdd
        }

        func restTimerAuthorizationStatus() async -> UNAuthorizationStatus {
            authorizationStatus
        }

        func requestRestTimerAuthorization() async throws -> Bool {
            authorizationRequestCount += 1
            return authorizationGranted
        }

        func addRestTimerRequest(_ request: UNNotificationRequest) async throws {
            if shouldSuspendNextAdd {
                shouldSuspendNextAdd = false
                suspendedRequestIdentifier = request.identifier
                await withCheckedContinuation { continuation in
                    suspendedAddContinuation = continuation
                }
            }

            completedAddIdentifiers.insert(request.identifier)
            pendingRequests[request.identifier] = request
        }

        func removePendingRestTimerRequests(withIdentifiers identifiers: [String]) {
            for identifier in identifiers {
                pendingRequests[identifier] = nil
            }
        }

        func pendingRestTimerRequests() async -> [UNNotificationRequest] {
            Array(pendingRequests.values)
        }

        func insertPendingRequest(identifier: String) {
            pendingRequests[identifier] = UNNotificationRequest(
                identifier: identifier,
                content: UNMutableNotificationContent(),
                trigger: nil
            )
        }

        func resumeSuspendedAdd() {
            let continuation = suspendedAddContinuation
            suspendedAddContinuation = nil
            continuation?.resume()
        }
    }

    @Test
    func schedulingUsesRemainingTimeUntilDeadline() async {
        let notificationCenter = ControllableNotificationCenter(
            shouldSuspendNextAdd: false
        )
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var now = start.addingTimeInterval(20)
        let scheduler = UserNotificationRestTimerScheduler(
            notificationCenter: notificationCenter,
            now: { now }
        )
        let timerID = UUID()

        let outcome = await scheduler.scheduleReminder(
            id: timerID,
            deadline: start.addingTimeInterval(60)
        )

        let request = notificationCenter.pendingRequests["restTimer.\(timerID.uuidString)"]
        let trigger = request?.trigger as? UNTimeIntervalNotificationTrigger
        #expect(outcome == .scheduled)
        #expect(trigger?.timeInterval == 40)

        now = start.addingTimeInterval(61)
    }

    @Test
    func replacingTimerCannotRestoreAnOlderPendingNotification() async {
        let notificationCenter = ControllableNotificationCenter()
        let scheduler = UserNotificationRestTimerScheduler(
            notificationCenter: notificationCenter
        )

        let firstID = UUID()
        let firstTask = Task {
            await scheduler.scheduleReminder(
                id: firstID,
                deadline: Date().addingTimeInterval(30)
            )
        }
        await yieldUntil {
            notificationCenter.suspendedRequestIdentifier != nil
        }

        let replacementID = UUID()
        let replacementOutcome = await scheduler.scheduleReminder(
            id: replacementID,
            deadline: Date().addingTimeInterval(60)
        )

        let replacementIdentifier = notificationCenter.pendingRequests.keys.first
        notificationCenter.resumeSuspendedAdd()
        let firstOutcome = await firstTask.value
        await yieldUntil {
            guard let suspendedIdentifier = notificationCenter.suspendedRequestIdentifier else {
                return false
            }
            return notificationCenter.completedAddIdentifiers.contains(suspendedIdentifier) &&
                notificationCenter.pendingRequests[suspendedIdentifier] == nil
        }

        #expect(notificationCenter.pendingRequests.count == 1)
        #expect(notificationCenter.pendingRequests[replacementIdentifier ?? ""] != nil)
        #expect(replacementIdentifier == "restTimer.\(replacementID.uuidString)")
        #expect(replacementOutcome == .scheduled)
        #expect(firstOutcome == .cancelled)
    }

    @Test
    func cancellingTimerRemovesNotificationAddedBySuspendedTask() async {
        let notificationCenter = ControllableNotificationCenter()
        let scheduler = UserNotificationRestTimerScheduler(
            notificationCenter: notificationCenter
        )

        let timerID = UUID()
        let scheduleTask = Task {
            await scheduler.scheduleReminder(
                id: timerID,
                deadline: Date().addingTimeInterval(30)
            )
        }
        await yieldUntil {
            notificationCenter.suspendedRequestIdentifier != nil
        }

        scheduler.cancelReminder(id: timerID)
        notificationCenter.resumeSuspendedAdd()
        let outcome = await scheduleTask.value
        await yieldUntil {
            guard let suspendedIdentifier = notificationCenter.suspendedRequestIdentifier else {
                return false
            }
            return notificationCenter.completedAddIdentifiers.contains(suspendedIdentifier) &&
                notificationCenter.pendingRequests[suspendedIdentifier] == nil
        }

        #expect(notificationCenter.pendingRequests.isEmpty)
        #expect(outcome == .cancelled)
    }

    @Test
    func firstScheduleRequestsUndeterminedAuthorization() async {
        let notificationCenter = ControllableNotificationCenter(
            authorizationStatus: .notDetermined,
            shouldSuspendNextAdd: false
        )
        let scheduler = UserNotificationRestTimerScheduler(
            notificationCenter: notificationCenter
        )

        let outcome = await scheduler.scheduleReminder(
            id: UUID(),
            deadline: Date().addingTimeInterval(30)
        )

        #expect(notificationCenter.authorizationRequestCount == 1)
        #expect(notificationCenter.pendingRequests.count == 1)
        #expect(outcome == .scheduled)
    }

    @Test
    func deniedAuthorizationSchedulesNothing() async {
        let notificationCenter = ControllableNotificationCenter(
            authorizationStatus: .notDetermined,
            authorizationGranted: false,
            shouldSuspendNextAdd: false
        )
        let scheduler = UserNotificationRestTimerScheduler(
            notificationCenter: notificationCenter
        )

        let outcome = await scheduler.scheduleReminder(
            id: UUID(),
            deadline: Date().addingTimeInterval(30)
        )

        #expect(notificationCenter.authorizationRequestCount == 1)
        #expect(notificationCenter.pendingRequests.isEmpty)
        #expect(outcome == .authorizationDenied)
    }

    @Test
    func provisionalAuthorizationDoesNotPromiseAnAlert() async {
        let notificationCenter = ControllableNotificationCenter(
            authorizationStatus: .provisional,
            shouldSuspendNextAdd: false
        )
        let scheduler = UserNotificationRestTimerScheduler(
            notificationCenter: notificationCenter
        )

        let outcome = await scheduler.scheduleReminder(
            id: UUID(),
            deadline: Date().addingTimeInterval(30)
        )

        #expect(outcome == .alertsUnavailable)
        #expect(notificationCenter.pendingRequests.isEmpty)
    }

    @Test
    func passedDeadlineSchedulesNothing() async {
        let notificationCenter = ControllableNotificationCenter(
            shouldSuspendNextAdd: false
        )
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let scheduler = UserNotificationRestTimerScheduler(
            notificationCenter: notificationCenter,
            now: { now }
        )

        let outcome = await scheduler.scheduleReminder(
            id: UUID(),
            deadline: now.addingTimeInterval(-1)
        )

        #expect(outcome == .deadlinePassed)
        #expect(notificationCenter.pendingRequests.isEmpty)
    }

    @Test
    func recreatedSchedulerCanCancelPersistedRequest() async {
        let notificationCenter = ControllableNotificationCenter()
        let timerID = UUID()
        notificationCenter.insertPendingRequest(
            identifier: "restTimer.\(timerID.uuidString)"
        )

        let recreatedScheduler = UserNotificationRestTimerScheduler(
            notificationCenter: notificationCenter
        )
        recreatedScheduler.cancelReminder(id: timerID)

        #expect(notificationCenter.pendingRequests.isEmpty)
    }

    private func yieldUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if condition() {
                return
            }
            await Task.yield()
        }
        #expect(condition())
    }
}
