//
//  OnyxProLockOverlay.swift
//  GymStreak
//
//  The blurred-preview lock every §8 C contextual gate reuses.
//  See docs/monetization-strategy.md §3 Rule 2 and docs/pro-subscription.md §5b.
//

import SwiftUI

/// Renders real content behind a blur with a lock affordance and an unlock CTA.
///
/// **Why blur rather than hide.** The conversion engine is loss aversion against
/// data the user generated themselves (§3 Rule 2). A hidden feature produces no
/// loss; a blurred chart of *your own numbers* does. So the content stays
/// rendered — it is only made unreadable and non-interactive.
///
/// **Why the lock is a sibling of the content, not an overlay on top of it.**
/// The first version centred a fixed-size lock card over the content, which
/// works only while the content is taller than the card. It is not: the
/// conditioning program's weekly card is two rows, and the lock overflowed it in
/// every direction — glyph above the card, button below it, headline truncated
/// (docs/fight-conditioning.md, ticket 08). Here the content and the lock panel
/// are the two children of a `VStack(spacing: 0)`, so the container is
/// **content-plus-panel tall by construction** and there is no arrangement in
/// which the panel can overflow. Short content (two rows) and tall content (a
/// year of chart) compose identically; only the amount of visible plan differs.
///
/// Purely presentational: it takes a `PaywallPlacement` (a value, for the
/// headline copy §8 C requires) and a callback. It never sees the entitlement
/// provider, the paywall presenter or a ViewModel — the caller decides *whether*
/// to lock and *what* unlocking does, typically
/// `{ paywallPresenter.present(.chartMetric) }`.
struct OnyxProLockOverlay<Content: View>: View {

    private let placement: PaywallPlacement
    private let subtitle: String?
    private let footnote: String?
    private let onUnlock: () -> Void
    private let content: Content

    /// Reduce Transparency swaps the blur for an opaque scrim: a blur is a
    /// legibility hazard for exactly the users who turn that setting on.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Reduce Motion skips the lock-in animation and starts settled.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the one-shot lock-in: the plan is briefly legible, then blurs.
    /// Latched, so scrolling the lock off and back on does not replay it.
    @State private var hasSettled = false

    init(
        placement: PaywallPlacement,
        subtitle: String? = nil,
        footnote: String? = nil,
        onUnlock: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
        self.subtitle = subtitle
        self.footnote = footnote
        self.onUnlock = onUnlock
        self.content = content()
    }

    /// Low enough that the shapes of the user's own plan still shimmer through —
    /// which is the entire point — and high enough that no word or number can be
    /// made out. 14 over near-black content produced flat black, i.e. no loss at
    /// all; 7 still read as smoke once the scrim was over it.
    private static var blurRadius: CGFloat { 5 }

    /// The fade from legible plan into the opaque panel.
    ///
    /// **Shorter than `contentMinHeight` on purpose.** While the two were equal
    /// the gradient covered every pixel of a short subject — the weekly card is
    /// ~112pt — so nothing was ever seen un-scrimmed and the lock read as an
    /// empty grey box. The difference between the two is the clear strip.
    private static var scrimHeight: CGFloat { 76 }

    /// The floor under the content, so a one-row subject still has a clear strip
    /// above the fade rather than starting mid-gradient.
    private static var contentMinHeight: CGFloat { 96 }

    private static var lockInDuration: TimeInterval { 0.45 }

    private var headline: String { placement.headlineKey.localized }

    private var isBlurred: Bool { hasSettled && !reduceTransparency }

    var body: some View {
        // A `VStack`, not an overlay and not a bottom-aligned `ZStack`. An
        // overlay does not grow its container, so the block could overflow it —
        // the bug this replaces. A bottom-aligned stack would instead park short
        // content *behind* the opaque panel, hiding the very plan the gate is
        // supposed to show. In a stack the two are simply sequential: the
        // container is content + panel tall, always, whatever either measures.
        VStack(spacing: 0) {
            content
                .blur(radius: isBlurred ? Self.blurRadius : 0)
                // `allowsHitTesting(false)` silences this subtree's own hit
                // testing; `disabled(true)` is what stops an *enclosing*
                // `NavigationLink` or `Button` — the shape every chart and
                // deep-dive gate has — from carrying a tap through to the gated
                // screen, and what removes it from Full Keyboard Access.
                .allowsHitTesting(false)
                .disabled(true)
                .accessibilityHidden(true)
                // The floor is what guarantees a one-row subject still has a
                // clear strip above the fade; a blur also bleeds past its own
                // bounds, so the frame is clipped.
                .frame(maxWidth: .infinity, minHeight: Self.contentMinHeight, alignment: .top)
                .overlay(alignment: .bottom) { scrim }
                .overlay { reduceTransparencyWash }
                .clipped()

            lockPanel
                .opacity(hasSettled ? 1 : 0)
        }
        // Clipped, but **not** filled. The panel paints its own `card`
        // background and the scrim's tail is opaque `card`, so a fill here would
        // be invisible behind a caller that is already an `OnyxCard` and would
        // paint an unwanted opaque block behind one that is not — the chart
        // card, whose own surface is a different colour and radius. The clip is
        // still needed: without it the panel's square bottom corners would cut
        // the corners off a rounded card caller.
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusLG))
        .onAppear {
            guard !hasSettled else { return }
            if reduceMotion {
                hasSettled = true
            } else {
                withAnimation(.easeOut(duration: Self.lockInDuration)) { hasSettled = true }
            }
        }
    }

    /// Reduce Transparency makes the plan unreadable by **coverage** rather than
    /// by softening: a blur is a legibility hazard for exactly the users who turn
    /// that setting on, so the subject is covered instead of blurred.
    @ViewBuilder
    private var reduceTransparencyWash: some View {
        if reduceTransparency {
            DesignSystem.Colors.card
                .opacity(hasSettled ? 0.94 : 0)
                .allowsHitTesting(false)
        }
    }

    /// Carries the edge between the plan and the panel without drawing a line.
    /// It sits on the *content*, so the plan fades into the panel's colour
    /// rather than stopping against it.
    private var scrim: some View {
        LinearGradient(
            colors: [
                DesignSystem.Colors.card.opacity(0),
                DesignSystem.Colors.card.opacity(0.55),
                DesignSystem.Colors.card
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: Self.scrimHeight)
        .opacity(hasSettled ? 1 : 0)
        .allowsHitTesting(false)
    }

    private var lockPanel: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            proChip

            Text(headline)
                .font(.onyxHeader)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                // Without this the headline truncates instead of wrapping, which
                // silently drops the half of the copy §8 C exists to show.
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle ?? "pro.lock.subtitle".localized)
                .font(.onyxFootnote)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onUnlock) {
                Text("pro.lock.cta".localized)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.onyxProminent)
            .padding(.top, DesignSystem.Spacing.xs)

            if let footnote {
                Text(footnote)
                    .font(.onyxCaption2)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignSystem.Dimensions.cardPadding)
        .padding(.top, DesignSystem.Spacing.md)
        .padding(.bottom, DesignSystem.Dimensions.cardPadding)
        .background(DesignSystem.Colors.card)
        // One VoiceOver element that says what is locked and how to unlock it —
        // a blur communicates nothing to a VoiceOver user, and the content
        // behind it is hidden from the accessibility tree on purpose.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("pro.lock.accessibility".localized(headline))
        .accessibilityHint("pro.lock.accessibility_hint".localized)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onUnlock() }
    }

    /// Outlined rather than `OnyxProBadge`'s filled capsule, deliberately. That
    /// badge marks an *entry point* that leads somewhere gated; here the user has
    /// already arrived, and a second solid tint block directly above a full-width
    /// tint button competes with the one thing that should be tapped.
    private var proChip: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "lock.fill")
                .font(.onyxCaption2.bold())
            Text("pro.badge.label".localized)
                .font(.onyxCaption2.bold())
        }
        .foregroundStyle(DesignSystem.Colors.tint)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(DesignSystem.Colors.tint.opacity(0.14))
        )
        .overlay(
            Capsule().strokeBorder(DesignSystem.Colors.tint.opacity(0.34), lineWidth: 1)
        )
    }
}

// MARK: - Convenience modifier

extension View {

    /// Locks this view behind a blurred Pro preview when `isLocked` is `true`.
    ///
    /// Written as a modifier so a gate reads as one line at the call site:
    /// `chart.proLocked(!entitlements.state.isPro, placement: .chartMetric) { … }`.
    ///
    /// - Parameters:
    ///   - subtitle: overrides the generic "included in Pro" line where a gate
    ///     has something specific to say about what is waiting. The default
    ///     keeps the other gates on one shared string.
    ///   - footnote: what the user keeps regardless, rendered *inside* the lock.
    ///     It belongs here rather than under the card: §10's guardrails put
    ///     free-user retention above conversion, and the reassurance only works
    ///     where the gate is felt.
    @ViewBuilder
    func proLocked(
        _ isLocked: Bool,
        placement: PaywallPlacement,
        subtitle: String? = nil,
        footnote: String? = nil,
        onUnlock: @escaping () -> Void
    ) -> some View {
        if isLocked {
            OnyxProLockOverlay(
                placement: placement,
                subtitle: subtitle,
                footnote: footnote,
                onUnlock: onUnlock
            ) { self }
        } else {
            self
        }
    }
}
