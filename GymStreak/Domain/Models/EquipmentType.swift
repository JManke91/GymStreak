import Foundation

/// Equipment type for exercises
enum EquipmentType: String, Codable, CaseIterable {
    case dumbbell
    case barbell
    case machine

    /// Returns the localized display name for this equipment type
    var displayName: String {
        switch self {
        case .dumbbell: return "equipment.dumbbell".localized
        case .barbell: return "equipment.barbell".localized
        case .machine: return "equipment.machine".localized
        }
    }

    /// Returns an SF Symbol icon for this equipment type
    var icon: String {
        switch self {
        case .dumbbell: return "dumbbell.fill"
        case .barbell: return "figure.strengthtraining.traditional"
        case .machine: return "gearshape.fill"
        }
    }
}
