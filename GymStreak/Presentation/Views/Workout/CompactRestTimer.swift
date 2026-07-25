import SwiftUI

/// Compact rest-timer banner shown in `ActiveWorkoutView`'s top safe-area inset
/// while a rest is running and the large timer is minimized. Shares its ring and
/// time label with `RestTimerView` through `namespace` (see `RestTimerRing`).
struct CompactRestTimer: View {
    @ObservedObject var viewModel: WorkoutViewModel
    /// Shared namespace with `RestTimerView` — carries the shrink/grow morph.
    let namespace: Namespace.ID
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Circular progress indicator (small) — shared with the large timer.
            // The effect sits inside the frame so the diameter interpolates.
            RestTimerRing(progress: progress)
                .matchedGeometryEffect(id: RestTimerMorph.ringID, in: namespace)
                .frame(width: RestTimerMorph.compactRingDiameter, height: RestTimerMorph.compactRingDiameter)

            // Timer text
            VStack(alignment: .leading, spacing: 2) {
                Text("rest_timer.title".localized)
                    .font(.onyxCaption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Text(viewModel.formatTime(viewModel.restTimeRemaining))
                    .font(.onyxNumber)
                    // See RestTimerView: position-only match, intrinsic size, and
                    // no content transition — otherwise the digits jitter as the
                    // morph settles.
                    .fixedSize()
                    .contentTransition(.identity)
                    .matchedGeometryEffect(id: RestTimerMorph.timeLabelID, in: namespace, properties: .position)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                // Skip button
                Button {
                    viewModel.stopRestTimer()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.warning)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Expand button
                Button {
                    onExpand()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.card)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(DesignSystem.Colors.divider),
            alignment: .bottom
        )
        // Resolve this banner's geometry as one unit so the morph is not
        // re-interpolated against the scroll view's own layout pass.
        .geometryGroup()
    }

    private var progress: CGFloat {
        let totalDuration = viewModel.restDuration
        guard totalDuration > 0 else { return 0 }

        return CGFloat(viewModel.restTimeRemaining / totalDuration)
    }
}
