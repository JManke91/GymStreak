import SwiftUI

struct RestTimerView: View {
    let timeRemaining: TimeInterval
    let totalDuration: TimeInterval
    let formattedTime: String
    let state: WatchWorkoutViewModel.RestTimerState
    let onSkip: () -> Void
    let onMinimize: () -> Void

    var body: some View {
        let _ = print("🎨 Rendering RestTimerView - state: \(state)")
        ZStack {
            // Running timer state
            VStack(spacing: 8) {
                Text("Rest")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Large timer display
                Text(formattedTime)
                    .font(.system(.title, design: .rounded).monospacedDigit())
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Rest time remaining \(formattedTime)")

                // Progress ring - slightly smaller
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 5)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.yellow, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)
                }
                .frame(width: 55, height: 55)

                // Horizontal button layout - only show in running state
                HStack(spacing: 8) {
                    Button {
                        onMinimize()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .accessibilityLabel("Minimize")
                    .accessibilityHint("Double tap to minimize rest timer")

                    Button {
                        onSkip()
                    } label: {
                        Text("Skip")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .accessibilityHint("Double tap to skip rest")
                }
                .buttonBorderShape(.capsule)
            }
            .opacity(state == .running ? 1 : 0)

            // Beautiful completion screen
            VStack(spacing: 12) {
                let _ = print("✅ Completion view in hierarchy - opacity: \(state == .completed ? 1.0 : 0.0)")
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: state == .completed)

                Text("Let's Go!")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.green)

                Text("Rest Complete")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .opacity(state == .completed ? 1 : 0)
            .scaleEffect(state == .completed ? 1.0 : 0.85)
            .accessibilityLabel("Rest complete. Let's go!")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.black))
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: state)
    }

    private var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return timeRemaining / totalDuration
    }
}

// MARK: - Compact Rest Timer

struct CompactRestTimer: View {
    let timeRemaining: TimeInterval
    let totalDuration: TimeInterval
    let formattedTime: String
    let onSkip: () -> Void
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Circular progress indicator - smaller
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2.5)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
            }
            .frame(width: 20, height: 20)

            // Timer text - no icon to save space
            Text(formattedTime)
                .font(.system(size: 14, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)

            Spacer()

            // Expand chevron
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.95))
                .shadow(color: .black.opacity(0.2), radius: 4, y: -1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            WKInterfaceDevice.current().play(.click)
            onExpand()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            WKInterfaceDevice.current().play(.success)
            onSkip()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rest timer, \(formattedTime) remaining")
        .accessibilityHint("Tap to expand timer. Long press to skip rest.")
    }

    private var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return timeRemaining / totalDuration
    }
}

#Preview("Running") {
    RestTimerView(
        timeRemaining: 45,
        totalDuration: 90,
        formattedTime: "0:45",
        state: .running,
        onSkip: { },
        onMinimize: { }
    )
}

#Preview("Completed") {
    RestTimerView(
        timeRemaining: 0,
        totalDuration: 90,
        formattedTime: "0:00",
        state: .completed,
        onSkip: { },
        onMinimize: { }
    )
}
