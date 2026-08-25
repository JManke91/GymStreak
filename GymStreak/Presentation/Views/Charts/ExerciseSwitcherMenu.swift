//
//  ExerciseSwitcherMenu.swift
//  GymStreak
//
//  Split out of ExerciseProgressChartView.swift (2026-08-24) when the same-name
//  disambiguation grew it: the menu is self-contained, and its sibling ExerciseUsageMenu
//  already lives in its own file.
//

import SwiftUI

/// The exercise detail screen's "switch exercise" menu.
///
/// Entries print `ExerciseWithHistory.displayName`, so two library exercises sharing a
/// name ("Biceps Curls" barbell and dumbbell) are separable here exactly as they are in
/// the Fortschritt list. They are also keyed and checkmarked by `stableKey` rather than
/// by name — same-named entries would otherwise collide as `ForEach` ids and both show
/// the checkmark.
struct ExerciseSwitcherMenu: View {
    let currentExercise: String
    let currentExerciseId: UUID?
    let onSelect: (ExerciseWithHistory) -> Void

    /// Grouped in `init` rather than in a computed property, so the pass over the library
    /// runs once per construction instead of twice per menu `body`. The owning screen's
    /// body still reconstructs this view on its own invalidations, so this is a reduction,
    /// not an escape from the render path — the collection is the exercise library and the
    /// work is a single grouping pass.
    private let sortedMuscleGroups: [String]
    private let groupedExercises: [String: [ExerciseWithHistory]]
    /// Mirrors `ExerciseWithHistory.stableKey` for the exercise currently charted.
    /// Resolved once, not once per menu entry — `UUID.uuidString` allocates.
    private let currentKey: String

    init(
        currentExercise: String,
        currentExerciseId: UUID?,
        exercises: [ExerciseWithHistory],
        onSelect: @escaping (ExerciseWithHistory) -> Void
    ) {
        self.currentExercise = currentExercise
        self.currentExerciseId = currentExerciseId
        self.onSelect = onSelect
        self.currentKey = currentExerciseId?.uuidString ?? currentExercise.lowercased()
        let grouped = Dictionary(grouping: exercises) { $0.primaryMuscleGroup }
        self.groupedExercises = grouped
        self.sortedMuscleGroups = grouped.keys.sorted()
    }

    var body: some View {
        Menu {
            ForEach(sortedMuscleGroups, id: \.self) { muscleGroup in
                Section(muscleGroup.localized) {
                    ForEach(groupedExercises[muscleGroup] ?? [], id: \.stableKey) { exercise in
                        Button {
                            onSelect(exercise)
                        } label: {
                            HStack {
                                Text(exercise.displayName)
                                if exercise.stableKey == currentKey {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                Text("switch".localized)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel("chart.switch_exercise".localized(currentExercise))
    }
}
