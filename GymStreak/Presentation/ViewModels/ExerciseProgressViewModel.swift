//
//  ExerciseProgressViewModel.swift
//  GymStreak
//

import Foundation
import SwiftUI

/// Owns the exercise detail screen's precomputed state.
///
/// Loading is `async` on purpose (audit P1.2). It used to be a synchronous
/// `fetchProgressData` call with no `await` anywhere in the chain, run from `init` and
/// again on every range-pill tap and exercise switch: an unbounded fetch plus a full
/// relationship traversal, on the main actor, for every user with a chart — the same
/// shape that measured ~600 ms in History. The work now happens inside
/// `SwiftDataHistorySnapshotStore`'s model actor and only immutable values come back.
/// `isLoading` is also observable for the first time; nothing used to yield, so the
/// spinner could never render.
@MainActor
class ExerciseProgressViewModel: ObservableObject {
    /// Identity of a load. `ExerciseProgressChartView` feeds this to `.task(id:)`, which
    /// cancels and restarts the load whenever the exercise, the timeframe or the selected
    /// usage changes.
    struct LoadKey: Equatable {
        let exerciseName: String
        let exerciseId: UUID?
        let timeframe: ChartTimeframe
        /// What the *user* asked for, not what was resolved — `nil` means "take the
        /// default", and resolving it here would make the key change on its own once the
        /// first load came back.
        let usageSelection: ExerciseUsageSelection?
    }

    /// `private(set)` so `updateTimeframe` stays the only writer — it is what records the
    /// user's choice, and a direct write from a view would bypass that and let the opening
    /// default overrule a tap.
    @Published private(set) var selectedTimeframe: ChartTimeframe = .month
    @Published var selectedMetric: ProgressMetric = .maxWeight
    @Published private(set) var progressData: ExerciseProgressData?
    /// One card per usage per session — a workout that trained the exercise twice
    /// contributes two entries. Capped by sessions, see `recentSessionLimit`.
    @Published private(set) var recentUsages: [ExerciseRecentUsage] = []
    @Published var selectedDataPoint: SelectedDataPoint?
    @Published private(set) var isLoading = true

    /// The usages the picker offers, labelled. Empty until the first load returns; a
    /// single entry means there is nothing to choose between and the picker stays hidden.
    @Published private(set) var usageOptions: [ExerciseUsagePickerItem] = []
    /// The usage the loaded data actually describes — resolved by the aggregator, which
    /// only fills in the default when nothing has been requested yet. A chosen usage is
    /// never swapped out: outside the window it draws the empty-chart state instead.
    @Published private(set) var selectedUsage: ExerciseUsageSelection = .combined
    /// What the user picked, or `nil` while they have not picked anything for this
    /// exercise — which is what lets the aggregator open the screen on the most recently
    /// trained usage instead of on the combined sawtooth.
    ///
    /// `@Published` because it is part of `loadKey`: the re-render it triggers is what
    /// restarts `.task(id:)` and actually performs the reload. Leaving it a plain `var`
    /// worked only because `updateUsage` also clears `selectedDataPoint`, which hung the
    /// entire picker on an unrelated line.
    @Published private(set) var requestedUsage: ExerciseUsageSelection?

    /// The empty chart's message for the windowed case, with the selected usage's
    /// last-trained date already named and formatted — "Zuletzt trainiert am 12.07.".
    ///
    /// That date is the fact that turns "no data in this range" into a single correct
    /// range tap: the reporter's usage was last trained on 12.07., which neither 1W nor
    /// 1M reaches, so copy without it leaves the user hopping pills. Built in `load()`
    /// and `nil` when no date can be resolved (nothing in history, or a failed load),
    /// which falls back to the undated copy.
    @Published private(set) var datedWindowEmptyMessage: String?

    /// The last window this user was actually allowed to read. It is what the
    /// chart keeps drawing while a Pro-only window is selected — see
    /// `chartTimeframe`.
    @Published private(set) var lastUnlockedTimeframe: ChartTimeframe = .month

    /// `true` once the user has tapped a range pill. Their choice then stands for the
    /// rest of the screen's life: the opening default is a default, not a lock, so it
    /// must not re-assert itself on a reload, a metric change, a usage switch or an
    /// exercise switch.
    private var hasUserChosenTimeframe = false

    /// `true` once the opening window has been decided for the exercise on screen.
    /// Reset by `updateExercise`, so switching exercise inside the screen lands on
    /// *that* exercise's narrowest window with data — the same thing tapping its
    /// Fortschritt row would have done.
    private var hasResolvedOpeningTimeframe = false

    /// Bounded so the recent-sets list stays a small, non-lazy stack. It caps
    /// **sessions**, not cards: a session that trained the exercise twice renders two
    /// cards, so the stack scales with the routine's shape rather than with history length.
    static let recentSessionLimit = 8

    private var exerciseName: String
    private var exerciseId: UUID?
    private let provider: HistorySnapshotProviding
    private let proEntitlements: any ProEntitlementProviding
    private let paywalls: any PaywallPresenting
    private let isGatingEnabled: Bool

    /// Separate from task cancellation on purpose, mirroring `HistoryViewModel`: the
    /// fetches inside the model actor are synchronous, so a superseded load can still
    /// run to completion and resume here after a newer one has already published. Only
    /// the newest generation is allowed to write.
    private var generation = 0

    /// Republishes when the entitlement changes (docs/pro-subscription.md §3c).
    /// It does more here than repaint: `chartTimeframe` is part of `loadKey`, so
    /// the re-render is what restarts `.task(id:)` and actually widens the
    /// window a purchase just unlocked.
    private var entitlementObserver: EntitlementChangeObserver?

    /// - Parameter isGatingEnabled: injected rather than read from `ProGating`
    ///   inside the gate, for the same reason `PaywallPresenter` and
    ///   `RoutinesViewModel` inject it — a test that baked in whatever the switch
    ///   currently ships as would prove the shipped configuration rather than the
    ///   rule. Gating has shipped **on** since 2026-08-17
    ///   (`ProGating.shippedValue`), so the view's own construction takes the
    ///   gated branch: for a free user the opening-window search stops at 3M.
    /// - Parameter initialUsage: the usage the Fortschritt row that pushed this screen
    ///   summarised, or `nil` to take the default. It becomes a *requested* selection so
    ///   the two surfaces cannot open on different usages; a key this exercise's history
    ///   does not hold falls back to the default in `ExerciseUsageResolver`.
    init(
        exerciseName: String,
        exerciseId: UUID? = nil,
        initialUsage: ExerciseUsage.Key? = nil,
        provider: HistorySnapshotProviding,
        proEntitlements: any ProEntitlementProviding,
        paywalls: any PaywallPresenting,
        isGatingEnabled: Bool = ProGating.isEnabled
    ) {
        self.exerciseName = exerciseName
        self.exerciseId = exerciseId
        self.requestedUsage = initialUsage.map(ExerciseUsageSelection.usage)
        self.provider = provider
        self.proEntitlements = proEntitlements
        self.paywalls = paywalls
        self.isGatingEnabled = isGatingEnabled
        entitlementObserver = EntitlementChangeObserver(
            entitlements: proEntitlements
        ) { [weak self] in
            self?.objectWillChange.send()
        }
    }

    /// Keyed on `chartTimeframe`, not on the selection: picking a Pro-only
    /// window must not widen the fetch just so the result can be blurred.
    var loadKey: LoadKey {
        LoadKey(
            exerciseName: exerciseName,
            exerciseId: exerciseId,
            timeframe: chartTimeframe,
            usageSelection: requestedUsage
        )
    }

    /// Mutates the load parameters only — `.task(id: viewModel.loadKey)` performs the reload.
    ///
    /// - Parameter initialUsage: the switched-to exercise's own Fortschritt headline
    ///   usage, so switching lands where tapping that exercise's row would have. `nil`
    ///   takes the default.
    func updateExercise(
        _ newExerciseName: String,
        exerciseId: UUID?,
        initialUsage: ExerciseUsage.Key? = nil
    ) {
        // Re-picking the exercise already on screen is a no-op, and must stay one. The
        // switcher menu lists the current exercise (checkmarked) and fires `onSelect`
        // unconditionally, so this method is reachable with nothing to change — and
        // everything below is destructive: it would clear the picker, reset the selection
        // to `.combined`, and retire an in-flight load that `.task(id:)` will not restart,
        // because `loadKey` did not move. That last one is a permanent spinner.
        guard newExerciseName != exerciseName
                || exerciseId != self.exerciseId
                || initialUsage.map(ExerciseUsageSelection.usage) != requestedUsage else {
            return
        }
        self.exerciseName = newExerciseName
        self.exerciseId = exerciseId
        // Retires any load still in flight for the *previous* exercise. Without it, one
        // that resumes between here and SwiftUI restarting `.task(id:)` still passes the
        // generation guard, and would spend the freshly reset one-shot flag below on the
        // old exercise's `lastPerformed` — leaving the switched-to exercise on whatever
        // window happened to be selected, i.e. the empty chart this ticket removes.
        // Only here: `updateTimeframe` and `updateUsage` keep no per-load flag, so a
        // superseded load there is simply overwritten by the newer one.
        generation += 1
        selectedDataPoint = nil
        // A different exercise has different usages: replace the choice with the
        // switched-to exercise's own headline usage (`nil` clears it and takes the
        // default) and drop the stale menu, so the picker never offers the previous
        // exercise's slots during the load.
        requestedUsage = initialUsage.map(ExerciseUsageSelection.usage)
        usageOptions = []
        selectedUsage = .combined
        datedWindowEmptyMessage = nil
        // A different exercise gets its own opening window — unless the user has
        // already picked one, in which case `hasUserChosenTimeframe` keeps it.
        hasResolvedOpeningTimeframe = false
    }

    /// Selects which usage the chart and the recent-sets list describe.
    ///
    /// Part of `loadKey`, so the reload runs through `.task(id:)` and the existing
    /// generation guard — rather than filtering the loaded arrays here. Filtering after
    /// the fact would silently shrink the recent-sets list, whose cap counts *sessions*:
    /// eight workouts of alternating usages would leave four cards for whichever one is
    /// selected. Reloading keeps "the last eight workouts of this usage".
    /// A tap always becomes the request, even when it names the usage already on screen —
    /// on first open `requestedUsage` is `nil` while `selectedUsage` already names the
    /// default, and tapping that default has to be recorded as a choice.
    func updateUsage(_ selection: ExerciseUsageSelection) {
        guard selection != requestedUsage else { return }
        requestedUsage = selection
        selectedDataPoint = nil
    }

    /// Whether there is anything to choose between. One usage and the picker is noise:
    /// its only entry would chart exactly what is already on screen.
    var showsUsagePicker: Bool { usageOptions.count > 1 }

    /// The picker's current label.
    var selectedUsageLabel: String {
        switch selectedUsage {
        case .combined:
            return "chart.usage.combined".localized
        case .usage(let key):
            return usageOptions.first { $0.key == key }?.label ?? "chart.usage.combined".localized
        }
    }

    /// Which of the two emptinesses the chart is currently showing. They need
    /// different copy because they have different remedies: one asks for a workout,
    /// the other for one tap on a wider range pill.
    ///
    /// `usageOptions` is built from **all** completed history
    /// (`ExerciseProgressSnapshot.availableUsages`), never from the charted window, so it
    /// is empty only when this exercise was never trained at all. A non-empty menu with
    /// an empty series therefore *is* the windowed case — the history exists, the selected
    /// window simply does not reach it. That is exactly the state ticket 03a made
    /// reachable by keeping a chosen usage instead of swapping it out.
    ///
    /// Derived from already-loaded state on purpose: no second fetch, and an `isEmpty`
    /// check rather than a collection walk, so `body` may read it (docs/history-performance.md).
    /// Meaningful only while the chart has no data to draw.
    var emptyChartReason: EmptyChartReason {
        usageOptions.isEmpty ? .neverTrained : .outsideSelectedWindow
    }

    /// The empty chart's two states, each owning its own copy.
    enum EmptyChartReason: Equatable {
        /// No completed set of this exercise anywhere in history.
        case neverTrained
        /// History exists for the selected usage, just not inside the selected window.
        case outsideSelectedWindow

        var titleKey: String {
            switch self {
            case .neverTrained: return "chart.empty.title"
            case .outsideSelectedWindow: return "chart.empty.window.title"
            }
        }

        var messageKey: String {
            switch self {
            case .neverTrained: return "chart.empty.message"
            case .outsideSelectedWindow: return "chart.empty.window.message"
            }
        }
    }

    /// The message line the empty chart renders.
    ///
    /// Purely descriptive in both states — it never instructs an action and never
    /// branches on the entitlement (2026-08-24). With gating on, the free windows end at
    /// 3M, so "pick a wider range" named an action a free user cannot always complete;
    /// naming the date is true for a free and a Pro user alike, and the lock badges on
    /// the 1Y and All pills already say which ranges are theirs.
    ///
    /// A string lookup and an optional read — the date was formatted during `load()`, so
    /// `body` may read this (docs/history-performance.md).
    var emptyChartMessage: String {
        switch emptyChartReason {
        case .neverTrained:
            return EmptyChartReason.neverTrained.messageKey.localized
        case .outsideSelectedWindow:
            return datedWindowEmptyMessage
                ?? EmptyChartReason.outsideSelectedWindow.messageKey.localized
        }
    }

    /// When the selected usage was last trained, or `nil` when the snapshot holds no
    /// usage to take a date from.
    ///
    /// One date answers both of this screen's "the window is wrong" problems: it is what
    /// the empty copy names, and what the opening window has to reach. `.combined` is
    /// described by the **newest** date across the usages: it charts all of them, so the
    /// nearest one is the window that would first show something. Walks the options once,
    /// in `load()`.
    private static func lastPerformed(
        for selection: ExerciseUsageSelection,
        in options: [ExerciseUsageOption]
    ) -> Date? {
        switch selection {
        case .combined:
            return options.map(\.lastPerformed).max()
        case .usage(let key):
            return options.first { $0.key == key }?.lastPerformed
        }
    }

    /// The **second**-most-recent workout of the selected usage — the date the opening
    /// window would ideally reach, so the window it lands on can draw a line and a trend
    /// rather than a lone dot. `nil` when the usage has been trained only once.
    ///
    /// One point is a chart only in the arithmetic sense — no line, no percentage, and an
    /// axis invented around a single value. Verified on device: Biceps Curls, trained once
    /// in the last week, opened on 1W showing exactly that while 1M held the progression.
    /// So "the narrowest window that works" prefers two points to one.
    ///
    /// It is a *preference*, never a requirement — see `applyOpeningTimeframe`. Making it a
    /// requirement re-broke the very bug this ticket exists to fix.
    ///
    /// `recentUsages` is all-time, already filtered to the selected usage and capped by
    /// **sessions**, so the second distinct session is the second chart point and costs no
    /// extra fetch. It is a sound proxy because both halves of the snapshot select sessions
    /// identically — `endTime != nil`, the same `ExerciseUsageResolver.keyedRows` predicate,
    /// the same selection filter, and at least one *completed* set — so a session here
    /// always has a point on the chart. Walks at most `recentSessionLimit` entries, in
    /// `load()`.
    private static func secondMostRecentWorkout(in recentUsages: [ExerciseRecentUsage]) -> Date? {
        // Keyed by session, which is what a chart point is: `.combined` lists one card per
        // usage, so a workout that trained the exercise twice appears twice while
        // `buildProgress` still folds it into a single point.
        var seen = Set<UUID>()
        let dates = recentUsages
            .filter { seen.insert($0.workoutSessionId).inserted }
            .map(\.date)
            .sorted(by: >)
        return dates.count >= 2 ? dates[1] : nil
    }

    /// The dated windowed-empty line for one last-trained date.
    private static func datedWindowEmptyMessage(lastPerformed: Date) -> String {
        "chart.empty.window.message.dated".localized(
            ExerciseUsageLabeling.lastTrainedDateText(lastPerformed)
        )
    }

    /// Selects a window. A Pro-only one is still *selected* — its pill highlights
    /// and the chart blurs behind the lock — but it raises `chartWindow` and
    /// leaves the loaded window alone.
    func updateTimeframe(_ timeframe: ChartTimeframe) {
        // From here on the window is the user's, including a locked one they tapped
        // to see the paywall: the opening default never overrides it again.
        hasUserChosenTimeframe = true
        selectedTimeframe = timeframe
        selectedDataPoint = nil
        if isTimeframeLocked(timeframe) {
            paywalls.present(.chartWindow)
        } else {
            lastUnlockedTimeframe = timeframe
        }
    }

    /// Moves the screen onto the narrowest unlocked window that actually holds a readable
    /// series for the usage being charted — once per exercise, and never once the user has
    /// picked a window themselves.
    ///
    /// The screen used to open on 1M unconditionally, so any exercise last trained more
    /// than a month ago opened on an empty chart while its own recent-sets list sat
    /// underneath listing eight entries. The data was never the problem, the default was.
    ///
    /// Two dates, in order of preference — the second reached is the floor, not a
    /// consolation prize.
    ///
    /// - Parameter preferred: the second-most-recent workout, so the window can draw a
    ///   line. `nil` when the usage has only ever been trained once.
    /// - Parameter orAtLeast: the most recent workout. Reached whenever `preferred` cannot
    ///   be: a **gated** user's windows end at 3M, so a usage last trained 80 days ago
    ///   whose previous workout was 100 days ago has no unlocked window reaching the
    ///   preferred date — and requiring it would leave that user on an empty 1M chart with
    ///   their sets listed underneath, which is verbatim the bug 05b exists to remove. One
    ///   real point beats none.
    /// - Returns: `true` when the window changed, i.e. when a second load is about to run.
    private func applyOpeningTimeframe(preferring preferred: Date?, orAtLeast lastPerformed: Date?) -> Bool {
        guard !hasUserChosenTimeframe, !hasResolvedOpeningTimeframe else { return false }
        // One shot per exercise either way: a usage switch or a plain reload must not
        // move a window again once this screen has opened.
        hasResolvedOpeningTimeframe = true
        guard let opening = openingTimeframe(reaching: preferred)
                ?? openingTimeframe(reaching: lastPerformed) else {
            // Nothing found (never trained, or *every* workout older than the widest
            // unlocked window) keeps the existing default, so the never-trained empty state
            // is unchanged and 03d's dated copy explains the windowed one.
            return false
        }
        // Compared on `chartTimeframe`, never on `selectedTimeframe`: the second load is
        // driven by `loadKey`, which carries `chartTimeframe`. The two coincide only while
        // the selection is unlocked — true today because 1M is free, but
        // `ProFeatureCaps.freeChartTimeframes` is an explicit tuning knob. Keying the
        // handshake on the other one would, the first time that knob is narrowed, suppress
        // `isLoading = false` for a reload that `loadKey` never asks for: a permanent
        // spinner, with a green build.
        let previousWindow = chartTimeframe
        selectedTimeframe = opening
        // Always an unlocked window, so it is also the last one this user could read.
        lastUnlockedTimeframe = opening
        return chartTimeframe != previousWindow
    }

    /// The narrowest window this user may read that reaches `date`, or `nil` — for no date,
    /// or for a date older than every window they are entitled to.
    private func openingTimeframe(reaching date: Date?) -> ChartTimeframe? {
        guard let date else { return nil }
        return ChartGatingPolicy.narrowestUnlockedTimeframe(
            reaching: date,
            isPro: proEntitlements.isPro,
            isGatingEnabled: isGatingEnabled
        )
    }

    func load() async {
        generation += 1
        let generation = self.generation
        isLoading = true

        // Resolved here, not inside the actor: `ChartTimeframe.startDate` reads
        // `Calendar.current` and `Date()`, so only the resulting cutoff crosses the hop.
        // `chartTimeframe`, not the selection: a Pro-only window never widens the fetch.
        let startDate = chartTimeframe.startDate

        do {
            let snapshot = try await provider.fetchExerciseProgress(
                exerciseName: exerciseName,
                exerciseId: exerciseId,
                startDate: startDate,
                recentSessionLimit: Self.recentSessionLimit,
                usageSelection: requestedUsage
            )
            guard !Task.isCancelled, generation == self.generation else { return }
            let lastPerformed = Self.lastPerformed(
                for: snapshot.selectedUsage,
                in: snapshot.availableUsages
            )
            // Resolved **before** anything is published. Deciding the opening window needs
            // a load first — the narrowest window with data cannot be known before the
            // charted usage is — so when it moves, this snapshot describes a window the
            // screen is about to abandon. Publishing it would render one frame of it:
            // `chartContent` is gated on `isLoading`, but the stat triple is not, so the
            // stats would flash "- / - / 0 Workouts", which is the exact symptom this rule
            // exists to remove. `loadKey` moves with the window, `.task(id:)` runs the
            // second load, and `isLoading` stays up until that one lands.
            if applyOpeningTimeframe(
                preferring: Self.secondMostRecentWorkout(in: snapshot.recentUsages),
                orAtLeast: lastPerformed
            ) { return }
            progressData = snapshot.data
            recentUsages = snapshot.recentUsages
            // Labelled once, here — the picker must not build localized strings or scan
            // for duplicate labels while a view body is being evaluated.
            usageOptions = ExerciseUsageLabeling.pickerItems(for: snapshot.availableUsages)
            selectedUsage = snapshot.selectedUsage
            // Formatted here for the same reason the labels are: the empty chart's copy
            // must not build a date string while `body` is being evaluated.
            datedWindowEmptyMessage = lastPerformed.map(Self.datedWindowEmptyMessage(lastPerformed:))
            if !availableMetrics.contains(selectedMetric) {
                selectedMetric = .maxWeight
            }
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            guard generation == self.generation else { return }
            progressData = nil
            recentUsages = []
            usageOptions = []
            selectedUsage = .combined
            datedWindowEmptyMessage = nil
            isLoading = false
        }
    }

    /// Selects a metric. A Pro-only one is still *selected* — the tab highlights
    /// and its real series renders blurred behind the lock — but it raises
    /// `chartMetric`. Nothing extra is computed for it: every data point already
    /// carries all three values from the one fetch.
    func updateMetric(_ metric: ProgressMetric) {
        guard availableMetrics.contains(metric) else { return }
        selectedMetric = metric
        selectedDataPoint = nil
        if isMetricLocked(metric) {
            paywalls.present(.chartMetric)
        }
    }

    // MARK: - Progress analytics gate (P2)
    //
    // The rules live in `ChartGatingPolicy`; this end owns only the inputs (the
    // live entitlement) and what a locked selection does to the screen. The gate
    // narrows the *analytics view* and nothing else — no session, set or workout
    // is hidden in any entitlement state, and a resubscribe restores the full
    // window on the spot because nothing was ever migrated away.

    /// `true` when this metric is Pro-only for the current user.
    ///
    /// Computed rather than stored so it tracks the entitlement live:
    /// `proEntitlements` is `@Observable`, and reading it during the chart's
    /// `body` evaluation is what unblurs the screen the moment a purchase lands.
    /// It is a comparison against one constant — no collection walk, no
    /// formatter, no SwiftData read.
    func isMetricLocked(_ metric: ProgressMetric) -> Bool {
        ChartGatingPolicy.isMetricLocked(
            metric,
            isPro: proEntitlements.isPro,
            isGatingEnabled: isGatingEnabled
        )
    }

    /// `true` when this window is Pro-only for the current user.
    func isTimeframeLocked(_ timeframe: ChartTimeframe) -> Bool {
        ChartGatingPolicy.isTimeframeLocked(
            timeframe,
            isPro: proEntitlements.isPro,
            isGatingEnabled: isGatingEnabled
        )
    }

    /// The window the chart actually renders: the selection, or the last
    /// unlocked one while a Pro-only window is selected.
    ///
    /// This is the whole reason a locked window costs nothing — the blurred
    /// preview is the user's own real data over the window they are entitled to,
    /// never a year-long series fetched purely to be made unreadable. It falls
    /// back to the selection once the gate lifts, which is what reloads the full
    /// window on a purchase without any refresh gesture.
    ///
    /// After a lapse the last unlocked window can itself be Pro-only (it was
    /// picked while entitled), so it is clamped to the widest free one rather
    /// than left fetching a year of history for a blur.
    var chartTimeframe: ChartTimeframe {
        guard isTimeframeLocked(selectedTimeframe) else { return selectedTimeframe }
        return isTimeframeLocked(lastUnlockedTimeframe)
            ? ChartGatingPolicy.widestFreeTimeframe()
            : lastUnlockedTimeframe
    }

    /// `true` when the current selection puts the chart behind the Pro lock.
    var isChartLocked: Bool {
        isMetricLocked(selectedMetric) || isTimeframeLocked(selectedTimeframe)
    }

    /// Which capability the lock card names. The metric wins when both are
    /// locked: it is the axis the user just switched, and §8 C only requires the
    /// paywall to name *a* specific capability, not to enumerate them.
    /// Meaningful only while `isChartLocked`.
    var chartLockPlacement: PaywallPlacement {
        isMetricLocked(selectedMetric) ? .chartMetric : .chartWindow
    }

    /// The lock card's CTA.
    func requestChartUnlock() {
        paywalls.present(chartLockPlacement)
    }

    /// The metric the (unblurred) stat triple reports on.
    ///
    /// A locked selection falls back to the free metric so the PR and trend
    /// cards never print a Pro number in plain text beside the blurred chart.
    /// For a free user on a free selection this is simply the selection, i.e.
    /// unchanged from before the gate existed.
    private var statMetric: ProgressMetric {
        isMetricLocked(selectedMetric) ? ProFeatureCaps.freeChartMetric : selectedMetric
    }

    // MARK: - Data Point Selection

    func selectDataPoint(_ dataPoint: ExerciseProgressDataPoint, for metric: ProgressMetric) {
        let value = dataPoint.value(for: metric)
        let displayValue = formatCompactValue(value, unit: metric.unit)
        let displayDate = dataPoint.date.formatted(date: .abbreviated, time: .omitted)
        selectedDataPoint = SelectedDataPoint(
            dataPoint: dataPoint,
            displayValue: displayValue,
            displayDate: displayDate
        )
    }

    func clearSelection() {
        selectedDataPoint = nil
    }

    // MARK: - Computed Properties for Display

    var availableMetrics: [ProgressMetric] {
        guard let data = progressData,
              data.loadBehavior.isCounterweightAssistance,
              !data.usesEffectiveLoad else {
            return ProgressMetric.allCases
        }
        return [.maxWeight]
    }

    var selectedMetricTitle: String {
        guard selectedMetric == .maxWeight,
              progressData?.loadBehavior.isCounterweightAssistance == true,
              progressData?.usesEffectiveLoad == false else {
            return selectedMetric.localizedTitle
        }
        return "exercise.assistance".localized
    }

    var personalRecordString: String? {
        guard let data = progressData else { return nil }

        switch statMetric {
        case .maxWeight:
            if let pr = data.personalRecord {
                return String(format: "%.1f kg", pr)
            }
        case .estimated1RM:
            if let pr = data.personalRecord1RM {
                return String(format: "%.1f kg", pr)
            }
        case .volume:
            if let maxVolume = data.dataPoints.map(\.totalVolume).max() {
                return String(format: "%.0f kg", maxVolume)
            }
        }
        return nil
    }

    /// Whether the loaded series folds several usages into one line — `.combined` on an
    /// exercise that has more than one usage.
    ///
    /// Two comparisons on already-loaded state, so `body` may read it
    /// (docs/history-performance.md). It is `false` for an exercise with a single usage,
    /// where `.combined` *is* that usage and every card means exactly what it says.
    var chartsSeveralUsagesTogether: Bool {
        selectedUsage == .combined && usageOptions.count > 1
    }

    /// First-to-last change of the plotted series, or `nil` when there is no such number
    /// to state.
    ///
    /// `nil` while several usages are charted together: the combined series alternates
    /// between two loads, so its first-vs-last delta is an artefact of which usage
    /// happens to sit at each end — the reporter's screen read **+42.9%** off a series
    /// that never progressed. Arithmetically correct, and a claim about progression that
    /// the data does not support, so it is withheld rather than dressed up.
    private var trendPercentage: Double? {
        guard !chartsSeveralUsagesTogether else { return nil }
        return progressData?.progressPercentage(for: statMetric)
    }

    var trendPercentageString: String? {
        guard let percentage = trendPercentage else { return nil }

        let sign = percentage >= 0 ? "+" : ""
        return String(format: "%@%.1f%%", sign, percentage)
    }

    /// What the trend card prints. A percentage when there is one; "Gemischt" / "Mixed"
    /// when the series mixes usages, which says *why* no number is shown and points at
    /// the picker; the plain placeholder when a single usage simply has too few points.
    var trendValueString: String {
        if let trendPercentageString { return trendPercentageString }
        return chartsSeveralUsagesTogether ? "chart.trend.mixed".localized : "-"
    }

    /// `false` when the trend card is printing something other than a percentage — the
    /// card then renders in a neutral tone, because red for "no number" reads as a loss.
    var hasTrendValue: Bool { trendPercentage != nil }

    var trendIsPositive: Bool {
        guard let percentage = trendPercentage else { return false }
        return percentage >= 0
    }

    var sessionCountString: String? {
        guard let count = progressData?.sessionCount else { return nil }
        return "\(count)"
    }
}
