import SwiftUI

struct AddRoutineView: View {
    @ObservedObject var viewModel: RoutinesViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var routineName = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Routine Details") {
                    TextField("Routine Name", text: $routineName)
                }
                
                Section("Next Steps") {
                    Text("After creating this routine, you can add exercises to it from the routine detail view.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("New Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
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
