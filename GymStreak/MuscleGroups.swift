import Foundation
import SwiftUI

/// Body regions for color-coded muscle group categorization
enum BodyRegion {
    case upperBody
    case core
    case lowerBody

    var color: Color {
        switch self {
        case .upperBody: return .blue
        case .core: return .orange
        case .lowerBody: return .green
        }
    }
}

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

    /// Returns the body region for a muscle group
    static func bodyRegion(for muscleGroup: String) -> BodyRegion {
        switch muscleGroup {
        // Upper Body - Arms, Chest, Back, Shoulders
        case "Biceps", "Triceps", "Forearms",
             "Chest", "Upper Chest",
             "Upper Back", "Lats", "Lower Back",
             "Shoulders", "Front Delts", "Side Delts", "Rear Delts":
            return .upperBody

        // Core
        case "Abs", "Obliques":
            return .core

        // Lower Body
        case "Quadriceps", "Hamstrings", "Glutes", "Calves", "Hip Flexors":
            return .lowerBody

        default:
            return .upperBody
        }
    }

    /// Returns body region for the first muscle group in an array
    static func bodyRegion(for muscleGroups: [String]) -> BodyRegion {
        guard let first = muscleGroups.first else {
            return .upperBody
        }
        return bodyRegion(for: first)
    }

    /// Returns a short abbreviation for a muscle group
    static func abbreviation(for muscleGroup: String) -> String {
        switch muscleGroup {
        // Arms
        case "Biceps": return "BI"
        case "Triceps": return "TRI"
        case "Forearms": return "FA"

        // Chest
        case "Chest", "Upper Chest": return "CH"

        // Back
        case "Upper Back": return "UB"
        case "Lats": return "LAT"
        case "Lower Back": return "LB"

        // Shoulders
        case "Shoulders": return "SH"
        case "Front Delts": return "FD"
        case "Side Delts": return "SD"
        case "Rear Delts": return "RD"

        // Core
        case "Abs": return "ABS"
        case "Obliques": return "OBL"

        // Lower Body
        case "Quadriceps": return "QD"
        case "Hamstrings": return "HM"
        case "Glutes": return "GL"
        case "Calves": return "CV"
        case "Hip Flexors": return "HF"

        default: return "EX"
        }
    }

    /// Returns abbreviation for the first muscle group in an array
    static func abbreviation(for muscleGroups: [String]) -> String {
        guard let first = muscleGroups.first else {
            return "EX"
        }
        return abbreviation(for: first)
    }
}
