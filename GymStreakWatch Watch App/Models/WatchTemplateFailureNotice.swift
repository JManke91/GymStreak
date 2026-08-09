//
//  WatchTemplateFailureNotice.swift
//  GymStreakWatch Watch App
//
//  A routine change the user accepted on the watch that will NEVER be applied.
//
//  Since the history/template split (ADR 0001) a template update can die
//  silently: the workout still reaches iOS, only the routine update goes
//  missing, and the watch's optimistic value simply reverts. This is the record
//  that makes that failure visible — written in the SAME atomic state commit
//  that retires or quarantines the dead transaction, so a notice can never
//  outlive its cause or be lost with it.
//
//  Only TERMINAL outcomes produce one. A transaction that is merely in flight
//  produces nothing, however long it stays that way: pending is the normal
//  state for every workout performed away from the phone.
//
//  The reason is reconstructed on the watch from the outcome plus what the
//  watch already knows (see `WatchSyncStateStore`), not carried on the wire —
//  the terminal acknowledgment transports a machine outcome only.
//
//  IDENTICAL COPY in both targets — `GymStreak/Data/Sync/` and
//  `GymStreakWatch Watch App/Models/` — keep them in sync. There is no watch
//  unit-test target, so the iOS test target covers this logic.
//

import Foundation

struct WatchTemplateFailureNotice: Codable, Equatable, Identifiable {
    /// What the user is told. Deliberately coarse: each case maps to one
    /// sentence the user can act on, and every terminal cause folds into one of
    /// them rather than exposing an internal diagnostic.
    enum Reason: String, Codable {
        /// iOS terminally rejected the merge while the routine still exists —
        /// from the user's side, it had already changed on the iPhone.
        case routineChangedOnPhone
        /// iOS terminally rejected the merge and the authoritative base no
        /// longer carries the routine at all.
        case routineDeleted
        /// The exact bytes can never be transported (quarantine). The cause is
        /// internal, so the user is told only what it means for them.
        case couldNotSend
    }

    /// Newer notices replace an older one for the same routine and reason, and
    /// only this many are retained — a notice is a nudge to look at the routine
    /// on the iPhone, not a log.
    static let maxRetained = 5

    let id: UUID
    let routineID: UUID?
    /// Resolved when the notice is recorded; nil only when neither the
    /// authoritative base, the routine anchor, nor the payload knows a name.
    let routineName: String?
    let reason: Reason
    let occurredAt: Date

    init(
        id: UUID = UUID(),
        routineID: UUID?,
        routineName: String?,
        reason: Reason,
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.routineID = routineID
        self.routineName = routineName
        self.reason = reason
        self.occurredAt = occurredAt
    }

    /// Two notices are the same complaint when they name the same routine for
    /// the same reason; the newer one supersedes the older.
    func isSameComplaint(as other: WatchTemplateFailureNotice) -> Bool {
        routineID == other.routineID && reason == other.reason
    }
}
