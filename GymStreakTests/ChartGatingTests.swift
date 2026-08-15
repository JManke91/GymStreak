//
//  ChartGatingTests.swift
//  GymStreakTests
//
//  P2 — progress analytics gating (docs/monetization-strategy.md §4.2a P2,
//  §3 Rule 2, §7). Two assertions carry the ticket: a Pro-only window is
//  *previewed*, never *fetched* — the blur covers the window the user is
//  entitled to, so the gate cannot cost more than the free path — and a lapse
//  or a resubscribe changes what is readable and nothing else.
//

import Testing
import Foundation
@testable import GymStreak

@Suite
@MainActor
struct ChartGatingTests {

    // MARK: - Free tier

    @Test("The free metric and the three free windows are never locked")
    func freeSelectionsAreUnlocked() {
        let harness = makeHarness()

        #expect(harness.viewModel.isMetricLocked(ProFeatureCaps.freeChartMetric) == false)
        for timeframe in ProFeatureCaps.freeChartTimeframes {
            #expect(harness.viewModel.isTimeframeLocked(timeframe) == false)
        }

        harness.viewModel.updateTimeframe(.threeMonths)

        #expect(harness.viewModel.isChartLocked == false)
        #expect(harness.viewModel.chartTimeframe == .threeMonths)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test("Estimated 1RM and volume are locked and raise chartMetric", arguments: [
        ProgressMetric.estimated1RM, .volume
    ])
    func proMetricsAreLocked(metric: ProgressMetric) {
        let harness = makeHarness()

        #expect(harness.viewModel.isMetricLocked(metric))

        harness.viewModel.updateMetric(metric)

        // Selected, so its own real series renders — blurred, per §3 Rule 2.
        #expect(harness.viewModel.selectedMetric == metric)
        #expect(harness.viewModel.isChartLocked)
        #expect(harness.viewModel.chartLockPlacement == .chartMetric)
        #expect(harness.paywalls.presentedPlacements == [.chartMetric])
    }

    @Test("The one-year and all-time windows are locked and raise chartWindow", arguments: [
        ChartTimeframe.year, .all
    ])
    func proWindowsAreLocked(timeframe: ChartTimeframe) {
        let harness = makeHarness()

        #expect(harness.viewModel.isTimeframeLocked(timeframe))

        harness.viewModel.updateTimeframe(timeframe)

        #expect(harness.viewModel.selectedTimeframe == timeframe)
        #expect(harness.viewModel.isChartLocked)
        #expect(harness.viewModel.chartLockPlacement == .chartWindow)
        #expect(harness.paywalls.presentedPlacements == [.chartWindow])
    }

    @Test("The lock card CTA raises the placement naming the locked capability")
    func unlockCTARaisesTheSpecificPlacement() {
        let harness = makeHarness()

        harness.viewModel.updateTimeframe(.all)
        harness.viewModel.requestChartUnlock()

        #expect(harness.paywalls.presentedPlacements == [.chartWindow, .chartWindow])
    }

    // MARK: - The preview must not cost more than the free path

    @Test("A locked window is previewed, not fetched")
    func lockedWindowDoesNotWidenTheFetch() async {
        let harness = makeHarness()
        harness.viewModel.updateTimeframe(.month)
        await harness.viewModel.load()

        harness.viewModel.updateTimeframe(.all)
        await harness.viewModel.load()

        // The chart keeps drawing the last window the user is entitled to, so
        // the reload asks for the same cutoff rather than all of history.
        #expect(harness.viewModel.chartTimeframe == .month)
        #expect(harness.viewModel.loadKey.timeframe == .month)
        let requested = await harness.provider.requestedStartDates
        #expect(requested.count == 2)
        #expect(requested.allSatisfy { $0 > Date.distantPast })
        let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        #expect(requested.allSatisfy { abs($0.timeIntervalSince(monthAgo)) < 60 })
    }

    @Test("A locked metric costs nothing — the series is already in the snapshot")
    func lockedMetricDoesNotRefetch() async {
        let harness = makeHarness()
        await harness.viewModel.load()

        harness.viewModel.updateMetric(.volume)
        let key = harness.viewModel.loadKey

        #expect(key.timeframe == .month)
        let requested = await harness.provider.requestedStartDates
        #expect(requested.count == 1)
    }

    @Test("The stat triple never prints a Pro number beside the blurred chart")
    func lockedMetricStatsFallBackToTheFreeMetric() async {
        let harness = makeHarness()
        await harness.viewModel.load()
        let freeMetricPR = harness.viewModel.personalRecordString

        harness.viewModel.updateMetric(.estimated1RM)

        #expect(harness.viewModel.personalRecordString == freeMetricPR)
    }

    // MARK: - Pro, Founder and the kill switch

    @Test("Pro and Founder users see every metric and every window", arguments: [
        ProEntitlementState.subscription, .lifetime, .founder
    ])
    func proAndFounderSeeEverything(state: ProEntitlementState) {
        let harness = makeHarness(state: state)

        for metric in ProgressMetric.allCases {
            #expect(harness.viewModel.isMetricLocked(metric) == false)
        }
        for timeframe in ChartTimeframe.allCases {
            #expect(harness.viewModel.isTimeframeLocked(timeframe) == false)
        }

        harness.viewModel.updateMetric(.volume)
        harness.viewModel.updateTimeframe(.all)

        #expect(harness.viewModel.isChartLocked == false)
        #expect(harness.viewModel.chartTimeframe == .all)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    @Test("With the kill switch off, the charts behave identically to today")
    func killSwitchOffBehavesAsBefore() {
        let harness = makeHarness(isGatingEnabled: false)

        harness.viewModel.updateMetric(.estimated1RM)
        harness.viewModel.updateTimeframe(.year)

        #expect(harness.viewModel.isMetricLocked(.estimated1RM) == false)
        #expect(harness.viewModel.isTimeframeLocked(.year) == false)
        #expect(harness.viewModel.isChartLocked == false)
        #expect(harness.viewModel.chartTimeframe == .year)
        #expect(harness.paywalls.presentedPlacements.isEmpty)
    }

    // MARK: - Lapse and resubscribe (§7, Rule 4)

    @Test("Resubscribing restores the full window immediately, with no migration")
    func resubscribeRestoresTheFullWindow() {
        let harness = makeHarness()
        harness.viewModel.updateTimeframe(.year)
        #expect(harness.viewModel.chartTimeframe == .month)

        harness.entitlements.state = .subscription

        // The load key changing is what reloads the year — no refresh gesture,
        // no stored state to migrate.
        #expect(harness.viewModel.isChartLocked == false)
        #expect(harness.viewModel.chartTimeframe == .year)
        #expect(harness.viewModel.loadKey.timeframe == .year)
    }

    @Test("A lapse narrows the window and blurs the chart, and destroys nothing")
    func lapseNarrowsWithoutLosingAnything() async {
        let harness = makeHarness(state: .subscription)
        harness.viewModel.updateMetric(.volume)
        harness.viewModel.updateTimeframe(.year)
        await harness.viewModel.load()
        #expect(harness.viewModel.progressData?.dataPoints.isEmpty == false)

        harness.entitlements.state = .free

        // The selection is kept, the chart blurs, and the window it renders
        // clamps back to the widest free one instead of re-fetching the year.
        #expect(harness.viewModel.selectedTimeframe == .year)
        #expect(harness.viewModel.selectedMetric == .volume)
        #expect(harness.viewModel.isChartLocked)
        #expect(harness.viewModel.chartTimeframe == .threeMonths)
        // Nothing already loaded was thrown away.
        #expect(harness.viewModel.progressData?.dataPoints.isEmpty == false)
        #expect(harness.viewModel.recentSessions.isEmpty == false)
    }

    // MARK: - The policy, without a view model
    //
    // §4.4 and §11 Q4 both anticipate retuning these, so the boundary is
    // asserted against explicit caps as well as against the shipped constants.

    @Test("The free metric and windows come from the caps, not from literals")
    func policyFollowsTheCaps() {
        #expect(ChartGatingPolicy.isMetricLocked(
            .volume, isPro: false, isGatingEnabled: true, freeMetric: .volume
        ) == false)
        #expect(ChartGatingPolicy.isMetricLocked(
            .maxWeight, isPro: false, isGatingEnabled: true, freeMetric: .volume
        ))
        #expect(ChartGatingPolicy.isTimeframeLocked(
            .year, isPro: false, isGatingEnabled: true, freeTimeframes: [.week, .year]
        ) == false)
        #expect(ChartGatingPolicy.isTimeframeLocked(
            .month, isPro: false, isGatingEnabled: true, freeTimeframes: [.week, .year]
        ))
    }

    @Test("Neither exemption gates anything")
    func policyExemptions() {
        for metric in ProgressMetric.allCases {
            #expect(ChartGatingPolicy.isMetricLocked(metric, isPro: true, isGatingEnabled: true) == false)
            #expect(ChartGatingPolicy.isMetricLocked(metric, isPro: false, isGatingEnabled: false) == false)
        }
        for timeframe in ChartTimeframe.allCases {
            #expect(ChartGatingPolicy.isTimeframeLocked(timeframe, isPro: true, isGatingEnabled: true) == false)
            #expect(ChartGatingPolicy.isTimeframeLocked(timeframe, isPro: false, isGatingEnabled: false) == false)
        }
    }

    @Test("The widest free window is the three-month one")
    func widestFreeWindowIsThreeMonths() {
        // Pins `ChartTimeframe.allCases` being ordered narrowest-first, which is
        // how `widestFreeTimeframe` reads "widest".
        #expect(ChartGatingPolicy.widestFreeTimeframe() == .threeMonths)
        #expect(ChartGatingPolicy.widestFreeTimeframe(freeTimeframes: [.week, .month]) == .month)
    }

    // MARK: - Harness

    private struct Harness {
        let viewModel: ExerciseProgressViewModel
        let entitlements: StubProEntitlements
        let paywalls: RecordingPaywallPresenter
        let provider: StubHistorySnapshotProvider
    }

    private func makeHarness(
        state: ProEntitlementState = .free,
        isGatingEnabled: Bool = true
    ) -> Harness {
        let entitlements = StubProEntitlements(state: state)
        let paywalls = RecordingPaywallPresenter()
        let provider = StubHistorySnapshotProvider()
        return Harness(
            viewModel: ExerciseProgressViewModel(
                exerciseName: "Bankdrücken",
                exerciseId: UUID(),
                provider: provider,
                proEntitlements: entitlements,
                paywalls: paywalls,
                isGatingEnabled: isGatingEnabled
            ),
            entitlements: entitlements,
            paywalls: paywalls,
            provider: provider
        )
    }
}

// MARK: - Doubles

/// Returns a fixed two-point series and records the cutoff every load asked for.
///
/// An `actor` because `HistorySnapshotProviding` is `Sendable` and the view model
/// awaits it off its own isolation; the recording is the point of the double, so
/// it has to be safe to read back from the test.
private actor StubHistorySnapshotProvider: HistorySnapshotProviding {

    struct Unused: Error {}

    private(set) var requestedStartDates: [Date] = []

    func fetchTrainingSnapshot(referenceDate: Date) async throws -> HistorySnapshot {
        // Unreachable from the exercise detail screen; a requirement of the
        // shared history boundary.
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
        requestedStartDates.append(startDate)
        let sessionId = UUID()
        let points = [
            ExerciseProgressDataPoint(
                date: Date().addingTimeInterval(-86_400 * 14),
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
                workoutSessionId: sessionId
            )
        ]
        return ExerciseProgressSnapshot(
            data: ExerciseProgressData(exerciseName: exerciseName, dataPoints: points),
            recentSessions: [
                ExerciseRecentSession(
                    id: sessionId,
                    date: Date(),
                    sets: [ExerciseRecentSession.SetEntry(id: UUID(), weight: 90, reps: 10)]
                )
            ]
        )
    }

    func fetchPreviousPerformances(
        _ lookup: PreviousPerformanceLookup
    ) async throws -> [UUID: PreviousExercisePerformance] { [:] }
}
