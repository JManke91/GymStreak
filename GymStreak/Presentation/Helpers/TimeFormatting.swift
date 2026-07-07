import Foundation

/// Helper functions for consistent time formatting across the app
struct TimeFormatting {
    /// Formats a time interval in seconds to a readable string
    /// - Examples:
    ///   - 30s -> "30s"
    ///   - 60s -> "1m"
    ///   - 90s -> "1m 30s"
    ///   - 120s -> "2m"
    static func formatRestTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60

        if minutes == 0 {
            return "\(remainingSeconds)s"
        } else if remainingSeconds == 0 {
            return "\(minutes)m"
        } else {
            return "\(minutes)m \(remainingSeconds)s"
        }
    }

    /// Relative "last trained" label: "Today", "Yesterday", short relative
    /// ("3 days ago"), or the localized never-trained placeholder for nil.
    static func lastTrainedLabel(for date: Date?) -> String {
        guard let date else { return "routines.last_done.never".localized }
        if Calendar.current.isDateInToday(date) { return "date.today".localized }
        if Calendar.current.isDateInYesterday(date) { return "date.yesterday".localized }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale.current
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
