//
//  SetValueKeypad.swift
//  GymStreak
//
//  The digit pad of `SetValueKeypadSheet`. Split out so the sheet stays about
//  editing one set value and this stays about typing digits into a buffer.
//

import SwiftUI

/// A 3×4 numeric pad that edits a string buffer of typed digits.
///
/// It carries its own keys rather than raising the system keyboard so the sheet
/// height is fixed and the quick-step buttons stay reachable next to the digits.
struct SetValueKeypad: View {

    /// Typed digits. Empty means "untouched" — the caller shows the current
    /// value instead.
    @Binding var buffer: String
    /// `false` for integer fields such as reps, which blanks the separator key.
    let allowsDecimalSeparator: Bool

    /// Shared with the sheet, which parses the buffer with it.
    static let decimalSeparator = Locale.current.decimalSeparator ?? "."

    var body: some View {
        Grid(horizontalSpacing: 7, verticalSpacing: 7) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(1...3, id: \.self) { column in
                        let digit = String(row * 3 + column)
                        key(digit) { push(digit) }
                    }
                }
            }
            GridRow {
                if allowsDecimalSeparator {
                    key(Self.decimalSeparator) { push(Self.decimalSeparator) }
                } else {
                    Color.clear.frame(height: 50)
                }
                key("0") { push("0") }
                key(symbol: "delete.backward") {
                    buffer = String(buffer.dropLast())
                }
            }
        }
    }

    private func key(_ label: String? = nil, symbol: String? = nil, action: @escaping () -> Void) -> some View {
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
}
