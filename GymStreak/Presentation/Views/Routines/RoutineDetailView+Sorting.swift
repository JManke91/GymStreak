//
//  RoutineDetailView+Sorting.swift
//  GymStreak
//
//  The routine detail's "Sortieren" mode: a dedicated container built on a real
//  `List` + `.onMove`. Kept apart from the browsing container because the two
//  use deliberately different scroll containers — see the note on
//  `sortingModeContent` and docs/routines-exercises-redesign.md.
//

import SwiftUI

extension RoutineDetailView {

    /// Sorting mode uses a real `List` + `.onMove` — the only reorder API that
    /// owns the whole drag lifecycle itself. A hand-rolled `.onDrag`/`.onDrop`
    /// reorder in the LazyVStack left the list permanently dead whenever a drop
    /// landed outside a row (see docs/routines-exercises-redesign.md). The
    /// height-snap reason for avoiding `List` does not apply here: these rows
    /// are fixed-height and nothing expands in this mode.
    var sortingModeContent: some View {
        // Unit grouping and label assignment both walk the whole routine, so
        // they run once for the list here — never inside a row body, and off a
        // single sort. Deriving them per render rather than caching them in
        // `@State` is deliberate: `List.onMove` offsets must match the rendered
        // row set exactly, and a cached copy that drifts by one render would be
        // a real reorder bug.
        let ordered = sortedExercises
        let units = SupersetOrderingService.units(for: ordered)
        let labels = SupersetLabelProvider.labels(for: ordered)

        return VStack(alignment: .leading, spacing: 0) {
            topBar
            titleBlock
                .frame(maxWidth: .infinity, alignment: .leading)
            sortingHint

            List {
                ForEach(units) { unit in
                    sortingRow(for: unit, labels: labels)
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: moveExerciseUnits)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
        }
        .padding(.horizontal, 16)
    }

    /// A superset renders as one framed block, everything else as a plain row.
    /// Either way it is a single `List` row, so a drag can only ever move the
    /// whole unit.
    @ViewBuilder
    func sortingRow(for unit: SupersetOrderingService.OrderingUnit, labels: [UUID: String]) -> some View {
        if let supersetId = unit.supersetId {
            let letter = labels[supersetId] ?? "?"
            RoutineSortingGroupRow(
                label: letter,
                color: SupersetLabelProvider.color(for: letter),
                members: unit.exercises.map { routineExercise in
                    RoutineSortingMemberDisplay(
                        id: routineExercise.id,
                        display: RoutineExerciseCardDisplay(routineExercise),
                        onRemove: { removeExercise(routineExercise) }
                    )
                }
            )
        } else if let routineExercise = unit.exercises.first {
            RoutineSortingRow(
                display: RoutineExerciseCardDisplay(routineExercise),
                onRemove: { removeExercise(routineExercise) }
            )
        }
    }

    /// Persistent while sorting — it explains both affordances of the mode.
    var sortingHint: some View {
        Text("routine.sort_hint".localized)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(DesignSystem.Colors.tint.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(DesignSystem.Colors.tint.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignSystem.Colors.tint.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.bottom, 10)
    }

    /// `List.onMove` hands back offsets into the row set — units, not single
    /// exercises. The reorder transaction itself lives in the ViewModel, like
    /// every other multi-object edit on this screen.
    func moveExerciseUnits(from source: IndexSet, to destination: Int) {
        HapticManager.shared.light()
        viewModel.moveRoutineExerciseUnits(from: source, to: destination, in: routine)
    }
}
