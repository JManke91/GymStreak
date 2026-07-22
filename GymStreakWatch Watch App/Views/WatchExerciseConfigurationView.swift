import SwiftUI
import WatchKit

struct WatchExerciseConfigurationView: View {
    let selection: WatchExerciseSelection
    let onAdded: () -> Void

    @EnvironmentObject private var catalogStore: ExerciseCatalogStore
    @EnvironmentObject private var workoutViewModel: WatchWorkoutViewModel

    @State private var draft = WatchExerciseConfigurationDraft()
    @State private var unavailableMessage: String?

    private var currentItem: WatchExerciseCatalogItem? {
        WatchWorkoutStructuralReducer.resolve(selection, in: catalogStore.items)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentItem?.name ?? String(localized: "Exercise unavailable"))
                        .font(.headline)
                    if let item = currentItem {
                        Text(item.muscleGroups.first ?? String(localized: "General"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Set configuration") {
                Picker("Sets", selection: $draft.setCount) {
                    ForEach(1...20, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.navigationLink)

                Picker("Reps per set", selection: $draft.reps) {
                    ForEach(1...100, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.navigationLink)

                NavigationLink {
                    WatchWeightConfigurationEditor(value: $draft.weight)
                } label: {
                    HStack {
                        Text("Weight")
                        Spacer()
                        Text(weightText)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Rest", selection: $draft.restSeconds) {
                    ForEach(Array(stride(from: 0, through: 300, by: 30)), id: \.self) { value in
                        Text(restText(value)).tag(value)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section {
                Button {
                    if workoutViewModel.addConfiguredExercise(
                        draft: draft,
                        catalogueItems: catalogStore.items
                    ) != nil {
                        onAdded()
                    } else {
                        unavailableMessage = workoutViewModel.errorMessage
                            ?? String(localized: "This exercise could not be added.")
                    }
                } label: {
                    Text("Add Exercise")
                        .fontWeight(.semibold)
                        .foregroundStyle(OnyxWatch.Colors.textOnTint)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(OnyxWatch.Colors.tint)
            }
        }
        .listStyle(.carousel)
        .navigationTitle("Configure")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Exercise unavailable",
            isPresented: Binding(
                get: { unavailableMessage != nil },
                set: { if !$0 { unavailableMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { unavailableMessage = nil }
        } message: {
            Text(unavailableMessage ?? "")
        }
    }

    private var weightText: String {
        String(localized: "\(Int(draft.weight)) kg")
    }

    private func restText(_ seconds: Int) -> String {
        if seconds == 0 { return String(localized: "No rest") }
        if seconds < 60 { return String(localized: "\(seconds) sec") }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0
            ? String(localized: "\(minutes) min")
            : String(localized: "\(minutes) min \(remainder) sec")
    }
}

struct WatchWeightConfigurationEditor: View {
    @Binding var value: Double
    @FocusState private var isCrownFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("Weight")
                .font(.headline)

            Text("\(Int(value)) kg")
                .font(.title.bold().monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(OnyxWatch.Colors.card, in: RoundedRectangle(cornerRadius: 14))
                .focusable()
                .focused($isCrownFocused)
                .digitalCrownRotation(
                    $value,
                    from: 0,
                    through: 999,
                    by: 1,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                .accessibilityLabel("Weight")
                .accessibilityValue("\(Int(value)) kilograms")
                .accessibilityHint("Turn the Digital Crown or swipe up and down to adjust")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: adjust(by: 1)
                    case .decrement: adjust(by: -1)
                    @unknown default: break
                    }
                }

            HStack(spacing: 18) {
                adjustmentButton(systemName: "minus", label: "Decrease weight", amount: -1)
                adjustmentButton(systemName: "plus", label: "Increase weight", amount: 1)
            }
        }
        .padding(.horizontal, 8)
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isCrownFocused = true }
    }

    private func adjustmentButton(
        systemName: String,
        label: LocalizedStringKey,
        amount: Double
    ) -> some View {
        Button {
            adjust(by: amount)
            WKInterfaceDevice.current().play(.click)
        } label: {
            Image(systemName: systemName)
                .font(.title3.bold())
                .foregroundStyle(OnyxWatch.Colors.textOnTint)
                .frame(width: 44, height: 44)
                .background(OnyxWatch.Colors.tint, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(amount < 0 ? value <= 0 : value >= 999)
        .accessibilityLabel(Text(label))
    }

    private func adjust(by amount: Double) {
        value = min(max(value + amount, 0), 999)
    }
}
