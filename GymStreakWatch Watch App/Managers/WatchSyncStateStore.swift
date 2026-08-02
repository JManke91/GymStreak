//
//  WatchSyncStateStore.swift
//  GymStreakWatch Watch App
//
//  The single watch sync-state owner (ticket 04, extended by ticket 05 of
//  in-workout routine editing). Formerly `WatchWorkoutOutgoingQueue` — the
//  responsibility grew from "outgoing workout FIFO" to everything the watch
//  must keep consistent across the sync boundary, all in ONE atomically
//  replaced App Group state file:
//
//    • the durable FIFO of completed workouts / template transactions,
//      each with its finalization phase and any held terminal acknowledgment;
//    • the persistent template sender epoch and per-routine sequence counters;
//    • the routine authority state (epoch/generation/nonce/retired epochs);
//    • the authoritative routine base plus per-routine optimistic anchors.
//
//  They share one file because they must commit together: allocating a
//  transaction identity with its payload, and accepting a routine handover
//  while retiring the acknowledged head, are each a single transaction.
//  `RoutineStore` no longer persists an overlapping copy of the routines — it
//  is a published projection of `effectiveRoutines()`.
//
//  Finalization phases (unchanged from ticket 04):
//    awaitingHealthKitMetadata → awaitingHealthKitFinish → transportEligible
//  (`quarantined` marks payloads whose exact bytes can never transport).
//
//  Entries are retired only by an app-level acknowledgment from iOS — never by
//  WatchConnectivity transfer callbacks. A template transaction additionally
//  requires that the correlated authoritative routine generation has applied
//  locally, so ack-first and context-first delivery converge identically.
//
//  IDENTICAL COPY in both targets — `GymStreak/Data/Sync/` and
//  `GymStreakWatch Watch App/Managers/` — keep them in sync. There is no
//  watch unit-test target, so the iOS test target covers this logic
//  (see WatchSyncStateStoreTests / WatchWorkoutFinalizerTests).
//

import Foundation

/// Versioned envelope so future schema revisions stay backward-decodable.
/// v1/v2 entries decode through `OutgoingSyncEntry`'s legacy `workout` key;
/// v3 stores the generic transaction-first payload.
private struct WatchSyncStateFile: Codable {
    var version: Int
    var entries: [OutgoingSyncEntry]
    var senderEpoch: UUID?
    /// routineID.uuidString → next sequence to allocate.
    var nextSequenceByRoutine: [String: UInt64]?
    var routineAuthority: WatchRoutineAuthorityState?
    /// Last accepted authoritative routine list; nil until one arrives.
    var authoritativeRoutines: [WatchRoutine]?
    /// routineID.uuidString → the effective routine captured when that
    /// routine's first pending template transaction was queued.
    var routineAnchors: [String: WatchRoutine]?
    var lastRoutineSyncDate: Date?
    /// Once true, the pre-file UserDefaults stores never need to be opened
    /// again. Optional so state written before this marker remains decodable.
    var hasCompletedLegacyDefaultsMigration: Bool?
}

@MainActor
final class WatchSyncStateStore {
    nonisolated static let appGroupID = "group.com.gymstreak.shared"
    nonisolated static let legacyDefaultsKey = "pendingCompletedWorkouts"
    /// RoutineStore's pre-ticket-05 persistence, adopted once as the initial
    /// authoritative base so an upgrade never blanks the watch's routines.
    nonisolated static let legacyRoutinesKey = "syncedRoutines"

    private var entries: [OutgoingSyncEntry] = []
    private var senderEpoch: UUID?
    private var nextSequenceByRoutine: [String: UInt64] = [:]
    private var routineAuthority = WatchRoutineAuthorityState.initial()
    private var authoritativeRoutines: [WatchRoutine]?
    private var routineAnchors: [String: WatchRoutine] = [:]
    private(set) var lastRoutineSyncDate: Date?
    private var hasCompletedLegacyDefaultsMigration = false
    private var isStateDurable = false

    private let fileURL: URL?

    /// Invoked whenever the effective routines may have changed (new base,
    /// new pending transaction, retirement). `RoutineStore` republishes on it.
    var onEffectiveRoutinesChanged: (() -> Void)?
    /// Invoked when the published routine challenge changed and must be
    /// republished to iOS (bootstrap, handover acceptance).
    var onChallengeStateChanged: (() -> Void)?
    /// Invoked after a durable retirement can expose the next per-routine FIFO
    /// head. The transport coordinator uses this to continue draining without
    /// waiting for another Watch lifecycle event.
    var onTransportEligibilityChanged: (() -> Void)?

    /// - Parameters:
    ///   - directory: override for tests; defaults to the App Group's
    ///     WorkoutSync directory.
    ///   - legacyDefaults: source of the pre-ticket-04 UserDefaults queue and
    ///     the pre-ticket-05 routine cache, migrated on first init.
    init(
        directory: URL? = nil,
        legacyDefaults: UserDefaults? = nil
    ) {
        let base = directory ?? FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent("WorkoutSync", isDirectory: true)
        self.fileURL = base?.appendingPathComponent("outgoing-queue.json")
        if let base { try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true) }

        var hadState = false
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            if let decoded = try? JSONDecoder().decode(WatchSyncStateFile.self, from: data) {
                entries = decoded.entries
                senderEpoch = decoded.senderEpoch
                nextSequenceByRoutine = decoded.nextSequenceByRoutine ?? [:]
                if let authority = decoded.routineAuthority { routineAuthority = authority }
                authoritativeRoutines = decoded.authoritativeRoutines
                routineAnchors = decoded.routineAnchors ?? [:]
                lastRoutineSyncDate = decoded.lastRoutineSyncDate
                hasCompletedLegacyDefaultsMigration =
                    decoded.hasCompletedLegacyDefaultsMigration ?? false
                hadState = true
                isStateDurable = true
            } else {
                // An undecodable state file is preserved for diagnostics
                // instead of being silently overwritten.
                try? FileManager.default.moveItem(at: fileURL, to: fileURL.appendingPathExtension("corrupt"))
                WatchSyncDiagnostics.fault("queue: state file undecodable — quarantined as .corrupt, starting empty")
            }
        }

        // The App Group suite exists only to adopt state written by older
        // releases. Resolve it lazily until a successful atomic state write
        // records that migration is complete; later launches stay file-only.
        let migrationDefaults: UserDefaults?
        if hasCompletedLegacyDefaultsMigration {
            migrationDefaults = nil
        } else if let legacyDefaults {
            migrationDefaults = legacyDefaults
        } else if directory == nil {
            migrationDefaults = UserDefaults(suiteName: Self.appGroupID)
        } else {
            migrationDefaults = nil
        }

        let originalEntries = entries
        let originalEpoch = senderEpoch
        let originalSequences = nextSequenceByRoutine
        let originalRoutines = authoritativeRoutines
        let originalMigrationCompletion = hasCompletedLegacyDefaultsMigration
        let entryMigration = migrateLegacyEntries(from: migrationDefaults)
        let routineMigration = migrateLegacyRoutines(from: migrationDefaults)
        let didAssignIdentities = assignMissingTransactionIdentities()
        let didCompleteLegacyMigration =
            !hasCompletedLegacyDefaultsMigration
            && migrationDefaults != nil
            && entryMigration.isComplete
            && routineMigration.isComplete
        if didCompleteLegacyMigration {
            hasCompletedLegacyDefaultsMigration = true
        }

        // Queue migration, identity allocation, sequence counters, routine
        // anchor/base state, and the stable watch authority are committed in
        // one replacement before any migrated entry can transport.
        if !hadState || entryMigration.didChange || routineMigration.didChange
            || didAssignIdentities || didCompleteLegacyMigration {
            do {
                try persist()
                if entryMigration.didChange {
                    migrationDefaults?.removeObject(forKey: Self.legacyDefaultsKey)
                }
            } catch {
                entries = originalEntries
                senderEpoch = originalEpoch
                nextSequenceByRoutine = originalSequences
                authoritativeRoutines = originalRoutines
                hasCompletedLegacyDefaultsMigration = originalMigrationCompletion
                WatchSyncDiagnostics.error("queue: migration/state write failed — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Reading

    var all: [OutgoingSyncEntry] { entries }

    func entry(id: UUID) -> OutgoingSyncEntry? {
        entries.first { $0.workoutID == id || $0.id == id }
    }

    /// Entries whose frozen bytes may be handed to WatchConnectivity now.
    /// No-template workouts are always eligible once finalized; a template
    /// transaction only when it is the head of its routine's FIFO — the next
    /// one is released when the head retires (matching ack + applied routine
    /// generation), never merely when its transfer completes.
    func transportEligibleEntries() -> [OutgoingSyncEntry] {
        guard isStateDurable else { return [] }
        let eligible = entries.filter { entry in
            guard entry.phase == .transportEligible else { return false }
            guard entry.hasTemplateIntent else { return true }
            guard entry.hasDurableTemplateIdentity else { return false }
            return isHeadTransaction(entry)
        }
        logWithheldEntries(eligible: eligible)
        return eligible
    }

    /// One bounded line naming what the per-routine FIFO head gate is holding
    /// back, and for how long. Without it a stalled head is completely silent —
    /// the blocked entries are simply never handed to WatchConnectivity, so
    /// there is nothing to observe in either app or in any transport log, and a
    /// finalized workout can sit undelivered indefinitely with no signal.
    private func logWithheldEntries(eligible: [OutgoingSyncEntry]) {
        let eligibleIDs = Set(eligible.map(\.id))
        let withheld = entries.filter {
            $0.phase == .transportEligible && !eligibleIDs.contains($0.id)
        }
        guard !withheld.isEmpty else { return }
        let blockingHead = withheld
            .compactMap { $0.routineID }
            .compactMap { liveHeadTransaction(forRoutine: $0) }
            .min { $0.enqueuedAt < $1.enqueuedAt }
        let minutes = blockingHead.map { Int(Date().timeIntervalSince($0.enqueuedAt) / 60) } ?? -1
        let message = """
            queue: \(withheld.count) finalized entr\(withheld.count == 1 ? "y" : "ies") withheld behind \
            unretired transaction \(WatchSyncDiagnostics.shortID(blockingHead?.id)) \
            (queued \(minutes) min ago)
            """
        // A head unretired for hours is no longer ordinary back-pressure: the
        // acknowledgment that would release it is not coming, and the workouts
        // behind it are being silently withheld from transport. Escalate so it
        // is findable in a support log without a debugger.
        if minutes >= Self.stalledHeadFaultMinutes {
            WatchSyncDiagnostics.fault(message + " — head appears stalled")
        } else {
            WatchSyncDiagnostics.notice(message)
        }
    }

    /// How long a per-routine FIFO head may stay unretired before the withheld
    /// entries behind it are logged as a fault rather than back-pressure. Two
    /// hours is far beyond any legitimate offline/unreachable window (transport
    /// reconciles on every activation, reachability change, foreground and
    /// background wake) while staying clear of a genuinely long unpaired trip.
    private static let stalledHeadFaultMinutes = 120

    /// Workout IDs of entries a previous process left mid-HealthKit
    /// finalization (`awaitingHealthKitMetadata`/`awaitingHealthKitFinish`),
    /// oldest first. Ticket 08 recovery inspects these to reconnect or reconcile
    /// the live HealthKit session before the launch-time promotion sweep.
    func interruptedFinalizationWorkoutIDs() -> [UUID] {
        entries
            .filter { $0.phase == .awaitingHealthKitMetadata || $0.phase == .awaitingHealthKitFinish }
            .compactMap { $0.workoutID }
    }

    /// The oldest unretired template transaction for a routine.
    func headTransaction(forRoutine routineId: UUID) -> OutgoingSyncEntry? {
        entries.first { $0.hasTemplateIntent && $0.routineID == routineId }
    }

    /// A quarantined entry is terminal: its exact bytes can never transport and
    /// no acknowledgment will ever retire it. It must therefore gate nothing —
    /// not transport ordering, not retirement, not the optimistic fold. This is
    /// the single definition all three sites share; `headTransaction(forRoutine:)`
    /// deliberately keeps the broader "oldest unretired" meaning for anchoring.
    private func isLiveTemplateIntent(_ entry: OutgoingSyncEntry) -> Bool {
        entry.hasTemplateIntent && entry.phase != .quarantined
    }

    private func liveHeadTransaction(forRoutine routineID: UUID) -> OutgoingSyncEntry? {
        entries.first { isLiveTemplateIntent($0) && $0.routineID == routineID }
    }

    private func isHeadTransaction(_ entry: OutgoingSyncEntry) -> Bool {
        guard let routineID = entry.routineID else { return false }
        return liveHeadTransaction(forRoutine: routineID)?.id == entry.id
    }

    /// Whether a template transaction is still queued — i.e. iOS has not yet
    /// returned a terminal acknowledgment whose routine generation also applied
    /// locally. Read by the post-workout recap (ticket 05) to tell "still
    /// converging" from "iPhone has ruled on it"; it deliberately exposes only
    /// presence, since the outcome itself is already legible from the effective
    /// routine once the entry is gone.
    func hasPendingTransaction(id transactionID: UUID) -> Bool {
        entries.contains { $0.templateTransaction?.transactionID == transactionID }
    }

    // MARK: - Routine authority + effective routines

    var routineChallengeContext: [String: String] {
        isStateDurable ? routineAuthority.challengeContext : [:]
    }

    var acceptedRoutineEpoch: UUID? { routineAuthority.acceptedEpoch }
    var acceptedRoutineGeneration: UInt64 { routineAuthority.acceptedGeneration }

    /// What the watch UI must show: the newest authoritative base with every
    /// unresolved template transaction folded back over it, so an ordinary or
    /// legacy routine context can never erase pending optimistic values.
    func effectiveRoutines() -> [WatchRoutine] {
        var routines = authoritativeRoutines ?? []
        // A routine the base doesn't carry (never-synced base, or an anchor
        // captured before the first context) falls back to its anchor.
        for (key, anchor) in routineAnchors where !routines.contains(where: { $0.id.uuidString == key }) {
            routines.append(anchor)
        }
        // Every unresolved template-mutating kind folds, in FIFO order, so the
        // overlay always matches the order iOS will apply them in. A
        // quarantined entry is excluded by the same terminal-entry rule as the
        // transport/retirement gates: iOS will never apply it, so folding it
        // would overlay values on an authoritative base that has moved past it
        // and then prescribe them for the next workout.
        for entry in entries where isLiveTemplateIntent(entry) {
            if let workout = entry.completedWorkout {
                routines = routines.map { WatchRoutineTemplateFold.apply(workout, to: $0) }
            } else if let intent = entry.templateTransaction?.payload.progressiveOverload {
                routines = routines.map { WatchRoutineTemplateFold.apply(intent, to: $0) }
            }
        }
        return routines
    }

    /// Applies an incoming iOS → watch routine snapshot.
    ///
    /// `header` is nil for a legacy unversioned context (pre-ticket-05 iOS):
    /// it replaces the base but never touches the authority, so it can neither
    /// establish nor advance a generation — and the fold still protects
    /// pending optimistic values.
    ///
    /// Returns true when the base was replaced.
    @discardableResult
    func applyRoutineContext(_ routines: [WatchRoutine], header: RoutineSnapshotHeader?) -> Bool {
        guard let header else {
            if routines == authoritativeRoutines {
                let previousSyncDate = lastRoutineSyncDate
                lastRoutineSyncDate = Date()
                do {
                    try persist()
                } catch {
                    lastRoutineSyncDate = previousSyncDate
                    WatchSyncDiagnostics.error("queue: legacy routine freshness write failed — \(error.localizedDescription)")
                    return false
                }
                onEffectiveRoutinesChanged?()
                return false
            }
            let previousRoutines = authoritativeRoutines
            let previousSyncDate = lastRoutineSyncDate
            authoritativeRoutines = routines
            lastRoutineSyncDate = Date()
            do {
                try persist()
            } catch {
                authoritativeRoutines = previousRoutines
                lastRoutineSyncDate = previousSyncDate
                WatchSyncDiagnostics.error("queue: legacy routine context write failed — \(error.localizedDescription)")
                return false
            }
            onEffectiveRoutinesChanged?()
            return true
        }

        switch routineAuthority.decision(for: header) {
        case .reject(let reason):
            WatchSyncDiagnostics.notice("queue: rejected routine context (\(reason))")
            return false
        case .duplicate:
            // Same epoch/generation already applied. Still re-evaluate held
            // acknowledgments: an ack may have arrived after the context.
            retireSatisfiedAcknowledgments()
            return false
        case .apply(let isHandover):
            let previous = routineAuthority
            routineAuthority.accept(header, isHandover: isHandover)
            let previousBase = authoritativeRoutines
            let previousSyncDate = lastRoutineSyncDate
            authoritativeRoutines = routines
            lastRoutineSyncDate = Date()
            do {
                try persist()
            } catch {
                routineAuthority = previous
                authoritativeRoutines = previousBase
                lastRoutineSyncDate = previousSyncDate
                WatchSyncDiagnostics.error("queue: routine context write failed — \(error.localizedDescription)")
                return false
            }
            if isHandover { onChallengeStateChanged?() }
            onEffectiveRoutinesChanged?()
            retireSatisfiedAcknowledgments()
            return true
        }
    }

    // MARK: - Mutations (throwing = atomic write is the persistence boundary)

    /// Idempotent enqueue: an existing entry with the same workout id keeps
    /// its FIFO position, frozen payload bytes, and phase — retries never
    /// reconstruct a finalized workout. Throws when the atomic state write
    /// fails, in which case nothing was enqueued and no identity was
    /// allocated.
    ///
    /// A workout carrying template intent is assigned its transaction identity
    /// (stable transaction ID, the persistent sender epoch, and the next
    /// per-routine sequence) here, and `routineAnchor` is retained for the
    /// routine's first pending transaction — payload, identity, counter, FIFO
    /// position, and anchor all commit in one replacement, before transport or
    /// any optimistic local mutation.
    @discardableResult
    func enqueue(
        _ workout: CompletedWatchWorkout,
        phase: OutgoingWorkoutPhase,
        routineAnchor: WatchRoutine? = nil
    ) throws -> OutgoingSyncEntry {
        if let existing = entry(id: workout.id) { return existing }

        var payload = workout
        let previousEpoch = senderEpoch
        let previousSequences = nextSequenceByRoutine
        let previousAnchors = routineAnchors

        if payload.shouldUpdateTemplate,
           payload.templateTransactionID == nil
            || payload.templateSenderEpoch == nil
            || payload.templateSequence == nil {
            let identity = allocateTransactionIdentity(for: payload.routineId)
            payload.templateTransactionID = UUID()
            payload.templateSenderEpoch = identity.epoch
            payload.templateSequence = identity.sequence
        }
        if payload.shouldUpdateTemplate, let routineAnchor,
           routineAnchors[payload.routineId.uuidString] == nil,
           headTransaction(forRoutine: payload.routineId) == nil {
            routineAnchors[payload.routineId.uuidString] = routineAnchor
        }

        let syncPayload: OutgoingSyncPayload = payload.shouldUpdateTemplate
            ? .templateTransaction(TemplateTransactionEnvelope(completedWorkout: payload))
            : .completedWorkout(payload)
        let newEntry = OutgoingSyncEntry(
            payload: syncPayload, phase: phase, enqueuedAt: Date(), quarantineReason: nil, heldAck: nil
        )
        entries.append(newEntry)
        do {
            try persist()
        } catch {
            entries.removeLast()
            senderEpoch = previousEpoch
            nextSequenceByRoutine = previousSequences
            routineAnchors = previousAnchors
            throw error
        }
        onEffectiveRoutinesChanged?()
        return newEntry
    }

    /// Enqueues a TEMPLATE-ONLY transaction — one that carries no completed
    /// workout (progressive overload, ticket 04). Same commit contract as the
    /// workout enqueue: the exact payload bytes, the per-routine sequence, the
    /// FIFO position, and the routine anchor all commit in ONE atomic
    /// replacement, before transport and before any optimistic local mutation.
    /// Throws when the write fails, in which case nothing was enqueued and no
    /// counter was consumed — the caller must then neither transport nor show
    /// success.
    ///
    /// `transactionID` is supplied by the caller and is the deduplication key:
    /// a repeated attempt with the same id returns the existing entry rather
    /// than allocating a second sequence, so repeated taps and post-crash
    /// recovery can never apply twice. The envelope's `workoutID` is
    /// deliberately nil — `TemplateTransactionEnvelope.isInternallyConsistent`
    /// requires it for a payload without a workout, and a non-nil value would
    /// additionally collide with the workout-id matching used by `entry(id:)`,
    /// `advance`, `quarantine`, and `retire`.
    @discardableResult
    func enqueue(
        progressiveOverload intent: WatchProgressiveOverloadIntent,
        routineID: UUID,
        transactionID: UUID,
        routineAnchor: WatchRoutine? = nil
    ) throws -> OutgoingSyncEntry {
        if let existing = entries.first(where: { $0.templateTransaction?.transactionID == transactionID }) {
            return existing
        }

        let previousEpoch = senderEpoch
        let previousSequences = nextSequenceByRoutine
        let previousAnchors = routineAnchors

        let identity = allocateTransactionIdentity(for: routineID)
        if let routineAnchor,
           routineAnchors[routineID.uuidString] == nil,
           headTransaction(forRoutine: routineID) == nil {
            routineAnchors[routineID.uuidString] = routineAnchor
        }

        let envelope = TemplateTransactionEnvelope(
            transactionID: transactionID,
            senderEpoch: identity.epoch,
            routineID: routineID,
            sequence: identity.sequence,
            workoutID: nil,
            payload: .progressiveOverload(intent)
        )
        // A template-only transaction has no HealthKit finalization to wait
        // for, so it is transport-eligible the moment it is durable.
        let newEntry = OutgoingSyncEntry(
            payload: .templateTransaction(envelope), phase: .transportEligible,
            enqueuedAt: Date(), quarantineReason: nil, heldAck: nil
        )
        entries.append(newEntry)
        do {
            try persist()
        } catch {
            entries.removeLast()
            senderEpoch = previousEpoch
            nextSequenceByRoutine = previousSequences
            routineAnchors = previousAnchors
            throw error
        }
        onEffectiveRoutinesChanged?()
        return newEntry
    }

    /// Advances an entry's finalization phase. Throws (and keeps the previous
    /// phase) when the atomic write fails, so callers never treat an
    /// unpersisted advancement as durable.
    func advance(id: UUID, to phase: OutgoingWorkoutPhase) throws {
        guard let index = entries.firstIndex(where: { $0.workoutID == id || $0.id == id }) else { return }
        let previous = entries[index].phase
        entries[index].phase = phase
        do {
            try persist()
        } catch {
            entries[index].phase = previous
            throw error
        }
    }

    /// Marks an entry's exact bytes as permanently untransportable. Best
    /// effort: a failed write leaves the previous phase, which at worst
    /// retries a doomed transfer once more on the next lifecycle trigger.
    func quarantine(id: UUID, reason: String) {
        guard let index = entries.firstIndex(where: { $0.workoutID == id || $0.id == id }) else { return }
        let previousPhase = entries[index].phase
        let previousReason = entries[index].quarantineReason
        entries[index].phase = .quarantined
        entries[index].quarantineReason = reason
        do {
            try persist()
        } catch {
            entries[index].phase = previousPhase
            entries[index].quarantineReason = previousReason
            WatchSyncDiagnostics.error("queue: quarantine write failed — \(error.localizedDescription)")
            return
        }
        WatchSyncDiagnostics.fault("queue: quarantined entry \(WatchSyncDiagnostics.shortID(id)) — \(reason). These exact bytes can never transport.")
        // Quarantining is head-releasing (a terminal entry no longer gates its
        // routine), so the successor must be reconciled now rather than waiting
        // for an unrelated lifecycle trigger.
        onEffectiveRoutinesChanged?()
        onTransportEligibilityChanged?()
    }

    /// Promotes entries stranded in a HealthKit phase by a previous process
    /// (crash mid-finalization, or a HealthKit failure that was never retried
    /// in-process) to `transportEligible`, so the frozen payload still reaches
    /// iOS. Call only at process start, before any finalization can be in
    /// flight — promoting an entry whose finalizer is mid-sequence would let
    /// its next `advance` move the phase backwards.
    ///
    /// Safe against HealthKit-side duplicates because `finishWorkout()` is the
    /// only step that saves the HKWorkout and metadata is stamped before it:
    /// an interrupted finalization either never produced an HKWorkout at all,
    /// or produced a complete one carrying its external UUID (crash between
    /// finish and the phase write), which iOS ingestion/reconciliation already
    /// handles idempotently. The Apple Health record of a never-finished
    /// workout is lost — GymStreak history is the primary record. Interim
    /// policy until ticket 08 adds live-session recovery.
    func promoteInterruptedFinalizations() {
        let previousEntries = entries
        var promoted = false
        for index in entries.indices
        where entries[index].phase == .awaitingHealthKitMetadata || entries[index].phase == .awaitingHealthKitFinish {
            entries[index].phase = .transportEligible
            promoted = true
            WatchSyncDiagnostics.notice("queue: promoted interrupted finalization \(WatchSyncDiagnostics.shortID(entries[index].id)) to transportEligible")
        }
        guard promoted else { return }
        do {
            try persist()
        } catch {
            entries = previousEntries
            WatchSyncDiagnostics.error("queue: interrupted-finalization promotion failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Acknowledgments

    /// Records a plain legacy `workoutAck`. It retires only a no-template
    /// workout: an old iOS build acknowledges history without ever having
    /// processed the template intent, so discarding a template transaction on
    /// it would silently drop the user's requested update. Such entries stay
    /// queued and are re-sent on lifecycle triggers until iOS is upgraded.
    func acknowledgePlain(workoutId: UUID) {
        guard let entry = entry(id: workoutId) else { return }
        guard !entry.hasTemplateIntent else {
            WatchSyncDiagnostics.notice("queue: plain ack for template transaction \(WatchSyncDiagnostics.shortID(workoutId)) — retained (old iOS build)")
            return
        }
        retire(id: workoutId)
    }

    /// Records a versioned terminal acknowledgment. The entry is retired only
    /// once the correlated authoritative routine generation has also applied
    /// locally; until then the ack is held durably, so ack-first and
    /// context-first delivery converge identically.
    func acknowledgeTemplateTransaction(workoutId: UUID, ack: TemplateAckRecord) {
        acknowledgeTemplateTransaction(ack)
    }

    func acknowledgeTemplateTransaction(_ ack: TemplateAckRecord) {
        guard let index = entries.firstIndex(where: { $0.templateTransaction?.transactionID == ack.transactionID }),
              let transaction = entries[index].templateTransaction else { return }
        guard transaction.senderEpoch == ack.senderEpoch,
              transaction.sequence == ack.sequence,
              TemplateTransactionOutcomeWire(rawValue: ack.outcomeRaw) != nil else {
            WatchSyncDiagnostics.error("queue: template ack identity mismatch for transaction \(WatchSyncDiagnostics.shortID(ack.transactionID)) — ignored")
            return
        }
        let previous = entries[index].heldAck
        entries[index].heldAck = ack
        do {
            try persist()
        } catch {
            entries[index].heldAck = previous
            WatchSyncDiagnostics.error("queue: failed to persist template ack — \(error.localizedDescription)")
            return
        }
        retireSatisfiedAcknowledgments()
    }

    /// Retires every entry whose held acknowledgment's routine version has
    /// been applied locally, then recomputes the effective routines and lets
    /// the next transaction for that routine through.
    private func retireSatisfiedAcknowledgments() {
        // A later transaction may already have an ack/context because legacy
        // migration could leave multiple transfers in flight. Retire only the
        // satisfied prefix for each routine; removing B while A remains would
        // fold older A over B's authoritative base and visibly regress state.
        var blockedRoutines: Set<UUID> = []
        var satisfied: [OutgoingSyncEntry] = []
        // A quarantined entry can never be acknowledged, so it must not block
        // its routine's prefix (same terminal-entry rule as `isHeadTransaction`).
        for entry in entries where isLiveTemplateIntent(entry) {
            guard let routineID = entry.routineID, !blockedRoutines.contains(routineID) else { continue }
            guard let ack = entry.heldAck,
                  routineAuthority.hasApplied(
                    epoch: ack.routineEpoch, generation: ack.routineGeneration
                  ) else {
                blockedRoutines.insert(routineID)
                continue
            }
            satisfied.append(entry)
        }
        guard !satisfied.isEmpty else { return }
        for entry in satisfied {
            WatchSyncDiagnostics.info("queue: retiring template transaction \(WatchSyncDiagnostics.shortID(entry.id)) — ack + routine generation applied")
        }
        retire(ids: satisfied.map(\.id))
    }

    /// Removes an acknowledged workout. Best effort: if the write fails the
    /// entry stays queued and iOS re-acks the redelivered duplicate, so
    /// retirement converges.
    func retire(id: UUID) {
        retire(ids: [id])
    }

    private func retire(ids: [UUID]) {
        let removed = Set(ids)
        let previousEntries = entries
        let previousAnchors = routineAnchors
        entries.removeAll { removed.contains($0.id) || $0.workoutID.map(removed.contains) == true }
        let before = previousEntries.count
        guard entries.count != before else { return }
        // An anchor exists only to protect unresolved intent for its routine.
        for key in routineAnchors.keys
        where !entries.contains(where: { $0.hasTemplateIntent && $0.routineID?.uuidString == key }) {
            routineAnchors.removeValue(forKey: key)
        }
        do {
            try persist()
        } catch {
            entries = previousEntries
            routineAnchors = previousAnchors
            WatchSyncDiagnostics.error("queue: failed to retire durable entry — \(error.localizedDescription)")
            return
        }
        onEffectiveRoutinesChanged?()
        onTransportEligibilityChanged?()
    }

    // MARK: - Persistence

    private func persist() throws {
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
        let file = WatchSyncStateFile(
            version: 3,
            entries: entries,
            senderEpoch: senderEpoch,
            nextSequenceByRoutine: nextSequenceByRoutine,
            routineAuthority: routineAuthority,
            authoritativeRoutines: authoritativeRoutines,
            routineAnchors: routineAnchors,
            lastRoutineSyncDate: lastRoutineSyncDate,
            hasCompletedLegacyDefaultsMigration: hasCompletedLegacyDefaultsMigration
        )
        let data = try JSONEncoder().encode(file)
        try data.write(to: fileURL, options: .atomic)
        isStateDurable = true
    }

    /// Assigns transaction identities to template entries queued before
    /// ticket 05 (or migrated from the legacy blob), in their existing FIFO
    /// order, so ordering identity is established before any of them is sent.
    @discardableResult
    private func assignMissingTransactionIdentities() -> Bool {
        let pending = entries.indices.filter {
            entries[$0].hasTemplateIntent && entries[$0].templateTransaction == nil
        }
        guard !pending.isEmpty else { return false }
        for index in pending {
            guard var workout = entries[index].completedWorkout else { continue }
            let identity = allocateTransactionIdentity(for: workout.routineId)
            workout.templateTransactionID = UUID()
            workout.templateSenderEpoch = identity.epoch
            workout.templateSequence = identity.sequence
            entries[index].payload = .templateTransaction(
                TemplateTransactionEnvelope(completedWorkout: workout)
            )
        }
        WatchSyncDiagnostics.info("queue: prepared transaction identity for \(pending.count) pre-ticket-05 template transaction(s)")
        return true
    }

    /// Allocates without trapping at `UInt64.max`. Sequence exhaustion starts
    /// a fresh sender epoch and resets every per-routine counter; already
    /// queued envelopes retain their old epoch and remain fully identifiable.
    private func allocateTransactionIdentity(for routineID: UUID) -> (epoch: UUID, sequence: UInt64) {
        let key = routineID.uuidString
        if nextSequenceByRoutine[key] == UInt64.max {
            let newEpoch = UUID()
            senderEpoch = newEpoch
            nextSequenceByRoutine = [key: 1]
            return (newEpoch, 0)
        }
        let epoch = senderEpoch ?? UUID()
        senderEpoch = epoch
        let sequence = nextSequenceByRoutine[key] ?? 0
        nextSequenceByRoutine[key] = sequence + 1
        return (epoch, sequence)
    }

    /// Migrates the pre-ticket-04 UserDefaults queue. Those entries were
    /// created by the old flow (transport attempted immediately after
    /// enqueue), so they enter as `transportEligible` in their original
    /// order. The legacy blob is removed only after the state file committed;
    /// on a failed write it stays the recovery source and migration re-runs
    /// on the next launch (id-deduped).
    private func migrateLegacyEntries(
        from defaults: UserDefaults?
    ) -> (didChange: Bool, isComplete: Bool) {
        guard let defaults else { return (false, false) }
        guard let data = defaults.data(forKey: Self.legacyDefaultsKey) else {
            return (false, true)
        }
        guard let legacy = try? JSONDecoder().decode([CompletedWatchWorkout].self, from: data) else {
            WatchSyncDiagnostics.error("queue: legacy workout queue is undecodable — migration will retry")
            return (false, false)
        }
        guard !legacy.isEmpty else { return (false, true) }
        var didAdd = false
        for workout in legacy where entry(id: workout.id) == nil {
            entries.append(OutgoingSyncEntry(
                payload: .completedWorkout(workout), phase: .transportEligible, enqueuedAt: Date(),
                quarantineReason: nil, heldAck: nil
            ))
            didAdd = true
        }
        return (didAdd, true)
    }

    /// Adopts RoutineStore's pre-ticket-05 UserDefaults cache as the initial
    /// authoritative base, so upgrading does not blank the watch's routine
    /// list while waiting for the next iOS context. The legacy key is left in
    /// place (harmless, and it keeps a downgrade readable).
    private func migrateLegacyRoutines(
        from defaults: UserDefaults?
    ) -> (didChange: Bool, isComplete: Bool) {
        guard authoritativeRoutines == nil else { return (false, true) }
        guard let defaults else { return (false, false) }
        guard let data = defaults.data(forKey: Self.legacyRoutinesKey) else {
            return (false, true)
        }
        guard let legacy = try? JSONDecoder().decode([WatchRoutine].self, from: data) else {
            WatchSyncDiagnostics.error("queue: legacy routine cache is undecodable — migration will retry")
            return (false, false)
        }
        guard !legacy.isEmpty else { return (false, true) }
        authoritativeRoutines = legacy
        WatchSyncDiagnostics.info("queue: adopted \(legacy.count) cached routine(s) as the initial authoritative base")
        return (true, true)
    }
}
