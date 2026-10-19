//
//  HealthKitConditioningHeartRateReader.swift
//  GymStreak
//
//  Reads the heart-rate samples of a conditioning session's time window for its
//  share card. Read-only, and never asks for access: heart-rate read access is part
//  of the workout authorization. See docs/workout-sharing.md.
//

import Foundation
import HealthKit

@MainActor
final class HealthKitConditioningHeartRateReader: ConditioningHeartRateReading {

    private let healthStore = HKHealthStore()

    func readings(from start: Date, to end: Date) async -> [HeartRateReading] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        // No options: a sample overlapping either edge still counts; the summarizer
        // clamps it to the window.
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(
                type: HKQuantityType(.heartRate),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end)
            )],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: healthStore) else { return [] }
        let unit = HKUnit.count().unitDivided(by: .minute())
        // A series sample (count > 1) carries one summary value for its span; it is
        // treated as holding that value over the span.
        return samples.map {
            HeartRateReading(start: $0.startDate, end: $0.endDate, bpm: $0.quantity.doubleValue(for: unit))
        }
    }
}
