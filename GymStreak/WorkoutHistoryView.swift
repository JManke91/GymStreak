import SwiftUI

struct WorkoutHistoryView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var selectedWorkout: WorkoutSession?

    var body: some View {
        NavigationView {
            Group {
                if viewModel.workoutHistory.isEmpty {
                    ContentUnavailableView {
                        Label("history.empty.title".localized, systemImage: "figure.strengthtraining.traditional")
                    } description: {
                        Text("history.empty.description".localized)
                    }
                } else {
                    List {
                        ForEach(viewModel.workoutHistory) { workout in
                            Button {
                                selectedWorkout = workout
                            } label: {
                                WorkoutHistoryCard(workout: workout)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                        .onDelete(perform: deleteWorkouts)
                    }
                    .listStyle(.plain)
                    .refreshable {
                        viewModel.fetchWorkoutHistory()
                    }
                }
            }
            .navigationTitle("history.title".localized)
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                viewModel.updateModelContext(modelContext)
            }
            .sheet(item: $selectedWorkout) { workout in
                WorkoutDetailView(workout: workout)
            }
        }
    }

    private func deleteWorkouts(offsets: IndexSet) {
        for index in offsets {
            let workout = viewModel.workoutHistory[index]
            viewModel.deleteWorkout(workout)
        }
    }
}

// MARK: - Workout History Card

struct WorkoutHistoryCard: View {
    let workout: WorkoutSession

    var body: some View {
        HStack(spacing: 16) {
            // Date Badge
            VStack(spacing: 2) {
                Text(workout.startTime, format: .dateTime.day())
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                Text(workout.startTime, format: .dateTime.month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 60)
            .padding(.vertical, 8)
            .background(Color.appAccent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(workout.routineName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    Label(formatDuration(workout.duration), systemImage: "clock.fill")
                    Label("\(workout.completedSetsCount)", systemImage: "checkmark.circle.fill")
                    Label("\(workout.completionPercentage)%", systemImage: "chart.bar.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
