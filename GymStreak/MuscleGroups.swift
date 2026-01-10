import Foundation

/// Centralized muscle group definitions for the app
struct MuscleGroups {
    /// Returns all muscle groups as localized strings
    static var all: [String] {
        return [
            // General
            "muscle.general".localized,
            "muscle.full_body".localized,

            // Upper Body - Arms
            "muscle.biceps".localized,
            "muscle.triceps".localized,
            "muscle.forearms".localized,

            // Upper Body - Chest & Back
            "muscle.chest".localized,
            "muscle.upper_back".localized,
            "muscle.lats".localized,
            "muscle.lower_back".localized,

            // Upper Body - Shoulders
            "muscle.front_delts".localized,
            "muscle.side_delts".localized,
            "muscle.rear_delts".localized,

            // Core
            "muscle.abs".localized,
            "muscle.obliques".localized,

            // Lower Body
            "muscle.quadriceps".localized,
            "muscle.hamstrings".localized,
            "muscle.glutes".localized,
            "muscle.calves".localized,
            "muscle.hip_flexors".localized
        ]
    }

    /// Returns an appropriate SF Symbol for the given muscle group
    /// Works with both localized and English muscle group names
    static func icon(for muscleGroup: String) -> String {
        // Normalize the muscle group name by checking against all localized values
        let normalizedGroup = normalizeMuscleName(muscleGroup)

        switch normalizedGroup {
        // General
        case "General", "Full Body": return "figure.strengthtraining.traditional"

        // Arms
        case "Biceps", "Triceps", "Forearms": return "figure.arms.open"

        // Chest & Back
        case "Chest": return "figure.strengthtraining.traditional"
        case "Upper Back", "Lats", "Lower Back": return "figure.cooldown"

        // Shoulders
        case "Front Delts", "Side Delts", "Rear Delts": return "figure.flexibility"

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

    /// Helper to normalize muscle group names (convert localized back to English key for icon lookup)
    private static func normalizeMuscleName(_ name: String) -> String {
        let mappings: [String: String] = [
            "muscle.general".localized: "General",
            "muscle.full_body".localized: "Full Body",
            "muscle.biceps".localized: "Biceps",
            "muscle.triceps".localized: "Triceps",
            "muscle.forearms".localized: "Forearms",
            "muscle.chest".localized: "Chest",
            "muscle.upper_back".localized: "Upper Back",
            "muscle.lats".localized: "Lats",
            "muscle.lower_back".localized: "Lower Back",
            "muscle.front_delts".localized: "Front Delts",
            "muscle.side_delts".localized: "Side Delts",
            "muscle.rear_delts".localized: "Rear Delts",
            "muscle.abs".localized: "Abs",
            "muscle.obliques".localized: "Obliques",
            "muscle.quadriceps".localized: "Quadriceps",
            "muscle.hamstrings".localized: "Hamstrings",
            "muscle.glutes".localized: "Glutes",
            "muscle.calves".localized: "Calves",
            "muscle.hip_flexors".localized: "Hip Flexors"
        ]

        return mappings[name] ?? name
    }
}
