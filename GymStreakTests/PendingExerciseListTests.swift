//
//  PendingExerciseListTests.swift
//  GymStreakTests
//
//  The Create-Routine draft's superset rules: linking two standalone
//  exercises, extending a superset, merging two, and the group letters.
//

import Testing
import Foundation
@testable import GymStreak

@MainActor
struct PendingExerciseListTests {

    private func makeDraft(count: Int) -> PendingExerciseList {
        var draft = PendingExerciseList()
        for index in 0..<count {
            draft.append(
                exercise: Exercise(name: "Exercise \(index)"),
                sets: [ExerciseSet(reps: 8, weight: 50, restTime: 90, order: 0)],
                alternatives: [],
                targetRepMin: nil,
                targetRepMax: nil
            )
        }
        return draft
    }

    private func id(_ index: Int, in draft: PendingExerciseList) -> UUID {
        draft.exercises[index].id
    }

    @Test("Linking two standalone exercises creates a new superset")
    func linkCreatesSuperset() throws {
        var draft = makeDraft(count: 3)

        draft.link(after: id(0, in: draft))

        let supersetId = try #require(draft.exercises[0].supersetId)
        #expect(draft.exercises[1].supersetId == supersetId)
        #expect(draft.exercises[2].supersetId == nil)
        #expect(draft.supersetLabel(for: draft.exercises[0]) == "A")
        #expect(draft.supersetLabel(for: draft.exercises[2]) == nil)
    }

    @Test("A standalone exercise joins the neighbouring superset, above or below")
    func linkExtendsSuperset() throws {
        var draft = makeDraft(count: 4)
        draft.link(after: id(1, in: draft))
        let supersetId = try #require(draft.exercises[1].supersetId)

        draft.link(after: id(2, in: draft)) // superset above, standalone below
        draft.link(after: id(0, in: draft)) // standalone above, superset below

        #expect(draft.exercises.map(\.supersetId) == Array(repeating: supersetId, count: 4))
    }

    @Test("Linking two adjacent supersets merges them into one")
    func linkMergesSupersets() throws {
        var draft = makeDraft(count: 4)
        draft.link(after: id(0, in: draft))
        draft.link(after: id(2, in: draft))
        #expect(draft.exercises[0].supersetId != draft.exercises[2].supersetId)

        draft.link(after: id(1, in: draft))

        let supersetId = try #require(draft.exercises[0].supersetId)
        #expect(draft.exercises.allSatisfy { $0.supersetId == supersetId })
        #expect(Set(draft.supersetLabels.values) == ["A"])
    }

    @Test("The link control exists only between rows not already in one superset")
    func canLinkRules() {
        var draft = makeDraft(count: 3)
        #expect(draft.canLink(after: id(0, in: draft)))
        #expect(draft.canLink(after: id(1, in: draft)))
        #expect(!draft.canLink(after: id(2, in: draft))) // last row

        draft.link(after: id(0, in: draft))

        #expect(!draft.canLink(after: id(0, in: draft)))
        #expect(draft.canLink(after: id(1, in: draft)))
    }

    @Test("Two supersets are labelled A and B in routine order")
    func twoSupersetsGetAAndB() {
        var draft = makeDraft(count: 5)
        draft.link(after: id(0, in: draft))
        draft.link(after: id(3, in: draft))

        #expect(draft.exercises.map { draft.supersetLabel(for: $0) } == ["A", "A", nil, "B", "B"])
    }

    @Test("Deleting keeps order equal to position")
    func deleteRenumbers() {
        var draft = makeDraft(count: 3)
        draft.delete(id: id(0, in: draft))
        #expect(draft.exercises.map(\.order) == [0, 1])
    }

    // MARK: - Unlink

    @Test("Unlinking a two-member superset dissolves it")
    func unlinkDissolvesPair() {
        var draft = makeDraft(count: 3)
        draft.link(after: id(0, in: draft))

        draft.unlink(after: id(0, in: draft))

        #expect(draft.exercises.allSatisfy { $0.supersetId == nil })
        #expect(draft.supersetLabels.isEmpty)
    }

    @Test("Unlinking in the middle of a four-member superset makes two groups, relabelled A and B")
    func unlinkSplitsIntoTwoGroups() throws {
        var draft = makeDraft(count: 4)
        draft.link(after: id(0, in: draft))
        draft.link(after: id(1, in: draft))
        draft.link(after: id(2, in: draft))

        draft.unlink(after: id(1, in: draft))

        let upper = try #require(draft.exercises[0].supersetId)
        let lower = try #require(draft.exercises[2].supersetId)
        #expect(upper != lower)
        #expect(draft.exercises.map(\.supersetId) == [upper, upper, lower, lower])
        #expect(draft.exercises.map { draft.supersetLabel(for: $0) } == ["A", "A", "B", "B"])
    }

    @Test("Unlinking leaves a one-exercise side standalone")
    func unlinkLeavesLoneSideStandalone() throws {
        var draft = makeDraft(count: 3)
        draft.link(after: id(0, in: draft))
        draft.link(after: id(1, in: draft))

        draft.unlink(after: id(1, in: draft))

        let supersetId = try #require(draft.exercises[0].supersetId)
        #expect(draft.exercises.map(\.supersetId) == [supersetId, supersetId, nil])
    }

    @Test("Unlinking below the last member or a standalone exercise does nothing")
    func unlinkIgnoresInvalidSeams() throws {
        var draft = makeDraft(count: 3)
        draft.link(after: id(0, in: draft))
        let before = draft.exercises.map(\.supersetId)

        draft.unlink(after: id(1, in: draft))
        draft.unlink(after: id(2, in: draft))

        #expect(draft.exercises.map(\.supersetId) == before)
    }

    // MARK: - Delete

    @Test("Deleting one member of a pair leaves the survivor standalone")
    func deleteLoneSurvivorBecomesStandalone() {
        var draft = makeDraft(count: 3)
        draft.link(after: id(0, in: draft))

        draft.delete(id: id(0, in: draft))

        #expect(draft.exercises.allSatisfy { $0.supersetId == nil })
        #expect(draft.units.count == 2)
    }

    @Test("Deleting a member of a larger superset keeps the group")
    func deleteKeepsLargerGroup() throws {
        var draft = makeDraft(count: 3)
        draft.link(after: id(0, in: draft))
        draft.link(after: id(1, in: draft))

        draft.delete(id: id(1, in: draft))

        let supersetId = try #require(draft.exercises[0].supersetId)
        #expect(draft.exercises.map(\.supersetId) == [supersetId, supersetId])
    }

    // MARK: - Reorder

    @Test("A superset is one unit and moves as a block")
    func moveUnitsMovesSupersetAsBlock() throws {
        var draft = makeDraft(count: 4)
        draft.link(after: id(0, in: draft))
        let supersetId = try #require(draft.exercises[0].supersetId)
        #expect(draft.units.map(\.exercises.count) == [2, 1, 1])

        // Superset block to the end.
        draft.moveUnits(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        #expect(draft.exercises.map(\.exercise.name) == ["Exercise 2", "Exercise 3", "Exercise 0", "Exercise 1"])
        #expect(draft.exercises.map(\.supersetId) == [nil, nil, supersetId, supersetId])
        #expect(draft.exercises.map(\.order) == [0, 1, 2, 3])
    }
}
