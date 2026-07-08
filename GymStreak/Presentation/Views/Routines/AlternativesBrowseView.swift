//
//  AlternativesBrowseView.swift
//  GymStreak
//
//  Compact browse sheet for a routine exercise's alternatives — the one-tap
//  entry point from the "Alternativen" info chip on a collapsed exercise card.
//  Visually modeled on the in-workout SwapExercisePickerView: a flat list of
//  every alternative (name · muscle group · set scheme) so the user can find one
//  without expanding the card and scrolling past sets/rest/rep-range.
//
//  This is a *browse/jump* surface only: selecting a row hands back to
//  RoutineDetailView, which expands the card and that alternative's inline
//  editor (AlternativeSetsInlineEditor). Set / rep-range editing and removal stay
//  inline (2026-07-07 decision preserved) — see docs/alternative-exercises.md.
//

import SwiftUI

struct AlternativesBrowseView: View {
    let routineExercise: RoutineExercise
    /// Jump to this alternative's inline editor (presenter expands + scrolls to it).
    let onSelect: (RoutineExerciseAlternative) -> Void
    /// Open the add-alternative picker for this exercise.
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Primary exercise, for orientation (not selectable) — mirrors the
                // "Current" row idiom of the in-workout Swap picker.
                Section {
                    orientationRow
                }

                Section {
                    ForEach(routineExercise.alternativesList) { alternative in
                        Button {
                            onSelect(alternative)
                            dismiss()
                        } label: {
                            alternativeRow(alternative)
                        }
                    }

                    Button {
                        onAdd()
                        dismiss()
                    } label: {
                        Label("alternatives.add".localized, systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignSystem.Colors.tint)
                    }
                }
            }
            .navigationTitle("alternatives.browse.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel".localized) { dismiss() }
                }
            }
        }
        .presentationDetents([.height(360), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Rows

    private var orientationRow: some View {
        HStack(spacing: 12) {
            if let exercise = routineExercise.exercise {
                ExerciseAvatarView(
                    muscleGroups: exercise.muscleGroups,
                    equipmentType: exercise.equipmentType,
                    size: 34,
                    radius: 10
                )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(routineExercise.exercise?.name ?? "")
                    .fontWeight(.medium)
                Text("alternatives.browse.for_exercise".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .foregroundStyle(.secondary)
    }

    private func alternativeRow(_ alternative: RoutineExerciseAlternative) -> some View {
        HStack(spacing: 12) {
            if let exercise = alternative.exercise {
                ExerciseAvatarView(
                    muscleGroups: exercise.muscleGroups,
                    equipmentType: exercise.equipmentType,
                    size: 34,
                    radius: 10
                )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(alternative.exercise?.name ?? "")
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(subtitle(for: alternative))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Navigates away (dismisses the sheet, jumps to the inline editor) —
            // a genuine push, so chevron.right is the correct disclosure glyph here.
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func subtitle(for alternative: RoutineExerciseAlternative) -> String {
        var parts: [String] = []
        if let muscles = alternative.exercise?.muscleGroupsDisplay, !muscles.isEmpty {
            parts.append(muscles)
        }
        if let scheme = RoutineMetricsService.setSchemeSummary(
            reps: alternative.setsList.map(\.reps),
            weights: alternative.setsList.map(\.weight)
        ) {
            parts.append(scheme)
        }
        return parts.joined(separator: " · ")
    }
}
