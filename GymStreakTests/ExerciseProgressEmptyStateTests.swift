//
//  ExerciseProgressEmptyStateTests.swift
//  GymStreakTests
//
//  Ticket 03c — the exercise detail chart's empty state has two meanings and one
//  of them only became reachable once the usage picker stopped swapping the
//  user's selection (03a): a usage last trained in July, charted over 1M, draws
//  nothing while nine real workouts of it sit in history. These pin which copy
//  each emptiness gets, and that the distinction is derived from state the load
//  already returned rather than from a second fetch.
//
//  They drive `loadUntilSettled` rather than a bare `load()`: since ticket 05b the screen
//  may spend one extra load moving onto the window its data is actually in, and these
//  stubs date their usages far in the past, so a single `load()` would leave the view
//  model unpublished.
//
//  Ticket 03d added the second half: the windowed copy names the date that usage was
//  last trained and stops instructing a range change — an instruction a free user
//  cannot always follow, since the free windows end at 3M.
//

import Testing
import Foundation
@testable import GymStreak

@Suite
@MainActor
struct ExerciseProgressEmptyStateTests {

    // MARK: - Which emptiness

    @Test("History outside the window names the window, not a missing workout")
    func windowedEmptinessNamesTheWindow() async {
        let harness = makeHarness(mode: .historyButNoneInWindow)

        await loadUntilSettled(harness.viewModel)

        // The state the user actually reported: an empty series with a populated menu.
        #expect(harness.viewModel.progressData?.dataPoints.isEmpty == true)
        #expect(harness.viewModel.progressData?.hasEnoughData == false)
        #expect(harness.viewModel.usageOptions.isEmpty == false)

        #expect(harness.viewModel.emptyChartReason == .outsideSelectedWindow)
        #expect(harness.viewModel.emptyChartReason.titleKey == "chart.empty.window.title")
        #expect(harness.viewModel.emptyChartReason.messageKey == "chart.empty.window.message")
    }

    @Test("An exercise trained only once, outside the window, is still the window case")
    func singleUsageOutsideTheWindowIsTheWindowCase() async {
        // The picker is hidden below two usages, but the remedy is the same one tap
        // on a wider range — so the flag must not be keyed on `showsUsagePicker`.
        let harness = makeHarness(mode: .oneUsageNoneInWindow)

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.showsUsagePicker == false)
        #expect(harness.viewModel.emptyChartReason == .outsideSelectedWindow)
    }

    @Test("Nothing anywhere in history keeps the never-trained copy")
    func noHistoryAnywhereKeepsTheOriginalCopy() async {
        let harness = makeHarness(mode: .neverTrained)

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.usageOptions.isEmpty)
        #expect(harness.viewModel.emptyChartReason == .neverTrained)
        // The shared keys `EmptyChartView` and the recent-sets empty line also read.
        #expect(harness.viewModel.emptyChartReason.titleKey == "chart.empty.title")
        #expect(harness.viewModel.emptyChartReason.messageKey == "chart.empty.message")
    }

    @Test("A failed load falls back to the never-trained copy")
    func failedLoadDoesNotClaimTheWindowIsTooNarrow() async {
        // Nothing is known about history, so promising older workouts behind a
        // wider range would be a guess.
        let harness = makeHarness(mode: .failing)

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.progressData == nil)
        #expect(harness.viewModel.emptyChartReason == .neverTrained)
    }

    // MARK: - Cost

    @Test("The distinction costs no second fetch")
    func distinctionIsDerivedFromTheOneLoad() async {
        let harness = makeHarness(mode: .historyButNoneInWindow)

        await loadUntilSettled(harness.viewModel)
        // Counted after the screen has settled: the opening-window rule (05b) may spend
        // one extra load deciding which window to open on, and this test is about the
        // *reads*, not about that.
        let afterLoading = await harness.provider.fetchCount
        // Reading the flag repeatedly — as `body` does, twice per render — must not
        // reach the provider again.
        for _ in 0..<5 {
            #expect(harness.viewModel.emptyChartReason == .outsideSelectedWindow)
        }

        #expect(await harness.provider.fetchCount == afterLoading)
    }

    // MARK: - Copy

    @Test("Both empty states resolve to distinct, localized copy")
    func bothStatesHaveTheirOwnStrings() {
        let cases: [ExerciseProgressViewModel.EmptyChartReason] = [.neverTrained, .outsideSelectedWindow]

        for reason in cases {
            // A missing entry in Localizable.strings resolves to the key itself.
            #expect(reason.titleKey.localized != reason.titleKey)
            #expect(reason.messageKey.localized != reason.messageKey)
        }

        #expect(
            ExerciseProgressViewModel.EmptyChartReason.neverTrained.titleKey
                != ExerciseProgressViewModel.EmptyChartReason.outsideSelectedWindow.titleKey
        )
        #expect(
            ExerciseProgressViewModel.EmptyChartReason.neverTrained.messageKey
                != ExerciseProgressViewModel.EmptyChartReason.outsideSelectedWindow.messageKey
        )
    }

    // MARK: - The date

    @Test("The windowed empty chart names the date the selected usage was last trained")
    func windowedEmptinessNamesTheLastTrainedDate() async {
        let harness = makeHarness(mode: .historyButNoneInWindow)

        await loadUntilSettled(harness.viewModel)

        let expectedDate = ExerciseUsageLabeling.lastTrainedDateText(
            StubEmptyStateProvider.lastPerformed(forOptionAt: 0)
        )
        #expect(harness.viewModel.emptyChartMessage.contains(expectedDate))
        #expect(
            harness.viewModel.emptyChartMessage
                == "chart.empty.window.message.dated".localized(expectedDate)
        )
    }

    @Test("All usages names the newest last-trained date across them")
    func combinedNamesTheNewestDate() async {
        let harness = makeHarness(mode: .combinedNoneInWindow)

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.selectedUsage == .combined)
        // The third option is the most recently trained one; the first is the oldest.
        let newest = ExerciseUsageLabeling.lastTrainedDateText(
            StubEmptyStateProvider.lastPerformed(forOptionAt: 2)
        )
        let oldest = ExerciseUsageLabeling.lastTrainedDateText(
            StubEmptyStateProvider.lastPerformed(forOptionAt: 0)
        )
        #expect(harness.viewModel.emptyChartMessage.contains(newest))
        #expect(harness.viewModel.emptyChartMessage.contains(oldest) == false)
    }

    @Test("No resolvable date falls back to the undated copy")
    func unresolvableDateKeepsTheUndatedCopy() async {
        let harness = makeHarness(mode: .selectionMissingFromOptions)

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.datedWindowEmptyMessage == nil)
        #expect(harness.viewModel.emptyChartReason == .outsideSelectedWindow)
        #expect(harness.viewModel.emptyChartMessage == "chart.empty.window.message".localized)
    }

    @Test("The never-trained state keeps its own undated copy")
    func neverTrainedKeepsItsOwnMessage() async {
        let harness = makeHarness(mode: .neverTrained)

        await loadUntilSettled(harness.viewModel)

        #expect(harness.viewModel.emptyChartMessage == "chart.empty.message".localized)
    }

    @Test("The dated copy is localized and names no action")
    func datedCopyIsLocalizedAndDescriptive() {
        let dated = "chart.empty.window.message.dated".localized("12.07.")

        // A missing entry in Localizable.strings resolves to the key itself.
        #expect(dated != "chart.empty.window.message.dated")
        #expect(dated.contains("12.07."))
    }

    @Test("The date is formatted once, during load")
    func dateIsFormattedDuringLoad() async {
        let harness = makeHarness(mode: .historyButNoneInWindow)

        await loadUntilSettled(harness.viewModel)

        // Stored, not derived on read: `body` reads `emptyChartMessage` twice per
        // render and must not format a date or walk the options (docs/history-performance.md).
        let stored = harness.viewModel.datedWindowEmptyMessage
        let afterLoading = await harness.provider.fetchCount
        #expect(stored != nil)
        for _ in 0..<5 {
            #expect(harness.viewModel.emptyChartMessage == stored)
        }
        #expect(await harness.provider.fetchCount == afterLoading)
    }

    // MARK: - Harness

    private struct Harness {
        let viewModel: ExerciseProgressViewModel
        let provider: StubEmptyStateProvider
    }

    private func makeHarness(mode: StubEmptyStateProvider.Mode) -> Harness {
        let provider = StubEmptyStateProvider(mode: mode)
        return Harness(
            viewModel: ExerciseProgressViewModel(
                exerciseName: "Bankdrücken",
                exerciseId: UUID(),
                provider: provider,
                proEntitlements: StubProEntitlements(),
                paywalls: RecordingPaywallPresenter(),
                isGatingEnabled: false
            ),
            provider: provider
        )
    }
}

// MARK: - Double

/// Returns the exact snapshot shapes the aggregator produces for the two
/// emptinesses: all-time usage options are independent of the charted window, so
/// "history exists but not in this window" is an empty series beside a populated
/// `availableUsages`.
private actor StubEmptyStateProvider: HistorySnapshotProviding {

    enum Mode {
        /// Several usages in all-time history, none of them inside the window.
        case historyButNoneInWindow
        /// One usage in all-time history, not inside the window — the picker is hidden.
        case oneUsageNoneInWindow
        /// Several usages, none in the window, charted as `.combined`.
        case combinedNoneInWindow
        /// A selection naming a usage the snapshot does not carry — no date to name.
        case selectionMissingFromOptions
        /// The exercise was never trained.
        case neverTrained
        /// The fetch threw.
        case failing
    }

    /// Fixed so the expected date string can be built the same way the screen does.
    ///
    /// Far enough back that the opening-window rule (05b) moves the screen onto its widest
    /// unlocked window — with this harness ungated, that is `.all`. The series stays empty
    /// regardless because this stub ignores `startDate` and always returns no data points:
    /// these cases pin which *copy* an empty window gets, not which window is empty.
    static let oldestLastPerformed = Date(timeIntervalSince1970: 1_700_000_000)
    /// Each further usage was trained 30 days later than the one before, so the
    /// *newest* date is never the first option's — which is what `.combined` must pick.
    static func lastPerformed(forOptionAt index: Int) -> Date {
        oldestLastPerformed.addingTimeInterval(86_400 * 30 * Double(index))
    }

    struct Unused: Error {}
    struct Failed: Error {}

    private let mode: Mode
    private(set) var fetchCount = 0

    init(mode: Mode) {
        self.mode = mode
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
        fetchCount += 1
        if case .failing = mode { throw Failed() }

        let usageCount: Int
        switch mode {
        case .historyButNoneInWindow: usageCount = 3
        case .combinedNoneInWindow: usageCount = 3
        case .selectionMissingFromOptions: usageCount = 3
        case .oneUsageNoneInWindow: usageCount = 1
        case .neverTrained: usageCount = 0
        case .failing: usageCount = 0
        }

        let options = (0..<usageCount).map { index in
            ExerciseUsageOption(
                usage: ExerciseUsage(
                    key: .routineSlot(UUID()),
                    targetRepMin: 4 + index,
                    targetRepMax: 6 + index,
                    routineName: "Push A"
                ),
                lastPerformed: StubEmptyStateProvider.lastPerformed(forOptionAt: index),
                lastPerformedOrder: index
            )
        }

        let selectedUsage: ExerciseUsageSelection
        switch mode {
        case .combinedNoneInWindow:
            selectedUsage = .combined
        case .selectionMissingFromOptions:
            selectedUsage = .usage(.routineSlot(UUID()))
        default:
            // The first option, i.e. the *oldest* one — so a test expecting the newest
            // date cannot pass by accident.
            selectedUsage = options.first.map { .usage($0.usage.key) } ?? .combined
        }

        return ExerciseProgressSnapshot(
            // Empty: the window holds nothing, whatever all-time history says.
            data: ExerciseProgressData(exerciseName: exerciseName, dataPoints: []),
            // All-time, so it stays populated beside the empty series.
            recentUsages: [],
            availableUsages: options,
            selectedUsage: selectedUsage
        )
    }

    func fetchPreviousPerformances(
        _ lookup: PreviousPerformanceLookup
    ) async throws -> [UUID: PreviousExercisePerformance] { [:] }
}
