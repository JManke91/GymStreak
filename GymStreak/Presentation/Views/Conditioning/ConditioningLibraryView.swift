//
//  ConditioningLibraryView.swift
//  GymStreak
//
//  Entry point for fight conditioning: the session library grouped by energy
//  system. Presented full screen from the Routines tab.
//  See docs/fight-conditioning.md.
//

import SwiftUI

struct ConditioningLibraryView: View {
    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        ConditioningLibraryContent(dependencies: dependencies)
    }
}

private struct ConditioningLibraryContent: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ConditioningLibraryViewModel
    @State private var showingSafetyInfo = false

    init(dependencies: AppDependencies) {
        _viewModel = State(initialValue: ConditioningLibraryViewModel(
            safety: dependencies.conditioningSafety,
            heartRateProfile: dependencies.heartRateProfileStore,
            makeRun: dependencies.makeConditioningRunViewModel(plan:),
            makeHeartRateEditor: dependencies.makeHeartRateProfileEditor
        ))
    }

    var body: some View {
        NavigationStack {
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
                                NavigationLink(value: session.id) {
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
            .navigationTitle("conditioning.library.title".localized)
            .navigationDestination(for: ConditioningSessionDefinition.ID.self) { id in
                ConditioningPreviewView(
                    definition: ConditioningLibrary.session(id),
                    viewModel: viewModel
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close".localized) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSafetyInfo = true
                    } label: {
                        Image(systemName: "heart.text.square")
                    }
                    .accessibilityLabel("conditioning.safety.title".localized)
                }
            }
            .sheet(isPresented: $showingSafetyInfo) {
                ConditioningSafetyView(onAcknowledge: nil)
            }
            .fullScreenCover(item: $viewModel.activeRun) { run in
                ConditioningRunnerView(
                    viewModel: run,
                    needsSafetyAcknowledgement: viewModel.needsSafetyAcknowledgement,
                    onAcknowledgeSafety: viewModel.acknowledgeSafety
                )
            }
        }
    }
}

private struct ConditioningSessionCard: View {
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
