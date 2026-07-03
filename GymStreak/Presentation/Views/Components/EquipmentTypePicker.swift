import SwiftUI

/// A single-select picker for equipment type
struct EquipmentTypePicker: View {
    @Binding var selectedEquipmentType: EquipmentType

    var body: some View {
        LabeledContent("exercises.equipment_type".localized) {
            Menu {
                ForEach(EquipmentType.allCases, id: \.self) { equipmentType in
                    Button {
                        selectedEquipmentType = equipmentType
                    } label: {
                        Label(equipmentType.displayName, systemImage: equipmentType.icon)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectedEquipmentType.icon)
                    Text(selectedEquipmentType.displayName)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var selected: EquipmentType = .dumbbell

        var body: some View {
            Form {
                EquipmentTypePicker(selectedEquipmentType: $selected)
            }
        }
    }

    return PreviewWrapper()
}
