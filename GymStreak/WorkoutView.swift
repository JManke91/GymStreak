import SwiftUI

struct WorkoutView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "dumbbell")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Workout Tab")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("This tab will be implemented in the next phase to include:")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("• Start workout from routines")
                    Text("• Freestyle workout creation")
                    Text("• Apple HealthKit integration")
                    Text("• Set completion tracking")
                    Text("• Rest timer functionality")
                }
                .font(.body)
                .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Workout")
        }
    }
}

#Preview {
    WorkoutView()
}
