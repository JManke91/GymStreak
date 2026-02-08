import Foundation
import SwiftData
import SwiftUI

@MainActor
class ExercisesViewModel: ObservableObject {
    @Published var exercises: [Exercise] = []
    @Published var showingAddExercise = false
    @Published var selectedExercise: Exercise?

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
    
    func deleteExercise(_ exercise: Exercise) {
        modelContext.delete(exercise)
        save()
        fetchExercises()
    }
    
    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }
}
