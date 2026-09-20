//
//  ConditioningSessionListView.swift
//  GymStreak
//
//  The five conditioning sessions, grouped by energy system — single sessions
//  outside the program. Pushed from the Conditioning screen, which belongs to
//  the 12-week program. See docs/fight-conditioning.md.
//

import SwiftUI

struct ConditioningSessionListView: View {
    let viewModel: ConditioningLibraryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                Text("conditioning.library.subtitle".localized)
                    .font(.onyxBody)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                // Bounded, constant content (five sessions) — a plain stack is fine.
                ForEach(viewModel.sections) { section in
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                        Text(ConditioningCopy.energySystem(section.system).uppercased())
                            .font(.onyxMonoLabel)
                            .kerning(0.7)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)

                        ForEach(section.sessions) { session in
                            NavigationLink(value: ConditioningRoute.session(session.id)) {
                                ConditioningSessionCard(id: session.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.xxl)
        }
        .background(DesignSystem.Colors.background.ignoresSafeArea())
        .navigationTitle("conditioning.library.single.title".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ConditioningSessionCard: View {
    let id: ConditioningSessionDefinition.ID

    var body: some View {
        OnyxCard {
            HStack(spacing: DesignSystem.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(ConditioningCopy.title(id))
                        .font(.onyxHeader)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text(ConditioningCopy.summary(id))
                        .font(.onyxFootnote)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}
