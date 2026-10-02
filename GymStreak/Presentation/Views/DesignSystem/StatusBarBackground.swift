//
//  StatusBarBackground.swift
//  GymStreak
//
//  See docs/routine-programs.md ("Status-bar strip").
//

import SwiftUI

extension View {
    /// For screens that hide the navigation bar (the Routines tab and the
    /// program screens): nothing else covers the status bar, so scrolled
    /// content shows through under the clock. Paints
    /// the background behind the top safe area only. The colour must sit in a
    /// `background` of the zero-height view: `.ignoresSafeArea` cannot grow a
    /// view with a fixed `.frame(height: 0)`, so that version paints nothing.
    func statusBarBackground() -> some View {
        overlay(alignment: .top) {
            Color.clear
                .frame(height: 0)
                .background(DesignSystem.Colors.background.ignoresSafeArea(edges: .top))
        }
    }
}
