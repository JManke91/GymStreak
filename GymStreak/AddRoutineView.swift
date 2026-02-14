import SwiftUI

struct AddRoutineView: View {
    @ObservedObject var viewModel: RoutinesViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var routineName = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("add_routine.section.details".localized) {
                    TextField("add_routine.name_placeholder".localized, text: $routineName)
                }

                Section("add_routine.section.next_steps".localized) {
                    Text("add_routine.next_steps_description".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("add_routine.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("action.cancel".localized) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("action.save".localized) {
                        saveRoutine()
                    }
                    .disabled(routineName.isEmpty)
                }
            }
        }
    }
    
    private func saveRoutine() {
        viewModel.addRoutine(name: routineName)
        dismiss()
    }
}

#Preview {
    Text("AddRoutineView Preview")
}
