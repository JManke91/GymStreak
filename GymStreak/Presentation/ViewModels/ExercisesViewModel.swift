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
    private let catalogSync: ExerciseCatalogSyncRequesting
    /// The History model actor fetches the **whole** `Exercise` table
    /// (`SwiftDataHistorySnapshotStore.fetchFortschrittSnapshot`,
    /// `fetchExerciseProgress`, `fetchPreviousPerformances`), so deleting an exercise
    /// removes rows it may be holding — and the cascade through `RoutineExercise`
    /// reaches its routine graph too. Same uncatchable trap as a History deletion;
    /// see `HistoryStoreGate` and `docs/history-delete-race.md`.
    private let historyStoreGate: HistoryStoreGate
    private var cloudSyncObserver: NSObjectProtocol?

    init(
        exerciseRepository: ExerciseRepository,
        routineRepository: RoutineRepository,
        catalogSync: ExerciseCatalogSyncRequesting,
        historyStoreGate: HistoryStoreGate = .unshared()
    ) {
        self.exerciseRepository = exerciseRepository
        self.routineRepository = routineRepository
        self.catalogSync = catalogSync
        self.historyStoreGate = historyStoreGate
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

    func addExercise(
        name: String,
        muscleGroups: [String],
        equipmentType: EquipmentType = .dumbbell,
        loadBehavior: ExerciseLoadBehavior = .resistance
    ) -> Exercise? {
        let exercise = Exercise(
            name: name,
            muscleGroups: muscleGroups,
            equipmentType: equipmentType,
            loadBehavior: loadBehavior
        )
        exerciseRepository.insert(exercise)
        let saved = save()
        fetchExercises()
        if saved { catalogSync.requestCatalogSync() }
        return exercise
    }

    func updateExercise(_ exercise: Exercise) {
        exercise.updatedAt = Date()
        let saved = save()
        fetchExercises()
        if saved { catalogSync.requestCatalogSync() }
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

    /// Actually deletes the exercise and removes it from all routines.
    ///
    /// `async` because the deletion has to exclude the History model actor — see
    /// `historyStoreGate`.
    func confirmDeleteExercise() async {
        guard let exercise = exerciseToDelete else { return }
        // Cleared before the `await`: the confirmation alert's own body reads
        // `exerciseToDelete`, and this now suspends while the gate is held.
        resetDeleteState()
        await performDeleteExercise(exercise)
    }

    /// Performs the actual deletion of an exercise and its associated RoutineExercises
    private func performDeleteExercise(_ exercise: Exercise) async {
        let saved = await historyStoreGate.withExclusiveAccess {
            // First, delete all RoutineExercise records that reference this exercise
            // This also cascades to delete their ExerciseSets
            let routineExercises = exercise.routineExercises ?? []
            for routineExercise in routineExercises {
                routineRepository.delete(routineExercise)
            }

            // Now delete the exercise itself
            exerciseRepository.delete(exercise)
            return save()
        }
        fetchExercises()
        if saved {
            catalogSync.requestCatalogSync()
            notifyRoutineTemplatesChanged()
        }
    }

    /// Deleting an exercise deletes the `RoutineExercise` rows referencing it, so routine
    /// templates changed here even though this screen never touches a routine directly.
    /// `RoutinesViewModel` renders precomputed card models rather than reading the `@Model`
    /// live (docs/history-performance.md §7), so without this the routine cards keep the
    /// deleted exercise's counts and avatars until the next fetch — and the watch keeps the
    /// stale template.
    private func notifyRoutineTemplatesChanged() {
        NotificationCenter.default.post(name: .routineTemplateDidChange, object: nil)
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

    /// Confirms and performs deletion of all exercises.
    ///
    /// `async` for the same reason as `confirmDeleteExercise` — and this is the larger
    /// of the two, since it removes every `Exercise` the History actor holds.
    func confirmDeleteAllExercises() async {
        // Dismissed before the `await`, for the same reason `confirmDeleteExercise`
        // clears its confirmation state first.
        showingDeleteAllConfirmation = false
        let saved = await historyStoreGate.withExclusiveAccess {
            for exercise in exercises {
                // Delete all RoutineExercise records first
                let routineExercises = exercise.routineExercises ?? []
                for routineExercise in routineExercises {
                    routineRepository.delete(routineExercise)
                }
                // Then delete the exercise
                exerciseRepository.delete(exercise)
            }
            return save()
        }
        fetchExercises()
        if saved {
            catalogSync.requestCatalogSync()
            notifyRoutineTemplatesChanged()
        }
    }

    /// Cancels the delete all operation
    func cancelDeleteAllExercises() {
        showingDeleteAllConfirmation = false
    }

    /// Commits pending changes. Success must be observable so callers request
    /// a catalogue sync only for state that actually reached the store — a
    /// failed save must never publish an in-memory snapshot to the watch.
    @discardableResult
    private func save() -> Bool {
        do {
            try exerciseRepository.save()
            NotificationCenter.default.post(name: .historySourceDataDidChange, object: nil)
            return true
        } catch {
            print("Error saving context: \(error)")
            return false
        }
    }
}
