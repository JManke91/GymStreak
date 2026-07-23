import Foundation

enum RestTimerReminderOutcome: Equatable {
    case scheduled
    case authorizationDenied
    case alertsUnavailable
    case deadlinePassed
    case failed
    case cancelled
}

@MainActor
protocol RestTimerReminderScheduling {
    func scheduleReminder(
        id: UUID,
        deadline: Date
    ) async -> RestTimerReminderOutcome

    func cancelReminder(id: UUID)
}
