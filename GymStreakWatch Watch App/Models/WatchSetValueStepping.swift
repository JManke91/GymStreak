//
//  WatchSetValueStepping.swift
//  GymStreakWatch Watch App
//
//  The one stepping rule for the set editor's weight and reps values, shared by
//  the ± buttons and the Digital Crown. Pure, so the watch test suite can pin
//  it.
//

import Foundation

enum WatchSetValueStepping {
    /// Upper bound for a set's reps, on both input paths.
    static let maximumReps = 100

    /// Steps a weight by `steps` units **of what the user is reading**, never
    /// by kilograms of what is stored.
    ///
    /// The ±1 happens in display space and the result is converted back and
    /// clamped against the canonical ceiling. It deliberately does NOT snap to
    /// the display grid: a 60 kg set read in pounds steps 132.3 → 133.3, so a
    /// weight that is not on the current unit's grid survives being edited
    /// (`docs/weight-unit-preference.md` §9a).
    static func weight(_ kilograms: Double, steppedBy steps: Int, in unit: WeightUnit) -> Double {
        let display = unit.converting(fromKilograms: kilograms)
        return unit.clampedKilograms(fromDisplay: display + Double(steps))
    }

    static func reps(_ reps: Int, steppedBy steps: Int) -> Int {
        min(max(reps + steps, 0), maximumReps)
    }

    /// Whole detents between two readings of the Crown's detent counter.
    ///
    /// There is no delta API on the Crown (`DigitalCrownEvent` carries only
    /// `offset` and `velocity`), so the editor binds a scratch counter and
    /// applies the difference. A fast spin can deliver several detents in one
    /// change, which is why this is a count and not a direction.
    ///
    /// The counter is continuous (`isContinuous: true` hides the system Crown
    /// indicator), so it wraps from `bound` to `-bound` and back; a jump wider
    /// than `bound` is a wrap, not a spin.
    static func detents(from previous: Double, to current: Double, wrappingAt bound: Double = .infinity) -> Int {
        var delta = current - previous
        if delta > bound {
            delta -= 2 * bound
        } else if delta < -bound {
            delta += 2 * bound
        }
        return Int(delta.rounded())
    }
}
