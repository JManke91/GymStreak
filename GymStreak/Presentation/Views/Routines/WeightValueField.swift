//
//  WeightValueField.swift
//  GymStreak
//
//  The labelled weight field of the Form-based set editor
//  (RoutineExerciseDetailView), which used to hold a bare
//  `TextField(value:format:)` over the stored kilograms — no unit, no increment
//  and no snapping.
//

import SwiftUI

/// `label` + a right-aligned weight field.
///
/// The binding is always **canonical kilograms**; the field edits a display-space
/// mirror of it, so a pounds user types pounds while the store keeps kilograms.
/// `weightDisplayMirror` owns that invariant — including snapping the typed value
/// to the displayed unit's grid and clamping it in kilogram space.
///
/// The mirror's state is private to each instance on purpose. Sharing one display
/// value across the rows of a collapsible editor is how a collapsing row's still-live
/// handlers write the newly expanded row's number into the old set.
struct WeightValueField: View {
    let label: String
    /// Canonical kilograms.
    @Binding var kilograms: Double

    @Environment(\.weightUnit) private var weightUnit
    /// `kilograms` expressed in `weightUnit` — the value the field edits.
    @State private var displayWeight: Double = 0

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: $displayWeight, format: WeightFormatting.inputStyle(for: weightUnit))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .selectAllOnFocus()
        }
        .weightDisplayMirror(kilograms: $kilograms, displayValue: $displayWeight)
    }
}
