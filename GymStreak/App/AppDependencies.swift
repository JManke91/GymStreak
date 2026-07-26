//
//  AppDependencies.swift
//  GymStreak
//
//  Composition root: owns the repository and gateway instances used across
//  the app, built once from the shared ModelContainer's mainContext. Views
//  read this via `@EnvironmentObject` and pass dependencies down to the
//  ViewModels they construct — views themselves must never construct
//  repositories or services directly.
//

import Foundation
import SwiftData

@MainActor
final class AppDependencies: ObservableObject {
    let routineRepository: RoutineRepository
    let exerciseRepository: ExerciseRepository
    let workoutSessionRepository: WorkoutSessionRepository
    let historySnapshotProvider: HistorySnapshotProviding
    let workoutHistoryCorrelation: WorkoutHistoryCorrelationProviding
    let restTimerReminders: RestTimerReminderScheduling
    let aiCoachPreferences: AICoachPreferencesProviding
    let aiCoachAvailability: AICoachAvailabilityProviding
    let proactivePromptCoordinator: ProactivePromptCoordinating

    /// A true app-wide singleton — `WatchConnectivityManager.shared` must be the same
    /// instance everywhere so its WCSession delegate (registered at app launch) is the
    /// one that receives deliveries.
    let watchSync: WatchSyncServicing

    /// Shared across the app since it's bound to the container's stable mainContext —
    /// no need to reconstruct it per screen the way the old modelContext-swap pattern did.
    /// Exposed as `ExerciseProgressProviding` — Presentation depends on the protocol,
    /// this composition root is the only place allowed to know the concrete type.
    let exerciseProgressService: ExerciseProgressProviding

    /// Launch-time seeder for the built-in starter exercise catalog — seeds the
    /// catalog for all users (skipping name collisions with user-created
    /// exercises) and dedups CloudKit sync races (see
    /// docs/starter-exercise-library.md). Invoked once from GymStreakApp at launch.
    let defaultContentSeeder: DefaultContentSeeder

    /// App-lifetime owner of the exercise-catalogue → watch sync triggers
    /// (post-seed, committed library mutations, CloudKit changes). ViewModels
    /// receive it as `ExerciseCatalogSyncRequesting` — never the concrete type.
    let exerciseCatalogSync: ExerciseCatalogSyncRequesting

    /// App-lifetime owner of the completed-watch-workout receive pipeline
    /// (ticket 04): serialized durable-inbox drain, isolated no-template
    /// ingestion, terminal receipts, and watch acks. Lives here — not in a
    /// ViewModel — because payloads must be ingested before any view exists
    /// and mutation order must not depend on view lifecycles.
    let watchWorkoutIngestion: WatchWorkoutIngestionCoordinator

    /// App-lifetime HealthKit-orphan recovery engine (ticket 09): incremental
    /// anchored discovery, the durable recovery ledger, background observer,
    /// and the conservative reconciler. ViewModels receive it as
    /// `WorkoutRecoveryCoordinating` — never the concrete type.
    let workoutRecovery: WorkoutRecoveryCoordinating

    init(modelContext: ModelContext) {
        self.routineRepository = SwiftDataRoutineRepository(modelContext: modelContext)
        self.exerciseRepository = SwiftDataExerciseRepository(modelContext: modelContext)
        self.workoutSessionRepository = SwiftDataWorkoutSessionRepository(modelContext: modelContext)
        self.historySnapshotProvider = SwiftDataHistorySnapshotProvider(
            modelContainer: modelContext.container
        )
        self.workoutHistoryCorrelation = SwiftDataWorkoutHistoryCorrelationProvider(
            container: modelContext.container
        )
        self.restTimerReminders = UserNotificationRestTimerScheduler()
        let aiCoachPreferences = AICoachPreferences.shared
        let aiCoachAvailability = AICoachAvailability.shared
        self.aiCoachPreferences = aiCoachPreferences
        self.aiCoachAvailability = aiCoachAvailability
        self.proactivePromptCoordinator = ProactivePromptCoordinator(
            preferences: aiCoachPreferences,
            availability: aiCoachAvailability
        )
        let watchConnectivity = WatchConnectivityManager.shared
        self.watchSync = watchConnectivity
        self.exerciseProgressService = ExerciseProgressService(modelContext: modelContext)
        self.defaultContentSeeder = DefaultContentSeeder(modelContext: modelContext)
        self.exerciseCatalogSync = ExerciseCatalogSyncCoordinator(
            exerciseRepository: exerciseRepository,
            watchSync: watchSync
        )
        // One receipt store shared by ingestion (which writes terminal
        // receipts + their external-UUID index) and recovery (which reads that
        // index to prove a workout was already ingested).
        let receipts = WorkoutIngestReceiptStore()
        self.watchWorkoutIngestion = WatchWorkoutIngestionCoordinator(
            inbox: watchConnectivity.workoutInbox,
            receipts: receipts,
            historyTransactions: SwiftDataWorkoutHistoryTransactionFactory(container: modelContext.container),
            routineSnapshots: SwiftDataAuthoritativeRoutineSnapshotProvider(
                container: modelContext.container
            ),
            routineSnapshotTransport: watchConnectivity,
            mainContextCache: SwiftDataMainContextRoutineCacheRefresher(modelContext: modelContext),
            watchSync: watchConnectivity
        )
        let recovery = WorkoutRecoveryCoordinator(
            anchorStore: HealthKitWorkoutAnchorStore(),
            ledger: WorkoutRecoveryLedgerStore(),
            drain: HealthKitAnchoredWorkoutDrain(),
            observer: HealthKitWorkoutObserver(),
            historyCorrelation: workoutHistoryCorrelation,
            receipts: receipts,
            watchSync: watchConnectivity
        )
        self.workoutRecovery = recovery
        // Receipt-of-payload and activation drains route through the manager;
        // weak because the manager is an app-lifetime singleton and must not
        // retain the composition root's coordinators.
        watchConnectivity.onWorkoutInboxUpdated = {
            [weak ingestion = watchWorkoutIngestion, weak recovery] in
            ingestion?.drainInbox()
            // A new/settled payload changes the buffered set and may resolve a
            // recovery candidate — re-reconcile without a fresh HealthKit drain.
            recovery?.reconcile()
        }
        watchConnectivity.onRoutineChallengeUpdated = { [weak coordinator = watchWorkoutIngestion] in
            coordinator?.routineAuthorityDidChange()
        }
        // Launch drain: entries that arrived before this init or were left by
        // a prior crash (processed before any RoutinesViewModel can trigger a
        // routine sync with stale data).
        watchWorkoutIngestion.routineAuthorityDidChange()
        // Register the HealthKit observer + run the first incremental drain.
        recovery.start()
    }

    /// Each `WorkoutViewModel` owns its own HealthKit workout session — unlike
    /// WatchConnectivity there is no cross-instance state to share, and the previous
    /// code created a fresh `HealthKitWorkoutManager()` per WorkoutViewModel (there are
    /// two concurrently: one on the Routines tab for active workouts, one on the
    /// History tab). A factory preserves that instead of collapsing them into one.
    func makeHealthKitWorkoutService() -> HealthKitWorkoutServicing {
        HealthKitWorkoutManager()
    }
}
