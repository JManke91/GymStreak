//
//  RoutineSyncAuthority.swift
//  GymStreak
//
//  The single serialized owner of routine `applicationContext` generations
//  (ticket 05, in-workout routine editing). Every routine snapshot the watch
//  receives — ordinary list syncs and the authoritative post-commit snapshot
//  of a template transaction — is versioned here, so a delayed old context can
//  never regress the watch and a terminal acknowledgment can name the exact
//  generation it staged.
//
//  Authority follows the receiver-authorized principle established by the
//  exercise-catalogue sync (ticket 03): recency is comparable only within one
//  epoch, and an unknown epoch is accepted by the watch only through a
//  one-shot handover bound to the watch's exact published challenge tuple. A
//  previously persisted authority is never re-proposed — the watch may have
//  retired it.
//
//  State is one atomically replaced Application Support file, written BEFORE
//  the context is handed to WatchConnectivity, so a relaunch never reuses a
//  generation it already gave away.
//

import Foundation

/// The watch's published routine acceptance state (watch → iOS
/// applicationContext). nil-initialized when the keys are absent (older watch
/// build) or malformed.
struct WatchRoutineChallenge: Codable, Equatable {
    let watchInstanceID: UUID
    /// nil while the watch has never accepted a versioned routine snapshot.
    let currentEpoch: UUID?
    let currentGeneration: UInt64
    let handoverNonce: UUID

    init?(applicationContext: [String: Any]) {
        guard
            let instanceString = applicationContext[WatchRoutineSync.challengeWatchInstanceIDKey] as? String,
            let instanceID = UUID(uuidString: instanceString),
            let generationString = applicationContext[WatchRoutineSync.challengeCurrentGenerationKey] as? String,
            let generation = UInt64(generationString),
            let nonceString = applicationContext[WatchRoutineSync.challengeNonceKey] as? String,
            let nonce = UUID(uuidString: nonceString)
        else { return nil }
        self.watchInstanceID = instanceID
        self.currentEpoch = (applicationContext[WatchRoutineSync.challengeCurrentEpochKey] as? String)
            .flatMap(UUID.init(uuidString:))
        self.currentGeneration = generation
        self.handoverNonce = nonce
    }
}

/// Persisted authority state. Mirrors `ExerciseCatalogSenderState`'s proven
/// shape (active epoch + next generation + challenge-bound proposal).
struct RoutineSyncAuthorityState: Codable {
    struct ProposedAuthority: Codable, Equatable {
        let epoch: UUID
        /// The exact challenge tuple this proposal is bound to — a changed
        /// tuple must allocate a new proposal.
        let challenge: WatchRoutineChallenge
    }

    /// The epoch the watch last reported back as current. nil until bootstrap.
    var activeAuthorityEpoch: UUID?
    /// Next generation to allocate within `activeAuthorityEpoch`.
    var nextGeneration: UInt64 = 1
    var proposedAuthority: ProposedAuthority?
}

/// What the authority needs from WCSession. Implemented by
/// `WatchConnectivityManager`; tests inject a recording double.
@MainActor
protocol RoutineContextTransporting: AnyObject {
    /// Hands a fully built context dictionary to
    /// `updateApplicationContext`. Throws exactly what WCSession throws.
    func sendRoutineContext(_ context: [String: Any]) throws
}

@MainActor
final class RoutineSyncAuthority {
    private var state: RoutineSyncAuthorityState
    private var challenge: WatchRoutineChallenge?
    private let stateURL: URL?
    private unowned let transport: RoutineContextTransporting

    /// Last routines payload actually handed to WatchConnectivity — in-memory
    /// only, so every launch resends once. Suppresses identical re-syncs (e.g.
    /// from CloudKit remote-change storms).
    private var lastSentRoutinesPayload: Data?

    init(transport: RoutineContextTransporting, directory: URL? = nil) {
        self.transport = transport
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RoutineSync", isDirectory: true)
        if let base { try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true) }
        self.stateURL = base?.appendingPathComponent("authority.json")
        if let stateURL, let data = try? Data(contentsOf: stateURL),
           let decoded = try? JSONDecoder().decode(RoutineSyncAuthorityState.self, from: data) {
            self.state = decoded
        } else {
            self.state = RoutineSyncAuthorityState()
        }
    }

    /// The watch's last published challenge, for callers that must know
    /// whether an authority exists at all.
    var publishedChallenge: (epoch: UUID?, generation: UInt64)? {
        challenge.map { ($0.currentEpoch, $0.currentGeneration) }
    }

    /// Records the watch's challenge from a received applicationContext. When
    /// the watch reports our proposed epoch as its current one, the proposal
    /// is promoted to the active authority.
    func updateChallenge(fromApplicationContext context: [String: Any]) {
        guard let received = WatchRoutineChallenge(applicationContext: context) else { return }
        let previous = challenge
        challenge = received
        let previousState = state

        if let proposal = state.proposedAuthority, received.currentEpoch == proposal.epoch {
            state.activeAuthorityEpoch = proposal.epoch
            state.proposedAuthority = nil
            // The watch is at `currentGeneration` within the accepted epoch;
            // never hand out a generation it would reject as stale.
            let receiverNext = received.currentGeneration == UInt64.max
                ? UInt64.max : received.currentGeneration + 1
            state.nextGeneration = max(state.nextGeneration, receiverNext)
            print("RoutineSync: watch accepted authority \(proposal.epoch) at generation \(received.currentGeneration)")
        } else if let active = state.activeAuthorityEpoch, received.currentEpoch == active,
                  received.currentGeneration >= state.nextGeneration {
            // Restored iOS backup: the watch is ahead of our counter.
            state.nextGeneration = received.currentGeneration == UInt64.max
                ? UInt64.max : received.currentGeneration + 1
        } else if let proposal = state.proposedAuthority,
                  proposal.challenge != received,
                  received.currentEpoch != proposal.epoch {
            // The receiver changed/rotated the exact challenge without
            // accepting this proposal. It can never become valid again.
            state.proposedAuthority = nil
        }
        if stateDiffers(from: previousState) {
            do {
                try persist()
            } catch {
                state = previousState
                print("RoutineSync: failed to persist challenge state — \(error.localizedDescription)")
            }
        }
        if previous != received { print("RoutineSync: routine challenge updated") }
    }

    /// Sends an ordinary routine snapshot, suppressing identical repeats.
    /// Returns the staged version, or nil when nothing was sent.
    @discardableResult
    func sendOrdinary(_ routines: [WatchRoutine]) -> (epoch: UUID, generation: UInt64)? {
        guard let payload = Self.encode(routines) else {
            print("RoutineSync: failed to encode routines")
            return nil
        }
        guard payload != lastSentRoutinesPayload else { return nil }
        guard challenge != nil else {
            // Mixed-version compatibility: an old watch never publishes the
            // ticket-05 challenge, but still understands the routines payload.
            do {
                try transport.sendRoutineContext([WatchRoutineSync.contextRoutinesKey: payload])
                lastSentRoutinesPayload = payload
            } catch {
                print("RoutineSync: failed to send legacy routine context — \(error.localizedDescription)")
            }
            return nil
        }
        return send(payload: payload)
    }

    /// Sends an authoritative post-commit snapshot for a template
    /// transaction. Never suppressed: the acknowledgment must be able to name
    /// the generation the watch will apply, even when the routine bytes are
    /// unchanged (a deliberately rejected transaction leaves the routine
    /// untouched but still needs a correlated generation).
    @discardableResult
    func sendAuthoritative(_ routines: [WatchRoutine]) -> (epoch: UUID, generation: UInt64)? {
        guard let payload = Self.encode(routines) else {
            print("RoutineSync: failed to encode authoritative routines")
            return nil
        }
        return send(payload: payload)
    }

    /// Clears the identical-content suppression so a newly installed, switched
    /// or reactivated watch receives the current routines again.
    func resetSuppression() {
        lastSentRoutinesPayload = nil
    }

    // MARK: - Sending

    private func send(payload: Data) -> (epoch: UUID, generation: UInt64)? {
        // No challenge means no authority can be established yet: the watch
        // has never told us who it is, so a proposal could not be bound to it.
        guard let challenge else {
            print("RoutineSync: no watch challenge yet — routine context withheld")
            return nil
        }

        var context: [String: Any] = [WatchRoutineSync.contextRoutinesKey: payload]
        let epoch: UUID
        let generation: UInt64

        if let active = state.activeAuthorityEpoch, challenge.currentEpoch == active {
            epoch = active
            // The watch's own high-water always wins over a restored counter.
            guard challenge.currentGeneration < UInt64.max,
                  state.nextGeneration < UInt64.max else {
                // Overflow: start a fresh authorized epoch instead of wrapping.
                return proposeHandover(context: context, challenge: challenge)
            }
            generation = max(state.nextGeneration, challenge.currentGeneration + 1)
            guard generation < UInt64.max else {
                return proposeHandover(context: context, challenge: challenge)
            }
        } else {
            return proposeHandover(context: context, challenge: challenge)
        }

        context[WatchRoutineSync.contextEpochKey] = epoch.uuidString
        context[WatchRoutineSync.contextGenerationKey] = String(generation)

        let previousState = state
        state.nextGeneration = generation + 1
        do {
            try persist()
        } catch {
            state = previousState
            print("RoutineSync: failed to persist generation — \(error.localizedDescription)")
            return nil
        }
        do {
            try transport.sendRoutineContext(context)
        } catch {
            // The transport may have accepted the context before surfacing an
            // error. Keep the generation consumed so relaunch/retry can never
            // reuse an authority version already handed across the boundary.
            print("RoutineSync: failed to send routine context — \(error.localizedDescription)")
            return nil
        }
        lastSentRoutinesPayload = payload
        return (epoch, generation)
    }

    /// Proposes a fresh epoch bound to this exact challenge tuple. A
    /// previously persisted proposal is reused only while the challenge it was
    /// bound to is unchanged — the watch may have retired anything else.
    private func proposeHandover(
        context: [String: Any],
        challenge: WatchRoutineChallenge
    ) -> (epoch: UUID, generation: UInt64)? {
        var context = context
        let proposal: RoutineSyncAuthorityState.ProposedAuthority
        if let existing = state.proposedAuthority, existing.challenge == challenge {
            proposal = existing
        } else {
            proposal = .init(epoch: UUID(), challenge: challenge)
        }
        let generation: UInt64 = 1

        context[WatchRoutineSync.contextEpochKey] = proposal.epoch.uuidString
        context[WatchRoutineSync.contextGenerationKey] = String(generation)
        context[WatchRoutineSync.contextTargetWatchInstanceIDKey] = challenge.watchInstanceID.uuidString
        if let from = challenge.currentEpoch {
            context[WatchRoutineSync.contextFromEpochKey] = from.uuidString
        }
        context[WatchRoutineSync.contextHandoverNonceKey] = challenge.handoverNonce.uuidString

        let previous = state.proposedAuthority
        state.proposedAuthority = proposal
        do {
            try persist()
        } catch {
            state.proposedAuthority = previous
            print("RoutineSync: failed to persist authority proposal — \(error.localizedDescription)")
            return nil
        }
        do {
            try transport.sendRoutineContext(context)
        } catch {
            // Keep the challenge-bound proposal durable. Retrying the same
            // proposal/generation is idempotent; a changed challenge replaces
            // it in `updateChallenge`.
            print("RoutineSync: failed to send handover context — \(error.localizedDescription)")
            return nil
        }
        if let payload = context[WatchRoutineSync.contextRoutinesKey] as? Data {
            lastSentRoutinesPayload = payload
        }
        print("RoutineSync: proposed authority \(proposal.epoch) to watch \(challenge.watchInstanceID)")
        return (proposal.epoch, generation)
    }

    /// Deterministic encoding (sorted keys) so identical routine content
    /// always produces identical bytes — the basis of duplicate suppression.
    static func encode(_ routines: [WatchRoutine]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(routines)
    }

    private func persist() throws {
        guard let stateURL else { throw CocoaError(.fileNoSuchFile) }
        let data = try JSONEncoder().encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    private func stateDiffers(from other: RoutineSyncAuthorityState) -> Bool {
        state.activeAuthorityEpoch != other.activeAuthorityEpoch
            || state.nextGeneration != other.nextGeneration
            || state.proposedAuthority != other.proposedAuthority
    }
}
