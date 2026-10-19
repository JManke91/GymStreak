//
//  ActivityKitRoundTimerPresenter.swift
//  GymStreak
//
//  The round timer's Live Activity (docs/fight-conditioning.md, "Round timer"
//  → Live Activity). The second app-target type importing ActivityKit, built
//  one-for-one on `ActivityKitRestTimerPresenter`: the same injectable store
//  seam (ActivityKit needs an app bundle with `NSSupportsLiveActivities` and the
//  system daemon, so the policy is only testable behind a protocol), the same
//  identity keying, the same `@preconcurrency import` for the non-`Sendable`
//  `Activity` crossing at `await` (see that file's header and
//  docs/swift6-concurrency.md §8 — nothing here changes the analysis).
//
//  What differs from the rest timer: the activity is *updated* at every phase
//  boundary, pause and resume, each update carrying the phase's end as its
//  `staleDate` — so a phone the app could not update falls back to the
//  whole-run level on its own instead of showing a wrong phase. And no run
//  survives a process death, so every listed activity at launch is a leftover.
//

import Foundation
@preconcurrency import ActivityKit

// MARK: - Injectable ActivityKit seam

/// One presented round-timer activity. Fire-and-forget: updating and ending
/// are asynchronous inside ActivityKit, but nothing in the app waits on them.
@MainActor
protocol RoundTimerLiveActivityHandle: AnyObject {
    func update(content: RoundTimerLiveActivityContent, staleDate: Date?)

    /// Ends the activity. A `completionMessage` shows a final state until
    /// `dismissAfter`; passing `nil` for both dismisses immediately.
    func end(completionMessage: String?, dismissAfter: Date?)
}

/// The ActivityKit entry points the presenter uses.
@MainActor
protocol RoundTimerLiveActivityStore {
    /// Whether the user has Live Activities turned on for GymStreak.
    var areActivitiesEnabled: Bool { get }

    /// Every round-timer activity the system currently knows about, including
    /// ones started by an earlier launch of the app.
    func currentActivities() -> [any RoundTimerLiveActivityHandle]

    func requestActivity(
        content: RoundTimerLiveActivityContent,
        staleDate: Date?
    ) throws -> any RoundTimerLiveActivityHandle
}

// MARK: - ActivityKit conformance

@MainActor
final class ActivityKitRoundTimerStore: RoundTimerLiveActivityStore {
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func currentActivities() -> [any RoundTimerLiveActivityHandle] {
        Activity<RoundTimerAttributes>.activities.map(ActivityKitHandle.init)
    }

    func requestActivity(
        content: RoundTimerLiveActivityContent,
        staleDate: Date?
    ) throws -> any RoundTimerLiveActivityHandle {
        ActivityKitHandle(
            try Activity.request(
                attributes: RoundTimerAttributes(content.run),
                content: ActivityContent(state: .init(content), staleDate: staleDate),
                pushType: nil
            )
        )
    }
}

@MainActor
private final class ActivityKitHandle: RoundTimerLiveActivityHandle {
    private let activity: Activity<RoundTimerAttributes>

    init(_ activity: Activity<RoundTimerAttributes>) {
        self.activity = activity
    }

    func update(content: RoundTimerLiveActivityContent, staleDate: Date?) {
        let next = ActivityContent(state: RoundTimerAttributes.ContentState(content), staleDate: staleDate)
        // `Task` inherits this main actor; the non-`Sendable` `activity` only
        // crosses at the `await`, which is what `@preconcurrency` covers.
        Task {
            await activity.update(next)
        }
    }

    func end(completionMessage: String?, dismissAfter: Date?) {
        let content: ActivityContent<RoundTimerAttributes.ContentState>? = completionMessage.map { message in
            let stamp = Date.now
            return ActivityContent(
                state: RoundTimerAttributes.ContentState(
                    runRange: stamp...stamp,
                    pauseDate: nil,
                    phaseLabel: nil,
                    phaseIsRound: false,
                    phasePosition: nil,
                    phaseRange: nil,
                    completionMessage: message
                ),
                staleDate: nil
            )
        }
        let policy: ActivityUIDismissalPolicy = dismissAfter.map { .after($0) } ?? .immediate
        Task {
            await activity.end(content, dismissalPolicy: policy)
        }
    }
}

// MARK: - Domain content → wire format

private extension RoundTimerAttributes {
    init(_ run: RoundTimerLiveActivityContent.Run) {
        self.init(
            title: run.title,
            subtitle: run.subtitle,
            isOpenEnded: run.isOpenEnded,
            timeLabel: run.timeLabel,
            pausedLabel: run.pausedLabel,
            staleNote: run.staleNote
        )
    }
}

private extension RoundTimerAttributes.ContentState {
    init(_ content: RoundTimerLiveActivityContent) {
        self.init(
            runRange: content.runRange,
            pauseDate: content.pauseDate,
            phaseLabel: content.phase?.label,
            phaseIsRound: content.phase?.isRound ?? false,
            phasePosition: content.phase?.position,
            phaseRange: content.phase?.range,
            completionMessage: nil
        )
    }
}

// MARK: - Presenter

@MainActor
final class ActivityKitRoundTimerPresenter: RoundTimerLiveActivityPresenting {
    /// How long "Rounds complete · …" stays on screen after the run ends.
    static let completionDisplayDuration: TimeInterval = 4

    private let store: any RoundTimerLiveActivityStore
    private let now: () -> Date

    /// Non-nil exactly when `presentedActivity` is — the run this presenter put
    /// on screen. A failed request leaves both nil, so the next transition
    /// retries instead of assuming the activity is up.
    private var presentedRunID: UUID?
    private var presentedActivity: (any RoundTimerLiveActivityHandle)?
    /// Whether this process has ever put an activity on screen. Gates the
    /// leftover sweep to the relaunch case: between two runs within one
    /// process the previous activity is deliberately still listed for a few
    /// seconds showing its completion state, and must not be swept.
    private var hasPresentedActivity = false

    init(
        store: (any RoundTimerLiveActivityStore)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        // Resolved in the `@MainActor` init body rather than as a default
        // argument, which would be evaluated in a nonisolated context.
        self.store = store ?? ActivityKitRoundTimerStore()
        self.now = now
    }

    /// The phase detail is trusted until the phase ends. A paused run never
    /// goes stale: nothing moves, so the frozen phase stays right.
    static func staleDate(for content: RoundTimerLiveActivityContent) -> Date? {
        guard content.pauseDate == nil else { return nil }
        return content.phase?.range.upperBound
    }

    func presentActivity(id: UUID, content: RoundTimerLiveActivityContent) {
        let staleDate = Self.staleDate(for: content)

        if presentedRunID == id, let presentedActivity {
            presentedActivity.update(content: content, staleDate: staleDate)
            return
        }

        if presentedActivity != nil {
            // Replacing a different run's activity.
            endPresentedActivity(completionMessage: nil)
        } else if !hasPresentedActivity {
            // Whatever the system still lists was started by an earlier
            // process, which cannot reach it any more.
            endLeftoverActivities()
        }

        guard store.areActivitiesEnabled else { return }

        do {
            presentedActivity = try store.requestActivity(content: content, staleDate: staleDate)
            presentedRunID = id
            hasPresentedActivity = true
        } catch let error as ActivityAuthorizationError {
            print("Round timer Live Activity not started (\(error)): \(error.localizedDescription)")
        } catch {
            print("Round timer Live Activity not started: \(error.localizedDescription)")
        }
    }

    func endActivity(id: UUID, completionMessage: String) {
        guard presentedRunID == id else { return }
        endPresentedActivity(completionMessage: completionMessage)
    }

    func dismissLeftoverActivities() {
        // Only before this process has presented anything: afterwards the
        // listed activities include our own.
        guard !hasPresentedActivity else { return }
        endLeftoverActivities()
    }

    private func endPresentedActivity(completionMessage: String?) {
        guard let activity = presentedActivity else { return }
        presentedActivity = nil
        presentedRunID = nil

        guard let completionMessage else {
            activity.end(completionMessage: nil, dismissAfter: nil)
            return
        }
        activity.end(
            completionMessage: completionMessage,
            dismissAfter: now().addingTimeInterval(Self.completionDisplayDuration)
        )
    }

    private func endLeftoverActivities() {
        for activity in store.currentActivities() {
            activity.end(completionMessage: nil, dismissAfter: nil)
        }
    }
}
