//
//  WatchConditioningStoreTests.swift
//  GymStreakWatchTests
//
//  Ticket 06 (docs/fight-conditioning.md): the synced offer on the watch —
//  persisted across launches, never replaced by garbage, hidden once its
//  program week is over, and "today" only on the day the iPhone said it.
//

import Foundation
import Testing
@testable import GymStreakWatch_Watch_App

@Suite @MainActor
struct WatchConditioningStoreTests {

    private let day = Date(timeIntervalSince1970: 1_790_000_000)

    private func program(sessions: Int = 1) -> WatchConditioningProgram {
        WatchConditioningProgram(
            day: day,
            validUntil: day.addingTimeInterval(7 * 86_400),
            sessions: (0..<sessions).map { index in
                WatchConditioningSession(
                    sessionType: index == 0 ? "aerobicBase" : "aerobicBursts",
                    energySystem: "aerobic",
                    modalities: ["run", "rower"],
                    volume: 30,
                    isSuggestedToday: index == 0,
                    phases: [ConditioningPhase(kind: .steady, duration: 1800, effort: .conversational)],
                    heartRateZone: WatchHeartRateZone(lowerBPM: 120, upperBPM: 145)
                )
            }
        )
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @Test("An applied offer survives a relaunch")
    func persistsAcrossLaunches() throws {
        let directory = tempDirectory()
        let data = try #require(WatchConditioningWire.encode(program(sessions: 2)))
        #expect(WatchConditioningStore(directory: directory).apply(data))
        #expect(WatchConditioningStore(directory: directory).program == program(sessions: 2))
    }

    @Test("Undecodable bytes keep the last good offer; an identical one changes nothing")
    func ignoresGarbageAndDuplicates() throws {
        let store = WatchConditioningStore(directory: tempDirectory())
        let data = try #require(WatchConditioningWire.encode(program()))
        #expect(store.apply(data))
        #expect(!store.apply(Data("nope".utf8)))
        #expect(!store.apply(data))
        #expect(store.program == program())
    }

    @Test("No sessions once the program week is over, and none without a synced program")
    func staleWeekShowsNothing() throws {
        let store = WatchConditioningStore(directory: tempDirectory(), now: day)
        #expect(store.sessions.isEmpty)
        store.apply(try #require(WatchConditioningWire.encode(program())), now: day.addingTimeInterval(3600))
        #expect(store.sessions.count == 1)
        store.refresh(at: day.addingTimeInterval(7 * 86_400))
        #expect(store.sessions.isEmpty)
        #expect(store.today == nil)
    }

    @Test("Today's suggestion is only marked on the day it was made")
    func todayOnlyOnItsDay() throws {
        let store = WatchConditioningStore(directory: tempDirectory(), now: day)
        store.apply(try #require(WatchConditioningWire.encode(program(sessions: 2))), now: day.addingTimeInterval(60))
        #expect(store.today?.sessionType == "aerobicBase")
        #expect(store.others.map(\.sessionType) == ["aerobicBursts"])
        store.refresh(at: day.addingTimeInterval(2 * 86_400))
        #expect(store.today == nil)
        #expect(store.others.count == 2)
    }
}
