//
//  SeedCatalogVersionStore.swift
//  GymStreak
//
//  The cross-device half of the starter-catalog version flag, split out of
//  DefaultContentSeeder so the seeder file stays about seeding.
//  See docs/starter-exercise-library.md.
//

import Foundation

/// The cross-device half of the catalog version flag.
///
/// Behind a protocol because `NSUbiquitousKeyValueStore` has exactly one usable
/// instance (`.default`) whose contents live outside the app container and
/// survive deleting the app — a test that wrote it would stamp the developer's
/// simulator for good, and a test that read it would inherit whatever that
/// simulator already carries.
protocol SeedCatalogVersionStore: Sendable {
    func version(forKey key: String) -> Int
    func setVersion(_ version: Int, forKey key: String)
}

/// Production implementation: iCloud key-value storage, so a device the user
/// already seeded on does not seed again.
struct UbiquitousSeedCatalogVersionStore: SeedCatalogVersionStore {
    func version(forKey key: String) -> Int {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        return Int(store.longLong(forKey: key))
    }

    func setVersion(_ version: Int, forKey key: String) {
        let store = NSUbiquitousKeyValueStore.default
        store.set(Int64(version), forKey: key)
        store.synchronize()
    }
}
