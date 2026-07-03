//
//  AICoachTheme.swift
//  GymStreak
//
//  Shared constants and helpers for all AI Coach UI surfaces.
//  Colors are derived from DesignSystem — no new hex values introduced.
//

import SwiftUI

/// Shared theme constants for AI Coach UI surfaces.
enum AICoachTheme {

    // MARK: - Colors

    /// Primary AI accent — matches `DesignSystem.Colors.tint` (#00FF85).
    static let accent: Color = DesignSystem.Colors.tint

    /// Warning/correlation accent — matches `DesignSystem.Colors.warning` (orange).
    static let warningAccent: Color = DesignSystem.Colors.warning

    // MARK: - Corner Radii

    /// Outer rounded rect corner radius for `AISurface`.
    static let surfaceCorner: CGFloat = 22

    /// Inner rounded rect corner radius for `AISurface` content area.
    static let innerCorner: CGFloat = 21

    // MARK: - Border

    /// Gradient border stroke width for `AISurface`.
    static let borderWidth: CGFloat = 1.5

    // MARK: - Typography

    /// Returns a monospaced font of the given size and weight.
    static func mono(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
