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

    /// Observable singletons — @State so SwiftUI tracks their changes.
    @State private var preferences = AICoachPreferences.shared
    @State private var availability = AICoachAvailability.shared

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

            HistoryView(viewModel: workoutViewModel)
                .tabItem {
                    Label("tab.history".localized, systemImage: "clock.fill")
                }
        }
        .tint(DesignSystem.Colors.tint)
        .preferredColorScheme(.dark)
        // AI Coach opt-in: shown once when Apple Intelligence is available
        // and the user has not yet completed or permanently dismissed opt-in.
        .fullScreenCover(isPresented: .constant(shouldShowOptIn)) {
            AICoachOptInView()
        }
        .task {
            // Resolve availability on first foreground; the fullScreenCover
            // binding re-evaluates once state changes from .unknown → .available.
            await availability.refresh()
        }
    }

    /// `true` when all conditions for showing the opt-in screen are met.
    private var shouldShowOptIn: Bool {
        availability.isAvailable && preferences.shouldShowOptIn
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Routine.self, Exercise.self, RoutineExercise.self, ExerciseSet.self, WorkoutSession.self, WorkoutExercise.self, WorkoutSet.self], inMemory: true)
}
