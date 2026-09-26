//
//  RoutineDraftSheet.swift
//  GymStreak
//
//  "Describe a routine, review the draft, save it" — the drafting sheet opened from the
//  Coach Chat chip. See docs/ai-coach-routine-drafting.md.
//
//  Once the draft is final it is editable in place: rename it, move or remove rows, and
//  open any resolved row in `ConfigureExerciseSetsView` to adjust its sets.
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
    /// The resolved row whose sets are open in `ConfigureExerciseSetsView`.
    @State private var configuringRow: RoutineDraftRow?

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.background.ignoresSafeArea()

                if let created = viewModel.createdRoutine {
                    // Create's answer: the routine landing, not the sheet vanishing.
                    RoutineDraftCreatedView(summary: created, onDone: { dismiss() })
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    VStack(spacing: 0) {
                        content
                        RoutineDraftFooter(viewModel: viewModel)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.didCreateRoutine)
            .navigationTitle(viewModel.didCreateRoutine ? "" : "ai_coach.routine_draft.title".localized)
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
            .navigationDestination(item: $configuringRow) { row in
                configureDestination(for: row)
            }
            .toolbar {
                // The success face has its own Done; a second close control would compete.
                if !viewModel.didCreateRoutine {
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
        }
        .onAppear { viewModel.onAppear(weightUnit: weightUnit) }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                switch viewModel.phase {
                case .describing:
                    intro
                case .drafting, .asking, .review:
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
                // Lazy although the schema caps the list at twelve: the rows are the
                // user-scaled part of this screen (rendering rule 1).
                LazyVStack(alignment: .leading, spacing: 14) {
                    if viewModel.phase == .review {
                        nameField
                    } else if viewModel.routineName.isEmpty, viewModel.isDrafting {
                        AISkeletonBar(width: 160)
                    } else if viewModel.routineName.isEmpty {
                        // No name yet, and the sheet may be about to ask for one.
                        Text("ai_coach.routine_draft.default_name".localized)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.35))
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
                        } else if viewModel.question == nil {
                            Text("ai_coach.routine_draft.empty".localized)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        ForEach(viewModel.rows) { row in
                            RoutineDraftRowView(
                                row: row,
                                isEditable: viewModel.phase == .review,
                                onChoose: { choose(row) },
                                onEdit: { edit(row) },
                                onMove: { viewModel.moveRow(row.id, by: $0) },
                                onRemove: { viewModel.removeRow(row.id) }
                            )
                        }
                    }
                }
            }

            // Also while the answer's turn runs, so the question stays beside the draft
            // it is changing.
            if let question = viewModel.question {
                RoutineDraftQuestionCard(
                    question: question,
                    error: viewModel.answerError,
                    isInteractive: viewModel.isAsking,
                    canReviewNow: viewModel.canReviewNow,
                    onReviewNow: { viewModel.reviewNow() },
                    onDiscard: { viewModel.discard() }
                )
            }

            if viewModel.hasUnresolvedRows {
                RoutineDraftLeftOutNote()
            }

            if let dropped = viewModel.droppedSummary {
                RoutineDraftLeftOutNote(
                    title: "ai_coach.routine_draft.dropped.title".localized,
                    message: dropped
                )
            }
        }
    }

    /// The drafted name, editable once the draft is final. Left empty, Create falls back
    /// to the default name rather than refusing.
    private var nameField: some View {
        HStack(spacing: 8) {
            TextField(
                "ai_coach.routine_draft.name.placeholder".localized,
                text: $viewModel.routineName
            )
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color.white)
            .submitLabel(.done)

            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .accessibilityHidden(true)
        }
    }

    /// The app's one set editor, seeded with the row's current scheme — its last edit, or
    /// the drafted figures. Edit mode saves on back too, so a swipe-back keeps the change.
    @ViewBuilder
    private func configureDestination(for row: RoutineDraftRow) -> some View {
        if let pending = viewModel.configuration(for: row.id) {
            ConfigureExerciseSetsView(
                exercise: pending.exercise,
                navigationTitleKey: "configure_exercise.edit_title",
                saveButtonKey: "configure_exercise.save_changes",
                existingConfiguration: .init(
                    sets: pending.sets,
                    alternatives: pending.alternatives,
                    targetRepMin: pending.targetRepMin,
                    targetRepMax: pending.targetRepMax
                ),
                onSave: { _, sets, alternatives, repMin, repMax in
                    viewModel.updateConfiguration(
                        row.id,
                        sets: sets,
                        alternatives: alternatives,
                        targetRepMin: repMin,
                        targetRepMax: repMax
                    )
                }
            )
        }
    }

    private func errorState(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 15))
            .foregroundStyle(Color.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }

    /// Opens the set editor for one resolved row, once the draft has stopped moving.
    private func edit(_ row: RoutineDraftRow) {
        guard row.isResolved, viewModel.phase == .review else { return }
        configuringRow = row
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
        guard !row.isResolved, viewModel.phase == .review else { return }
        exercisesViewModel.fetchExercises()
        pickingRow = row
    }
}
