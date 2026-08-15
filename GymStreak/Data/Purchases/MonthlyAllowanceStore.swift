//
//  MonthlyAllowanceStore.swift
//  GymStreak
//
//  The durable half of the free AI tasters: how many units of this calendar
//  month a free user has spent, per surface. See docs/pro-subscription.md §5e
//  and docs/monetization-strategy.md §9 ("month-keyed counts in App Group
//  UserDefaults, mirrored to iCloud KVS").
//

import Foundation

/// One surface's consumption for one month, as a single value.
///
/// Month **and** count in one record, written atomically under one key, because
/// the two are only meaningful together: a torn write that updated the count but
/// not the month (or the reverse) would either hand out a free allowance or
/// charge for a month the user never used.
///
/// The month is a `"YYYY-MM"` string rather than a `Date` so it is directly
/// comparable (`<`, `>` are lexicographic and, zero-padded, chronological), and
/// so what is persisted stays readable in a defaults dump.
struct MonthlyAllowanceRecord: Equatable, Sendable {

    let month: String
    let count: Int

    init(month: String, count: Int) {
        self.month = month
        self.count = count
    }

    /// `"2026-08:3"`. Encoded as one string so both stores below can hold it
    /// with the same single-key API (KVS has no "set two keys atomically").
    var rawValue: String { "\(month):\(count)" }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let count = Int(parts[1]) else { return nil }
        self.month = String(parts[0])
        self.count = count
    }

    /// The later of two records, or the larger count when they share a month.
    ///
    /// This is the whole reinstall/clock story in one function: the local store
    /// is empty after a reinstall and the cloud one is not, and neither is
    /// allowed to *lower* the other. Taking the max in both dimensions means a
    /// count can only ever move forward within a month.
    static func newer(_ lhs: MonthlyAllowanceRecord?, _ rhs: MonthlyAllowanceRecord?) -> MonthlyAllowanceRecord? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        if lhs.month == rhs.month {
            return lhs.count >= rhs.count ? lhs : rhs
        }
        return lhs.month > rhs.month ? lhs : rhs
    }
}

/// The cross-device half of the counters.
///
/// Behind a protocol for the same reason `SeedCatalogVersionStore` is
/// (`DefaultContentSeeder`): `NSUbiquitousKeyValueStore` has exactly one usable
/// instance whose contents live outside the app container and survive deleting
/// the app, so a test that wrote it would stamp the developer's simulator for
/// good and a test that read it would inherit whatever that simulator carries.
protocol AllowanceCloudStore: Sendable {
    func record(forKey key: String) -> MonthlyAllowanceRecord?
    func setRecord(_ record: MonthlyAllowanceRecord, forKey key: String)
}

/// Production implementation: iCloud key-value storage.
///
/// This is what stops the taster from being reset by deleting and reinstalling
/// the app — the deliberate difference from the Founder flag (§3a), which needs
/// no mirroring because `AppTransaction` is itself durable. A counter has no
/// such backing.
struct UbiquitousAllowanceCloudStore: AllowanceCloudStore {

    func record(forKey key: String) -> MonthlyAllowanceRecord? {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        guard let raw = store.string(forKey: key) else { return nil }
        return MonthlyAllowanceRecord(rawValue: raw)
    }

    func setRecord(_ record: MonthlyAllowanceRecord, forKey key: String) {
        let store = NSUbiquitousKeyValueStore.default
        store.set(record.rawValue, forKey: key)
        store.synchronize()
    }
}

/// Month-keyed consumption counts for the metered AI surfaces.
///
/// **Reads are answered from memory.** A record is loaded (from both stores,
/// merged) the first time a surface is asked about and cached for the process
/// lifetime; every write updates the cache and both stores. That is a contract,
/// not an optimisation — `consumedCount(for:)` is read from a computed property
/// a view body evaluates, and `NSUbiquitousKeyValueStore.synchronize()` on every
/// render would put file I/O on the main thread (main-thread rule 3).
///
/// **The active month is `max(current, stored)`, and that is what makes a clock
/// rollback harmless.** Moving the device date back a month must not hand out a
/// fresh allowance for a month already spent, so a stored month *ahead* of the
/// device's own month keeps winning: the user stays on the record they already
/// consumed instead of getting a second one. Rolling forward is not defended
/// against and does not need to be — it grants the next month's allowance early
/// and permanently loses the current one, which is a worse deal than waiting.
@MainActor
final class MonthlyAllowanceStore: MonthlyAllowanceTracking {

    private let defaults: UserDefaults
    private let cloud: any AllowanceCloudStore
    private let calendar: Calendar
    private let now: () -> Date

    /// **Doubly optional on purpose.** Assigning `nil` to a `Dictionary`
    /// subscript *removes* the key, so a plain `[MeteredAISurface:
    /// MonthlyAllowanceRecord]` would never cache the "no record yet" answer —
    /// which is the state every user is in before their first message, and the
    /// state *all* users are in while the kill switch is off. Each read would
    /// then fall through to `UserDefaults` and `NSUbiquitousKeyValueStore` from
    /// a view body, on every keystroke. `Optional<Optional<…>>` lets the absence
    /// itself be cached.
    private var cache: [MeteredAISurface: MonthlyAllowanceRecord?] = [:]

    /// - Parameters:
    ///   - defaults: the App Group suite, so a future Pro-aware widget or a
    ///     watch-side surface reads the same counters. Falls back to
    ///     `.standard` only if the container is unavailable.
    ///   - now: injected so the month boundary and a rolled-back clock are
    ///     testable without touching the device date.
    init(
        defaults: UserDefaults? = nil,
        cloud: any AllowanceCloudStore = UbiquitousAllowanceCloudStore(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.appGroupID) ?? .standard
        self.cloud = cloud
        self.calendar = calendar
        self.now = now
    }

    private static let appGroupID = "group.com.gymstreak.shared"

    // MARK: - MonthlyAllowanceTracking

    func consumedCount(for surface: MeteredAISurface) -> Int {
        activeRecord(for: surface).count
    }

    func consume(_ surface: MeteredAISurface) {
        let active = activeRecord(for: surface)
        write(MonthlyAllowanceRecord(month: active.month, count: active.count + 1), for: surface)
    }

    func refund(_ surface: MeteredAISurface) {
        let active = activeRecord(for: surface)
        guard active.count > 0 else { return }
        write(MonthlyAllowanceRecord(month: active.month, count: active.count - 1), for: surface)
    }

    // MARK: - Records

    /// The record the *current* consumption belongs to: the stored one while it
    /// is for this month (or a later one — see the clock note above), a fresh
    /// zeroed record once the month has rolled over.
    private func activeRecord(for surface: MeteredAISurface) -> MonthlyAllowanceRecord {
        let currentMonth = Self.monthKey(for: now(), calendar: calendar)
        guard let stored = storedRecord(for: surface) else {
            return MonthlyAllowanceRecord(month: currentMonth, count: 0)
        }
        // `>` covers the rolled-back clock: the stored month wins and its count
        // stands. `<` is an ordinary new month.
        return stored.month >= currentMonth
            ? stored
            : MonthlyAllowanceRecord(month: currentMonth, count: 0)
    }

    private func storedRecord(for surface: MeteredAISurface) -> MonthlyAllowanceRecord? {
        // One `if let` unwraps "this surface has been loaded"; the value inside
        // may still be `nil`, meaning "loaded, and there is no record".
        if let cached = cache[surface] { return cached }
        let key = surface.storageKey
        let local = defaults.string(forKey: key).flatMap(MonthlyAllowanceRecord.init(rawValue:))
        let merged = MonthlyAllowanceRecord.newer(local, cloud.record(forKey: key))
        cache[surface] = .some(merged)
        return merged
    }

    private func write(_ record: MonthlyAllowanceRecord, for surface: MeteredAISurface) {
        cache[surface] = .some(record)
        defaults.set(record.rawValue, forKey: surface.storageKey)
        cloud.setRecord(record, forKey: surface.storageKey)
    }

    /// `"2026-08"`. Built from date components rather than a `DateFormatter`:
    /// this runs on every read, and allocating a formatter per call is exactly
    /// what main-thread rule 2 forbids.
    static func monthKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }
}
