//
//  CoachChatMessageBubble.swift
//  GymStreak
//
//  One chat message as it appears in the list: the user's tint bubble, the
//  assistant's AI surface while streaming/final, and the inline error
//  affordance for a failed generation. Split out of `CoachChatView` so that
//  file stays near the 300-line convention.
//

import SwiftUI

// MARK: - Message bubble

struct MessageBubble: View {

    let message: CoachChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(DesignSystem.Colors.textOnTint)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AICoachTheme.accent)
                    )
            }
        case .assistant:
            HStack {
                assistantContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 40)
            }
        }
    }

    @ViewBuilder
    private var assistantContent: some View {
        switch message.phase {
        case .streaming:
            AISurface(isStreaming: true, showFooter: false, compact: true) {
                StreamingTextView(text: message.text, isStreaming: true)
            }
        case .final:
            AISurface(isStreaming: false, showFooter: false, compact: true) {
                StreamingTextView(text: message.text, isStreaming: false)
            }
        case .failed:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(DesignSystem.Colors.warning)
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
    }
}
