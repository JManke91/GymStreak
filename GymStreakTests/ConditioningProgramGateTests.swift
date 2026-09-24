//
//  ConditioningProgramGateTests.swift
//  GymStreakTests
//
//  Ticket 08 (docs/fight-conditioning.md): the P12 depth gate on the 12-week
//  conditioning program. Phase 1 is free in full; Phases 2–3 are Pro, and what
//  a locked week withholds is the *prescription* — never a logged session,
//  never the enrollment, and never anything the watch or the runner does.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

private struct NoGateCloud: ConditioningProgramCloudStore {
    func data(forKey key: String) -> Data? { nil }
    func set(_ data: Data, forKey key: String) {}
}

@MainActor
private final class RecordingGateWatchPublisher: ConditioningWatchPublishing {
    private(set) var offers: [ConditioningWatchOffer] = []
    func publishConditioningOffer(_ offer: ConditioningWatchOffer) { offers.append(offer) }
}

// MARK: - The policy

@Suite
struct ConditioningProgramGatingPolicyTests {

    /// Every entitlement that grants Pro, and the two reasons the gate does not
    /// apply at all. `.founder` is the §7 case that must behave exactly like a
    /// paying subscriber.
    @Test("A week past the free depth is locked only for a gated free user")
    func lockDependsOnEntitlement() {
        for state in ProEntitlementState.allCases {
            #expect(
                ConditioningProgramGatingPolicy.isWeekLocked(5, isPro: state.isPro, isGatingEnabled: true)
                    == (state == .free),
                "unexpected lock for \(state)"
            )
        }
        // The kill switch off is the pre-ticket-08 app, for everyone.
        #expect(!ConditioningProgramGatingPolicy.isWeekLocked(12, isPro: false, isGatingEnabled: false))
    }

    @Test("Weeks 1–4 are free, 5–12 are not")
    func freeDepthIsTheFirstFourWeeks() {
        for week in 1...ConditioningProgramContent.weekCount {
            #expect(
                ConditioningProgramGatingPolicy.isWeekLocked(week, isPro: false, isGatingEnabled: true)
                    == (week > ProFeatureCaps.freeConditioningProgramWeeks),
                "unexpected lock for week \(week)"
            )
        }
    }

    /// The cap is a number so it can be retuned in a one-line diff, which means
    /// nothing structural stops it from landing mid-phase. This is that stop:
    /// the free depth must end exactly where Phase 1 does, or a free user is cut
    /// off in the middle of a block.
    @Test("The free depth covers Phase 1 exactly")
    func freeConditioningWeeksCoverPhaseOne() throws {
        let firstPhase = try #require(ConditioningProgramContent.phases.first)
        #expect(ProFeatureCaps.freeConditioningProgramWeeks == firstPhase.weeks.upperBound)
        #expect(!ConditioningProgramGatingPolicy.isPhaseLocked(firstPhase, isPro: false, isGatingEnabled: true))
        for phase in ConditioningProgramContent.phases.dropFirst() {
            #expect(ConditioningProgramGatingPolicy.isPhaseLocked(phase, isPro: false, isGatingEnabled: true))
        }
    }

    @Test("The last-free-week cue fires in week 4, and only for a gated user")
    func lastFreeWeekCue() {
        #expect(ConditioningProgramGatingPolicy.isLastFreeWeek(4, isPro: false, isGatingEnabled: true))
        #expect(!ConditioningProgramGatingPolicy.isLastFreeWeek(3, isPro: false, isGatingEnabled: true))
        #expect(!ConditioningProgramGatingPolicy.isLastFreeWeek(5, isPro: false, isGatingEnabled: true))
        // A Founder told their program is about to end is exactly what §7's
        // grant exists to prevent.
        #expect(!ConditioningProgramGatingPolicy.isLastFreeWeek(4, isPro: true, isGatingEnabled: true))
        #expect(!ConditioningProgramGatingPolicy.isLastFreeWeek(4, isPro: false, isGatingEnabled: false))
    }
}

// MARK: - The dashboard, the watch and the add-on

@Suite @MainActor
struct ConditioningProgramGateTests {
    let calendar = ProgramTestCalendar.make()

    /// Enrols so that `week` is the week in progress and is already three days
    /// old, which is what makes "a session logged earlier this week" land in it.
    private func makeViewModel(
        week: Int,
        state: ProEntitlementState,
        isGatingEnabled: Bool = true,
        now: Date
    ) -> (
        program: ConditioningProgramViewModel,
        watch: RecordingGateWatchPublisher,
        paywalls: RecordingPaywallPresenter,
        entitlements: StubProEntitlements,
        records: any ConditioningRecordRepository,
        container: ModelContainer
    ) {
        let container = InMemoryModelContainer.make()
        let context = container.mainContext
        let watch = RecordingGateWatchPublisher()
        let paywalls = RecordingPaywallPresenter()
        let entitlements = StubProEntitlements(state: state)
        let records = SwiftDataConditioningRecordRepository(modelContext: context)
        let program = ConditioningProgramViewModel(
            store: ConditioningProgramStore(
                defaults: UserDefaults(suiteName: UUID().uuidString)!,
                cloud: NoGateCloud(),
                observesExternalChanges: false
            ),
            conditioningRecords: records,
            workoutSessions: SwiftDataWorkoutSessionRepository(modelContext: context),
            watch: watch,
            gate: ConditioningProgramGate(
                entitlements: entitlements,
                paywalls: paywalls,
                isGatingEnabled: isGatingEnabled
            ),
            calendar: calendar,
            now: { now }
        )
        program.enroll(
            startDate: now.addingTimeInterval(-Double((week - 1) * 7 + 3) * 86_400),
            experience: .experienced,
            sparsHard: false
        )
        return (program, watch, paywalls, entitlements, records, container)
    }

    private static let now = ProgramTestCalendar.date(2026, 9, 23, 9)

    // MARK: Free

    @Test("A free user's Phase 1 is untouched: nothing locked, a session to start, the watch served")
    func phaseOneIsFree() throws {
        let sut = makeViewModel(week: 2, state: .free, now: Self.now)
        _ = sut.container
        let dashboard = try #require(sut.program.dashboard)

        #expect(!dashboard.isLocked)
        #expect(!sut.program.isProgramLocked)
        #expect(dashboard.suggestion != nil)
        #expect(!dashboard.isLastFreeWeek)
        #expect(try #require(sut.watch.offers.last).sessions.isEmpty == false)
    }

    @Test("Week 4 carries the placement-D cue, and nothing is locked yet")
    func lastFreeWeekNudges() throws {
        let sut = makeViewModel(week: 4, state: .free, now: Self.now)
        _ = sut.container
        let dashboard = try #require(sut.program.dashboard)

        #expect(dashboard.isLastFreeWeek)
        #expect(!dashboard.isLocked)
        #expect(dashboard.suggestion != nil)
        // The cue is a hint, never a paywall: nothing was raised.
        #expect(sut.paywalls.presentedPlacements.isEmpty)
    }

    @Test("Week 5 locks the plan: blurrable targets stay, everything actionable goes")
    func phaseTwoIsLockedForFree() throws {
        let sut = makeViewModel(week: 5, state: .free, now: Self.now)
        _ = sut.container
        let dashboard = try #require(sut.program.dashboard)

        #expect(dashboard.isLocked)
        #expect(sut.program.isProgramLocked)
        // Blurred, never hidden (§3 Rule 2) — the view needs the real targets.
        #expect(!dashboard.progress.isEmpty)
        #expect(dashboard.currentWeek?.number == 5)
        // Nothing to start, nothing to offer, nothing to add on.
        #expect(dashboard.suggestion == nil)
        #expect(try #require(sut.watch.offers.last).sessions.isEmpty)
        #expect(sut.program.addOn(finishedAt: Self.now, isHeavyLowerBody: false) == .none)
        // A gate asks, it never presents by itself.
        #expect(sut.paywalls.presentedPlacements.isEmpty)
    }

    @Test("The unlock CTA raises the conditioning placement and nothing else")
    func unlockRaisesThePlacement() {
        let sut = makeViewModel(week: 5, state: .free, now: Self.now)
        _ = sut.container

        sut.program.requestProgramUnlock()

        #expect(sut.paywalls.presentedPlacements == [.conditioningProgram])
    }

    // MARK: Entitled

    @Test("Trial, subscriber, lifetime and Founder all continue into Phase 2 seamlessly")
    func entitledUsersAreNeverLocked() throws {
        // A free trial reports the subscription entitlement — RevenueCat makes
        // no distinction the app can act on, and none is wanted here.
        for state in ProEntitlementState.allCases where state != .free {
            let sut = makeViewModel(week: 5, state: state, now: Self.now)
            _ = sut.container
            let dashboard = try #require(sut.program.dashboard)

            #expect(!dashboard.isLocked, "locked for \(state)")
            #expect(dashboard.suggestion != nil, "no suggestion for \(state)")
            #expect(try #require(sut.watch.offers.last).sessions.isEmpty == false, "empty watch offer for \(state)")
            #expect(sut.program.addOn(finishedAt: Self.now, isHeavyLowerBody: false) != .none, "no add-on for \(state)")
        }
    }

    @Test("With the kill switch off, a free user runs the whole program")
    func gatingDisabledLocksNothing() throws {
        let sut = makeViewModel(week: 9, state: .free, isGatingEnabled: false, now: Self.now)
        _ = sut.container
        let dashboard = try #require(sut.program.dashboard)

        #expect(!dashboard.isLocked)
        #expect(dashboard.suggestion != nil)
        #expect(!dashboard.isLastFreeWeek)
    }

    // MARK: Lapse

    /// §7 Rule 4: a lapse narrows the view and takes nothing away. The
    /// enrollment keeps advancing, the logged sessions stay, and a resubscribe
    /// puts the user back exactly where they were — no migration in either
    /// direction.
    @Test("A lapsed subscriber keeps every logged session and their place in the program")
    func lapseKeepsProgressAndLogs() throws {
        let sut = makeViewModel(week: 6, state: .subscription, now: Self.now)
        _ = sut.container

        let logged = ConditioningRecord(
            id: UUID(),
            startTime: Self.now.addingTimeInterval(-3_600),
            endTime: Self.now.addingTimeInterval(-1_800),
            sessionTypeRaw: ConditioningSessionDefinition.ID.lactic30.rawValue,
            titleSnapshot: "Lactic 30/120",
            energySystemRaw: ConditioningEnergySystem.lactic.rawValue,
            modalityRaw: ConditioningModality.rower.rawValue,
            effortRaw: ConditioningEffort.hardRepeatable.rawValue,
            roundsCompleted: 6,
            roundsPlanned: 6,
            setsPlanned: 0,
            workInterval: 30,
            restInterval: 120,
            endedEarly: false
        )
        sut.records.insert(logged)
        try sut.records.save()
        sut.program.refresh()

        let before = try #require(sut.program.dashboard)
        #expect(!before.isLocked)
        let enrollmentBefore = before.enrollment

        sut.entitlements.state = .free
        sut.program.refresh()
        let after = try #require(sut.program.dashboard)

        #expect(after.isLocked)
        // Nothing was rewound, deleted or restarted.
        #expect(after.enrollment == enrollmentBefore)
        #expect(after.currentWeek?.number == before.currentWeek?.number)
        #expect(sut.records.fetchAll().contains { $0.id == logged.id })
        // And it is fully reversible.
        sut.entitlements.state = .lifetime
        sut.program.refresh()
        #expect(try #require(sut.program.dashboard).isLocked == false)
        #expect(try #require(sut.program.dashboard).suggestion != nil)
    }

    // MARK: The free residue

    /// §3 Rules 3 and 4 in one assertion: the gate must not reach the library of
    /// single sessions, which is what a locked user still trains with.
    @Test("Single sessions stay available to a locked user")
    func singleSessionsStayFree() {
        let sut = makeViewModel(week: 8, state: .free, now: Self.now)
        _ = sut.container

        #expect(sut.program.isProgramLocked)
        #expect(!ConditioningLibrary.sessions.isEmpty)
    }
}
