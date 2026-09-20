//
//  ConditioningLibraryView.swift
//  GymStreak
//
//  Entry point for fight conditioning: the 12-week program. Presented full
//  screen from the Routines tab. The screen has one subject — single sessions
//  live one tap away in `ConditioningSessionListView`.
//  See docs/fight-conditioning.md.
//

import SwiftUI

/// Where the Conditioning screen's navigation stack can go.
enum ConditioningRoute: Hashable {
    /// The session library, outside the program.
    case sessionList
    case session(ConditioningSessionDefinition.ID)
    /// A session pre-set to a program target's volume.
    case programSession(ConditioningProgramTarget)
    case programShowcase
}

struct ConditioningLibraryView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    /// Opens straight into the program showcase (the Routines-tab invitation).
    var opensShowcase = false

    var body: some View {
        ConditioningLibraryContent(dependencies: dependencies, opensShowcase: opensShowcase)
    }
}

private struct ConditioningLibraryContent: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ConditioningLibraryViewModel
    @State private var path: [ConditioningRoute]
    @State private var showingSafetyInfo = false
    private let program: ConditioningProgramViewModel

    init(dependencies: AppDependencies, opensShowcase: Bool) {
        program = dependencies.conditioningProgram
        _path = State(initialValue: opensShowcase ? [.programShowcase] : [])
        _viewModel = State(initialValue: ConditioningLibraryViewModel(
            safety: dependencies.conditioningSafety,
            heartRateProfile: dependencies.heartRateProfileStore,
            makeRun: dependencies.makeConditioningRunViewModel(plan:),
            makeHeartRateEditor: dependencies.makeHeartRateProfileEditor
        ))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                    ConditioningProgramSection(
                        viewModel: program,
                        onStart: { path.append(.programSession($0)) },
                        onShowShowcase: { path.append(.programShowcase) }
                    )

                    singleSessionRow
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.xxl)
            }
            .background(DesignSystem.Colors.background.ignoresSafeArea())
            .navigationTitle("conditioning.library.title".localized)
            .navigationDestination(for: ConditioningRoute.self) { route in
                switch route {
                case .sessionList:
                    ConditioningSessionListView(viewModel: viewModel)
                case .session(let id):
                    ConditioningPreviewView(definition: ConditioningLibrary.session(id), viewModel: viewModel)
                case .programSession(let target):
                    ConditioningPreviewView(
                        definition: target.definition,
                        viewModel: viewModel,
                        initialOptions: target.options
                    )
                case .programShowcase:
                    ConditioningProgramShowcaseView(viewModel: program) { path.removeAll() }
                }
            }
            // Bounded fetches (this week's conditioning, today's workouts) — see `refresh()`.
            .onAppear { program.refresh() }
            // Another device enrolled, paused or left.
            .onChange(of: program.enrollment) { program.refresh() }
            // A finished session counts toward this week and moves today's suggestion.
            .onChange(of: viewModel.activeRun == nil) { _, isIdle in
                if isIdle { program.refresh() }
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

    /// The library, one tap away: the program owns this screen, but a user who
    /// wants a one-off session must not have to leave it.
    private var singleSessionRow: some View {
        NavigationLink(value: ConditioningRoute.sessionList) {
            OnyxCard {
                HStack(spacing: DesignSystem.Spacing.md) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("conditioning.library.single.title".localized)
                            .font(.onyxSubheadline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Text("conditioning.library.single.subtitle".localized)
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
        .buttonStyle(.plain)
    }
}
