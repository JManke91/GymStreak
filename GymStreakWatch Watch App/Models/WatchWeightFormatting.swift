//
//  WatchWeightFormatting.swift
//  GymStreakWatch Watch App
//
//  The watch's single weight-formatting seam — the counterpart of
//  `GymStreak/Presentation/Helpers/WeightFormatting.swift`. See
//  docs/weight-unit-preference.md.
//

import Foundation

/// Converts the canonical kilograms into the user's unit and renders them
/// locale-aware and trailing-zero-free ("90", "37,5", "198,4 lb").
///
/// **Never `.formatted(.measurement(...))`.** Its default `usage: .general`
/// re-derives the unit from `Locale`, which is precisely the bug this ticket
/// removed: a US-locale watch rendered "80 lb" in the routine overview while the
/// set editor on the same watch said "kg". The unit word comes from the String
/// Catalog and the value comes from the synced preference, so the two can never
/// contradict each other.
///
/// The format styles are `static let` because these strings are produced once
/// per row per render (CLAUDE.md, rendering rules), and because
/// `MeasurementFormatter` — the obvious alternative — is a mutable `NSObject`
/// that is not `Sendable` and so cannot be hoisted at all in this Swift 6 build.
///
/// A deliberately smaller surface than the iOS seam: the watch has no tonnage,
/// no chart headline and no Epley estimate, so `volume`/`estimateLabel` have no
/// watch caller and are not copied.
enum WatchWeightFormatting {

    // MARK: - Format styles

    private static let kilogramStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0...2))
        .grouping(.never)

    /// One digit is enough for pounds: their grid is 0.5 lb, and a converted
    /// figure carries no meaningful second decimal.
    private static let poundStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0...1))
        .grouping(.never)

    /// Increments carry a digit the weights themselves do not: 1.25 is a real
    /// micro-plate in **both** units, and the pound style's single decimal would
    /// round it to a misleading "1.3".
    private static let incrementStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0...2))
        .grouping(.never)

    private static func style(for unit: WeightUnit) -> FloatingPointFormatStyle<Double> {
        switch unit {
        case .kilograms: kilogramStyle
        case .pounds: poundStyle
        }
    }

    // MARK: - Unit words

    /// The written unit: "kg" / "lb".
    static func unitWord(_ unit: WeightUnit) -> String {
        switch unit {
        case .kilograms: String(localized: "kg", comment: "Abbreviated kilograms unit shown next to a weight")
        case .pounds: String(localized: "lb", comment: "Abbreviated pounds unit shown next to a weight")
        }
    }

    /// The spoken unit, for VoiceOver: "kilograms" / "pounds". A screen reader
    /// saying "kay gee" is the reason this exists.
    static func spokenUnitWord(_ unit: WeightUnit) -> String {
        switch unit {
        case .kilograms: String(localized: "kilograms", comment: "Spoken kilograms unit, for VoiceOver")
        case .pounds: String(localized: "pounds", comment: "Spoken pounds unit, for VoiceOver")
        }
    }

    // MARK: - Canonical kilograms in

    /// Bare number, converted from the canonical kilograms: "90", "198,4".
    static func number(_ kilograms: Double, in unit: WeightUnit) -> String {
        displayNumber(unit.converting(fromKilograms: kilograms), in: unit)
    }

    /// Number with the unit word: "90 kg", "198,4 lb".
    static func label(_ kilograms: Double, in unit: WeightUnit) -> String {
        labelled(number(kilograms, in: unit), in: unit)
    }

    // MARK: - Display space in

    /// Bare number for a value that is *already* in `unit` — a stepper delta, a
    /// figure the user just dialled in. Never hand this canonical kilograms: it
    /// does not convert, by design.
    static func displayNumber(_ display: Double, in unit: WeightUnit) -> String {
        display.formatted(style(for: unit))
    }

    /// A value already in `unit`, with the unit word: "203,4 lb".
    static func displayLabel(_ display: Double, in unit: WeightUnit) -> String {
        labelled(displayNumber(display, in: unit), in: unit)
    }

    /// A progressive-overload or stepper increment, with the unit word:
    /// "1,25 kg", "5 lb". See `incrementStyle` for why it does not use the
    /// unit's own display precision.
    static func incrementLabel(_ display: Double, in unit: WeightUnit) -> String {
        labelled(display.formatted(incrementStyle), in: unit)
    }

    // MARK: - Composition

    /// Any preformatted number — a single value or a range such as "40–45" —
    /// with the unit word appended in the locale's order. The one place that
    /// pairing is expressed.
    ///
    /// `unitWord` defaults to the written form; a VoiceOver site passes
    /// `spokenUnitWord` instead so it gets the same pairing rather than
    /// concatenating its own space.
    static func labelled(
        _ number: String,
        in unit: WeightUnit,
        unitWord word: String? = nil
    ) -> String {
        String(
            localized: "\(number) \(word ?? unitWord(unit))",
            comment: "A weight and its unit, e.g. \"90 kg\""
        )
    }
}
