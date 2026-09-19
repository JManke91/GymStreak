//
//  HeartRateZonesTests.swift
//  GymStreakTests
//
//  Personal heart-rate zones for fight conditioning (docs/fight-conditioning.md):
//  the HRmax estimate, % HRmax, Karvonen, validation, which efforts get a
//  target, persistence, the Apple Health pre-fill and the preview guidance.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
struct HeartRateZonesTests {

    // MARK: - Math

    @Test("HRmax estimate is 208 − 0.7 × age, rounded")
    func estimate() {
        #expect(HeartRateZones.estimatedMaxHeartRate(age: 30) == 187)
        #expect(HeartRateZones.estimatedMaxHeartRate(age: 40) == 180)
        #expect(HeartRateZones.estimatedMaxHeartRate(age: 20) == 194)
    }

    @Test("Without resting HR the aerobic zone is 60–75 % of the estimated max")
    func percentOfMax() throws {
        let target = try #require(HeartRateZones.aerobicTarget(for: HeartRateProfile(age: 30)))
        #expect(target.lowerBPM == 112) // 0.60 × 187 = 112.2
        #expect(target.upperBPM == 140) // 0.75 × 187 = 140.25
        #expect(target.method == .percentOfMax)
        #expect(target.lowerPercent == 60 && target.upperPercent == 75)
        #expect(target.isMaxEstimated)
    }

    @Test("A measured max replaces the estimate and is not flagged as one")
    func measuredMax() throws {
        let profile = HeartRateProfile(maxSource: .measured, age: 30, measuredMaxHeartRate: 200)
        let target = try #require(HeartRateZones.aerobicTarget(for: profile))
        #expect(target.lowerBPM == 120)
        #expect(target.upperBPM == 150)
        #expect(!target.isMaxEstimated)
    }

    @Test("With resting HR the zone is 50–70 % of heart-rate reserve (Karvonen)")
    func karvonen() throws {
        let profile = HeartRateProfile(maxSource: .measured, measuredMaxHeartRate: 190, restingHeartRate: 60)
        let target = try #require(HeartRateZones.aerobicTarget(for: profile))
        #expect(target.lowerBPM == 125) // 60 + 0.5 × 130
        #expect(target.upperBPM == 151) // 60 + 0.7 × 130
        #expect(target.method == .heartRateReserve)
    }

    // MARK: - Validation

    @Test("The active source's value is required; the inactive one is ignored")
    func missingValues() {
        #expect(HeartRateZones.validate(HeartRateProfile()) == [.missingAge])
        #expect(HeartRateZones.validate(HeartRateProfile(maxSource: .measured, age: 30)) == [.missingMaxHeartRate])
        #expect(HeartRateZones.validate(HeartRateProfile(maxSource: .measured, age: 5, measuredMaxHeartRate: 190)).isEmpty)
    }

    @Test("Implausible input is rejected", arguments: [
        (HeartRateProfile(age: 8), HeartRateZones.ValidationIssue.ageOutOfRange),
        (HeartRateProfile(age: 140), .ageOutOfRange),
        (HeartRateProfile(maxSource: .measured, measuredMaxHeartRate: 90), .maxHeartRateOutOfRange),
        (HeartRateProfile(maxSource: .measured, measuredMaxHeartRate: 260), .maxHeartRateOutOfRange),
        (HeartRateProfile(age: 30, restingHeartRate: 20), .restingHeartRateOutOfRange),
        (HeartRateProfile(age: 30, restingHeartRate: 150), .restingHeartRateOutOfRange),
        (HeartRateProfile(maxSource: .measured, measuredMaxHeartRate: 140, restingHeartRate: 110), .restingTooCloseToMax),
    ])
    func implausible(profile: HeartRateProfile, issue: HeartRateZones.ValidationIssue) {
        #expect(HeartRateZones.validate(profile) == [issue])
        #expect(HeartRateZones.aerobicTarget(for: profile) == nil)
    }

    @Test("Medication turns every target off and needs no numbers")
    func medication() {
        let profile = HeartRateProfile(age: 30, usesHeartRateMedication: true)
        #expect(HeartRateZones.validate(HeartRateProfile(usesHeartRateMedication: true)).isEmpty)
        #expect(HeartRateZones.aerobicTarget(for: profile) == nil)
        #expect(HeartRateZones.target(for: .conversational, profile: profile) == nil)
    }

    // MARK: - Which efforts get a target

    @Test("Only the conversational aerobic effort has a heart-rate target")
    func onlyConversational() {
        let profile = HeartRateProfile(age: 30)
        #expect(HeartRateZones.target(for: .conversational, profile: profile) != nil)
        for effort in [ConditioningEffort.easy, .strongBurst, .hardRepeatable, .maximal, .subMaximal] {
            #expect(HeartRateZones.target(for: effort, profile: profile) == nil)
        }
        #expect(HeartRateZones.target(for: .conversational, profile: nil) == nil)
    }
}

// MARK: - Store, editor, preview guidance

@MainActor
@Suite
struct HeartRateProfilePresentationTests {

    private func throwawayDefaults() -> UserDefaults {
        let name = "HeartRateProfileTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("The profile persists across store instances and clears to nil")
    func persistence() {
        let defaults = throwawayDefaults()
        let profile = HeartRateProfile(maxSource: .measured, age: 41, measuredMaxHeartRate: 184,
                                       restingHeartRate: 52, usesHeartRateMedication: true)
        HeartRateProfileStore(defaults: defaults).heartRateProfile = profile
        #expect(HeartRateProfileStore(defaults: defaults).heartRateProfile == profile)

        HeartRateProfileStore(defaults: defaults).heartRateProfile = nil
        #expect(HeartRateProfileStore(defaults: defaults).heartRateProfile == nil)
    }

    @Test("Health pre-fill fills only what it found; save refuses an invalid draft")
    func editor() async {
        let store = HeartRateProfileStore(defaults: throwawayDefaults())
        let reader = StubHeartRateHealthReader(prefill: HeartRateHealthPrefill(age: 34, restingHeartRate: nil))
        let editor = HeartRateProfileEditorViewModel(store: store, healthReader: reader)

        #expect(!editor.save())
        #expect(store.heartRateProfile == nil)

        editor.draft.restingHeartRate = 58
        await editor.prefillFromHealth()
        #expect(editor.prefillState == .filled)
        #expect(editor.draft.age == 34)
        #expect(editor.draft.restingHeartRate == 58)

        #expect(editor.save())
        #expect(store.heartRateProfile?.age == 34)
    }

    @Test("The Health peak is only suggested; using it switches to a measured max")
    func peakSuggestion() async {
        let store = HeartRateProfileStore(defaults: throwawayDefaults())
        let editor = HeartRateProfileEditorViewModel(
            store: store,
            healthReader: StubHeartRateHealthReader(prefill: HeartRateHealthPrefill(
                age: nil, restingHeartRate: nil, peakHeartRate: 192
            ))
        )
        await editor.prefillFromHealth()
        #expect(editor.prefillState == .idle) // a peak alone fills no field
        #expect(editor.suggestedMaxHeartRate == 192)
        #expect(editor.draft.maxSource == .estimatedFromAge)
        #expect(editor.draft.measuredMaxHeartRate == nil)

        editor.useSuggestedMax()
        #expect(editor.draft.maxSource == .measured)
        #expect(editor.draft.measuredMaxHeartRate == 192)
        #expect(editor.suggestedMaxHeartRate == nil)
        #expect(editor.save())
        #expect(store.heartRateProfile?.measuredMaxHeartRate == 192)
    }

    @Test("Ignoring the Health peak leaves the draft untouched")
    func peakDismissed() async {
        let editor = HeartRateProfileEditorViewModel(
            store: HeartRateProfileStore(defaults: throwawayDefaults()),
            healthReader: StubHeartRateHealthReader(prefill: HeartRateHealthPrefill(
                age: 30, restingHeartRate: nil, peakHeartRate: 192
            ))
        )
        await editor.prefillFromHealth()
        editor.dismissSuggestedMax()
        #expect(editor.suggestedMaxHeartRate == nil)
        #expect(editor.draft.maxSource == .estimatedFromAge)
        #expect(editor.draft.measuredMaxHeartRate == nil)
    }

    @Test("Health pre-fill that finds nothing says so")
    func prefillNothing() async {
        let editor = HeartRateProfileEditorViewModel(
            store: HeartRateProfileStore(defaults: throwawayDefaults()),
            healthReader: StubHeartRateHealthReader(prefill: HeartRateHealthPrefill(age: nil, restingHeartRate: nil))
        )
        await editor.prefillFromHealth()
        #expect(editor.prefillState == .nothingFound)
    }

    @Test("Preview guidance: alactic never gets a target, aerobic follows the profile")
    func guidance() {
        let store = HeartRateProfileStore(defaults: throwawayDefaults())
        let library = ConditioningLibraryViewModel(
            safety: StubSafety(),
            heartRateProfile: store,
            makeRun: { _ in fatalError("not started in this test") },
            makeHeartRateEditor: { fatalError("not opened in this test") }
        )

        #expect(library.heartRateGuidance(for: ConditioningLibrary.alacticPower) == .maximalIntent)
        #expect(library.heartRateGuidance(for: ConditioningLibrary.lactic30) == .none)
        #expect(library.heartRateGuidance(for: ConditioningLibrary.aerobicBase) == .needsSetup)

        store.heartRateProfile = HeartRateProfile(age: 30)
        #expect(library.heartRateGuidance(for: ConditioningLibrary.aerobicBase)
                == .target(HeartRateZones.aerobicTarget(for: store.heartRateProfile)!))
        #expect(library.heartRateGuidance(for: ConditioningLibrary.alacticPower) == .maximalIntent)

        store.heartRateProfile = HeartRateProfile(age: 30, usesHeartRateMedication: true)
        #expect(library.heartRateGuidance(for: ConditioningLibrary.aerobicBase) == .rpeOnly)
    }
}

@MainActor
private final class StubHeartRateHealthReader: HeartRateProfileHealthReading {
    let prefill: HeartRateHealthPrefill
    init(prefill: HeartRateHealthPrefill) { self.prefill = prefill }
    var isHealthDataAvailable: Bool { true }
    func readPrefill() async -> HeartRateHealthPrefill { prefill }
}

@MainActor
private final class StubSafety: ConditioningSafetyAcknowledging {
    var hasAcknowledgedSafety = true
    func recordSafetyAcknowledged() {}
}
