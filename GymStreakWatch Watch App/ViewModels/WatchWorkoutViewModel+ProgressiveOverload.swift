//
//  WatchWorkoutViewModel+ProgressiveOverload.swift
//  GymStreakWatch Watch App
//
//  Mid-workout progressive overload (ticket 04): the presentation state that
//  drives the suggestion capsule, increment picker, and confirmation, plus
//  qualification and template-target resolution.
//
//  The apply path itself lives in `+ProgressiveOverloadApply.swift`. The UI
//  supplies only intent — a slot id and an increment — and target resolution,
//  math, durable persistence, sequencing, transport, and retry all stay behind
//  `applyProgressiveOverload(slotID:increment:)`.
//

import Foundation
import WatchKit

/// The single mid-workout overload surface. One value, not competing booleans,
/// so the capsule, picker, and confirmation can never be on screen together.
///
/// Every case carries the stable slot UUID rather than an array index or a
/// model copy, so removing or swapping a preceding exercise can never make the
/// surface point at the wrong exercise.
enum WatchOverloadPresentation: Equatable {
    case none
    case suggestion(slotID: UUID)
    case picker(slotID: UUID)
    case applying(slotID: UUID)
    case confirmation(slotID: UUID, newWeight: Double, targetRepMin: Int)

    var slotID: UUID? {
        switch self {
        case .none: nil
        case .suggestion(let id), .picker(let id), .applying(let id): id
        case .confirmation(let id, _, _): id
        }
    }

    /// While any overload surface is up, set input stays suspended and the rest
    /// overlay is minimized.
    var isActive: Bool { self != .none }

}

/// Everything the overload sheet needs to draw, resolved ONCE when a step is
/// entered.
///
/// The views used to reach back into the view model for the exercise, its
/// template scheme, and its load behavior. That is a lookup chain — routine
/// list → slot → alternatives — running inside `body`, on a broad
/// `ObservableObject` that also publishes heart rate and elapsed time, so it
/// re-ran on every sensor tick while the sheet was open.
struct WatchOverloadDisplay: Equatable {
    let slotID: UUID
    let exerciseName: String
    /// nil when the target has no rep-range goal (it then cannot qualify).
    let targetRepMax: Int?
    /// First template set's weight — what the increase is previewed against.
    let templateWeight: Double
    let isAssistance: Bool
}

extension WatchWorkoutViewModel {

    // MARK: - Qualification

    /// Whether a target is currently eligible for a suggestion.
    ///
    /// Deliberately re-derived from live state every time rather than cached:
    /// undoing a set, lowering reps, swapping the target, or removing the slot
    /// must all invalidate the suggestion, and this is the one place that
    /// decides it. Newly added Watch exercises have no rep-range goal and
    /// therefore cannot qualify until they are configured on iPhone.
    func qualifiesForProgressiveOverload(slotID: UUID) -> Bool {
        guard !isEnding, !isWorkoutFrozen else { return false }
        guard appliedOverloadSlots[slotID] == nil else { return false }
        guard let exercise = exercises.first(where: { $0.id == slotID }) else { return false }
        guard ProgressiveOverloadService.workoutQualifiesForIncrease(
            sets: exercise.sets.map {
                ProgressiveOverloadService.SetProgress(reps: $0.actualReps, isCompleted: $0.isCompleted)
            },
            targetRepMax: exercise.targetRepMax
        ) else { return false }
        // A counterweight-assistance exercise already at zero assistance cannot
        // progress further: the clamp would make every proposed value equal the
        // expected one, so applying would stage a no-op transaction and still
        // announce "Increased to 0 kg".
        return !isAlreadyAtMinimumAssistance(exercise)
    }

    private func isAlreadyAtMinimumAssistance(_ exercise: ActiveWorkoutExercise) -> Bool {
        let behavior = ExerciseLoadBehavior.from(raw: exercise.loadBehaviorRaw)
        guard behavior.isCounterweightAssistance,
              let routineID = currentRoutine?.id,
              let target = resolveOverloadTemplateTarget(for: exercise, routineID: routineID)
        else { return false }
        // The smallest offered step still leaves every set unchanged.
        let smallest = ProgressiveOverloadIncrement.options.min() ?? ProgressiveOverloadIncrement.default
        return target.sets.allSatisfy { set in
            ProgressiveOverloadService.increasedWeight(
                set.weight, increment: smallest, loadBehavior: behavior
            ) == set.weight
        }
    }

    /// Opens the suggestion for a slot unless it was already applied or the user
    /// dismissed it with "Later" during this workout. Called from the serialized
    /// set-completion mutation, before navigation or auto-advance can run.
    func presentOverloadSuggestionIfQualified(slotID: UUID) {
        guard overloadPresentation == .none else { return }
        guard !deferredOverloadSlotIDs.contains(slotID) else { return }
        guard qualifiesForProgressiveOverload(slotID: slotID) else { return }
        setOverloadPresentation(.suggestion(slotID: slotID))
    }

    /// Re-checks the active surface against live state and dismisses it if the
    /// target stopped qualifying (set uncompleted, reps lowered, slot removed or
    /// swapped, terminal transition begun). Confirmation is exempt — it reports
    /// something that already happened durably.
    func revalidateOverloadPresentation() {
        guard let slotID = overloadPresentation.slotID else { return }
        if case .confirmation = overloadPresentation { return }
        if case .applying = overloadPresentation { return }
        guard qualifiesForProgressiveOverload(slotID: slotID) else {
            setOverloadPresentation(.none)
            // The surface was holding back a finish condition that may still
            // hold (e.g. the slot was removed while every other set is done).
            resumeAutoFinishAfterOverloadFlow()
            return
        }
    }

    // MARK: - Presentation transitions

    /// The one place the surface changes, so the coupled side effects — input
    /// suspension, the resolved display data, and the rest overlay — can never
    /// drift apart from it.
    func setOverloadPresentation(_ presentation: WatchOverloadPresentation) {
        overloadPresentation = presentation
        // Reuse the EXISTING suspension flag (ticket 06) rather than adding a
        // second gate: the Action Button and Double Tap must not complete
        // another set while this flow is up.
        isWorkoutInputSuspended = presentation.isActive
        // Resolve once per step instead of per render (see WatchOverloadDisplay).
        overloadDisplay = presentation.slotID.flatMap(makeOverloadDisplay(slotID:))
        if presentation.isActive {
            // Keep a running rest timer running; only its full-screen overlay
            // steps aside, so it can't cover the sheet's own dismissal chrome.
            if isResting { isRestTimerMinimized = true }
        } else {
            // The alert lives inside the sheet, so a message left set as the
            // flow closes would have no view attached — and would then fire on
            // the NEXT suggestion the moment it appeared.
            overloadErrorMessage = nil
        }
    }

    private func makeOverloadDisplay(slotID: UUID) -> WatchOverloadDisplay? {
        guard let exercise = exercises.first(where: { $0.id == slotID }),
              let routineID = currentRoutine?.id,
              let target = resolveOverloadTemplateTarget(for: exercise, routineID: routineID),
              let firstSet = target.sets.first else { return nil }
        return WatchOverloadDisplay(
            slotID: slotID,
            exerciseName: exercise.name,
            targetRepMax: exercise.targetRepMax,
            templateWeight: firstSet.weight,
            isAssistance: ExerciseLoadBehavior
                .from(raw: exercise.loadBehaviorRaw).isCounterweightAssistance
        )
    }

    func showOverloadIncrementPicker(slotID: UUID) {
        guard qualifiesForProgressiveOverload(slotID: slotID) else {
            setOverloadPresentation(.none)
            return
        }
        setOverloadPresentation(.picker(slotID: slotID))
    }

    /// "Later": dismisses this mid-workout surface for one slot only. It does
    /// NOT mark overload applied, so the post-workout summary can still offer
    /// it, and other qualifying exercises are untouched.
    func deferProgressiveOverload(slotID: UUID) {
        deferredOverloadSlotIDs.insert(slotID)
        setOverloadPresentation(.none)
        persistActiveCheckpoint()
        resumeAutoFinishAfterOverloadFlow()
    }

    /// Interactive dismissal of the sheet (swipe or crown press), which is not
    /// the same thing as tapping "Later": it can land on any step. The mapping
    /// keeps each step's meaning intact — deferring only where deferring is
    /// what the user meant.
    func deferProgressiveOverloadIfPresenting(slotID: UUID) {
        switch overloadPresentation {
        case .suggestion, .picker:
            deferProgressiveOverload(slotID: slotID)
        case .confirmation:
            // Already applied and durable; dismissing just acknowledges it.
            dismissOverloadConfirmation()
        case .applying:
            // A write is in flight — its completion owns the next state.
            break
        case .none:
            break
        }
    }

    /// Dismisses the confirmation and lets a pending auto-finish resume.
    func dismissOverloadConfirmation() {
        guard case .confirmation = overloadPresentation else { return }
        setOverloadPresentation(.none)
        resumeAutoFinishAfterOverloadFlow()
    }

    // MARK: - Template target resolution

    /// The template scheme an overload writes to: the performed alternative's
    /// own sets when the exercise was swapped, otherwise the primary slot's.
    ///
    /// Resolved against the effective routine (authoritative base + pending
    /// optimistic overlay), so consecutive overloads in one workout build on
    /// each other instead of both proposing from the same stale base.
    /// Internal (not private) so the apply half in
    /// `+ProgressiveOverloadApply.swift` resolves the same target this file
    /// qualifies against — one resolution rule, not two.
    func resolveOverloadTemplateTarget(
        for exercise: ActiveWorkoutExercise,
        routineID: UUID
    ) -> (sets: [WatchSet], alternativeID: UUID?)? {
        guard let routine = effectiveRoutine(for: routineID),
              let slot = routine.exercises.first(where: { $0.id == exercise.id }) else { return nil }

        guard exercise.wasSwapped else {
            guard !slot.sets.isEmpty else { return nil }
            return (slot.sets, nil)
        }
        // A swapped exercise's values belong to the alternative's OWN scheme.
        // Match on the performed exercise's library id — never the name.
        guard let alternative = slot.alternatives?.first(where: { $0.exerciseId == exercise.exerciseId }),
              !alternative.sets.isEmpty else { return nil }
        return (alternative.sets, alternative.id)
    }

}
