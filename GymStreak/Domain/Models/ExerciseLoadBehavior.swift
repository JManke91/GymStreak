import Foundation

/// Describes what the number entered for a set represents.
///
/// Most exercises use added resistance. Counterweight machines are different:
/// their selected stack helps the user, so a smaller value is harder.
enum ExerciseLoadBehavior: String, Codable, CaseIterable, Hashable {
    case resistance
    case counterweightAssistance

    var isCounterweightAssistance: Bool {
        self == .counterweightAssistance
    }
}
