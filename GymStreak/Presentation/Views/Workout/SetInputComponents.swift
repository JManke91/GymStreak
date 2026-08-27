//
//  SetInputComponents.swift
//  GymStreak
//
//  Reusable components for editing exercise sets (reps and weight)
//

import SwiftUI

/// A horizontal stepper with minus/plus buttons on left/right of the value
struct HorizontalStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let onUpdate: (Int) -> Void

    init(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int> = 1...100,
        step: Int = 1,
        onUpdate: @escaping (Int) -> Void = { _ in }
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.onUpdate = onUpdate
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .fixedSize()

            Spacer()

            // Minus button
            Button {
                guard value > range.lowerBound else { return }
                withAnimation(.snappy(duration: 0.3)) {
                    value -= step
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(value <= range.lowerBound ? DesignSystem.Colors.textDisabled : DesignSystem.Colors.tint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(value <= range.lowerBound)

            // Tappable number display
            Text("\(value)")
                .font(.onyxNumber)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(minWidth: 44)
                .contentShape(Rectangle())

            // Plus button
            Button {
                guard value < range.upperBound else { return }
                withAnimation(.snappy(duration: 0.3)) {
                    value += step
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(value >= range.upperBound ? DesignSystem.Colors.textDisabled : DesignSystem.Colors.tint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(value >= range.upperBound)
        }
        .onChange(of: value) { _, newValue in
            onUpdate(newValue)
        }
    }
}

/// A weight input with TextField for keyboard entry and stepper buttons for quick adjustments.
///
/// The binding is always **canonical kilograms**; the field edits a display-space
/// mirror of it, so a pounds user types and steps in pounds while the store keeps
/// kilograms. `weightDisplayMirror` owns that whole invariant.
struct WeightInput: View {
    let title: String
    /// Canonical kilograms.
    @Binding var weight: Double
    /// Called with canonical kilograms.
    let onUpdate: (Double) -> Void

    @Environment(\.weightUnit) private var weightUnit
    @FocusState private var isFocused: Bool
    /// `weight` expressed in `weightUnit` — the value the field actually edits.
    @State private var displayValue: Double = 0

    init(
        title: String,
        weight: Binding<Double>,
        onUpdate: @escaping (Double) -> Void = { _ in }
    ) {
        self.title = title
        self._weight = weight
        self.onUpdate = onUpdate
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .fixedSize()

            Spacer()

            // Minus button
            Button {
                let next = max(0, displayValue - weightUnit.fineIncrement)
                withAnimation(.snappy(duration: 0.3)) {
                    displayValue = next
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(displayValue <= 0 ? DesignSystem.Colors.textDisabled : DesignSystem.Colors.tint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(displayValue <= 0)

            // Editable weight field, in the displayed unit
            TextField("0", value: $displayValue, format: WeightFormatting.inputStyle(for: weightUnit))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.onyxNumber)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .frame(width: 70)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(DesignSystem.Colors.input)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusSM))
                .focused($isFocused)
                .selectAllOnFocus()

            // Plus button
            Button {
                let next = min(displayValue + weightUnit.fineIncrement, weightUnit.maximumDisplay)
                withAnimation(.snappy(duration: 0.3)) {
                    displayValue = next
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DesignSystem.Colors.tint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("action.done".localized) {
                    isFocused = false
                }
                .fontWeight(.semibold)
            }
        }
        .weightDisplayMirror(
            kilograms: $weight,
            displayValue: $displayValue,
            onUpdate: onUpdate
        )
    }
}

// MARK: - Previews

#Preview("Horizontal Stepper") {
    struct PreviewWrapper: View {
        @State private var reps = 10

        var body: some View {
            Form {
                Section {
                    HorizontalStepper(
                        title: "Reps",
                        value: $reps,
                        range: 1...100,
                        step: 1
                    ) { newValue in
                        print("Reps updated to \(newValue)")
                    }
                }
            }
        }
    }

    return PreviewWrapper()
}

#Preview("Weight Input") {
    struct PreviewWrapper: View {
        @State private var weight = 20.0

        var body: some View {
            Form {
                Section {
                    WeightInput(
                        title: "Weight (kg)",
                        weight: $weight
                    ) { newValue in
                        print("Weight updated to \(newValue)")
                    }
                }
            }
        }
    }

    return PreviewWrapper()
}

// MARK: - Select All on Focus Modifier

/// A view modifier that selects all text in a TextField when it receives focus
struct SelectAllOnFocusModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { notification in
                if let textField = notification.object as? UITextField {
                    // Delay slightly to ensure the text field is fully focused
                    DispatchQueue.main.async {
                        textField.selectAll(nil)
                    }
                }
            }
    }
}

extension View {
    /// Selects all text in a TextField when it receives focus
    func selectAllOnFocus() -> some View {
        modifier(SelectAllOnFocusModifier())
    }
}

#Preview("Combined Set Editor") {
    struct PreviewWrapper: View {
        @State private var reps = 10
        @State private var weight = 20.0

        var body: some View {
            Form {
                Section("Edit Set") {
                    HorizontalStepper(
                        title: "Reps",
                        value: $reps,
                        range: 1...100,
                        step: 1
                    )

                    WeightInput(
                        title: "Weight (kg)",
                        weight: $weight
                    )
                }
            }
        }
    }

    return PreviewWrapper()
}
