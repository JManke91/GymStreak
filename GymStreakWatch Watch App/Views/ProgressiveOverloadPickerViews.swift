//
//  ProgressiveOverloadPickerViews.swift
//  GymStreakWatch Watch App
//
//  The pushed increment picker (design surface 2b) and the confirmation moment
//  (2c), split out of `ProgressiveOverloadViews.swift` to keep both files within
//  the repository's file-length convention. The container and the suggestion
//  capsule live there; the shared `ProgressiveOverloadFormat` helper lives here
//  because the picker is its heaviest user.
//
//  Presentation only — both report intent to `WatchWorkoutViewModel` and hold no
//  persistence, math, or transport.
//

import SwiftUI
import WatchKit

// MARK: - 2b · Increment picker

/// Chooses the weight step. Digital Crown is the primary input (one focused
/// owner on this screen); the chevrons are its required touch equivalent.
///
/// **No `ScrollView`, deliberately.** The crown is bound to the value here, so
/// it cannot also scroll the screen — a crown-focused control and a scroll
/// container compete for the same physical input, and focus does not reliably
/// return to the control after a touch-scroll. Everything must therefore fit.
/// Two structural moves buy that space:
///
/// * the exercise name goes in an inline **navigation title**, and
/// * Apply/Cancel go in the **toolbar** (`.confirmationAction` /
///   `.cancellationAction`, which watchOS places in the navigation bar), rather
///   than costing a full content row each.
///
/// The `NavigationStack` here is the root of the SHEET's own hierarchy, not a
/// second stack inside the workout's — that is a separate presentation context,
/// so it does not violate the in-workout-editing rule about competing stacks.
struct ProgressiveOverloadIncrementPicker: View {
    let exerciseName: String
    /// Canonical kilograms.
    let currentWeight: Double
    let isAssistance: Bool
    /// False for a pyramid/drop scheme. The step applies to every set either
    /// way, but only a uniform scheme has ONE resulting weight worth previewing
    /// — naming the first set's result for the others would be wrong.
    let hasUniformWeights: Bool
    /// Called with the step in **canonical kilograms** — this picker is the one
    /// place the user's display-space pick is converted, and it happens once.
    let onApply: (Double) -> Void
    /// Returns to the suggestion step. Not a sheet dismissal: the user asked to
    /// change the value, so backing out should land where they came from.
    let onCancel: () -> Void

    @Environment(\.weightUnit) private var weightUnit

    /// The crown drives the WEIGHT STEP directly, not an index into a preset
    /// list: boxing the user into four values was the whole complaint. The
    /// bounded/strided overload keeps haptic detents, which the unbounded one
    /// cannot — see `ProgressiveOverloadIncrement` for why a finite maximum.
    ///
    /// In **display units**, like the grid it moves along. `nil` until the view
    /// has seen its unit: the grid is per-unit, so the default cannot be
    /// resolved at initialization, before the environment exists.
    @State private var selectedIncrement: Double?
    @FocusState private var isCrownFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The current unit's steps. Pounds get their own plate steps rather than
    /// converted kilograms — see `ProgressiveOverloadIncrement`.
    private var grid: ProgressiveOverloadIncrement.Grid {
        ProgressiveOverloadIncrement.grid(for: weightUnit)
    }

    private var increment: Double {
        selectedIncrement ?? grid.defaultOption
    }

    /// `currentWeight` in the displayed unit. Every number this screen shows is
    /// computed in display space, so the arithmetic the user reads adds up
    /// exactly ("198,4 + 5 = 203,4") instead of drifting through a conversion.
    private var currentDisplayWeight: Double {
        weightUnit.converting(fromKilograms: currentWeight)
    }

    /// The result the user is about to apply, computed in display space.
    ///
    /// Goes through the SAME service the apply path uses rather than
    /// reimplementing its assistance clamp here — otherwise a future change to
    /// that rule would silently desync this preview from what actually gets
    /// applied. The service is unit-agnostic pure math, and the kg↔display
    /// conversion is linear, so feeding it display units is exact.
    private var resultingDisplayWeight: Double {
        ProgressiveOverloadService.increasedWeight(
            currentDisplayWeight,
            increment: increment,
            loadBehavior: isAssistance ? .counterweightAssistance : .resistance
        )
    }

    private var resultingWeightPreview: Text {
        hasUniformWeights
            ? Text(
                "→ \(WatchWeightFormatting.displayLabel(resultingDisplayWeight, in: weightUnit))",
                comment: "Resulting weight preview in the increment picker"
            )
            : Text("all sets", comment: "Increment picker preview when the target's sets do not share one weight")
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(exerciseName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onCancel) {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel(Text(
                            "Back", comment: "Returns from the increment picker to the suggestion"
                        ))
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            // The one conversion: the grid lives in display
                            // space, everything past this line is kilograms.
                            onApply(weightUnit.kilograms(fromDisplay: increment))
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .tint(OnyxWatch.Colors.warning)
                        .accessibilityLabel(Text(
                            "Apply", comment: "Confirms the chosen progressive-overload increment"
                        ))
                    }
                }
        }
        .onAppear { isCrownFocused = true }
    }

    private var content: some View {
        VStack(spacing: 10) {

            HStack(spacing: 10) {
                stepButton(systemName: "chevron.left", delta: -1)

                VStack(spacing: 3) {
                    Text(ProgressiveOverloadFormat.increment(
                        increment, isAssistance: isAssistance, in: weightUnit
                    ))
                        .font(.system(size: 24, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(OnyxWatch.Colors.warning)
                    resultingWeightPreview
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(OnyxWatch.Colors.warning.opacity(0.85))
                }
                // Proportional to the sheet's height rather than a hardcoded
                // point value, so the card neither wastes space on a large case
                // nor squeezes the presets off a small one.
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical, count: 10, span: 4, spacing: 0)
                .background(OnyxWatch.Colors.warning.opacity(0.16), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(OnyxWatch.Colors.warning, lineWidth: 2)
                }

                stepButton(systemName: "chevron.right", delta: 1)
            }
            // One Digital Crown owner on this screen, bound straight to the
            // weight step. `isContinuous: false` stops it wrapping around from
            // the maximum back to the minimum.
            .focusable(true)
            .focused($isCrownFocused)
            .digitalCrownRotation(
                crownValue,
                from: grid.minimum,
                through: grid.maximum,
                by: grid.step,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            // Switching units mid-picker cannot carry the number across: 2.5 kg
            // is not 2.5 lb. Drop back to the new unit's default rather than
            // reinterpreting the old figure on the new grid.
            .onChange(of: weightUnit) { _, _ in
                selectedIncrement = nil
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Weight increase", comment: "VoiceOver label for the increment picker"))
            .accessibilityValue(Text(ProgressiveOverloadFormat.increment(
                increment, isAssistance: isAssistance, in: weightUnit
            )))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(by: 1)
                case .decrement: step(by: -1)
                @unknown default: break
                }
            }

            // Presets stay one tap away. This replaced a dot indicator, which
            // was meaningless once the crown covered a continuous range.
            //
            // Dropped at accessibility text sizes: with no ScrollView to fall
            // back on, this row is the one piece worth sacrificing — the crown
            // still reaches every value it offers.
            if !dynamicTypeSize.isAccessibilitySize {
                presetChips
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    private var presetChips: some View {
        HStack(spacing: 5) {
            ForEach(grid.options, id: \.self) { preset in
                Button {
                    setIncrement(preset)
                } label: {
                        // In the same unit as everything else on screen — a
                        // bare number here read "2.5" next to a "+5.51 lb"
                        // preview back when the unit came from the locale.
                        Text(WatchWeightFormatting.incrementLabel(preset, in: weightUnit))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(
                                preset == increment
                                    ? OnyxWatch.Colors.textOnWarning
                                    : OnyxWatch.Colors.textSecondary
                            )
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(
                                preset == increment
                                    ? OnyxWatch.Colors.warning
                                    : OnyxWatch.Colors.card,
                                in: Capsule()
                            )
                    }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(
                    ProgressiveOverloadFormat.increment(
                        preset, isAssistance: isAssistance, in: weightUnit
                    )
                ))
            }
        }
    }

    private func stepButton(systemName: String, delta: Int) -> some View {
        Button {
            step(by: delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OnyxWatch.Colors.textSecondary)
                .frame(width: 40, height: 40)
                .background(OnyxWatch.Colors.card, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    /// The crown's binding. It normalizes on write because the crown writes
    /// directly: accumulated float drift would otherwise leave the value
    /// marginally off-grid and silently break the `preset == increment` chip
    /// highlight.
    private var crownValue: Binding<Double> {
        Binding(
            get: { increment },
            set: { selectedIncrement = ProgressiveOverloadIncrement.normalized($0, in: weightUnit) }
        )
    }

    /// Fine adjustment by one stride — the touch equivalent of one crown detent.
    private func step(by delta: Int) {
        setIncrement(increment + Double(delta) * grid.step)
    }

    private func setIncrement(_ value: Double) {
        let next = ProgressiveOverloadIncrement.normalized(value, in: weightUnit)
        guard next != increment else { return }
        selectedIncrement = next
        WKInterfaceDevice.current().play(.click)
    }
}

// MARK: - 2c · Confirmation

/// The success moment. It means "durably applied on this Watch for the next
/// workout" — deliberately NOT "already saved on iPhone", which may still be
/// pending while the phone is unreachable.
struct ProgressiveOverloadConfirmationView: View {
    /// Canonical kilograms.
    let newWeight: Double
    let targetRepMin: Int
    /// Progressing a counterweight stack REMOVES assistance, so the headline
    /// must not claim the weight went up. Wording matches the iOS
    /// `ProgressiveOverloadCard` (`rep_range.overload_card.reduced_to`).
    let isAssistance: Bool
    /// False for a pyramid/drop scheme, where `newWeight` is only the first
    /// set's result. The headline then states that every set moved rather than
    /// naming a weight the other sets do not have.
    let hasUniformWeights: Bool
    let onDismiss: () -> Void

    @Environment(\.weightUnit) private var weightUnit

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(OnyxWatch.Colors.accentGreen)
                    .shadow(color: OnyxWatch.Colors.accentGreen.opacity(0.4), radius: 17)
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(OnyxWatch.Colors.textOnTint)
            }
            .frame(width: 74, height: 74)

            VStack(spacing: 4) {
                if !hasUniformWeights {
                    // No single resulting weight exists for this scheme, so the
                    // moment states what actually happened to all of them.
                    Text(
                        "All sets increased",
                        comment: "Progressive-overload confirmation headline when the target's sets do not share one weight"
                    )
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(OnyxWatch.Colors.accentGreen)
                } else {
                    if isAssistance {
                        Text(
                            "Assistance reduced to",
                            comment: "Progressive-overload confirmation headline for counterweight-assistance exercises, where progressing means removing assistance"
                        )
                        .font(.system(size: 18, weight: .heavy))
                    } else {
                        Text("Increased to", comment: "Progressive-overload confirmation headline")
                            .font(.system(size: 20, weight: .heavy))
                    }
                    Text(ProgressiveOverloadFormat.weight(newWeight, in: weightUnit))
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(OnyxWatch.Colors.accentGreen)
                }
            }
            .multilineTextAlignment(.center)

            Text(
                "Applies from your next workout · starting at \(targetRepMin) reps",
                comment: "Progressive-overload confirmation detail; parameter is the rep-range minimum"
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(OnyxWatch.Colors.textMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnyxWatch.Colors.background.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .task {
            // Auto-returns to the workout so the flow costs one tap in total.
            try? await Task.sleep(for: .seconds(2))
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Formatting

/// Shared formatting for the three overload surfaces, over the watch's one
/// weight-formatting seam.
///
/// It used to format with `.formatted(.measurement(width: .abbreviated,
/// usage: .general))`, whose `usage: .general` re-derives the unit **from the
/// locale**. That is what made a US-locale watch show "80 lb" in the routine
/// overview beside a set editor that said "kg", and the older bug the comment
/// on `increment` records — "+2.5 kg" next to "→ 137.8 lb" — was the same
/// defect one layer down. Both are gone: the unit is the one synced preference,
/// for the value and for the word.
enum ProgressiveOverloadFormat {
    /// A **canonical kilogram** weight, converted and labelled in `unit`.
    static func weight(_ kilograms: Double, in unit: WeightUnit) -> String {
        WatchWeightFormatting.label(kilograms, in: unit)
    }

    /// The signed step as shown on the button: a counterweight stack progresses
    /// by REMOVING assistance, so the user sees a minus there.
    ///
    /// `value` is in **display units**, like the grid it comes from — the step
    /// and the resulting-weight preview are both computed in display space, so
    /// the arithmetic the user reads adds up exactly. Two fraction digits, so a
    /// 1.25 step reads "1,25" rather than being rounded to a misleading "1,3".
    static func increment(_ value: Double, isAssistance: Bool, in unit: WeightUnit) -> String {
        "\(isAssistance ? "−" : "+")\(WatchWeightFormatting.incrementLabel(value, in: unit))"
    }
}
