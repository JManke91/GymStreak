//
//  HeartRateProfileEditorViewModel.swift
//  GymStreak
//
//  Edits the conditioning heart-rate profile: max-HR source, age or measured
//  max, optional resting HR, the medication switch, and the optional Apple
//  Health pre-fill. See docs/fight-conditioning.md.
//

import Foundation
import Observation

@Observable
@MainActor
final class HeartRateProfileEditorViewModel {

    enum PrefillState: Equatable {
        case idle, reading, filled, nothingFound
    }

    var draft: HeartRateProfile
    private(set) var prefillState: PrefillState = .idle
    /// The Apple Health peak, offered as a measured max until the user takes or dismisses it.
    private(set) var suggestedMaxHeartRate: Int?

    @ObservationIgnored private let store: any HeartRateProfileStoring
    @ObservationIgnored private let healthReader: any HeartRateProfileHealthReading

    init(store: any HeartRateProfileStoring, healthReader: any HeartRateProfileHealthReading) {
        self.store = store
        self.healthReader = healthReader
        self.draft = store.heartRateProfile ?? HeartRateProfile()
    }

    var issues: [HeartRateZones.ValidationIssue] { HeartRateZones.validate(draft) }
    var canSave: Bool { issues.isEmpty }
    /// The zone the current draft produces — the live preview under the form.
    var aerobicTarget: HeartRateTarget? { HeartRateZones.aerobicTarget(for: draft) }
    var estimatedMaxHeartRate: Int? { draft.age.map(HeartRateZones.estimatedMaxHeartRate(age:)) }
    var canPrefillFromHealth: Bool { healthReader.isHealthDataAvailable }

    func prefillFromHealth() async {
        prefillState = .reading
        let prefill = await healthReader.readPrefill()
        if let age = prefill.age { draft.age = age }
        if let resting = prefill.restingHeartRate { draft.restingHeartRate = resting }
        suggestedMaxHeartRate = prefill.peakHeartRate
        // `.filled` only when a field was actually filled: a peak alone is just a
        // suggestion, and after "Ignore" the footer must not claim anything was filled.
        if prefill.age != nil || prefill.restingHeartRate != nil {
            prefillState = .filled
        } else {
            prefillState = prefill.peakHeartRate == nil ? .nothingFound : .idle
        }
    }

    func useSuggestedMax() {
        guard let suggestedMaxHeartRate else { return }
        draft.maxSource = .measured
        draft.measuredMaxHeartRate = suggestedMaxHeartRate
        self.suggestedMaxHeartRate = nil
    }

    func dismissSuggestedMax() {
        suggestedMaxHeartRate = nil
    }

    /// Writes the draft; returns whether it was valid enough to save.
    @discardableResult
    func save() -> Bool {
        guard canSave else { return false }
        store.heartRateProfile = draft
        return true
    }
}

/// Presented with `.sheet(item:)`; identity is the instance (`AnyObject` default `id`).
extension HeartRateProfileEditorViewModel: Identifiable {}
