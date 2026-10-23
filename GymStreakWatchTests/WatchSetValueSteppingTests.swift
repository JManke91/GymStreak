//
//  WatchSetValueSteppingTests.swift
//  GymStreakWatchTests
//
//  The set editor's one stepping rule, shared by its ± buttons and the Digital
//  Crown (`docs/watch-crown-value-adjustment.md`).
//

import Testing
import Foundation
@testable import GymStreakWatch_Watch_App

@Suite @MainActor
struct WatchSetValueSteppingTests {

    // MARK: - Detent deltas

    @Test("A single detent in either direction is one step")
    func singleDetent() {
        #expect(WatchSetValueStepping.detents(from: 4, to: 5) == 1)
        #expect(WatchSetValueStepping.detents(from: 4, to: 3) == -1)
        #expect(WatchSetValueStepping.detents(from: 4, to: 4) == 0)
    }

    @Test("A fast spin delivering several detents in one change applies all of them")
    func multiDetentDelta() {
        #expect(WatchSetValueStepping.detents(from: -2, to: 5) == 7)
        #expect(WatchSetValueStepping.detents(from: 9_998, to: 9_995) == -3)
    }

    @Test("A continuous counter wrapping past its bound reads as the short way round")
    func wrappedCounter() {
        #expect(WatchSetValueStepping.detents(from: 9_999, to: -9_999, wrappingAt: 10_000) == 2)
        #expect(WatchSetValueStepping.detents(from: -9_999, to: 9_998, wrappingAt: 10_000) == -3)
        #expect(WatchSetValueStepping.detents(from: 5, to: 7, wrappingAt: 10_000) == 2)
    }

    @Test("Floating-point noise on the counter never becomes a phantom step")
    func deltaRounding() {
        #expect(WatchSetValueStepping.detents(from: 1, to: 1.999_999_9) == 1)
        #expect(WatchSetValueStepping.detents(from: 1, to: 1.000_000_1) == 0)
    }

    // MARK: - Weight

    @Test("Kilograms step by whole kilograms")
    func kilogramStep() {
        #expect(WatchSetValueStepping.weight(60, steppedBy: 1, in: .kilograms) == 61)
        #expect(WatchSetValueStepping.weight(60, steppedBy: -3, in: .kilograms) == 57)
    }

    @Test("A 60 kg set read in pounds steps by one pound and is never snapped to the grid")
    func poundsNonSnapping() {
        let start = WeightUnit.pounds.converting(fromKilograms: 60)  // 132.277…
        let up = WatchSetValueStepping.weight(60, steppedBy: 1, in: .pounds)
        #expect(abs(WeightUnit.pounds.converting(fromKilograms: up) - (start + 1)) < 1e-9)

        let back = WatchSetValueStepping.weight(up, steppedBy: -1, in: .pounds)
        #expect(abs(back - 60) < 1e-9)
    }

    @Test("A multi-detent step equals the same number of single steps")
    func multiStepMatchesRepeatedSingleSteps() {
        var single = 61.235
        for _ in 0..<5 { single = WatchSetValueStepping.weight(single, steppedBy: 1, in: .pounds) }
        let multi = WatchSetValueStepping.weight(61.235, steppedBy: 5, in: .pounds)
        #expect(abs(single - multi) < 1e-9)
    }

    @Test("Weight clamps to the canonical 0…999 kg on both units")
    func weightBounds() {
        #expect(WatchSetValueStepping.weight(0.5, steppedBy: -3, in: .kilograms) == 0)
        #expect(WatchSetValueStepping.weight(998, steppedBy: 10, in: .kilograms) == 999)
        #expect(WatchSetValueStepping.weight(1, steppedBy: -10, in: .pounds) == 0)
        #expect(abs(WatchSetValueStepping.weight(998.9, steppedBy: 10, in: .pounds) - 999) < 1e-9)
    }

    // MARK: - Reps

    @Test("Reps step by one and clamp to 0…100")
    func repsStepAndBounds() {
        #expect(WatchSetValueStepping.reps(8, steppedBy: 1) == 9)
        #expect(WatchSetValueStepping.reps(8, steppedBy: -3) == 5)
        #expect(WatchSetValueStepping.reps(1, steppedBy: -4) == 0)
        #expect(WatchSetValueStepping.reps(98, steppedBy: 7) == WatchSetValueStepping.maximumReps)
    }
}
