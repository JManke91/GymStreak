import SwiftUI

/// A small badge showing position within a superset (e.g., "1/3")
struct SupersetBadge: View {
    let position: Int
    let total: Int

    var body: some View {
        Text("\(position)/\(total)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(DesignSystem.Colors.tint.opacity(0.8))
            )
    }
}

/// A badge indicating an exercise is part of a superset with link icon
struct SupersetIndicatorBadge: View {
    let exerciseCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .font(.caption2.weight(.semibold))
            Text("Superset (\(exerciseCount))")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(DesignSystem.Colors.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(DesignSystem.Colors.tint.opacity(0.15))
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        SupersetBadge(position: 1, total: 3)
        SupersetBadge(position: 2, total: 3)
        SupersetBadge(position: 3, total: 3)

        SupersetIndicatorBadge(exerciseCount: 3)
    }
    .padding()
}
