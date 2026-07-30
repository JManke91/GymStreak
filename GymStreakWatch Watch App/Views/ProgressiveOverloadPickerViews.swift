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
    let currentWeight: Double
    let isAssistance: Bool
    let onApply: (Double) -> Void
    /// Returns to the suggestion step. Not a sheet dismissal: the user asked to
    /// change the value, so backing out should land where they came from.
    let onCancel: () -> Void

    /// The crown drives the WEIGHT STEP directly, not an index into a preset
    /// list: boxing the user into four values was the whole complaint. The
    /// bounded/strided overload keeps haptic detents, which the unbounded one
    /// cannot — see `ProgressiveOverloadIncrement` for why a finite maximum.
    @State private var increment: Double = ProgressiveOverloadIncrement.default
    @FocusState private var isCrownFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var resultingWeight: Double {
        ProgressiveOverloadService.increasedWeight(
            currentWeight,
            increment: increment,
            loadBehavior: isAssistance ? .counterweightAssistance : .resistance
        )
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
                            onApply(increment)
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
                    Text(ProgressiveOverloadFormat.increment(increment, isAssistance: isAssistance))
                        .font(.system(size: 24, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(OnyxWatch.Colors.warning)
                    Text(
                        "→ \(ProgressiveOverloadFormat.weight(resultingWeight))",
                        comment: "Resulting weight preview in the increment picker"
                    )
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
                $increment,
                from: ProgressiveOverloadIncrement.minimum,
                through: ProgressiveOverloadIncrement.maximum,
                by: ProgressiveOverloadIncrement.step,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            // The crown writes the binding directly, so accumulated float drift
            // could leave the value marginally off-grid and silently break the
            // `preset == increment` chip highlight. Snap it back.
            .onChange(of: increment) { _, value in
                let snapped = ProgressiveOverloadIncrement.normalized(value)
                if snapped != value { increment = snapped }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Weight increase", comment: "VoiceOver label for the increment picker"))
            .accessibilityValue(Text(ProgressiveOverloadFormat.increment(increment, isAssistance: isAssistance)))
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
            ForEach(ProgressiveOverloadIncrement.options, id: \.self) { preset in
                Button {
                    setIncrement(preset)
                } label: {
                        // Locale-converted like every other weight on screen —
                        // a bare number here read "2.5" next to a "+5.51 lb"
                        // preview in a pounds locale.
                        Text(ProgressiveOverloadFormat.weight(preset))
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
                    ProgressiveOverloadFormat.increment(preset, isAssistance: isAssistance)
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

    /// Fine adjustment by one stride — the touch equivalent of one crown detent.
    private func step(by delta: Int) {
        setIncrement(increment + Double(delta) * ProgressiveOverloadIncrement.step)
    }

    private func setIncrement(_ value: Double) {
        let next = ProgressiveOverloadIncrement.normalized(value)
        guard next != increment else { return }
        increment = next
        WKInterfaceDevice.current().play(.click)
    }
}

// MARK: - 2c · Confirmation

/// The success moment. It means "durably applied on this Watch for the next
/// workout" — deliberately NOT "already saved on iPhone", which may still be
/// pending while the phone is unreachable.
struct ProgressiveOverloadConfirmationView: View {
    let newWeight: Double
    let targetRepMin: Int
    /// Progressing a counterweight stack REMOVES assistance, so the headline
    /// must not claim the weight went up. Wording matches the iOS
    /// `ProgressiveOverloadCard` (`rep_range.overload_card.reduced_to`).
    let isAssistance: Bool
    let onDismiss: () -> Void

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
                Text(ProgressiveOverloadFormat.weight(newWeight))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(OnyxWatch.Colors.accentGreen)
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

/// Shared, allocation-light formatting for the three surfaces. `FormatStyle`
/// rather than a `MeasurementFormatter` instance, per the repository's
/// main-thread rules.
enum ProgressiveOverloadFormat {
    /// Up to two fraction digits so a 1.25 kg step reads "1.25 kg" rather than
    /// being rounded to "1.2 kg" by the default precision.
    static func weight(_ kilograms: Double) -> String {
        Measurement(value: kilograms, unit: UnitMass.kilograms)
            .formatted(.measurement(
                width: .abbreviated,
                usage: .general,
                numberFormatStyle: .number.precision(.fractionLength(0...2))
            ))
    }

    /// The signed step as shown on the button: a counterweight stack progresses
    /// by REMOVING assistance, so the user sees a minus there.
    ///
    /// Formatted through the SAME locale-aware `Measurement` path as `weight`.
    /// Hardcoding " kg" here made the step and the resulting-weight preview
    /// disagree in both unit and magnitude in a locale that displays pounds
    /// (e.g. "+2.5 kg" next to "→ 137.8 lb").
    static func increment(_ value: Double, isAssistance: Bool) -> String {
        "\(isAssistance ? "−" : "+")\(weight(value))"
    }
}
