//
//  SupersetEditorTests.swift
//  GymStreakTests
//
//  SupersetEditor is pure set-algebra over in-memory `@Model` graphs — no
//  ModelContext/persistence needed, just plain object construction.
//

import Testing
import Foundation
@testable import GymStreak

@MainActor
struct SupersetEditorTests {

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

    @Test
    func canApplyEditRequiresTwoForCreating() {
        #expect(SupersetEditor.canApplyEdit(.creating, selection: []) == false)
        #expect(SupersetEditor.canApplyEdit(.creating, selection: [UUID()]) == false)
        #expect(SupersetEditor.canApplyEdit(.creating, selection: [UUID(), UUID()]) == true)
    }

    @Test
    func canApplyEditAlwaysAllowsEditing() {
        #expect(SupersetEditor.canApplyEdit(.editing(UUID()), selection: []) == true)
        #expect(SupersetEditor.canApplyEdit(.editing(UUID()), selection: [UUID()]) == true)
    }

    @Test
    func canApplyEditDisallowsNoMode() {
        #expect(SupersetEditor.canApplyEdit(nil, selection: [UUID(), UUID()]) == false)
    }

    @Test
    func decideEditCreatingWithTwoOrMoreReturnsSortedCreate() {
        let (routine, exercises) = makeRoutine(exerciseCount: 3)
        let selection = Set(exercises.map(\.id))

        let decision = SupersetEditor.decideEdit(.creating, selection: selection, in: routine)

        guard case .create(let selected) = decision else {
            Issue.record("Expected .create, got \(decision)")
            return
        }
        #expect(selected.map(\.order) == [0, 1, 2])
    }

    @Test
    func decideEditCreatingWithFewerThanTwoReturnsNone() {
        let (routine, exercises) = makeRoutine(exerciseCount: 3)
        let decision = SupersetEditor.decideEdit(.creating, selection: [exercises[0].id], in: routine)

        guard case .none = decision else {
            Issue.record("Expected .none, got \(decision)")
            return
        }
    }

    @Test
    func decideEditEditingWithFewerThanTwoDissolves() {
        let (routine, exercises) = makeRoutine(exerciseCount: 3)
        let supersetId = UUID()
        for exercise in exercises {
            exercise.supersetId = supersetId
        }

        let decision = SupersetEditor.decideEdit(.editing(supersetId), selection: [exercises[0].id], in: routine)

        guard case .dissolve(let dissolvedId) = decision else {
            Issue.record("Expected .dissolve, got \(decision)")
            return
        }
        #expect(dissolvedId == supersetId)
    }

    @Test
    func decideEditEditingDiffsMembershipChanges() {
        let (routine, exercises) = makeRoutine(exerciseCount: 4)
        let supersetId = UUID()
        // Exercises 0 and 1 currently form the superset; exercise 2 is not a member.
        exercises[0].supersetId = supersetId
        exercises[1].supersetId = supersetId

        // New selection: drop exercise 1, add exercise 2. Keep exercise 0.
        let selection: Set<UUID> = [exercises[0].id, exercises[2].id]

        let decision = SupersetEditor.decideEdit(.editing(supersetId), selection: selection, in: routine)

        guard case .modify(let modifiedId, let toAdd, let toRemove) = decision else {
            Issue.record("Expected .modify, got \(decision)")
            return
        }
        #expect(modifiedId == supersetId)
        #expect(toAdd == [exercises[2].id])
        #expect(toRemove == [exercises[1].id])
    }
}
