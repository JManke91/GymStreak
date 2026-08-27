//
//  WeightDisplayMirror.swift
//  GymStreak
//
//  The one place the canonical-kilograms ↔ displayed-unit invariant lives.
//  See docs/weight-unit-preference.md §6.
//

import SwiftUI

/// Keeps a display-space weight field in sync with a canonical-kilograms
/// binding — shared by `WeightInput` and `OnyxWeightStepper` so this invariant
/// exists once rather than twice.
///
/// The mirror is deliberately **one-directional**: `displayValue` is re-derived
/// from `kilograms` on appear, on an external write and on a unit switch. Only
/// an actual edit travels the other way, and it snaps in display space, clamps
/// in kilogram space, and stores canonical kilograms.
///
/// The load-bearing line is `commit`'s opening guard. A re-derived mirror
/// carries exactly the canonical value, so it is recognised as not-an-edit —
/// without that, switching units would snap the derived value onto the new
/// unit's grid and write the re-gridded kilograms straight back to the store,
/// and "switch to lb and back" would silently rewrite every weight it touched.
private struct WeightDisplayMirror: ViewModifier {
    /// The canonical stored value.
    @Binding var kilograms: Double
    /// The same value in the displayed unit — what the field edits.
    @Binding var displayValue: Double
    /// Called with canonical kilograms whenever the stored value changes.
    let onUpdate: (Double) -> Void

    @Environment(\.weightUnit) private var weightUnit

    func body(content: Content) -> some View {
        content
            .onAppear { displayValue = weightUnit.converting(fromKilograms: kilograms) }
            .onChange(of: kilograms) { _, newKilograms in
                mirror(newKilograms, in: weightUnit)
            }
            .onChange(of: weightUnit) { _, newUnit in
                mirror(kilograms, in: newUnit)
            }
            .onChange(of: displayValue) { _, newValue in
                commit(newValue)
            }
    }

    /// Re-derives the field from the canonical value — always from the
    /// kilograms, never from the previous display value.
    ///
    /// Rewrites the field only when the string it renders would actually change.
    /// The kg round trip is exact for most values but not all — 1134.5 lb comes
    /// back 2.3e-13 short — and assigning that would rewrite the text and move
    /// the cursor while the user is still typing.
    ///
    /// Comparing the rendered strings is exactly the question being asked, so it
    /// cannot mask a correction the user could see. A numeric tolerance can, in
    /// two ways: a snap smaller than the tolerance, and a pair inside the
    /// tolerance that still straddles a rounding boundary.
    private func mirror(_ newKilograms: Double, in unit: WeightUnit) {
        let derived = unit.converting(fromKilograms: newKilograms)
        guard WeightFormatting.displayNumber(derived, in: unit)
            != WeightFormatting.displayNumber(displayValue, in: unit) else { return }
        displayValue = derived
    }

    /// Snap → clamp → store, for every change of the edited value.
    private func commit(_ newValue: Double) {
        // Not an edit: the field was merely re-derived from the canonical value.
        guard newValue != weightUnit.converting(fromKilograms: kilograms) else { return }

        // Snap in *display* space — quantizing after conversion would hand a
        // pounds user a grid of kilogram boundaries.
        let snapped = weightUnit.snapped(newValue, to: weightUnit.fineIncrement)
        // The ceiling is a kilogram magnitude, so it is enforced there.
        let stored = weightUnit.clampedKilograms(fromDisplay: snapped)
        // Snapping and the ceiling correct the field visibly, so it never shows
        // a number the store does not hold.
        mirror(stored, in: weightUnit)

        // Compared against the *current* canonical value, not a remembered one:
        // history would drop an edit that happened to snap back onto the last
        // value this field reported.
        guard stored != kilograms else { return }
        kilograms = stored
        onUpdate(stored)
    }
}

extension View {

    /// Binds a display-space weight field to a canonical-kilograms value.
    /// See `WeightDisplayMirror`.
    func weightDisplayMirror(
        kilograms: Binding<Double>,
        displayValue: Binding<Double>,
        onUpdate: @escaping (Double) -> Void = { _ in }
    ) -> some View {
        modifier(
            WeightDisplayMirror(
                kilograms: kilograms,
                displayValue: displayValue,
                onUpdate: onUpdate
            )
        )
    }
}
