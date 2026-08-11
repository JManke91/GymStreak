//
//  WatchTemplateTransactionService+ProgressiveOverload.swift
//  GymStreak
//
//  The template-ONLY progressive-overload kind (progressive-overload ticket 04),
//  executed through the same phases, repositories, and single save as every
//  other watch template transaction. See the header of
//  `WatchTemplateTransactionService.swift` for the transaction contract.
//
//  Two properties make this safe to redeliver:
//
//  • Values are ABSOLUTE, never deltas. Each set change carries the value the
//    watch expected to find and the value it proposes, so a duplicate delivery
//    re-applies the same end state instead of incrementing twice.
//  • The whole intent is resolved and checked BEFORE anything is mutated, so a
//    single unresolvable target or conflicting value rejects the entire
//    transaction with the routine left byte-for-byte untouched.
//
//  It never creates workout history: a template-only transaction legitimately
//  has no workout, and fabricating a placeholder session would invent a
//  training record the user never performed.
//

import Foundation

extension WatchTemplateTransactionService {
    /// Why a resolved intent could not be applied. Every case is TERMINAL —
    /// the watch's optimistic overlay is retired through the ordinary
    /// acknowledgment + authoritative-context flow, never by a silent repair.
    private enum OverloadResolution {
        case success(routine: Routine, updates: [SetUpdate])
        case failure(String)
    }

    /// Applies one progressive-overload intent to the current SwiftData routine.
    ///
    /// Targets resolve by stable ID only — the routine slot, then the
    /// alternative's own set scheme when `alternativeID` is set. A missing
    /// routine, slot, alternative, or set is a terminal rejection, never a
    /// name-based repair or a recreated template.
    func executeProgressiveOverload(
        _ intent: IncomingProgressiveOverload,
        routineID: UUID
    ) -> Outcome {
        switch resolveOverload(intent, routineID: routineID) {
        case .failure(let reason):
            // Nothing was staged, so this save is a no-op; it keeps every kind
            // on the same commit-exactly-once path.
            if let failure = commit(routine: nil) { return failure }
            print("Progressive-overload transaction rejected: \(reason) — routine untouched")
            return .rejected(reason)
        case .success(let routine, let updates):
            apply(updates)
            if let failure = commit(routine: routine) { return failure }
            print("Progressive-overload transaction applied: \(updates.count) set(s) on '\(routine.name)'")
            return .applied
        }
    }

    // MARK: - Resolution + validation (before any mutation)

    private func resolveOverload(
        _ intent: IncomingProgressiveOverload,
        routineID: UUID
    ) -> OverloadResolution {
        // Separate from `isWellFormed` so the versioned rejection is
        // diagnosable: "the sender speaks a newer schema" and "the sender sent
        // nonsense" are very different failures to read in a log.
        guard intent.isSchemaSupported else {
            return .failure("unsupported progressive-overload payload schema")
        }
        guard intent.isWellFormed else {
            return .failure("malformed progressive-overload intent")
        }
        guard let routine = routineRepository.fetch(id: routineID) else {
            return .failure("routine \(routineID) not found")
        }
        guard let slot = routine.routineExercisesList.first(where: { $0.id == intent.routineExerciseID }) else {
            return .failure("routine slot \(intent.routineExerciseID) not found")
        }

        // Resolve the exact scheme the watch performed against. An alternative's
        // values must never be written into the primary scheme, so the
        // alternative is matched by its own stable id — never by display name.
        if let alternativeID = intent.alternativeID {
            guard let alternative = slot.alternativesList.first(where: { $0.id == alternativeID }) else {
                return .failure("alternative \(alternativeID) not found on slot \(intent.routineExerciseID)")
            }
            return resolve(intent, in: routine, sets: alternative.setsList, wrap: SetUpdate.Target.alternativeSet)
        }
        return resolve(intent, in: routine, sets: slot.setsList, wrap: SetUpdate.Target.routineSet)
    }

    /// Three-way comparison per set against the CURRENT template values.
    /// Generic over the two set row types so the primary and alternative
    /// schemes cannot drift apart.
    private func resolve<Row>(
        _ intent: IncomingProgressiveOverload,
        in routine: Routine,
        sets: [Row],
        wrap: (Row) -> SetUpdate.Target
    ) -> OverloadResolution where Row: TemplateSetRow {
        var updates: [SetUpdate] = []
        for change in intent.setChanges {
            guard let set = sets.first(where: { $0.id == change.setID }) else {
                return .failure("template set \(change.setID) not found")
            }
            let matchesExpected = set.reps == change.expectedReps
                && IncomingTemplateSetChange.weightsMatch(set.weight, change.expectedWeight)
            let matchesProposed = set.reps == change.proposedReps
                && IncomingTemplateSetChange.weightsMatch(set.weight, change.proposedWeight)

            if matchesExpected {
                updates.append(SetUpdate(
                    target: wrap(set), reps: change.proposedReps, weight: change.proposedWeight
                ))
            } else if matchesProposed {
                // Already satisfied — a duplicate delivery, or the user's own
                // iPhone edit happened to land on the same values. Idempotent.
                continue
            } else {
                // A third value: the template changed on iPhone since the watch
                // read it. The authoritative routine wins; rejecting the WHOLE
                // transaction is what keeps "all set changes are one atomic
                // intent" true rather than applying a partial increase.
                return .failure(
                    "template set \(change.setID) changed since the watch read it "
                    + "(expected \(change.expectedReps)×\(change.expectedWeight), "
                    + "found \(set.reps)×\(set.weight))"
                )
            }
        }
        return .success(routine: routine, updates: updates)
    }
}

/// The two template set row types share the value shape the overload compares
/// and writes. This exists only so the resolution above can be written once.
protocol TemplateSetRow: AnyObject {
    var id: UUID { get }
    var reps: Int { get set }
    var weight: Double { get set }
    var restTime: TimeInterval { get set }
}

extension ExerciseSet: TemplateSetRow {}
extension AlternativeExerciseSet: TemplateSetRow {}
