//
//  ExerciseProgressStatCardTests.swift
//  GymStreakTests
//
//  Ticket 04 — the three stat cards above the chart (REKORD / TREND / WORKOUTS) must
//  describe the *selected* usage, not a blend of all of them. The reporter's screen read
//  "REKORD 20.0 kg" and "TREND +42.9%" over sessions that were mostly 14–15 kg work:
//  both numbers arithmetically correct over the blended series, both useless.
//
//  Two halves: the aggregator half pins that record, trend and workout count are computed
//  over exactly the points the chart plots for a selection; the view-model half pins that
//  the combined view withholds the trend rather than presenting a blend as progression.
//
//  The view-model half drives `loadUntilSettled` rather than a bare `load()`: since ticket
//  05b the screen may spend one extra load moving onto the window its data is actually in,
//  and this stub dates its usages far in the past.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct ExerciseProgressStatCardTests {

    // MARK: - The cards follow the selection

    /// The reporter's shape: one exercise trained heavy in one slot and light in another,
    /// alternating week by week. Blended, the series runs 20 → 14 → 20 → 15.
    @Test("Record, trend and workout count are per usage, not per exercise")
    func statsDescribeTheSelectedUsage() throws {
        let fixture = try TwoUsageHistory()

        let heavy = fixture.snapshot(for: .usage(fixture.heavyKey)).data
        #expect(heavy.dataPoints.map(\.maxWeight) == [20, 20])
        #expect(heavy.personalRecord == 20)
        // The heavy slot stalled. Nothing the light slot did may hide that.
        #expect(heavy.progressPercentage(for: .maxWeight) == 0)
        #expect(heavy.sessionCount == 2)

        let light = fixture.snapshot(for: .usage(fixture.lightKey)).data
        #expect(light.dataPoints.map(\.maxWeight) == [14, 15])
        // The light slot's own best — not the heavy slot's 20 kg personal record.
        #expect(light.personalRecord == 15)
        #expect(light.progressPercentage(for: .maxWeight).map { ($0 * 100).rounded() } == 714)
        #expect(light.sessionCount == 2)
    }

    @Test("The combined view keeps the all-usage record and counts every plotted workout")
    func combinedRecordAndCountSpanEveryUsage() throws {
        let fixture = try TwoUsageHistory()

        let combined = fixture.snapshot(for: .combined).data

        #expect(combined.dataPoints.map(\.maxWeight) == [20, 14, 20, 15])
        // Defensible across usages: it is the best this exercise was ever lifted.
        #expect(combined.personalRecord == 20)
        #expect(combined.sessionCount == 4)
    }

    @Test("A counterweight usage keeps the inverted record and trend under selection")
    func assistedUsageKeepsItsInvertedSemantics() throws {
        let fixture = try TwoUsageHistory(loadBehavior: .counterweightAssistance)

        // Less assistance is the better set, so the record is the *lowest* number and a
        // falling series is progress.
        let light = fixture.snapshot(for: .usage(fixture.lightKey)).data
        #expect(light.dataPoints.map(\.maxWeight) == [14, 15])
        #expect(light.personalRecord == 14)
        // 14 → 15 kg of assistance is a regression: −7.1%, not +7.1%.
        #expect(light.progressPercentage(for: .maxWeight).map { ($0 * 100).rounded() } == -714)

        let heavy = fixture.snapshot(for: .usage(fixture.heavyKey)).data
        #expect(heavy.personalRecord == 20)
        #expect(heavy.progressPercentage(for: .maxWeight) == 0)
    }

    @Test("A recent-sets card names the least-assisted set as its best")
    func assistedRecentCardInvertsItsBestSet() {
        let sets = [
            ExerciseRecentUsage.SetEntry(id: UUID(), weight: 20, reps: 8),
            ExerciseRecentUsage.SetEntry(id: UUID(), weight: 14, reps: 10)
        ]

        // Assistance: the 14 kg set is the one carrying the most of the user's own weight.
        #expect(makeCard(sets: sets, loadBehavior: .counterweightAssistance).bestSet?.weight == 14)
        #expect(makeCard(sets: sets, loadBehavior: .resistance).bestSet?.weight == 20)
    }

    @Test("The aggregator hands each card the exercise's load behaviour")
    func recentCardsCarryTheLoadBehaviour() throws {
        let assisted = try TwoUsageHistory(loadBehavior: .counterweightAssistance)
        #expect(
            assisted.snapshot(for: .usage(assisted.lightKey)).recentUsages
                .allSatisfy { $0.loadBehavior == .counterweightAssistance }
        )

        let resistance = try TwoUsageHistory()
        #expect(
            resistance.snapshot(for: .usage(resistance.lightKey)).recentUsages
                .allSatisfy { $0.loadBehavior == .resistance }
        )
    }

    private func makeCard(
        sets: [ExerciseRecentUsage.SetEntry],
        loadBehavior: ExerciseLoadBehavior
    ) -> ExerciseRecentUsage {
        ExerciseRecentUsage(
            id: UUID(),
            workoutSessionId: UUID(),
            date: Date(),
            usage: ExerciseUsage(key: .unattributed, targetRepMin: nil, targetRepMax: nil, routineName: ""),
            sets: sets,
            loadBehavior: loadBehavior
        )
    }

    // MARK: - What the combined view prints

    @Test("The combined view withholds the trend instead of blending two usages")
    func combinedViewWithholdsTheTrend() async {
        let harness = makeHarness(usageCount: 2, selection: .combined)

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.chartsSeveralUsagesTogether)
        #expect(harness.viewModel.trendPercentageString == nil)
        #expect(harness.viewModel.hasTrendValue == false)
        #expect(harness.viewModel.trendIsPositive == false)
        // Not a bare dash: the card says why there is no number, and the picker is on the
        // same screen.
        #expect(harness.viewModel.trendValueString == "chart.trend.mixed".localized)
        #expect(harness.viewModel.trendValueString != "chart.trend.mixed")
        // The other two cards still describe the plotted series.
        #expect(harness.viewModel.personalRecordString == "90.0 kg")
        #expect(harness.viewModel.sessionCountString == "2")
    }

    @Test("A selected usage prints its own trend")
    func selectedUsagePrintsItsTrend() async {
        let harness = makeHarness(usageCount: 2, selection: .usage(.routineSlot(UUID())))

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.chartsSeveralUsagesTogether == false)
        #expect(harness.viewModel.hasTrendValue)
        #expect(harness.viewModel.trendPercentageString == "+12.5%")
        #expect(harness.viewModel.trendValueString == "+12.5%")
        #expect(harness.viewModel.trendIsPositive)
    }

    @Test("An exercise with one usage keeps its trend in the combined view")
    func singleUsageCombinedIsNotABlend() async {
        // `.combined` over one usage *is* that usage — withholding the number there would
        // remove a correct trend from almost every exercise in the app.
        let harness = makeHarness(usageCount: 1, selection: .combined)

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.chartsSeveralUsagesTogether == false)
        #expect(harness.viewModel.trendPercentageString == "+12.5%")
    }

    @Test("A blended series withholds the trend for every metric, locked or free")
    func blendedTrendIsWithheldUnderTheProGate() async {
        let harness = makeHarness(usageCount: 2, selection: .combined, isGatingEnabled: true)

        await loadUntilSettled(harness.viewModel)
        harness.viewModel.updateMetric(.estimated1RM)

        // The gate falls the stat cards back to the free metric; the blend rule still
        // withholds that metric's trend rather than printing a blended free number.
        #expect(harness.viewModel.isMetricLocked(.estimated1RM))
        #expect(harness.viewModel.personalRecordString == "90.0 kg")
        #expect(harness.viewModel.trendValueString == "chart.trend.mixed".localized)
    }

    // MARK: - Harness

    private struct Harness {
        let viewModel: ExerciseProgressViewModel
        let provider: StubUsageSeriesProvider
    }

    private func makeHarness(
        usageCount: Int,
        selection: ExerciseUsageSelection,
        isGatingEnabled: Bool = false
    ) -> Harness {
        let provider = StubUsageSeriesProvider(usageCount: usageCount, selection: selection)
        return Harness(
            viewModel: ExerciseProgressViewModel(
                exerciseName: "Bizeps Curls",
                exerciseId: UUID(),
                provider: provider,
                proEntitlements: StubProEntitlements(),
                paywalls: RecordingPaywallPresenter(),
                isGatingEnabled: isGatingEnabled
            ),
            provider: provider
        )
    }
}

// MARK: - Fixtures

/// One exercise trained two ways, alternating: 20 kg in a 4–6 slot, 14 then 15 kg in an
/// 8–12 slot. Built through the real aggregator over a real in-memory store, so the
/// assertions pin the numbers the screen actually receives.
@MainActor
private struct TwoUsageHistory {

    let heavyKey: ExerciseUsage.Key
    let lightKey: ExerciseUsage.Key

    private let sessions: [WorkoutSession]
    private let exercise: Exercise

    init(loadBehavior: ExerciseLoadBehavior = .resistance) throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let exercise = Exercise(name: "Bizeps Curls")
        exercise.loadBehavior = loadBehavior
        context.insert(exercise)

        let heavySlot = UUID()
        let lightSlot = UUID()
        let block: [(slot: UUID, repMin: Int, repMax: Int, weight: Double, reps: Int)] = [
            (heavySlot, 4, 6, 20, 5),
            (lightSlot, 8, 12, 14, 10),
            (heavySlot, 4, 6, 20, 5),
            (lightSlot, 8, 12, 15, 10)
        ]
        for (index, entry) in block.enumerated() {
            let session = WorkoutSession(routine: nil)
            session.startTime = Date(timeIntervalSince1970: 1_000 * Double(index + 1))
            session.endTime = session.startTime.addingTimeInterval(600)
            context.insert(session)

            let workoutExercise = WorkoutExercise(
                exerciseName: exercise.name,
                muscleGroups: ["Arms"],
                order: 0,
                exerciseId: exercise.id,
                routineExerciseId: entry.slot,
                loadBehavior: loadBehavior
            )
            workoutExercise.targetRepMin = entry.repMin
            workoutExercise.targetRepMax = entry.repMax
            workoutExercise.workoutSession = session
            context.insert(workoutExercise)

            let set = WorkoutSet(
                plannedReps: entry.reps,
                actualReps: entry.reps,
                plannedWeight: entry.weight,
                actualWeight: entry.weight,
                restTime: 60,
                order: 0
            )
            set.isCompleted = true
            set.workoutExercise = workoutExercise
            context.insert(set)
        }
        try context.save()

        self.exercise = exercise
        self.sessions = try context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endTime != nil })
        )
        heavyKey = .routineSlot(heavySlot)
        lightKey = .routineSlot(lightSlot)
    }

    func snapshot(for selection: ExerciseUsageSelection) -> ExerciseProgressSnapshot {
        ExerciseProgressAggregator.buildSnapshot(
            sessions: sessions,
            liveExercises: [exercise],
            exerciseName: exercise.name,
            exerciseId: exercise.id,
            startDate: .distantPast,
            recentSessionLimit: 8,
            requestedUsage: selection
        )
    }
}

// MARK: - Double

/// A two-point rising series (80 → 90 kg, +12.5%) beside a configurable number of usage
/// options — enough to drive every branch of the trend card without a store.
private actor StubUsageSeriesProvider: HistorySnapshotProviding {

    struct Unused: Error {}

    private let usageCount: Int
    private let selection: ExerciseUsageSelection

    init(usageCount: Int, selection: ExerciseUsageSelection) {
        self.usageCount = usageCount
        self.selection = selection
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
        let sessionId = UUID()
        let points = [
            ExerciseProgressDataPoint(
                date: Date().addingTimeInterval(-86_400 * 7),
                maxWeight: 80,
                estimated1RM: 92,
                totalVolume: 2_400,
                totalSets: 3,
                totalReps: 30,
                workoutSessionId: sessionId
            ),
            ExerciseProgressDataPoint(
                date: Date(),
                maxWeight: 90,
                estimated1RM: 104,
                totalVolume: 2_700,
                totalSets: 3,
                totalReps: 30,
                workoutSessionId: UUID()
            )
        ]
        let options = (0..<usageCount).map { index in
            ExerciseUsageOption(
                usage: ExerciseUsage(
                    key: .routineSlot(UUID()),
                    targetRepMin: 4 + index,
                    targetRepMax: 6 + index,
                    routineName: "Pull"
                ),
                // Dated in 2023 while the data points above are dated today: this stub
                // ignores `startDate`, so the opening-window rule (05b) settles the screen
                // on its widest unlocked window and the series is returned either way.
                // Synthetic, and deliberately so — these cases pin the stat cards, not the
                // window.
                lastPerformed: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                lastPerformedOrder: index
            )
        }
        return ExerciseProgressSnapshot(
            data: ExerciseProgressData(exerciseName: exerciseName, dataPoints: points),
            recentUsages: [],
            availableUsages: options,
            selectedUsage: selection
        )
    }

    func fetchPreviousPerformances(
        _ lookup: PreviousPerformanceLookup
    ) async throws -> [UUID: PreviousExercisePerformance] { [:] }
}
