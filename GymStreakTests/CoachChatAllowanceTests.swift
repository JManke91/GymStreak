//
//  CoachChatAllowanceTests.swift
//  GymStreakTests
//
//  P3 — the five-messages-per-month Coach Chat taster (docs/monetization-strategy.md
//  §4.2a P3, §4.3, §7, §8 C/D). Three assertions carry the ticket: a device that
//  cannot run Apple Intelligence is never paywalled, a failed generation costs
//  the user nothing, and a counter cannot be reset by reinstalling the app or by
//  moving the device clock backwards.
//

import Testing
import Foundation
@testable import GymStreak

@Suite
@MainActor
struct CoachChatAllowanceTests {

    // MARK: - The free monthly taster

    @Test("A free user gets five messages, and the sixth raises the coachChat paywall")
    func fiveMessagesThenPaywall() {
        let harness = makeHarness()

        for index in 0..<ProFeatureCaps.freeCoachChatMessagesPerMonth {
            #expect(harness.gate.requestGeneration()?.didConsume == true)
            #expect(harness.gate.consumedCount == index + 1)
        }

        #expect(harness.gate.isExhausted)
        #expect(harness.gate.requestGeneration() == nil)
        #expect(harness.paywalls.presentedPlacements == [.coachChat])
        // The refused request consumed nothing — the user is at five, not six.
        #expect(harness.gate.consumedCount == ProFeatureCaps.freeCoachChatMessagesPerMonth)
    }

    @Test("Opening the chat with nothing left raises the paywall without consuming")
    func openingExhaustedChatPaywalls() {
        let harness = makeHarness()
        spend(harness.gate, ProFeatureCaps.freeCoachChatMessagesPerMonth)
        harness.paywalls.reset()

        harness.gate.presentPaywallIfExhausted()

        #expect(harness.paywalls.presentedPlacements == [.coachChat])
        #expect(harness.gate.consumedCount == ProFeatureCaps.freeCoachChatMessagesPerMonth)
    }

    @Test("Opening the chat with messages left raises nothing — history is free to read")
    func openingChatWithAllowanceLeftIsSilent() {
        let harness = makeHarness()
        spend(harness.gate, 4)

        harness.gate.presentPaywallIfExhausted()

        #expect(harness.paywalls.presentedPlacements.isEmpty)
        #expect(harness.gate.remaining == 1)
    }

    @Test("A failed generation gives the unit back")
    func failedGenerationRefunds() {
        let harness = makeHarness()

        guard let ticket = harness.gate.requestGeneration() else {
            Issue.record("the first message must be allowed")
            return
        }
        #expect(harness.gate.consumedCount == 1)

        harness.gate.refund(ticket)

        #expect(harness.gate.consumedCount == 0)
        #expect(harness.gate.remaining == ProFeatureCaps.freeCoachChatMessagesPerMonth)
    }

    @Test("A refund can restore the message that hit the wall")
    func refundAtTheCapReopensTheAllowance() {
        let harness = makeHarness()
        spend(harness.gate, 4)

        guard let ticket = harness.gate.requestGeneration() else {
            Issue.record("the fifth message must be allowed")
            return
        }
        #expect(harness.gate.isExhausted)

        harness.gate.refund(ticket)

        #expect(harness.gate.isExhausted == false)
        #expect(harness.gate.requestGeneration()?.didConsume == true)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    // MARK: - The §8 D nudge

    @Test("The nudge appears at one remaining and stays once the allowance is spent")
    func nudgeAppearsOnTheLastMessageAndStays() {
        let harness = makeHarness()

        #expect(harness.gate.nudgeState == nil)
        spend(harness.gate, 3)
        #expect(harness.gate.nudgeState == nil)

        spend(harness.gate, 1)
        #expect(harness.gate.nudgeState == .lastRemaining(consumed: 4, limit: 5))

        spend(harness.gate, 1)
        #expect(harness.gate.nudgeState == .exhausted(consumed: 5, limit: 5))
    }

    @Test("Buying Pro removes the nudge with no reload")
    func nudgeFollowsTheEntitlement() {
        let harness = makeHarness()
        spend(harness.gate, 5)
        #expect(harness.gate.nudgeState == .exhausted(consumed: 5, limit: 5))

        harness.entitlements.state = .subscription

        #expect(harness.gate.nudgeState == nil)
        #expect(harness.gate.isExhausted == false)
    }

    // MARK: - Entitlement states

    @Test("Pro, lifetime and Founder are unmetered", arguments: [
        ProEntitlementState.subscription, .lifetime, .founder
    ])
    func proUsersAreUnmetered(state: ProEntitlementState) {
        let harness = makeHarness(state: state)

        for _ in 0..<20 {
            #expect(harness.gate.requestGeneration()?.didConsume == false)
        }

        #expect(harness.gate.isMetered == false)
        #expect(harness.gate.isExhausted == false)
        #expect(harness.gate.consumedCount == 0)
        #expect(harness.gate.nudgeState == nil)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test("A lapsed subscriber returns to the free taster with their chat intact")
    func lapseReturnsToTheTaster() {
        let harness = makeHarness(state: .subscription)
        for _ in 0..<20 { _ = harness.gate.requestGeneration() }

        harness.entitlements.state = .free

        // Nothing was counted while they were Pro, so the taster starts whole.
        #expect(harness.gate.consumedCount == 0)
        #expect(harness.gate.remaining == ProFeatureCaps.freeCoachChatMessagesPerMonth)
        spend(harness.gate, ProFeatureCaps.freeCoachChatMessagesPerMonth)
        #expect(harness.gate.requestGeneration() == nil)
        #expect(harness.paywalls.presentedPlacements == [.coachChat])
    }

    // MARK: - Availability comes first

    @Test("A device without Apple Intelligence is never paywalled and never metered")
    func unavailableDeviceIsNeverPaywalled() {
        let harness = makeHarness(availability: .deviceNotEligible)

        for _ in 0..<20 {
            #expect(harness.gate.requestGeneration()?.didConsume == false)
        }
        harness.gate.presentPaywallIfExhausted()

        #expect(harness.paywalls.presentedPlacements.isEmpty)
        #expect(harness.gate.isMetered == false)
        #expect(harness.gate.nudgeState == nil)
        #expect(harness.gate.consumedCount == 0)
    }

    @Test("An allowance already spent stays spent when the model becomes unavailable")
    func unavailabilityDoesNotClearTheCount() {
        let harness = makeHarness()
        spend(harness.gate, 5)

        harness.availability.state = .modelNotReady
        #expect(harness.gate.requestGeneration()?.didConsume == false)
        harness.availability.state = .available

        #expect(harness.gate.consumedCount == 5)
        #expect(harness.gate.isExhausted)
    }

    // MARK: - The kill switch

    @Test("With the kill switch off chat is unmetered and unchanged from today")
    func killSwitchOffBehavesAsBefore() {
        let harness = makeHarness(isGatingEnabled: false)

        for _ in 0..<20 {
            #expect(harness.gate.requestGeneration()?.didConsume == false)
        }
        harness.gate.presentPaywallIfExhausted()

        #expect(harness.gate.isMetered == false)
        #expect(harness.gate.isExhausted == false)
        #expect(harness.gate.nudgeState == nil)
        #expect(harness.gate.consumedCount == 0)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    // MARK: - The store: months, clocks and reinstalls

    @Test("The counter resets at the calendar month boundary")
    func countResetsOnTheFirstOfTheMonth() {
        let clock = MutableClock(date: date(year: 2026, month: 8, day: 31))
        let store = makeStore(clock: clock)

        store.consume(.coachChat)
        store.consume(.coachChat)
        #expect(store.consumedCount(for: .coachChat) == 2)

        clock.date = date(year: 2026, month: 9, day: 1)

        #expect(store.consumedCount(for: .coachChat) == 0)
        store.consume(.coachChat)
        #expect(store.consumedCount(for: .coachChat) == 1)
    }

    @Test("Moving the device clock backwards does not restore a consumed allowance")
    func clockRollbackDoesNotRefillTheAllowance() {
        let clock = MutableClock(date: date(year: 2026, month: 8, day: 20))
        let store = makeStore(clock: clock)
        for _ in 0..<5 { store.consume(.coachChat) }

        // Backwards inside the same month, then into the previous one.
        clock.date = date(year: 2026, month: 8, day: 1)
        #expect(store.consumedCount(for: .coachChat) == 5)

        clock.date = date(year: 2026, month: 7, day: 15)
        #expect(store.consumedCount(for: .coachChat) == 5)

        // And the month the user really spent is still the one being written to,
        // so returning to it does not show a second, parallel count.
        store.consume(.coachChat)
        clock.date = date(year: 2026, month: 8, day: 20)
        #expect(store.consumedCount(for: .coachChat) == 6)
    }

    @Test("A reinstall restores the consumed count from iCloud KVS")
    func reinstallRestoresTheCountFromTheCloud() {
        let clock = MutableClock(date: date(year: 2026, month: 8, day: 12))
        let cloud = FakeAllowanceCloudStore()
        let store = makeStore(clock: clock, cloud: cloud)
        for _ in 0..<4 { store.consume(.coachChat) }

        // Deleting the app takes the App Group container with it; KVS survives.
        let reinstalled = MonthlyAllowanceStore(
            defaults: makeDefaults(),
            cloud: cloud,
            calendar: .current,
            now: { clock.date }
        )

        #expect(reinstalled.consumedCount(for: .coachChat) == 4)
    }

    @Test("A cloud record from a month already over does not carry into the new one")
    func staleCloudRecordDoesNotCarryOver() {
        let cloud = FakeAllowanceCloudStore()
        cloud.records[MeteredAISurface.coachChat.storageKey] =
            MonthlyAllowanceRecord(month: "2026-07", count: 5)
        let clock = MutableClock(date: date(year: 2026, month: 8, day: 2))

        let store = makeStore(clock: clock, cloud: cloud)

        #expect(store.consumedCount(for: .coachChat) == 0)
    }

    @Test("An absent record is cached, so a view body never falls through to iCloud")
    func absentRecordIsCachedLikeAPresentOne() {
        let cloud = FakeAllowanceCloudStore()
        let store = makeStore(cloud: cloud)

        // The state every user is in before their first message — and, while the
        // kill switch is off, the state of every user there is.
        for _ in 0..<10 { _ = store.consumedCount(for: .coachChat) }
        #expect(cloud.readCount == 1)

        store.consume(.coachChat)
        for _ in 0..<10 { _ = store.consumedCount(for: .coachChat) }
        #expect(cloud.readCount == 1)
    }

    @Test("A Pro user and a kill-switch-off build never read the allowance store")
    func unmeteredUsersNeverTouchTheStore() {
        for state in [ProEntitlementState.subscription, .free] {
            let counting = CountingAllowanceTracker()
            let gate = AICoachAllowanceGate(
                surface: .coachChat,
                entitlements: StubProEntitlements(state: state),
                paywalls: RecordingPaywallPresenter(),
                allowance: counting,
                availability: StubAICoachAvailability(),
                // Free + gating off is the shipped app; subscription + gating on
                // is the paying user. Neither may reach the store from a body.
                isGatingEnabled: state.isPro
            )

            _ = gate.nudgeState
            _ = gate.isExhausted

            #expect(counting.readCount == 0)
        }
    }

    @Test("A refund never takes the count below zero")
    func refundBelowZeroIsIgnored() {
        let store = makeStore()

        store.refund(.coachChat)
        store.refund(.coachChat)

        #expect(store.consumedCount(for: .coachChat) == 0)
    }

    @Test("The three surfaces count independently")
    func surfacesAreIndependent() {
        let store = makeStore()

        store.consume(.coachChat)
        store.consume(.coachChat)
        store.consume(.periodRecap)

        #expect(store.consumedCount(for: .coachChat) == 2)
        #expect(store.consumedCount(for: .periodRecap) == 1)
        #expect(store.consumedCount(for: .exerciseDeepDive) == 0)
    }

    @Test("Every metered surface has its own storage key, limit and placement")
    func surfaceMappingIsDistinct() {
        let keys = Set(MeteredAISurface.allCases.map(\.storageKey))
        let placements = Set(MeteredAISurface.allCases.map(\.placement))

        #expect(keys.count == MeteredAISurface.allCases.count)
        #expect(placements.count == MeteredAISurface.allCases.count)
        #expect(MeteredAISurface.coachChat.freeMonthlyLimit == ProFeatureCaps.freeCoachChatMessagesPerMonth)
        #expect(MeteredAISurface.periodRecap.freeMonthlyLimit == ProFeatureCaps.freePeriodRecapsPerMonth)
        #expect(MeteredAISurface.exerciseDeepDive.freeMonthlyLimit == ProFeatureCaps.freeExerciseDeepDivesPerMonth)
    }

    @Test("A record survives a round trip through its stored form")
    func recordRoundTrips() {
        let record = MonthlyAllowanceRecord(month: "2026-08", count: 3)

        #expect(MonthlyAllowanceRecord(rawValue: record.rawValue) == record)
        #expect(MonthlyAllowanceRecord(rawValue: "garbage") == nil)
        #expect(MonthlyAllowanceRecord(rawValue: "2026-08") == nil)
    }

    // MARK: - The policy, with no store at all

    @Test("A retuned cap moves the wall and the nudge with it", arguments: [1, 3, 10])
    func policyHonoursARetunedLimit(limit: Int) {
        #expect(AIAllowancePolicy.isExhausted(
            consumed: limit - 1, limit: limit, isPro: false, isGatingEnabled: true
        ) == false)
        #expect(AIAllowancePolicy.isExhausted(
            consumed: limit, limit: limit, isPro: false, isGatingEnabled: true
        ))
        #expect(AIAllowancePolicy.nudgeState(
            consumed: limit - 1, limit: limit, isPro: false, isGatingEnabled: true
        ) == .lastRemaining(consumed: limit - 1, limit: limit))
    }

    @Test("A count above a retuned-down cap still reads as exhausted, not as a negative")
    func policyClampsAnOvershotCount() {
        #expect(AIAllowancePolicy.remaining(consumed: 9, limit: 5) == 0)
        #expect(AIAllowancePolicy.nudgeState(
            consumed: 9, limit: 5, isPro: false, isGatingEnabled: true
        ) == .exhausted(consumed: 5, limit: 5))
    }

    // MARK: - Harness

    private struct Harness {
        let gate: AICoachAllowanceGate
        let entitlements: StubProEntitlements
        let paywalls: RecordingPaywallPresenter
        let availability: StubAICoachAvailability
        let store: MonthlyAllowanceStore
    }

    /// Defaults to gating **on**, unlike the shipped app: with the real
    /// `ProGating.isEnabled` every test here would pass by proving the gate is
    /// inert rather than that it is correct.
    private func makeHarness(
        state: ProEntitlementState = .free,
        availability: AICoachAvailabilityState = .available,
        isGatingEnabled: Bool = true
    ) -> Harness {
        let entitlements = StubProEntitlements(state: state)
        let paywalls = RecordingPaywallPresenter()
        let availabilityStub = StubAICoachAvailability(state: availability)
        let store = makeStore()
        return Harness(
            gate: AICoachAllowanceGate(
                surface: .coachChat,
                entitlements: entitlements,
                paywalls: paywalls,
                allowance: store,
                availability: availabilityStub,
                isGatingEnabled: isGatingEnabled
            ),
            entitlements: entitlements,
            paywalls: paywalls,
            availability: availabilityStub,
            store: store
        )
    }

    private func makeStore(
        clock: MutableClock = MutableClock(date: Date()),
        cloud: FakeAllowanceCloudStore = FakeAllowanceCloudStore()
    ) -> MonthlyAllowanceStore {
        MonthlyAllowanceStore(
            defaults: makeDefaults(),
            cloud: cloud,
            calendar: .current,
            now: { clock.date }
        )
    }

    /// A throwaway suite per test — the real store writes the App Group suite,
    /// which every other test and the developer's simulator share.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "CoachChatAllowanceTests.\(UUID().uuidString)")!
    }

    private func spend(_ gate: AICoachAllowanceGate, _ count: Int) {
        for _ in 0..<count { _ = gate.requestGeneration() }
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

// MARK: - Doubles

/// A movable "now", so the month boundary and a rolled-back device clock are
/// testable without touching the system date.
private final class MutableClock: @unchecked Sendable {

    /// `@unchecked` with a written invariant: every read and write happens on
    /// the test's `@MainActor` isolation; the box exists only because the store
    /// takes an escaping `() -> Date`.
    var date: Date

    init(date: Date) {
        self.date = date
    }
}

/// Counts every read, and holds nothing: the point is to prove that an
/// unmetered user's gate never asks the counters anything at all.
@MainActor
private final class CountingAllowanceTracker: MonthlyAllowanceTracking {

    private(set) var readCount = 0

    func consumedCount(for surface: MeteredAISurface) -> Int {
        readCount += 1
        return 0
    }

    func consume(_ surface: MeteredAISurface) {}

    func refund(_ surface: MeteredAISurface) {}
}

/// Stands in for `NSUbiquitousKeyValueStore`, which has exactly one usable
/// instance whose contents survive deleting the app — writing the real one from
/// a test would stamp the developer's simulator for good.
private final class FakeAllowanceCloudStore: AllowanceCloudStore, @unchecked Sendable {

    /// Same invariant as `MutableClock`: main-actor-only access, boxed because
    /// `AllowanceCloudStore` is `Sendable` by protocol.
    var records: [String: MonthlyAllowanceRecord] = [:]

    /// Reads are counted because the store's "answers from memory" contract is
    /// load-bearing: the real cloud store synchronizes with iCloud, and the
    /// count is read from a computed property a view body evaluates.
    private(set) var readCount = 0

    func record(forKey key: String) -> MonthlyAllowanceRecord? {
        readCount += 1
        return records[key]
    }

    func setRecord(_ record: MonthlyAllowanceRecord, forKey key: String) {
        records[key] = record
    }
}
