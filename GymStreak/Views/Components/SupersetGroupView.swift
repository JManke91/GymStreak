import SwiftUI

/// Visual container for grouped superset exercises with connecting line and anchor dots
struct SupersetGroupView<Content: View>: View {
    let letter: String
    let exerciseCount: Int
    var color: Color = DesignSystem.Colors.tint
    let content: Content

    init(letter: String, exerciseCount: Int, color: Color = DesignSystem.Colors.tint, @ViewBuilder content: () -> Content) {
        self.letter = letter
        self.exerciseCount = exerciseCount
        self.color = color
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Superset header
            SupersetIndicatorBadge(letter: letter, exerciseCount: exerciseCount, color: color)
                .padding(.bottom, 8)

            // Content with connecting line
            HStack(alignment: .top, spacing: 0) {
                // Vertical connecting line with anchor dots
                SupersetConnectingLine(color: color)
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
    var color: Color = DesignSystem.Colors.tint

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
                    color.opacity(0.5),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

                // Top anchor dot
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .position(x: centerX, y: dotSize / 2)

                // Bottom anchor dot
                Circle()
                    .fill(color)
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
    var color: Color = DesignSystem.Colors.tint
    let content: Content

    init(position: Int, total: Int, color: Color = DesignSystem.Colors.tint, @ViewBuilder content: () -> Content) {
        self.position = position
        self.total = total
        self.color = color
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            content

            Spacer()

            SupersetBadge(position: position, total: total, color: color)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        Section {
            SupersetGroupView(letter: "A", exerciseCount: 3) {
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

        Section {
            let indigo = Color(red: 94/255, green: 92/255, blue: 230/255)
            SupersetGroupView(letter: "B", exerciseCount: 2, color: indigo) {
                ForEach(1...2, id: \.self) { index in
                    SupersetExerciseContainer(position: index, total: 2, color: indigo) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exercise \(index)")
                                .font(.headline)
                            Text("3 sets")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if index < 2 {
                        Divider()
                            .padding(.leading, 8)
                    }
                }
            }
        }
    }
    .listStyle(.insetGrouped)
}
