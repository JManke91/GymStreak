//
//  WatchTemplateTransactionModels.swift
//  GymStreak
//
//  Durable and wire-level transaction models shared with the watch copy.
//  Keep this file aligned with the watch target's copy.
//

import Foundation

struct TemplateTransactionKey: Hashable {
    let senderEpoch: UUID
    let routineID: UUID
    let sequence: UInt64
}

enum WatchWorkoutWire {
    static let payloadKey = "completedWorkout"
    static let templateTransactionKey = "templateTransaction"
    static let workoutIdKey = "workoutId"
    static let transactionIdKey = "templateTransactionId"
    static let ackKey = "workoutAck"
    static let queueDrainRequestKey = "requestWorkoutQueueDrain"
    static let queueDrainRequestVersion = "1"

    static var queueDrainRequestPayload: [String: Any] {
        [queueDrainRequestKey: queueDrainRequestVersion]
    }

    static func isQueueDrainRequest(_ payload: [String: Any]) -> Bool {
        payload[queueDrainRequestKey] as? String == queueDrainRequestVersion
    }
}

enum TemplateTransactionOutcomeWire: String, Codable {
    case applied
    case rejected
}

/// The extensible payload carried by the shared per-routine transaction
/// protocol. Ticket 05 implements only the completed-workout kind; later kinds
/// extend this enum and automatically reuse the same queue and authority.
enum TemplateTransactionPayload: Codable {
    case completedWorkoutUpdate(CompletedWatchWorkout)

    var completedWorkout: CompletedWatchWorkout? {
        switch self {
        case .completedWorkoutUpdate(let workout): workout
        }
    }
}

/// The durable unit for every template mutation. Workout identity is optional
/// correlation; ordering and deduplication always use this envelope's own
/// identity.
struct TemplateTransactionEnvelope: Codable {
    let transactionID: UUID
    let senderEpoch: UUID
    let routineID: UUID
    let sequence: UInt64
    let workoutID: UUID?
    let payload: TemplateTransactionPayload

    init(completedWorkout: CompletedWatchWorkout) {
        precondition(completedWorkout.shouldUpdateTemplate)
        precondition(completedWorkout.templateTransactionID != nil)
        precondition(completedWorkout.templateSenderEpoch != nil)
        precondition(completedWorkout.templateSequence != nil)
        self.transactionID = completedWorkout.templateTransactionID!
        self.senderEpoch = completedWorkout.templateSenderEpoch!
        self.routineID = completedWorkout.routineId
        self.sequence = completedWorkout.templateSequence!
        self.workoutID = completedWorkout.id
        self.payload = .completedWorkoutUpdate(completedWorkout)
    }

    init(
        transactionID: UUID,
        senderEpoch: UUID,
        routineID: UUID,
        sequence: UInt64,
        workoutID: UUID?,
        payload: TemplateTransactionPayload
    ) {
        self.transactionID = transactionID
        self.senderEpoch = senderEpoch
        self.routineID = routineID
        self.sequence = sequence
        self.workoutID = workoutID
        self.payload = payload
    }

    var key: TemplateTransactionKey {
        TemplateTransactionKey(senderEpoch: senderEpoch, routineID: routineID, sequence: sequence)
    }

    var completedWorkout: CompletedWatchWorkout? { payload.completedWorkout }

    var isInternallyConsistent: Bool {
        guard let workout = completedWorkout else { return workoutID == nil }
        return workout.shouldUpdateTemplate
            && workoutID == workout.id
            && routineID == workout.routineId
            && transactionID == workout.templateTransactionID
            && senderEpoch == workout.templateSenderEpoch
            && sequence == workout.templateSequence
    }
}

enum OutgoingSyncPayload: Codable {
    /// A no-template workout, or a pre-ticket-05 template workout awaiting
    /// atomic migration into `templateTransaction`.
    case completedWorkout(CompletedWatchWorkout)
    case templateTransaction(TemplateTransactionEnvelope)
}

enum OutgoingWorkoutPhase: String, Codable {
    case awaitingHealthKitMetadata
    case awaitingHealthKitFinish
    case transportEligible
    case quarantined
}

struct OutgoingSyncEntry: Codable {
    var payload: OutgoingSyncPayload
    var phase: OutgoingWorkoutPhase
    var enqueuedAt: Date
    var quarantineReason: String?
    var heldAck: TemplateAckRecord?

    var completedWorkout: CompletedWatchWorkout? {
        switch payload {
        case .completedWorkout(let workout): workout
        case .templateTransaction(let transaction): transaction.completedWorkout
        }
    }

    var templateTransaction: TemplateTransactionEnvelope? {
        guard case .templateTransaction(let transaction) = payload else { return nil }
        return transaction
    }

    var id: UUID {
        templateTransaction?.transactionID ?? completedWorkout!.id
    }

    var workoutID: UUID? { templateTransaction?.workoutID ?? completedWorkout?.id }
    var routineID: UUID? { templateTransaction?.routineID ?? completedWorkout?.routineId }

    var hasTemplateIntent: Bool {
        templateTransaction != nil || completedWorkout?.shouldUpdateTemplate == true
    }

    var hasDurableTemplateIdentity: Bool {
        !hasTemplateIntent || templateTransaction != nil
    }

    private enum CodingKeys: String, CodingKey {
        case payload, workout, phase, enqueuedAt, quarantineReason, heldAck
    }

    init(
        payload: OutgoingSyncPayload,
        phase: OutgoingWorkoutPhase,
        enqueuedAt: Date,
        quarantineReason: String?,
        heldAck: TemplateAckRecord?
    ) {
        self.payload = payload
        self.phase = phase
        self.enqueuedAt = enqueuedAt
        self.quarantineReason = quarantineReason
        self.heldAck = heldAck
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let payload = try container.decodeIfPresent(OutgoingSyncPayload.self, forKey: .payload) {
            self.payload = payload
        } else {
            // v1/v2 queue entries stored a CompletedWatchWorkout directly.
            self.payload = .completedWorkout(try container.decode(CompletedWatchWorkout.self, forKey: .workout))
        }
        self.phase = try container.decode(OutgoingWorkoutPhase.self, forKey: .phase)
        self.enqueuedAt = try container.decode(Date.self, forKey: .enqueuedAt)
        self.quarantineReason = try container.decodeIfPresent(String.self, forKey: .quarantineReason)
        self.heldAck = try container.decodeIfPresent(TemplateAckRecord.self, forKey: .heldAck)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(payload, forKey: .payload)
        try container.encode(phase, forKey: .phase)
        try container.encode(enqueuedAt, forKey: .enqueuedAt)
        try container.encodeIfPresent(quarantineReason, forKey: .quarantineReason)
        try container.encodeIfPresent(heldAck, forKey: .heldAck)
    }
}
