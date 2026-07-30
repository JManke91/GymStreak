//
//  WatchWorkoutViewModel+SummaryOverload.swift
//  GymStreakWatch Watch App
//
//  Post-workout summary progressive overload (ticket 05): the row state the
//  recap renders, derived from the FROZEN terminal workout rather than from any
//  live editing state.
//
//  This file owns only which rows exist and gathering the inputs each one's
//  state is decided from — the decision itself lives in the shared, testable
//  `WatchSummaryOverloadPolicy`. It adds no qualification rule, no math, no
//  persistence and no transport: rows call straight into ticket 04's
//  `applyProgressiveOverload`, so the recap and the mid-workout capsule are two
//  entry points to ONE operation.
//
//  Rows are resolved into stored state and never computed in a view body — the
//  lookup chain behind one row walks the routine list, its slots and their
//  alternatives (see `WatchOverloadDisplay` for the same reasoning).
//

import Foundation

extension WatchWorkoutViewModel {

    // MARK: - Recording

    /// Called by the single apply operation, for BOTH surfaces, so a
    /// mid-workout apply arrives at the summary already confirmed and can never
    /// be offered a second time.
    func recordAppliedOverload(
        slotID: UUID,
        setChanges: [WatchTemplateSetChange],
        targetRepMin: Int,
        isAssistance: Bool
    ) {
        guard let probe = setChanges.first, let transactionID = appliedOverloadSlots[slotID] else { return }
        // The same helper iOS uses on the delivered payload, so the recap and
        // History can never reach opposite verdicts on one intent.
        let isUniform = WatchTemplateSetChange.haveUniformProposedWeights(setChanges)
        appliedOverloadResults[slotID] = WatchAppliedOverload(
            transactionID: transactionID,
            probeSetID: probe.setID,
            probeWeight: probe.proposedWeight,
            newWeight: isUniform ? probe.proposedWeight : nil,
            targetRepMin: targetRepMin,
            isAssistance: isAssistance
        )
        refreshSummaryOverloadRows()
    }

    // MARK: - Rows

    /// Rebuilds every row from current state. Cheap enough to re-run whenever
    /// something it depends on moves (the summary appearing, an apply
    /// committing, the effective routine changing after an acknowledgment) and
    /// deliberately NOT incremental — one derivation means the states cannot
    /// drift out of agreement with each other.
    func refreshSummaryOverloadRows() {
        guard let summary = workoutSummary else {
            summaryOverloadRows = [:]
            return
        }
        // Keyed by slot id rather than ordered: the recap already renders the
        // frozen exercise order, and each of its rows needs an O(1) answer for
        // its own slot without searching a list per row.
        var rows: [UUID: WatchSummaryOverloadRow] = [:]
        for exercise in summary.exercises {
            guard let state = summaryOverloadState(slotID: exercise.id) else { continue }
            rows[exercise.id] = WatchSummaryOverloadRow(id: exercise.id, state: state)
        }
        summaryOverloadRows = rows
    }

    /// Gathers the live inputs and hands the decision to the shared policy, so
    /// the rule itself lives in one testable place rather than inside a view
    /// model the test suite cannot reach.
    ///
    /// nil means "this exercise gets no overload row at all" — it never
    /// qualified, or its template target can no longer be resolved (the slot or
    /// alternative was deleted on iPhone), in which case there is nothing
    /// honest to offer and the recap keeps its plain achievement styling.
    private func summaryOverloadState(slotID: UUID) -> WatchSummaryOverloadRow.State? {
        let applied = appliedOverloadResults[slotID]
        // The same target resolution the apply path uses, so an actionable row
        // is always applicable and a probe weight is always the current one.
        var target: (sets: [WatchSet], alternativeID: UUID?)?
        if let exercise = exercises.first(where: { $0.id == slotID }), let routineID = currentRoutine?.id {
            target = resolveOverloadTemplateTarget(for: exercise, routineID: routineID)
        }
        return WatchSummaryOverloadPolicy.state(
            applied: applied,
            isTransactionPending: applied.map {
                connectivityManager.syncState.hasPendingTransaction(id: $0.transactionID)
            } ?? false,
            currentProbeWeight: applied.flatMap { result in
                target?.sets.first(where: { $0.id == result.probeSetID })?.weight
            },
            qualifies: qualifiesForProgressiveOverload(slotID: slotID),
            isTargetResolvable: target != nil
        )
    }

    // MARK: - Row actions

    /// Opens the shared overload sheet for a recap row. Same presentation owner
    /// as mid-workout, so only one picker can ever be up at a time.
    func presentSummaryOverload(slotID: UUID) {
        guard overloadPresentation == .none else { return }
        guard case .actionable? = summaryOverloadRows[slotID]?.state else { return }
        setOverloadPresentation(.suggestion(slotID: slotID))
    }
}
