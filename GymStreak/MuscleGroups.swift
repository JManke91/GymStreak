import Foundation

/// Centralized muscle group definitions for the app
struct MuscleGroups {
    static let all: [String] = [
        // General
        "General",
        "Full Body",

        // Upper Body - Arms
        "Biceps",
        "Triceps",
        "Forearms",

        // Upper Body - Chest & Back
        "Chest",
        "Upper Back",
        "Lats",
        "Lower Back",

        // Upper Body - Shoulders
        "Shoulder",
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

    /// Returns an appropriate SF Symbol for the given muscle group
    static func icon(for muscleGroup: String) -> String {
        switch muscleGroup {
        // General
        case "General": return "figure.mixed.cardio"
        case "Full Body": return "figure.strengthtraining.traditional"

        // Arms
        case "Biceps", "Triceps", "Forearms": return "figure.arms.open"

        // Chest & Back
        case "Chest": return "figure.strengthtraining.traditional"
        case "Upper Back", "Lats", "Lower Back": return "figure.cooldown"

        // Shoulders
        case "Shoulder", "Front Delts", "Side Delts", "Rear Delts": return "figure.flexibility"

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
}
