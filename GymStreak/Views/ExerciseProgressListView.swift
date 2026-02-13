//
//  ExerciseProgressListView.swift
//  GymStreak
//

import SwiftUI
import SwiftData

// MARK: - Exercise With History Model

struct ExerciseWithHistory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let muscleGroups: [String]
    let workoutCount: Int
    let lastPerformed: Date?
    var allExercises: [ExerciseWithHistory] = []

    var primaryMuscleGroup: String {
        muscleGroups.first ?? "General"
    }

    // Hashable conformance (exclude allExercises to avoid circular reference)
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: ExerciseWithHistory, rhs: ExerciseWithHistory) -> Bool {
        lhs.name == rhs.name
    }
}

// MARK: - Exercise Progress List View

struct ExerciseProgressListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var exercisesWithHistory: [ExerciseWithHistory] = []
    @State private var searchText = ""
    @State private var isLoading = true

    private var filteredExercises: [ExerciseWithHistory] {
        if searchText.isEmpty {
            return exercisesWithHistory
        }
        return exercisesWithHistory.filter { exercise in
            exercise.name.localizedCaseInsensitiveContains(searchText) ||
            exercise.muscleGroups.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var groupedExercises: [String: [ExerciseWithHistory]] {
        Dictionary(grouping: filteredExercises) { $0.primaryMuscleGroup }
    }

    private var sortedMuscleGroups: [String] {
        groupedExercises.keys.sorted()
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if exercisesWithHistory.isEmpty {
                ContentUnavailableView {
                    Label("progress.empty.title".localized, systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("progress.empty.description".localized)
                }
            } else if filteredExercises.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(sortedMuscleGroups, id: \.self) { muscleGroup in
                        Section(muscleGroup.localized) {
                            ForEach(groupedExercises[muscleGroup] ?? []) { exercise in
                                NavigationLink(value: exerciseWithAllExercises(exercise)) {
                                    ExerciseProgressRow(exercise: exercise)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $searchText, prompt: "progress.search".localized)
        .task {
            await loadExercisesWithHistory()
        }
    }

    private func exerciseWithAllExercises(_ exercise: ExerciseWithHistory) -> ExerciseWithHistory {
        var updated = exercise
        updated.allExercises = exercisesWithHistory
        return updated
    }

    private func loadExercisesWithHistory() async {
        isLoading = true

        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endTime != nil }
        )

        do {
            let sessions = try modelContext.fetch(descriptor)

            // Aggregate exercises from all workout sessions
            var exerciseMap: [String: (muscleGroups: [String], count: Int, lastDate: Date?)] = [:]

            for session in sessions {
                for exercise in session.workoutExercisesList {
                    let hasCompletedSets = exercise.setsList.contains { $0.isCompleted }
                    guard hasCompletedSets else { continue }

                    let name = exercise.exerciseName
                    let existing = exerciseMap[name]

                    if let existing = existing {
                        let newDate = max(existing.lastDate ?? .distantPast, session.startTime)
                        exerciseMap[name] = (existing.muscleGroups, existing.count + 1, newDate)
                    } else {
                        exerciseMap[name] = (exercise.muscleGroups, 1, session.startTime)
                    }
                }
            }

            // Convert to array and sort by workout count (most performed first)
            exercisesWithHistory = exerciseMap.map { name, data in
                ExerciseWithHistory(
                    name: name,
                    muscleGroups: data.muscleGroups,
                    workoutCount: data.count,
                    lastPerformed: data.lastDate
                )
            }.sorted { $0.workoutCount > $1.workoutCount }

        } catch {
            print("Error loading exercises with history: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Exercise Progress Row

struct ExerciseProgressRow: View {
    let exercise: ExerciseWithHistory

    var body: some View {
        HStack(spacing: 12) {
            MuscleGroupAbbreviationBadge(
                muscleGroups: exercise.muscleGroups,
                isActive: true
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.body)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Label(
                        "progress.workout_count".localized(exercise.workoutCount),
                        systemImage: "figure.strengthtraining.traditional"
                    )

                    if let lastDate = exercise.lastPerformed {
                        Text("•")
                        Text(lastDate, format: .dateTime.month(.abbreviated).day())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(DesignSystem.Colors.tint)
                .font(.body)
        }
        .padding(.vertical, 4)
    }
}
