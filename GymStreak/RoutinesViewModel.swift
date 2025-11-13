import Foundation
import SwiftData
import SwiftUI

@MainActor
class RoutinesViewModel: ObservableObject {
    @Published var routines: [Routine] = []
    @Published var showingAddRoutine = false
    @Published var selectedRoutine: Routine?
    
    private var modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchRoutines()
    }
    
    func updateModelContext(_ newContext: ModelContext) {
        self.modelContext = newContext
        fetchRoutines()
    }
    
    func fetchRoutines() {
        let descriptor = FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        do {
            routines = try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching routines: \(error)")
        }
    }
    
    func addRoutine(name: String) {
        let routine = Routine(name: name)
        modelContext.insert(routine)
        save()
        fetchRoutines()
    }
    
    func updateRoutine(_ routine: Routine) {
        routine.updatedAt = Date()
        save()
        fetchRoutines()
    }
    
    func deleteRoutine(_ routine: Routine) {
        modelContext.delete(routine)
        save()
        fetchRoutines()
    }
    
    func removeRoutineExercise(_ routineExercise: RoutineExercise, from routine: Routine) {
        if let index = routine.routineExercises.firstIndex(where: { $0.id == routineExercise.id }) {
            routine.routineExercises.remove(at: index)
            modelContext.delete(routineExercise)
            updateRoutine(routine)
        }
    }
    
    func addSet(to routineExercise: RoutineExercise) {
        let set = ExerciseSet(reps: 10, weight: 0.0, restTime: 60)
        set.routineExercise = routineExercise
        routineExercise.sets.append(set)
        if let routine = routineExercise.routine {
            updateRoutine(routine)
        }
    }
    
    func removeSet(_ set: ExerciseSet, from routineExercise: RoutineExercise) {
        if let index = routineExercise.sets.firstIndex(where: { $0.id == set.id }) {
            routineExercise.sets.remove(at: index)
            modelContext.delete(set)
            if let routine = routineExercise.routine {
                updateRoutine(routine)
            }
        }
    }
    
    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }
}
