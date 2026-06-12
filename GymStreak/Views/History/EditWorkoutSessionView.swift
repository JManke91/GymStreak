//
//  EditWorkoutSessionView.swift
//  GymStreak
//
//  Lets the user correct a completed (past) workout from the History detail screen:
//  edit reps / weight / completion / rest per set, plus add or delete sets within an
//  exercise. Edits are held in value-type drafts and only written back to the SwiftData
//  @Model objects on Save — Cancel discards them without touching the model. On Save the
//  user is asked whether to push the corrected values back to the routine template
//  (mirrors the active-workout "update template" flow), which then syncs to the watch.
//

import SwiftUI

// MARK: - Drafts

/// Value-type snapshot of one editable set. `existingSetId == nil` marks a set the user
/// added in the editor (no backing `WorkoutSet` yet).
struct WorkoutSetDraft: Identifiable {
    let id: UUID
    let existingSetId: UUID?
    var reps: Int
    var weight: Double
    var restTime: TimeInterval
    var isCompleted: Bool
}

/// Value-type snapshot of one exercise and its sets. `usePlanned` mirrors
/// `WorkoutExercise.progressiveOverloadApplied` — when true the displayed (and edited)
/// values come from the planned fields, matching `WorkoutDetailExerciseBlock`.
struct WorkoutExerciseDraft: Identifiable {
    let id: UUID
    let name: String
    let usePlanned: Bool
    var sets: [WorkoutSetDraft]
}

// MARK: - View

struct EditWorkoutSessionView: View {
    let workout: WorkoutSession
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var exerciseDrafts: [WorkoutExerciseDraft] = []
    @State private var showingTemplatePrompt = false

    var body: some View {
        NavigationStack {
            Form {
                ForEach(exerciseDrafts.indices, id: \.self) { exerciseIndex in
                    exerciseSection(exerciseIndex)
                }
            }
            .navigationTitle("edit_workout.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save".localized) { onSaveTapped() }
                }
            }
            .confirmationDialog(
                "edit_workout.template_prompt.title".localized,
                isPresented: $showingTemplatePrompt,
                titleVisibility: .visible
            ) {
                Button("edit_workout.template_prompt.update".localized) { commit(updateTemplate: true) }
                Button("edit_workout.template_prompt.skip".localized) { commit(updateTemplate: false) }
                Button("action.cancel".localized, role: .cancel) {}
            } message: {
                Text("edit_workout.template_prompt.message".localized)
            }
            .onAppear(perform: buildDrafts)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func exerciseSection(_ exerciseIndex: Int) -> some View {
        Section {
            ForEach(exerciseDrafts[exerciseIndex].sets.indices, id: \.self) { setIndex in
                SetEditorRow(
                    index: setIndex,
                    set: $exerciseDrafts[exerciseIndex].sets[setIndex]
                )
            }
            .onDelete { offsets in
                exerciseDrafts[exerciseIndex].sets.remove(atOffsets: offsets)
            }

            Button {
                addSet(toExerciseAt: exerciseIndex)
            } label: {
                Label("edit_workout.add_set".localized, systemImage: "plus.circle.fill")
                    .foregroundStyle(DesignSystem.Colors.tint)
            }
        } header: {
            Text(exerciseDrafts[exerciseIndex].name)
        }
    }

    // MARK: - Actions

    private func onSaveTapped() {
        // Only offer the template prompt when the session is linked to a routine
        // (recovered/orphaned sessions have none).
        if workout.routine != nil {
            showingTemplatePrompt = true
        } else {
            commit(updateTemplate: false)
        }
    }

    private func commit(updateTemplate: Bool) {
        viewModel.saveEditedWorkout(
            workout,
            exerciseDrafts: exerciseDrafts,
            updateTemplate: updateTemplate
        )
        HapticManager.shared.success()
        dismiss()
    }

    private func addSet(toExerciseAt index: Int) {
        let last = exerciseDrafts[index].sets.last
        let newSet = WorkoutSetDraft(
            id: UUID(),
            existingSetId: nil,
            reps: last?.reps ?? 10,
            weight: last?.weight ?? 0,
            restTime: last?.restTime ?? 60,
            isCompleted: true
        )
        exerciseDrafts[index].sets.append(newSet)
        HapticManager.shared.light()
    }

    // MARK: - Draft building

    private func buildDrafts() {
        guard exerciseDrafts.isEmpty else { return }
        let exercises = workout.workoutExercisesList.sorted(by: { $0.order < $1.order })
        exerciseDrafts = exercises.map { exercise in
            let usePlanned = exercise.progressiveOverloadApplied
            let sets = exercise.setsList.sorted(by: { $0.order < $1.order }).map { set in
                WorkoutSetDraft(
                    id: set.id,
                    existingSetId: set.id,
                    reps: usePlanned ? set.plannedReps : set.actualReps,
                    weight: usePlanned ? set.plannedWeight : set.actualWeight,
                    restTime: set.restTime,
                    isCompleted: set.isCompleted
                )
            }
            return WorkoutExerciseDraft(
                id: exercise.id,
                name: exercise.exerciseName,
                usePlanned: usePlanned,
                sets: sets
            )
        }
    }
}

// MARK: - Set editor row

private struct SetEditorRow: View {
    let index: Int
    @Binding var set: WorkoutSetDraft

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(String(format: "history.detail.set_n".localized, index + 1))
                    .font(.caption.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("edit_workout.completed".localized, isOn: $set.isCompleted)
                    .labelsHidden()
            }

            HorizontalStepper(
                title: "set.reps_label".localized,
                value: $set.reps,
                range: 1...100,
                step: 1
            )

            WeightInput(
                title: "set.weight_label".localized,
                weight: $set.weight,
                increment: 0.25
            )

            VStack(spacing: 8) {
                HStack {
                    Text("edit_set.rest_time".localized)
                        .font(.subheadline)
                    Spacer()
                    Text(TimeFormatting.formatRestTime(set.restTime))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $set.restTime, in: 0...300, step: 30)
            }
        }
        .padding(.vertical, 4)
    }
}
