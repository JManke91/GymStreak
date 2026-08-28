import SwiftUI
import WatchKit

struct WatchExerciseConfigurationView: View {
    let selection: WatchExerciseSelection
    let onAdded: () -> Void

    @EnvironmentObject private var catalogStore: ExerciseCatalogStore
    @EnvironmentObject private var workoutViewModel: WatchWorkoutViewModel
    @Environment(\.weightUnit) private var weightUnit

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
                        Text(item.muscleGroups.first.map(localizedWatchMuscleGroup)
                            ?? String(localized: "General"))
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
                    WatchWeightConfigurationEditor(kilograms: $draft.weight)
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
        WatchWeightFormatting.label(draft.weight, in: weightUnit)
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

/// Crown editor for the weight of a Watch-added exercise.
///
/// **The value the crown moves is in display units; the binding it writes is in
/// canonical kilograms.** That split is the whole point: the crown's whole-unit
/// grid has to be the user's grid (±1 kg or ±1 lb), and quantizing the *stored*
/// kilograms instead would silently destroy a pounds value on every edit
/// (135 lb → 61.235 kg → 61 kg → 134.5 lb, drifting again next time). The
/// ceiling is still enforced in kilogram space, so there is one number to keep
/// true whatever unit is showing.
struct WatchWeightConfigurationEditor: View {
    /// Canonical kilograms — what the draft stores and what goes on the wire.
    @Binding var kilograms: Double

    @Environment(\.weightUnit) private var weightUnit
    @FocusState private var isCrownFocused: Bool

    /// The crown's own value, in display units. Seeded on appear rather than
    /// derived per frame so a crown detent is never fought by a re-conversion.
    @State private var display: Double = 0

    /// Whole display units, so the crown's detents line up with the number the
    /// user reads. Derived from the canonical ceiling, never hand-copied.
    private var maximumDisplay: Double {
        weightUnit.maximumDisplay.rounded(.down)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Weight")
                .font(.headline)

            Text(WatchWeightFormatting.displayLabel(display, in: weightUnit))
                .font(.title.bold().monospacedDigit())
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(OnyxWatch.Colors.card, in: RoundedRectangle(cornerRadius: 14))
                .focusable()
                .focused($isCrownFocused)
                .digitalCrownRotation(
                    $display,
                    from: 0,
                    through: maximumDisplay,
                    by: 1,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                .accessibilityLabel("Weight")
                // Through `labelled`, not a hardcoded space: that is the one
                // place the number/unit pairing is expressed, so it carries the
                // locale's order.
                .accessibilityValue(WatchWeightFormatting.labelled(
                    WatchWeightFormatting.displayNumber(display, in: weightUnit),
                    in: weightUnit,
                    unitWord: WatchWeightFormatting.spokenUnitWord(weightUnit)
                ))
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
        .onAppear {
            display = weightUnit.converting(fromKilograms: kilograms).rounded()
            isCrownFocused = true
        }
        // The crown writes `display` directly, so the canonical value is
        // rewritten from it — one direction only, never display ← kg ← display.
        .onChange(of: display) { _, value in
            kilograms = weightUnit.clampedKilograms(fromDisplay: value)
        }
        // The unit can change mid-edit (the iPhone publishes it at any time).
        // Re-derive the crown's value from the canonical kilograms, which never
        // moved, rather than reinterpreting the old number in the new unit.
        .onChange(of: weightUnit) { _, unit in
            display = unit.converting(fromKilograms: kilograms).rounded()
        }
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
        .disabled(amount < 0 ? display <= 0 : display >= maximumDisplay)
        .accessibilityLabel(Text(label))
    }

    private func adjust(by amount: Double) {
        display = min(max(display + amount, 0), maximumDisplay)
    }
}
