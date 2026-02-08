import SwiftUI

/// A visual indicator for superset exercises showing a vertical line with a link icon
struct SupersetLineIndicator: View {
    var body: some View {
        ZStack {
            // Vertical line
            Rectangle()
                .fill(DesignSystem.Colors.tint)
                .frame(width: 4)

            // Link icon centered on the line
            Image(systemName: "link")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(
                    Circle()
                        .fill(DesignSystem.Colors.tint)
                )
        }
        .frame(width: 20)
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 0) {
            SupersetLineIndicator()
            Text("Exercise in superset")
                .padding()
            Spacer()
        }
        .frame(height: 60)
        .background(DesignSystem.Colors.tint.opacity(0.05))

        HStack(spacing: 0) {
            SupersetLineIndicator()
            Text("Another exercise")
                .padding()
            Spacer()
        }
        .frame(height: 60)
        .background(DesignSystem.Colors.tint.opacity(0.05))
    }
    .padding()
}
