//
//  ConditioningGauge.swift
//  GymStreakWatch Watch App
//
//  The runner's 240° gauge, open at the bottom and following the watch edge
//  (docs/fight-conditioning.md, watch runner redesign). One geometry for both
//  pages: the heart-rate zone gauge and the phase-countdown ring. Sizes come
//  from the design canvas, drawn for the Ultra 3 (211 pt wide) and scaled by
//  width, so the 40 mm SE shows the same layout without scrolling.
//

import SwiftUI

// `nonisolated`: `Shape.path(in:)` is nonisolated, and the watch module defaults to MainActor.
nonisolated struct ConditioningGaugeLayout {
    static let designWidth: CGFloat = 211
    static let startDegrees = 150.0
    static let sweepDegrees = 240.0

    let size: CGSize

    var scale: CGFloat { size.width / Self.designWidth }
    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.47) }
    var radius: CGFloat { min(size.width, size.height) * 0.43 }
    /// Where the two ends of the arc sit — the top of the bottom opening.
    var endsY: CGFloat { center.y + radius * 0.5 }

    func angle(_ fraction: Double) -> Angle {
        .degrees(Self.startDegrees + Self.sweepDegrees * fraction)
    }

    func point(_ fraction: Double, inset: CGFloat = 0) -> CGPoint {
        let radians = angle(fraction).radians
        let r = radius - inset
        return CGPoint(x: center.x + r * cos(radians), y: center.y + r * sin(radians))
    }
}

/// A stretch of the gauge between two fractions.
nonisolated struct ConditioningGaugeArc: Shape {
    var from: Double
    var to: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(from, to) }
        set { from = newValue.first; to = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let layout = ConditioningGaugeLayout(size: rect.size)
        var path = Path()
        guard to > from else { return path }
        // SwiftUI's `clockwise` is flipped in y-down space: increasing angles here
        // run clockwise on screen, from lower left over the top to lower right.
        path.addArc(
            center: layout.center,
            radius: layout.radius,
            startAngle: layout.angle(from),
            endAngle: layout.angle(to),
            clockwise: false
        )
        return path
    }
}

/// The heart-rate gauge: track, the tinted below/above stretches, the target band,
/// the bound labels and the marker. Without a range it is a plain progress ring.
struct ConditioningZoneGaugeView: View {
    let zone: WatchHeartRateZone?
    let heartRate: Int?
    let status: ConditioningZoneStatus?
    /// Drawn instead of the band when there is no range (RPE-only).
    let progress: Double

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        GeometryReader { proxy in
            let layout = ConditioningGaugeLayout(size: proxy.size)
            let s = layout.scale
            let stroke = StrokeStyle(lineWidth: 6 * s, lineCap: .round)
            ZStack {
                ConditioningGaugeArc(from: 0, to: 1).stroke(OnyxWatch.Colors.gaugeTrack, style: stroke)
                if let zone {
                    let band = ConditioningZoneGauge.band(of: zone)
                    ConditioningGaugeArc(from: 0, to: band.lowerBound - 0.012)
                        .stroke(OnyxWatch.Colors.zoneBelow.opacity(0.28), style: stroke)
                    ConditioningGaugeArc(from: band.upperBound + 0.012, to: 1)
                        .stroke(OnyxWatch.Colors.zoneAbove.opacity(0.28), style: stroke)
                    ConditioningGaugeArc(from: band.lowerBound, to: band.upperBound)
                        .stroke(
                            OnyxWatch.Colors.tint.opacity(status == .inZone ? 1 : 0.55),
                            style: StrokeStyle(lineWidth: 8 * s, lineCap: .round)
                        )
                    boundLabel(zone.lowerBPM, at: layout.point(band.lowerBound, inset: 15 * s), scale: s)
                    boundLabel(zone.upperBPM, at: layout.point(band.upperBound, inset: 15 * s), scale: s)
                    if let heartRate {
                        marker(at: layout.point(ConditioningZoneGauge.fraction(of: heartRate, in: zone)), scale: s)
                    }
                } else {
                    ConditioningGaugeArc(from: 0, to: progress)
                        .stroke(OnyxWatch.Colors.textPrimary, style: stroke)
                }
            }
            .animation(.easeInOut(duration: 0.6), value: heartRate)
        }
        .accessibilityHidden(true)
    }

    private func boundLabel(_ bpm: Int, at point: CGPoint, scale s: CGFloat) -> some View {
        Text("\(bpm)")
            .font(.system(size: 8 * s, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(OnyxWatch.Colors.textSecondary)
            .position(point)
    }

    private func marker(at point: CGPoint, scale s: CGFloat) -> some View {
        let color = ConditioningRunnerStyle.color(for: status)
        return ZStack {
            if !isLuminanceReduced {
                Circle().fill(color.opacity(0.55)).frame(width: 22 * s, height: 22 * s).blur(radius: 4 * s)
            }
            Circle().fill(OnyxWatch.Colors.background).frame(width: 13 * s, height: 13 * s)
            Circle().stroke(color, lineWidth: 2.5 * s).frame(width: 13 * s, height: 13 * s)
            Circle().fill(OnyxWatch.Colors.textPrimary).frame(width: 4 * s, height: 4 * s)
        }
        .position(point)
    }
}

enum ConditioningRunnerStyle {
    static func color(for status: ConditioningZoneStatus?) -> Color {
        switch status {
        case .below: OnyxWatch.Colors.zoneBelow
        case .above: OnyxWatch.Colors.zoneAbove
        case .inZone: OnyxWatch.Colors.tint
        case nil: OnyxWatch.Colors.textPrimary
        }
    }

    /// Rounded, heavy, scaled with the screen.
    static func font(_ size: CGFloat, _ scale: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size * scale, weight: weight, design: .rounded).monospacedDigit()
    }
}
