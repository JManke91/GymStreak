//
//  RoutinePlanLinkRepair.swift
//  GymStreak
//

import Foundation
import SwiftData

/// One-shot repair for training plans that reached CloudKit without their
/// owning routine.
///
/// Until `Routine.schedules` was remodelled as a to-many, the routine ↔ plan
/// link was a to-one ↔ to-one relationship, which `NSPersistentCloudKitContainer`
/// does not mirror in practice: every `CD_RoutineSchedule` record arrived in the
/// private database with its scalar fields intact and **no** `CD_routine`
/// reference, and `CD_Routine.CD_schedule` stayed empty as well. Other devices
/// therefore imported plans as orphans and showed every routine as unplanned.
/// See docs/workout-planning.md for the measurements.
///
/// Remodelling fixes plans created or edited from now on, but not the records
/// already sitting in CloudKit: mirroring exports from persistent history, so an
/// object nobody touches is never re-uploaded. This pass touches them. For each
/// planned routine it deletes the existing schedule rows and inserts one
/// identical replacement linked to the routine, which registers a create
/// transaction and exports a correct record while tombstoning the broken one.
/// Every user-configured value is copied verbatim, so nothing observable
/// changes locally.
///
/// Schedules that arrive with no routine at all are **left alone**, deliberately.
/// Deleting them looks tempting — they are invisible and unrecoverable, since
/// nothing records which routine they belonged to — but a local delete is
/// exported and removes the record for every other device that imports it. The
/// device that still holds the plan linked locally depends on that same record,
/// so deleting an orphan here would destroy the user's only good copy there. It
/// is also unnecessary: when the device that owns the link runs this pass, its
/// own delete of the stale record retires the orphan everywhere automatically.
///
/// Waits for the sync status to reach `.upToDate` — no events in flight — before
/// touching anything, so it is far less likely to delete a record that is
/// mid-import or race the importer's merge on this context. That gate is a
/// mitigation, not a guarantee: the status is optimistic at cold launch (see
/// `runIfNeeded()`). With iCloud off there is nothing to re-export, so it does
/// nothing and leaves the flag clear for a later launch.
///
/// Runs at most once per device, gated by a `UserDefaults` version — but never
/// over an empty store, so a device that has not imported anything yet retries
/// on the next launch instead of stranding the flag. Two devices
/// that both run it before syncing can leave two identical schedules on one
/// routine; `Routine.schedule` resolves that deterministically, so both still
/// display the same plan. That is the deliberate trade — a duplicated plan is
/// recoverable, a lost one is not.
@MainActor
final class RoutinePlanLinkRepair {
    private static let repairVersionKey = "routinePlanLinkRepairVersion"
    private static let currentVersion = 1

    private let modelContext: ModelContext
    private let cloudSyncStatus: CloudSyncStatusProviding
    private let defaults: UserDefaults

    init(
        modelContext: ModelContext,
        cloudSyncStatus: CloudSyncStatusProviding,
        defaults: UserDefaults = .standard
    ) {
        self.modelContext = modelContext
        self.cloudSyncStatus = cloudSyncStatus
        self.defaults = defaults
    }

    /// Waits for sync to be quiescent, then repairs once.
    ///
    /// Awaits rather than polls: `statusUpdates()` emits the current status
    /// immediately and every change after it, so this returns on the first
    /// status that is `.upToDate` — or on `.off`, where there is nothing to do.
    func runIfNeeded() async {
        guard defaults.integer(forKey: Self.repairVersionKey) < Self.currentVersion else { return }

        for await status in cloudSyncStatus.statusUpdates() {
            switch status.state {
            case .off:
                // No mirroring — signed out, restricted, or the local-only
                // fallback. There is nothing to re-export and nothing will
                // import later either, so churning the store would be pointless.
                // The flag stays clear so a launch with iCloud available repairs.
                return
            case .upToDate:
                // No events in flight. Note this is *optimistic at cold launch*:
                // `CloudKitSyncStatusMonitor` seeds its status from restored
                // defaults in `init`, so the very first `.upToDate` can arrive
                // before this session has imported anything. That is safe — the
                // pass either finds nothing to look at and keeps waiting, or
                // operates on rows that are already local — but it is not proof
                // that an import finished. There is no signal in this app's sync
                // model that proves that, and building one is not worth it here.
                //
                // Returning either way is deliberate: waiting around for rows to
                // appear would leave a task suspended for the whole session on
                // every device that has no plans, and the flag stays clear
                // whenever nothing was repaired, so the next launch retries.
                repair()
                return
            case .syncing, .waiting:
                // Keep waiting. Note `lastSuccessfulSync` is NOT usable as the
                // gate: `CloudKitSyncStatusMonitor` restores it from
                // `UserDefaults` at launch, so on any device that has ever
                // synced it is already non-nil before this session transfers
                // anything — it cannot distinguish "finished" from "mid-import",
                // which is the race this wait exists to avoid. A session that
                // never quiesces simply leaves the flag clear and retries on the
                // next launch.
                continue
            }
        }
    }

    private func repair() {
        // Only ever save or roll back our own work. Another component can have
        // staged unsaved changes on this shared context — `DefaultContentSeeder`'s
        // stranded-library recovery leaves its inserts pending when its own save
        // throws — and committing or discarding those is not this pass's call.
        // Same guard, and same reason, as `SwiftDataMainContextRoutineCacheRefresher`.
        // The flag stays clear, so the next launch retries.
        guard !modelContext.hasChanges else {
            print("RoutinePlanLinkRepair deferred — unsaved work exists on the context")
            return
        }
        do {
            // Fetched from the child side on purpose: it is the small table, and
            // every routine it reaches is already faulted in, so the pass costs
            // no per-routine relationship fault on the main actor.
            let schedules = try modelContext.fetch(FetchDescriptor<RoutineSchedule>())

            // Nothing to repair *yet*. A fresh install, or a device still
            // importing, would otherwise record the flag over an empty store and
            // never repair the plans that arrive a moment later — the same
            // stranding trap `DefaultContentSeeder` documents. Leaving the flag
            // clear costs one fetch of a tiny table per launch.
            guard !schedules.isEmpty else { return }

            var plannedRoutines: [Routine] = []
            for schedule in schedules {
                // Orphans are skipped, never deleted — see the type's note.
                guard let routine = schedule.routine else { continue }
                if !plannedRoutines.contains(where: { $0 === routine }) {
                    plannedRoutines.append(routine)
                }
            }

            for routine in plannedRoutines {
                relinkPlan(of: routine)
            }

            if modelContext.hasChanges {
                try modelContext.save()
            }
            // Only recorded once the save committed: a thrown save leaves the
            // flag clear so the next launch retries instead of skipping.
            defaults.set(Self.currentVersion, forKey: Self.repairVersionKey)
        } catch {
            print("RoutinePlanLinkRepair failed: \(error)")
            // The deletes and inserts are still pending on the shared
            // `mainContext`, and other components save that same context
            // whenever it has changes — without this, one of them would commit a
            // half-finished repair while the retry flag is clear. Discarding
            // everything pending is correct here only because the guard above
            // proved the context was clean when this pass began.
            modelContext.rollback()
        }
    }

    /// Replaces a routine's plan with an identical, freshly inserted one so the
    /// mirroring delegate exports it with its `CD_routine` reference set.
    private func relinkPlan(of routine: Routine) {
        guard let existing = routine.schedule else { return }

        // Read every value before deleting anything — `existing` is one of the
        // rows about to be removed.
        let replacement = RoutineSchedule(
            type: existing.type,
            intervalDays: existing.intervalDays,
            weekdays: existing.weekdays,
            startDate: existing.startDate
        )
        replacement.id = existing.id
        replacement.isActive = existing.isActive
        replacement.createdAt = existing.createdAt

        for stale in routine.schedules ?? [] {
            // Unlink before deleting, matching `removeSchedule`. Defensive: the
            // replacement copies `id` *and* `createdAt`, so if a deleted row ever
            // lingered in the faulted inverse array the comparator in
            // `Routine.schedule` would be a total tie and could surface the
            // tombstoned row while this pass reported success.
            stale.routine = nil
            modelContext.delete(stale)
        }
        replacement.routine = routine
        modelContext.insert(replacement)
    }
}
