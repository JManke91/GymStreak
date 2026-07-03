//
//  OnyxTextField.swift
//  GymStreak
//
//  Styled text input for the Onyx Design System
//

import SwiftUI

/// A text field styled with Onyx Design System colors
struct OnyxTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.input)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusSM))
    }
}

/// A numeric text field styled with Onyx Design System colors
struct OnyxNumericField: View {
    let placeholder: String
    @Binding var value: Double
    var format: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0...2))
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, value: $value, format: format)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.onyxNumber)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.input)
            .foregroundStyle(DesignSystem.Colors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Dimensions.cornerRadiusSM))
            .focused($isFocused)
            .selectAllOnFocus()
    }
}

// MARK: - Previews

#Preview("Text Fields") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        VStack(spacing: 16) {
            OnyxTextField(placeholder: "Exercise name", text: .constant("Bench Press"))

            OnyxTextField(placeholder: "Notes", text: .constant(""))

            OnyxNumericField(placeholder: "0.0", value: .constant(100.0))
        }
        .padding()
    }
}
