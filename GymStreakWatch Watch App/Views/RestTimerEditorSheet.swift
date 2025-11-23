import SwiftUI

struct RestTimerEditorSheet: View {
    let currentRestTime: TimeInterval
    let onSave: (TimeInterval) -> Void
    let onCancel: () -> Void

    @State private var restTime: Double
    @Environment(\.dismiss) private var dismiss

    init(currentRestTime: TimeInterval, onSave: @escaping (TimeInterval) -> Void, onCancel: @escaping () -> Void) {
        self.currentRestTime = currentRestTime
        self.onSave = onSave
        self.onCancel = onCancel
        _restTime = State(initialValue: currentRestTime)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Rest Timer")
                    .font(.headline)
                    .padding(.top, 4)

                // Large, easy-to-tap rest time display
                VStack(spacing: 2) {
                    Text("DURATION")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(formattedTime)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.blue, lineWidth: 2)
                        )
                }
                .focusable(true)
                .digitalCrownRotation(
                    $restTime,
                    from: 0,
                    through: 600, // 10 minutes max
                    by: 5,        // 5-second increments
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                .onChange(of: restTime) { oldValue, newValue in
                    WKInterfaceDevice.current().play(.click)
                }
                .accessibilityLabel("Rest duration: \(formattedTime)")
                .accessibilityHint("Rotate Digital Crown to adjust, or select a preset button")

                // Common presets
                Text("QUICK SELECT")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                HStack(spacing: 6) {
                    ForEach([30, 60, 90, 120], id: \.self) { seconds in
                        Button("\(seconds)s") {
                            restTime = Double(seconds)
                            WKInterfaceDevice.current().play(.click)
                        }
                        .buttonStyle(.bordered)
                        .tint(restTime == Double(seconds) ? .blue : .gray)
                        .controlSize(.small)
                    }
                }

                // Save button
                Button {
                    saveChanges()
                } label: {
                    Text("Apply to All Sets")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .padding(.top, 8)

                // Cancel button
                Button {
                    WKInterfaceDevice.current().play(.click)
                    onCancel()
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .controlSize(.regular)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let minutes = Int(restTime) / 60
        let seconds = Int(restTime) % 60

        if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        } else {
            return "\(seconds)s"
        }
    }

    private func saveChanges() {
        WKInterfaceDevice.current().play(.success)
        onSave(restTime)
        dismiss()
    }
}

#Preview {
    RestTimerEditorSheet(
        currentRestTime: 90,
        onSave: { newTime in
            print("New rest time: \(newTime)")
        },
        onCancel: { }
    )
}
