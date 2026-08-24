//
//  ExerciseProgressOpeningRangeTests.swift
//  GymStreakTests
//
//  Ticket 05b — the exercise detail screen opened on 1M unconditionally, so an
//  exercise last trained more than a month ago opened on an empty chart while its
//  own recent-sets list sat underneath listing eight entries (reported on device for
//  "Chest Press", last trained 27.06.). These pin the opening window: the narrowest
//  *unlocked* one that actually reaches the usage being charted, decided once, and
//  never over the user's own tap.
//

import Testing
import Foundation
@testable import GymStreak

@Suite
@MainActor
struct ExerciseProgressOpeningRangeTests {

    // MARK: - Narrowest that works

    @Test("An exercise trained twice this week opens on the tightest window that holds it")
    func opensOnTheNarrowestWindowWithData() async {
        let harness = makeHarness(lastPerformed: daysAgo(1), previousPerformed: daysAgo(3))

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.selectedTimeframe == .week)
        #expect(harness.viewModel.chartTimeframe == .week)
        // The point of the exercise: a *line* is actually drawn, not a lone dot.
        #expect(harness.viewModel.progressData?.hasEnoughDataForTrend == true)
    }

    @Test("Data only inside 3M opens on 3M")
    func opensOnThreeMonthsWhenThatIsTheNarrowestWithData() async {
        // The reported shape: last trained ~two months ago, invisible on 1W and 1M.
        let harness = makeHarness(lastPerformed: daysAgo(58), previousPerformed: daysAgo(59))

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.selectedTimeframe == .threeMonths)
        #expect(harness.viewModel.progressData?.hasEnoughDataForTrend == true)
        // Stat cards, chart and recent-sets list all come from that same load.
        #expect(harness.viewModel.personalRecordString != nil)
        #expect(harness.viewModel.sessionCountString != nil)
    }

    @Test("A single workout this week opens wide enough to draw a line")
    func oneWorkoutThisWeekWidensToWhereTheSeriesIs() async {
        // The device finding: Biceps Curls, trained once in the last week, opened on 1W
        // with one dot, no line and TREND "-" while 1M held the progression. The window
        // must reach the *second* workout, not just the last one.
        let harness = makeHarness(lastPerformed: daysAgo(2), previousPerformed: daysAgo(20))

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.selectedTimeframe == .month)
        // Two points, so there is a line and a real trend — the whole reason for the rule.
        #expect(harness.viewModel.progressData?.hasEnoughDataForTrend == true)
    }

    @Test("A usage trained only once ever still opens on the tightest window holding it")
    func singleWorkoutInAllOfHistoryKeepsTheTightestWindow() async {
        // Nothing to widen towards: one point is all there is, so 1W is right and the
        // two-point rule must fall back rather than jump to 1M.
        let harness = makeHarness(lastPerformed: daysAgo(2), previousPerformed: nil)

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.selectedTimeframe == .week)
        // One point is all history holds, so this is the honest outcome — not a lone dot
        // the rule could have avoided.
        #expect(harness.viewModel.progressData?.hasEnoughData == true)
        #expect(harness.viewModel.progressData?.hasEnoughDataForTrend == false)
    }

    @Test("A gated user whose previous workout is out of reach still gets the point they can see")
    func gatedUserFallsBackToTheWindowThatReachesTheLastWorkout() async {
        // The regression this rule nearly re-introduced: with gating on, the free windows end
        // at 3M. Last workout 80 days ago is inside 3M; the one before it, 100 days ago, is
        // not — so the preferred two-point window does not exist for this user. Requiring it
        // would leave them on an empty 1M chart with their sets listed underneath, which is
        // verbatim the reported bug. One real point beats none.
        let harness = makeHarness(
            lastPerformed: daysAgo(80),
            previousPerformed: daysAgo(100),
            state: .free,
            isGatingEnabled: true
        )

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.selectedTimeframe == .threeMonths)
        #expect(harness.viewModel.progressData?.hasEnoughData == true)
        // Honestly a single point — that is all this entitlement can reach.
        #expect(harness.viewModel.progressData?.hasEnoughDataForTrend == false)
    }

    @Test("A Pro user reaches the same pair the gated user cannot")
    func proUserReachesBothWorkouts() async {
        // Same history as above, entitled: 1J reaches both, so the curve is drawn.
        let harness = makeHarness(
            lastPerformed: daysAgo(80),
            previousPerformed: daysAgo(100),
            state: .subscription,
            isGatingEnabled: true
        )

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.selectedTimeframe == .year)
        #expect(harness.viewModel.progressData?.hasEnoughDataForTrend == true)
    }

    @Test("A window that already fits is kept, with no second fetch")
    func defaultThatAlreadyFitsCostsNothing() async {
        // 20 days back: 1W misses it, 1M reaches it — the default is already right.
        let harness = makeHarness(lastPerformed: daysAgo(20), previousPerformed: daysAgo(21))

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.selectedTimeframe == .month)
        #expect(harness.viewModel.progressData?.hasEnoughData == true)
        #expect(await harness.provider.fetchCount == 1)
    }

    @Test("Moving the window costs exactly one extra fetch")
    func movingTheWindowCostsOneExtraFetch() async throws {
        let harness = makeHarness(lastPerformed: daysAgo(58), previousPerformed: daysAgo(59))

        await loadUntilSettled(harness.viewModel)

        let requested = await harness.provider.requestedStartDates
        #expect(requested.count == 2)
        // The window the screen ends up rendering reaches the workout; the 1M window it
        // opened with does not.
        #expect(try #require(requested.first) > daysAgo(58))
        #expect(try #require(requested.last) <= daysAgo(58))
    }

    @Test("The abandoned window's snapshot is never published")
    func theSwapPublishesNothingInBetween() async {
        let harness = makeHarness(lastPerformed: daysAgo(58), previousPerformed: daysAgo(59))

        // The first load alone: it has moved the window and returned without publishing.
        await harness.viewModel.load()
        #expect(harness.viewModel.selectedTimeframe == .threeMonths)
        #expect(harness.viewModel.isLoading)
        // `isLoading` alone does not protect this: the stat triple reads these three
        // unconditionally, with no loading gate, so an assigned-then-abandoned snapshot
        // would render as "- / - / 0 Workouts" — this ticket's own screenshot.
        #expect(harness.viewModel.progressData == nil)
        #expect(harness.viewModel.sessionCountString == nil)
        #expect(harness.viewModel.personalRecordString == nil)

        await loadUntilSettled(harness.viewModel)
        #expect(harness.viewModel.isLoading == false)
        #expect(harness.viewModel.progressData?.hasEnoughData == true)
        #expect(harness.viewModel.sessionCountString != nil)
    }

    // MARK: - Nothing to find

    @Test("An exercise with no history anywhere still opens on 1M")
    func neverTrainedKeepsTheMonthDefault() async {
        let harness = makeHarness(lastPerformed: nil, previousPerformed: nil)

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.selectedTimeframe == .month)
        #expect(harness.viewModel.emptyChartReason == .neverTrained)
        #expect(await harness.provider.fetchCount == 1)
    }

    // MARK: - The Pro gate

    @Test("A locked window is never auto-selected")
    func gatedUserIsNeverOpenedOnAProWindow() async {
        // Older than the widest free window: the search finds nothing it may select.
        let harness = makeHarness(lastPerformed: daysAgo(200), previousPerformed: daysAgo(201), state: .free, isGatingEnabled: true)

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.isTimeframeLocked(.year))
        #expect(harness.viewModel.selectedTimeframe == .month)
        #expect(harness.viewModel.isTimeframeLocked(harness.viewModel.selectedTimeframe) == false)
        // 03d's dated copy remains the answer for data older than the free windows.
        #expect(harness.viewModel.emptyChartReason == .outsideSelectedWindow)
        #expect(harness.viewModel.datedWindowEmptyMessage != nil)
    }

    @Test("A Pro user opens on the wider window their entitlement unlocks")
    func proUserOpensOnAnUnlockedWideWindow() async {
        let harness = makeHarness(lastPerformed: daysAgo(200), previousPerformed: daysAgo(201), state: .subscription, isGatingEnabled: true)

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.selectedTimeframe == .year)
        #expect(harness.viewModel.progressData?.hasEnoughData == true)
    }

    @Test("The rule picks the window whose bound is the first to reach the date")
    func policyBoundariesArePinned() {
        // A fixed pair, so this asserts the boundary itself rather than "roughly a month".
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dayBefore = { (days: Int) in
            Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        }

        func picked(_ lastPerformed: Date) -> ChartTimeframe? {
            ChartGatingPolicy.narrowestUnlockedTimeframe(
                reaching: lastPerformed,
                isPro: false,
                isGatingEnabled: false,
                now: now
            )
        }

        #expect(picked(now) == .week)
        #expect(picked(ChartTimeframe.week.startDate(from: now)) == .week)
        // One second before 1W's bound falls out of it and into 1M.
        #expect(picked(ChartTimeframe.week.startDate(from: now).addingTimeInterval(-1)) == .month)
        #expect(picked(ChartTimeframe.month.startDate(from: now)) == .month)
        #expect(picked(ChartTimeframe.month.startDate(from: now).addingTimeInterval(-1)) == .threeMonths)
        #expect(picked(dayBefore(200)) == .year)
        #expect(picked(.distantPast) == .all)
    }

    @Test("The rule itself never returns a locked window, gating on or off")
    func policyNeverReturnsALockedWindow() {
        for isGatingEnabled in [true, false] {
            for isPro in [true, false] {
                for days in [1, 20, 58, 200, 900] {
                    let picked = ChartGatingPolicy.narrowestUnlockedTimeframe(
                        reaching: daysAgo(days),
                        isPro: isPro,
                        isGatingEnabled: isGatingEnabled
                    )
                    guard let picked else {
                        // Only a gated user can come up empty, and only past 3M.
                        #expect(isGatingEnabled && !isPro && days > 90)
                        continue
                    }
                    #expect(
                        ChartGatingPolicy.isTimeframeLocked(
                            picked,
                            isPro: isPro,
                            isGatingEnabled: isGatingEnabled
                        ) == false
                    )
                }
            }
        }
    }

    // MARK: - It is a default, not a lock

    @Test("A window the user picked before the load survives it")
    func userChoiceBeforeTheFirstLoadWins() async {
        let harness = makeHarness(lastPerformed: daysAgo(1), previousPerformed: daysAgo(3))

        harness.viewModel.updateTimeframe(.threeMonths)
        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.selectedTimeframe == .threeMonths)
        #expect(await harness.provider.fetchCount == 1)
    }

    @Test("The default never re-asserts itself after a reload, a metric change or a usage switch")
    func userChoiceSurvivesEverythingThatReloads() async {
        let harness = makeHarness(lastPerformed: daysAgo(58), previousPerformed: daysAgo(59))

        await loadUntilSettled(harness.viewModel)
        #expect(harness.viewModel.selectedTimeframe == .threeMonths)

        // The user narrows to a window that holds nothing for this usage — deliberately
        // the state the opening default exists to avoid, which makes it the sharp case.
        harness.viewModel.updateTimeframe(.week)
        await loadUntilSettled(harness.viewModel)
        #expect(harness.viewModel.selectedTimeframe == .week)

        harness.viewModel.updateMetric(.volume)
        harness.viewModel.updateUsage(.combined)
        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.selectedTimeframe == .week)
        #expect(harness.viewModel.progressData?.hasEnoughData == false)
    }

    @Test("Switching exercise inside the screen takes the switched-to exercise's window")
    func exerciseSwitchResolvesItsOwnWindow() async {
        let harness = makeHarness(lastPerformed: daysAgo(1), previousPerformed: daysAgo(3))

        await loadUntilSettled(harness.viewModel)
        #expect(harness.viewModel.selectedTimeframe == .week)

        await harness.provider.setLastPerformed(daysAgo(58), previousPerformed: daysAgo(59))
        harness.viewModel.updateExercise("Chest Press", exerciseId: UUID())
        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.selectedTimeframe == .threeMonths)
        #expect(harness.viewModel.progressData?.hasEnoughData == true)
    }

    @Test("Re-picking the exercise already on screen changes nothing")
    func reselectingTheCurrentExerciseIsANoOp() async {
        // The switcher menu lists the current exercise and fires `onSelect` unconditionally,
        // so this path is one tap away. Everything `updateExercise` does is destructive, and
        // retiring an in-flight load that `.task(id:)` will not restart — `loadKey` has not
        // moved — would hang the screen on its spinner.
        let harness = makeHarness(lastPerformed: daysAgo(58), previousPerformed: daysAgo(59))
        await loadUntilSettled(harness.viewModel)

        let key = harness.viewModel.loadKey
        let usage = harness.viewModel.selectedUsage
        harness.viewModel.updateExercise(
            "Bankdrücken",
            exerciseId: harness.viewModel.loadKey.exerciseId,
            initialUsage: harness.viewModel.requestedUsage.flatMap {
                if case .usage(let key) = $0 { return key } else { return nil }
            }
        )

        #expect(harness.viewModel.loadKey == key)
        #expect(harness.viewModel.isLoading == false)
        // Not cleared: the picker and the selection survive a tap that changed nothing.
        #expect(harness.viewModel.usageOptions.isEmpty == false)
        #expect(harness.viewModel.selectedUsage == usage)
        #expect(harness.viewModel.progressData?.hasEnoughDataForTrend == true)
    }

    // MARK: - Harness

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    private struct Harness {
        let viewModel: ExerciseProgressViewModel
        let provider: StubOpeningRangeProvider
    }

    /// - Parameter previousPerformed: the workout before `lastPerformed`, which is what the
    ///   opening window prefers to reach. Required, with no default: `nil` means "trained
    ///   exactly once, ever", and a default would let a case silently mean the opposite of
    ///   what it reads as.
    private func makeHarness(
        lastPerformed: Date?,
        previousPerformed: Date?,
        state: ProEntitlementState = .free,
        isGatingEnabled: Bool = false
    ) -> Harness {
        let provider = StubOpeningRangeProvider(
            lastPerformed: lastPerformed,
            previousPerformed: previousPerformed
        )
        return Harness(
            viewModel: ExerciseProgressViewModel(
                exerciseName: "Bankdrücken",
                exerciseId: UUID(),
                provider: provider,
                proEntitlements: StubProEntitlements(state: state),
                paywalls: RecordingPaywallPresenter(),
                isGatingEnabled: isGatingEnabled
            ),
            provider: provider
        )
    }

}

// MARK: - Double

/// Returns the aggregator's shape for a single-usage exercise: all-time usage options
/// regardless of the window, and a series that holds the usage's one workout only when
/// the requested window reaches back to it.
private actor StubOpeningRangeProvider: HistorySnapshotProviding {

    static let usageKey = ExerciseUsage.Key.routineSlot(UUID())

    private var lastPerformed: Date?
    /// The workout before `lastPerformed`, i.e. what decides the opening window. `nil` =
    /// the usage was trained exactly once in all of history.
    private var previousPerformed: Date?
    private(set) var requestedStartDates: [Date] = []

    var fetchCount: Int { requestedStartDates.count }

    init(lastPerformed: Date?, previousPerformed: Date?) {
        self.lastPerformed = lastPerformed
        self.previousPerformed = previousPerformed
    }

    /// Re-points the stub at another exercise's history, for the exercise-switch case.
    func setLastPerformed(_ date: Date?, previousPerformed: Date?) {
        lastPerformed = date
        self.previousPerformed = previousPerformed
    }

    struct Unused: Error {}

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
        requestedStartDates.append(startDate)

        guard let lastPerformed else {
            return ExerciseProgressSnapshot(
                data: ExerciseProgressData(exerciseName: exerciseName, dataPoints: []),
                recentUsages: []
            )
        }

        let option = ExerciseUsageOption(
            usage: ExerciseUsage(
                key: Self.usageKey,
                targetRepMin: 8,
                targetRepMax: 12,
                routineName: "Push A"
            ),
            lastPerformed: lastPerformed,
            lastPerformedOrder: 0
        )
        // One point per workout the window reaches, exactly like
        // `ExerciseProgressAggregator.windowedSessions` + `buildProgress`. Emitting a point
        // for *every* date rather than only the newest is what keeps this double honest:
        // the production rule reads `recentUsages` as a proxy for chart points, so a stub
        // that listed two workouts and charted one would satisfy `hasEnoughData` with the
        // lone-dot state this rule exists to eliminate.
        let workouts = [lastPerformed, previousPerformed].compactMap { $0 }
        let points = workouts
            .filter { $0 >= startDate }
            .sorted()
            .enumerated()
            .map { index, date in
                ExerciseProgressDataPoint(
                    date: date,
                    maxWeight: 60 + Double(index) * 5,
                    estimated1RM: 75 + Double(index) * 5,
                    totalVolume: 720,
                    totalSets: 3,
                    totalReps: 30,
                    workoutSessionId: UUID()
                )
            }

        // All-time and unwindowed, like the aggregator's: this is what the opening-window
        // rule reads to find the second-most-recent workout.
        let recentUsages = workouts
            .map { date in
                ExerciseRecentUsage(
                    id: UUID(),
                    workoutSessionId: UUID(),
                    date: date,
                    usage: option.usage,
                    sets: [ExerciseRecentUsage.SetEntry(id: UUID(), weight: 60, reps: 10)]
                )
            }

        return ExerciseProgressSnapshot(
            data: ExerciseProgressData(exerciseName: exerciseName, dataPoints: points),
            recentUsages: recentUsages,
            availableUsages: [option],
            selectedUsage: usageSelection ?? .usage(option.key)
        )
    }

    func fetchPreviousPerformances(
        _ lookup: PreviousPerformanceLookup
    ) async throws -> [UUID: PreviousExercisePerformance] { [:] }
}
