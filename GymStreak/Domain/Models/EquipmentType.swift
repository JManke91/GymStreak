import Foundation

/// Equipment type for exercises
enum EquipmentType: String, Codable, CaseIterable {
    case dumbbell
    case barbell
    case machine
    case cable
    case bodyweight

    /// Returns the localized display name for this equipment type
    var displayName: String {
        switch self {
        case .dumbbell: return "equipment.dumbbell".localized
        case .barbell: return "equipment.barbell".localized
        case .machine: return "equipment.machine".localized
        case .cable: return "equipment.cable".localized
        case .bodyweight: return "equipment.bodyweight".localized
        }
    }

    /// Returns an SF Symbol icon for this equipment type
    var icon: String {
        switch self {
        case .dumbbell: return "dumbbell.fill"
        case .barbell: return "figure.strengthtraining.traditional"
        case .machine: return "gearshape.fill"
        case .cable: return "arrow.up.arrow.down"
        case .bodyweight: return "figure.strengthtraining.functional"
        }
    }
}
