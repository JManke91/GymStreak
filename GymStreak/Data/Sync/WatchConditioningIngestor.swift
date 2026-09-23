//
//  WatchConditioningIngestor.swift
//  GymStreak
//
//  Records a conditioning session finished on the watch in History (ticket 07,
//  docs/fight-conditioning.md). Idempotent by the session id — which is also the
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

    /// Ids ever ingested. A record alone is not enough: a redelivery arriving after
    /// the user deleted the session would bring it back.
    static let receiptsKey = "conditioning.watchSessionReceipts"

    private let records: any ConditioningRecordRepository
    private let defaults: UserDefaults

    init(records: any ConditioningRecordRepository, defaults: UserDefaults = .standard) {
        self.records = records
        self.defaults = defaults
    }

    func ingest(_ session: WatchCompletedConditioningSession) -> Outcome {
        let id = session.id.uuidString
        var receipts = defaults.stringArray(forKey: Self.receiptsKey) ?? []
        if receipts.contains(id) {
            return .duplicate
        }
        if records.find(id: session.id) != nil {
            receipts.append(id)
            defaults.set(receipts, forKey: Self.receiptsKey)
            return .duplicate
        }

        let record = WatchConditioningMapper.record(from: session)
        records.insert(record)
        do {
            try records.save()
        } catch {
            records.delete(record)
            WatchSyncDiagnostics.error("phone: failed to save watch conditioning session \(WatchSyncDiagnostics.shortID(session.id)) — \(error.localizedDescription)")
            return .failed
        }
        receipts.append(id)
        defaults.set(receipts, forKey: Self.receiptsKey)
        return .inserted
    }
}
