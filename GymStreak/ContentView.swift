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
    @StateObject private var workoutViewModel: WorkoutViewModel

    init() {
        // Initialize with a temporary context, will be updated in onAppear
        let tempContext = ModelContext(try! ModelContainer(for: Routine.self, Exercise.self, RoutineExercise.self, ExerciseSet.self, WorkoutSession.self, WorkoutExercise.self, WorkoutSet.self))
        self._workoutViewModel = StateObject(wrappedValue: WorkoutViewModel(modelContext: tempContext))
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
        .onAppear {
            workoutViewModel.updateModelContext(modelContext)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Routine.self, Exercise.self, RoutineExercise.self, ExerciseSet.self, WorkoutSession.self, WorkoutExercise.self, WorkoutSet.self], inMemory: true)
}
