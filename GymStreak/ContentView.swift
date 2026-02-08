//
//  ContentView.swift
//  GymStreak
//
//  Created by Julian Manke on 14.08.25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ContentViewInternal(modelContext: modelContext)
    }
}

private struct ContentViewInternal: View {
    @StateObject private var workoutViewModel: WorkoutViewModel

    init(modelContext: ModelContext) {
        self._workoutViewModel = StateObject(wrappedValue: WorkoutViewModel(modelContext: modelContext))
    }

    var body: some View {
        TabView {
            RoutinesView()
                .tabItem {
                    Label("tab.routines".localized, systemImage: "list.bullet")
                }

            ExercisesView()
                .tabItem {
                    Label("tab.exercises".localized, systemImage: "dumbbell.fill")
                }

            WorkoutHistoryView(viewModel: workoutViewModel)
                .tabItem {
                    Label("tab.history".localized, systemImage: "clock.fill")
                }
        }
        .tint(Color.appAccent)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Routine.self, Exercise.self, RoutineExercise.self, ExerciseSet.self, WorkoutSession.self, WorkoutExercise.self, WorkoutSet.self], inMemory: true)
}
