//
//  Color+AccentColor.swift
//  GymStreak
//
//  Created by Julian Manke on 12.12.25.
//

import SwiftUI

extension Color {
    static let neonGreen = Color(red: 0/255, green: 255/255, blue: 136/255)
    static let gymGreen = Color(red: 0/255, green: 204/255, blue: 106/255)

    /// Adaptive accent color that provides good contrast in both light and dark modes
    /// - Light mode: Uses gymGreen (darker) for better contrast on light backgrounds
    /// - Dark mode: Uses neonGreen (brighter) for vibrant appearance on dark backgrounds
    static let appAccent = Color(
        light: Color(red: 0/255, green: 204/255, blue: 106/255), // gymGreen
        dark: Color(red: 0/255, green: 255/255, blue: 136/255)   // neonGreen
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
