import Foundation
import SwiftUI

/// A section of exercises grouped by muscle category
struct ExerciseSection: Identifiable {
    let categoryTitleKey: String
    let exercises: [Exercise]
    var id: String { categoryTitleKey }
    var localizedTitle: String { categoryTitleKey.localized }
}

@MainActor
class ExercisesViewModel: ObservableObject {
    @Published var exercises: [Exercise] = []
    @Published var showingAddExercise = false
    @Published var selectedExercise: Exercise?

    // Deletion confirmation state
    @Published var exerciseToDelete: Exercise?
    @Published var routinesUsingExercise: [Routine] = []
    @Published var showingDeleteConfirmation = false
    @Published var showingDeleteAllConfirmation = false

    /// Exercises grouped by muscle category, sorted anatomically top-to-bottom
    var groupedExercises: [ExerciseSection] {
        let grouped = Dictionary(grouping: exercises) { exercise -> String in
            let primaryMuscle = exercise.muscleGroups.first ?? "General"
            return MuscleGroups.categoryTitleKey(for: primaryMuscle)
        }
        return grouped
            .map { ExerciseSection(categoryTitleKey: $0.key, exercises: $0.value) }
            .sorted { MuscleGroups.categorySortOrder(for: $0.categoryTitleKey) < MuscleGroups.categorySortOrder(for: $1.categoryTitleKey) }
    }

    private let exerciseRepository: ExerciseRepository
    private let routineRepository: RoutineRepository
    private var cloudSyncObserver: NSObjectProtocol?

    init(exerciseRepository: ExerciseRepository, routineRepository: RoutineRepository) {
        self.exerciseRepository = exerciseRepository
        self.routineRepository = routineRepository
        fetchExercises()
        observeCloudKitChanges()
    }

    private func observeCloudKitChanges() {
        cloudSyncObserver = NotificationCenter.default.addObserver(
            forName: .cloudKitDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fetchExercises()
            }
        }
    }

    func fetchExercises() {
        exercises = exerciseRepository.fetchAll()
    }

    func addExercise(name: String, muscleGroups: [String], equipmentType: EquipmentType = .dumbbell) -> Exercise? {
        let exercise = Exercise(name: name, muscleGroups: muscleGroups, equipmentType: equipmentType)
        exerciseRepository.insert(exercise)
        save()
        fetchExercises()
        return exercise
    }

    func updateExercise(_ exercise: Exercise) {
        exercise.updatedAt = Date()
        save()
        fetchExercises()
    }

    /// Finds all routines that use the given exercise
    func findRoutinesUsing(_ exercise: Exercise) -> [Routine] {
        let routineExercises = exercise.routineExercises ?? []
        let routines = routineExercises.compactMap { $0.routine }
        // Remove duplicates and sort by name
        let uniqueRoutines = Array(Set(routines)).sorted { $0.name < $1.name }
        return uniqueRoutines
    }

    /// Initiates the delete flow - always shows confirmation for safety
    func requestDeleteExercise(_ exercise: Exercise) {
        let routines = findRoutinesUsing(exercise)
        exerciseToDelete = exercise
        routinesUsingExercise = routines
        showingDeleteConfirmation = true
    }

    /// Actually deletes the exercise and removes it from all routines
    func confirmDeleteExercise() {
        guard let exercise = exerciseToDelete else { return }
        performDeleteExercise(exercise)
        resetDeleteState()
    }

    /// Performs the actual deletion of an exercise and its associated RoutineExercises
    private func performDeleteExercise(_ exercise: Exercise) {
        // First, delete all RoutineExercise records that reference this exercise
        // This also cascades to delete their ExerciseSets
        let routineExercises = exercise.routineExercises ?? []
        for routineExercise in routineExercises {
            routineRepository.delete(routineExercise)
        }

        // Now delete the exercise itself
        exerciseRepository.delete(exercise)
        save()
        fetchExercises()
    }

    /// Cancels the delete operation
    func cancelDeleteExercise() {
        resetDeleteState()
    }

    private func resetDeleteState() {
        exerciseToDelete = nil
        routinesUsingExercise = []
        showingDeleteConfirmation = false
    }

    /// Requests confirmation before deleting all exercises
    func requestDeleteAllExercises() {
        showingDeleteAllConfirmation = true
    }

    /// Confirms and performs deletion of all exercises
    func confirmDeleteAllExercises() {
        for exercise in exercises {
            // Delete all RoutineExercise records first
            let routineExercises = exercise.routineExercises ?? []
            for routineExercise in routineExercises {
                routineRepository.delete(routineExercise)
            }
            // Then delete the exercise
            exerciseRepository.delete(exercise)
        }
        save()
        fetchExercises()
        showingDeleteAllConfirmation = false
    }

    /// Cancels the delete all operation
    func cancelDeleteAllExercises() {
        showingDeleteAllConfirmation = false
    }

    private func save() {
        do {
            try exerciseRepository.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }
}
