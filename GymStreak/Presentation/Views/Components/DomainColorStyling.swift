import SwiftUI

// Color styling for Domain types. Lives in Presentation so the Domain layer
// stays free of SwiftUI — Domain types expose semantics, this file maps them
// to the visual design.

extension BodyRegion {
    var color: Color {
        switch self {
        case .upperBody: return .blue
        case .core: return .orange
        case .lowerBody: return .green
        }
    }
}

extension WorkoutType {
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
}

extension SupersetLabelProvider {
    /// Color for a given superset letter ("A", "B", ...).
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
