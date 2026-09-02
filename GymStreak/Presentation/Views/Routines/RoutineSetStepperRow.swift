//
//  RoutineSetStepperRow.swift
//  GymStreak
//
//  One row of the always-editable set list: index badge, reps stepper, weight
//  stepper, remove button. Split out of RoutineSetsEditor when the weight-unit
//  conversion pushed that file past the 300-line convention — "one set row" and
//  "the set list plus its apply-to-all banner" are two jobs.
//

import SwiftUI

/// Value-typed set row: takes plain numbers, reports edits through callbacks.
/// Keeping models out of the row avoids a relationship read per row.
///
/// The row carries **no words** — only digits and SF Symbols. The unit labels
/// live once per set list in `RoutineSetsHeaderRow`, which is what makes this
/// row's width a constant instead of a function of the display language; see
/// the budget note on `Metrics`.
struct RoutineSetStepperRow: View {
    let index: Int
    let reps: Int
    /// Canonical kilograms, as stored.
    let weight: Double
    var targetRepMin: Int? = nil
    var targetRepMax: Int? = nil
    var canRemove: Bool = true
    /// Shared "a set value is being typed" flag driving the screen's Done bar.
    var valueFocus: FocusState<Bool>.Binding
    let onRepsChange: (Int) -> Void
    /// Called with canonical kilograms.
    let onWeightChange: (Double) -> Void
    let onRemove: () -> Void

    @Environment(\.weightUnit) private var weightUnit
    /// `weight` expressed in `weightUnit` — the value the field and the ±
    /// buttons actually edit. `weightDisplayMirror` owns the invariant that
    /// keeps it and the canonical kilograms in step.
    @State private var displayWeight: Double = 0

    private var repsColor: Color {
        guard let min = targetRepMin, let max = targetRepMax else { return .white }
        if reps >= max { return DesignSystem.Colors.warning }
        if reps >= min { return DesignSystem.Colors.tint }
        return Color.white.opacity(0.6)
    }

    /// Every width in the row, in one place — `RoutineSetsHeaderRow` builds its
    /// column legend from these same constants, so the legend cannot drift out
    /// of alignment with the fields it labels.
    ///
    /// **The width budget, measured 2026-09-02.** Available width depends on how
    /// deeply the row is nested, and the deepest nesting is reachable: the
    /// ALTERNATIVEN block is rendered unconditionally inside superset member
    /// cards, so an alternative's own set list can sit two indents deep.
    ///
    /// | Chrome the row does not get | Cost |
    /// |---|---|
    /// | `LazyVStack` list padding (`RoutineDetailView`) | 32 |
    /// | Exercise card `.padding(14)` | 28 |
    /// | Superset connector lane (`ExerciseHeaderView.connectorLaneWidth`, leading only) | 24 |
    /// | Alternative cell padding (`RoutineAlternativesSection`) | 16 |
    ///
    /// Against that, this row is **273 pt on every device and at every nesting
    /// depth** — the sum below — and the tightest cell in the matrix, a 375 pt
    /// phone (SE, 13 mini) with an alternative expanded inside a superset
    /// member, offers 275 pt. Every other cell clears it by 17 pt or more.
    ///
    /// That 2 pt margin is thin on purpose rather than by luck: nothing in the
    /// row is flexible any more, so `RoutineSetRowWidthBudgetTests` sums these
    /// constants against the whole matrix. Widening anything here fails that
    /// test rather than clipping a button on a phone nobody tested on.
    ///
    /// **What the shipped bug was.** The row used to carry a unit word beside
    /// each value ("Wdh." 33.9 pt in German against "reps" 29.1, "kg" 16.0), so
    /// its width was a function of the display language and came to ~330 pt —
    /// over budget in most cells. The units were the only non-fixed element, so
    /// they were where the shortfall landed: "kg" truncated to "k", and once the
    /// weight field was too narrow for a converted value, `136,08` clipped to
    /// `136…` as well.
    ///
    /// **Rejected fixes, so they are not re-tried.**
    /// - `minimumScaleFactor` on the unit label: shipped first, and it only
    ///   moves the failure — 14.9 pt of give at the 0.7 floor against a 63 pt
    ///   worst-case deficit, after which it truncates anyway.
    /// - `minimumScaleFactor` on the `TextField`: Apple documents no such
    ///   behaviour for it, demonstrates the reverse in every example, and its
    ///   behaviour while the field is focused is undocumented.
    /// - `ViewThatFits`: swaps whole subtrees, and nothing documents that a
    ///   focused `TextField` survives the swap.
    /// - Dropping the unit only where it does not fit: would render two set
    ///   tables differently **on one screen** (on a 402 pt phone a superset
    ///   member has 318 pt and keeps its units, while its own alternative has
    ///   294 pt and loses them), and puts a width measurement inside a repeated
    ///   row body — the cost `docs/history-performance.md` exists to prevent.
    /// - Narrowing `connectorLaneWidth`: its job is keeping avatars on the same
    ///   x whether or not a card is in a superset, so it would buy 4 pt at the
    ///   price of a visible cross-card misalignment.
    ///
    /// **The remaining slack, unspent on purpose:** the remove button is 26 pt
    /// (30 with its spacing) funding an action that happens rarely, and moving
    /// deletion to a swipe would recover it. Not done here — it hides a primary
    /// action to buy width the row does not currently need.
    enum Metrics {
        static let rowPadding: CGFloat = 6
        static let outerSpacing: CGFloat = 4
        static let groupSpacing: CGFloat = 4
        static let stepperSpacing: CGFloat = 4
        /// Reserved whether or not the button is drawn — see `removeColumn`.
        static let removeButtonWidth: CGFloat = 26
        static let stepButtonWidth: CGFloat = 26
        /// Fits "10"–"99" (16.2 pt at this font). The previous 14 pt was
        /// narrower than a two-digit number, so an exercise with ten or more
        /// sets truncated its own index to "1…".
        static let indexWidth: CGFloat = 17
        /// Fits any three-digit rep count (27.7 pt). Three digits is the true
        /// bound because the reps binding clamps to `repsMaximum` on typed input
        /// as well as on the ± buttons — without that clamp a typed "2500"
        /// reached the store and no plausible field width would hold it.
        static let repsFieldWidth: CGFloat = 28
        /// Fits a converted weight at full precision — "136,08", "999,99" — which
        /// is 50.4 pt here. Unit conversion is what produces those: 300 lb is
        /// 136,078 kg, so a routine authored in pounds has six-character
        /// kilogram values throughout.
        static let weightFieldWidth: CGFloat = 52
        /// The value fields' font size. A constant rather than a literal at the
        /// use site because `RoutineSetRowWidthBudgetTests` measures the widest
        /// value against it — the field widths above are only correct relative
        /// to a font, and that relationship should break a test, not a screen.
        static let valueFontSize: CGFloat = 13.5

        /// − field + , as one block. The header's column labels are centred over
        /// these, which is why they are derived rather than written down.
        static let repsGroupWidth: CGFloat =
            stepButtonWidth * 2 + stepperSpacing * 2 + repsFieldWidth
        static let weightGroupWidth: CGFloat =
            stepButtonWidth * 2 + stepperSpacing * 2 + weightFieldWidth
    }

    /// Domain maximum for a set's reps, enforced on the ± buttons *and* on typed
    /// input. See `Metrics.repsFieldWidth`.
    private static let repsMaximum: Double = 100

    var body: some View {
        HStack(spacing: Metrics.outerSpacing) {
            removeColumn

            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(1)
                .frame(width: Metrics.indexWidth)

            HStack(spacing: Metrics.groupSpacing) {
                valueStepper(
                    value: Binding(
                        get: { Double(reps) },
                        set: { onRepsChange(Int(Swift.min(Self.repsMaximum, Swift.max(1, $0)))) }
                    ),
                    step: 1,
                    minimum: 1,
                    maximum: Self.repsMaximum,
                    fieldWidth: Metrics.repsFieldWidth,
                    valueColor: repsColor,
                    keyboard: .numberPad,
                    format: Self.repsStyle
                )

                Spacer(minLength: 2)

                valueStepper(
                    // The field edits display space; the mirror below converts,
                    // snaps and clamps before anything reaches the store.
                    value: $displayWeight,
                    step: weightUnit.coarseIncrement,
                    minimum: 0,
                    maximum: weightUnit.maximumDisplay,
                    fieldWidth: Metrics.weightFieldWidth,
                    valueColor: .white,
                    keyboard: .decimalPad,
                    format: WeightFormatting.inputStyle(for: weightUnit)
                )
            }
        }
        .padding(.horizontal, Metrics.rowPadding)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .weightDisplayMirror(
            // The setter is the row's own report-upward hook, so the mirror's
            // separate `onUpdate` would fire a second, duplicate write.
            // A closure literal, not `set: onWeightChange`: `Binding`'s setter
            // is `@Sendable`, and handing it a stored non-`Sendable` closure
            // property warns. The literal is main-actor-isolated (SE-0461).
            kilograms: Binding(get: { weight }, set: { onWeightChange($0) }),
            displayValue: $displayWeight
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("accessibility.set.label".localized(
            index + 1,
            reps,
            WeightFormatting.spokenLabel(weight, in: weightUnit)
        ))
    }

    /// The leading column keeps its width whether or not the button is drawn.
    /// Two reasons: the set rows of a one-set exercise then line up with those
    /// of a multi-set one, and — the load-bearing one — the row's geometry stays
    /// a constant, so `RoutineSetsHeaderRow` needs no conditional to stay
    /// aligned. It costs nothing: the case that loses the button is also the
    /// case that has 30 pt more room.
    @ViewBuilder
    private var removeColumn: some View {
        if canRemove {
            Button {
                HapticManager.shared.light()
                onRemove()
            } label: {
                // `xmark.circle.fill`, not `minus.circle.fill`: the decrement
                // button 4 pt to its right is the same glyph at the same size,
                // and red-against-green is the only thing that told them apart —
                // which is no distinction at all under deuteranopia, on a
                // destructive control. The silhouette now differs.
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, DesignSystem.Colors.destructive)
                    .frame(width: Metrics.removeButtonWidth, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("set.delete_accessibility".localized(index + 1))
        } else {
            Color.clear
                .frame(width: Metrics.removeButtonWidth, height: 26)
        }
    }

    /// Reps are whole numbers; the field is a `Double` only because it shares
    /// the weight field's chrome.
    private static let repsStyle = FloatingPointFormatStyle<Double>.number
        .precision(.fractionLength(0))
        .grouping(.never)

    /// − [typable value] + — the number is a `TextField` styled as text, so exact
    /// values stay reachable without leaving the row. `minimum`/`maximum`/`step`
    /// are in the same space as `value`: display units for the weight field,
    /// plain counts for reps.
    ///
    /// The value is centred rather than trailing-aligned because nothing follows
    /// it any more; it reads as the label of the two buttons that flank it. The
    /// unit it used to sit beside is now in `RoutineSetsHeaderRow`.
    @ViewBuilder
    private func valueStepper(
        value: Binding<Double>,
        step: Double,
        minimum: Double,
        maximum: Double,
        fieldWidth: CGFloat,
        valueColor: Color,
        keyboard: UIKeyboardType,
        format: FloatingPointFormatStyle<Double>
    ) -> some View {
        HStack(spacing: Metrics.stepperSpacing) {
            stepButton(symbol: "minus", isEnabled: value.wrappedValue > minimum) {
                value.wrappedValue = Swift.max(minimum, value.wrappedValue - step)
            }

            TextField("", value: value, format: format)
                .keyboardType(keyboard)
                .multilineTextAlignment(.center)
                .focused(valueFocus)
                .selectAllOnFocus()
                .frame(width: fieldWidth)
                .font(.system(size: Metrics.valueFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)

            stepButton(symbol: "plus", isEnabled: value.wrappedValue < maximum) {
                value.wrappedValue = Swift.min(maximum, value.wrappedValue + step)
            }
        }
    }

    private func stepButton(symbol: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.light()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isEnabled ? DesignSystem.Colors.tint : DesignSystem.Colors.textDisabled)
                .frame(width: Metrics.stepButtonWidth, height: 26)
                .background(DesignSystem.Colors.tint.opacity(isEnabled ? 0.16 : 0.06), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
