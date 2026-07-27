import Foundation

/// The 13 muscle regions the schematic muscle-map figure is drawn in.
///
/// This is a *rendering* vocabulary and is deliberately coarser than the app's
/// muscle-group keys (`MuscleGroups.allKeys`), which collapse onto it.
/// Distinct from `BodyRegion` (upper body / core / lower body), which only drives
/// muscle-group badge coloring.
enum MuscleMapRegion: String, CaseIterable, Hashable, Sendable {
    case trapezius
    case shoulders
    case chest
    case biceps
    case triceps
    case forearms
    case abs
    case back
    case lowerBack
    case glutes
    case quadriceps
    case hamstrings
    case calves
}

/// How a region contributed to an exercise: the primary mover, or a supporting one.
enum MuscleEngagement: String, Hashable, Sendable {
    case primary
    case secondary
}

extension MuscleMapRegion {

    /// Localized name of the region, for labels and VoiceOver. The regions are coarser than the
    /// app's muscle-group keys, so they carry their own `muscle_region.*` strings rather than
    /// borrowing `MuscleGroups.displayName(for:)`.
    var displayName: String {
        switch self {
        case .trapezius: "muscle_region.trapezius".localized
        case .shoulders: "muscle_region.shoulders".localized
        case .chest: "muscle_region.chest".localized
        case .biceps: "muscle_region.biceps".localized
        case .triceps: "muscle_region.triceps".localized
        case .forearms: "muscle_region.forearms".localized
        case .abs: "muscle_region.abs".localized
        case .back: "muscle_region.back".localized
        case .lowerBack: "muscle_region.lower_back".localized
        case .glutes: "muscle_region.glutes".localized
        case .quadriceps: "muscle_region.quadriceps".localized
        case .hamstrings: "muscle_region.hamstrings".localized
        case .calves: "muscle_region.calves".localized
        }
    }

    /// Resolves one of the app's muscle-group keys (`MuscleGroups.allKeys`) onto the region the
    /// figure draws it in. Returns `nil` for keys the schematic body has no belly for — those
    /// contribute no highlight rather than lighting up something approximate.
    init?(muscleGroupKey: String) {
        guard let region = Self.regionsByMuscleGroupKey[muscleGroupKey] else { return nil }
        self = region
    }

    /// Covers all 19 keys of `MuscleGroups.allKeys` except `General`, which is the seed
    /// catalogue's fallback and deliberately maps to nothing. `Hip Flexors` has no belly of its
    /// own in the design body and is folded into the nearest region it sits behind.
    private static let regionsByMuscleGroupKey: [String: MuscleMapRegion] = [
        "Upper Back": .trapezius,
        "Shoulders": .shoulders,
        "Front Delts": .shoulders,
        "Side Delts": .shoulders,
        "Rear Delts": .shoulders,
        "Chest": .chest,
        "Upper Chest": .chest,
        "Biceps": .biceps,
        "Triceps": .triceps,
        "Forearms": .forearms,
        "Abs": .abs,
        "Obliques": .abs,
        "Lats": .back,
        "Lower Back": .lowerBack,
        "Glutes": .glutes,
        "Quadriceps": .quadriceps,
        "Hip Flexors": .quadriceps,
        "Hamstrings": .hamstrings,
        "Calves": .calves,
    ]
}
