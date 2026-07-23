import Foundation
import CoreData
import Combine

/// Legacy notification name posted when the persistent store reports a remote change.
extension Notification.Name {
    static let cloudKitDataDidChange = Notification.Name("cloudKitDataDidChange")
}

/// Observes persistent-store remote-change events and notifies subscribers.
/// This is a singleton that should be initialized once at app startup.
@MainActor
final class CloudSyncObserver: ObservableObject {
    static let shared = CloudSyncObserver()

    /// Published property that increments on each sync event, allowing views to react
    @Published private(set) var syncVersion: Int = 0

    private var notificationObserver: NSObjectProtocol?

    private init() {
        setupRemoteChangeObserver()
    }

    private func setupRemoteChangeObserver() {
        // This Core Data notification is not exclusive to CloudKit.
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleRemoteChange()
            }
        }
    }

    private func handleRemoteChange() {
        print("CloudSyncObserver: Persistent store change detected")
        syncVersion += 1

        // Post notification for ViewModels that prefer notification-based updates
        NotificationCenter.default.post(name: .cloudKitDataDidChange, object: nil)
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
