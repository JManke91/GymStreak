import SwiftUI

struct RestTimerView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    /// Shared namespace with `WorkoutRestBar` — carries the shrink/grow morph.
    let namespace: Namespace.ID
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Text("rest_timer.title".localized)
                .font(.headline)
                .foregroundStyle(.secondary)

            // Circular Progress Ring + time label — both shared with the compact
            // bar via matchedGeometryEffect, so they shrink and travel into
            // the bottom rest bar on minimize (and grow back on expand).
            ZStack {
                // The effect must sit *inside* the frame: it overrides the size
                // proposal handed to the ring, which is what makes the diameter
                // interpolate. A hard frame between effect and ring would pin it.
                RestTimerRing(progress: progress)
                    .matchedGeometryEffect(id: RestTimerMorph.ringID, in: namespace)
                    .frame(width: RestTimerMorph.largeRingDiameter, height: RestTimerMorph.largeRingDiameter)

                VStack(spacing: 4) {
                    Text(viewModel.formatTime(viewModel.restTimeRemaining))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        // Position-only match + fixedSize: the label travels but
                        // always renders at its own intrinsic size. Matching the
                        // frame would squeeze it into the other state's box and
                        // make it re-lay out (and jitter) on every step.
                        .fixedSize()
                        .contentTransition(.identity)
                        .matchedGeometryEffect(id: RestTimerMorph.timeLabelID, in: namespace, properties: .position)
                    Text("rest_timer.remaining".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .geometryGroup()

            if let warning = viewModel.restTimerReminderWarning {
                Label(warning, systemImage: "bell.slash.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }

            // Action buttons
            HStack(spacing: 12) {
                // Minimize button
                Button {
                    onDismiss()
                } label: {
                    Text("rest_timer.minimize".localized)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.bordered)

                // Skip button
                Button {
                    viewModel.stopRestTimer()
                    onDismiss()
                } label: {
                    Text("rest_timer.skip".localized)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(32)
        // Note: closing when the timer stops is owned by ActiveWorkoutView, which
        // observes `isRestTimerActive` and forces the overlay closed — no handler
        // here, so the two never race on the same state change.
    }

    private var progress: CGFloat {
        let totalDuration = viewModel.restDuration
        guard totalDuration > 0 else { return 0 }

        return CGFloat(viewModel.restTimeRemaining / totalDuration)
    }
}
