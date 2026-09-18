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
    /// The app's shared exercise library ViewModel, from the composition root. It backs
    /// the "which exercise did you mean?" picker through the same
    /// `sections(searchText:categoryKey:equipment:)` the add-to-routine picker uses.
    /// A plain `let`: this sheet only forwards the reference to the picker. As an
    /// `@ObservedObject` it would re-render the live streaming draft list on every
    /// unrelated `@Published` change of a broad multi-purpose object — including the
    /// picker's own library re-fetch (rendering rule 6).
    let exercisesViewModel: ExercisesViewModel

    /// The unresolved row whose picker is open. Held here rather than in the ViewModel:
    /// it is where the sheet is, not what the draft is.
    @State private var pickingRow: RoutineDraftRow?

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
            .navigationDestination(item: $pickingRow) { row in
                RoutineDraftExercisePickerView(
                    draftedName: row.name,
                    // A lookup in a list the generation schema caps at twelve, run once
                    // when this destination is built — not a search.
                    candidates: viewModel.candidates(for: row.id),
                    exercisesViewModel: exercisesViewModel,
                    onSelect: { exercise in
                        viewModel.resolveRow(row.id, to: exercise)
                        pickingRow = nil
                    }
                )
            }
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
                            RoutineDraftRowView(
                                row: row,
                                onChoose: { choose(row) },
                                onRemove: { viewModel.removeRow(row.id) }
                            )
                        }
                    }
                }
            }

            if viewModel.hasUnresolvedRows {
                leftOutNote
            }
        }
    }

    /// What Create will do with the rows above it, said before Create is tapped: an
    /// exercise the person has not yet pointed at a library entry is left out. Never
    /// silent, never invented, and now never a dead end either — the row itself is the way
    /// to fix it.
    private var leftOutNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("ai_coach.routine_draft.left_out.title".localized)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("ai_coach.routine_draft.left_out.body".localized)
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

    /// Opens the picker for one unresolved row — but not while the draft is still
    /// streaming, when the list under the finger is still moving.
    ///
    /// The library is re-fetched **here, on the tap**, rather than in the picker's
    /// `onAppear`: it is a synchronous full-library SwiftData fetch and `onAppear` runs
    /// while the push animates (rendering rule 7, the same reasoning as
    /// `RoutineDraftViewModel.requestDrafting()`). It is refreshed rather than trusted
    /// because the shared `ExercisesViewModel` outlives any one sheet, and an exercise
    /// created since it was built would otherwise be missing from exactly the screen that
    /// exists to find one.
    private func choose(_ row: RoutineDraftRow) {
        guard !row.isResolved, !viewModel.isDrafting else { return }
        exercisesViewModel.fetchExercises()
        pickingRow = row
    }
}
