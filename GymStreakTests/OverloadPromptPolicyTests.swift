//
//  OverloadPromptPolicyTests.swift
//  GymStreakTests
//
//  Covers *reachability* of the mid-workout progressive-overload prompt — the
//  half of the feature that was dead UI while the banner lived inside the
//  expanded exercise card. `ProgressiveOverloadServiceTests` covers the
//  qualification math this policy consumes.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
struct OverloadPromptPolicyTests {

    private let first = UUID()
    private let second = UUID()
    private let third = UUID()

    private func candidate(_ id: UUID, name: String = "Bench Press", isAssistance: Bool = false) -> OverloadPromptCandidate {
        OverloadPromptCandidate(exerciseId: id, exerciseName: name, targetRepMax: 12, isAssistance: isAssistance)
    }

    private func applied(_ name: String = "Bench Press") -> AppliedOverload {
        AppliedOverload(exerciseName: name, weight: 62.5, reps: 8, setCount: 3)
    }

    private func prompt(
        order: [UUID],
        candidates: [OverloadPromptCandidate] = [],
        dismissed: Set<UUID> = [],
        applied: [UUID: AppliedOverload] = [:]
    ) -> OverloadPrompt? {
        OverloadPromptPolicy.prompt(
            orderedExerciseIds: order,
            candidates: Dictionary(uniqueKeysWithValues: candidates.map { ($0.exerciseId, $0) }),
            dismissed: dismissed,
            applied: applied
        )
    }

    // MARK: - The bug

    /// The regression this policy exists for: completing the last set collapses
    /// the exercise's card and hands the screen to the next exercise, and the
    /// prompt must survive that.
    @Test
    func qualifyingExerciseGetsPromptEvenWhileItsCardIsCollapsed() {
        // `second` is the exercise the workout advanced to; `first` is the one
        // that just qualified and is now a collapsed row.
        let result = prompt(order: [first, second], candidates: [candidate(first)])
        #expect(result == .suggestion(candidate(first)))
    }

    /// The last exercise of the workout: `findNextIncompleteSet()` returns nil
    /// there, so the open card falls back to the *first* exercise.
    @Test
    func lastExerciseInWorkoutStillGetsPrompt() {
        let result = prompt(order: [first, second, third], candidates: [candidate(third, name: "Calf Raise")])
        #expect(result == .suggestion(candidate(third, name: "Calf Raise")))
    }

    @Test
    func noCandidatesYieldNoPrompt() {
        #expect(prompt(order: [first, second]) == nil)
    }

    // MARK: - Dismissal

    @Test
    func dismissedExerciseIsSuppressed() {
        #expect(prompt(order: [first], candidates: [candidate(first)], dismissed: [first]) == nil)
    }

    @Test
    func dismissingOneExerciseSurfacesTheNextCandidate() {
        let result = prompt(
            order: [first, second],
            candidates: [candidate(first), candidate(second, name: "Row")],
            dismissed: [first]
        )
        #expect(result == .suggestion(candidate(second, name: "Row")))
    }

    // MARK: - Applied confirmation

    /// Applying replaces the suggestion with the confirmation. The applied
    /// exercise is deliberately still a candidate — `overloadAlreadyApplied`
    /// short-circuits the qualification math to `true` — so this also pins the
    /// order in which the two are consulted.
    @Test
    func appliedExerciseShowsConfirmationInsteadOfSuggestion() {
        let result = prompt(
            order: [first],
            candidates: [candidate(first)],
            dismissed: [first],
            applied: [first: applied()]
        )
        #expect(result == .applied(exerciseId: first, applied()))
    }

    /// The same ordering, without the dismissal the apply records — the
    /// confirmation must not depend on it.
    @Test
    func appliedBeatsAStillQualifyingSuggestion() {
        let result = prompt(order: [first], candidates: [candidate(first)], applied: [first: applied()])
        #expect(result == .applied(exerciseId: first, applied()))
    }

    /// Dismissing the confirmation must not resurrect the suggestion — the
    /// completion screen is the independent second chance.
    @Test
    func dismissingConfirmationBringsNothingBack() {
        #expect(prompt(order: [first], candidates: [candidate(first)], dismissed: [first]) == nil)
    }

    // MARK: - Invalidation

    /// Un-completing a set or lowering reps takes the exercise out of
    /// `candidates` on the next pass, which is the whole invalidation story.
    @Test
    func exerciseThatStoppedQualifyingLosesItsPrompt() {
        #expect(prompt(order: [first, second], candidates: []) == nil)
    }

    /// A removed or swapped-away exercise leaves the order, and takes both a
    /// pending suggestion and a standing confirmation with it.
    @Test
    func removedExerciseDropsSuggestionAndConfirmation() {
        #expect(prompt(order: [second], candidates: [candidate(first)]) == nil)
        #expect(prompt(order: [second], applied: [first: applied()]) == nil)
    }

    // MARK: - Ordering

    @Test
    func twoSimultaneousCandidatesAreSurfacedInWorkoutOrder() {
        let both = [candidate(first, name: "Squat"), candidate(second, name: "Leg Press")]

        let firstPass = prompt(order: [first, second], candidates: both)
        #expect(firstPass == .suggestion(candidate(first, name: "Squat")))

        // …and only after the first is resolved does the second appear.
        let secondPass = prompt(order: [first, second], candidates: both, dismissed: [first])
        #expect(secondPass == .suggestion(candidate(second, name: "Leg Press")))
    }

    @Test
    func onlyOnePromptIsEverReturned() {
        let result = prompt(
            order: [first, second],
            candidates: [candidate(second, name: "Row")],
            applied: [first: applied("Squat")]
        )
        #expect(result == .applied(exerciseId: first, applied("Squat")))
    }

    @Test
    func assistanceExerciseKeepsItsWordingFlag() {
        let result = prompt(order: [first], candidates: [candidate(first, name: "Assisted Pull-up", isAssistance: true)])
        #expect(result?.exerciseName == "Assisted Pull-up")
        if case .suggestion(let candidate) = result {
            #expect(candidate.isAssistance)
        } else {
            Issue.record("expected a suggestion")
        }
    }
}
