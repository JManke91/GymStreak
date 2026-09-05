//
//  OnboardingInertPreview.swift
//  GymStreak
//
//  The one way an onboarding slide mounts a production component: as a picture
//  of itself. See docs/onboarding.md.
//

import SwiftUI

extension EnvironmentValues {

    /// Whether the surrounding view is being rendered as a still preview inside
    /// an onboarding slide rather than as the live screen.
    ///
    /// Read by production components that do something **on appear** — the
    /// thing `.allowsHitTesting(false)` cannot suppress, because nobody tapped.
    /// `ProgressiveOverloadBanner` is the first: it fires a success haptic in
    /// `onAppear`, and a tour that buzzes the phone while explaining a feature
    /// is a bug the user cannot even attribute.
    ///
    /// The default is `false`, so a component that never learns about this
    /// keeps behaving exactly as it does today.
    @Entry var isOnboardingPreview: Bool = false
}

extension View {

    /// Mounts this view inside an onboarding plate as a still image of the real
    /// screen: nothing is tappable, nothing acts on appear, and it speaks to
    /// VoiceOver as one element that names the screen it is a preview of.
    ///
    /// Three things, and why each is here rather than at the call site:
    ///
    /// - **`allowsHitTesting(false)`** rather than `disabled(true)`: `disabled`
    ///   changes how some controls *draw*, and the whole point of the plate is
    ///   that it looks like the shipped screen. Hit testing off blocks taps,
    ///   drags and focus alike, so the sample values can never be edited and no
    ///   tap haptic can fire.
    /// - **`isOnboardingPreview`** for the side effects a dead pointer does not
    ///   stop — see the environment value above.
    /// - **One accessibility element.** An expanded routine card is ~20 stops of
    ///   steppers and remove buttons that lead nowhere. The copy below the plate
    ///   is what carries the meaning; the plate is the illustration beside it.
    ///
    /// - Parameter description: what the preview shows, already localized.
    func onboardingInertPreview(describing description: String) -> some View {
        self
            .environment(\.isOnboardingPreview, true)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(description)
    }
}
