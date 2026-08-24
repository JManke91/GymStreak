//
//  ExerciseProgressLoadDriver.swift
//  GymStreakTests
//
//  Ticket 05b — the exercise detail screen can decide, from the result of its first
//  load, that it is on the wrong window; it then moves `selectedTimeframe` and lets
//  `.task(id: viewModel.loadKey)` run a second load, publishing nothing in between so
//  the stat triple never renders the abandoned window's `-` / `-` / `0 Workouts`.
//
//  A test that calls `load()` once therefore sees an unpublished view model whenever the
//  stub's history is older than the opening default — which is true of every stub that
//  dates its usages in the past. This drives the loads the way the view does.
//

import Testing
import Foundation
@testable import GymStreak

/// Reloads for as long as the load key keeps moving, exactly like
/// `.task(id: viewModel.loadKey)` does, so a window the view model selects for itself is
/// actually fetched.
///
/// Bounded rather than `while`: the opening window is decided at most once per exercise,
/// so two loads always settle it. If that invariant ever regresses this must fail the
/// suite, not hang CI.
@MainActor
func loadUntilSettled(
    _ viewModel: ExerciseProgressViewModel,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    var previousKey: ExerciseProgressViewModel.LoadKey?
    for _ in 0..<3 {
        guard viewModel.loadKey != previousKey else { break }
        previousKey = viewModel.loadKey
        await viewModel.load()
    }
    #expect(
        viewModel.loadKey == previousKey,
        "the load key never settled — the opening window is moving more than once",
        sourceLocation: sourceLocation
    )
}
