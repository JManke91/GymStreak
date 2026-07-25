import SwiftUI

struct MetricsView: View {
    let elapsedTime: String
    let heartRate: Int?
    let calories: Int?

    var body: some View {
        // The minimized rest timer is NOT declared here — ActiveWorkoutView owns
        // the single instance and overlays it above every workout screen.
        VStack(spacing: 12) {
            // Elapsed time
            Text(elapsedTime)
                .font(.system(.title, design: .rounded).monospacedDigit())
                .foregroundStyle(OnyxWatch.Colors.tint)
                .accessibilityLabel("Elapsed time \(elapsedTime)")

            HStack(spacing: 20) {
                // Heart rate
                VStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(OnyxWatch.Colors.destructive)
                    Text("\(heartRate ?? 0)")
                        .font(.title3.monospacedDigit())
                        .fontWeight(.semibold)
                    Text("BPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                // Calories
                VStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(OnyxWatch.Colors.warning)
                    Text("\(Int(calories ?? 0))")
                        .font(.title3.monospacedDigit())
                        .fontWeight(.semibold)
                    Text("CAL")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .scenePadding()
    }
}

#Preview {
    MetricsView(
        elapsedTime: "23:45",
        heartRate: 142,
        calories: 234
    )
}
