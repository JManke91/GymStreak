import SwiftUI

struct EmptyWorkoutExerciseListState: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "dumbbell")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No exercises in this workout")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Add an exercise or end the workout.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct AddWorkoutExerciseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add Exercise", systemImage: "plus")
                .fontWeight(.semibold)
                .foregroundStyle(OnyxWatch.Colors.textOnTint)
                .frame(maxWidth: .infinity)
        }
        .listRowBackground(OnyxWatch.Colors.tint)
        .accessibilityHint("Opens your synced iPhone exercise library")
    }
}
