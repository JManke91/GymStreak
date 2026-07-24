//
//  HealthKitWorkoutObserver.swift
//  GymStreak
//
//  Long-lived HealthKit change signal for the recovery pipeline (ticket 09 of
//  in-workout routine editing). Registers ONE `HKObserverQuery` for
//  `HKObjectType.workoutType()` during early app launch and requests
//  background delivery, so a watch→iPhone Health sync can wake the app to run
//  the bounded anchored drain.
//
//  The observer is only a wake/change signal — never the workout-completion
//  clock (Apple Watch→iPhone Health synchronization is system-controlled and
//  non-real-time, and `.immediate` is a maximum request under system policy,
//  not a latency guarantee). Its handler runs the injected drain and then
//  calls the HealthKit completion handler EXACTLY ONCE — on success or failure
//  — so HealthKit's background-delivery budget for this type is released. On
//  failure the drain leaves the anchor unchanged and the next notification (or
//  a foreground launch) retries.
//
//  NOTE: background observer delivery is unavailable on the Simulator — the
//  foreground drain (launch / scene-active) is the fallback there and on any
//  device where background delivery is delayed or disabled.
//

import Foundation
import HealthKit

@MainActor
final class HealthKitWorkoutObserver {
    /// Wraps HealthKit's non-Sendable completion handler so it can cross into
    /// the `@MainActor` drain Task under strict concurrency. HealthKit
    /// documents the handler as safe to call from any thread.
    private struct CompletionBox: @unchecked Sendable {
        let complete: HKObserverQueryCompletionHandler
    }

    private let healthStore: HKHealthStore
    private var observerQuery: HKObserverQuery?
    private var onChange: (() async -> Void)?

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    /// Registers the observer and enables background delivery. `onChange` runs
    /// the bounded drain; call this once at app launch. Safe to call again — a
    /// prior observer is stopped first.
    func start(onChange: @escaping () async -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        stop()
        self.onChange = onChange

        let query = HKObserverQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            let box = CompletionBox(complete: completionHandler)
            if let error {
                WorkoutRecoveryDiagnostics.logObserverError(error)
                box.complete()
                return
            }
            Task { @MainActor in
                await self?.onChange?()
                box.complete()
            }
        }
        self.observerQuery = query
        healthStore.execute(query)

        Task { @MainActor in
            do {
                try await healthStore.enableBackgroundDelivery(
                    for: HKObjectType.workoutType(), frequency: .immediate
                )
            } catch {
                // Foreground drains still cover discovery; not fatal.
                WorkoutRecoveryDiagnostics.logBackgroundDeliveryUnavailable(error)
            }
        }
    }

    func stop() {
        if let observerQuery {
            healthStore.stop(observerQuery)
            self.observerQuery = nil
        }
    }
}
