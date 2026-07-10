//
//  CoachBarView.swift
//  GymStreak
//
//  The floating coach companion bar hosted as the TabView's bottom accessory
//  (Apple Music mini-player pattern, iOS 26 `tabViewBottomAccessory`).
//  Tapping it zoom-morphs into the full CoachChatView (see ContentView).
//  The system draws the accessory capsule/background; this view is content only.
//

import SwiftUI

struct CoachBarView: View {

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                AISparkleView(size: 18, glow: placement != .inline)
                    .accessibilityHidden(true)

                Text("ai_coach.chat.bar.title".localized)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if placement != .inline {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ai_coach.chat.bar.title".localized)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ZStack {
        DesignSystem.Colors.background.ignoresSafeArea()
        CoachBarView(onTap: {})
            .frame(height: 48)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            .padding()
    }
}
