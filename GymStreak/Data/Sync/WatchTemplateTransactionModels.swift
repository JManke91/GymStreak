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

/// The template intent a user accepted during a workout, travelling on its own
/// (ADR 0001). The workout history it belongs to rides as an ordinary, ungated
/// workout payload with the same workout id, so a template transaction that
/// cannot be acknowledged can never withhold the workout itself.
///
/// It wraps the WHOLE completed workout deliberately: the iOS merge and the
/// history dedupe stay the already-exercised `execute` path, at the cost of a
/// few duplicated KB on the wire.
struct WatchWorkoutTemplateIntent: Codable {
    let workout: CompletedWatchWorkout
    /// The workout whose history travels as its own sync entry. Always
    /// `workout.id`; carried here because the ENVELOPE's `workoutID` must stay
    /// nil for this kind (see `isInternallyConsistent`).
    let sourceWorkoutID: UUID

    init(workout: CompletedWatchWorkout) {
        self.workout = workout
        self.sourceWorkoutID = workout.id
    }
}

/// The extensible payload carried by the shared per-routine transaction
/// protocol. Ticket 05 implements only the completed-workout kind; later kinds
/// extend this enum and automatically reuse the same queue and authority.
enum TemplateTransactionPayload: Codable {
    case completedWorkoutUpdate(CompletedWatchWorkout)
    /// Template-only kind (progressive-overload ticket 04). Carries no history
    /// and no workout correlation — see `isInternallyConsistent`, which
    /// requires `workoutID == nil` for every payload without a workout.
    case progressiveOverload(WatchProgressiveOverloadIntent)
    /// Template-only kind carrying a copy of the workout it was accepted in
    /// (ADR 0001). History for that workout travels separately, so this kind
    /// deliberately does NOT surface through `completedWorkout`.
    case workoutTemplateIntent(WatchWorkoutTemplateIntent)

    /// Non-nil only when this payload CARRIES the workout history. Split
    /// template intent wraps a workout without owning its history, so it stays
    /// nil here: `OutgoingSyncEntry.workoutID` derives from this accessor, and
    /// a non-nil value would make the watch's `entry(id:)` collapse a workout's
    /// two sync entries into one.
    var completedWorkout: CompletedWatchWorkout? {
        switch self {
        case .completedWorkoutUpdate(let workout): workout
        case .progressiveOverload, .workoutTemplateIntent: nil
        }
    }

    /// The workout a split template intent was accepted in, for the only two
    /// consumers that legitimately need it: the routine merge on iOS and the
    /// optimistic fold on the watch. Never a claim that this entry carries
    /// history — use `completedWorkout` for that.
    var templateIntentWorkout: CompletedWatchWorkout? {
        switch self {
        case .workoutTemplateIntent(let intent): intent.workout
        case .completedWorkoutUpdate, .progressiveOverload: nil
        }
    }

    var progressiveOverload: WatchProgressiveOverloadIntent? {
        switch self {
        case .progressiveOverload(let intent): intent
        case .completedWorkoutUpdate, .workoutTemplateIntent: nil
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

    /// The template half of a split workout (ADR 0001): the same ordering
    /// identity the fused kind would have used, but with `workoutID` nil so the
    /// history entry enqueued for the same workout stays a separate sync entry.
    init(templateIntentFor workout: CompletedWatchWorkout) {
        precondition(workout.shouldUpdateTemplate)
        precondition(workout.templateTransactionID != nil)
        precondition(workout.templateSenderEpoch != nil)
        precondition(workout.templateSequence != nil)
        self.transactionID = workout.templateTransactionID!
        self.senderEpoch = workout.templateSenderEpoch!
        self.routineID = workout.routineId
        self.sequence = workout.templateSequence!
        self.workoutID = nil
        self.payload = .workoutTemplateIntent(WatchWorkoutTemplateIntent(workout: workout))
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

    var templateIntentWorkout: CompletedWatchWorkout? { payload.templateIntentWorkout }

    var isInternallyConsistent: Bool {
        // Split template intent: the envelope must carry NO workout
        // correlation (the history for that workout is its own sync entry),
        // but its ordering identity must still match the workout it was
        // accepted in — that identity is the witness the iOS merge writes.
        if case .workoutTemplateIntent(let intent) = payload {
            return workoutID == nil
                && intent.sourceWorkoutID == intent.workout.id
                && matchesTemplateIdentity(of: intent.workout)
        }
        guard let workout = completedWorkout else { return workoutID == nil }
        return workoutID == workout.id && matchesTemplateIdentity(of: workout)
    }

    private func matchesTemplateIdentity(of workout: CompletedWatchWorkout) -> Bool {
        workout.shouldUpdateTemplate
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

    /// The workout whose history this entry carries — nil for every
    /// template-only kind, including split template intent (which wraps a copy
    /// of a workout it does not own). `entry(id:)`, `advance`, `quarantine` and
    /// `retire` all match on this, so a non-nil value for a template-only kind
    /// would silently collapse a split workout's two entries into one.
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
