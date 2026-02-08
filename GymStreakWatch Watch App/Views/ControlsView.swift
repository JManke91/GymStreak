import SwiftUI

struct ControlsView: View {
    let isPaused: Bool
    let onPause: () -> Void
    let onResume: () -> Void
    let onEnd: () -> Void

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

            VStack(spacing: 16) {
                // Pause/Resume as primary action
                Button(action: isPaused ? onResume : onPause) {
                    Label(
                        isPaused ? "Resume" : "Pause",
                        systemImage: isPaused ? "play.fill" : "pause.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(isPaused ? OnyxWatch.Colors.success : OnyxWatch.Colors.warning)
                .controlSize(.large)
                .accessibilityHint(isPaused ? "Double tap to resume workout" : "Double tap to pause workout")

                // End as secondary, destructive action
                Button(action: onEnd) {
                    Label("End Workout", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(OnyxWatch.Colors.destructive)
                .accessibilityLabel("End workout")
                .accessibilityHint("Double tap to end and save your workout")
            }
            .scenePadding()
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isResting)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isRestTimerMinimized)
    }
}

#Preview {
    ControlsView(
        isPaused: false,
        onPause: { },
        onResume: { },
        onEnd: { }
    )
}
