import SwiftUI

/// Position of an exercise within a superset group
enum SupersetPosition {
    case first   // Show top anchor dot
    case middle  // Just the line, no dots
    case last    // Show bottom anchor dot
    case only    // Single exercise (shouldn't happen, but handle gracefully)
}

/// A visual indicator for superset exercises showing a vertical line with anchor dots
struct SupersetLineIndicator: View {
    let position: SupersetPosition

    private let lineWidth: CGFloat = 3
    private let dotSize: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let height = geometry.size.height
            let dotY = height / 2

            ZStack {
                // Vertical line
                Path { path in
                    let startY: CGFloat
                    let endY: CGFloat

                    switch position {
                    case .first:
                        startY = dotY
                        endY = height
                    case .middle:
                        startY = 0
                        endY = height
                    case .last:
                        startY = 0
                        endY = dotY
                    case .only:
                        startY = dotY
                        endY = dotY
                    }

                    path.move(to: CGPoint(x: centerX, y: startY))
                    path.addLine(to: CGPoint(x: centerX, y: endY))
                }
                .stroke(
                    DesignSystem.Colors.tint.opacity(0.6),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

                // Top anchor dot
                if position == .first || position == .only {
                    Circle()
                        .fill(DesignSystem.Colors.tint)
                        .frame(width: dotSize, height: dotSize)
                        .position(x: centerX, y: dotY)
                }

                // Bottom anchor dot
                if position == .last || position == .only {
                    Circle()
                        .fill(DesignSystem.Colors.tint)
                        .frame(width: dotSize, height: dotSize)
                        .position(x: centerX, y: dotY)
                }
            }
        }
        .frame(width: 16)
    }
}

#Preview {
    VStack(spacing: 0) {
        HStack(spacing: 0) {
            SupersetLineIndicator(position: .first)
            VStack(alignment: .leading) {
                Text("First exercise in superset")
                    .font(.body.weight(.semibold))
                Text("3 sets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            Spacer()
        }
        .frame(height: 50)
        .background(DesignSystem.Colors.tint.opacity(0.08))

        HStack(spacing: 0) {
            SupersetLineIndicator(position: .middle)
            VStack(alignment: .leading) {
                Text("Middle exercise")
                    .font(.body.weight(.semibold))
                Text("3 sets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            Spacer()
        }
        .frame(height: 50)
        .background(DesignSystem.Colors.tint.opacity(0.08))

        HStack(spacing: 0) {
            SupersetLineIndicator(position: .last)
            VStack(alignment: .leading) {
                Text("Last exercise in superset")
                    .font(.body.weight(.semibold))
                Text("3 sets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            Spacer()
        }
        .frame(height: 50)
        .background(DesignSystem.Colors.tint.opacity(0.08))
    }
    .padding()
}
