//
//  RestDurationAdjustmentChrome.swift
//  GymStreakWatch Watch App
//
//  The editing treatment of the large rest timer: everything that appears while
//  the Digital Crown is changing the rest duration. Split out of
//  RestTimerLargeView, which owns the Crown itself.
//
//  Neither piece takes layout space of its own — this screen has none to give.
//  The badge is an OVERLAY on the "REST" caption, and the footer BORROWS the
//  Minimize/Skip slot, cross-fading with the buttons while the Crown turns.
//  That is what keeps the digits exactly where they are when an adjustment
//  starts. See `docs/watch-rest-timer-ui.md` for the two layouts that were
//  tried first and why each failed on a real 46 mm watch.
//

import SwiftUI

enum RestAdjustmentChrome {
    static let crossfade: TimeInterval = 0.12

    static func durationText(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// "REST", or the `+15 s` badge while adjusting.
///
/// The caption is always the layout element — the badge is drawn over it, so it
/// may be wider and taller without moving anything below.
struct RestAdjustmentCaption: View {
    let isAdjusting: Bool
    let delta: TimeInterval

    var body: some View {
        Text("Rest")
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.5)
            .opacity(isAdjusting ? 0 : 1)
            .overlay {
                if isAdjusting {
                    deltaText
                        .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(OnyxWatch.Colors.textOnTint)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(OnyxWatch.Colors.tint, in: Capsule())
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: RestAdjustmentChrome.crossfade), value: isAdjusting)
    }

    private var deltaText: Text {
        let seconds = Int(delta.rounded())
        return seconds < 0 ? Text("−\(abs(seconds)) s") : Text("+\(seconds) s")
    }
}

/// The tick track and the `1:30 → 1:45` line under the digits.
///
/// Meant to be attached with `.restAdjustmentFooter(...)`, which hangs it in the
/// gap below the countdown without giving it any layout space.
struct RestAdjustmentFooter: View {
    let isAdjusting: Bool
    /// The duration the adjustment started from.
    let baseline: TimeInterval
    let current: TimeInterval
    let step: TimeInterval

    /// Bounded literal set — safe in a plain `HStack`.
    private static let tickCount = 25
    private static let tickWidth: CGFloat = 1.5
    private static let tickSpacing: CGFloat = 6

    var body: some View {
        // Built only while adjusting: this sits inside a body that re-evaluates
        // every second from the countdown and 5–10×/s during a rotation, so the
        // 25 capsules, the gradient mask and the formatting must not be
        // constructed just to be hidden.
        ZStack {
            if isAdjusting {
                VStack(spacing: 4) {
                    tickTrack
                    Text("\(RestAdjustmentChrome.durationText(baseline)) → \(RestAdjustmentChrome.durationText(current))")
                        .font(.system(.caption2, design: .rounded).weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(.easeInOut(duration: RestAdjustmentChrome.crossfade), value: isAdjusting)
        .accessibilityHidden(true)
        // Decorative, and it is drawn OUTSIDE its host's bounds in the gap just
        // above the Minimize/Skip row — SwiftUI hit-tests at rendered position,
        // not at the declared layout box, so without this the ruler could
        // swallow a button tap during the fade-out.
        .allowsHitTesting(false)
    }

    /// A ruler that slides one notch per detent, so the size of the change is
    /// legible without reading the numbers.
    private var tickTrack: some View {
        HStack(spacing: Self.tickSpacing) {
            ForEach(0..<Self.tickCount, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(index.isMultiple(of: 5) ? 0.85 : 0.3))
                    .frame(width: Self.tickWidth, height: index.isMultiple(of: 5) ? 8 : 5)
            }
        }
        .offset(x: tickOffset)
        .frame(maxWidth: .infinity)
        .frame(height: 10)
        .clipped()
        .mask {
            LinearGradient(
                colors: [.clear, .white, .white, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .overlay {
            Capsule()
                .fill(OnyxWatch.Colors.tint)
                .frame(width: 2, height: 10)
        }
    }

    /// Wrapped over the five-tick group so the track can scroll indefinitely
    /// without running out of ticks.
    private var tickOffset: CGFloat {
        guard step > 0 else { return 0 }
        let pitch = Self.tickWidth + Self.tickSpacing
        let steps = (current - baseline) / step
        return (-CGFloat(steps) * pitch).truncatingRemainder(dividingBy: pitch * 5)
    }
}

extension View {
    /// Cross-fades this row with the adjustment footer **in the row's own
    /// slot**. Apply it to the Minimize/Skip row: while the Crown is turning,
    /// the buttons fade out and the ruler + `old → new` line take their place.
    ///
    /// The row stays the layout element — an overlay's base view "continues to
    /// provide the layout characteristics for the resulting combined view" — so
    /// the slot keeps the buttons' height and nothing on screen moves.
    ///
    /// This screen has no vertical slack to give the footer a slot of its own:
    /// with the metrics row, the caption, 44pt digits and the buttons, a 46 mm
    /// watch leaves ≈29 pt in each `Spacer`. Two earlier attempts are recorded
    /// in `docs/watch-rest-timer-ui.md` — reserving fixed-height slots (pushed
    /// the content past the safe area at both ends) and hanging the footer
    /// below the digits via an alignment guide (drew it straight over the
    /// buttons). Borrowing the button row is what actually fits.
    ///
    /// The buttons stop hit-testing while they are invisible, so a tap during a
    /// rotation can't skip the rest by accident.
    func restAdjustmentFooter(_ footer: RestAdjustmentFooter, isAdjusting: Bool) -> some View {
        opacity(isAdjusting ? 0 : 1)
            .allowsHitTesting(!isAdjusting)
            .animation(.easeInOut(duration: RestAdjustmentChrome.crossfade), value: isAdjusting)
            .overlay { footer }
    }
}
