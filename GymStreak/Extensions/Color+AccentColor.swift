//
//  Color+AccentColor.swift
//  GymStreak
//
//  Created by Julian Manke on 12.12.25.
//

import SwiftUI

extension Color {
    static let electricPurple = Color(red: 139/255, green: 92/255, blue: 246/255)
    static let electricCyan = Color(red: 0/255, green: 212/255, blue: 255/255)

    /// Adaptive accent color that provides excellent contrast in both light and dark modes
    /// - Light mode: Uses electricPurple for a modern, vibrant appearance
    /// - Dark mode: Uses electricCyan for vibrant, modern appearance on dark backgrounds
    static let appAccent = Color(
        light: Color(red: 139/255, green: 92/255, blue: 246/255), // electricPurple
        dark: Color(red: 0/255, green: 212/255, blue: 255/255)    // electricCyan
    )
}

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor(light: UIColor(light), dark: UIColor(dark)))
    }
}

extension UIColor {
    convenience init(light: UIColor, dark: UIColor) {
        self.init { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return dark
            default:
                return light
            }
        }
    }
}
