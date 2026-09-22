//
//  ConditioningRunnerPages.swift
//  GymStreakWatch Watch App
//
//  The two faces of the watch conditioning runner and its controls page
//  (docs/fight-conditioning.md, watch runner redesign): the heart-rate gauge for
//  steady state, the phase-countdown ring for intervals, and Pause/End one swipe
//  away. Every page fits the screen without scrolling. Value inputs only.
//

import SwiftUI

/// Steady state: the heart-rate gauge with one instruction in the middle.
struct ConditioningZonePage: View {
    let phaseTitle: String
    let reading: ConditioningHeartRateReading
    let zone: WatchHeartRateZone?
    let status: ConditioningZoneStatus?
    let remaining: TimeInterval
    let phaseDuration: TimeInterval
    let sessionFraction: Double
    let isPaused: Bool

    var body: some View {
        GeometryReader { proxy in
            let layout = ConditioningGaugeLayout(size: proxy.size)
            let s = layout.scale
            // No reading yet: the instruction is neutral, not a zone colour.
            let color = reading.bpm == nil && zone != nil
                ? OnyxWatch.Colors.textSecondary
                : ConditioningRunnerStyle.color(for: status)
            ZStack(alignment: .top) {
                ConditioningZoneGaugeView(zone: zone, heartRate: reading.bpm, status: status, progress: sessionFraction)

                VStack(spacing: 3 * s) {
                    Text(isPaused ? String(localized: "PAUSED") : phaseTitle)
                        .font(ConditioningRunnerStyle.font(10, s))
                        .tracking(1.2 * s)
                        .foregroundStyle(isPaused ? OnyxWatch.Colors.warning : OnyxWatch.Colors.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3 * s) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 15 * s))
                            .foregroundStyle(OnyxWatch.Colors.destructive)
                            .symbolEffect(.pulse, isActive: reading == .measuring)
                        ConditioningHeartRateValue(reading: reading, size: 42, scale: s)
                    }
                    HStack(spacing: 3 * s) {
                        if reading.bpm != nil || zone == nil, let symbol = statusSymbol {
                            Image(systemName: symbol)
                                .font(.system(size: 12 * s, weight: .heavy))
                        }
                        Text(WatchConditioningCopy.zoneInstruction(status, reading: reading, zone: zone))
                            .font(ConditioningRunnerStyle.font(15, s, weight: .black))
                    }
                    .foregroundStyle(color)
                    Text(WatchConditioningCopy.zoneDetail(status, reading: reading, zone: zone))
                        .font(ConditioningRunnerStyle.font(11, s, weight: .bold))
                        .foregroundStyle(OnyxWatch.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: proxy.size.width)
                // Below the band's bound labels, above the arc's open ends.
                .offset(y: layout.center.y - 54 * s)

                VStack(spacing: 1 * s) {
                    Text(WatchConditioningCopy.clock(remaining))
                        .font(ConditioningRunnerStyle.font(22, s, weight: .black))
                        .foregroundStyle(OnyxWatch.Colors.textPrimary)
                    Text(String(localized: "left of \(WatchConditioningCopy.clock(phaseDuration))"))
                        .font(ConditioningRunnerStyle.font(10, s, weight: .bold))
                        .foregroundStyle(OnyxWatch.Colors.textSecondary)
                }
                .frame(width: proxy.size.width)
                .offset(y: layout.endsY + 6 * s)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
    }

    private var statusSymbol: String? {
        switch status {
        case .below: "chevron.up.2"
        case .above: "chevron.down.2"
        case .inZone: "checkmark"
        case nil: nil
        }
    }
}

/// Warm-up, work, rest, set break and cool-down: the phase countdown on the ring.
struct ConditioningIntervalPage: View {
    let phase: ConditioningPhase
    let remaining: TimeInterval
    let remainingFraction: Double
    let leadInCount: Int?
    let rounds: (completed: Int, current: Int?, total: Int)?
    let reading: ConditioningHeartRateReading
    let nextPhase: ConditioningPhase?
    let isPaused: Bool

    var body: some View {
        GeometryReader { proxy in
            let layout = ConditioningGaugeLayout(size: proxy.size)
            let s = layout.scale
            let isWork = phase.kind.isEffort
            let accent = isWork || leadInCount != nil ? OnyxWatch.Colors.tint : OnyxWatch.Colors.textTertiary
            ZStack(alignment: .top) {
                ZStack {
                    ConditioningGaugeArc(from: 0, to: 1)
                        .stroke(OnyxWatch.Colors.gaugeTrack, style: StrokeStyle(lineWidth: 7 * s, lineCap: .round))
                    ConditioningGaugeArc(from: 0, to: remainingFraction)
                        .stroke(accent, style: StrokeStyle(lineWidth: 7 * s, lineCap: .round))
                        .animation(.linear(duration: 0.25), value: remainingFraction)
                }

                VStack(spacing: 4 * s) {
                    pill(isWork: isWork, scale: s)
                    Text(leadInCount.map { "\($0)" } ?? WatchConditioningCopy.clock(remaining))
                        .font(ConditioningRunnerStyle.font(leadInCount == nil ? 48 : 56, s, weight: .black))
                        .foregroundStyle(leadInCount == nil ? OnyxWatch.Colors.textPrimary : OnyxWatch.Colors.tint)
                        .contentTransition(.numericText(countsDown: true))
                    Text(leadInCount == nil ? WatchConditioningCopy.effort(phase.effort) : String(localized: "Get ready"))
                        .font(ConditioningRunnerStyle.font(11, s, weight: .heavy))
                        .foregroundStyle(OnyxWatch.Colors.chipText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: proxy.size.width)
                .offset(y: layout.center.y - (leadInCount == nil ? 56 : 60) * s)

                VStack(spacing: 4 * s) {
                    if let rounds {
                        roundDots(rounds, scale: s)
                    }
                    HStack(spacing: 4 * s) {
                        if let position = WatchConditioningCopy.position(phase) {
                            Text(position)
                            Text("·")
                        }
                        Image(systemName: "heart.fill")
                            .foregroundStyle(OnyxWatch.Colors.destructive)
                            .symbolEffect(.pulse, isActive: reading == .measuring)
                        ConditioningHeartRateValue(reading: reading, size: 10, scale: s)
                    }
                    .font(ConditioningRunnerStyle.font(10, s, weight: .bold))
                    .foregroundStyle(OnyxWatch.Colors.textSecondary)
                    if let nextPhase {
                        Text("Next: \(WatchConditioningCopy.phase(nextPhase.kind)) \(WatchConditioningCopy.clock(nextPhase.duration))")
                            .font(ConditioningRunnerStyle.font(10, s, weight: .bold))
                            .foregroundStyle(OnyxWatch.Colors.textTertiary)
                    }
                }
                .frame(width: proxy.size.width)
                .offset(y: layout.endsY + 4 * s)
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
    }

    private func pill(isWork: Bool, scale s: CGFloat) -> some View {
        let title: String
        if isPaused {
            title = String(localized: "PAUSED")
        } else if let nextPhase, leadInCount != nil {
            title = String(localized: "\(WatchConditioningCopy.phase(nextPhase.kind)) IN")
        } else {
            title = WatchConditioningCopy.phase(phase.kind)
        }
        let onTint = isWork && !isPaused
        return Text(title)
            .font(ConditioningRunnerStyle.font(9, s, weight: .black))
            .tracking(1 * s)
            .padding(.vertical, 3 * s)
            .padding(.horizontal, 8 * s)
            // Effort on the tint with black text — never white on the tint.
            .foregroundStyle(onTint ? OnyxWatch.Colors.textOnTint
                             : (leadInCount != nil ? OnyxWatch.Colors.tint
                                : (isPaused ? OnyxWatch.Colors.warning : OnyxWatch.Colors.textPrimary)))
            .background(Capsule().fill(onTint ? OnyxWatch.Colors.tint : OnyxWatch.Colors.cardElevated))
    }

    private func roundDots(_ rounds: (completed: Int, current: Int?, total: Int), scale s: CGFloat) -> some View {
        HStack(spacing: 4 * s) {
            // Bounded: at most eight rounds in a set.
            ForEach(0..<rounds.total, id: \.self) { index in
                let isCurrent = index == rounds.current
                Circle()
                    .fill(index < rounds.completed || isCurrent ? OnyxWatch.Colors.tint : OnyxWatch.Colors.strokeSubtle)
                    .frame(width: (isCurrent ? 7 : 5) * s, height: (isCurrent ? 7 : 5) * s)
            }
        }
    }
}

/// The heart-rate number, a spinner while the first reading is on its way, or a
/// dimmed "--" once none has arrived (the page says why).
struct ConditioningHeartRateValue: View {
    let reading: ConditioningHeartRateReading
    let size: CGFloat
    let scale: CGFloat

    var body: some View {
        switch reading {
        case .bpm(let bpm):
            Text("\(bpm)")
                .font(ConditioningRunnerStyle.font(size, scale, weight: .black))
                .foregroundStyle(OnyxWatch.Colors.textPrimary)
                .contentTransition(.numericText())
        case .measuring:
            ProgressView()
                .tint(OnyxWatch.Colors.textSecondary)
                // Sized to the number it stands in for, so nothing shifts when it arrives.
                .scaleEffect(size * scale / 30)
                .frame(width: size * scale * 1.2, height: size * scale)
                .accessibilityLabel(Text("Measuring heart rate…"))
        case .missing:
            Text(verbatim: "--")
                .font(ConditioningRunnerStyle.font(size, scale, weight: .black))
                .foregroundStyle(OnyxWatch.Colors.textTertiary)
                .accessibilityLabel(Text("No heart rate"))
        }
    }
}

/// Pause/Resume and End, one swipe to the left of the runner.
struct ConditioningControlsPage: View {
    let title: String
    let subtitle: String
    let isPaused: Bool
    let onPauseResume: () -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(spacing: OnyxWatch.Spacing.lg) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .foregroundStyle(OnyxWatch.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(OnyxWatch.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(spacing: OnyxWatch.Spacing.lg) {
                control(
                    isPaused ? String(localized: "Resume") : String(localized: "Pause"),
                    symbol: isPaused ? "play.fill" : "pause.fill",
                    tint: OnyxWatch.Colors.warning,
                    action: onPauseResume
                )
                control(String(localized: "End"), symbol: "xmark", tint: OnyxWatch.Colors.destructive, action: onEnd)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func control(_ label: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: OnyxWatch.Spacing.sm) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(tint)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(tint.opacity(0.22)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            Text(label)
                .font(.system(.footnote, design: .rounded).weight(.heavy))
                .foregroundStyle(OnyxWatch.Colors.textPrimary)
                // The button already carries the label for VoiceOver.
                .accessibilityHidden(true)
        }
    }
}
