//
//  SetDeltaAccessibilityTests.swift
//  GymStreakTests
//
//  The history detail's per-set delta chip used to decide whether it was
//  describing a weight or a rep count by substring-matching "kg" in its own
//  already-formatted label, and recovered the number by stripping "kg" out of
//  it. Both are build-green and test-green, and both go silently wrong the
//  moment the label reads "+11 lb" — VoiceOver then narrates a weight change as
//  a rep change. `Delta.Quantity` carries the kind explicitly now; these
//  assertions are what keeps it explicit.
//
//  See docs/weight-unit-preference.md §11.
//

import Testing
import Foundation
@testable import GymStreak

@MainActor
struct SetDeltaAccessibilityTests {

    // A 5 kg improvement — 11 lb once converted.
    private func weightGain(in unit: WeightUnit) -> SetDeltaChip.Delta {
        SetDeltaChip.Delta.fromWeight(current: 105, previous: 100, unit: unit)
    }

    @Test("A pounds weight delta is spoken in pounds, never in kilograms")
    func weightDeltaSpeaksTheChosenUnit() {
        let phrase = weightGain(in: .pounds).accessibilityPhrase
        #expect(phrase.contains(WeightFormatting.spokenUnitWord(.pounds)))
        #expect(!phrase.contains(WeightFormatting.spokenUnitWord(.kilograms)))

        let kilogramPhrase = weightGain(in: .kilograms).accessibilityPhrase
        #expect(kilogramPhrase.contains(WeightFormatting.spokenUnitWord(.kilograms)))
    }

    @Test("A weight delta is never described as a rep change")
    func weightIsNotMistakenForReps() {
        // This equality *is* the old defect: with the label reading "+11 lb",
        // `label.contains("kg")` was false and the rep phrasing was chosen.
        let weight = weightGain(in: .pounds).accessibilityPhrase
        let reps = SetDeltaChip.Delta.fromReps(current: 10, previous: 8).accessibilityPhrase
        #expect(weight != reps)
    }

    @Test("A volume delta is described as a percentage, not as zero reps")
    func volumeDeltaIsAPercentage() {
        // +15%. It had no phrase of its own, fell through the substring check to
        // the rep branch, and `Int("15%")` returned nil — so VoiceOver read a
        // 15% volume gain as "up 0 reps".
        let phrase = SetDeltaChip.Delta.fromVolume(current: 1150, previous: 1000)
            .accessibilityPhrase
        #expect(phrase.contains("15"))
        #expect(phrase != SetDeltaChip.Delta.fromReps(current: 10, previous: 8).accessibilityPhrase)
    }

    @Test("The visible label carries the chosen unit and its converted magnitude")
    func visibleLabelConverts() {
        let pounds = weightGain(in: .pounds)
        let kilograms = weightGain(in: .kilograms)
        #expect(pounds.label.contains(WeightFormatting.unitWord(.pounds)))
        #expect(kilograms.label.contains(WeightFormatting.unitWord(.kilograms)))
        // The *difference* is converted, not a difference of converted numbers.
        #expect(pounds.label != kilograms.label)
    }

    @Test("A change too small to matter is neutral in both units")
    func negligibleChangeIsNeutral() {
        #expect(SetDeltaChip.Delta.fromWeight(current: 100, previous: 100, unit: .pounds) == .neutral)
        #expect(SetDeltaChip.Delta.fromWeight(current: 100.005, previous: 100, unit: .kilograms) == .neutral)
    }
}
