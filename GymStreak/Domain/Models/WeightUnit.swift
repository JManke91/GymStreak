//
//  WeightUnit.swift
//  GymStreak
//
//  The unit weights are *shown and entered* in. See docs/weight-unit-preference.md.
//

import Foundation

/// The unit the user reads and types weights in.
///
/// **Kilograms remain the canonical stored unit everywhere.** Every `weight`,
/// `plannedWeight`, `actualWeight`, `bodyWeightKg` and every wire DTO keeps its
/// current meaning — pounds exist only between the store and the user's eyes.
/// Two rules follow from that and both matter:
///
/// 1. Always convert *from* the canonical kilograms, never from a previously
///    converted display value. Chained kg→lb→kg hops accumulate IEEE-754 error.
/// 2. Never persist a converted number. Only `kilograms(fromDisplay:)`'s result
///    goes back into the store.
///
/// Conversion uses `Measurement<UnitMass>`, whose `.pounds` is the international
/// avoirdupois pound — exactly `0.45359237` kg via `UnitConverterLinear`, so
/// display precision is the only thing that rounds.
enum WeightUnit: String, CaseIterable, Sendable {
    case kilograms
    case pounds

    var unitMass: UnitMass {
        switch self {
        case .kilograms: .kilograms
        case .pounds: .pounds
        }
    }

    // MARK: - Conversion

    /// Canonical kilograms → the value to display.
    func converting(fromKilograms kilograms: Double) -> Double {
        guard self != .kilograms else { return kilograms }
        return Measurement(value: kilograms, unit: UnitMass.kilograms)
            .converted(to: unitMass)
            .value
    }

    /// A displayed/typed value → the canonical kilograms to store.
    func kilograms(fromDisplay display: Double) -> Double {
        guard self != .kilograms else { return display }
        return Measurement(value: display, unit: unitMass)
            .converted(to: .kilograms)
            .value
    }

    /// Canonical kilograms → the value to display, rounded to this unit's
    /// precision.
    ///
    /// `converting(fromKilograms:)` keeps the full conversion residue — 100 kg is
    /// 220.46226… lb — which every `Presentation/` call site bounds with a format
    /// style's `fractionLength`. The AI coach builds its prompt lines with
    /// `String(format:)` and has no format style to lean on, so it rounds here
    /// rather than printing six decimals at the model.
    func roundedDisplay(fromKilograms kilograms: Double) -> Double {
        let scale = pow(10.0, Double(fractionDigits))
        return (converting(fromKilograms: kilograms) * scale).rounded() / scale
    }

    // MARK: - Display precision

    /// Digits after the decimal separator. Kilograms keep two — 0.25 kg
    /// increments need them; pounds need only one, their grid being 0.5 lb.
    var fractionDigits: Int {
        switch self {
        case .kilograms: 2
        case .pounds: 1
        }
    }

    // MARK: - Input grid

    /// The fine stepper's step, in *display* units (0.25 kg / 0.5 lb).
    var fineIncrement: Double {
        switch self {
        case .kilograms: 0.25
        case .pounds: 0.5
        }
    }

    /// The keypad's step, in *display* units — it drives the ±1×/±2× quick-step
    /// row, so this is what makes it ±2.5/±5 kg or ±5/±10 lb.
    var coarseIncrement: Double {
        switch self {
        case .kilograms: 2.5
        case .pounds: 5
        }
    }

    /// Snaps a *display-space* value to this unit's grid. Snapping has to happen
    /// before conversion — quantizing in kilograms would hand a pounds user a
    /// grid of kilogram boundaries.
    func snapped(_ display: Double, to increment: Double) -> Double {
        guard increment > 0 else { return display }
        return (display / increment).rounded() * increment
    }

    // MARK: - Input ceiling

    /// The weight ceiling, in canonical kilograms. Clamping happens here rather
    /// than per display unit so there is one number to keep true.
    static let maximumKilograms: Double = 999

    /// The same ceiling expressed in this unit, derived from the canonical one
    /// — and derived *once*.
    ///
    /// A set row reads this on every render to bound its stepper, and
    /// `docs/weight-unit-preference.md` §5 records the warning this obeys: a
    /// `Measurement` conversion is O(1) in a sheet but per-row work in a list.
    /// It stays derived rather than hand-copied so it cannot drift from
    /// `maximumKilograms`; `static let` is lazy, so the conversion runs once.
    var maximumDisplay: Double {
        switch self {
        case .kilograms: Self.maximumKilograms
        case .pounds: Self.maximumPoundsDisplay
        }
    }

    private static let maximumPoundsDisplay = WeightUnit.pounds
        .converting(fromKilograms: maximumKilograms)

    /// A typed display value → the canonical kilograms to store, clamped to
    /// `0...maximumKilograms`.
    func clampedKilograms(fromDisplay display: Double) -> Double {
        min(max(kilograms(fromDisplay: display), 0), Self.maximumKilograms)
    }

    // MARK: - Locale default

    /// The unit a fresh install starts on, seeded once and then user-owned.
    ///
    /// Only `.us` gets pounds. `.uk` is deliberately *not* treated as imperial:
    /// UK gyms use kilograms regardless of what CLDR says about road signs.
    /// `measurementSystem` is what makes that distinction possible at all —
    /// `usesMetricSystem` cannot tell `.us` from `.uk`.
    static func `default`(for locale: Locale = .current) -> WeightUnit {
        locale.measurementSystem == .us ? .pounds : .kilograms
    }
}
