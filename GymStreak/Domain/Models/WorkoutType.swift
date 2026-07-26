//
//  WorkoutType.swift
//  GymStreak
//

import Foundation

/// Classification used by the History redesign to color-code cards and calendar dots.
/// Derived from a routine's name rather than stored on the model, so no schema migration is needed.
enum WorkoutType: String, CaseIterable, Sendable {
    case push
    case pull
    case legs
    case core
    case fullBody
    case upper
    case lower
    case cardio
    case other

    /// Short display label shown in chips (uppercased by the chip itself).
    var label: String {
        switch self {
        case .push:     return "history.type.push".localized
        case .pull:     return "history.type.pull".localized
        case .legs:     return "history.type.legs".localized
        case .core:     return "history.type.core".localized
        case .fullBody: return "history.type.full_body".localized
        case .upper:    return "history.type.upper".localized
        case .lower:    return "history.type.lower".localized
        case .cardio:   return "history.type.cardio".localized
        case .other:    return "history.type.other".localized
        }
    }

    // The accent color per type is presentation styling and lives in
    // Presentation/Views/Components/DomainColorStyling.swift.

    /// Classifies a workout from its routine name. Case-insensitive substring match.
    /// Recognizes English and German keywords (the app ships both localizations).
    static func classify(routineName: String) -> WorkoutType {
        let name = routineName.lowercased()

        // Order matters: check combined / specific patterns first.
        if name.contains("full") || name.contains("ganzkörper") || name.contains("ganzkoerper") {
            return .fullBody
        }
        if name.contains("upper") || name.contains("oberkörper") || name.contains("oberkoerper") {
            return .upper
        }
        if name.contains("lower") || name.contains("unterkörper") || name.contains("unterkoerper") {
            return .lower
        }
        if name.contains("push") || name.contains("drück") || name.contains("druck") {
            return .push
        }
        if name.contains("pull") || name.contains("zieh") {
            return .pull
        }
        if name.contains("leg") || name.contains("bein") {
            return .legs
        }
        if name.contains("core") || name.contains("abs") || name.contains("bauch") {
            return .core
        }
        if name.contains("cardio") || name.contains("run") || name.contains("lauf") {
            return .cardio
        }
        return .other
    }
}
