//
//  StreamingTextView.swift
//  GymStreak
//
//  Renders AI-streamed text directly — no internal word-by-word timer.
//  The passed `text` string is rendered as-is; a blinking inline cursor appears
//  at the end while `isStreaming == true`. Snapshots from FoundationModels fire
//  at ~30 Hz; the previous timer-based reveal doubled the latency and added a
//  second layout-recompute pass on top of each snapshot. This version eliminates
//  that entirely.
//
//  VoiceOver reads the complete `text` value; the cursor bar is hidden from VO.
//

import SwiftUI

/// Renders a string directly with an optional blinking cursor at the tail.
///
/// - When `isStreaming` is `true`, a 7×14 pt accent-colored cursor blinks inline.
/// - When `isStreaming` is `false` (or `accessibilityReduceMotion` is active),
///   the text is rendered statically with no animation.
/// - `.animation(nil, value: text)` is applied to the inner `Text` so SwiftUI
///   does not attempt to animate height changes between snapshots.
///
/// **Migration note**: The `wordDelay` parameter is a no-op and kept only for
/// source compatibility with call sites that were written for the old timer-based
/// implementation. It has no effect and can be removed from call sites at leisure.
struct StreamingTextView: View {

    // MARK: - Props

    let text: String
    var isStreaming: Bool = true
    /// Deprecated no-op — kept for source compatibility only. Has no effect.
    var wordDelay: Duration = .milliseconds(28)
    var font: Font = .system(size: 14)
    var color: Color = .white.opacity(0.88)
    var lineSpacing: CGFloat = 4
    var onComplete: (() -> Void)? = nil

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    @State private var cursorVisible: Bool = true

    // MARK: - Body

    var body: some View {
        Group {
            if isStreaming && !reduceMotion {
                // Inline cursor appended to the streamed text.
                // Suppress any implicit animation on text height changes.
                (Text(text)
                    .font(font)
                    .foregroundColor(color)
                + cursorText)
                .lineSpacing(lineSpacing)
                .animation(nil, value: text)
                .transaction { $0.disablesAnimations = true }
            } else {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineSpacing(lineSpacing)
                    .animation(nil, value: text)
            }
        }
        .accessibilityLabel(text)
        .task(id: isStreaming) {
            guard isStreaming && !reduceMotion else {
                // Notify caller immediately when not streaming
                if !isStreaming { onComplete?() }
                return
            }
            await runCursorBlink()
        }
    }

    // MARK: - Cursor

    /// Blinking 7×14 pt accent-colored bar.
    /// Accessibility is suppressed on the whole container via `.accessibilityLabel(text)`,
    /// so we don't need `.accessibilityHidden` on this `Text` (which can't carry it anyway
    /// when used inside `Text` concatenation).
    private var cursorText: Text {
        Text(verbatim: " |")
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(cursorVisible ? AICoachTheme.accent : .clear)
    }

    private func runCursorBlink() async {
        while isStreaming, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            cursorVisible.toggle()
        }
        cursorVisible = true
    }
}

// MARK: - Previews

#Preview("Streaming On") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        VStack {
            StreamingTextView(
                text: "Solider Push-Tag — Volumen leicht unter Schnitt der letzten vier Wochen, dafür neue Bestleistung bei Bench Press.",
                isStreaming: true
            )
        }
        .padding()
    }
}

#Preview("Streaming Off") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()

        StreamingTextView(
            text: "Gute Leistung heute. Weiter so mit dem Training!",
            isStreaming: false
        )
        .padding()
    }
}
