//
//  RoutineDraftSheet.swift
//  GymStreak
//
//  "Describe a routine, review the draft, save it" — the drafting sheet opened from the
//  Coach Chat chip. See docs/ai-coach-routine-drafting.md.
//
//  Nothing on this screen writes anything. Create is the only affordance that persists,
//  and it goes through `RoutinesViewModel.createRoutine(name:pendingExercises:)`.
//

import SwiftUI

struct RoutineDraftSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.weightUnit) private var weightUnit

    /// Owned by the Coach Chat screen, not by this sheet: the drafting session outlives a
    /// single presentation only in the sense that the same ViewModel is reused, and
    /// `sheetWasDismissed()` resets it on the way out.
    @Bindable var viewModel: RoutineDraftViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    content
                    RoutineDraftFooter(viewModel: viewModel)
                }
            }
            .navigationTitle("ai_coach.routine_draft.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    .accessibilityLabel("ai_coach.routine_draft.close".localized)
                }
            }
        }
        .onAppear { viewModel.onAppear(weightUnit: weightUnit) }
        .onChange(of: viewModel.didCreateRoutine) { _, didCreate in
            if didCreate { dismiss() }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                switch viewModel.phase {
                case .describing:
                    intro
                case .drafting, .review:
                    draftBody
                case .failed(let message):
                    errorState(message)
                }

                AIPrivacyFooter(tone: .full)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            AISparkleView(size: 30, glow: true)
                .accessibilityHidden(true)
            Text("ai_coach.routine_draft.intro.title".localized)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.white)
            Text("ai_coach.routine_draft.intro.subtitle".localized)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            Text("ai_coach.routine_draft.intro.example".localized)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.4))
                .italic()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    /// The draft itself. The same layout streams and reviews — rows appear as exercises
    /// complete, so the list the person reads while it fills is the list they confirm.
    private var draftBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            AISurface(isStreaming: viewModel.isDrafting, showFooter: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.routineName.isEmpty {
                        AISkeletonBar(width: 160)
                    } else {
                        Text(viewModel.routineName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if viewModel.rows.isEmpty {
                        if viewModel.isDrafting {
                            AISkeletonBar(width: 220)
                            AISkeletonBar(width: 190)
                        } else {
                            Text("ai_coach.routine_draft.empty".localized)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        ForEach(viewModel.rows) { row in
                            RoutineDraftRowView(row: row)
                        }
                    }
                }
            }

            if !viewModel.unmatchedNames.isEmpty {
                leftOutNote
            }
        }
    }

    /// Never silent, never invented: an exercise the library could not place is named
    /// here and excluded from the draft.
    private var leftOutNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("ai_coach.routine_draft.left_out.title".localized)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(viewModel.unmatchedSummary)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

}

/// One drafted exercise. Takes a finished value struct — no `@Model` read, no formatter,
/// no aggregation in this `body`.
private struct RoutineDraftRowView: View {

    let row: RoutineDraftViewModel.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(row.summary)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
