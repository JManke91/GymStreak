//
//  WatchConditioningStore.swift
//  GymStreakWatch Watch App
//
//  The conditioning offer the iPhone last published (ticket 06,
//  docs/fight-conditioning.md): this program week's open sessions, today's
//  suggestion first, with the personal heart-rate zone already computed.
//
//  Persisted as the exact received bytes in an atomically-replaced App Group
//  file, so the entry is there before the first application context of a
//  launch arrives. Owned by `WatchConnectivityManager`, which applies it from
//  the routine context it rides in.
//

import Foundation
import Observation

@Observable
@MainActor
final class WatchConditioningStore {

    private(set) var program: WatchConditioningProgram?
    /// What the views render, precomputed so no `body` filters: every offered
    /// session, today's suggestion alone, and the rest of the week.
    private(set) var sessions: [WatchConditioningSession] = []
    private(set) var today: WatchConditioningSession?
    private(set) var others: [WatchConditioningSession] = []

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let calendar: Calendar

    init(directory: URL? = nil, calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        let base = directory ?? FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WatchActiveWorkoutCheckpointStore.appGroupID)?
            .appendingPathComponent("Conditioning", isDirectory: true)
        if let base { try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true) }
        fileURL = base?.appendingPathComponent("program.json")
        program = fileURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap(WatchConditioningWire.decode)
        refresh(at: now)
    }

    /// Applies a received payload. Undecodable bytes are ignored and the last good
    /// offer stays. Returns whether anything changed.
    @discardableResult
    func apply(_ data: Data, now: Date = Date()) -> Bool {
        guard let decoded = WatchConditioningWire.decode(data) else {
            WatchSyncDiagnostics.error("watch: undecodable conditioning offer ignored")
            return false
        }
        guard decoded != program else { return false }
        if let fileURL {
            try? data.write(to: fileURL, options: .atomic)
        }
        program = decoded
        refresh(at: now)
        return true
    }

    /// Recomputes what is offered at `now` — also on app activation, because
    /// "today" and the program week roll over by the clock. Nothing once the week
    /// the iPhone computed the offer for is over, so a stale week never shows up.
    func refresh(at now: Date = Date()) {
        let offered: [WatchConditioningSession]
        if let program, now < program.validUntil {
            let isSameDay = calendar.isDate(program.day, inSameDayAs: now)
            offered = program.sessions.compactMap { session in
                guard !session.modalities.isEmpty, !session.phases.isEmpty else { return nil }
                var session = session
                // "Today" is only true on the day the iPhone said it.
                session.isSuggestedToday = session.isSuggestedToday && isSameDay
                return session
            }
        } else {
            offered = []
        }
        guard offered != sessions else { return }
        sessions = offered
        today = offered.first(where: \.isSuggestedToday)
        others = offered.filter { !$0.isSuggestedToday }
    }
}
