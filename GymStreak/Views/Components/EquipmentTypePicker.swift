import SwiftUI

/// A single-select picker for equipment type
struct EquipmentTypePicker: View {
    @Binding var selectedEquipmentType: EquipmentType

    var body: some View {
        Picker(selection: $selectedEquipmentType) {
            ForEach(EquipmentType.allCases, id: \.self) { equipmentType in
                Label(equipmentType.displayName, systemImage: equipmentType.icon)
                    .tag(equipmentType)
            }
        } label: {
            Text("exercises.equipment_type".localized)
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
