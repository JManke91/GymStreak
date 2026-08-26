//
//  SchemaRegistrationTests.swift
//  GymStreakTests
//
//  The guardrail for schema drift. `GymStreakSchema.modelTypes` is the single
//  source of truth every container is built from — the app's CloudKit-backed
//  store, the debug CloudKit schema initializer, the SwiftUI previews and the
//  test containers. A new `@Model` that never reaches that list is invisible to
//  all of them, and the symptom is not a build error: it is data that silently
//  fails to persist or to sync, discovered on a user's second device.
//
//  So the list is checked against the app binary itself rather than against a
//  second hand-maintained list, which would drift the same way. Every class in
//  the app image is asked whether it conforms to `PersistentModel`; the ones
//  that do must be registered.
//

import Testing
import SwiftData
import Foundation
import ObjectiveC.runtime
@testable import GymStreak

@Suite
struct SchemaRegistrationTests {

    @Test("Every @Model type in the app is registered in GymStreakSchema.modelTypes")
    func everyModelTypeIsRegistered() {
        let discovered = Self.persistentModelTypesInAppImage()

        // A discovery failure (wrong image, runtime API returning nothing) would
        // otherwise make this test pass vacuously forever.
        #expect(
            discovered.count >= GymStreakSchema.modelTypes.count,
            "Class discovery found only \(discovered.count) @Model types in the app image — it is not seeing the app binary."
        )

        let registered = Set(GymStreakSchema.modelTypes.map(ObjectIdentifier.init))
        let unregistered = discovered
            .filter { !registered.contains(ObjectIdentifier($0)) }
            .map { String(reflecting: $0) }
            .sorted()

        #expect(
            unregistered.isEmpty,
            """
            @Model type(s) missing from GymStreakSchema.modelTypes: \(unregistered.joined(separator: ", ")).
            Add them there, then run the app once with -INITIALIZE_CLOUDKIT_SCHEMA and deploy the \
            CloudKit schema to Production before shipping (docs/cloudkit-schema-automation.md).
            """
        )
    }

    @Test("The shared schema list has no duplicate entries")
    func registeredTypesAreUnique() {
        let ids = GymStreakSchema.modelTypes.map(ObjectIdentifier.init)
        #expect(Set(ids).count == ids.count)
    }

    /// A second, independent catch for the same drift, and the reason the missing
    /// `RoutineSchedule` never showed up as a red test: `Schema` follows
    /// relationships, so a model reachable from a registered one is pulled into the
    /// graph anyway. Containers therefore keep working while the list is wrong —
    /// only the count reveals it.
    @Test("The schema graph contains exactly the registered types, nothing pulled in transitively")
    func schemaGraphMatchesTheRegisteredList() {
        let schema = Schema(GymStreakSchema.modelTypes)
        #expect(schema.entities.count == GymStreakSchema.modelTypes.count)
    }

    // MARK: - Discovery

    /// All classes in the app's binary image that conform to `PersistentModel`.
    ///
    /// `class_getImageName` on a known model pins the lookup to the image the app
    /// was built into, so classes from SwiftData, SwiftUI and the test bundle are
    /// never walked. `objc_lookUpClass` is used rather than `objc_getClass` because
    /// it does not trigger `+initialize` on unrelated classes.
    private static func persistentModelTypesInAppImage() -> [any PersistentModel.Type] {
        guard let imageName = class_getImageName(Routine.self) else { return [] }
        var count: UInt32 = 0
        guard let names = objc_copyClassNamesForImage(imageName, &count) else { return [] }
        // The runtime `malloc`s this buffer, so it is freed, not `deallocate()`d.
        defer { free(UnsafeMutableRawPointer(names)) }

        var found: [any PersistentModel.Type] = []
        for index in 0..<Int(count) {
            guard let cls = objc_lookUpClass(names[index]) else { continue }
            if let modelType = cls as? any PersistentModel.Type {
                found.append(modelType)
            }
        }
        return found
    }
}
