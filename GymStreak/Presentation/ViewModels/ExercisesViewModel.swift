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

    // MARK: - Library filtering & grouping (redesigned Übungen tab)

    /// Muscle categories present in the full library, in anatomical order.
    /// Drives the muscle-group filter pill row.
    var availableCategoryKeys: [String] {
        let keys = Set(exercises.map { MuscleGroups.categoryTitleKey(for: $0.primaryMuscleGroup) })
        return keys.sorted { MuscleGroups.categorySortOrder(for: $0) < MuscleGroups.categorySortOrder(for: $1) }
    }

    /// Equipment types present in the full library, in enum order.
    var availableEquipment: [EquipmentType] {
        EquipmentType.allCases.filter { type in exercises.contains { $0.equipmentType == type } }
    }

    /// Filters the library by free-text search, muscle category and equipment,
    /// then groups the result by muscle category in anatomical order.
    func sections(searchText: String, categoryKey: String?, equipment: EquipmentType?) -> [ExerciseSection] {
        let filtered = exercises.filter { exercise in
            let matchesSearch = searchText.isEmpty
                || exercise.name.localizedCaseInsensitiveContains(searchText)
                || exercise.muscleGroups.contains {
                    MuscleGroups.displayName(for: $0).localizedCaseInsensitiveContains(searchText)
                }
            let matchesCategory = categoryKey == nil
                || MuscleGroups.categoryTitleKey(for: exercise.primaryMuscleGroup) == categoryKey
            let matchesEquipment = equipment == nil || exercise.equipmentType == equipment
            return matchesSearch && matchesCategory && matchesEquipment
        }

        return Dictionary(grouping: filtered) { MuscleGroups.categoryTitleKey(for: $0.primaryMuscleGroup) }
            .map { ExerciseSection(categoryTitleKey: $0.key, exercises: $0.value.sorted { $0.name < $1.name }) }
            .sorted { MuscleGroups.categorySortOrder(for: $0.categoryTitleKey) < MuscleGroups.categorySortOrder(for: $1.categoryTitleKey) }
    }

    /// Routines using an exercise, primary uses first, deduplicated by routine.
    /// `routineExercise` is nil when the exercise appears only as an alternative.
    func usages(for exercise: Exercise) -> [(routine: Routine, routineExercise: RoutineExercise?)] {
        var seen = Set<UUID>()
        var result: [(Routine, RoutineExercise?)] = []
        for routineExercise in exercise.routineExercises ?? [] {
            guard let routine = routineExercise.routine, seen.insert(routine.id).inserted else { continue }
            result.append((routine, routineExercise))
        }
        for alternative in exercise.alternativeUses ?? [] {
            guard let routine = alternative.routineExercise?.routine, seen.insert(routine.id).inserted else { continue }
            result.append((routine, nil))
        }
        return result.sorted { $0.0.name < $1.0.name }
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

    /// Number of distinct routines using the exercise, either as a primary
    /// exercise or as an alternative. Shown on library rows and the detail view.
    func routineUsageCount(for exercise: Exercise) -> Int {
        var routineIds = Set<UUID>()
        for routineExercise in exercise.routineExercises ?? [] {
            if let routine = routineExercise.routine { routineIds.insert(routine.id) }
        }
        for alternative in exercise.alternativeUses ?? [] {
            if let routine = alternative.routineExercise?.routine { routineIds.insert(routine.id) }
        }
        return routineIds.count
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
