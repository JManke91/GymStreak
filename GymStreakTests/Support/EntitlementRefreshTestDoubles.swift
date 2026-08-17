//
//  EntitlementRefreshTestDoubles.swift
//  GymStreakTests
//
//  Doubles for `EntitlementRefreshTests`. Split out because they are reusable:
//  any future test about a gate reacting to a purchase needs an entitlement
//  provider that actually notifies.
//

import Combine
import Foundation
import Observation
import SwiftData
@testable import GymStreak

/// A `ProEntitlementProviding` whose state can be changed **and is observable**,
/// like the real `ProEntitlementProvider`.
///
/// `StubProEntitlements` deliberately is not `@Observable`, which is why it could
/// never have caught this: a gate reading a plain stored property back gets the
/// right answer with no notification, and so did the app.
@Observable
@MainActor
final class ObservableStubEntitlements: ProEntitlementProviding {

    var state: ProEntitlementState

    init(state: ProEntitlementState = .free) {
        self.state = state
    }

    var isPro: Bool { state.isPro }

    func refresh() async {}
}

/// Returns nothing at all. These tests never load a chart — they only assert
/// that the view model tells SwiftUI to re-render — so the history boundary just
/// has to exist.
actor SilentHistorySnapshotProvider: HistorySnapshotProviding {

    struct Unused: Error {}

    func fetchTrainingSnapshot(referenceDate: Date) async throws -> HistorySnapshot {
        throw Unused()
    }

    func fetchFortschrittSnapshot() async throws -> [FortschrittExerciseModel] { [] }

    func fetchPRDetails(sessionID: UUID) async throws -> [UUID: PersonalRecordService.PRDetail] { [:] }

    func fetchExerciseProgress(
        exerciseName: String,
        exerciseId: UUID?,
        startDate: Date,
        recentSessionLimit: Int
    ) async throws -> ExerciseProgressSnapshot {
        ExerciseProgressSnapshot(
            data: ExerciseProgressData(exerciseName: exerciseName, dataPoints: []),
            recentSessions: []
        )
    }

    func fetchPreviousPerformances(
        _ lookup: PreviousPerformanceLookup
    ) async throws -> [UUID: PreviousExercisePerformance] { [:] }
}

/// A `Sendable` "it fired" flag for `withObservationTracking`'s `nonisolated`
/// callback. A lock rather than an actor so the assertion can read it without
/// another suspension point deciding the outcome.
final class InvalidationFlag: @unchecked Sendable {

    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        defer { lock.unlock() }
        value = true
    }

    var wasSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

// MARK: - Emission counting

extension ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {

    /// How many times this object told SwiftUI to re-render while `mutate` ran.
    ///
    /// The republish crosses a `Task { @MainActor in … }` hop (observation's
    /// `onChange` is `nonisolated` and fires *during* the mutation), so the count
    /// is taken after yielding rather than synchronously. Yielding a few times
    /// rather than sleeping keeps the test deterministic and instant.
    @MainActor
    func emissionCount(while mutate: () -> Void) async -> Int {
        var count = 0
        let subscription = objectWillChange.sink { _ in count += 1 }
        defer { subscription.cancel() }

        mutate()
        for _ in 0..<10 { await Task.yield() }

        return count
    }
}

// MARK: - Harnesses

@MainActor
struct RoutinesHarness {
    let viewModel: RoutinesViewModel
    let entitlements: ObservableStubEntitlements

    /// Three routines is the free cap, so the nudge and the gate are both on.
    func fillToCap() {
        for index in 0..<ProFeatureCaps.freeRoutineLimit {
            viewModel.createRoutine(
                name: "Routine \(index)",
                pendingExercises: [PendingRoutineExercise(
                    exercise: Exercise(name: "Exercise \(index)"),
                    sets: [ExerciseSet(reps: 8, weight: 50, restTime: 90, order: 0)],
                    order: 0,
                    alternatives: []
                )]
            )
        }
    }
}

@MainActor
struct PeriodRecapHarness {
    let viewModel: PeriodRecapViewModel
    let context: ModelContext
    let allowance: SpyAllowanceStore
    private let container: ModelContainer

    init(entitlements: ObservableStubEntitlements) {
        let container = InMemoryModelContainer.make()
        self.container = container
        self.context = ModelContext(container)
        let allowance = SpyAllowanceStore()
        self.allowance = allowance
        self.viewModel = PeriodRecapViewModel(
            initialRange: .thisYear,
            allowanceGate: AICoachAllowanceGate(
                surface: .periodRecap,
                entitlements: entitlements,
                paywalls: RecordingPaywallPresenter(),
                allowance: allowance,
                availability: StubAICoachAvailability(),
                isGatingEnabled: true
            ),
            service: FakeAICoachService(),
            cache: FakeAICoachCache(),
            preferences: FakeAICoachPreferences(),
            availability: StubAICoachAvailability()
        )
    }

    func exhaustAllowance() {
        for _ in 0..<ProFeatureCaps.freePeriodRecapsPerMonth {
            allowance.consume(.periodRecap)
        }
    }

    func seedSessions(count: Int) {
        AICoachHistoryFixture.seedSessions(context: context, count: count)
    }
}
