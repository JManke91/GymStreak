import Foundation

/// Centralized muscle group definitions for the app
/// Muscle groups are stored as English keys internally and localized for display
struct MuscleGroups {
    /// All muscle group keys (English, for storage)
    static let allKeys: [String] = [
        // Upper Body - Arms
        "Biceps",
        "Triceps",
        "Forearms",
        // Upper Body - Chest & Back
        "Chest",
        "Upper Chest",
        "Upper Back",
        "Lats",
        "Lower Back",
        // Upper Body - Shoulders
        "Shoulders",
        "Front Delts",
        "Side Delts",
        "Rear Delts",
        // Core
        "Abs",
        "Obliques",
        // Lower Body
        "Quadriceps",
        "Hamstrings",
        "Glutes",
        "Calves",
        "Hip Flexors"
    ]

    /// Localization key mapping
    private static let localizationKeys: [String: String] = [
        "Biceps": "muscle.biceps",
        "Triceps": "muscle.triceps",
        "Forearms": "muscle.forearms",
        "Chest": "muscle.chest",
        "Upper Chest": "muscle.upper_chest",
        "Upper Back": "muscle.upper_back",
        "Lats": "muscle.lats",
        "Lower Back": "muscle.lower_back",
        "Shoulders": "muscle.shoulders",
        "Front Delts": "muscle.front_delts",
        "Side Delts": "muscle.side_delts",
        "Rear Delts": "muscle.rear_delts",
        "Abs": "muscle.abs",
        "Obliques": "muscle.obliques",
        "Quadriceps": "muscle.quadriceps",
        "Hamstrings": "muscle.hamstrings",
        "Glutes": "muscle.glutes",
        "Calves": "muscle.calves",
        "Hip Flexors": "muscle.hip_flexors"
    ]

    /// Returns the localized display name for a muscle group key
    static func displayName(for key: String) -> String {
        if let locKey = localizationKeys[key] {
            return locKey.localized
        }
        return key
    }

    /// Returns an appropriate SF Symbol for the given muscle group
    static func icon(for muscleGroup: String) -> String {
        switch muscleGroup {
        // Arms
        case "Biceps", "Triceps", "Forearms": return "figure.arms.open"

        // Chest & Back
        case "Chest", "Upper Chest": return "figure.strengthtraining.traditional"
        case "Upper Back", "Lats", "Lower Back": return "figure.cooldown"

        // Shoulders
        case "Shoulders", "Front Delts", "Side Delts", "Rear Delts": return "figure.flexibility"

        // Core
        case "Abs", "Obliques": return "figure.core.training"

        // Lower Body
        case "Quadriceps", "Hamstrings": return "figure.walk"
        case "Glutes": return "figure.run"
        case "Calves": return "figure.stairs"
        case "Hip Flexors": return "figure.flexibility"

        default: return "figure.mixed.cardio"
        }
    }

    /// Returns icon for the first muscle group in an array
    static func icon(for muscleGroups: [String]) -> String {
        guard let first = muscleGroups.first else {
            return "figure.mixed.cardio"
        }
        return icon(for: first)
    }

    /// Returns formatted display string for multiple muscle groups
    static func displayString(for muscleGroups: [String]) -> String {
        muscleGroups.map { displayName(for: $0) }.joined(separator: ", ")
    }
}
