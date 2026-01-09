import SwiftUI

struct RestTimerView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            Text("Rest Time")
                .font(.headline)
                .foregroundStyle(.secondary)

            // Circular Progress Ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 12)
                    .frame(width: 160, height: 160)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.neonGreen, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                VStack(spacing: 4) {
                    Text(viewModel.formatTime(viewModel.restTimeRemaining))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text("remaining")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                // Minimize button
                Button {
                    dismiss()
                    onDismiss()
                } label: {
                    Text("Minimize")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.bordered)

                // Skip button
                Button {
                    viewModel.stopRestTimer()
                    dismiss()
                    onDismiss()
                } label: {
                    Text("Skip Rest")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(32)
        .onChange(of: viewModel.isRestTimerActive) { _, isActive in
            if !isActive {
                dismiss()
                onDismiss()
            }
        }
    }

    private var progress: CGFloat {
        let totalDuration = viewModel.restDuration
        guard totalDuration > 0 else { return 0 }

        return CGFloat(viewModel.restTimeRemaining / totalDuration)
    }
}
