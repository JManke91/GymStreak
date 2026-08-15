//
//  OnyxProLockOverlay.swift
//  GymStreak
//
//  The blurred-preview lock every §8 C contextual gate reuses.
//  See docs/monetization-strategy.md §3 Rule 2 and docs/pro-subscription.md.
//

import SwiftUI

/// Renders real content behind a blur with a lock affordance and an unlock CTA.
///
/// **Why blur rather than hide.** The conversion engine is loss aversion against
/// data the user generated themselves (§3 Rule 2). A hidden feature produces no
/// loss; a blurred chart of *your own numbers* does. So the content stays
/// rendered — it is only made unreadable and non-interactive.
///
/// Purely presentational: it takes a `PaywallPlacement` (a value, for the
/// headline copy §8 C requires) and a callback. It never sees the entitlement
/// provider, the paywall presenter or a ViewModel — the caller decides *whether*
/// to lock and *what* unlocking does, typically
/// `{ paywallPresenter.present(.chartMetric) }`.
struct OnyxProLockOverlay<Content: View>: View {

    private let placement: PaywallPlacement
    private let onUnlock: () -> Void
    private let content: Content

    /// Reduce Transparency swaps the blur for an opaque scrim: a blur is a
    /// legibility hazard for exactly the users who turn that setting on, and the
    /// lock card sits on top of it.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        placement: PaywallPlacement,
        onUnlock: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
        self.onUnlock = onUnlock
        self.content = content()
    }

    private static var blurRadius: CGFloat { 14 }

    private var headline: String { placement.headlineKey.localized }

    var body: some View {
        // Overlays rather than a `ZStack`: a bare `Color` is infinitely greedy,
        // so as a stack sibling it would size the lock to the *proposal* instead
        // of to `content` and the locked branch would occupy more space than the
        // unlocked one. As an overlay the scrim inherits the content's geometry,
        // which is what keeps `.proLocked(true/false)` layout-identical.
        content
            .blur(radius: reduceTransparency ? 0 : Self.blurRadius)
            // `allowsHitTesting(false)` only silences this subtree's own hit
            // testing; `disabled(true)` is what stops an *enclosing*
            // `NavigationLink` or `Button` — the shape every chart and
            // deep-dive gate has — from carrying a tap on the blur through to
            // the gated screen, and what removes it from Full Keyboard Access.
            // Both `.overlay`s must stay *below* this `.disabled` — an overlay
            // attached after it is enabled, one attached before it is not
            // (measured, see docs/pro-subscription.md §5b). Reordering would
            // silently dim and deaden the unlock CTA.
            .allowsHitTesting(false)
            .disabled(true)
            .accessibilityHidden(true)
            .clipped()
            .overlay {
                // Keeps the lock card readable on top of bright chart content;
                // opaque when Reduce Transparency asks for it.
                DesignSystem.Colors.background
                    .opacity(reduceTransparency ? 0.94 : 0.55)
                    .allowsHitTesting(false)
            }
            .overlay { lockCard }
    }

    private var lockCard: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "lock.fill")
                .font(.onyxHeader)
                .foregroundStyle(DesignSystem.Colors.tint)

            Text(headline)
                .font(.onyxHeader)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Text("pro.lock.subtitle".localized)
                .font(.onyxCaption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button("pro.lock.cta".localized, action: onUnlock)
                .buttonStyle(.onyxProminent)
                .padding(.top, DesignSystem.Spacing.xs)
        }
        .padding(DesignSystem.Spacing.lg)
        // One VoiceOver element that says what is locked and how to unlock it —
        // a blur communicates nothing to a VoiceOver user, and the content
        // behind it is hidden from the accessibility tree on purpose.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("pro.lock.accessibility".localized(headline))
        .accessibilityHint("pro.lock.accessibility_hint".localized)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onUnlock() }
    }
}

// MARK: - Convenience modifier

extension View {

    /// Locks this view behind a blurred Pro preview when `isLocked` is `true`.
    ///
    /// Written as a modifier so a gate reads as one line at the call site:
    /// `chart.proLocked(!entitlements.state.isPro, placement: .chartMetric) { … }`.
    @ViewBuilder
    func proLocked(
        _ isLocked: Bool,
        placement: PaywallPlacement,
        onUnlock: @escaping () -> Void
    ) -> some View {
        if isLocked {
            OnyxProLockOverlay(placement: placement, onUnlock: onUnlock) { self }
        } else {
            self
        }
    }
}

// MARK: - Previews

private struct ProLockPreviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Estimated 1RM")
                .font(.onyxSubheadline)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("142.5 kg")
                .font(.onyxNumberLarge)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach([0.4, 0.55, 0.5, 0.7, 0.65, 0.85, 1.0], id: \.self) { height in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DesignSystem.Colors.tint)
                        .frame(height: 80 * height)
                }
            }
            .frame(height: 80)
        }
        .padding(DesignSystem.Dimensions.cardPadding)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusLG)
                .fill(DesignSystem.Colors.card)
        )
    }
}

#Preview("Lock overlay — dark") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        ProLockPreviewContent()
            .proLocked(true, placement: .chartMetric) { }
            .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Lock overlay — light") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        ProLockPreviewContent()
            .proLocked(true, placement: .chartWindow) { }
            .padding()
    }
    .preferredColorScheme(.light)
}

#Preview("Lock overlay — large type") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        ProLockPreviewContent()
            .proLocked(true, placement: .exerciseDeepDive) { }
            .padding()
    }
    .dynamicTypeSize(.accessibility1)
    .preferredColorScheme(.dark)
}

#Preview("Unlocked passthrough") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        ProLockPreviewContent()
            .proLocked(false, placement: .chartMetric) { }
            .padding()
    }
    .preferredColorScheme(.dark)
}
