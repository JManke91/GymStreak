//
//  WatchConditioningIngestor.swift
//  GymStreak
//
//  Records a conditioning session (ticket 07) or a mat session (positioning
//  ticket 05) finished on the watch in History (docs/fight-conditioning.md). Idempotent by the session id — which is also the
//  Apple Health external UUID — because WatchConnectivity may deliver the same
//  transfer more than once and the watch resends until it sees an ack.
//
//  Never touches HealthKit: the watch already saved that workout.
//

import Foundation

@MainActor
final class WatchConditioningIngestor {

    enum Outcome: Equatable {
        case inserted
        /// Already recorded — or recorded once and deleted since. Acknowledge, change nothing.
        case duplicate
        /// Not persisted; do not acknowledge, the watch sends it again.
        case failed
    }

    /// Ids ever ingested — conditioning and mat sessions alike, since both are keyed by
    /// a fresh UUID. A record alone is not enough: a redelivery arriving after the user
    /// deleted the session would bring it back.
    static let receiptsKey = "conditioning.watchSessionReceipts"

    private let records: any ConditioningRecordRepository
    private let matSessions: any MatSessionRepository
    private let defaults: UserDefaults

    init(
        records: any ConditioningRecordRepository,
        matSessions: any MatSessionRepository,
        defaults: UserDefaults = .standard
    ) {
        self.records = records
        self.matSessions = matSessions
        self.defaults = defaults
    }

    func ingest(_ session: WatchCompletedConditioningSession) -> Outcome {
        ingest(id: session.id, isRecorded: records.find(id: session.id) != nil) {
            let record = WatchConditioningMapper.record(from: session)
            records.insert(record)
            do {
                try records.save()
                return true
            } catch {
                records.delete(record)
                WatchSyncDiagnostics.error("phone: failed to save watch conditioning session \(WatchSyncDiagnostics.shortID(session.id)) — \(error.localizedDescription)")
                return false
            }
        }
    }

    /// A mat session recorded on the watch (positioning ticket 05): the same
    /// idempotency, into the same `MatSession` type the iPhone logs.
    func ingest(_ session: WatchCompletedMatSession) -> Outcome {
        ingest(id: session.id, isRecorded: matSessions.find(id: session.id) != nil) {
            let record = WatchConditioningMapper.matSession(from: session)
            matSessions.insert(record)
            do {
                try matSessions.save()
                return true
            } catch {
                matSessions.delete(record)
                WatchSyncDiagnostics.error("phone: failed to save watch mat session \(WatchSyncDiagnostics.shortID(session.id)) — \(error.localizedDescription)")
                return false
            }
        }
    }

    private func ingest(id: UUID, isRecorded: Bool, persist: () -> Bool) -> Outcome {
        var receipts = defaults.stringArray(forKey: Self.receiptsKey) ?? []
        if receipts.contains(id.uuidString) {
            return .duplicate
        }
        if isRecorded {
            receipts.append(id.uuidString)
            defaults.set(receipts, forKey: Self.receiptsKey)
            return .duplicate
        }
        guard persist() else { return .failed }
        receipts.append(id.uuidString)
        defaults.set(receipts, forKey: Self.receiptsKey)
        return .inserted
    }
}
