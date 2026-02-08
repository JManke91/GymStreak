import Foundation
import SwiftData
import SwiftUI

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

    private var modelContext: ModelContext
    private var cloudSyncObserver: NSObjectProtocol?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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

    func updateModelContext(_ newContext: ModelContext) {
        self.modelContext = newContext
        fetchExercises()
    }
    
    func fetchExercises() {
        let descriptor = FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name, order: .forward)])
        do {
            exercises = try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching exercises: \(error)")
        }
    }
    
    func addExercise(name: String, muscleGroups: [String]) -> Exercise? {
        let exercise = Exercise(name: name, muscleGroups: muscleGroups)
        modelContext.insert(exercise)
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

    /// Initiates the delete flow - shows confirmation if exercise is used in routines
    func requestDeleteExercise(_ exercise: Exercise) {
        let routines = findRoutinesUsing(exercise)
        exerciseToDelete = exercise
        routinesUsingExercise = routines

        if routines.isEmpty {
            // No routines use this exercise, delete directly
            performDeleteExercise(exercise)
        } else {
            // Show confirmation alert with routine names
            showingDeleteConfirmation = true
        }
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
            modelContext.delete(routineExercise)
        }

        // Now delete the exercise itself
        modelContext.delete(exercise)
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
                modelContext.delete(routineExercise)
            }
            // Then delete the exercise
            modelContext.delete(exercise)
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
            try modelContext.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }
}
