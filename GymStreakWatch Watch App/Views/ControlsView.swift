import SwiftUI

struct ControlsView: View {
    let isPaused: Bool
    let onPause: () -> Void
    let onResume: () -> Void
    let onEnd: () -> Void

    var body: some View {
        // The minimized rest timer is NOT declared here — ActiveWorkoutView owns
        // the single instance and overlays it above every workout screen.
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
}

#Preview {
    ControlsView(
        isPaused: false,
        onPause: { },
        onResume: { },
        onEnd: { }
    )
}
