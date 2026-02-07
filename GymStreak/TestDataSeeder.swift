//
//  TestDataSeeder.swift
//  GymStreak
//
//  Created for UI Testing - Seeds realistic data for App Store screenshots
//

import Foundation
import SwiftData

@MainActor
class TestDataSeeder {
    static func seedData(modelContext: ModelContext) {
        clearExistingData(modelContext: modelContext)

        let exercises = seedExercises(modelContext: modelContext)
        seedRoutines(modelContext: modelContext, exercises: exercises)
        seedWorkoutHistory(modelContext: modelContext)

        do {
            try modelContext.save()
        } catch {
            print("Failed to save test data: \(error)")
        }
    }

    private static func clearExistingData(modelContext: ModelContext) {
        do {
            try modelContext.delete(model: WorkoutSet.self)
            try modelContext.delete(model: WorkoutExercise.self)
            try modelContext.delete(model: WorkoutSession.self)
            try modelContext.delete(model: ExerciseSet.self)
            try modelContext.delete(model: RoutineExercise.self)
            try modelContext.delete(model: Routine.self)
            try modelContext.delete(model: Exercise.self)
        } catch {
            print("Failed to clear existing data: \(error)")
        }
    }

    private static func seedExercises(modelContext: ModelContext) -> [String: Exercise] {
        var exerciseMap: [String: Exercise] = [:]

        // Exercise data with localization keys: (nameKey, muscleGroup, descriptionKey)
        let allExercises: [(nameKey: String, muscleGroup: String, descKey: String)] = [
            ("testdata.exercise.bench_press", "Chest", "testdata.exercise.desc.bench_press"),
            ("testdata.exercise.incline_dumbbell_press", "Chest", "testdata.exercise.desc.incline_dumbbell_press"),
            ("testdata.exercise.cable_flyes", "Chest", "testdata.exercise.desc.cable_flyes"),
            ("testdata.exercise.overhead_press", "Front Delts", "testdata.exercise.desc.overhead_press"),
            ("testdata.exercise.lateral_raises", "Side Delts", "testdata.exercise.desc.lateral_raises"),
            ("testdata.exercise.tricep_pushdowns", "Triceps", "testdata.exercise.desc.tricep_pushdowns"),
            ("testdata.exercise.deadlift", "Lower Back", "testdata.exercise.desc.deadlift"),
            ("testdata.exercise.pull_ups", "Lats", "testdata.exercise.desc.pull_ups"),
            ("testdata.exercise.barbell_rows", "Upper Back", "testdata.exercise.desc.barbell_rows"),
            ("testdata.exercise.face_pulls", "Rear Delts", "testdata.exercise.desc.face_pulls"),
            ("testdata.exercise.hammer_curls", "Biceps", "testdata.exercise.desc.hammer_curls"),
            ("testdata.exercise.back_squat", "Quadriceps", "testdata.exercise.desc.back_squat"),
            ("testdata.exercise.romanian_deadlift", "Hamstrings", "testdata.exercise.desc.romanian_deadlift"),
            ("testdata.exercise.leg_press", "Quadriceps", "testdata.exercise.desc.leg_press"),
            ("testdata.exercise.leg_curls", "Hamstrings", "testdata.exercise.desc.leg_curls"),
            ("testdata.exercise.calf_raises", "Calves", "testdata.exercise.desc.calf_raises")
        ]

        for exerciseData in allExercises {
            let name = exerciseData.nameKey.localized
            let description = exerciseData.descKey.localized
            let exercise = Exercise(name: name, muscleGroup: exerciseData.muscleGroup, exerciseDescription: description)
            modelContext.insert(exercise)
            // Use the localization key as the map key for lookup
            exerciseMap[exerciseData.nameKey] = exercise
        }

        return exerciseMap
    }

    private static func seedRoutines(modelContext: ModelContext, exercises: [String: Exercise]) {
        let pushDay = Routine(name: "testdata.routine.push_day".localized)
        modelContext.insert(pushDay)
        addExercisesToRoutine(
            pushDay,
            exercises: [
                ("testdata.exercise.bench_press", 4, 8, 185.0, 120),
                ("testdata.exercise.incline_dumbbell_press", 3, 10, 70.0, 90),
                ("testdata.exercise.cable_flyes", 3, 12, 40.0, 60),
                ("testdata.exercise.overhead_press", 4, 8, 115.0, 120),
                ("testdata.exercise.lateral_raises", 3, 12, 20.0, 60),
                ("testdata.exercise.tricep_pushdowns", 3, 12, 60.0, 60)
            ],
            exerciseMap: exercises,
            modelContext: modelContext
        )

        let pullDay = Routine(name: "testdata.routine.pull_day".localized)
        modelContext.insert(pullDay)
        addExercisesToRoutine(
            pullDay,
            exercises: [
                ("testdata.exercise.deadlift", 4, 5, 315.0, 180),
                ("testdata.exercise.pull_ups", 4, 10, 0.0, 90),
                ("testdata.exercise.barbell_rows", 4, 8, 155.0, 120),
                ("testdata.exercise.face_pulls", 3, 15, 40.0, 60),
                ("testdata.exercise.hammer_curls", 3, 10, 40.0, 60)
            ],
            exerciseMap: exercises,
            modelContext: modelContext
        )

        let legDay = Routine(name: "testdata.routine.leg_day".localized)
        modelContext.insert(legDay)
        addExercisesToRoutine(
            legDay,
            exercises: [
                ("testdata.exercise.back_squat", 4, 8, 225.0, 150),
                ("testdata.exercise.romanian_deadlift", 3, 10, 185.0, 120),
                ("testdata.exercise.leg_press", 3, 12, 360.0, 90),
                ("testdata.exercise.leg_curls", 3, 12, 90.0, 60),
                ("testdata.exercise.calf_raises", 4, 15, 100.0, 45)
            ],
            exerciseMap: exercises,
            modelContext: modelContext
        )
    }

    private static func addExercisesToRoutine(
        _ routine: Routine,
        exercises: [(nameKey: String, sets: Int, reps: Int, weight: Double, restTime: TimeInterval)],
        exerciseMap: [String: Exercise],
        modelContext: ModelContext
    ) {
        for (index, exerciseData) in exercises.enumerated() {
            guard let exercise = exerciseMap[exerciseData.nameKey] else { continue }

            let routineExercise = RoutineExercise(exercise: exercise, order: index)
            routineExercise.routine = routine

            for _ in 0..<exerciseData.sets {
                let set = ExerciseSet(
                    reps: exerciseData.reps,
                    weight: exerciseData.weight,
                    restTime: exerciseData.restTime
                )
                set.routineExercise = routineExercise
                routineExercise.sets.append(set)
                modelContext.insert(set)
            }

            routine.routineExercises.append(routineExercise)
            modelContext.insert(routineExercise)
        }
    }

    private static func seedWorkoutHistory(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Routine>()
        guard let routines = try? modelContext.fetch(descriptor), !routines.isEmpty else {
            return
        }

        let dates = [
            Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
            Calendar.current.date(byAdding: .day, value: -5, to: Date())!,
            Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
            Calendar.current.date(byAdding: .day, value: -9, to: Date())!
        ]

        for (index, date) in dates.enumerated() {
            let routine = routines[index % routines.count]
            let session = WorkoutSession(routine: routine)
            session.startTime = date
            session.endTime = date.addingTimeInterval(3600 + Double(index) * 300)
            session.didUpdateTemplate = true

            for routineExercise in routine.routineExercises {
                let workoutExercise = WorkoutExercise(from: routineExercise, order: routineExercise.order)
                workoutExercise.workoutSession = session

                for set in workoutExercise.sets {
                    set.isCompleted = true
                    set.completedAt = date.addingTimeInterval(Double(set.order) * 180)
                    modelContext.insert(set)
                }

                session.workoutExercises.append(workoutExercise)
                modelContext.insert(workoutExercise)
            }

            modelContext.insert(session)
        }
    }
}
