import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class WorkoutViewModel: ObservableObject {
    @Published var currentSession: WorkoutSession?
    @Published var elapsedTime: TimeInterval = 0
    @Published var currentExerciseIndex: Int = 0
    @Published var currentSetIndex: Int = 0
    @Published var isRestTimerActive = false
    @Published var restTimeRemaining: TimeInterval = 0
    @Published var workoutHistory: [WorkoutSession] = []

    private var modelContext: ModelContext
    private var timer: Timer?
    private var restTimer: Timer?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchWorkoutHistory()
    }

    func updateModelContext(_ newContext: ModelContext) {
        self.modelContext = newContext
        fetchWorkoutHistory()
    }

    // MARK: - Workout Session Management

    func startWorkout(routine: Routine) {
        let session = WorkoutSession(routine: routine)

        // Create workout exercises from routine
        for (index, routineExercise) in routine.routineExercises.enumerated() {
            let workoutExercise = WorkoutExercise(from: routineExercise, order: index)
            workoutExercise.workoutSession = session
            session.workoutExercises.append(workoutExercise)
        }

        currentSession = session
        elapsedTime = 0
        currentExerciseIndex = 0
        currentSetIndex = 0

        modelContext.insert(session)
        save()

        startTimer()
    }

    func cancelWorkout() {
        stopTimer()
        stopRestTimer()

        if let session = currentSession {
            modelContext.delete(session)
            save()
        }

        currentSession = nil
        elapsedTime = 0
        currentExerciseIndex = 0
        currentSetIndex = 0
    }

    func pauseForCompletion() {
        guard let session = currentSession else { return }

        // Stop timers and set end time when user clicks "Finish Workout"
        stopTimer()
        stopRestTimer()
        session.endTime = Date()
        save()
    }

    func completeWorkout(updateTemplate: Bool, notes: String) {
        guard let session = currentSession else { return }

        // Update workout details
        session.notes = notes
        session.didUpdateTemplate = updateTemplate

        if updateTemplate {
            updateRoutineTemplate(session: session)
        }

        save()
        fetchWorkoutHistory()

        currentSession = nil
        elapsedTime = 0
    }

    // MARK: - Set Management

    func completeSet(workoutExercise: WorkoutExercise, set: WorkoutSet) {
        guard currentSession != nil else { return }

        objectWillChange.send()
        set.isCompleted = true
        set.completedAt = Date()
        save()

        // Check if there's any more work to do in the workout
        let hasMoreWork = findNextIncompleteSet() != nil

        // Find next incomplete set in current exercise
        if findNextIncompleteSet(after: set, in: workoutExercise) != nil {
            // More sets in same exercise - start rest timer if configured
            if set.restTime > 0 {
                startRestTimer(duration: set.restTime)
            }
        } else if hasMoreWork {
            // No more sets in current exercise, but more exercises remain
            // Start rest timer before moving to next exercise
            if set.restTime > 0 {
                startRestTimer(duration: set.restTime)
            }
            moveToNextExercise()
        } else {
            // Workout complete - no more work to do
            moveToNextExercise()
        }
    }

    func uncompleteSet(_ set: WorkoutSet) {
        guard currentSession != nil else { return }

        objectWillChange.send()
        set.isCompleted = false
        set.completedAt = nil
        save()
    }

    func updateSet(_ set: WorkoutSet, reps: Int, weight: Double) {
        objectWillChange.send()
        set.actualReps = reps
        set.actualWeight = weight
        save()
    }

    func skipSet(workoutExercise: WorkoutExercise, set: WorkoutSet) {
        // Move to next set without marking complete
        if let nextSet = findNextIncompleteSet(after: set, in: workoutExercise) {
            // Update current set index
            if let index = workoutExercise.sets.firstIndex(where: { $0.id == nextSet.id }) {
                currentSetIndex = index
            }
        } else {
            moveToNextExercise()
        }
    }

    // MARK: - Timer Management

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.elapsedTime += 1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func pauseWorkout() {
        stopTimer()
    }

    func resumeWorkout() {
        startTimer()
    }

    func startRestTimer(duration: TimeInterval) {
        stopRestTimer()

        restTimeRemaining = duration
        isRestTimerActive = true

        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if self.restTimeRemaining > 0 {
                    self.restTimeRemaining -= 1

                    // Haptic feedback at 3 seconds
                    if self.restTimeRemaining == 3 {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                } else {
                    self.stopRestTimer()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        isRestTimerActive = false
        restTimeRemaining = 0
    }

    // MARK: - Navigation Helpers

    private func findNextIncompleteSet(after currentSet: WorkoutSet, in workoutExercise: WorkoutExercise) -> WorkoutSet? {
        guard let currentIndex = workoutExercise.sets.firstIndex(where: { $0.id == currentSet.id }) else {
            return nil
        }

        // Find next incomplete set in same exercise
        for index in (currentIndex + 1)..<workoutExercise.sets.count {
            let set = workoutExercise.sets[index]
            if !set.isCompleted {
                currentSetIndex = index
                return set
            }
        }

        return nil
    }

    func findNextIncompleteSet() -> (exercise: WorkoutExercise, set: WorkoutSet)? {
        guard let session = currentSession else { return nil }

        for exercise in session.workoutExercises.sorted(by: { $0.order < $1.order }) {
            for set in exercise.sets.sorted(by: { $0.order < $1.order }) {
                if !set.isCompleted {
                    return (exercise, set)
                }
            }
        }

        return nil
    }

    private func moveToNextExercise() {
        guard let session = currentSession else { return }

        let sortedExercises = session.workoutExercises.sorted(by: { $0.order < $1.order })

        if currentExerciseIndex < sortedExercises.count - 1 {
            currentExerciseIndex += 1
            currentSetIndex = 0
        }
    }

    // MARK: - Template Update

    private func updateRoutineTemplate(session: WorkoutSession) {
        guard let routine = session.routine else { return }

        for workoutExercise in session.workoutExercises {
            // Find corresponding routine exercise
            if let routineExercise = routine.routineExercises.first(where: {
                $0.exercise?.name == workoutExercise.exerciseName
            }) {
                // Update sets that were completed
                for (index, workoutSet) in workoutExercise.sets.enumerated() {
                    if workoutSet.isCompleted && index < routineExercise.sets.count {
                        let routineSet = routineExercise.sets[index]
                        routineSet.reps = workoutSet.actualReps
                        routineSet.weight = workoutSet.actualWeight
                    }
                }
            }
        }

        routine.updatedAt = Date()
        save()
    }

    // MARK: - History

    func fetchWorkoutHistory() {
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        do {
            workoutHistory = try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching workout history: \(error)")
        }
    }

    func deleteWorkout(_ session: WorkoutSession) {
        modelContext.delete(session)
        save()
        fetchWorkoutHistory()
    }

    // MARK: - Helper Methods

    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }

    deinit {
        timer?.invalidate()
        restTimer?.invalidate()
    }
}
