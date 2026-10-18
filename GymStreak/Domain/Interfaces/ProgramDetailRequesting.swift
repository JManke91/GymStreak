//
//  ProgramDetailRequesting.swift
//  GymStreak
//
//  Asks the Routines tab to open one program's detail screen next.
//  See docs/onboarding.md, "Step 7 — How do you train?".
//

import Foundation

/// A request to land the user on a ready-made program's detail screen.
///
/// Exists so the first-run tour — a full-screen cover that knows nothing about
/// the tab bar underneath it — can end on the Fighter Strength program without
/// holding the Routines tab's navigation state. The tab owns the push; this is
/// only the request, and it is consumed once.
///
/// Beside `PaywallPresenting` for the same reason that one is a Domain seam: a
/// view model raises it, a different screen answers it, and neither may know
/// the other's concrete type.
@MainActor
protocol ProgramDetailRequesting: AnyObject {

    /// Opens the detail of the program with this catalog id the next time the
    /// Routines tab is on screen — immediately, if it already is.
    func requestProgramDetail(_ programId: String)
}
