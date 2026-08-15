//
//  GymStreakApp.swift
//  GymStreak
//
//  Created by Julian Manke on 14.08.25.
//

import SwiftUI
import SwiftData

@main
struct GymStreakApp: App {
    @Environment(\.scenePhase) private var scenePhase

    // Initialize CloudSyncObserver early to catch all sync events
    @StateObject private var cloudSyncObserver = CloudSyncObserver.shared

    // Initialize WatchConnectivityManager early so the WCSession delegate is
    // registered before any queued userInfo (e.g. completed watch workouts)
    // can be delivered during launch. Activating from a lazily-initialized
    // view-scoped object is too late and can drop deliveries.
    @StateObject private var watchConnectivity = WatchConnectivityManager.shared

    // Composition root: built once from the shared ModelContainer's mainContext
    // and handed down to every view via the environment.
    @StateObject private var dependencies: AppDependencies

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-UI_TESTING")
    }

    /// The app's store plus whether it is actually CloudKit-backed — the Settings
    /// sync row must report "off" when the local-only fallback was taken.
    struct Store {
        let container: ModelContainer
        let isCloudKitEnabled: Bool
    }

    let store: Store = {
        let schema = Schema(GymStreakSchema.modelTypes)
        let isEphemeralUITest = ProcessInfo.processInfo.arguments.contains(
            "-UI_TEST_EPHEMERAL_STORE"
        )
        if isEphemeralUITest {
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            do {
                return Store(
                    container: try ModelContainer(for: schema, configurations: [configuration]),
                    isCloudKitEnabled: false
                )
            } catch {
                fatalError("Could not create ephemeral UI-test ModelContainer: \(error)")
            }
        }

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(GymStreakSchema.cloudKitContainerIdentifier)
        )

        do {
            return Store(
                container: try ModelContainer(for: schema, configurations: [modelConfiguration]),
                isCloudKitEnabled: true
            )
        } catch {
            // If CloudKit container fails (e.g., no iCloud account), fall back to local-only storage
            print("Failed to create CloudKit container: \(error). Falling back to local storage.")
            let localConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            do {
                return Store(
                    container: try ModelContainer(for: schema, configurations: [localConfig]),
                    isCloudKitEnabled: false
                )
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var sharedModelContainer: ModelContainer { store.container }

    init() {
        let store = self.store
        _dependencies = StateObject(
            wrappedValue: AppDependencies(
                modelContext: store.container.mainContext,
                isCloudKitStoreEnabled: store.isCloudKitEnabled
            )
        )

        #if DEBUG
        if CloudKitSchemaInitializer.isRequested {
            Task.detached { CloudKitSchemaInitializer.run() }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dependencies)
                .onAppear {
                    if isUITesting {
                        seedTestData()
                    } else {
                        dependencies.defaultContentSeeder.run()
                        // Stage the first catalogue snapshot only after
                        // seeding/dedup committed, so it can't race ahead of
                        // the built-in library.
                        dependencies.exerciseCatalogSync.requestCatalogSync()
                    }
                }
                .task {
                    guard !isUITesting else { return }
                    // Waits for CloudKit to prove it has nothing to deliver
                    // before re-seeding a library the version flag stranded, so
                    // it never fires while a new device is still importing.
                    await dependencies.defaultContentSeeder.recoverStrandedLibraryIfNeeded()
                }
                .task {
                    guard !isUITesting else { return }
                    // Resolves the Founder grant, which needs one App Store
                    // round-trip on the very first launch (docs/pro-subscription.md).
                    // Its own `.task` rather than appended to the one above: the
                    // seeder deliberately waits on CloudKit, and the entitlement
                    // must not queue behind that wait.
                    await dependencies.proEntitlements.refresh()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        watchConnectivity.requestWorkoutQueueDrain()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    @MainActor
    private func seedTestData() {
        TestDataSeeder.seedData(modelContext: sharedModelContainer.mainContext)
    }
}
