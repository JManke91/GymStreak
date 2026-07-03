import SwiftUI

/// A small badge showing superset position (e.g., "1/2", "2/3")
struct SupersetBadge: View {
    let position: Int
    let total: Int
    var color: Color = DesignSystem.Colors.tint

    var body: some View {
        Text("\(position)/\(total)")
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
        SupersetBadge(position: 1, total: 3)
        SupersetBadge(position: 2, total: 3)
        SupersetBadge(position: 1, total: 2, color: Color(red: 94/255, green: 92/255, blue: 230/255))
        SupersetBadge(position: 2, total: 2, color: Color(red: 94/255, green: 92/255, blue: 230/255))

        SupersetIndicatorBadge(letter: "A", exerciseCount: 3)
        SupersetIndicatorBadge(letter: "B", exerciseCount: 2, color: Color(red: 94/255, green: 92/255, blue: 230/255))
    }
    .padding()
}
