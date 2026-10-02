import SwiftUI

/// Row of equipment tiles used by the add/edit exercise form; single selection.
struct ExerciseEquipmentPicker: View {
    @Binding var selection: EquipmentType

    var body: some View {
        HStack(spacing: 8) {
            ForEach(EquipmentType.allCases, id: \.self) { type in
                tile(type)
            }
        }
    }

    private func tile(_ type: EquipmentType) -> some View {
        let isActive = selection == type
        return Button {
            HapticManager.shared.selection()
            selection = type
        } label: {
            VStack(spacing: 7) {
                Image(systemName: type.icon)
                    .font(.system(size: 20, weight: .medium))
                Text(type.displayName)
                    .font(.system(size: 12, weight: isActive ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? DesignSystem.Colors.tint : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isActive ? DesignSystem.Colors.tint.opacity(0.14) : Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isActive ? DesignSystem.Colors.tint.opacity(0.45) : Color.white.opacity(0.06),
                        lineWidth: 1.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
