//
//  PendingExerciseList.swift
//  GymStreak
//
//  The Create-Routine screen's draft: its exercises in routine order, and the
//  rules for editing them — including linking, unlinking and reordering
//  supersets before the routine exists. A value type with no SwiftUI, so the
//  rules are unit-testable and stay out of the view (Hard rule 3).
//
//  The draft keeps the same invariant the saved routine has (see
//  SupersetOrderingService): a superset is one contiguous block with at least
//  two members. Every edit here preserves it — linking only joins neighbours,
//  moves go by whole units, a lone survivor is unlinked. The save still runs
//  `SupersetOrderingService.normalizeOrdering` rather than trusting the draft.
//

import Foundation

struct PendingExerciseList {

    /// One draggable/displayable unit: a standalone exercise, or a whole
    /// superset in member order. The draft counterpart of
    /// `SupersetOrderingService.OrderingUnit`.
    struct Unit: Identifiable {
        /// The superset's id for a group, the exercise's id for a standalone one.
        let id: UUID
        let supersetId: UUID?
        var exercises: [PendingRoutineExercise]
    }

    /// In routine order; `order` always equals the index.
    private(set) var exercises: [PendingRoutineExercise] = [] {
        didSet { rebuildDerivedState() }
    }

    /// supersetId → "A", "B", … — the same letters the routine detail screen
    /// shows once saved.
    private(set) var supersetLabels: [UUID: String] = [:]

    /// `exercises` folded into units. Like `supersetLabels`, kept in step with
    /// every edit so a render never has to compute it.
    private(set) var units: [Unit] = []

    var isEmpty: Bool { exercises.isEmpty }

    func exercise(withId id: UUID) -> PendingRoutineExercise? {
        exercises.first { $0.id == id }
    }

    /// The group letter of an exercise, or nil if it is standalone.
    func supersetLabel(for exercise: PendingRoutineExercise) -> String? {
        exercise.supersetId.flatMap { supersetLabels[$0] }
    }

    // MARK: - Editing

    mutating func append(
        exercise: Exercise,
        sets: [ExerciseSet],
        alternatives: [PendingAlternative],
        targetRepMin: Int?,
        targetRepMax: Int?
    ) {
        exercises.append(PendingRoutineExercise(
            exercise: exercise,
            sets: sets,
            order: exercises.count,
            alternatives: alternatives,
            targetRepMin: targetRepMin,
            targetRepMax: targetRepMax
        ))
    }

    mutating func update(
        id: UUID,
        sets: [ExerciseSet],
        alternatives: [PendingAlternative],
        targetRepMin: Int?,
        targetRepMax: Int?
    ) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        exercises[index].sets = sets
        exercises[index].alternatives = alternatives
        exercises[index].targetRepMin = targetRepMin
        exercises[index].targetRepMax = targetRepMax
    }

    /// Removes an exercise. A superset left with one member dissolves — the
    /// same lone-survivor rule as `RoutinesViewModel.removeExerciseFromSuperset`.
    mutating func delete(id: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        var remaining = exercises
        let removed = remaining.remove(at: index)
        if let supersetId = removed.supersetId {
            let survivors = remaining.indices.filter { remaining[$0].supersetId == supersetId }
            if survivors.count == 1 {
                remaining[survivors[0]].supersetId = nil
            }
        }
        exercises = renumbered(remaining)
    }

    /// Applies the offsets `List.onMove` reports over `units`. Whole units
    /// move, so a superset cannot be pulled apart or interleaved by a drag.
    mutating func moveUnits(fromOffsets source: IndexSet, toOffset destination: Int) {
        var moved = units
        moved.move(fromOffsets: source, toOffset: destination)
        exercises = renumbered(moved.flatMap(\.exercises))
    }

    // MARK: - Supersets

    /// Whether the seam below `id` can be linked: there is a next exercise, and
    /// the two are not already in the same superset.
    func canLink(after id: UUID) -> Bool {
        guard let index = exercises.firstIndex(where: { $0.id == id }),
              index + 1 < exercises.count else { return false }
        let upper = exercises[index].supersetId
        return upper == nil || upper != exercises[index + 1].supersetId
    }

    /// Joins the exercise `id` and the one below it: two standalone exercises
    /// become a new superset, a standalone one joins its neighbour's superset,
    /// and two adjacent supersets merge into the upper one.
    mutating func link(after id: UUID) {
        guard canLink(after: id),
              let index = exercises.firstIndex(where: { $0.id == id }) else { return }

        let upper = exercises[index].supersetId
        let lower = exercises[index + 1].supersetId
        let target = upper ?? lower ?? UUID()

        var linked = exercises
        linked[index].supersetId = target
        linked[index + 1].supersetId = target
        if let lower, lower != target {
            for i in linked.indices where linked[i].supersetId == lower {
                linked[i].supersetId = target
            }
        }
        exercises = linked
    }

    /// Breaks a superset at the seam below `id` — the draft counterpart of
    /// `RoutinesViewModel.splitSuperset(after:in:)`: members up to `id` keep
    /// the group, the rest form a new one, and a side left with a single
    /// exercise becomes standalone.
    mutating func unlink(after id: UUID) {
        guard let supersetId = exercise(withId: id)?.supersetId else { return }
        let memberIndices = exercises.indices.filter { exercises[$0].supersetId == supersetId }
        guard let seam = memberIndices.firstIndex(where: { exercises[$0].id == id }),
              seam < memberIndices.count - 1 else { return }

        let upper = Array(memberIndices[...seam])
        let lower = Array(memberIndices[(seam + 1)...])
        var split = exercises
        if upper.count == 1 { split[upper[0]].supersetId = nil }
        let lowerId: UUID? = lower.count == 1 ? nil : UUID()
        for i in lower { split[i].supersetId = lowerId }
        exercises = split
    }

    // MARK: - Derived state

    private func renumbered(_ list: [PendingRoutineExercise]) -> [PendingRoutineExercise] {
        var result = list
        for index in result.indices {
            result[index].order = index
        }
        return result
    }

    private mutating func rebuildDerivedState() {
        supersetLabels = SupersetLabelProvider.labels(for: exercises)

        var folded: [Unit] = []
        for exercise in exercises {
            if let supersetId = exercise.supersetId, folded.last?.supersetId == supersetId {
                folded[folded.count - 1].exercises.append(exercise)
            } else {
                folded.append(Unit(
                    id: exercise.supersetId ?? exercise.id,
                    supersetId: exercise.supersetId,
                    exercises: [exercise]
                ))
            }
        }
        units = folded
    }
}
