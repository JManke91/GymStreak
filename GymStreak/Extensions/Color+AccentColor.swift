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
    static let electricBlue = Color(red: 10/255, green: 132/255, blue: 255/255)

    /// App accent color - Electric Blue from Onyx Design System
    /// Uses DesignSystem.Colors.tint for consistency across the app
    static let appAccent = DesignSystem.Colors.tint
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
