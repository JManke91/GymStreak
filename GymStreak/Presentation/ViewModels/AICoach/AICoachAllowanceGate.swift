//
//  AICoachAllowanceGate.swift
//  GymStreak
//
//  One metered AI surface's gate: availability first, then the entitlement,
//  then this month's allowance. Shared by P3 (Coach Chat) and, from ticket 09,
//  P4/P5. See docs/pro-subscription.md §5e.
//

import Foundation

/// Answers "may this generation run?" for one `MeteredAISurface`, and owns the
/// consequences of the answer: consuming a unit, giving it back, and raising the
/// surface's paywall.
///
/// It exists as its own type rather than as three methods on
/// `CoachChatViewModel` because ticket 09 needs exactly the same decision for
/// two more surfaces, and because the chat's ViewModel cannot be tested through
/// the real `CoachChatService` (a singleton over an on-device model that is
/// unavailable in a test process). The gate takes no service, so the acceptance
/// criteria are assertable directly against it.
///
/// **Availability is checked before everything else.** A device that cannot run
/// Apple Intelligence must never be shown a paywall for it (§4.3): unavailable
/// is a disappointment, not a conversion opportunity. So on an unavailable
/// device this gate allows every request, meters nothing, and the surface's own
/// existing unavailable state is what the user sees.
@MainActor
final class AICoachAllowanceGate {

    /// Proof that a generation was admitted, and whether it cost the user a unit.
    ///
    /// The gate hands one out instead of returning `Bool` because the caller has
    /// to be able to give the unit back — a failed generation, or one that never
    /// started — and only the ticket knows whether there was anything to give
    /// back. Without it, a refund after an *unmetered* request (Pro, gating off,
    /// no Apple Intelligence) would silently hand the user a free unit.
    struct Ticket: Equatable {
        let surface: MeteredAISurface
        let didConsume: Bool
    }

    private let surface: MeteredAISurface
    private let entitlements: any ProEntitlementProviding
    private let paywalls: any PaywallPresenting
    private let allowance: any MonthlyAllowanceTracking
    private let availability: any AICoachAvailabilityProviding
    private let isGatingEnabled: Bool
    private let limit: Int

    /// - Parameters:
    ///   - isGatingEnabled: injected rather than read from `ProGating` inside
    ///     the checks, for the same reason `PaywallPresenter` and
    ///     `RoutinesViewModel` inject it: with the shipped switch baked in,
    ///     every test would pass by proving the gate is inert.
    ///   - limit: overridable so the §4.4 / §11 retune of a taster cap is
    ///     assertable at a boundary other than today's constant.
    init(
        surface: MeteredAISurface,
        entitlements: any ProEntitlementProviding,
        paywalls: any PaywallPresenting,
        allowance: any MonthlyAllowanceTracking,
        availability: any AICoachAvailabilityProviding,
        isGatingEnabled: Bool = ProGating.isEnabled,
        limit: Int? = nil
    ) {
        self.surface = surface
        self.entitlements = entitlements
        self.paywalls = paywalls
        self.allowance = allowance
        self.availability = availability
        self.isGatingEnabled = isGatingEnabled
        self.limit = limit ?? surface.freeMonthlyLimit
    }

    // MARK: - State

    /// `true` when this user is subject to the monthly allowance at all.
    var isMetered: Bool {
        availability.isAvailable
            && AIAllowancePolicy.isMetered(
                isPro: entitlements.isPro,
                isGatingEnabled: isGatingEnabled
            )
    }

    var consumedCount: Int { allowance.consumedCount(for: surface) }

    var remaining: Int {
        AIAllowancePolicy.remaining(consumed: consumedCount, limit: limit)
    }

    /// `true` when the next generation raises the paywall instead of running.
    var isExhausted: Bool {
        isMetered && remaining == 0
    }

    /// The §8 placement D hint, or `nil` when none belongs on screen.
    ///
    /// Computed, not stored: `entitlements` is `@Observable`, so reading it here
    /// during a view body's evaluation is what makes a purchase or a lapse
    /// remove or restore the hint with no refetch. It counts nothing, allocates
    /// no formatter, and the allowance store answers from memory by contract.
    /// The `isMetered` guard comes **before** `consumedCount`, deliberately: a
    /// Pro user, and every user while the kill switch is off, must not touch the
    /// allowance store at all from a view body.
    var nudgeState: AIAllowancePolicy.NudgeState? {
        guard isMetered else { return nil }
        return AIAllowancePolicy.nudgeState(
            consumed: consumedCount,
            limit: limit,
            isPro: entitlements.isPro,
            isGatingEnabled: isGatingEnabled
        )
    }

    // MARK: - Actions

    /// Admits a generation, consuming one unit — or refuses it and raises the
    /// surface's paywall.
    ///
    /// Consumption happens **here, at the start of the generation**, and is
    /// undone by `refund(_:)` if it never got going or failed. The alternative
    /// (consume on success) would let a user fire an unbounded number of
    /// concurrent-ish generations before any of them lands.
    func requestGeneration() -> Ticket? {
        guard isMetered else { return Ticket(surface: surface, didConsume: false) }
        guard remaining > 0 else {
            paywalls.present(surface.placement)
            return nil
        }
        allowance.consume(surface)
        return Ticket(surface: surface, didConsume: true)
    }

    /// Gives back the unit a ticket consumed. A no-op for an unmetered ticket.
    func refund(_ ticket: Ticket) {
        guard ticket.didConsume else { return }
        allowance.refund(ticket.surface)
    }

    /// Raises the paywall when the surface is *opened* with nothing left (§8 C —
    /// "open Coach Chat at 0 remaining"). Consumes nothing: opening a screen is
    /// never a unit, and reading what is already there is always free (Rule 4).
    func presentPaywallIfExhausted() {
        guard isExhausted else { return }
        paywalls.present(surface.placement)
    }
}
