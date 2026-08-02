//
//  SetValueKeypadSheet.swift
//  GymStreak
//
//  Editing one value of one set. This replaces the accordion that used to
//  expand inside the set list: the list stays still, nothing below it jumps,
//  and the value is changed where the user was already looking.
//
//  It carries its own keypad rather than a system keyboard so the sheet height
//  is fixed and the quick-step buttons stay reachable next to the digits.
//

import SwiftUI

struct SetValueKeypadSheet: View {
    let exerciseName: String
    let setNumber: Int
    let field: WorkoutSetField
    let display: WorkoutSetDisplay
    /// Hidden when this is the exercise's last incomplete set — there is nothing
    /// following to apply the value to.
    let canApplyToFollowing: Bool
    let onSave: (_ reps: Int, _ weight: Double, _ applyToFollowing: Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Typed digits. Empty means "untouched" — the current value is shown instead.
    @State private var buffer = ""
    @State private var applyToFollowing = false

    private var isReps: Bool { field == .reps }
    private static let decimalSeparator = Locale.current.decimalSeparator ?? "."

    private var baseValue: Double {
        isReps ? Double(display.reps) : display.weight
    }

    /// The value that would be saved right now.
    private var value: Double {
        guard !buffer.isEmpty else { return baseValue }
        return Double(buffer.replacingOccurrences(of: Self.decimalSeparator, with: ".")) ?? 0
    }

    private var displayedValue: String {
        buffer.isEmpty ? WorkoutValueFormatting.weight(baseValue) : buffer
    }

    private var unit: String {
        if isReps { return "set.reps_unit".localized }
        return display.isAssistance ? "exercise.assistance".localized : "set.weight_unit".localized
    }

    private var step: Double { isReps ? 1 : 2.5 }

    var body: some View {
        VStack(spacing: 0) {
            header
            quickSteps
            keypad

            if canApplyToFollowing {
                applyToFollowingToggle
            }

            applyButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DesignSystem.Colors.background)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("set.edit.context".localized(exerciseName, setNumber))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineLimit(1)

                    Text(isReps ? "set.reps_label".localized : "set.edit.weight_title".localized)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(displayedValue)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(unit)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }

            // The planned value stays visible: it is the reference the logged
            // value is judged against, and the old expanded editor showed it too.
            Text("set.planned_detail".localized(display.plannedReps, display.plannedWeight))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.bottom, 14)
    }

    // MARK: - Quick steps

    private var quickSteps: some View {
        HStack(spacing: 6) {
            ForEach([-2 * step, -step, step, 2 * step], id: \.self) { delta in
                Button {
                    HapticManager.shared.light()
                    buffer = format(max(0, value + delta))
                } label: {
                    Text((delta > 0 ? "+" : "−") + WorkoutValueFormatting.weight(abs(delta)))
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(DesignSystem.Colors.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(DesignSystem.Colors.tint.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DesignSystem.Colors.tint.opacity(0.22), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Keypad

    private var keypad: some View {
        Grid(horizontalSpacing: 7, verticalSpacing: 7) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(1...3, id: \.self) { column in
                        let digit = String(row * 3 + column)
                        keypadKey(digit) { push(digit) }
                    }
                }
            }
            GridRow {
                if isReps {
                    Color.clear.frame(height: 50)
                } else {
                    keypadKey(Self.decimalSeparator) { push(Self.decimalSeparator) }
                }
                keypadKey("0") { push("0") }
                keypadKey(symbol: "delete.backward") {
                    buffer = String(buffer.dropLast())
                }
            }
        }
    }

    private func keypadKey(_ label: String? = nil, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.light()
            action()
        } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .medium))
                } else {
                    Text(label ?? "")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == nil ? (label ?? "") : "action.delete".localized)
    }

    // MARK: - Apply to following

    private var applyToFollowingToggle: some View {
        Button {
            HapticManager.shared.light()
            applyToFollowing.toggle()
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(applyToFollowing ? DesignSystem.Colors.tint : Color.clear)
                        .frame(width: 20, height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(applyToFollowing ? 0 : 0.25), lineWidth: 1.6)
                        )

                    if applyToFollowing {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(DesignSystem.Colors.textOnTint)
                    }
                }

                Text("set.apply_to_following".localized)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(applyToFollowing ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Apply

    private var applyButton: some View {
        Button {
            HapticManager.shared.success()
            if isReps {
                onSave(Int(value.rounded()), display.weight, applyToFollowing)
            } else {
                onSave(display.reps, value, applyToFollowing)
            }
            dismiss()
        } label: {
            Text("action.apply".localized)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textOnTint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DesignSystem.Colors.tint)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    // MARK: - Buffer editing

    private func push(_ character: String) {
        // One separator only, and never as the leading character.
        if character == Self.decimalSeparator {
            guard !buffer.contains(Self.decimalSeparator) else { return }
            buffer = buffer.isEmpty ? "0" + character : buffer + character
            return
        }
        guard buffer.count < 6 else { return }
        buffer += character
    }

    private func format(_ value: Double) -> String {
        isReps ? String(Int(value.rounded())) : WorkoutValueFormatting.weight(value)
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            SetValueKeypadSheet(
                exerciseName: "Chest Press",
                setNumber: 3,
                field: .weight,
                display: WorkoutSetDisplay(
                    id: UUID(), number: 3, reps: 5, weight: 90, plannedReps: 5, plannedWeight: 90,
                    isCompleted: false, completedAt: nil, isAssistance: false,
                    targetRepMin: 4, targetRepMax: 6
                ),
                canApplyToFollowing: true,
                onSave: { _, _, _ in }
            )
            .presentationDetents([.height(520)])
            .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
}
