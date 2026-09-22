//
//  ConditioningWatchOfferTests.swift
//  GymStreakTests
//
//  Ticket 06 (docs/fight-conditioning.md): what the iPhone offers the watch —
//  the week's open sessions derived from the program dashboard, the heart-rate
//  range only for users who have one, the wire mapping, and the offer riding
//  the routine application context without clobbering it.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@MainActor
private final class RecordingWatchPublisher: ConditioningWatchPublishing {
    private(set) var offers: [ConditioningWatchOffer] = []
    func publishConditioningOffer(_ offer: ConditioningWatchOffer) { offers.append(offer) }
}

private struct NoProgramCloud: ConditioningProgramCloudStore {
    func data(forKey key: String) -> Data? { nil }
    func set(_ data: Data, forKey key: String) {}
}

@Suite @MainActor
struct ConditioningWatchOfferTests {
    let calendar = ProgramTestCalendar.make()

    private func makeViewModel(
        profile: HeartRateProfile?,
        now: Date
    ) -> (ConditioningProgramViewModel, RecordingWatchPublisher, ModelContainer) {
        let container = InMemoryModelContainer.make()
        let context = container.mainContext
        let profiles = HeartRateProfileStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        profiles.heartRateProfile = profile
        let publisher = RecordingWatchPublisher()
        let viewModel = ConditioningProgramViewModel(
            store: ConditioningProgramStore(
                defaults: UserDefaults(suiteName: UUID().uuidString)!,
                cloud: NoProgramCloud(),
                observesExternalChanges: false
            ),
            conditioningRecords: SwiftDataConditioningRecordRepository(modelContext: context),
            workoutSessions: SwiftDataWorkoutSessionRepository(modelContext: context),
            watch: publisher,
            heartRateProfiles: profiles,
            calendar: calendar,
            now: { now }
        )
        return (viewModel, publisher, container)
    }

    @Test("Enrolled: the week's open sessions reach the watch, today's suggestion first, valid until the week ends")
    func openSessionsSuggestionFirst() throws {
        let now = ProgramTestCalendar.date(2026, 9, 23, 9)
        let (viewModel, publisher, container) = makeViewModel(profile: HeartRateProfile(age: 30), now: now)
        _ = container
        viewModel.enroll(startDate: ProgramTestCalendar.date(2026, 9, 21), experience: .beginner, sparsHard: false)

        let offer = try #require(publisher.offers.last)
        let week = try #require(viewModel.dashboard?.currentWeek)
        let offered: Set<String> = Set(offer.sessions.map { $0.plan.definition.id.rawValue })
        let planned: Set<String> = Set(week.targets.map { $0.session.rawValue })
        #expect(offered == planned)
        #expect(offer.sessions.first?.isSuggestedToday == true)
        #expect(offer.sessions.dropFirst().allSatisfy { !$0.isSuggestedToday })
        #expect(offer.day == calendar.startOfDay(for: now))
        #expect(offer.validUntil == ProgramTestCalendar.date(2026, 9, 28, 0))
        // Each session runs at the program's volume.
        for session in offer.sessions {
            let target = try #require(week.targets.first { $0.session == session.plan.definition.id })
            #expect(session.plan.options.volume == target.volume)
        }
    }

    @Test("Only conversational sessions carry a heart-rate range, and never for an RPE-only user")
    func heartRateRangeOnlyWhereItApplies() throws {
        let now = ProgramTestCalendar.date(2026, 9, 21, 9)
        let (withProfile, publisher, container) = makeViewModel(profile: HeartRateProfile(age: 30), now: now)
        _ = container
        withProfile.enroll(startDate: now, experience: .beginner, sparsHard: false)
        let offer = try #require(publisher.offers.last)
        let base = try #require(offer.sessions.first { $0.plan.definition.id == .aerobicBase })
        let bursts = try #require(offer.sessions.first { $0.plan.definition.id == .aerobicBursts })
        #expect(base.heartRateTarget == HeartRateZones.aerobicTarget(for: HeartRateProfile(age: 30)))
        #expect(bursts.heartRateTarget == nil)

        let (medicated, medicatedPublisher, medicatedContainer) = makeViewModel(
            profile: HeartRateProfile(age: 30, usesHeartRateMedication: true),
            now: now
        )
        _ = medicatedContainer
        medicated.enroll(startDate: now, experience: .beginner, sparsHard: false)
        #expect(try #require(medicatedPublisher.offers.last).sessions.allSatisfy { $0.heartRateTarget == nil })
    }

    @Test("Not enrolled, paused or left: the watch is told there is nothing to offer")
    func nothingWithoutARunningProgram() throws {
        let now = ProgramTestCalendar.date(2026, 9, 21, 9)
        let (viewModel, publisher, container) = makeViewModel(profile: nil, now: now)
        _ = container

        viewModel.refresh()
        #expect(publisher.offers.last?.sessions.isEmpty == true)

        viewModel.enroll(startDate: now, experience: .beginner, sparsHard: false)
        #expect(publisher.offers.last?.sessions.isEmpty == false)
        viewModel.pause()
        #expect(publisher.offers.last?.sessions.isEmpty == true)
        viewModel.resume()
        viewModel.leave()
        #expect(publisher.offers.last?.sessions.isEmpty == true)
    }

    @Test("The wire offer drops swim, keeps the default modality first and carries expanded phases")
    func wireMapping() throws {
        let plan = ConditioningSessionPlan(
            definition: ConditioningLibrary.aerobicBase,
            options: ConditioningSessionOptions(volume: 45),
            modality: .run
        )
        let target = HeartRateZones.aerobicTarget(for: HeartRateProfile(age: 40))
        let offer = ConditioningWatchOffer(
            sessions: [.init(plan: plan, isSuggestedToday: true, heartRateTarget: target)],
            day: ProgramTestCalendar.date(2026, 9, 21, 0),
            validUntil: ProgramTestCalendar.date(2026, 9, 28, 0)
        )

        let wire = WatchConditioningMapper.program(from: offer)
        let session = try #require(wire.sessions.first)
        #expect(session.sessionType == "aerobicBase")
        #expect(session.modalities == ["run", "assaultBike", "rower"])
        #expect(session.phases == ConditioningTimeline(plan: plan).phases)
        #expect(session.heartRateZone?.lowerBPM == target?.lowerBPM)
        #expect(session.heartRateZone?.upperBPM == target?.upperBPM)

        // Deterministic bytes: an unchanged offer is not resent.
        #expect(WatchConditioningWire.encode(wire) == WatchConditioningWire.encode(WatchConditioningMapper.program(from: offer)))
        #expect(WatchConditioningWire.decode(try #require(WatchConditioningWire.encode(wire))) == wire)
    }

    @Test("The offer rides the routine context, is resent only when it changes, and keeps the routines")
    func ridesTheRoutineContext() throws {
        let transport = RecordingContextTransport()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let authority = RoutineSyncAuthority(transport: transport, directory: directory)
        authority.sendOrdinary([])
        #expect(transport.sent.count == 1)

        let payload = Data("offer-1".utf8)
        authority.updateConditioningProgram(payload, push: true)
        #expect(transport.sent.count == 2)
        #expect(transport.sent.last?[WatchConditioningProgram.contextKey] as? Data == payload)
        #expect(transport.sent.last?[WatchRoutineSync.contextRoutinesKey] as? Data != nil)

        authority.updateConditioningProgram(payload, push: true)
        #expect(transport.sent.count == 2)

        authority.updateWeightUnit("lb", push: true)
        #expect(transport.sent.last?[WatchConditioningProgram.contextKey] as? Data == payload)
    }
}

@Suite @MainActor
struct ConditioningOfferBeforeActivationTests {

    /// Covers the suppression bypass. The device failure itself (nothing sent before
    /// activation) is fixed by `activationDidCompleteWith` posting
    /// `.watchAppBecameAvailable`, which needs a real `WCSession` and is not unit-tested.
    @Test("An offer recorded while the session could not send still reaches the watch with the next routine sync")
    func offerRecordedBeforeActivationIsFlushed() throws {
        let transport = RecordingContextTransport()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let authority = RoutineSyncAuthority(transport: transport, directory: directory)

        // Routines already went out, then the offer is recorded while the
        // session cannot send.
        authority.sendOrdinary([])
        let payload = Data("offer".utf8)
        authority.updateConditioningProgram(payload, push: false)
        #expect(transport.sent.count == 1)
        #expect(authority.hasUnsentExtras)

        // Activation triggers a routine sync with unchanged routines: not suppressed.
        authority.sendOrdinary([])
        #expect(transport.sent.count == 2)
        #expect(transport.sent.last?[WatchConditioningProgram.contextKey] as? Data == payload)
        #expect(!authority.hasUnsentExtras)

        // Nothing pending any more: identical routines are suppressed again.
        authority.sendOrdinary([])
        #expect(transport.sent.count == 2)
    }
}

private final class RecordingContextTransport: RoutineContextTransporting {
    private(set) var sent: [[String: Any]] = []
    var receivedWatchContext: [String: Any] = [:]
    func sendRoutineContext(_ context: [String: Any]) throws { sent.append(context) }
}
