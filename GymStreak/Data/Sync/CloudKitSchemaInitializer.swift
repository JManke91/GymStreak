//
//  CloudKitSchemaInitializer.swift
//  GymStreak
//

#if DEBUG
import CloudKit
import CoreData
import SwiftData

/// Debug-only utility that uploads the complete SwiftData schema to the
/// CloudKit **Development** environment via
/// `NSPersistentCloudKitContainer.initializeCloudKitSchema`, so every record
/// type and field (including nil optionals) appears in the CloudKit Console
/// without having to create real data in the app first.
///
/// Trigger: launch the app once with the `-INITIALIZE_CLOUDKIT_SCHEMA`
/// argument on a device/simulator signed into iCloud, then deploy the schema
/// to Production in the CloudKit Console. Never runs in Release builds.
enum CloudKitSchemaInitializer {
    static let launchArgument = "-INITIALIZE_CLOUDKIT_SCHEMA"

    private enum InitializationError: Error {
        case modelCreationFailed
    }

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func run() {
        // initializeCloudKitSchema has a hard-coded internal 30s timeout and is
        // known to time out transiently (Core Data error 134060, Apple forums
        // thread 704844). The dev schema is additive, so retrying is the
        // community remedy — verify the result in the CloudKit Console.
        let maxAttempts = 5
        for attempt in 1...maxAttempts {
            do {
                try initializeSchema()
                print("✅ [CloudKitSchemaInitializer] Full schema uploaded to the CloudKit Development environment (attempt \(attempt)/\(maxAttempts)). Review and deploy to Production in the CloudKit Console.")
                return
            } catch {
                print("⚠️ [CloudKitSchemaInitializer] Attempt \(attempt)/\(maxAttempts) failed: \(error)")
                if attempt < maxAttempts {
                    Thread.sleep(forTimeInterval: 3)
                }
            }
        }
        print("❌ [CloudKitSchemaInitializer] Schema initialization failed after \(maxAttempts) attempts. Check the iCloud sign-in and network, then relaunch with \(launchArgument). Progress is incremental — already-created record types persist across runs.")
    }

    private static func initializeSchema() throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: GymStreakSchema.modelTypes) else {
            throw InitializationError.modelCreationFailed
        }

        let container = NSPersistentCloudKitContainer(name: "CloudKitSchemaInit", managedObjectModel: model)

        // Throwaway store: schema initialization only needs a loaded store to
        // generate representative records from — it must not touch the app's
        // real SwiftData store file.
        let storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cloudkit-schema-init-\(UUID().uuidString).sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldAddStoreAsynchronously = false
        // CloudKit mirroring requires history tracking even on this transient store.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: GymStreakSchema.cloudKitContainerIdentifier)
        options.databaseScope = .private
        description.cloudKitContainerOptions = options
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        try container.initializeCloudKitSchema(options: [])

        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try? container.persistentStoreCoordinator.remove(store)
        }
        try? FileManager.default.removeItem(at: storeURL)
    }
}
#endif
