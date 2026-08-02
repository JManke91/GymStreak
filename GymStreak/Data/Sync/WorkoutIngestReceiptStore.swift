//
//  WorkoutIngestReceiptStore.swift
//  GymStreak
//
//  Durable terminal receipts for ingested watch workouts and template
//  transactions (ticket 04, extended by ticket 05 of in-workout routine
//  editing). A receipt is written atomically AFTER the isolated save commits
//  and BEFORE the inbox entry is removed or the transaction is acknowledged,
//  so a redelivered duplicate — including one whose acknowledgment was lost,
//  and one whose history the user has since deleted — is answered from the
//  receipt without re-ingestion.
//
//  Keys (ticket 05): a template transaction's identity is
//  `(senderEpoch, routineID, sequence)` — shared by every template-mutating
//  kind — with the stable transaction ID persisted in the receipt and the
//  workout/external UUID kept only as secondary correlation (a template-only
//  kind is valid without either). A no-template workout keeps its ticket-04
//  workout-id key unchanged, so existing receipts stay readable.
//
//  Representation: one tiny file per receipt, plus a one-line correlation
//  index and a per-routine/epoch sequence file. Append-only with O(1) lookup
//  by filename — deliberately NOT a single monolithic state file, because
//  receipts are retained indefinitely (stale WatchConnectivity delivery has no
//  published lifetime bound, so exact-dedup state must never be pruned without
//  a separately proven compaction scheme) and a monolithic file would become
//  an ever-growing rewrite bottleneck. Performance at large synthetic counts
//  is covered by WatchWorkoutStoresTests.
//

import Foundation

extension TemplateTransactionKey {
    var fileName: String {
        "tx-\(senderEpoch.uuidString)-\(routineID.uuidString)-\(sequence).json"
    }

    /// The per-routine/epoch ledger this transaction is sequenced in.
    var ledgerName: String {
        "seq-\(senderEpoch.uuidString)-\(routineID.uuidString).json"
    }
}

struct WorkoutIngestReceipt: Codable, Equatable {
    enum Phase: String, Codable {
        /// History is committed and the workout requested no template update,
        /// so a plain `workoutAck` fully answers it.
        case readyToAcknowledgeNotRequested
        /// A template transaction reached a terminal outcome locally, but the
        /// authoritative routine context has not been staged yet. Resumes only
        /// authoritative refetch/context staging — never re-mutation.
        case committedAwaitingContext
        /// Terminal outcome plus the exact staged routine epoch/generation.
        /// Acknowledgment-only from here on.
        case readyToAcknowledge
    }

    let workoutId: UUID?
    let healthKitWorkoutId: UUID?
    let phase: Phase
    let recordedAt: Date

    // Template transaction fields (ticket 05); nil for no-template receipts.
    var transactionID: UUID?
    var senderEpoch: UUID?
    var routineID: UUID?
    var sequence: UInt64?
    /// `TemplateTransactionOutcome` raw value.
    var outcomeRaw: String?
    var protocolVersion: Int?
    /// The authoritative routine version staged for this transaction; set with
    /// `readyToAcknowledge`.
    var routineEpoch: UUID?
    var routineGeneration: UInt64?

    var transactionKey: TemplateTransactionKey? {
        guard let senderEpoch, let routineID, let sequence else { return nil }
        return TemplateTransactionKey(senderEpoch: senderEpoch, routineID: routineID, sequence: sequence)
    }

    var outcome: TemplateTransactionOutcome? {
        outcomeRaw.flatMap(TemplateTransactionOutcome.init(rawValue:))
    }
}

@MainActor
final class WorkoutIngestReceiptStore: AppliedOverloadCorrelationReading {
    private let directory: URL?
    private let indexDirectory: URL?
    private let hkIndexDirectory: URL?
    private let sequenceDirectory: URL?
    private let readyRecoveryDirectory: URL?
    /// Ticket 05's applied-overload ledger, in
    /// `WorkoutIngestReceiptStore+OverloadCorrelation.swift`. `nonisolated` so
    /// that extension can read it off the main actor — it is an immutable
    /// `Sendable` value and touches no mutable state.
    nonisolated let overloadCorrelationDirectory: URL?

    /// - Parameter directory: override for tests; defaults to the App Group's
    ///   WatchWorkoutSync/Receipts directory.
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WatchWorkoutInboxStore.appGroupID)?
            .appendingPathComponent("WatchWorkoutSync/Receipts", isDirectory: true)
        self.directory = base
        self.indexDirectory = base?.appendingPathComponent("Index", isDirectory: true)
        self.hkIndexDirectory = base?.appendingPathComponent("HKIndex", isDirectory: true)
        self.sequenceDirectory = base?.appendingPathComponent("Sequences", isDirectory: true)
        self.readyRecoveryDirectory = base?.appendingPathComponent("ReadyRecovery", isDirectory: true)
        self.overloadCorrelationDirectory = base?.appendingPathComponent("OverloadCorrelation", isDirectory: true)
        for url in [
            base, indexDirectory, hkIndexDirectory, sequenceDirectory,
            readyRecoveryDirectory, overloadCorrelationDirectory
        ].compactMap({ $0 }) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Lookup

    /// Receipt for a workout id — the ticket-04 no-template key, or a template
    /// transaction found through its correlation index.
    func receipt(for workoutId: UUID) -> WorkoutIngestReceipt? {
        if let direct = decode(directory?.appendingPathComponent("\(workoutId.uuidString).json")) {
            return direct
        }
        guard let indexURL = indexDirectory?.appendingPathComponent("\(workoutId.uuidString).json"),
              let data = try? Data(contentsOf: indexURL),
              let fileName = String(data: data, encoding: .utf8) else { return nil }
        return decode(directory?.appendingPathComponent(fileName))
    }

    /// Receipt for a template transaction identity — valid without any
    /// workout correlation.
    func receipt(for key: TemplateTransactionKey) -> WorkoutIngestReceipt? {
        decode(directory?.appendingPathComponent(key.fileName))
    }

    /// Receipt correlated to a HealthKit external UUID. Recovery consults this
    /// so a workout that was already ingested — even if the user has since
    /// deleted its history — is never re-offered as a HealthKit-only recovery
    /// candidate (which would resurrect deleted history).
    func receipt(forHealthKitWorkoutId healthKitWorkoutId: UUID) -> WorkoutIngestReceipt? {
        guard let indexURL = hkIndexDirectory?.appendingPathComponent("\(healthKitWorkoutId.uuidString).json"),
              let data = try? Data(contentsOf: indexURL),
              let fileName = String(data: data, encoding: .utf8) else { return nil }
        return decode(directory?.appendingPathComponent(fileName))
    }

    /// Template outcomes that are durable but not yet acknowledged, retained
    /// independently of their inbox entry. Two phases qualify:
    ///
    /// - `readyToAcknowledge` — staged, but a later watch challenge may prove
    ///   the staged authority proposal was never accepted.
    /// - `committedAwaitingContext` — committed locally, but no authoritative
    ///   snapshot could be staged yet (typically because no watch challenge
    ///   was resolvable at the time). Without this, such a receipt was only
    ///   ever retried by an inbox drain, so removing its inbox entry left it
    ///   permanently unacknowledgeable — and the watch's per-routine FIFO head
    ///   permanently unretired.
    func unresolvedTemplateReceipts() -> [WorkoutIngestReceipt] {
        guard let directory, let readyRecoveryDirectory,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: readyRecoveryDirectory, includingPropertiesForKeys: nil
              ) else { return [] }
        return urls
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { String(data: $0, encoding: .utf8) }
            .compactMap { decode(directory.appendingPathComponent($0)) }
            .filter { $0.phase == .readyToAcknowledge || $0.phase == .committedAwaitingContext }
    }

    /// Removes a receipt from authority-change recovery after the watch has
    /// proved that its correlated routine generation applied. The receipt
    /// itself remains indefinitely for O(1) duplicate acknowledgment.
    func markReadyRecoverySatisfied(_ receipt: WorkoutIngestReceipt) {
        guard let key = receipt.transactionKey, let readyRecoveryDirectory else { return }
        do {
            try FileManager.default.removeItem(
                at: readyRecoveryDirectory.appendingPathComponent(key.fileName)
            )
        } catch {
            if (error as NSError).code != NSFileNoSuchFileError {
                // A stale marker causes only another idempotent recovery pass.
                WatchSyncDiagnostics.error("receipts: ready-recovery marker removal failed — \(error.localizedDescription)")
            }
        }
    }

    /// Whether any sequenced transaction outcome is already terminal for a
    /// routine (under any sender epoch). Once one exists, an unsequenced
    /// legacy payload can no longer overwrite known newer template state.
    func hasSequencedOutcome(forRoutine routineID: UUID) -> Bool {
        guard let sequenceDirectory,
              let names = try? FileManager.default.contentsOfDirectory(
                atPath: sequenceDirectory.path) else { return false }
        return names.contains { $0.contains(routineID.uuidString) }
    }

    /// Next sequence expected for a routine within a sender epoch. nil means
    /// no sequenced outcome exists yet for that pair, so the first observed
    /// sequence establishes the ledger (covers a migrated/rebuilt epoch).
    func nextExpectedSequence(for senderEpoch: UUID, routineID: UUID) -> UInt64? {
        let key = TemplateTransactionKey(senderEpoch: senderEpoch, routineID: routineID, sequence: 0)
        guard let url = sequenceDirectory?.appendingPathComponent(key.ledgerName),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(UInt64.self, from: data) else { return nil }
        return value
    }

    // MARK: - Writing

    /// Atomically persists a receipt (and its correlation index). Throws on
    /// failure — the caller must then keep the inbox entry and acknowledge
    /// nothing. Idempotent: re-recording the same key replaces it in place,
    /// which is how a phase advances from `committedAwaitingContext` to
    /// `readyToAcknowledge`.
    func record(_ receipt: WorkoutIngestReceipt) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        guard let fileName = receipt.transactionKey?.fileName
            ?? receipt.workoutId.map({ "\($0.uuidString).json" }) else {
            throw CocoaError(.coderInvalidValue)
        }
        let data = try JSONEncoder().encode(receipt)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)

        // Secondary correlation: workout id → transaction receipt file.
        if receipt.transactionKey != nil, let workoutId = receipt.workoutId, let indexDirectory {
            try Data(fileName.utf8).write(
                to: indexDirectory.appendingPathComponent("\(workoutId.uuidString).json"),
                options: .atomic
            )
        }
        // Correlation: HealthKit external UUID → receipt file, so recovery can
        // prove a workout was already ingested even after its history is gone.
        if let healthKitWorkoutId = receipt.healthKitWorkoutId, let hkIndexDirectory {
            try Data(fileName.utf8).write(
                to: hkIndexDirectory.appendingPathComponent("\(healthKitWorkoutId.uuidString).json"),
                options: .atomic
            )
        }
        // Retained receipts are append-only, but authority recovery must stay
        // proportional to unresolved work rather than scanning all history.
        // This tiny marker is removed once the watch proves the generation.
        // `committedAwaitingContext` carries one too: it is unresolved work by
        // definition, and it is the phase a transaction parks in when no
        // authoritative snapshot could be staged.
        if receipt.phase == .readyToAcknowledge || receipt.phase == .committedAwaitingContext,
           receipt.transactionKey != nil,
           let readyRecoveryDirectory {
            try Data(fileName.utf8).write(
                to: readyRecoveryDirectory.appendingPathComponent(fileName),
                options: .atomic
            )
        }
    }

    /// Advances the per-routine/epoch expected sequence. Called only after a
    /// terminal outcome is durable, so a transient failure never lets a later
    /// transaction skip ahead of an unprocessed one.
    func advanceExpectedSequence(for key: TemplateTransactionKey) throws {
        guard let sequenceDirectory else { throw CocoaError(.fileNoSuchFile) }
        let current = nextExpectedSequence(for: key.senderEpoch, routineID: key.routineID) ?? 0
        guard key.sequence < UInt64.max else { throw CocoaError(.coderInvalidValue) }
        let next = max(current, key.sequence + 1)
        let data = try JSONEncoder().encode(next)
        try data.write(to: sequenceDirectory.appendingPathComponent(key.ledgerName), options: .atomic)
    }

    private func decode(_ url: URL?) -> WorkoutIngestReceipt? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WorkoutIngestReceipt.self, from: data)
    }
}
