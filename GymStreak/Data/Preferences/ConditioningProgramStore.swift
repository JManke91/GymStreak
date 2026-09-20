//
//  ConditioningProgramStore.swift
//  GymStreak
//
//  Persists the conditioning-program enrollment in `UserDefaults` and mirrors it
//  to iCloud key-value storage, so it follows the user to their other devices
//  and survives a reinstall. See docs/fight-conditioning.md.
//
//  Why KVS and not a SwiftData model: the enrollment is one small value per user.
//  As a CloudKit-synced `@Model` it would need a Production schema deploy that can
//  never be undone, and two devices enrolling offline would each insert a row —
//  a duplicate the app would have to reconcile. One KVS key cannot duplicate.
//

import Foundation
import Observation

/// What is stored under the key: the enrollment, or `nil` once the user left,
/// stamped with when it was written. The `nil` is a tombstone — without it, a
/// device that still holds an old enrollment locally would resurrect a program
/// the user left on another device. The later `updatedAt` wins.
struct ConditioningProgramStoredValue: Codable, Equatable, Sendable {
    let enrollment: ConditioningProgramEnrollment?
    let updatedAt: Date

    static func newer(_ lhs: Self?, _ rhs: Self?) -> Self? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return rhs.updatedAt > lhs.updatedAt ? rhs : lhs
    }
}

/// The cross-device half. Behind a protocol for the reason `AllowanceCloudStore`
/// gives: tests must never read or stamp the real `NSUbiquitousKeyValueStore`.
protocol ConditioningProgramCloudStore: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
}

struct UbiquitousConditioningProgramCloudStore: ConditioningProgramCloudStore {
    func data(forKey key: String) -> Data? {
        NSUbiquitousKeyValueStore.default.data(forKey: key)
    }

    func set(_ data: Data, forKey key: String) {
        let store = NSUbiquitousKeyValueStore.default
        store.set(data, forKey: key)
        store.synchronize()
    }
}

@Observable
@MainActor
final class ConditioningProgramStore: ConditioningProgramStoring {

    static let enrollmentKey = "conditioning.program.enrollment"
    private static let routinesCardDismissedKey = "conditioning.program.routinesCardDismissed"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cloud: any ConditioningProgramCloudStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var externalChangeObserver: NSObjectProtocol?

    private(set) var storedValue: ConditioningProgramStoredValue?

    init(
        defaults: UserDefaults = .standard,
        cloud: any ConditioningProgramCloudStore = UbiquitousConditioningProgramCloudStore(),
        observesExternalChanges: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.now = now
        isRoutinesCardDismissed = defaults.bool(forKey: Self.routinesCardDismissedKey)
        storedValue = ConditioningProgramStoredValue.newer(
            Self.decode(defaults.data(forKey: Self.enrollmentKey)),
            Self.decode(cloud.data(forKey: Self.enrollmentKey))
        )
        if observesExternalChanges {
            // Posted on a background queue; hop to the main actor with no payload.
            externalChangeObserver = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: nil,
                queue: nil
            ) { @Sendable [weak self] _ in
                Task { @MainActor in self?.mergeFromCloud() }
            }
        }
    }

    isolated deinit {
        if let externalChangeObserver {
            NotificationCenter.default.removeObserver(externalChangeObserver)
        }
    }

    var enrollment: ConditioningProgramEnrollment? {
        get { storedValue?.enrollment }
        set {
            let value = ConditioningProgramStoredValue(enrollment: newValue, updatedAt: now())
            storedValue = value
            guard let data = try? JSONEncoder().encode(value) else { return }
            defaults.set(data, forKey: Self.enrollmentKey)
            cloud.set(data, forKey: Self.enrollmentKey)
        }
    }

    var isRoutinesCardDismissed: Bool {
        didSet { defaults.set(isRoutinesCardDismissed, forKey: Self.routinesCardDismissedKey) }
    }

    /// Adopts a newer value written on another device.
    func mergeFromCloud() {
        let cloudValue = Self.decode(cloud.data(forKey: Self.enrollmentKey))
        guard let merged = ConditioningProgramStoredValue.newer(storedValue, cloudValue),
              merged != storedValue else { return }
        storedValue = merged
        if let data = try? JSONEncoder().encode(merged) {
            defaults.set(data, forKey: Self.enrollmentKey)
        }
    }

    private static func decode(_ data: Data?) -> ConditioningProgramStoredValue? {
        data.flatMap { try? JSONDecoder().decode(ConditioningProgramStoredValue.self, from: $0) }
    }
}
