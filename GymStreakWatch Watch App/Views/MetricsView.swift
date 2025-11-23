import SwiftUI

struct MetricsView: View {
    let elapsedTime: String
    let heartRate: Double
    let calories: Double

    @EnvironmentObject var viewModel: WatchWorkoutViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Compact timer integrated into layout
            if viewModel.isResting && viewModel.isRestTimerMinimized {
                CompactRestTimer(
                    timeRemaining: viewModel.restTimeRemaining,
                    totalDuration: viewModel.restDuration,
                    formattedTime: viewModel.formattedRestTime,
                    onSkip: viewModel.skipRest,
                    onExpand: viewModel.expandRestTimer
                )
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            VStack(spacing: 12) {
                // Elapsed time
                Text(elapsedTime)
                    .font(.system(.title, design: .rounded).monospacedDigit())
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Elapsed time \(elapsedTime)")

                HStack(spacing: 20) {
                    // Heart rate
                    VStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text("\(Int(heartRate))")
                            .font(.title3.monospacedDigit())
                            .fontWeight(.semibold)
                        Text("BPM")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Heart rate \(Int(heartRate)) beats per minute")

                    // Calories
                    VStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(Int(calories))")
                            .font(.title3.monospacedDigit())
                            .fontWeight(.semibold)
                        Text("CAL")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(Int(calories)) calories burned")
                }
            }
            .scenePadding()
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isResting)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isRestTimerMinimized)
    }
}

#Preview {
    MetricsView(
        elapsedTime: "23:45",
        heartRate: 142,
        calories: 234
    )
}
