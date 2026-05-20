//
//  ProactivePromptCoordinator.swift
//  GymStreak
//
//  Decides whether to show the proactive monthly period recap prompt.
//  Logic is kept in a dedicated service so TrainingsTabView remains a pure view.
//

import Foundation
import SwiftData

/// Determines whether the proactive monthly recap prompt should be shown.
///
/// Conditions (all must be true):
/// 1. `AICoachPreferences.shared.isProactiveMonthlyEffectivelyEnabled`
/// 2. `AICoachAvailability.shared.isAvailable`
/// 3. User has ≥ 3 sessions in the previous completed month.
/// 4. The prompt has not already been shown for this calendar-month boundary
///    (`lastProactivePromptShownForPeriodId != currentPeriodId`).
/// 5. The user has not already dismissed/viewed it this in-memory session.
@Observable
@MainActor
final class ProactivePromptCoordinator {

    // MARK: - Singleton

    static let shared = ProactivePromptCoordinator()
    private init() {}

    // MARK: - Public state

    /// `true` when the prompt card should be shown.
    private(set) var shouldShow: Bool = false

    /// The label for the previous completed month (e.g. "April 2026").
    private(set) var monthLabel: String = ""

    /// Headline stats for the previous month for the card subline.
    private(set) var sessionCount: Int = 0
    private(set) var totalVolumeTons: Double = 0
    private(set) var newPRCount: Int = 0

    // MARK: - Private

    /// Tracks whether the user already dismissed during this app session.
    private var dismissedThisSession: Bool = false

    // MARK: - Evaluation

    /// Call this whenever the session list changes (e.g. on appear or after workout save).
    func evaluate(sessions: [WorkoutSession], prCountBySession: [UUID: Int]) {
        guard !dismissedThisSession else { return }

        let preferences = AICoachPreferences.shared
        guard preferences.isProactiveMonthlyEffectivelyEnabled else {
            shouldShow = false
            return
        }

        guard AICoachAvailability.shared.isAvailable else {
            shouldShow = false
            return
        }

        let calendar = Calendar.current
        let now = Date()

        // Previous completed month identifier "yyyy-MM"
        guard let prevMonthDate = calendar.date(byAdding: .month, value: -1, to: now),
              let prevInterval = calendar.dateInterval(of: .month, for: prevMonthDate) else {
            shouldShow = false
            return
        }

        let periodId = periodIdentifier(for: prevInterval.start, calendar: calendar)

        // Already shown for this period?
        if preferences.lastProactivePromptShownForPeriodId == periodId {
            shouldShow = false
            return
        }

        // Sessions in the previous month
        let prevSessions = sessions.filter { s in
            s.endTime != nil && s.startTime >= prevInterval.start && s.startTime < prevInterval.end
        }
        guard prevSessions.count >= 3 else {
            shouldShow = false
            return
        }

        // Populate display stats
        sessionCount = prevSessions.count
        totalVolumeTons = prevSessions.reduce(0) { $0 + $1.totalVolume } / 1000.0
        newPRCount = prevSessions.reduce(0) { $0 + (prCountBySession[$1.id] ?? 0) }

        // Human-readable month label
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        monthLabel = fmt.string(from: prevInterval.start)

        shouldShow = true
    }

    // MARK: - Dismiss actions

    /// Called when the user taps the primary CTA ("Jetzt ansehen") or the close/Später button.
    func dismiss() {
        dismissedThisSession = true
        shouldShow = false

        // Stamp so the prompt doesn't reappear until next month boundary.
        let calendar = Calendar.current
        let now = Date()
        if let prevMonthDate = calendar.date(byAdding: .month, value: -1, to: now),
           let prevInterval = calendar.dateInterval(of: .month, for: prevMonthDate) {
            let id = periodIdentifier(for: prevInterval.start, calendar: calendar)
            AICoachPreferences.shared.lastProactivePromptShownForPeriodId = id
        }
    }

    // MARK: - Helpers

    private func periodIdentifier(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }
}
