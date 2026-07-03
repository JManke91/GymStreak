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
}
