//
//  ExerciseProgressMetricTitleTests.swift
//  GymStreakTests
//
//  Ticket 01 (chart-metric-tab-title) — selecting "Gesch. 1RM" made the tab row read
//  `Gesch. 1RM | Gesch. 1RM | Gesamtvolumen`: the max-weight tab was wired through
//  `selectedMetricTitle`, which describes the *selected* metric, so it renamed itself to
//  whatever was selected and the first metric became unreachable by name.
//
//  The rename it was actually there for is narrow and still valid: a counterweight
//  exercise charted in entered weight plots assistance on the max-weight axis. That is a
//  property of the metric and the exercise, never of the selection — which is what these
//  tests pin, per metric and across every selection.
//

import Foundation
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct ExerciseProgressMetricTitleTests {

    // MARK: - A plain resistance exercise

    @Test("Every tab keeps its own name whatever is selected")
    func resistanceTitlesAreIndependentOfTheSelection() async {
        let viewModel = makeViewModel(loadBehavior: .resistance)
        await loadUntilSettled(viewModel)

        for selection in ProgressMetric.allCases {
            viewModel.selectedMetric = selection

            for metric in ProgressMetric.allCases {
                #expect(viewModel.title(for: metric) == metric.localizedTitle)
            }
            // The bug in one line: two tabs carrying the same name.
            let titles = ProgressMetric.allCases.map { viewModel.title(for: $0) }
            #expect(Set(titles).count == ProgressMetric.allCases.count)
        }
    }

    // MARK: - Counterweight assistance, charted in entered weight

    @Test("The max-weight tab reads as assistance under every selection")
    func assistedEnteredWeightRenamesOnlyMaxWeight() async {
        let viewModel = makeViewModel(loadBehavior: .counterweightAssistance, hasBodyWeight: false)
        await loadUntilSettled(viewModel)

        #expect(viewModel.progressData?.usesEffectiveLoad == false)

        for selection in ProgressMetric.allCases {
            viewModel.selectedMetric = selection

            #expect(viewModel.title(for: .maxWeight) == "exercise.assistance".localized)
            #expect(viewModel.title(for: .maxWeight) != "exercise.assistance")
            #expect(viewModel.title(for: .maxWeight) != ProgressMetric.maxWeight.localizedTitle)
            // The rename is the max-weight axis's alone.
            #expect(viewModel.title(for: .estimated1RM) == ProgressMetric.estimated1RM.localizedTitle)
            #expect(viewModel.title(for: .volume) == ProgressMetric.volume.localizedTitle)
        }
    }

    // MARK: - Counterweight assistance, charted in effective load

    @Test("Effective load keeps the plain max-weight wording")
    func assistedEffectiveLoadKeepsMaxWeight() async {
        let viewModel = makeViewModel(loadBehavior: .counterweightAssistance, hasBodyWeight: true)
        await loadUntilSettled(viewModel)

        #expect(viewModel.progressData?.usesEffectiveLoad == true)

        for selection in ProgressMetric.allCases {
            viewModel.selectedMetric = selection
            for metric in ProgressMetric.allCases {
                #expect(viewModel.title(for: metric) == metric.localizedTitle)
            }
        }
    }

    // MARK: - The header still names the selection

    @Test("The stat header follows the selected metric through the same rule")
    func headerNamesTheSelectedMetric() async {
        let resistance = makeViewModel(loadBehavior: .resistance)
        await loadUntilSettled(resistance)

        for selection in ProgressMetric.allCases {
            resistance.selectedMetric = selection
            #expect(resistance.selectedMetricTitle == selection.localizedTitle)
            #expect(resistance.selectedMetricTitle == resistance.title(for: selection))
        }

        // One rule, one implementation: the header inherits the assistance rename rather
        // than repeating it.
        let assisted = makeViewModel(loadBehavior: .counterweightAssistance, hasBodyWeight: false)
        await loadUntilSettled(assisted)
        assisted.selectedMetric = .maxWeight
        #expect(assisted.selectedMetricTitle == "exercise.assistance".localized)
        assisted.selectedMetric = .volume
        #expect(assisted.selectedMetricTitle == ProgressMetric.volume.localizedTitle)
    }

    // MARK: - Harness

    private func makeViewModel(
        loadBehavior: ExerciseLoadBehavior,
        hasBodyWeight: Bool = false
    ) -> ExerciseProgressViewModel {
        ExerciseProgressViewModel(
            exerciseName: "Bizeps Curls",
            exerciseId: UUID(),
            provider: StubMetricTitleProvider(
                loadBehavior: loadBehavior,
                usesEffectiveLoad: hasBodyWeight
            ),
            legacyAttribution: RecordingLegacyHistoryAttribution(),
            proEntitlements: StubProEntitlements(),
            paywalls: RecordingPaywallPresenter()
        )
    }
}

// MARK: - Double

/// A two-point series on one usage, with the exercise's load behaviour configurable —
/// enough to drive the title rule without a store.
private actor StubMetricTitleProvider: HistorySnapshotProviding {

    struct Unused: Error {}

    private let loadBehavior: ExerciseLoadBehavior
    private let usesEffectiveLoad: Bool

    init(loadBehavior: ExerciseLoadBehavior, usesEffectiveLoad: Bool) {
        self.loadBehavior = loadBehavior
        self.usesEffectiveLoad = usesEffectiveLoad
    }

    func fetchTrainingSnapshot(referenceDate: Date) async throws -> HistorySnapshot { throw Unused() }

    func fetchFortschrittSnapshot() async throws -> [FortschrittExerciseModel] { [] }

    func fetchPRDetails(sessionID: UUID) async throws -> [UUID: PersonalRecordService.PRDetail] { [:] }

    func fetchExerciseProgress(
        exerciseName: String,
        exerciseId: UUID?,
        startDate: Date,
        recentSessionLimit: Int,
        usageSelection: ExerciseUsageSelection?
    ) async throws -> ExerciseProgressSnapshot {
        let usage = ExerciseUsage(
            key: .routineSlot(UUID()),
            targetRepMin: 8,
            targetRepMax: 12,
            routineName: "Pull"
        )
        let points = [
            ExerciseProgressDataPoint(
                date: Date().addingTimeInterval(-86_400 * 7),
                maxWeight: 20,
                estimated1RM: 23,
                totalVolume: 600,
                totalSets: 3,
                totalReps: 30,
                workoutSessionId: UUID()
            ),
            ExerciseProgressDataPoint(
                date: Date(),
                maxWeight: 18,
                estimated1RM: 21,
                totalVolume: 540,
                totalSets: 3,
                totalReps: 30,
                workoutSessionId: UUID()
            )
        ]
        return ExerciseProgressSnapshot(
            data: ExerciseProgressData(
                exerciseName: exerciseName,
                dataPoints: points,
                loadBehavior: loadBehavior,
                usesEffectiveLoad: usesEffectiveLoad
            ),
            recentUsages: [],
            availableUsages: [
                ExerciseUsageOption(usage: usage, lastPerformed: Date(), lastPerformedOrder: 0)
            ],
            selectedUsage: .usage(usage.key)
        )
    }

    func fetchPreviousPerformances(
        _ lookup: PreviousPerformanceLookup
    ) async throws -> [UUID: PreviousExercisePerformance] { [:] }
}
