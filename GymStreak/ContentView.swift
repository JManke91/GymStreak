//
//  ContentView.swift
//  GymStreak
//
//  Created by Julian Manke on 14.08.25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RoutinesView()
                .tabItem {
                    Label("Routines", systemImage: "list.bullet")
                }
            
            ExercisesView()
                .tabItem {
                    Label("Exercises", systemImage: "dumbbell.fill")
                }
            
            WorkoutView()
                .tabItem {
                    Label("Workout", systemImage: "play.circle")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Routine.self, Exercise.self, RoutineExercise.self, ExerciseSet.self], inMemory: true)
}
