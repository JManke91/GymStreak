import SwiftUI

/// Shared constants for the large↔compact rest-timer morph.
enum RestTimerMorph {
    /// `matchedGeometryEffect` ids — one shared ring, one shared time label.
    static let ringID = "restTimerRing"
    static let timeLabelID = "restTimerTimeLabel"

    static let largeRingDiameter: CGFloat = 160
    static let compactRingDiameter: CGFloat = 32

    static let animation: Animation = .spring(response: 0.45, dampingFraction: 0.85)
}

/// Shared circular countdown ring used by both rest-timer states (the large
/// overlay and the compact top banner).
///
/// It deliberately has **no intrinsic size**: it fills whatever size its
/// container proposes, and the stroke width scales with the diameter. That is
/// what lets `matchedGeometryEffect` morph it continuously between the 160pt
/// large ring and the 32pt compact ring — a hard-coded frame or stroke width
/// would not interpolate.
struct RestTimerRing: View {
    let progress: CGFloat

    /// 12pt stroke at the large 160pt diameter; scales down proportionally.
    private static let strokeRatio: CGFloat = 0.075

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(2, diameter * Self.strokeRatio)

            ZStack {
                Circle()
                    .stroke(DesignSystem.Colors.divider, lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(DesignSystem.Colors.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
            }
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
