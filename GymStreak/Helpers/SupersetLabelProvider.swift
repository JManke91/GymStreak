import SwiftUI

/// Protocol for types that participate in superset grouping
protocol SupersetGroupable {
    var supersetId: UUID? { get }
    var order: Int { get }
}

extension RoutineExercise: SupersetGroupable {}
extension WorkoutExercise: SupersetGroupable {}

/// Computes display labels (A, B, C...) and colors for superset groups at render time.
/// Labels are assigned in the order supersets first appear in the exercise list.
enum SupersetLabelProvider {
    /// Returns a mapping from supersetId → letter label ("A", "B", "C", ...)
    static func labels<T: SupersetGroupable>(for exercises: [T]) -> [UUID: String] {
        let sorted = exercises.sorted { $0.order < $1.order }
        var labelMap: [UUID: String] = [:]
        var nextIndex = 0

        for exercise in sorted {
            guard let supersetId = exercise.supersetId else { continue }
            if labelMap[supersetId] == nil {
                let letter = String(Character(UnicodeScalar(65 + nextIndex)!)) // A=65
                labelMap[supersetId] = letter
                nextIndex += 1
            }
        }
        return labelMap
    }

    /// Color for a given superset letter
    static func color(for letter: String) -> Color {
        let colors: [Color] = [
            DesignSystem.Colors.tint,
            Color(red: 94/255, green: 92/255, blue: 230/255),   // indigo
            Color(red: 255/255, green: 159/255, blue: 10/255),  // orange
            Color(red: 0/255, green: 122/255, blue: 255/255),   // blue
            Color(red: 255/255, green: 55/255, blue: 95/255),   // pink
        ]
        guard let ascii = letter.first?.asciiValue else {
            return DesignSystem.Colors.tint
        }
        let index = Int(ascii) - 65
        return colors[index % colors.count]
    }
}
