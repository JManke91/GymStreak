//
//  HistoryHeaderView.swift
//  GymStreak
//

import OSLog
import SwiftUI

/// History title, settings action and Trainings/Fortschritt selector.
struct HistoryHeaderView: View {
    @Binding var section: HistorySection
    let onOpenSettings: () -> Void
    let onInteractionStarted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("history.title".localized)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .kerning(-0.7)
                    .foregroundStyle(Color.white)

                Spacer()

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ai_coach.settings.open".localized)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            HStack(spacing: 0) {
                ForEach(HistorySection.allCases, id: \.self) { target in
                    Button {
                        onInteractionStarted()
                        HapticManager.shared.selection()
                        Self.signposter.emitEvent(
                            target == .trainings
                                ? "HistoryTrainingsSelected"
                                : "HistoryFortschrittSelected"
                        )
                        withAnimation(.easeOut(duration: 0.18)) {
                            section = target
                        }
                    } label: {
                        Text(target.title)
                            .font(.system(
                                size: 15,
                                weight: section == target ? .semibold : .medium,
                                design: .rounded
                            ))
                            .foregroundStyle(
                                section == target ? Color.white : Color.white.opacity(0.55)
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                section == target ? Color.white.opacity(0.12) : Color.clear
                            )
                            .clipShape(RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            ))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("history-section-\(target.rawValue)")
                }
            }
            .padding(4)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 20)
        }
    }

    private static let signposter = OSSignposter(
        subsystem: "com.shotat24fps.GymStreak",
        category: "History"
    )
}
