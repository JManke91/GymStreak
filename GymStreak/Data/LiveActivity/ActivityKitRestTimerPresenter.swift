//
//  ActivityKitRestTimerPresenter.swift
//  GymStreak
//
//  The only type in the iOS app target that imports ActivityKit (the widget
//  extension has its own). Extracted from `WorkoutViewModel` by audit P1.5,
//  mirroring `Domain/Interfaces/RestTimerReminderScheduling.swift` +
//  `Data/Notifications/UserNotificationRestTimerScheduler.swift`.
//
//  `RestTimerLiveActivityStore` is the injectable seam over ActivityKit itself:
//  `Activity.request` needs a real app bundle with `NSSupportsLiveActivities`
//  and the running system daemon, neither of which a unit-test host has, so the
//  presenter's policy — identity keying, idempotence, the authorization gate,
//  the leftover sweep — is only testable behind a protocol.
//
//  Concurrency, verified against the iOS 26.5 SDK's `ActivityKit.swiftinterface`
//  rather than assumed:
//  - `public class Activity<Attributes>` carries **no** isolation annotation and
//    is **not** `Sendable`.
//  - `end(_:dismissalPolicy:)` is a plain `nonisolated async` method — it is
//    *not* `@concurrent`, contrary to what this project's own comments claimed
//    before this change (corrected in docs/swift6-concurrency.md §8).
//  ActivityKit's module is built `-swift-version 5` and without SE-0461, so
//  awaiting `end` still leaves the main actor and handing it our main-actor-held
//  `Activity` is a non-`Sendable` crossing. Verified, not assumed: dropping
//  `@preconcurrency` below fails the build with
//  `error: sending 'self.activity' risks causing data races` at the `await` in
//  `ActivityKitHandle.end`. It is the migration guide's sanctioned tool for that
//  gap and stays until ActivityKit ships annotations — now confined to this
//  file instead of covering a 2,000-line ViewModel.
//

import Foundation
@preconcurrency import ActivityKit

// MARK: - Injectable ActivityKit seam

/// One presented Live Activity. Fire-and-forget: ending is asynchronous inside
/// ActivityKit, but nothing in the app waits on it.
@MainActor
protocol RestTimerLiveActivityHandle: AnyObject {
    /// The end of this activity's countdown — how a leftover from an earlier
    /// app process is recognised as already expired.
    var deadline: Date { get }

    /// Ends the activity. A `completionMessage` shows a final state until
    /// `dismissAfter`; passing `nil` for both dismisses immediately.
    func end(completionMessage: String?, dismissAfter: Date?)
}

/// The ActivityKit entry points the presenter uses.
@MainActor
protocol RestTimerLiveActivityStore {
    /// Whether the user has Live Activities turned on for GymStreak.
    var areActivitiesEnabled: Bool { get }

    /// Every rest-timer activity the system currently knows about, including
    /// ones started by an earlier launch of the app.
    func currentActivities() -> [any RestTimerLiveActivityHandle]

    func requestActivity(
        workoutName: String,
        exerciseName: String?,
        timerRange: ClosedRange<Date>
    ) throws -> any RestTimerLiveActivityHandle
}

// MARK: - ActivityKit conformance

@MainActor
final class ActivityKitRestTimerStore: RestTimerLiveActivityStore {
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func currentActivities() -> [any RestTimerLiveActivityHandle] {
        Activity<RestTimerAttributes>.activities.map(ActivityKitHandle.init)
    }

    func requestActivity(
        workoutName: String,
        exerciseName: String?,
        timerRange: ClosedRange<Date>
    ) throws -> any RestTimerLiveActivityHandle {
        let content = ActivityContent(
            state: RestTimerAttributes.ContentState(
                timerRange: timerRange,
                exerciseName: exerciseName,
                completionMessage: nil
            ),
            // The countdown's own end is the point after which the content is
            // no longer trustworthy — the same absolute deadline the in-app
            // timer and the local notification use.
            staleDate: timerRange.upperBound
        )
        return ActivityKitHandle(
            try Activity.request(
                attributes: RestTimerAttributes(workoutName: workoutName),
                content: content,
                pushType: nil
            )
        )
    }
}

@MainActor
private final class ActivityKitHandle: RestTimerLiveActivityHandle {
    private let activity: Activity<RestTimerAttributes>

    init(_ activity: Activity<RestTimerAttributes>) {
        self.activity = activity
    }

    var deadline: Date {
        activity.content.state.timerRange.upperBound
    }

    func end(completionMessage: String?, dismissAfter: Date?) {
        let content: ActivityContent<RestTimerAttributes.ContentState>? = completionMessage.map {
            message in
            let stamp = Date.now
            return ActivityContent(
                state: RestTimerAttributes.ContentState(
                    timerRange: stamp...stamp,
                    exerciseName: nil,
                    completionMessage: message
                ),
                staleDate: nil
            )
        }
        let policy: ActivityUIDismissalPolicy = dismissAfter.map { .after($0) } ?? .immediate

        // `Task` inherits this main actor; the non-`Sendable` `activity` only
        // crosses at the `await`, which is what `@preconcurrency` covers.
        Task {
            await activity.end(content, dismissalPolicy: policy)
        }
    }
}

// MARK: - Presenter

@MainActor
final class ActivityKitRestTimerPresenter: RestTimerLiveActivityPresenting {
    /// How long the "Rest Complete" state stays on screen after the timer ends.
    private static let completionDisplayDuration: TimeInterval = 3
    /// Localized here, in the app process: the widget extension only renders
    /// whatever string arrives in `ContentState`, so it needs no key of its own.
    private static var completionMessage: String {
        "live_activity.rest_timer.complete".localized
    }

    private let store: any RestTimerLiveActivityStore
    private let now: () -> Date

    /// Non-nil exactly when `presentedActivity` is — the timer whose countdown
    /// this presenter put on screen. A failed request leaves both nil, so a
    /// later restore retries instead of assuming the countdown is up.
    private var presentedTimerID: UUID?
    private var presentedActivity: (any RestTimerLiveActivityHandle)?
    /// Whether this process has ever put a countdown on screen. Gates the
    /// leftover sweep to the relaunch case only: between two rest timers within
    /// one session the previous activity is deliberately still on screen for a
    /// few seconds showing "Rest Complete", and must not be swept.
    private var hasPresentedActivity = false

    init(
        store: (any RestTimerLiveActivityStore)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        // Resolved in the `@MainActor` init body rather than as a default
        // argument, which would be evaluated in a nonisolated context.
        self.store = store ?? ActivityKitRestTimerStore()
        self.now = now
    }

    func startActivity(id: UUID, content: RestTimerLiveActivityContent) {
        guard presentedTimerID != id else { return }
        // A `ClosedRange` with an inverted bound traps. No caller produces one
        // today (the only extension is +30s), but a crash is too high a price
        // for a countdown.
        guard content.deadline >= content.startDate else { return }

        if presentedActivity != nil {
            // Replacing a different timer's countdown.
            endPresentedActivity(showingCompletion: false)
        } else if !hasPresentedActivity {
            // This process has never presented anything, so whatever the system
            // still lists was started by an earlier one. Ending it before
            // requesting is what stops a relaunch mid-rest from stacking two
            // countdowns on the Lock Screen.
            endLeftoverActivities()
        }

        guard store.areActivitiesEnabled else { return }

        do {
            presentedActivity = try store.requestActivity(
                workoutName: content.workoutName,
                exerciseName: content.exerciseName,
                timerRange: content.startDate...content.deadline
            )
            presentedTimerID = id
            hasPresentedActivity = true
        } catch let error as ActivityAuthorizationError {
            // Typed, unlike the string matching this replaced: two of the three
            // names that code compared against (`activitiesDisabled`,
            // `activityLimitExceeded`) are not cases of this enum at all, and
            // `localizedDescription` yields a localized sentence rather than a
            // case name — so none of those branches could ever be taken.
            print("Rest timer Live Activity not started (\(error)): \(error.localizedDescription)")
        } catch {
            print("Rest timer Live Activity not started: \(error.localizedDescription)")
        }
    }

    func endActivity(id: UUID) {
        guard presentedTimerID == id else { return }
        endPresentedActivity(showingCompletion: true)
    }

    func dismissExpiredActivities() {
        for activity in store.currentActivities() where activity.deadline < now() {
            activity.end(completionMessage: nil, dismissAfter: nil)
        }
    }

    private func endPresentedActivity(showingCompletion: Bool) {
        guard let activity = presentedActivity else { return }
        presentedActivity = nil
        presentedTimerID = nil

        guard showingCompletion else {
            activity.end(completionMessage: nil, dismissAfter: nil)
            return
        }
        activity.end(
            completionMessage: Self.completionMessage,
            dismissAfter: now().addingTimeInterval(Self.completionDisplayDuration)
        )
    }

    private func endLeftoverActivities() {
        for activity in store.currentActivities() {
            activity.end(completionMessage: nil, dismissAfter: nil)
        }
    }
}
