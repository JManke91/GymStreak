//
//  ExerciseCatalogStore.swift
//  GymStreakWatch Watch App
//
//  Watch-side owner of the synced exercise catalogue (ticket 03, in-workout
//  routine editing). Sibling of RoutineStore, but with file-based persistence:
//  one atomically replaced App Group state file holding the last-good snapshot
//  plus the acceptance state (epoch/generation/nonce — see
//  WatchExerciseCatalogReceiverState in WatchExerciseCatalogModels.swift).
//
//  Received transfer files first land in an owned App Group inbox (moved there
//  synchronously by the WCSessionDelegate callback) and count as processed
//  only once the state-file replacement commits. Routine persistence stays in
//  RoutineStore — this store never touches routines.
//

import Foundation
import Combine

// MARK: - Inbox (nonisolated)

/// The delegate's `session(_:didReceive:)` runs nonisolated and the received
/// temporary file only survives until the callback returns — an in-memory copy
/// could still be lost to suspension before persistence. This helper moves the
/// file into our owned inbox synchronously, before the callback returns.
enum ExerciseCatalogInbox {
    static let appGroupID = "group.com.gymstreak.shared"

    static func directory(in container: URL?) -> URL? {
        (container ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID))?
            .appendingPathComponent("ExerciseCatalog/Inbox", isDirectory: true)
    }

    /// Moves a received transfer file to a unique URL in the owned inbox.
    /// The filename encodes arrival time so the serialized drain preserves
    /// delivery order. Returns false when the move fails (previous cache is
    /// kept; the sender's retained snapshot + lifecycle retries recover).
    @discardableResult
    static func storeIncomingFile(from temporaryURL: URL) -> Bool {
        guard let inbox = directory(in: nil) else {
            print("ExerciseCatalogInbox: App Group container unavailable")
            return false
        }
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let name = String(format: "%017.6f", Date().timeIntervalSince1970) + "-" + UUID().uuidString + ".json"
            try FileManager.default.moveItem(at: temporaryURL, to: inbox.appendingPathComponent(name))
            return true
        } catch {
            print("ExerciseCatalogInbox: failed to move received file — \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Store

@MainActor
final class ExerciseCatalogStore: ObservableObject {
    /// Last valid catalogue. Empty both when never synced and when the iOS
    /// library is validly empty — distinguish via `hasReceivedCatalog`.
    @Published private(set) var items: [WatchExerciseCatalogItem] = []
    /// True once a valid snapshot was committed — NOT `!items.isEmpty`.
    @Published private(set) var hasReceivedCatalog = false
    @Published private(set) var lastSyncDate: Date?

    var lastSnapshotID: UUID? { state.lastSnapshotID }
    var lastAuthorityEpoch: UUID? { state.acceptedEpoch }
    var lastGeneration: UInt64 { state.acceptedGeneration }

    /// Set by WatchConnectivityManager: republishes the challenge context
    /// after a commit changed it (bootstrap persistence or accepted handover).
    var onChallengeStateChanged: (() -> Void)?

    private(set) var state: WatchExerciseCatalogReceiverState
    /// The challenge may only be published once its nonce is durably persisted.
    private var isStatePersisted = false

    private let stateFileURL: URL?
    private let inboxDirectory: URL?
    private var isDraining = false
    private var needsAnotherDrain = false

    /// - Parameter directory: override for tests; defaults to the App Group's
    ///   ExerciseCatalog directory.
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ExerciseCatalogInbox.appGroupID)?
            .appendingPathComponent("ExerciseCatalog", isDirectory: true)
        self.stateFileURL = base?.appendingPathComponent("state.json")
        self.inboxDirectory = base?.appendingPathComponent("Inbox", isDirectory: true)
        if let base { try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true) }

        if let stateFileURL,
           let data = try? Data(contentsOf: stateFileURL),
           let loaded = try? JSONDecoder().decode(WatchExerciseCatalogReceiverState.self, from: data) {
            self.state = loaded
            self.isStatePersisted = true
        } else {
            self.state = .initial()
        }
        ensureStatePersisted()
        publishState()
        print("ExerciseCatalogStore: loaded state — items: \(state.items.map { String($0.count) } ?? "never-synced"), epoch: \(state.acceptedEpoch?.uuidString ?? "none"), generation: \(state.acceptedGeneration), lastSync: \(state.lastSyncDate?.description ?? "-")")
        drainInbox()
    }

    /// The context to publish to iOS — nil until the nonce is durably stored
    /// (publishing an unpersisted nonce could authorize a handover the watch
    /// forgets after a crash).
    var publishableChallengeContext: [String: String]? {
        ensureStatePersisted()
        return isStatePersisted ? state.challengeContext : nil
    }

    // MARK: - Inbox drain (the single serialized catalogue processor)

    /// Serially validates and applies every inbox file, oldest first. Runs
    /// synchronously on the main actor — when it returns, all persistence for
    /// currently present files is finished (or intentionally deferred).
    func drainInbox() {
        guard !isDraining else {
            needsAnotherDrain = true
            return
        }
        isDraining = true
        defer {
            isDraining = false
            if needsAnotherDrain {
                needsAnotherDrain = false
                drainInbox()
            }
        }

        guard let inboxDirectory else { return }
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: inboxDirectory, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in files {
            process(url)
        }
    }

    private func process(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            // Transient read failure — keep the file replayable for the next drain.
            print("ExerciseCatalogStore: could not read inbox file \(url.lastPathComponent) — will retry")
            return
        }

        let snapshot: WatchExerciseCatalogSnapshot
        do {
            snapshot = try JSONDecoder().decode(WatchExerciseCatalogSnapshot.self, from: data)
        } catch {
            // Malformed/unsupported content is terminal for this delivery:
            // quarantine-delete after diagnostics, keep the last good cache.
            print("ExerciseCatalogStore: malformed catalogue file — \(error.localizedDescription). Deleted.")
            try? FileManager.default.removeItem(at: url)
            return
        }

        switch state.decision(for: snapshot) {
        case .duplicate:
            try? FileManager.default.removeItem(at: url)

        case .reject(let reason):
            // Unauthorized/stale deliveries are terminally deleted; their
            // sender must restage against the currently published challenge.
            print("ExerciseCatalogStore: rejected snapshot \(snapshot.snapshotID) (\(reason.rawValue), epoch \(snapshot.authorityEpoch), generation \(snapshot.generation))")
            try? FileManager.default.removeItem(at: url)

        case .apply(let isHandover):
            var newState = state
            newState.accept(snapshot, isHandover: isHandover, at: Date())
            do {
                try persist(newState)
            } catch {
                // Transient persistence failure: previous cache stays, inbox
                // file stays replayable.
                print("ExerciseCatalogStore: state persistence failed — \(error.localizedDescription). Keeping \(url.lastPathComponent) for retry.")
                return
            }
            state = newState
            isStatePersisted = true
            publishState()
            // The file counts as processed only after the commit above.
            try? FileManager.default.removeItem(at: url)
            print("ExerciseCatalogStore: applied snapshot \(snapshot.snapshotID) — \(snapshot.items.count) items, epoch \(snapshot.authorityEpoch), generation \(snapshot.generation), handover: \(isHandover)")
            if isHandover {
                onChallengeStateChanged?()
            }
        }
    }

    // MARK: - Persistence

    private func persist(_ newState: WatchExerciseCatalogReceiverState) throws {
        guard let stateFileURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try JSONEncoder().encode(newState)
        try data.write(to: stateFileURL, options: .atomic)
    }

    /// Bootstrap states (fresh instance ID + nonce) must reach disk before the
    /// challenge is published; retried here until it succeeds.
    private func ensureStatePersisted() {
        guard !isStatePersisted else { return }
        do {
            try persist(state)
            isStatePersisted = true
        } catch {
            print("ExerciseCatalogStore: failed to persist initial state — \(error.localizedDescription)")
        }
    }

    private func publishState() {
        items = state.items ?? []
        hasReceivedCatalog = state.hasReceivedCatalog
        lastSyncDate = state.lastSyncDate
    }
}
