import SwiftUI

/// Visual container for grouped superset exercises with connecting line
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
                // Vertical connecting line
                SupersetConnectingLine()
                    .frame(width: 3)
                    .padding(.leading, 4)

                // Grouped exercises
                VStack(spacing: 0) {
                    content
                }
                .padding(.leading, 12)
            }
        }
    }
}

/// Vertical connecting line for superset exercises
struct SupersetConnectingLine: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let x = geometry.size.width / 2
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: geometry.size.height))
            }
            .stroke(
                DesignSystem.Colors.tint.opacity(0.5),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
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
            // Position indicator dot
            Circle()
                .fill(DesignSystem.Colors.tint)
                .frame(width: 8, height: 8)
                .offset(x: -15.5) // Align with connecting line

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
