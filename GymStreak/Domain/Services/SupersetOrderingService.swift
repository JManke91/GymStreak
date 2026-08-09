//
//  SupersetOrderingService.swift
//  GymStreak
//
//  The superset contiguity invariant: a superset's members always occupy an
//  uninterrupted run of `order` slots in the routine, anchored at the earliest
//  member's slot, and `supersetOrder` mirrors that run. Superset creation used
//  to only stamp `supersetId`/`supersetOrder` and never touch positions, so
//  members could sit scattered across the routine with unrelated exercises in
//  between — which no connecting line can span.
//
//  Pure logic over model arrays: it renumbers `order`/`supersetOrder` on the
//  passed objects and never saves. `RoutinesViewModel` runs it after every
//  edit that can disturb positions and persists once via `updateRoutine`.
//

import Foundation

enum SupersetOrderingService {

    /// One draggable unit of routine order: a standalone exercise, or a whole
    /// superset that moves as a block. Sorting works on units rather than on
    /// single exercises — that is what makes a drop between two members of a
    /// superset impossible, and what keeps the contiguity invariant safe from
    /// dragging. Pulling a single member out is deliberately not a gesture;
    /// unlinking is an explicit action.
    struct OrderingUnit: Identifiable {
        /// The superset's id for a group, the exercise's id for a standalone one.
        let id: UUID
        let supersetId: UUID?
        let exercises: [RoutineExercise]
    }

    /// The routine's exercises in contiguous-superset order: each superset's
    /// members emitted as one uninterrupted block at the position of its
    /// earliest member, everything else keeping its relative order.
    ///
    /// Member sequence inside a block follows routine `order` too — position in
    /// the routine is the single source of truth for sequence, so a member
    /// dragged within its block reorders the superset instead of snapping back.
    static func contiguousOrder(for exercises: [RoutineExercise]) -> [RoutineExercise] {
        // Deterministic even if stored `order` values collide (legacy data).
        let sorted = exercises.sorted {
            $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order
        }

        var membersBySuperset: [UUID: [RoutineExercise]] = [:]
        for exercise in sorted {
            guard let supersetId = exercise.supersetId else { continue }
            membersBySuperset[supersetId, default: []].append(exercise)
        }

        var emittedSupersetIds: Set<UUID> = []
        var result: [RoutineExercise] = []
        result.reserveCapacity(sorted.count)

        for exercise in sorted {
            guard let supersetId = exercise.supersetId else {
                result.append(exercise)
                continue
            }
            // The first member reached anchors the whole block.
            guard emittedSupersetIds.insert(supersetId).inserted else { continue }
            result.append(contentsOf: membersBySuperset[supersetId] ?? [])
        }

        return result
    }

    /// The routine as draggable units, in contiguous-superset order. Members of
    /// a superset arrive as one unit even if the stored data still has them
    /// scattered, because `contiguousOrder(for:)` gathers them first.
    static func units(for exercises: [RoutineExercise]) -> [OrderingUnit] {
        var units: [OrderingUnit] = []

        for exercise in contiguousOrder(for: exercises) {
            guard let supersetId = exercise.supersetId else {
                units.append(OrderingUnit(id: exercise.id, supersetId: nil, exercises: [exercise]))
                continue
            }
            if let last = units.last, last.supersetId == supersetId {
                units[units.count - 1] = OrderingUnit(
                    id: last.id,
                    supersetId: supersetId,
                    exercises: last.exercises + [exercise]
                )
            } else {
                units.append(OrderingUnit(id: supersetId, supersetId: supersetId, exercises: [exercise]))
            }
        }

        return units
    }

    /// Applies a unit-level move — the offsets `List.onMove` reports over
    /// `units(for:)` — and renumbers the routine. Whole units move, so every
    /// superset comes out of any drag as one contiguous block with its internal
    /// order intact.
    static func moveUnits(from source: IndexSet, to destination: Int, in routine: Routine) {
        var moved = units(for: routine.routineExercisesList)
        moved.move(fromOffsets: source, toOffset: destination)

        for (index, exercise) in moved.flatMap(\.exercises).enumerated() {
            exercise.order = index
        }
        normalizeOrdering(in: routine)
    }

    /// Restores the invariant in place: `order` becomes `0..<count` in
    /// contiguous-superset sequence and each superset's `supersetOrder` becomes
    /// `0..<memberCount` along it. Returns whether anything actually moved, so
    /// callers can skip a redundant save.
    @discardableResult
    static func normalizeOrdering(in routine: Routine) -> Bool {
        let ordered = contiguousOrder(for: routine.routineExercisesList)
        var didChange = false

        var positionInSuperset: [UUID: Int] = [:]
        for (index, exercise) in ordered.enumerated() {
            if exercise.order != index {
                exercise.order = index
                didChange = true
            }
            guard let supersetId = exercise.supersetId else { continue }
            let position = positionInSuperset[supersetId, default: 0]
            positionInSuperset[supersetId] = position + 1
            if exercise.supersetOrder != position {
                exercise.supersetOrder = position
                didChange = true
            }
        }

        return didChange
    }
}
