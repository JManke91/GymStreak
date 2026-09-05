//
//  OnboardingChromePill.swift
//  GymStreak
//
//  A caption the tour adds *around* a preview. Not a piece of any app screen.
//  See docs/onboarding.md.
//

import SwiftUI

/// A small tinted capsule an onboarding slide pins to its preview.
///
/// **This exists nowhere in the app**, and that is the whole reason it is a
/// declared component rather than an inline `HStack` in one slide: a still
/// picture cannot say what a link is called or that a suggestion arrived on its
/// own, so the tour is allowed to caption it — but the caption has to be
/// recognisable as the tour's own voice rather than as a control the user will
/// go looking for. Step 3 uses it for the group's name, step 4 for "Automatic".
///
/// Its text should be either the app's own word for the thing (step 3 passes
/// `superset.label`) or plainly the tour talking; never an invented affordance.
struct OnboardingChromePill: View {

    let text: String
    /// The leading glyph, or `nil` for a word that needs none. Step 6's "BETA"
    /// marker is that case: there is no icon for "this feature is young", and a
    /// glyph would make a two-word status read as a control.
    var systemImage: String?
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }

            Text(text.uppercased())
                .font(.onyxMonoLabel)
                .tracking(1.3)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(color.opacity(0.38), lineWidth: 1))
    }
}
