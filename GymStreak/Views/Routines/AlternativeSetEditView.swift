import SwiftUI
import SwiftData

/// Edits the set scheme (reps / weight / rest) of a single alternative exercise.
/// Presented as a sheet from the routine editor's alternatives edit mode.
struct AlternativeSetEditView: View {
    let alternative: RoutineExerciseAlternative
    @ObservedObject var viewModel: RoutinesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var restTimerExpanded = false

    private var sortedSets: [AlternativeExerciseSet] {
        alternative.setsList
    }

    private var restTime: TimeInterval {
        sortedSets.first?.restTime ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Rest timer applies to all sets of this alternative
                    RestTimerConfigView(
                        restTime: Binding(
                            get: { restTime },
                            set: { newValue in updateAllSetsRestTime(newValue) }
                        ),
                        isExpanded: $restTimerExpanded,
                        showToggle: true
                    )

                    ForEach(Array(sortedSets.enumerated()), id: \.element.id) { index, set in
                        setCard(set: set, index: index)
                    }

                    // Add Set
                    Button {
                        withAnimation(DesignSystem.Animation.spring) {
                            viewModel.addSet(to: alternative)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("exercise.add_set".localized)
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.Colors.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(DesignSystem.Colors.input)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle(alternative.exercise?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("action.done".localized) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func setCard(set: AlternativeExerciseSet, index: Int) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(index + 1)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DesignSystem.Colors.textOnTint)
                    .frame(width: 28, height: 28)
                    .background(DesignSystem.Colors.tint)
                    .clipShape(Circle())

                Spacer()

                if sortedSets.count > 1 {
                    Button {
                        withAnimation(DesignSystem.Animation.spring) {
                            viewModel.removeSet(set, from: alternative)
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .red)
                            .symbolRenderingMode(.palette)
                    }
                    .buttonStyle(.plain)
                }
            }

            HorizontalStepper(
                title: "set.reps_label".localized,
                value: Binding(
                    get: { set.reps },
                    set: { set.reps = $0 }
                ),
                range: 1...100,
                onUpdate: { _ in viewModel.updateSet(set) }
            )

            WeightInput(
                title: "set.weight_label".localized,
                weight: Binding(
                    get: { set.weight },
                    set: { set.weight = $0 }
                ),
                onUpdate: { _ in viewModel.updateSet(set) }
            )
        }
        .padding()
        .background(DesignSystem.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func updateAllSetsRestTime(_ newValue: TimeInterval) {
        for set in alternative.setsList {
            set.restTime = newValue
        }
        if let first = alternative.setsList.first {
            viewModel.updateSet(first)
        }
    }
}
