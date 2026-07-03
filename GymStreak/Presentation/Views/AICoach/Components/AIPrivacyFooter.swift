//
//  AIPrivacyFooter.swift
//  GymStreak
//
//  Standalone on-device privacy disclosure used inside AISurface (inline)
//  and at the bottom of full-screen AI surfaces like Period Recap (full).
//

import SwiftUI

/// Tone variants for `AIPrivacyFooter`.
enum AIPrivacyFooterTone {
    /// Compact inline variant — used inside `AISurface`.
    case inline
    /// Larger standalone footer with more padding — used at the bottom of full-screen surfaces.
    case full
}

/// On-device AI privacy disclaimer footer.
///
/// Shows a lock icon and a short monospaced line confirming that inference
/// runs locally and data never leaves the device.
struct AIPrivacyFooter: View {

    var tone: AIPrivacyFooterTone = .inline

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(textColor)

            Text(footerText)
                .font(AICoachTheme.mono(size: fontSize, weight: .regular))
                .foregroundStyle(textColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(outerPadding)
    }

    // MARK: - Derived metrics

    private var footerText: String {
        "ai_coach.privacy_footer".localized
    }

    private var iconSize: CGFloat {
        tone == .inline ? 10 : 12
    }

    private var fontSize: CGFloat {
        tone == .inline ? 9.5 : 11
    }

    private var textColor: Color {
        Color.white.opacity(0.4)
    }

    private var outerPadding: EdgeInsets {
        switch tone {
        case .inline:
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        case .full:
            return EdgeInsets(top: 12, leading: 0, bottom: 4, trailing: 0)
        }
    }
}

// MARK: - Previews

#Preview("Inline") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        AIPrivacyFooter(tone: .inline)
            .padding()
    }
}

#Preview("Full") {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        AIPrivacyFooter(tone: .full)
            .padding()
    }
}
