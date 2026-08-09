//
//  SupersetOrderingServiceTests.swift
//  GymStreakTests
//
//  The superset contiguity invariant. Like SupersetEditorTests these run on
//  in-memory `@Model` graphs — the service is pure logic over model arrays and
//  never touches a ModelContext.
//

import Testing
import Foundation
@testable import GymStreak

@MainActor
struct SupersetOrderingServiceTests {

    private func makeRoutine(exerciseCount: Int) -> (routine: Routine, exercises: [RoutineExercise]) {
        let routine = Routine(name: "Push Day")
        let exercises = (0..<exerciseCount).map { index -> RoutineExercise in
            let exercise = RoutineExercise(exercise: Exercise(name: "Exercise \(index)"), order: index)
            exercise.routine = routine
            return exercise
        }
        routine.routineExercises = exercises
        return (routine, exercises)
    }

    /// Names in routine order — readable expectations for the reordering cases.
    private func names(of routine: Routine) -> [String] {
        SupersetOrderingService.contiguousOrder(for: routine.routineExercisesList)
            .compactMap { $0.exercise?.name }
    }

    @Test
    func scatteredMembersGatherAtTheEarliestMemberSlot() {
        let (routine, exercises) = makeRoutine(exerciseCount: 5)
        let supersetId = UUID()
        exercises[0].supersetId = supersetId
        exercises[0].supersetOrder = 0
        exercises[4].supersetId = supersetId
        exercises[4].supersetOrder = 1

        #expect(SupersetOrderingService.normalizeOrdering(in: routine))

        #expect(names(of: routine) == [
            "Exercise 0", "Exercise 4", "Exercise 1", "Exercise 2", "Exercise 3"
        ])
        #expect(exercises[0].order == 0)
        #expect(exercises[4].order == 1)
        // Bystanders keep their relative order among themselves.
        #expect(exercises[1].order == 2)
        #expect(exercises[2].order == 3)
        #expect(exercises[3].order == 4)
    }

    @Test
    func supersetOrderIsRenumberedAlongTheBlock() {
        let (routine, exercises) = makeRoutine(exerciseCount: 4)
        let supersetId = UUID()
        // Deliberately gappy/duplicated stored values.
        exercises[1].supersetId = supersetId
        exercises[1].supersetOrder = 7
        exercises[3].supersetId = supersetId
        exercises[3].supersetOrder = 7

        SupersetOrderingService.normalizeOrdering(in: routine)

        #expect(exercises[1].supersetOrder == 0)
        #expect(exercises[3].supersetOrder == 1)
        #expect(exercises[3].order == exercises[1].order + 1)
    }

    @Test
    func twoSupersetsFormSeparateBlocksWithoutInterleaving() {
        let (routine, exercises) = makeRoutine(exerciseCount: 6)
        let first = UUID()
        let second = UUID()
        exercises[0].supersetId = first
        exercises[3].supersetId = first
        exercises[1].supersetId = second
        exercises[5].supersetId = second

        SupersetOrderingService.normalizeOrdering(in: routine)

        #expect(names(of: routine) == [
            "Exercise 0", "Exercise 3",   // superset A block
            "Exercise 1", "Exercise 5",   // superset B block
            "Exercise 2", "Exercise 4"
        ])
    }

    @Test
    func alreadyContiguousRoutineReportsNoChange() {
        let (routine, exercises) = makeRoutine(exerciseCount: 4)
        let supersetId = UUID()
        exercises[1].supersetId = supersetId
        exercises[1].supersetOrder = 0
        exercises[2].supersetId = supersetId
        exercises[2].supersetOrder = 1

        #expect(SupersetOrderingService.normalizeOrdering(in: routine) == false)
    }

    @Test
    func normalizationIsIdempotent() {
        let (routine, exercises) = makeRoutine(exerciseCount: 5)
        let supersetId = UUID()
        exercises[1].supersetId = supersetId
        exercises[4].supersetId = supersetId

        SupersetOrderingService.normalizeOrdering(in: routine)
        let afterFirstPass = names(of: routine)

        #expect(SupersetOrderingService.normalizeOrdering(in: routine) == false)
        #expect(names(of: routine) == afterFirstPass)
    }

    @Test
    func ordersStayGapFreeAndUniqueAfterAMemberLeaves() {
        let (routine, exercises) = makeRoutine(exerciseCount: 5)
        let supersetId = UUID()
        exercises[0].supersetId = supersetId
        exercises[2].supersetId = supersetId
        exercises[4].supersetId = supersetId
        SupersetOrderingService.normalizeOrdering(in: routine)

        // Exercise 2 leaves the superset; it stays where it sits.
        exercises[2].supersetId = nil
        exercises[2].supersetOrder = 0
        SupersetOrderingService.normalizeOrdering(in: routine)

        let orders = routine.routineExercisesList.map(\.order).sorted()
        #expect(orders == [0, 1, 2, 3, 4])
        #expect(names(of: routine) == [
            "Exercise 0", "Exercise 4", "Exercise 2", "Exercise 1", "Exercise 3"
        ])
        #expect(exercises[0].supersetOrder == 0)
        #expect(exercises[4].supersetOrder == 1)
    }

    @Test
    func dissolvingASupersetLeavesTheBlockOrderIntact() {
        let (routine, exercises) = makeRoutine(exerciseCount: 4)
        let supersetId = UUID()
        exercises[0].supersetId = supersetId
        exercises[3].supersetId = supersetId
        SupersetOrderingService.normalizeOrdering(in: routine)

        for exercise in exercises where exercise.supersetId == supersetId {
            exercise.supersetId = nil
            exercise.supersetOrder = 0
        }
        #expect(SupersetOrderingService.normalizeOrdering(in: routine) == false)
        #expect(names(of: routine) == [
            "Exercise 0", "Exercise 3", "Exercise 1", "Exercise 2"
        ])
    }

    @Test
    func memberSequenceFollowsRoutinePositionWhenADistantExerciseJoins() {
        let (routine, exercises) = makeRoutine(exerciseCount: 5)
        let supersetId = UUID()
        exercises[2].supersetId = supersetId
        exercises[3].supersetId = supersetId
        SupersetOrderingService.normalizeOrdering(in: routine)

        // Exercise 0 (earlier in the routine) joins the group: the block moves
        // up to its slot and it becomes the group's first member.
        exercises[0].supersetId = supersetId
        exercises[0].supersetOrder = 99
        SupersetOrderingService.normalizeOrdering(in: routine)

        #expect(names(of: routine) == [
            "Exercise 0", "Exercise 2", "Exercise 3", "Exercise 1", "Exercise 4"
        ])
        #expect(exercises[0].supersetOrder == 0)
        #expect(exercises[2].supersetOrder == 1)
        #expect(exercises[3].supersetOrder == 2)
    }

    @Test
    func emptyRoutineIsUnchanged() {
        let routine = Routine(name: "Empty")
        routine.routineExercises = []

        #expect(SupersetOrderingService.normalizeOrdering(in: routine) == false)
    }

    // MARK: - Sorting units (drag can't split a superset)

    /// The `order` slots a superset's members occupy, sorted.
    private func positions(ofSuperset supersetId: UUID, in routine: Routine) -> [Int] {
        routine.routineExercisesList
            .filter { $0.supersetId == supersetId }
            .map(\.order)
            .sorted()
    }

    private func isContiguous(_ positions: [Int]) -> Bool {
        guard let first = positions.first else { return true }
        return positions == Array(first..<(first + positions.count))
    }

    @Test
    func aSupersetBecomesOneDraggableUnit() {
        let (routine, exercises) = makeRoutine(exerciseCount: 5)
        let supersetId = UUID()
        exercises[0].supersetId = supersetId
        exercises[4].supersetId = supersetId

        let units = SupersetOrderingService.units(for: routine.routineExercisesList)

        #expect(units.count == 4)
        #expect(units[0].id == supersetId)
        #expect(units[0].exercises.compactMap { $0.exercise?.name } == ["Exercise 0", "Exercise 4"])
        #expect(units.dropFirst().allSatisfy { $0.supersetId == nil && $0.exercises.count == 1 })
    }

    @Test
    func movingASupersetMovesEveryMemberTogether() {
        let (routine, exercises) = makeRoutine(exerciseCount: 4)
        let supersetId = UUID()
        exercises[0].supersetId = supersetId
        exercises[1].supersetId = supersetId
        SupersetOrderingService.normalizeOrdering(in: routine)

        // Units are [AB, 2, 3] — drag the superset to the end.
        SupersetOrderingService.moveUnits(from: IndexSet(integer: 0), to: 3, in: routine)

        #expect(names(of: routine) == ["Exercise 2", "Exercise 3", "Exercise 0", "Exercise 1"])
        #expect(positions(ofSuperset: supersetId, in: routine) == [2, 3])
        #expect(exercises[0].supersetOrder == 0)
        #expect(exercises[1].supersetOrder == 1)
    }

    @Test
    func aStandaloneExerciseLandsBesideASupersetNeverInsideIt() {
        let (routine, exercises) = makeRoutine(exerciseCount: 4)
        let supersetId = UUID()
        exercises[0].supersetId = supersetId
        exercises[1].supersetId = supersetId
        SupersetOrderingService.normalizeOrdering(in: routine)

        // Units are [AB, 2, 3] — drop Exercise 3 onto the slot right after the
        // group. The exercise-level offset it visually covers sits between the
        // members; the unit-level move resolves it to after the whole block.
        SupersetOrderingService.moveUnits(from: IndexSet(integer: 2), to: 1, in: routine)

        #expect(names(of: routine) == ["Exercise 0", "Exercise 1", "Exercise 3", "Exercise 2"])
        #expect(positions(ofSuperset: supersetId, in: routine) == [0, 1])

        // ...and onto the slot before it.
        SupersetOrderingService.moveUnits(from: IndexSet(integer: 1), to: 0, in: routine)

        #expect(names(of: routine) == ["Exercise 3", "Exercise 0", "Exercise 1", "Exercise 2"])
        #expect(positions(ofSuperset: supersetId, in: routine) == [1, 2])
    }

    @Test
    func aSupersetCanReachTheVeryTopAndTheVeryBottom() {
        let (routine, exercises) = makeRoutine(exerciseCount: 4)
        let supersetId = UUID()
        exercises[1].supersetId = supersetId
        exercises[2].supersetId = supersetId
        SupersetOrderingService.normalizeOrdering(in: routine)

        // Units are [0, BC, 3] — to the top.
        SupersetOrderingService.moveUnits(from: IndexSet(integer: 1), to: 0, in: routine)
        #expect(names(of: routine) == ["Exercise 1", "Exercise 2", "Exercise 0", "Exercise 3"])
        #expect(positions(ofSuperset: supersetId, in: routine) == [0, 1])

        // Units are now [BC, 0, 3] — to the bottom.
        SupersetOrderingService.moveUnits(from: IndexSet(integer: 0), to: 3, in: routine)
        #expect(names(of: routine) == ["Exercise 0", "Exercise 3", "Exercise 1", "Exercise 2"])
        #expect(positions(ofSuperset: supersetId, in: routine) == [2, 3])
    }

    @Test
    func twoSupersetsSwapWithoutEitherBreaking() {
        let (routine, exercises) = makeRoutine(exerciseCount: 4)
        let first = UUID()
        let second = UUID()
        exercises[0].supersetId = first
        exercises[1].supersetId = first
        exercises[2].supersetId = second
        exercises[3].supersetId = second
        SupersetOrderingService.normalizeOrdering(in: routine)

        // Units are [A, B] — swap them.
        SupersetOrderingService.moveUnits(from: IndexSet(integer: 1), to: 0, in: routine)

        #expect(names(of: routine) == ["Exercise 2", "Exercise 3", "Exercise 0", "Exercise 1"])
        #expect(positions(ofSuperset: second, in: routine) == [0, 1])
        #expect(positions(ofSuperset: first, in: routine) == [2, 3])
    }

    @Test
    func everySupersetStaysContiguousAfterASequenceOfMoves() {
        let (routine, exercises) = makeRoutine(exerciseCount: 7)
        let first = UUID()
        let second = UUID()
        exercises[0].supersetId = first
        exercises[1].supersetId = first
        exercises[2].supersetId = first
        exercises[4].supersetId = second
        exercises[5].supersetId = second
        SupersetOrderingService.normalizeOrdering(in: routine)

        // Units: [A(3), 3, B(2), 6] — walk them through a few drags.
        for (source, destination) in [(0, 4), (3, 0), (1, 3), (2, 1)] {
            SupersetOrderingService.moveUnits(from: IndexSet(integer: source), to: destination, in: routine)

            #expect(isContiguous(positions(ofSuperset: first, in: routine)))
            #expect(isContiguous(positions(ofSuperset: second, in: routine)))
            #expect(routine.routineExercisesList.map(\.order).sorted() == Array(0..<7))
        }

        // Internal order survives every block move.
        #expect(exercises[0].order + 1 == exercises[1].order)
        #expect(exercises[1].order + 1 == exercises[2].order)
        #expect(exercises[4].order + 1 == exercises[5].order)
    }
}
