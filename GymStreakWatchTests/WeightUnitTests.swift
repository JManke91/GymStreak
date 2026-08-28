//
//  WeightUnitTests.swift
//  GymStreakWatchTests
//
//  Watch-side twin of `GymStreakTests/WeightUnitTests.swift`.
//
//  `WeightUnit` is duplicated per target (the watch may not import iOS
//  `Domain/`, which owns SwiftData `@Model` types), and it decides what a stored
//  kilogram figure *means* on screen. A divergence between the two copies makes
//  the same set read as two different weights on the two devices, so the
//  conversion, precision, grid and ceiling assertions are kept identical to the
//  iOS twin on purpose.
//
//  Volume/tonnage and the Epley estimate have no watch caller and are not
//  copied — see `WatchWeightFormatting`.
//

import Testing
import Foundation
@testable import GymStreakWatch_Watch_App

@Suite @MainActor
struct WeightUnitTests {

    // MARK: - Conversion

    @Test("Kilograms convert to themselves untouched")
    func kilogramsAreIdentity() {
        #expect(WeightUnit.kilograms.converting(fromKilograms: 87.5) == 87.5)
        #expect(WeightUnit.kilograms.kilograms(fromDisplay: 87.5) == 87.5)
    }

    @Test("Pounds use Foundation's pound coefficient, which is not the exact avoirdupois one")
    func poundsUseFoundationsCoefficient() {
        // `UnitMass.pounds` converts with 0.453592 kg/lb, *not* the exact
        // avoirdupois 0.45359237 — a 8e-7 relative difference. Asserted rather
        // than glossed over so an SDK that tightens the constant shows up here
        // instead of as a silent shift in everyone's logged pounds.
        #expect(WeightUnit.pounds.kilograms(fromDisplay: 100) == 45.3592)
        let trueAvoirdupois = 100 / 0.45359237
        #expect(abs(WeightUnit.pounds.converting(fromKilograms: 100) - trueAvoirdupois) < 1e-3)
    }

    @Test("A kg → lb → kg round trip returns the canonical value")
    func roundTripFromCanonicalKilograms() {
        for kilograms in [0.0, 0.25, 2.5, 20, 37.5, 90, 137.75, 999] {
            let display = WeightUnit.pounds.converting(fromKilograms: kilograms)
            let restored = WeightUnit.pounds.kilograms(fromDisplay: display)
            #expect(abs(restored - kilograms) < 1e-9)
        }
    }

    // MARK: - Locale default

    @Test("Only the US measurement system seeds pounds")
    func localeDefaults() {
        // The watch never calls this — its unit arrives from iPhone — but the
        // copy must stay identical to the iOS original, which does.
        #expect(WeightUnit.default(for: Locale(identifier: "en_US")) == .pounds)
        #expect(WeightUnit.default(for: Locale(identifier: "en_GB")) == .kilograms)
        #expect(WeightUnit.default(for: Locale(identifier: "de_DE")) == .kilograms)
    }

    // MARK: - Display precision

    @Test("A whole number renders without a trailing separator")
    func wholeNumbersHaveNoFraction() {
        #expect(WatchWeightFormatting.number(65, in: .kilograms) == "65")
        // 100 lb on the nose, under Foundation's pound coefficient.
        #expect(WatchWeightFormatting.number(45.3592, in: .pounds) == "100")
    }

    @Test("Kilograms keep two fraction digits, pounds one")
    func perUnitPrecision() {
        let separator = Locale.current.decimalSeparator ?? "."
        #expect(WatchWeightFormatting.number(37.25, in: .kilograms) == "37\(separator)25")
        // 100 kg is 220.46226… lb — one digit, so "220,5".
        #expect(WatchWeightFormatting.number(100, in: .pounds) == "220\(separator)5")
    }

    @Test("Thousands are never grouped")
    func noGrouping() {
        // 999 kg is 2202.6 lb: a grouping separator here would read as a decimal.
        #expect(WatchWeightFormatting.number(999, in: .pounds).hasPrefix("2202"))
    }

    @Test("An increment keeps two digits in both units, so 1.25 is not rounded to 1.3")
    func incrementPrecision() {
        // 1.25 is a real micro-plate in BOTH units. The pound style's single
        // decimal would round it to a misleading "1,3".
        let separator = Locale.current.decimalSeparator ?? "."
        #expect(WatchWeightFormatting.incrementLabel(1.25, in: .pounds).contains("1\(separator)25"))
        #expect(WatchWeightFormatting.incrementLabel(1.25, in: .kilograms).contains("1\(separator)25"))
    }

    // MARK: - Input grid

    @Test("Typed input snaps to the grid of the displayed unit")
    func snappingHappensInDisplaySpace() {
        #expect(WeightUnit.kilograms.snapped(37.6, to: 0.25) == 37.5)
        #expect(WeightUnit.kilograms.snapped(37.7, to: 0.25) == 37.75)
        #expect(WeightUnit.pounds.snapped(220.3, to: 0.5) == 220.5)
        #expect(WeightUnit.pounds.snapped(220.1, to: 0.5) == 220.0)
    }

    @Test("Each unit brings its own increments")
    func perUnitIncrements() {
        #expect(WeightUnit.kilograms.fineIncrement == 0.25)
        #expect(WeightUnit.pounds.fineIncrement == 0.5)
        #expect(WeightUnit.kilograms.coarseIncrement == 2.5)
        #expect(WeightUnit.pounds.coarseIncrement == 5)
    }

    // MARK: - Input ceiling

    @Test("The ceiling is enforced in kilogram space")
    func ceilingIsCanonical() {
        #expect(WeightUnit.kilograms.clampedKilograms(fromDisplay: 1200) == 999)
        // 5000 lb is far past 999 kg, so it clamps to the same canonical value.
        #expect(WeightUnit.pounds.clampedKilograms(fromDisplay: 5000) == 999)
        #expect(WeightUnit.pounds.clampedKilograms(fromDisplay: -3) == 0)
    }

    @Test("The display ceiling is derived from the canonical one")
    func displayCeilingIsDerived() {
        #expect(WeightUnit.kilograms.maximumDisplay == 999)
        #expect(abs(WeightUnit.pounds.maximumDisplay - 2202.4198) < 1e-3)
        let atCeiling = WeightUnit.pounds.clampedKilograms(
            fromDisplay: WeightUnit.pounds.maximumDisplay
        )
        #expect(abs(atCeiling - 999) < 1e-9)
    }

    // MARK: - The integer-kilogram grid this ticket removed

    /// The watch's steppers and crown editors used to quantize the **stored
    /// kilograms** to whole numbers. In pounds that silently destroys the value
    /// the user entered, and it drifts further on every subsequent edit — the
    /// single most likely data bug in this change, pinned here.
    @Test("Stepping in display space survives a round trip that rounding kilograms does not")
    func displaySpaceSteppingPreservesAPoundsValue() {
        let entered = 135.0  // lb
        let stored = WeightUnit.pounds.clampedKilograms(fromDisplay: entered)

        // What the old code did: round the stored kilograms to a whole number.
        let roundedStorage = stored.rounded()
        #expect(WeightUnit.pounds.converting(fromKilograms: roundedStorage) != entered)

        // What it does now: the number the user manipulates is quantized, the
        // stored kilograms are not.
        #expect(abs(WeightUnit.pounds.converting(fromKilograms: stored) - entered) < 1e-9)

        // And repeated ±1 lb steps land back exactly where they started.
        var kilograms = stored
        for delta in [1.0, 1.0, -1.0, -1.0] {
            let display = WeightUnit.pounds.converting(fromKilograms: kilograms)
            kilograms = WeightUnit.pounds.clampedKilograms(fromDisplay: display + delta)
        }
        #expect(abs(WeightUnit.pounds.converting(fromKilograms: kilograms) - entered) < 1e-9)
    }

    // MARK: - Unit words

    @Test("The unit word and its spoken form come from the two dedicated keys")
    func unitWords() {
        #expect(WatchWeightFormatting.unitWord(.kilograms) != WatchWeightFormatting.unitWord(.pounds))
        #expect(WatchWeightFormatting.spokenUnitWord(.kilograms)
                != WatchWeightFormatting.unitWord(.kilograms))
    }

    // MARK: - The locale-derived unit this ticket removed

    /// `WatchExercise.setsSummary` and `ProgressiveOverloadFormat` both used
    /// `usage: .general`, which re-derives the unit from `Locale`. A US-locale
    /// watch therefore showed "80 lb" in the routine overview and "kg" in the
    /// set editor of the same workout. The summary now takes the synced unit and
    /// nothing else decides.
    @Test("The routine summary renders the unit it is given, not the locale's")
    func setsSummaryFollowsTheGivenUnit() {
        let exercise = WatchExercise(
            id: UUID(),
            name: "Bench Press",
            muscleGroup: "Chest",
            sets: (0..<3).map { _ in
                WatchSet(id: UUID(), reps: 10, weight: 80, restTime: 90)
            },
            order: 0,
            supersetId: nil,
            supersetOrder: 0
        )

        let kilograms = exercise.setsSummary(in: .kilograms)
        let pounds = exercise.setsSummary(in: .pounds)

        #expect(kilograms.contains(WatchWeightFormatting.unitWord(.kilograms)))
        #expect(pounds.contains(WatchWeightFormatting.unitWord(.pounds)))
        // Not merely a different word: 80 kg is 176.4 lb.
        #expect(kilograms != pounds)
        #expect(pounds.contains(WatchWeightFormatting.number(80, in: .pounds)))
    }

    @Test("A bodyweight exercise still omits the weight entirely")
    func setsSummaryOmitsBodyweight() {
        let exercise = WatchExercise(
            id: UUID(),
            name: "Pull-up",
            muscleGroup: "Back",
            sets: [WatchSet(id: UUID(), reps: 8, weight: 0, restTime: 90)],
            order: 0,
            supersetId: nil,
            supersetOrder: 0
        )
        for unit in WeightUnit.allCases {
            #expect(exercise.setsSummary(in: unit) == "1 × 8")
        }
    }

    @Test("A mixed-weight scheme renders one range with a single unit word")
    func setsSummaryRendersARange() {
        let exercise = WatchExercise(
            id: UUID(),
            name: "Dumbbell Press",
            muscleGroup: "Chest",
            sets: [
                WatchSet(id: UUID(), reps: 10, weight: 60, restTime: 90),
                WatchSet(id: UUID(), reps: 10, weight: 80, restTime: 90)
            ],
            order: 0,
            supersetId: nil,
            supersetOrder: 0
        )
        let summary = exercise.setsSummary(in: .pounds)
        // Both ends converted from the canonical kilograms, independently.
        #expect(summary.contains(WatchWeightFormatting.number(60, in: .pounds)))
        #expect(summary.contains(WatchWeightFormatting.number(80, in: .pounds)))
        // The unit word appears once, on the pair — not on each end.
        let word = WatchWeightFormatting.unitWord(.pounds)
        #expect(summary.components(separatedBy: word).count == 2)
    }
}
