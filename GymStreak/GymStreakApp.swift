//
//  GymStreakApp.swift
//  GymStreak
//
//  Created by Julian Manke on 14.08.25.
//

import SwiftUI
import SwiftData

@main
struct GymStreakApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Routine.self, Exercise.self, RoutineExercise.self, ExerciseSet.self, WorkoutSession.self, WorkoutExercise.self, WorkoutSet.self])
    }
}
