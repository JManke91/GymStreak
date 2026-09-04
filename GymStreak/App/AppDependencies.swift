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
    /// The one gate that makes History's model-actor reads and the main context's
    /// completed-session deletes mutually exclusive. Both sides must be handed *this*
    /// instance — a second gate excludes nothing. See `HistoryStoreGate`.
    let historyStoreGate = HistoryStoreGate()
    let historySnapshotProvider: HistorySnapshotProviding
    /// The exercise deep-dive's history boundary. The **same instance** as
    /// `historySnapshotProvider`: the narrative is read from the very sessions
    /// the chart above it is drawn from, so a second `@ModelActor` would fault
    /// the same graph twice for one screen.
    let exerciseDeepDiveFacts: ExerciseDeepDiveFactProviding
    /// The one write path into workout history outside of recording a workout: linking
    /// pre-`exerciseId` rows to the library exercise the user says they meant.
    let legacyHistoryAttribution: LegacyHistoryAttributing
    let workoutHistoryCorrelation: WorkoutHistoryCorrelationProviding
    let restTimerReminders: RestTimerReminderScheduling
    /// The rest timer's Lock Screen / Dynamic Island surface. One instance for
    /// the whole app, like the reminder scheduler: there is only ever one
    /// rest-timer Live Activity, and identity-keyed calls keep the two
    /// `WorkoutViewModel`s from ending each other's countdown.
    let restTimerLiveActivity: RestTimerLiveActivityPresenting
    /// Writes a session's performed values back onto its routine template
    /// ("Update routine"). Stateless domain logic over the shared main-context
    /// repositories, so one instance serves both `WorkoutViewModel`s.
    let routineTemplateSync: RoutineTemplateSyncService
    let aiCoachPreferences: AICoachPreferencesProviding
    let aiCoachAvailability: AICoachAvailabilityProviding
    let proactivePromptCoordinator: ProactivePromptCoordinating

    /// A true app-wide singleton — `WatchConnectivityManager.shared` must be the same
    /// instance everywhere so its WCSession delegate (registered at app launch) is the
    /// one that receives deliveries.
    let watchSync: WatchSyncServicing

    /// Retained so model-actor-backed dependencies can be built lazily by factory
    /// (see `makeChatFactProvider`). Never handed to Presentation.
    private let modelContainer: ModelContainer

    /// Shared across the app: it holds no context of its own, only the history read
    /// boundary its off-main half calls (audit P1.6). Exposed as
    /// `ExerciseProgressProviding` — Presentation depends on the protocol, this
    /// composition root is the only place allowed to know the concrete type.
    let exerciseProgressService: any ExerciseProgressProviding

    /// Launch-time seeder for the built-in starter exercise catalog — seeds the
    /// catalog for all users (skipping name collisions with user-created
    /// exercises) and dedups CloudKit sync races (see
    /// docs/starter-exercise-library.md). Invoked once from GymStreakApp at launch.
    let defaultContentSeeder: DefaultContentSeeder

    /// Launch-time seeder for the built-in example routine — gives a user with
    /// no routines of their own one ready-made routine instead of an empty
    /// state, and dedups CloudKit sync races on it (see
    /// docs/example-starter-routine.md). Invoked once from GymStreakApp at
    /// launch, after `defaultContentSeeder`, whose exercises it resolves.
    let exampleRoutineSeeder: ExampleRoutineSeeder

    /// One-shot repair that re-exports training plans whose CloudKit records
    /// were written without their owning routine, back when the link was a
    /// to-one ↔ to-one relationship CloudKit does not mirror (see
    /// docs/workout-planning.md). Invoked once from GymStreakApp at launch.
    let routinePlanLinkRepair: RoutinePlanLinkRepair

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

    /// Which recorded workouts already had a weight increase applied from the
    /// Watch's post-workout recap (progressive-overload ticket 05), so History
    /// does not offer the same increase a second time. Read-only from
    /// Presentation, and it never mutates a recorded workout.
    let appliedOverloadCorrelation: AppliedOverloadCorrelationReading

    /// Live iCloud sync status for the Settings row. App-lifetime because it has
    /// to be subscribed to CloudKit's mirroring events before the user opens
    /// Settings — otherwise the first events of the session are missed.
    /// Presentation only ever sees `CloudSyncStatusProviding`.
    let cloudSyncStatus: CloudSyncStatusProviding

    /// The unit weights are shown and entered in (docs/weight-unit-preference.md).
    /// App-lifetime because the app root publishes it into the environment and
    /// every weight on screen reads it; kilograms stay the stored unit whatever
    /// it says. Presentation only ever sees `WeightUnitPreferenceProviding`.
    let weightUnitPreference: WeightUnitPreferenceProviding

    /// Whether the user opted into mirroring planned workouts to Apple Calendar
    /// (docs/calendar-sync.md). Intent only — `workoutCalendarSync` owns whether
    /// the permission and the app's calendar are actually in place. Presentation
    /// only ever sees `CalendarSyncPreferenceProviding`.
    let calendarSyncPreference: CalendarSyncPreferenceProviding

    /// Owner of the app's dedicated "GymStreak" calendar and the only holder of
    /// an `EKEventStore` (docs/calendar-sync.md). App-lifetime because the store
    /// is expensive to build and its authorization state is per-instance;
    /// Presentation only ever sees `WorkoutCalendarSyncing`.
    let workoutCalendarSync: WorkoutCalendarSyncing

    /// Brings the app-owned calendar in line with the user's plans whenever one
    /// changes (docs/calendar-sync.md). App-lifetime because both trigger sites —
    /// the planning sheet and the Settings toggle — share it, and it holds no
    /// state of its own. Presentation only ever sees
    /// `PlannedWorkoutCalendarMirroring`.
    let plannedWorkoutCalendarMirror: PlannedWorkoutCalendarMirroring

    /// The Pro entitlement every gate reads (docs/pro-subscription.md): the
    /// Founder grant composed with the RevenueCat entitlement. This is the only
    /// place the purchase layer is named — Presentation only ever sees
    /// `ProEntitlementProviding`.
    let proEntitlements: ProEntitlementProviding

    #if DEBUG
    /// The same instance as `proEntitlements`, typed for the debug-only
    /// entitlement picker and Test Store section in Settings. Compiled out of
    /// release builds along with them.
    let proEntitlementDebug: ProEntitlementDebugging
    #endif

    /// The app-wide "a workout is running" flag. Written by the `WorkoutViewModel`
    /// that owns the session, read by `paywalls` to enforce Rule 3 — no upsell
    /// inside a workout (docs/monetization-strategy.md §8).
    let activeWorkout: ActiveWorkoutReporting

    /// The one seam any gate uses to raise a paywall (docs/pro-subscription.md).
    /// Hosted once near the app root, so a gate anywhere raises the sheet
    /// without its screen owning one.
    let paywalls: PaywallPresenting

    #if DEBUG
    /// The same instance as `paywalls`, typed for the debug-only placement
    /// section in Settings — the shipped `present(_:)` is inert while the kill
    /// switch is off, so nothing else could raise a placement during development.
    let paywallDebug: PaywallPresentationDebugging
    #endif

    /// §8's two proactive placements (A — first routine created, B — the value
    /// moment). App-lifetime because a trigger armed inside a workout has to
    /// outlive the screen that armed it: the deferral is the feature
    /// (docs/pro-subscription.md §5g).
    let proactivePaywalls: ProactivePaywallCoordinator

    #if DEBUG
    /// The armed-trigger record behind `proactivePaywalls`, typed for the debug
    /// placement section's reset. Same instance.
    let proactivePaywallTriggersDebug: ProactivePaywallTrackingDebugging
    #endif

    /// The one-time Founder thank-you (docs/pro-subscription.md §5h). Held as
    /// the concrete type, like `proactivePaywalls`: the app root binds a
    /// `.fullScreenCover` straight to its `@Observable` `isPresenting`.
    let founderCelebration: FounderCelebrationCoordinator

    /// The first-run onboarding tour (docs/onboarding.md). Held as the concrete
    /// type, like `founderCelebration`: the app root binds a `.fullScreenCover`
    /// straight to its `@Observable` `isPresenting`, and it must be the *same*
    /// instance the cover is built from so a dismissal is recorded once.
    let onboarding: OnboardingFlowViewModel

    /// The month-keyed free-tier counters behind the AI tasters (P3/P4/P5).
    /// App-lifetime because it caches its records in memory — a second instance
    /// would answer from a stale cache after the first one wrote. Presentation
    /// only ever sees `MonthlyAllowanceTracking`.
    let aiAllowance: MonthlyAllowanceTracking

    /// Bundle/OS/hardware metadata prefilled into the Settings support mail.
    /// Stateless, so it is cheap to hold for the app's lifetime; Presentation
    /// only ever sees `DeviceDiagnosticsProviding`.
    let deviceDiagnostics: any DeviceDiagnosticsProviding

    /// - Parameter isCloudKitStoreEnabled: whether the app is running on the
    ///   CloudKit-backed store. `false` when `GymStreakApp` had to fall back to a
    ///   local-only store, and in ephemeral UI-test runs, which the sync status
    ///   must never report as "up to date".
    /// - Parameter cloudKitStoreFailure: why the CloudKit store could not be
    ///   built, when that is what forced the fallback. Reported as `.failing`
    ///   rather than `.off` — a broken store is not a store that is local on
    ///   purpose. `nil` in UI-test runs and whenever CloudKit is fine.
    init(
        modelContext: ModelContext,
        isCloudKitStoreEnabled: Bool,
        cloudKitStoreFailure: String? = nil
    ) {
        self.modelContainer = modelContext.container
        self.routineRepository = SwiftDataRoutineRepository(modelContext: modelContext)
        self.exerciseRepository = SwiftDataExerciseRepository(modelContext: modelContext)
        self.workoutSessionRepository = SwiftDataWorkoutSessionRepository(modelContext: modelContext)
        self.routineTemplateSync = RoutineTemplateSyncService(
            routineRepository: routineRepository,
            exerciseRepository: exerciseRepository
        )
        let historySnapshotProvider = SwiftDataHistorySnapshotProvider(
            modelContainer: modelContext.container,
            gate: historyStoreGate
        )
        self.historySnapshotProvider = historySnapshotProvider
        self.exerciseDeepDiveFacts = historySnapshotProvider
        self.legacyHistoryAttribution = SwiftDataLegacyHistoryAttributionProvider(
            modelContainer: modelContext.container,
            gate: historyStoreGate
        )
        self.workoutHistoryCorrelation = SwiftDataWorkoutHistoryCorrelationProvider(
            container: modelContext.container
        )
        self.restTimerReminders = UserNotificationRestTimerScheduler()
        self.restTimerLiveActivity = ActivityKitRestTimerPresenter()
        self.cloudSyncStatus = CloudKitSyncStatusMonitor(
            isCloudKitStoreEnabled: isCloudKitStoreEnabled,
            storeFailureDescription: cloudKitStoreFailure,
            containerIdentifier: GymStreakSchema.cloudKitContainerIdentifier
        )
        self.deviceDiagnostics = SystemDeviceDiagnosticsProvider()
        let weightUnitPreference = WeightUnitPreference.shared
        self.weightUnitPreference = weightUnitPreference
        let calendarSyncPreference = CalendarSyncPreference.shared
        self.calendarSyncPreference = calendarSyncPreference
        let workoutCalendarSync = EventKitWorkoutCalendarSync()
        self.workoutCalendarSync = workoutCalendarSync
        self.plannedWorkoutCalendarMirror = PlannedWorkoutCalendarMirror(
            routineRepository: routineRepository,
            workoutSessionRepository: workoutSessionRepository,
            preference: calendarSyncPreference,
            sync: workoutCalendarSync
        )
        // Constructing the gateway configures the RevenueCat SDK — this runs in
        // `GymStreakApp.init()`, so it happens once, before any UI exists and
        // before anything can read an entitlement.
        let proEntitlements = ProEntitlementProvider(
            founderStatus: Self.makeFounderStatusService(),
            purchases: RevenueCatPurchaseGateway()
        )
        self.proEntitlements = proEntitlements
        #if DEBUG
        self.proEntitlementDebug = proEntitlements
        #endif
        let activeWorkout = ActiveWorkoutRegistry()
        self.activeWorkout = activeWorkout
        let paywalls = PaywallPresenter(
            entitlements: proEntitlements,
            activeWorkout: activeWorkout
        )
        self.paywalls = paywalls
        #if DEBUG
        self.paywallDebug = paywalls
        #endif
        let proactivePaywallTriggers = ProactivePaywallTriggerStore()
        self.proactivePaywalls = ProactivePaywallCoordinator(
            entitlements: proEntitlements,
            paywalls: paywalls,
            triggers: proactivePaywallTriggers,
            // The same provider the History tab reads, so placement B's figures
            // come off the one `@ModelActor` rather than a second context.
            totals: historySnapshotProvider,
            activeWorkout: activeWorkout
        )
        #if DEBUG
        self.proactivePaywallTriggersDebug = proactivePaywallTriggers
        #endif
        self.founderCelebration = FounderCelebrationCoordinator(
            entitlements: proEntitlements,
            record: FounderCelebrationStore(),
            activeWorkout: activeWorkout
        )
        self.onboarding = OnboardingFlowViewModel(completion: OnboardingCompletionStore())
        self.aiAllowance = MonthlyAllowanceStore()
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
        // The watch cannot read the iPhone's UserDefaults — the App Group suite
        // is shared within a device's app family, not across the pairing — so
        // the unit is published over WatchConnectivity, merged into the routine
        // applicationContext. Seed it now and republish on every change.
        watchConnectivity.syncWeightUnit(weightUnitPreference.weightUnit)
        weightUnitPreference.onChange = { [weak watchConnectivity] unit in
            watchConnectivity?.syncWeightUnit(unit)
        }
        self.exerciseProgressService = ExerciseProgressService(
            historyProvider: historySnapshotProvider
        )
        self.defaultContentSeeder = DefaultContentSeeder(
            modelContext: modelContext,
            cloudSyncStatus: cloudSyncStatus,
            historyStoreGate: historyStoreGate
        )
        self.exampleRoutineSeeder = ExampleRoutineSeeder(
            modelContext: modelContext,
            historyStoreGate: historyStoreGate
        )
        self.routinePlanLinkRepair = RoutinePlanLinkRepair(
            modelContext: modelContext,
            cloudSyncStatus: cloudSyncStatus,
            historyStoreGate: historyStoreGate
        )
        self.exerciseCatalogSync = ExerciseCatalogSyncCoordinator(
            exerciseRepository: exerciseRepository,
            watchSync: watchSync
        )
        // One receipt store shared by ingestion (which writes terminal
        // receipts + their external-UUID index) and recovery (which reads that
        // index to prove a workout was already ingested).
        let receipts = WorkoutIngestReceiptStore()
        // The same store also holds the recap's applied-overload correlation:
        // it is written by the transaction path that already owns receipts, so
        // giving it a second home would mean two ledgers to keep in step.
        self.appliedOverloadCorrelation = receipts
        self.watchWorkoutIngestion = WatchWorkoutIngestionCoordinator(
            inbox: watchConnectivity.workoutInbox,
            receipts: receipts,
            historyTransactions: SwiftDataWorkoutHistoryTransactionFactory(container: modelContext.container),
            routineSnapshots: SwiftDataAuthoritativeRoutineSnapshotProvider(
                container: modelContext.container
            ),
            routineSnapshotTransport: watchConnectivity,
            mainContextCache: SwiftDataMainContextRoutineCacheRefresher(modelContext: modelContext),
            watchSync: watchConnectivity,
            historyStoreGate: historyStoreGate
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
        // The two drains are `async` now (they hold the History gate for the whole pass —
        // see `WatchWorkoutIngestionCoordinator.historyStoreGate`), so each hops through a
        // `Task`.
        //
        // **`Task { @MainActor in … }`, never a bare `Task { … }`.** SE-0431 guarantees tasks
        // start on an actor *in creation order* only for closures carrying an explicit
        // isolation marker, and deliberately excludes merely *implicitly* isolated ones (so
        // bare `Task {}` does not become a scheduling bottleneck). The explicit form is the
        // same guarantee `docs/swift6-concurrency.md` §4 already relies on for the delegate
        // hops, and it costs nothing to keep here.
        //
        // Scope note, so nobody over-reads this: payload-vs-payload order does **not** depend
        // on it. `drainInboxLocked()` iterates `inbox.entries()`, which sorts by arrival
        // timestamp, so whichever task wins the gate drains everything oldest-first and the
        // loser finds an empty inbox — inbox order is a property of the store. What does
        // depend on task order is `routineAuthorityDidChange` (receipt recovery) landing
        // before a plain drain, and even that converges, because it re-drains after
        // `recoverReadyReceipts()`.
        watchConnectivity.onWorkoutInboxUpdated = {
            [weak ingestion = watchWorkoutIngestion, weak recovery] in
            // `reconcile()` runs INSIDE the task, after the drain — it reads
            // `historyCorrelation.healthKitWorkoutIDs()` and `watchSync.pendingWorkouts()`,
            // both of which the drain mutates, and its comment below describes a *post*-drain
            // reconcile. Making the drain `async` briefly inverted this: left outside the
            // task it ran first, and on the drain branches that acknowledge without ingesting
            // (no `.workoutHistoryDidChange` post) the entry stayed buffered until some
            // unrelated trigger.
            Task { @MainActor in
                await ingestion?.drainInbox()
                // A new/settled payload changes the buffered set and may resolve a
                // recovery candidate — re-reconcile without a fresh HealthKit drain.
                recovery?.reconcile()
            }
        }
        watchConnectivity.onRoutineChallengeUpdated = { [weak coordinator = watchWorkoutIngestion] in
            Task { @MainActor in await coordinator?.routineAuthorityDidChange() }
        }
        // Launch drain: entries that arrived before this init or were left by a prior crash.
        //
        // This no longer completes before `RoutinesViewModel` first fetches — the drain is
        // `async`, so the enqueued task cannot start until this main-actor turn ends, and the
        // first `body` evaluation (which builds `RoutinesViewModel` and calls `fetchRoutines()`
        // → `syncRoutinesToWatch()`) is in that same turn. What actually prevents a stale
        // routine sync is `canSyncRoutines` refusing to send before WCSession activation
        // (docs/watch-sync.md) — that gate is now the only thing holding the invariant.
        // The `Task` captures the coordinator rather than `self`, which is still initializing.
        Task { @MainActor [watchWorkoutIngestion] in
            await watchWorkoutIngestion.routineAuthorityDidChange()
        }
        // Register the HealthKit observer + run the first incremental drain.
        recovery.start()
    }

    /// Each `WorkoutViewModel` owns its own `HealthKitWorkoutManager` instance — unlike
    /// WatchConnectivity there is no cross-instance state to share (the only per-instance
    /// state left is the derived `isAuthorized` flag; the phone runs no live workout
    /// session), and the previous
    /// code created a fresh `HealthKitWorkoutManager()` per WorkoutViewModel (there are
    /// two concurrently: one on the Routines tab for active workouts, one on the
    /// History tab). A factory preserves that instead of collapsing them into one.
    func makeHealthKitWorkoutService() -> HealthKitWorkoutServicing {
        HealthKitWorkoutManager()
    }

    /// The free-tier gate for one metered AI surface (docs/pro-subscription.md
    /// §5e). A factory rather than a stored property because each surface gets
    /// its own gate and they are cheap, stateless compositions of app-lifetime
    /// collaborators — the counters they share live in `aiAllowance`.
    func makeAICoachAllowanceGate(for surface: MeteredAISurface) -> AICoachAllowanceGate {
        AICoachAllowanceGate(
            surface: surface,
            entitlements: proEntitlements,
            paywalls: paywalls,
            allowance: aiAllowance,
            availability: aiCoachAvailability
        )
    }

    /// The Founder grant, reading StoreKit — unless a Debug run asked to
    /// simulate the original download (docs/pro-subscription.md §9.4c).
    ///
    /// The simulated service is handed a **separate defaults suite**, wiped at
    /// the start of every simulated launch. Two things follow, both deliberate:
    /// the real `pro.isFounder` key is never written, so removing the argument
    /// returns the device to its real state; and each simulated launch resolves
    /// from scratch instead of short-circuiting on `isDecided`, which is the
    /// only way to exercise the decision itself more than once per install.
    private static func makeFounderStatusService() -> FounderStatusService {
        #if DEBUG
        let suiteName = SimulatedOriginalAppDownloadReader.defaultsSuiteName
        // Falling back to `.standard` here would write a simulated grant into
        // the real `pro.isFounder` key, which is recorded once and kept forever
        // — so the whole point of the separate suite would be undone by the one
        // line meant to make it robust. Not simulating is the fail-closed
        // choice, and the argument having no effect is a loud enough symptom.
        if let simulated = SimulatedOriginalAppDownloadReader.fromLaunchArguments(),
           let simulatedDefaults = UserDefaults(suiteName: suiteName) {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            return FounderStatusService(downloads: simulated, defaults: simulatedDefaults)
        }
        #endif
        return FounderStatusService(downloads: StoreKitOriginalAppDownloadReader())
    }

    /// The AI-coach chat's tool-backing read boundary. A factory rather than a stored
    /// property because building it spins up a `@ModelActor` and a second, read-only
    /// `ModelContext` (audit P1.3) — most users never open the chat, and the AI coach is
    /// opt-in and hardware-gated, so nobody should pay for that at launch.
    /// `CoachChatService.isConfigured` is what keeps this to one call per process.
    func makeChatFactProvider() -> ChatFactProviding {
        ChatFactProvider(modelContainer: modelContainer, gate: historyStoreGate)
    }
}
