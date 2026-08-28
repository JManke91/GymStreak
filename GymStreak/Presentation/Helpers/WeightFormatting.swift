import Foundation

/// The app's single weight-formatting seam: converts the canonical kilograms
/// into the user's unit and renders it locale-aware and trailing-zero-free
/// ("90", "37,5", "198,4 lb").
///
/// It replaced three parallel implementations (a `FloatingPointFormatStyle`
/// helper, `WorkoutValueFormatting.weight`'s hand-rolled separator swap, and
/// `SetSummaryFormatting`'s own call into the first) — that drift is exactly how
/// "kg" ended up baked into twenty localized values. Everything that renders a
/// weight goes through here.
///
/// The format styles are `static let` because these strings are produced once
/// per set row per render (see CLAUDE.md, rendering rules), and because
/// `MeasurementFormatter` — the obvious alternative — is a mutable `NSObject`
/// that is not `Sendable` and so cannot be hoisted at all in this Swift 6 build.
/// The unit word comes from `Localizable.strings` rather than
/// `.formatted(.measurement(...))`, whose default `usage: .general` re-derives
/// the unit from the locale and would contradict the value just converted.
enum WeightFormatting {

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
    /// round it to a misleading "1.3" — the same trap `%.2g` sprang by rendering
    /// it "1.2". So a step is formatted by what it is, not by its unit.
    private static let incrementStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0...2))
        .grouping(.never)

    private static func style(for unit: WeightUnit) -> FloatingPointFormatStyle<Double> {
        switch unit {
        case .kilograms: kilogramStyle
        case .pounds: poundStyle
        }
    }

    /// The style a `TextField(value:format:)` edits a weight in — the same one
    /// the read-only sites use, exposed so a field never builds its own.
    static func inputStyle(for unit: WeightUnit) -> FloatingPointFormatStyle<Double> {
        style(for: unit)
    }

    // MARK: - Unit words

    /// The written unit: "kg" / "lb".
    static func unitWord(_ unit: WeightUnit) -> String {
        switch unit {
        case .kilograms: "unit.weight.kg".localized
        case .pounds: "unit.weight.lb".localized
        }
    }

    /// The spoken unit, for VoiceOver: "kilograms" / "pounds". A screen reader
    /// saying "kay gee" is the reason this exists.
    static func spokenUnitWord(_ unit: WeightUnit) -> String {
        switch unit {
        case .kilograms: "unit.weight.kg.spoken".localized
        case .pounds: "unit.weight.lb.spoken".localized
        }
    }

    /// The unit's own name for a standalone label such as the Settings picker:
    /// "Kilograms" / "Pounds". Capitalized from the spoken word so the unit
    /// still lives in one pair of keys instead of three.
    static func unitName(_ unit: WeightUnit) -> String {
        spokenUnitWord(unit).localizedCapitalized
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

    /// Number with the spoken unit word, for accessibility labels.
    static func spokenLabel(_ kilograms: Double, in unit: WeightUnit) -> String {
        "set.weight_compact".localized(number(kilograms, in: unit), spokenUnitWord(unit))
    }

    /// A *derived* weight rather than one the user entered, where whole display
    /// units are the right precision: "137 kg", "303 lb". The history PR banner's
    /// two Epley figures are the callers.
    ///
    /// Not every estimate wants this. The chart's PR stat card is also an Epley
    /// figure but sits directly under a headline rendered at the unit's own
    /// precision, and rounding one of a visually paired number is worse than
    /// carrying the decimal.
    ///
    /// Rounded to whole display units, because `label(_:in:)` carries the
    /// precision of an *entered* weight and a computed estimate has arbitrary
    /// decimals — it would print "137,35 kg" of false confidence where the old
    /// `%.0f kg` printed "137 kg". The rounding happens in display space, after
    /// converting from the canonical kilograms, so the pound figure is derived
    /// from the stored value and not from a rounded kilogram one.
    static func estimateLabel(_ kilograms: Double, in unit: WeightUnit) -> String {
        displayLabel(unit.converting(fromKilograms: kilograms).rounded(), in: unit)
    }

    // MARK: - Display space in

    /// Bare number for a value that is *already* in `unit` — a stepper delta, a
    /// figure the user just typed. Never hand this canonical kilograms: it does
    /// not convert, by design.
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

    // MARK: - Volume (tonnage)

    /// A tonnage figure — a session's, a week's or a month's summed weight ×
    /// reps — from canonical kilograms: "847 kg", "12,3 t", "27,6k lb".
    ///
    /// Eight near-identical `formatVolume`/`formatTons` helpers each made this
    /// decision on their own ("over 1000 → `%.1ft`, else `%.0fkg`"), and one had
    /// already drifted to `%.0ft`. There is one now.
    ///
    /// **The pound rollup, decided once here.** Kilograms roll up to the metric
    /// tonne at 1 000 kg. Pounds have no equivalent: 1 000 lb is not a unit, a
    /// short ton (2 000 lb) abbreviates to "tn" — one letter from the tonne, and
    /// not gym vocabulary in the first place — and showing a pounds user "0,5 t"
    /// mixes measurement systems on their own numbers. So pounds keep "lb" and
    /// take a magnitude prefix on the *number*: "27,6k lb". The prefix goes on
    /// the number rather than into the unit word because the shared
    /// `set.weight_compact` puts a space between the two, which would orphan the
    /// "k". The threshold is applied *after* conversion, so each unit rolls at
    /// 1 000 of its own numbers and the two paths keep the same digit count.
    static func volume(_ kilograms: Double, in unit: WeightUnit) -> String {
        joined(volumeParts(kilograms, in: unit))
    }

    /// As `volume(_:in:)`, under a rollup decision made elsewhere — see
    /// `volumeParts(_:in:rolledUp:)`.
    static func volume(_ kilograms: Double, in unit: WeightUnit, rolledUp: Bool) -> String {
        joined(volumeParts(kilograms, in: unit, rolledUp: rolledUp))
    }

    static func joined(_ parts: VolumeParts) -> String {
        "set.weight_compact".localized(parts.number, parts.unitWord)
    }

    /// A tonnage split into its number and its unit word, for the chart headline
    /// — the one caller that renders the two in different type styles.
    ///
    /// Produced together rather than by two calls so the number and the word
    /// cannot disagree about whether the rollup happened.
    struct VolumeParts {
        let number: String
        let unitWord: String
    }

    static func volumeParts(_ kilograms: Double, in unit: WeightUnit) -> VolumeParts {
        volumeParts(kilograms, in: unit, rolledUp: volumeRollsUp(kilograms, in: unit))
    }

    /// Whether a tonnage of this size rolls up in this unit.
    static func volumeRollsUp(_ kilograms: Double, in unit: WeightUnit) -> Bool {
        unit.converting(fromKilograms: kilograms) >= volumeRollupThreshold
    }

    /// Formats a tonnage under a rollup decision made *elsewhere*.
    ///
    /// Several related volumes share one screen — a window record, the latest
    /// value, a tap annotation — and they are read against each other. Letting
    /// each decide its own rollup puts them in different units the moment one
    /// crosses 1000 and another does not: "REKORD 1,1 t" sat directly above
    /// "GESAMTVOLUMEN 960 kg" on device, two numbers meant to be compared at a
    /// glance and no longer comparable. The caller decides once, from the
    /// largest of the set, and passes the decision here.
    static func volumeParts(
        _ kilograms: Double,
        in unit: WeightUnit,
        rolledUp: Bool
    ) -> VolumeParts {
        let display = unit.converting(fromKilograms: kilograms)
        guard rolledUp else {
            return VolumeParts(
                number: display.formatted(volumeStyle),
                unitWord: unitWord(unit)
            )
        }
        let rolled = (display / volumeRollupThreshold).formatted(rolledVolumeStyle)
        switch unit {
        case .kilograms:
            return VolumeParts(number: rolled, unitWord: "unit.volume.t".localized)
        case .pounds:
            return VolumeParts(
                number: rolled + "unit.volume.thousand".localized,
                unitWord: unitWord(unit)
            )
        }
    }

    /// 1 000 *display* units, in both systems — see `volume(_:in:)`.
    static let volumeRollupThreshold: Double = 1000

    /// A tonnage below the rollup is a whole number: nobody reads "847,3 kg" of
    /// weekly volume as more informative than "847 kg".
    private static let volumeStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0))
        .grouping(.never)

    private static let rolledVolumeStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(1))
        .grouping(.never)

    // MARK: - Composition

    /// Any preformatted number — a single value or a range such as "40–45" —
    /// with the unit word appended in the locale's order. The one place that
    /// pairing is expressed.
    static func labelled(_ number: String, in unit: WeightUnit) -> String {
        "set.weight_compact".localized(number, unitWord(unit))
    }
}
