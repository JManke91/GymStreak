//
//  WeightUnitTests.swift
//  GymStreakTests
//
//  The unit seam (docs/weight-unit-preference.md). The load-bearing assertions
//  are the ones about *storage*: a round trip through pounds has to come back
//  to the kilograms it started from, because every conversion in the app starts
//  from the canonical value and nothing converted is ever persisted.
//

import Testing
import Foundation
@testable import GymStreak

@MainActor
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
        // 0.0002 lb at 100 kg: three orders of magnitude below the one decimal
        // place pounds are displayed with, so the discrepancy is invisible.
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
        #expect(WeightUnit.default(for: Locale(identifier: "en_US")) == .pounds)
        // The product call: UK gyms use kilograms whatever CLDR says about
        // road signs, so `.uk` is deliberately not treated as imperial.
        #expect(WeightUnit.default(for: Locale(identifier: "en_GB")) == .kilograms)
        #expect(WeightUnit.default(for: Locale(identifier: "de_DE")) == .kilograms)
        #expect(WeightUnit.default(for: Locale(identifier: "ja_JP")) == .kilograms)
    }

    @Test("The `.uk` measurement system is what makes the UK case possible")
    func ukIsDistinguishableFromUS() {
        // `usesMetricSystem` reports false for both, which is why the seed reads
        // `measurementSystem` instead.
        #expect(Locale(identifier: "en_GB").measurementSystem == .uk)
        #expect(Locale(identifier: "en_US").measurementSystem == .us)
    }

    // MARK: - Display precision

    @Test("A whole number renders without a trailing separator")
    func wholeNumbersHaveNoFraction() {
        #expect(WeightFormatting.number(65, in: .kilograms) == "65")
        // 100 lb on the nose, under Foundation's pound coefficient.
        #expect(WeightFormatting.number(45.3592, in: .pounds) == "100")
    }

    @Test("Kilograms keep two fraction digits, pounds one")
    func perUnitPrecision() {
        let separator = Locale.current.decimalSeparator ?? "."
        #expect(WeightFormatting.number(37.25, in: .kilograms) == "37\(separator)25")
        // 100 kg is 220.46226… lb — one digit, so "220,5".
        #expect(WeightFormatting.number(100, in: .pounds) == "220\(separator)5")
    }

    @Test("Thousands are never grouped")
    func noGrouping() {
        // 999 kg is 2202.6 lb: a grouping separator here would read as a decimal.
        let formatted = WeightFormatting.number(999, in: .pounds)
        #expect(formatted.hasPrefix("2202"))
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

    @Test("A pounds grid does not quantize to kilogram boundaries")
    func poundGridIsNotAKilogramGrid() {
        // 220.5 lb is 100.017 kg — off the 0.25 kg grid, and correctly so: the
        // grid the user gets is the grid of the unit they are typing in.
        let kilograms = WeightUnit.pounds.clampedKilograms(fromDisplay: 220.5)
        #expect(WeightUnit.kilograms.snapped(kilograms, to: 0.25) != kilograms)
    }

    @Test("Float dust from the kg round trip renders identically, so the field is not rewritten")
    func roundTripDustRendersIdentically() {
        // `WeightDisplayMirror` re-derives the field only when the rendered
        // string changes. The kg round trip is exact for most values — 225 lb
        // returns 225 bit-for-bit — but not all: 1134.5 lb, itself on the 0.5 lb
        // grid, comes back 2.3e-13 short. Assigning that would rewrite the text
        // and move the cursor mid-typing.
        #expect(
            WeightUnit.pounds.converting(
                fromKilograms: WeightUnit.pounds.kilograms(fromDisplay: 225)
            ) == 225
        )
        let dusty = WeightUnit.pounds.converting(
            fromKilograms: WeightUnit.pounds.kilograms(fromDisplay: 1134.5)
        )
        #expect(dusty != 1134.5)
        #expect(abs(dusty - 1134.5) < 1e-9)
        #expect(
            WeightFormatting.displayNumber(dusty, in: .pounds)
                == WeightFormatting.displayNumber(1134.5, in: .pounds)
        )

        // A correction the user could see does change the string — including a
        // snap far smaller than half an increment, which a numeric tolerance
        // would have masked.
        #expect(
            WeightFormatting.displayNumber(220.5, in: .pounds)
                != WeightFormatting.displayNumber(220.0, in: .pounds)
        )
        #expect(
            WeightFormatting.displayNumber(37.5, in: .kilograms)
                != WeightFormatting.displayNumber(37.49, in: .kilograms)
        )
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
        // A value at the display ceiling survives the trip back.
        let atCeiling = WeightUnit.pounds.clampedKilograms(
            fromDisplay: WeightUnit.pounds.maximumDisplay
        )
        #expect(abs(atCeiling - 999) < 1e-9)
    }

    // MARK: - Volume and the tonnage rollup

    @Test("A tonnage below the rollup carries the plain unit word and no decimals")
    func volumeBelowRollup() {
        let parts = WeightFormatting.volumeParts(847.4, in: .kilograms)
        #expect(parts.unitWord == WeightFormatting.unitWord(.kilograms))
        // Weekly volume is not more informative to a tenth of a kilogram.
        if let separator = Locale.current.decimalSeparator {
            #expect(!parts.number.contains(separator))
        }
    }

    /// Kilograms signal the rollup by swapping the unit word for the tonne;
    /// pounds keep "lb" and carry a magnitude prefix on the number instead, so
    /// "did this roll up?" is a different question per unit (§10).
    private func isRolledUp(_ kilograms: Double, in unit: WeightUnit) -> Bool {
        let parts = WeightFormatting.volumeParts(kilograms, in: unit)
        switch unit {
        case .kilograms: return parts.unitWord != WeightFormatting.unitWord(.kilograms)
        case .pounds: return parts.number.hasSuffix("unit.volume.thousand".localized)
        }
    }

    @Test("Kilograms roll up to the metric tonne, and exactly at 1000")
    func kilogramRollup() {
        #expect(isRolledUp(1500, in: .kilograms))
        #expect(isRolledUp(1000, in: .kilograms))
        #expect(!isRolledUp(999, in: .kilograms))
        #expect(WeightFormatting.volumeParts(12_500, in: .kilograms).number
                == 12.5.formatted(.number.precision(.fractionLength(1)).grouping(.never)))
    }

    @Test("Pounds keep their own unit word when rolled, never the tonne")
    func poundRollupIsNotTonnes() {
        let pounds = WeightFormatting.volumeParts(12_500, in: .pounds)
        let tonneWord = WeightFormatting.volumeParts(12_500, in: .kilograms).unitWord
        // "0,5 t" for a pounds user would mix measurement systems on their own
        // numbers — the product call this asserts.
        #expect(pounds.unitWord != tonneWord)
        #expect(pounds.unitWord == WeightFormatting.unitWord(.pounds))
        // The rollup shows on the number ("27,6k"), so the shared "%@ %@" join
        // cannot orphan the prefix.
        #expect(isRolledUp(12_500, in: .pounds))
    }

    @Test("The rollup threshold is applied after conversion, so each unit rolls at 1000 of its own numbers")
    func rollupHappensInDisplaySpace() {
        // 500 kg is 1102 lb: below the threshold as kilograms, above it as pounds.
        // Deciding before conversion would have rolled both or neither.
        #expect(!isRolledUp(500, in: .kilograms))
        #expect(isRolledUp(500, in: .pounds))
    }

    @Test("A tonnage is converted from the canonical kilograms")
    func volumeConverts() {
        #expect(WeightFormatting.volume(400, in: .kilograms)
                != WeightFormatting.volume(400, in: .pounds))
        // 400 kg is 882 lb — still below the rollup in both units, so the two
        // strings differ by their *numbers*, not only by their unit words.
        let kilograms = WeightFormatting.volumeParts(400, in: .kilograms)
        let pounds = WeightFormatting.volumeParts(400, in: .pounds)
        #expect(kilograms.number != pounds.number)
    }

    @Test("The joined string is exactly the parts, so number and word cannot disagree")
    func volumeJoinsItsOwnParts() {
        for kilograms in [0.0, 12.0, 847.4, 999.0, 1000.0, 12_500.0] {
            for unit in WeightUnit.allCases {
                let parts = WeightFormatting.volumeParts(kilograms, in: unit)
                let joined = WeightFormatting.volume(kilograms, in: unit)
                #expect(joined.contains(parts.number))
                #expect(joined.contains(parts.unitWord))
            }
        }
    }

    @Test("Related volumes share one rollup decision, so they never land in different units")
    func relatedVolumesShareTheRollup() {
        // Inclined Flying on device: a 1080 kg window record beside a 960 kg
        // latest value. Deciding per figure printed "1,1 t" directly above
        // "960 kg" — both correct alone, and not comparable, which is the only
        // reason the two sit next to each other.
        let record = 1080.0, latest = 960.0
        for unit in WeightUnit.allCases {
            let rolled = WeightFormatting.volumeRollsUp(record, in: unit)
            let recordWord = WeightFormatting.volumeParts(record, in: unit, rolledUp: rolled).unitWord
            let latestWord = WeightFormatting.volumeParts(latest, in: unit, rolledUp: rolled).unitWord
            #expect(recordWord == latestWord)
        }
        // Deciding independently is what produced the mismatch — pinned so the
        // shared-decision overload cannot quietly become redundant.
        #expect(WeightFormatting.volumeParts(record, in: .kilograms).unitWord
                != WeightFormatting.volumeParts(latest, in: .kilograms).unitWord)
    }

    @Test("The rollup decision is taken in display space")
    func rollsUpMatchesTheParts() {
        for kilograms in [0.0, 400.0, 500.0, 999.0, 1000.0, 12_500.0] {
            for unit in WeightUnit.allCases {
                let rolled = WeightFormatting.volumeRollsUp(kilograms, in: unit)
                #expect(WeightFormatting.volumeParts(kilograms, in: unit).unitWord
                        == WeightFormatting.volumeParts(kilograms, in: unit, rolledUp: rolled).unitWord)
            }
        }
    }

    @Test("A derived weight rounds to whole display units, an entered one does not")
    func estimateLabelRoundsWhereLabelDoesNot() {
        // An Epley estimate has arbitrary decimals; printing them is false
        // confidence, which is why `estimateLabel` exists next to `label`.
        if let separator = Locale.current.decimalSeparator {
            #expect(!WeightFormatting.estimateLabel(137.35, in: .kilograms).contains(separator))
            #expect(WeightFormatting.label(137.35, in: .kilograms).contains(separator))
            #expect(!WeightFormatting.estimateLabel(137.35, in: .pounds).contains(separator))
        }
        // Rounding happens after converting, so the pound figure is derived from
        // the stored kilograms rather than from a rounded kilogram value.
        #expect(WeightFormatting.estimateLabel(137.35, in: .pounds)
                != WeightFormatting.estimateLabel(137.0, in: .pounds))
    }

    // MARK: - Unit words

    @Test("The unit word and its spoken form come from the two dedicated keys")
    func unitWords() {
        #expect(WeightFormatting.unitWord(.kilograms) != WeightFormatting.unitWord(.pounds))
        #expect(WeightFormatting.spokenUnitWord(.kilograms) != WeightFormatting.unitWord(.kilograms))
        // The picker's label is the spoken word, capitalized — not a third key.
        #expect(
            WeightFormatting.unitName(.pounds)
                == WeightFormatting.spokenUnitWord(.pounds).localizedCapitalized
        )
    }
}

// MARK: - Preference store

@MainActor
struct WeightUnitPreferenceTests {

    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "WeightUnitPreferenceTests.\(name)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    @Test("A first launch in the US seeds pounds and persists the decision")
    func firstLaunchSeedsFromLocale() {
        let defaults = makeDefaults("seed-us")
        let preference = WeightUnitPreference(
            defaults: defaults,
            locale: Locale(identifier: "en_US")
        )

        #expect(preference.weightUnit == .pounds)
        #expect(defaults.string(forKey: "units.weight") == WeightUnit.pounds.rawValue)
    }

    @Test("A first launch outside the US seeds kilograms")
    func firstLaunchOutsideUSSeedsKilograms() {
        let defaults = makeDefaults("seed-gb")
        let preference = WeightUnitPreference(
            defaults: defaults,
            locale: Locale(identifier: "en_GB")
        )

        #expect(preference.weightUnit == .kilograms)
    }

    @Test("The stored unit is never re-seeded, whatever the locale later says")
    func storedUnitIsNeverReSeeded() {
        let defaults = makeDefaults("no-reseed")
        _ = WeightUnitPreference(defaults: defaults, locale: Locale(identifier: "en_US"))

        // Second launch, now in a metric locale: the unit is the user's.
        let relaunched = WeightUnitPreference(
            defaults: defaults,
            locale: Locale(identifier: "de_DE")
        )
        #expect(relaunched.weightUnit == .pounds)
    }

    @Test("A change writes through and survives a relaunch")
    func changeWritesThrough() {
        let defaults = makeDefaults("write-through")
        let preference = WeightUnitPreference(
            defaults: defaults,
            locale: Locale(identifier: "de_DE")
        )

        preference.weightUnit = .pounds

        #expect(defaults.string(forKey: "units.weight") == WeightUnit.pounds.rawValue)
        let relaunched = WeightUnitPreference(defaults: defaults, locale: Locale(identifier: "de_DE"))
        #expect(relaunched.weightUnit == .pounds)
    }

    @Test("An unrecognized stored value falls back to the locale default")
    func unknownStoredValueFallsBack() {
        let defaults = makeDefaults("garbage")
        defaults.set("stones", forKey: "units.weight")

        let preference = WeightUnitPreference(
            defaults: defaults,
            locale: Locale(identifier: "en_GB")
        )
        #expect(preference.weightUnit == .kilograms)
    }
}
