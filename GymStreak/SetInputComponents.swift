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

/// A weight input with TextField for keyboard entry and stepper buttons for quick adjustments
struct WeightInput: View {
    let title: String
    @Binding var weight: Double
    let increment: Double
    let onUpdate: (Double) -> Void
    @FocusState private var isFocused: Bool
    @State private var lastReportedValue: Double?

    init(
        title: String = "Weight (kg)",
        weight: Binding<Double>,
        increment: Double = 0.25,
        onUpdate: @escaping (Double) -> Void = { _ in }
    ) {
        self.title = title
        self._weight = weight
        self.increment = increment
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
                let newWeight = max(0, weight - increment)
                withAnimation(.snappy(duration: 0.3)) {
                    weight = newWeight
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // Directly call onUpdate for button clicks
                lastReportedValue = newWeight
                onUpdate(newWeight)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(weight <= 0 ? DesignSystem.Colors.textDisabled : DesignSystem.Colors.tint)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(weight <= 0)

            // Editable weight field
            TextField("0.0", value: $weight, format: .number.precision(.fractionLength(0...2)))
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
                .onChange(of: weight) { oldValue, newValue in
                    // Round to nearest increment (e.g., 0.25kg)
                    let rounded = round(newValue / increment) * increment

                    // Only update if this is a new value we haven't reported yet
                    // This prevents feedback loops from external updates
                    if rounded != lastReportedValue {
                        if rounded != newValue {
                            weight = rounded
                        }
                        lastReportedValue = rounded
                        onUpdate(rounded)
                    }
                }

            // Plus button
            Button {
                let newWeight = weight + increment
                withAnimation(.snappy(duration: 0.3)) {
                    weight = newWeight
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // Directly call onUpdate for button clicks
                lastReportedValue = newWeight
                onUpdate(newWeight)
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
                        weight: $weight,
                        increment: 0.25
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
                        weight: $weight,
                        increment: 0.25
                    )
                }
            }
        }
    }

    return PreviewWrapper()
}
