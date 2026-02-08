import SwiftUI

/// Visual container for grouped superset exercises with connecting line and anchor dots
struct SupersetGroupView<Content: View>: View {
    let exerciseCount: Int
    let content: Content

    init(exerciseCount: Int, @ViewBuilder content: () -> Content) {
        self.exerciseCount = exerciseCount
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Superset header
            SupersetIndicatorBadge(exerciseCount: exerciseCount)
                .padding(.bottom, 8)

            // Content with connecting line
            HStack(alignment: .top, spacing: 0) {
                // Vertical connecting line with anchor dots
                SupersetConnectingLine()
                    .frame(width: 12)
                    .padding(.leading, 4)

                // Grouped exercises
                VStack(spacing: 0) {
                    content
                }
                .padding(.leading, 8)
            }
        }
    }
}

/// Vertical connecting line for superset exercises with anchor dots at start and end
struct SupersetConnectingLine: View {
    private let lineWidth: CGFloat = 3
    private let dotSize: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let height = geometry.size.height

            ZStack {
                // Vertical line connecting the dots
                Path { path in
                    path.move(to: CGPoint(x: centerX, y: dotSize / 2))
                    path.addLine(to: CGPoint(x: centerX, y: height - dotSize / 2))
                }
                .stroke(
                    DesignSystem.Colors.tint.opacity(0.5),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

                // Top anchor dot
                Circle()
                    .fill(DesignSystem.Colors.tint)
                    .frame(width: dotSize, height: dotSize)
                    .position(x: centerX, y: dotSize / 2)

                // Bottom anchor dot
                Circle()
                    .fill(DesignSystem.Colors.tint)
                    .frame(width: dotSize, height: dotSize)
                    .position(x: centerX, y: height - dotSize / 2)
            }
        }
    }
}

/// Container for a single exercise within a superset (shows position badge)
struct SupersetExerciseContainer<Content: View>: View {
    let position: Int
    let total: Int
    let content: Content

    init(position: Int, total: Int, @ViewBuilder content: () -> Content) {
        self.position = position
        self.total = total
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            content

            Spacer()

            SupersetBadge(position: position, total: total)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        Section {
            SupersetGroupView(exerciseCount: 3) {
                ForEach(1...3, id: \.self) { index in
                    SupersetExerciseContainer(position: index, total: 3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exercise \(index)")
                                .font(.headline)
                            Text("3 sets")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if index < 3 {
                        Divider()
                            .padding(.leading, 8)
                    }
                }
            }
        }
    }
    .listStyle(.insetGrouped)
}
