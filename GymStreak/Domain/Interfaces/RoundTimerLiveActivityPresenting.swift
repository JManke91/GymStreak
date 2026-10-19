//
//  RoundTimerLiveActivityPresenting.swift
//  GymStreak
//
//  The round timer's Lock Screen / Dynamic Island surface, as a system gateway
//  (docs/fight-conditioning.md, "Round timer" → Live Activity). Mirrors
//  `RestTimerLiveActivityPresenting`: ActivityKit-free, so `Domain/` and
//  `Presentation/` stay unaware of the framework — only `Data/LiveActivity`
//  imports it.
//

import Foundation

/// What the Lock Screen needs to know about one round-timer run, at two levels
/// of trust. ActivityKit cannot pre-schedule future states, so the phase detail
/// is only right while the app keeps updating it; the whole-run level is given
/// as wall-clock dates the system's own timer views advance without the app.
struct RoundTimerLiveActivityContent: Equatable {
    /// Fixed for the run. Localized in the app process — the widget extension
    /// renders these strings as they arrive and needs no keys of its own.
    struct Run: Equatable {
        /// "Round timer".
        let title: String
        /// "BJJ · 5:00 / 1:00".
        let subtitle: String
        /// An open-ended run shows elapsed time counting up and no progress bar.
        let isOpenEnded: Bool
        /// "Time left" / "Elapsed" — the caption of the whole-run time.
        let timeLabel: String
        /// "Paused".
        let pausedLabel: String
        /// The quiet note shown once the phase detail is stale.
        let staleNote: String
    }

    /// The current phase — trusted only until `range.upperBound`, which is the
    /// activity's stale date while the run is going.
    struct Phase: Equatable {
        /// "ROUND" / "REST".
        let label: String
        let isRound: Bool
        /// "Round 3 of 6", or nil when the phase has no round.
        let position: String?
        let range: ClosedRange<Date>
    }

    let run: Run
    /// Level 1: the whole run between its wall-clock start and the last bell,
    /// shifted by the pauses so far. Correct without the app.
    let runRange: ClosedRange<Date>
    /// Set while paused: every countdown freezes at this instant.
    let pauseDate: Date?
    /// Level 2: the current phase; nil hides the detail.
    let phase: Phase?
}

/// Identity-keyed like the rest timer's presenter, so two runs can never end
/// each other's activity; the run's UUID is the `RoundTimerViewModel`'s id.
@MainActor
protocol RoundTimerLiveActivityPresenting {
    /// Puts run `id` on the Lock Screen, or updates it if it is already there.
    /// Presenting a *different* id replaces the current one. A no-op when the
    /// user has Live Activities turned off.
    func presentActivity(id: UUID, content: RoundTimerLiveActivityContent)

    /// Ends `id`'s activity, briefly showing `completionMessage`. Does nothing
    /// if `id` is not the presented run.
    func endActivity(id: UUID, completionMessage: String)

    /// Ends every round-timer activity an earlier app process left behind. No
    /// run survives a relaunch — nothing is persisted to restore it from — so
    /// all of them are leftovers, whatever their dates. Safe to call repeatedly.
    func dismissLeftoverActivities()
}
