//
//  HealthKitHeartRateProfileReader.swift
//  GymStreak
//
//  Reads date of birth and the latest resting heart rate from Apple Health to
//  pre-fill the conditioning heart-rate profile. Read-only; asked for only when
//  the user taps "Fill from Apple Health". See docs/fight-conditioning.md.
//

import Foundation
import HealthKit

@MainActor
final class HealthKitHeartRateProfileReader: HeartRateProfileHealthReading {

    private let healthStore = HKHealthStore()
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func readPrefill() async -> HeartRateHealthPrefill {
        guard isHealthDataAvailable else { return HeartRateHealthPrefill(age: nil, restingHeartRate: nil) }
        let restingType = HKQuantityType(.restingHeartRate)
        let heartRateType = HKQuantityType(.heartRate)
        do {
            try await healthStore.requestAuthorization(
                toShare: [],
                read: [HKCharacteristicType(.dateOfBirth), restingType, heartRateType]
            )
        } catch {
            return HeartRateHealthPrefill(age: nil, restingHeartRate: nil)
        }
        return HeartRateHealthPrefill(
            age: readAge(),
            restingHeartRate: await readLatestRestingHeartRate(restingType),
            peakHeartRate: await readPeakHeartRate(heartRateType)
        )
    }

    /// The highest heart-rate sample of the lookback window, computed by HealthKit
    /// (`.discreteMax`) rather than by fetching months of samples. A value outside the
    /// plausible max range is a sensor artifact and is dropped.
    private func readPeakHeartRate(_ type: HKQuantityType) async -> Int? {
        let end = Date.now
        guard let start = calendar.date(byAdding: .month, value: -HeartRateZones.peakLookbackMonths, to: end) else {
            return nil
        }
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .discreteMax
        )
        guard let quantity = try? await descriptor.result(for: healthStore)?.maximumQuantity() else { return nil }
        let bpm = Int(quantity.doubleValue(for: .count().unitDivided(by: .minute())).rounded())
        return HeartRateZones.maxHeartRateRange.contains(bpm) ? bpm : nil
    }

    /// Throws both when access is denied and when no birthday is set — neither
    /// is distinguishable, and both mean "leave the field empty".
    private func readAge() -> Int? {
        guard let birthday = try? healthStore.dateOfBirthComponents(),
              let date = calendar.date(from: birthday) else { return nil }
        return calendar.dateComponents([.year], from: date, to: .now).year
    }

    private func readLatestRestingHeartRate(_ type: HKQuantityType) async -> Int? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try? await descriptor.result(for: healthStore).first else { return nil }
        return Int(sample.quantity.doubleValue(for: .count().unitDivided(by: .minute())).rounded())
    }
}
