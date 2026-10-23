//
//  CompactValueEditor.swift
//  GymStreakWatch Watch App
//
//  Value card for the set editor's side-by-side weight/reps layout.
//  The focused card gets the dark-green active treatment; the shared
//  stepper buttons in FullScreenSetEditorView adjust the focused value.
//

import SwiftUI

struct CompactValueEditor: View {
    let label: String
    /// Already formatted for display. The caller owns the unit — the card never
    /// converts, so it cannot disagree with the value the stepper is editing.
    let value: String
    /// The written unit shown under the number ("kg", "lb", "reps").
    let unit: String
    /// The spoken form for VoiceOver ("kilograms"). A screen reader saying
    /// "kay gee" is the reason this is separate from `unit`.
    let spokenUnit: String
    let icon: String
    let isFocused: Bool
    /// Whether the Digital Crown is locked or unlocked for this card, shown as
    /// a Crown + lock pair at the end of the unit line (the card's height never
    /// changes).
    var crownState: CrownState = .unavailable
    /// When an unlocked Crown locks again. The green border drains towards it,
    /// so the user can see the lock coming.
    var crownRelockDeadline: Date?
    /// The "Tap first" hint, replacing the unit line while true.
    var showsCrownHint = false
    let onTap: () -> Void
    /// VoiceOver's swipe up/down; ±1 step of this card's value.
    var onAdjust: (Int) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped to bounce the lock as it opens.
    @State private var glyphBounce = 0

    private let metrics = WorkoutScreenMetrics.current

    enum CrownState {
        /// No glyph: an unselected card, or the Crown cannot edit right now.
        case unavailable
        /// Muted Crown + closed lock: the affordance — tap to unlock the Crown.
        case locked
        /// Green Crown + open lock: the Crown is stepping this value.
        case unlocked
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(spacing: 1.5) {
                Text(value)
                    .font(.system(size: metrics.valueFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(OnyxWatch.Colors.textPrimary)

                HStack(spacing: 2.5) {
                    Image(systemName: icon)
                        .font(.system(size: metrics.valueUnitSize, weight: .semibold))
                    Text(unit)
                        .font(.system(size: metrics.valueUnitSize, weight: .medium))
                    // Inline, not a corner overlay: a corner collides with a
                    // wide value ("132,3") or unit ("Wdh.") on a 40 mm card.
                    if crownState != .unavailable {
                        crownLockGlyph
                    }
                }
                .foregroundStyle(OnyxWatch.Colors.textMuted)
                .opacity(showsCrownHint ? 0 : 1)
                // An overlay on the unit line, so the card keeps its height and
                // the hint may run wider than "kg".
                .overlay {
                    if showsCrownHint {
                        CrownLockedHint(fontSize: metrics.valueUnitSize)
                            .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: metrics.valueCardHeight)
            .background {
                RoundedRectangle(cornerRadius: metrics.valueCardRadius, style: .continuous)
                    .fill(isFocused ? OnyxWatch.Colors.surfaceCardActive : OnyxWatch.Colors.card)
            }
            .overlay {
                if let crownRelockDeadline, crownState == .unlocked {
                    relockCountdownBorder(until: crownRelockDeadline)
                } else {
                    RoundedRectangle(cornerRadius: metrics.valueCardRadius, style: .continuous)
                        .strokeBorder(
                            isFocused ? OnyxWatch.Colors.accentGreen : OnyxWatch.Colors.strokeSubtle,
                            lineWidth: isFocused ? 1 : 0.75
                        )
                }
            }
            .shadow(
                color: isFocused ? OnyxWatch.Colors.accentGreen.opacity(0.22) : .clear,
                radius: 8
            )
            .contentShape(RoundedRectangle(cornerRadius: metrics.valueCardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label). \(value) \(spokenUnit)")
        .accessibilityValue(value)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityHint("Swipe up or down to adjust")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onAdjust(1)
            case .decrement: onAdjust(-1)
            @unknown default: break
            }
        }
        .onChange(of: crownState) { _, state in
            if state == .unlocked && !reduceMotion { glyphBounce += 1 }
        }
    }

    /// The unlocked card's border runs out over the relock delay: a dim track
    /// with a bright stroke draining from full to empty. Linear and confined to
    /// the card's edge, so it stays on under Reduce Motion — it carries
    /// information, not decoration. Redraws per frame only while unlocked
    /// (≤ 3 s at a time).
    private func relockCountdownBorder(until deadline: Date) -> some View {
        let card = RoundedRectangle(cornerRadius: metrics.valueCardRadius, style: .continuous)
        let lineWidth: CGFloat = 1.5
        return TimelineView(.animation) { context in
            let remaining = deadline.timeIntervalSince(context.date) / SetValueCrown.relockDelay
            ZStack {
                card.strokeBorder(OnyxWatch.Colors.accentGreen.opacity(0.25), lineWidth: lineWidth)
                card.inset(by: lineWidth / 2)
                    .trim(from: 0, to: min(max(remaining, 0), 1))
                    .stroke(OnyxWatch.Colors.accentGreen, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
    }

    /// "Crown, locked" / "Crown, unlocked". The Crown glyph says *what* is
    /// locked — a lock alone would read as "this value cannot be edited",
    /// which ± contradicts. The lock morphs open with Magic Replace (shared
    /// base shape) and bounces once; under Reduce Motion it simply swaps.
    private var crownLockGlyph: some View {
        HStack(spacing: 1) {
            Image(systemName: "digitalcrown.arrow.clockwise")
            Image(systemName: crownState == .unlocked ? "lock.open.fill" : "lock.fill")
                .contentTransition(
                    reduceMotion ? .identity : .symbolEffect(.replace.magic(fallback: .replace))
                )
                .symbolEffect(.bounce, value: glyphBounce)
        }
        .font(.system(size: metrics.valueUnitSize, weight: .semibold))
        .foregroundStyle(
            crownState == .unlocked ? OnyxWatch.Colors.accentGreen : OnyxWatch.Colors.textMuted
        )
        .padding(.leading, 1.5)
        .transition(.opacity)
    }
}

/// "🔒 Tap first": answers a Crown turned while locked. The lock wiggles once
/// as the hint appears (not under Reduce Motion) — the unit line, and with it
/// the card's own lock glyph, is hidden behind the hint, so the hint carries
/// its own.
private struct CrownLockedHint: View {
    let fontSize: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wiggle = 0

    var body: some View {
        HStack(spacing: 2.5) {
            Image(systemName: "lock.fill")
                .symbolEffect(.wiggle, value: wiggle)
            Text("Tap first")
        }
        .font(.system(size: fontSize, weight: .semibold))
        .foregroundStyle(OnyxWatch.Colors.accentGreen)
        .lineLimit(1)
        // An overlay is proposed its base's size; the hint may run wider than "kg".
        .fixedSize()
        // After insertion, so the change is seen as one (a value set before the
        // view exists triggers nothing).
        .task {
            if !reduceMotion { wiggle += 1 }
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var focused = 0

        var body: some View {
            ZStack {
                OnyxWatch.Colors.background.ignoresSafeArea()

                HStack(spacing: 6.5) {
                    CompactValueEditor(
                        label: "WEIGHT",
                        value: WatchWeightFormatting.number(61.235, in: .pounds),
                        unit: WatchWeightFormatting.unitWord(.pounds),
                        spokenUnit: WatchWeightFormatting.spokenUnitWord(.pounds),
                        icon: "scalemass.fill",
                        isFocused: focused == 0,
                        crownState: focused == 0 ? .unlocked : .unavailable,
                        crownRelockDeadline: .now.addingTimeInterval(2),
                        onTap: { focused = 0 }
                    )

                    CompactValueEditor(
                        label: "REPS",
                        value: "10",
                        unit: "reps",
                        spokenUnit: "reps",
                        icon: "repeat",
                        isFocused: focused == 1,
                        crownState: focused == 1 ? .locked : .unavailable,
                        showsCrownHint: focused == 1,
                        onTap: { focused = 1 }
                    )
                }
                .padding(.horizontal, 8)
            }
        }
    }

    return PreviewWrapper()
}
