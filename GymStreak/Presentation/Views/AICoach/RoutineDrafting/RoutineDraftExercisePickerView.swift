//
//  RoutineDraftExercisePickerView.swift
//  GymStreak
//
//  "Which exercise did you mean?" — the screen a person reaches by tapping an unresolved
//  row in the routine-drafting sheet. See docs/ai-coach-routine-drafting.md.
//
//  It resolves the name **in the UI**, not with a second model round trip. A picker is
//  deterministic, costs no tokens and no allowance, and cannot translate or invent a name
//  — all three of which the model has been measured doing in this app.
//
//  The search and filtering are `ExercisesViewModel.sections(…)`, the same implementation
//  the add-to-routine picker uses; there is no third one.
//
//  A name genuinely absent from the library can also be **created** here: the create row
//  pushes the app's `AddExerciseView` with the drafted name filled in, and saving resolves
//  the row to the new exercise through the same `onSelect` as picking one. The exercise is
//  written on save and stays in the library if the draft is discarded (doc §1).
//

import SwiftUI

struct RoutineDraftExercisePickerView: View {

    /// What the person actually said, as the model transcribed it. Named on screen so the
    /// row being answered is never in doubt.
    let draftedName: String
    /// The few library exercises the resolver found equally plausible, offered **before**
    /// the library. Empty when nothing matched at all, which is the case that has nothing
    /// better to offer than the whole library.
    let candidates: [Exercise]
    /// A plain `let`, not `@ObservedObject`: nothing in this `body` reads a `@Published`
    /// property of it. `results` is `@State`, refreshed explicitly. Observing a broad
    /// multi-purpose object for properties a view never reads is rendering rule 6.
    let exercisesViewModel: ExercisesViewModel
    let onSelect: (Exercise) -> Void

    @State private var searchText = ""
    /// The filtered library, recomputed when the search changes rather than in `body`:
    /// filtering the whole library is a collection operation over user-scaled data
    /// (CLAUDE.md rendering rule 3).
    @State private var results: [Exercise] = []
    @FocusState private var isSearchFocused: Bool
    @State private var isCreatingExercise = false

    /// Candidates are a **suggestion about the drafted name**, so they stop being relevant
    /// the moment the person searches for something of their own.
    private var showsCandidates: Bool { !candidates.isEmpty && searchText.isEmpty }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Text("ai_coach.routine_draft.picker.subtitle".localized(draftedName))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)

                    RedesignSearchBar(
                        text: $searchText,
                        placeholder: "ai_coach.routine_draft.picker.search".localized,
                        isFocused: $isSearchFocused
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                    if showsCandidates {
                        sectionLabel("ai_coach.routine_draft.picker.candidates".localized)
                        ForEach(candidates) { exercise in
                            row(exercise)
                        }
                    }

                    // First on an unmatched row, after the suggestions on an ambiguous one.
                    createRow

                    sectionLabel("ai_coach.routine_draft.picker.all".localized)
                    ForEach(results) { exercise in
                        row(exercise)
                    }

                    Color.clear.frame(height: 40)
                }
            }
        }
        .keyboardDoneBar(isFocused: $isSearchFocused)
        .navigationTitle("ai_coach.routine_draft.picker.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        // Only the filtering — the library itself was re-fetched by the sheet on the tap
        // that opened this screen, because `fetchExercises()` is a synchronous full-library
        // SwiftData fetch and `onAppear` runs while the push animates (rendering rule 7).
        .onAppear { refreshResults() }
        .onChange(of: searchText) { _, _ in refreshResults() }
        .navigationDestination(isPresented: $isCreatingExercise) {
            // The drafted name, never the search text. Cancelling pops back here with
            // nothing written; saving resolves only this row — the sheet pops both screens.
            AddExerciseView(
                viewModel: exercisesViewModel,
                presentationMode: .navigation,
                initialName: draftedName,
                onExerciseCreated: { onSelect($0) }
            )
        }
    }

    // MARK: - Pieces

    private func row(_ exercise: Exercise) -> some View {
        Button {
            onSelect(exercise)
        } label: {
            ExercisePickerRowView(exercise: exercise, trailingSymbol: "checkmark")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.bottom, 7)
        .accessibilityLabel("\(exercise.name), \(MuscleGroups.displayString(for: exercise.muscleGroups))")
    }

    private var createRow: some View {
        Button {
            isCreatingExercise = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text("ai_coach.routine_draft.picker.create".localized(draftedName))
                    .font(.system(size: 13.5, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(DesignSystem.Colors.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(DesignSystem.Colors.tint.opacity(0.5))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(0.7)
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The library as the search currently sees it, through the app's one search/filter
    /// implementation. Candidates are dropped from the full list while they have their own
    /// section, so the same exercise never appears twice on one screen.
    private func refreshResults() {
        let all = exercisesViewModel
            .sections(searchText: searchText, categoryKey: nil, equipment: nil)
            .flatMap(\.exercises)
        guard showsCandidates else {
            results = all
            return
        }
        let offered = Set(candidates.map(\.id))
        results = all.filter { !offered.contains($0.id) }
    }
}
