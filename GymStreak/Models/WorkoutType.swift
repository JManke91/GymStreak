//
//  WorkoutType.swift
//  GymStreak
//

import SwiftUI

/// Classification used by the History redesign to color-code cards and calendar dots.
/// Derived from a routine's name rather than stored on the model, so no schema migration is needed.
enum WorkoutType: String, CaseIterable {
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

    /// Accent color used on cards, calendar dots, and chips.
    var color: Color {
        switch self {
        case .push:     return Color(red: 48/255, green: 217/255, blue: 124/255)   // mint
        case .pull:     return Color(red: 90/255, green: 180/255, blue: 255/255)   // blue
        case .legs:     return Color(red: 200/255, green: 140/255, blue: 255/255)  // purple
        case .core:     return Color(red: 255/255, green: 159/255, blue: 90/255)   // orange
        case .fullBody: return DesignSystem.Colors.tint
        case .upper:    return Color(red: 255/255, green: 180/255, blue: 90/255)   // amber
        case .lower:    return Color(red: 180/255, green: 120/255, blue: 255/255)  // violet
        case .cardio:   return Color(red: 255/255, green: 107/255, blue: 107/255)  // red
        case .other:    return DesignSystem.Colors.tint
        }
    }

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
