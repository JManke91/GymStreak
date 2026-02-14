import SwiftUI

/// A small badge showing superset letter and position (e.g., "A1", "B2")
struct SupersetBadge: View {
    let letter: String
    let position: Int
    var color: Color = DesignSystem.Colors.tint

    var body: some View {
        Text("\(letter)\(position)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(DesignSystem.Colors.textOnTint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.8))
            )
    }
}

/// A badge indicating an exercise is part of a superset with link icon
struct SupersetIndicatorBadge: View {
    let letter: String
    let exerciseCount: Int
    var color: Color = DesignSystem.Colors.tint

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .font(.caption2.weight(.semibold))
            Text("Superset \(letter) (\(exerciseCount))")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        SupersetBadge(letter: "A", position: 1)
        SupersetBadge(letter: "A", position: 2)
        SupersetBadge(letter: "B", position: 1, color: Color(red: 94/255, green: 92/255, blue: 230/255))
        SupersetBadge(letter: "B", position: 2, color: Color(red: 94/255, green: 92/255, blue: 230/255))

        SupersetIndicatorBadge(letter: "A", exerciseCount: 3)
        SupersetIndicatorBadge(letter: "B", exerciseCount: 2, color: Color(red: 94/255, green: 92/255, blue: 230/255))
    }
    .padding()
}
