import Foundation

/// Protocol for types that participate in superset grouping
protocol SupersetGroupable {
    var supersetId: UUID? { get }
    var order: Int { get }
}

extension RoutineExercise: SupersetGroupable {}
extension WorkoutExercise: SupersetGroupable {}

/// Computes display labels (A, B, C...) for superset groups at render time.
/// Labels are assigned in the order supersets first appear in the exercise list.
/// (The label → color mapping is presentation styling and lives in
/// Presentation/Views/Components/DomainColorStyling.swift.)
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
}
