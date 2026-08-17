//
//  GymStreakApp.swift
//  GymStreak
//
//  Created by Julian Manke on 14.08.25.
//

import SwiftUI
import SwiftData
import OSLog

@main
struct GymStreakApp: App {
    @Environment(\.scenePhase) private var scenePhase

    /// Same subsystem as the entitlement and purchase logs, so one Console
    /// filter shows the whole Pro story for a launch.
    private static let logger = Logger(subsystem: "app.gymstreak.pro", category: "Gating")

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
                    // Logged every launch, and worth the line: `-PRO_GATING_ON`
                    // comes from the Xcode scheme, so it is present only when
                    // *Xcode* launched the app. Kill the app and reopen it from
                    // the home screen and gating silently turns itself off — a
                    // free user then sees exactly what a Pro user sees, which is
                    // indistinguishable from "the purchase worked" and cost a
                    // whole investigation to spot (docs/pro-subscription.md §9.4b).
                    Self.logger.info(
                        """
                        Launch: gating \(ProGating.isEnabled ? "ON" : "OFF", privacy: .public) \
                        (\(ProGating.gatingSourceDescription, privacy: .public))
                        """
                    )
                    // Resolves the Founder grant, which needs one App Store
                    // round-trip on the very first launch (docs/pro-subscription.md).
                    // Its own `.task` rather than appended to the one above: the
                    // seeder deliberately waits on CloudKit, and the entitlement
                    // must not queue behind that wait.
                    await dependencies.proEntitlements.refresh()
                    // Straight after the grant settles, so a Founder meets the
                    // thank-you on the first launch of the build that turns
                    // gating on — before any gate, badge or nudge is reachable
                    // (docs/pro-subscription.md §5h). A no-op for everyone else.
                    dependencies.founderCelebration.presentIfDue()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        watchConnectivity.requestWorkoutQueueDrain()
                        // The next safe moment for a Founder screen that Rule 3
                        // suppressed (the launch above landed inside a restored
                        // workout). Idempotent, and inert once it has been shown.
                        dependencies.founderCelebration.presentIfDue()
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
