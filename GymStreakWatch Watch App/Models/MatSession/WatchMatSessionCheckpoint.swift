//
//  WatchMatSessionCheckpoint.swift
//  GymStreakWatch Watch App
//
//  The crash boundary of a mat session recorded on the watch (positioning
//  ticket 05, docs/fight-conditioning.md): the conditioning runner's checkpoint
//  discipline, in a file of its own. Written on start, pause, resume, once a
//  minute (the heart-rate tally) and on end, so a relaunch on the review screen
//  comes back to it rather than losing the session.
//

import Foundation

struct WatchMatSessionCheckpoint: Codable, Equatable {
    let sport: WatchMatSport
    var clock: ConditioningClock
    let externalUUID: UUID
    /// Snapshot at start, like the conditioning runner's range.
    let zones: WatchMatIntensityZones?
    var tally: MatHeartRateTally
    /// Set when the user ended the session; the review screen is still open.
    var endedAt: Date?
    /// The round timer's plan (positioning ticket 07); `nil` for a plain mat
    /// session. Optional, so a checkpoint written before it existed still decodes.
    var rounds: RoundTimerConfiguration?
}

typealias WatchMatSessionCheckpointStore = WatchSessionCheckpointStore<WatchMatSessionCheckpoint>

extension WatchSessionCheckpointStore where Checkpoint == WatchMatSessionCheckpoint {
    convenience init(directory: URL? = nil) {
        self.init(directory: directory, fileName: "mat-session-checkpoint.json")
    }
}
