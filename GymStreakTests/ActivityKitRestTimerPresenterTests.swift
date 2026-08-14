//
//  ActivityKitRestTimerPresenterTests.swift
//  GymStreakTests
//
//  Contract tests for the rest timer's Lock Screen gateway (audit P1.5). The
//  presenter's policy — identity keying, idempotence, the authorization gate,
//  the leftover sweep, replacement — is asserted against a fake
//  `RestTimerLiveActivityStore`, because the real one needs an app bundle with
//  `NSSupportsLiveActivities` and the system daemon, neither of which exists in
//  a unit-test host.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct ActivityKitRestTimerPresenterTests {
    private final class FakeActivityHandle: RestTimerLiveActivityHandle {
        let deadline: Date
        private(set) var endCalls: [(completionMessage: String?, dismissAfter: Date?)] = []
        var isEnded: Bool { !endCalls.isEmpty }

        init(deadline: Date) {
            self.deadline = deadline
        }

        func end(completionMessage: String?, dismissAfter: Date?) {
            endCalls.append((completionMessage, dismissAfter))
        }
    }

    private final class FakeActivityStore: RestTimerLiveActivityStore {
        var areActivitiesEnabled = true
        var requestError: Error?

        private(set) var requests: [(workoutName: String, exerciseName: String?, timerRange: ClosedRange<Date>)] = []
        /// Everything the system would still list, including activities this
        /// process did not start. ActivityKit keeps an ended activity listed
        /// until it is dismissed, so ending does not remove it here either.
        var listedActivities: [FakeActivityHandle] = []

        func currentActivities() -> [any RestTimerLiveActivityHandle] {
            listedActivities
        }

        func requestActivity(
            workoutName: String,
            exerciseName: String?,
            timerRange: ClosedRange<Date>
        ) throws -> any RestTimerLiveActivityHandle {
            requests.append((workoutName, exerciseName, timerRange))
            if let requestError {
                throw requestError
            }
            let handle = FakeActivityHandle(deadline: timerRange.upperBound)
            listedActivities.append(handle)
            return handle
        }
    }

    private let now = Date(timeIntervalSinceReferenceDate: 10_000)

    private func makeContent(
        workoutName: String = "Push",
        exerciseName: String? = "Bench Press",
        start: Date,
        duration: TimeInterval = 60
    ) -> RestTimerLiveActivityContent {
        RestTimerLiveActivityContent(
            workoutName: workoutName,
            exerciseName: exerciseName,
            startDate: start,
            deadline: start.addingTimeInterval(duration)
        )
    }

    @Test
    func startingPresentsTheCountdownWithTheRequestedRangeAndNames() throws {
        let store = FakeActivityStore()
        let presenter = ActivityKitRestTimerPresenter(store: store, now: { self.now })

        presenter.startActivity(id: UUID(), content: makeContent(start: now))

        #expect(store.requests.count == 1)
        let request = try #require(store.requests.first)
        #expect(request.workoutName == "Push")
        #expect(request.exerciseName == "Bench Press")
        #expect(request.timerRange == now...now.addingTimeInterval(60))
    }

    /// The user turning Live Activities off must not produce a request — and
    /// must not be mistaken for a presented countdown afterwards.
    @Test
    func nothingIsRequestedWhenLiveActivitiesAreDisabled() {
        let store = FakeActivityStore()
        store.areActivitiesEnabled = false
        let presenter = ActivityKitRestTimerPresenter(store: store, now: { self.now })
        let id = UUID()

        presenter.startActivity(id: id, content: makeContent(start: now))
        #expect(store.requests.isEmpty)

        // Still re-tryable: nothing was presented, so this is not a duplicate.
        store.areActivitiesEnabled = true
        presenter.startActivity(id: id, content: makeContent(start: now))
        #expect(store.requests.count == 1)
    }

    /// `restoreTimerState` re-presents the running timer on every foreground.
    /// Requesting a second activity for a countdown that is already up would
    /// stack two of them on the Lock Screen.
    @Test
    func startingTheSameTimerTwiceDoesNotRequestASecondActivity() {
        let store = FakeActivityStore()
        let presenter = ActivityKitRestTimerPresenter(store: store, now: { self.now })
        let id = UUID()

        presenter.startActivity(id: id, content: makeContent(start: now))
        presenter.startActivity(id: id, content: makeContent(start: now))

        #expect(store.requests.count == 1)
        #expect(store.listedActivities.count == 1)
        #expect(store.listedActivities.allSatisfy { !$0.isEnded })
    }

    /// A new rest timer replaces the previous countdown rather than adding to
    /// it, and the replaced one goes away immediately — the "Rest Complete"
    /// state belongs to a timer that *finished*, not one that was superseded.
    @Test
    func startingADifferentTimerReplacesThePresentedCountdown() throws {
        let store = FakeActivityStore()
        let presenter = ActivityKitRestTimerPresenter(store: store, now: { self.now })

        presenter.startActivity(id: UUID(), content: makeContent(start: now))
        let first = try #require(store.listedActivities.first)

        presenter.startActivity(id: UUID(), content: makeContent(start: now.addingTimeInterval(90)))

        #expect(store.requests.count == 2)
        #expect(first.endCalls.count == 1)
        #expect(first.endCalls.first?.completionMessage == nil)
        #expect(first.endCalls.first?.dismissAfter == nil)
    }

    @Test
    func endingThePresentedTimerShowsTheCompletionStateBriefly() throws {
        let store = FakeActivityStore()
        let presenter = ActivityKitRestTimerPresenter(store: store, now: { self.now })
        let id = UUID()

        presenter.startActivity(id: id, content: makeContent(start: now))
        let activity = try #require(store.listedActivities.first)

        presenter.endActivity(id: id)

        #expect(activity.endCalls.count == 1)
        #expect(activity.endCalls.first?.completionMessage != nil)
        #expect(activity.endCalls.first?.dismissAfter == now.addingTimeInterval(3))
    }

    /// Both `WorkoutViewModel`s share one presenter, so an `endActivity` for a
    /// timer this presenter is not showing must do nothing at all.
    @Test
    func endingAnUnknownTimerLeavesThePresentedCountdownAlone() throws {
        let store = FakeActivityStore()
        let presenter = ActivityKitRestTimerPresenter(store: store, now: { self.now })

        presenter.startActivity(id: UUID(), content: makeContent(start: now))
        let activity = try #require(store.listedActivities.first)

        presenter.endActivity(id: UUID())

        #expect(activity.endCalls.isEmpty)
    }

    @Test
    func endingIsIdempotent() throws {
        let store = FakeActivityStore()
        let presenter = ActivityKitRestTimerPresenter(store: store, now: { self.now })
        let id = UUID()

        presenter.startActivity(id: id, content: makeContent(start: now))
        let activity = try #require(store.listedActivities.first)

        presenter.endActivity(id: id)
        presenter.endActivity(id: id)

        #expect(activity.endCalls.count == 1)
    }

    /// What `WorkoutViewModel.init` calls: only countdowns whose deadline has
    /// already passed are cleared. A leftover that is still running belongs to a
    /// rest the user may be in the middle of — a background launch would
    /// otherwise kill it with nothing to restore it.
    @Test
    func onlyExpiredLeftoversAreDismissed() {
        let store = FakeActivityStore()
        let expired = FakeActivityHandle(deadline: now.addingTimeInterval(-1))
        let running = FakeActivityHandle(deadline: now.addingTimeInterval(30))
        store.listedActivities = [expired, running]
        let presenter = ActivityKitRestTimerPresenter(store: store, now: { self.now })

        presenter.dismissExpiredActivities()

        #expect(expired.endCalls.count == 1)
        #expect(expired.endCalls.first?.dismissAfter == nil)
        #expect(running.endCalls.isEmpty)
    }

    /// Relaunching mid-rest: the previous process's countdown is still on the
    /// Lock Screen and this process cannot reach its handle, so presenting the
    /// restored timer must end it first or the user sees two countdowns.
    @Test
    func aStillRunningLeftoverIsEndedBeforeTheRestoredCountdownIsPresented() {
        let store = FakeActivityStore()
        let leftover = FakeActivityHandle(deadline: now.addingTimeInterval(30))
        store.listedActivities = [leftover]
        let presenter = ActivityKitRestTimerPresenter(store: store, now: { self.now })

        presenter.startActivity(id: UUID(), content: makeContent(start: now))

        #expect(leftover.endCalls.count == 1)
        #expect(store.requests.count == 1)
    }

    /// The sweep above must not fire between two timers inside one session:
    /// the previous countdown is deliberately still listed for a few seconds
    /// showing "Rest Complete", and cutting that short is a regression.
    @Test
    func aCompletedCountdownIsNotSweptWhenTheNextTimerStarts() throws {
        let store = FakeActivityStore()
        let presenter = ActivityKitRestTimerPresenter(store: store, now: { self.now })
        let first = UUID()

        presenter.startActivity(id: first, content: makeContent(start: now))
        let firstActivity = try #require(store.listedActivities.first)
        presenter.endActivity(id: first)
        #expect(firstActivity.endCalls.count == 1)

        presenter.startActivity(id: UUID(), content: makeContent(start: now.addingTimeInterval(1)))

        // Still exactly the one graceful end from `endActivity`.
        #expect(firstActivity.endCalls.count == 1)
        #expect(firstActivity.endCalls.first?.completionMessage != nil)
        #expect(store.requests.count == 2)
    }

    /// A failed request leaves nothing on screen, so the next attempt for the
    /// same timer must go through instead of being treated as a duplicate.
    @Test
    func aFailedRequestLeavesTheTimerRetryable() {
        let store = FakeActivityStore()
        store.requestError = ActivityKitTestError.denied
        let presenter = ActivityKitRestTimerPresenter(store: store, now: { self.now })
        let id = UUID()

        presenter.startActivity(id: id, content: makeContent(start: now))
        #expect(store.requests.count == 1)

        store.requestError = nil
        presenter.startActivity(id: id, content: makeContent(start: now))
        #expect(store.requests.count == 2)
        #expect(store.listedActivities.count == 1)
    }

    /// A `ClosedRange` with an inverted bound traps. No caller produces one
    /// today, but the presenter is the last line before ActivityKit.
    @Test
    func anInvertedTimerRangeIsRejectedRatherThanCrashing() {
        let store = FakeActivityStore()
        let presenter = ActivityKitRestTimerPresenter(store: store, now: { self.now })

        presenter.startActivity(
            id: UUID(),
            content: RestTimerLiveActivityContent(
                workoutName: "Push",
                exerciseName: nil,
                startDate: now,
                deadline: now.addingTimeInterval(-30)
            )
        )

        #expect(store.requests.isEmpty)
    }

    private enum ActivityKitTestError: Error {
        case denied
    }
}
