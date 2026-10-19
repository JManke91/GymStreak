//
//  ActivityKitRoundTimerPresenterTests.swift
//  GymStreakTests
//
//  Contract tests for the round timer's Lock Screen gateway
//  (docs/fight-conditioning.md, "Round timer" → Live Activity), against a fake
//  `RoundTimerLiveActivityStore` like `ActivityKitRestTimerPresenterTests`:
//  start, per-phase update with the phase end as `staleDate`, pause (no stale
//  date — nothing moves), end with a completion state, identity, and the
//  leftover sweep.
//

import Foundation
import Testing
@testable import GymStreak

@Suite
@MainActor
struct ActivityKitRoundTimerPresenterTests {
    private let now = Date(timeIntervalSinceReferenceDate: 10_000)

    private static let run = RoundTimerLiveActivityContent.Run(
        title: "Round timer", subtitle: "BJJ · 5:00 / 1:00", isOpenEnded: false,
        timeLabel: "Time left", pausedLabel: "Paused", staleNote: "Open Gym Streak for the rounds"
    )

    /// A 6 × 5:00 / 1:00 run started at `start`, in the round `round` (1-based),
    /// `into` seconds in; paused at `pauseDate` when given.
    private func makeContent(
        start: Date,
        round: Int = 1,
        pauseDate: Date? = nil,
        phase: Bool = true
    ) -> RoundTimerLiveActivityContent {
        let roundStart = start.addingTimeInterval(TimeInterval(round - 1) * 360)
        return RoundTimerLiveActivityContent(
            run: Self.run,
            runRange: start...start.addingTimeInterval(35 * 60),
            pauseDate: pauseDate,
            phase: phase
                ? .init(label: "ROUND", isRound: true, position: "Round \(round) of 6",
                        range: roundStart...roundStart.addingTimeInterval(300))
                : nil
        )
    }

    @Test
    func startingRequestsTheRunWithThePhaseEndAsStaleDate() throws {
        let store = FakeRoundTimerLiveActivityStore()
        let presenter = ActivityKitRoundTimerPresenter(store: store, now: { self.now })

        presenter.presentActivity(id: UUID(), content: makeContent(start: now))

        #expect(store.requests.count == 1)
        let request = try #require(store.requests.first)
        #expect(request.content.run.subtitle == "BJJ · 5:00 / 1:00")
        #expect(request.content.runRange == now...now.addingTimeInterval(35 * 60))
        #expect(request.content.phase?.position == "Round 1 of 6")
        #expect(request.staleDate == now.addingTimeInterval(300))
    }

    /// Every boundary while the app is on screen is an update of the one
    /// activity — never a second request — carrying the new phase's end.
    @Test
    func presentingTheSameRunAgainUpdatesThePhaseInsteadOfRequesting() throws {
        let store = FakeRoundTimerLiveActivityStore()
        let presenter = ActivityKitRoundTimerPresenter(store: store, now: { self.now })
        let id = UUID()

        presenter.presentActivity(id: id, content: makeContent(start: now))
        let activity = try #require(store.listedActivities.first)
        presenter.presentActivity(id: id, content: makeContent(start: now, round: 2))

        #expect(store.requests.count == 1)
        #expect(activity.updates.count == 1)
        #expect(activity.updates.first?.content.phase?.position == "Round 2 of 6")
        #expect(activity.updates.first?.staleDate == now.addingTimeInterval(360 + 300))
        #expect(!activity.isEnded)
    }

    /// A paused run never goes stale: the frozen phase stays right for as long
    /// as the pause lasts, so no stale date is set — on request or on update.
    @Test
    func aPausedRunCarriesNoStaleDate() throws {
        let store = FakeRoundTimerLiveActivityStore()
        let presenter = ActivityKitRoundTimerPresenter(store: store, now: { self.now })
        let id = UUID()
        let paused = makeContent(start: now, pauseDate: now.addingTimeInterval(42))

        presenter.presentActivity(id: id, content: paused)
        #expect(store.requests.first?.staleDate == nil)
        #expect(store.requests.first?.content.pauseDate == now.addingTimeInterval(42))

        presenter.presentActivity(id: id, content: makeContent(start: now))
        let activity = try #require(store.listedActivities.first)
        #expect(activity.updates.last?.staleDate == now.addingTimeInterval(300))

        presenter.presentActivity(id: id, content: paused)
        #expect(activity.updates.last?.staleDate == nil)
        #expect(ActivityKitRoundTimerPresenter.staleDate(for: makeContent(start: now, phase: false)) == nil)
    }

    @Test
    func nothingIsRequestedWhenLiveActivitiesAreDisabled() {
        let store = FakeRoundTimerLiveActivityStore()
        store.areActivitiesEnabled = false
        let presenter = ActivityKitRoundTimerPresenter(store: store, now: { self.now })
        let id = UUID()

        presenter.presentActivity(id: id, content: makeContent(start: now))
        #expect(store.requests.isEmpty)

        // Still re-tryable at the next transition: nothing was presented.
        store.areActivitiesEnabled = true
        presenter.presentActivity(id: id, content: makeContent(start: now, round: 2))
        #expect(store.requests.count == 1)
    }

    /// A new run replaces the previous activity rather than adding to it, and
    /// the replaced one goes away immediately — the completion state belongs
    /// to a run that *ended*, not one that was superseded.
    @Test
    func presentingADifferentRunReplacesThePresentedActivity() throws {
        let store = FakeRoundTimerLiveActivityStore()
        let presenter = ActivityKitRoundTimerPresenter(store: store, now: { self.now })

        presenter.presentActivity(id: UUID(), content: makeContent(start: now))
        let first = try #require(store.listedActivities.first)

        presenter.presentActivity(id: UUID(), content: makeContent(start: now.addingTimeInterval(90)))

        #expect(store.requests.count == 2)
        #expect(first.endCalls.count == 1)
        #expect(first.endCalls.first?.completionMessage == nil)
        #expect(first.endCalls.first?.dismissAfter == nil)
    }

    @Test
    func endingThePresentedRunShowsTheCompletionStateBriefly() throws {
        let store = FakeRoundTimerLiveActivityStore()
        let presenter = ActivityKitRoundTimerPresenter(store: store, now: { self.now })
        let id = UUID()

        presenter.presentActivity(id: id, content: makeContent(start: now))
        let activity = try #require(store.listedActivities.first)

        presenter.endActivity(id: id, completionMessage: "Rounds complete · 6 rounds · 35:00")

        #expect(activity.endCalls.count == 1)
        #expect(activity.endCalls.first?.completionMessage == "Rounds complete · 6 rounds · 35:00")
        #expect(activity.endCalls.first?.dismissAfter
                == now.addingTimeInterval(ActivityKitRoundTimerPresenter.completionDisplayDuration))
    }

    @Test
    func endingAnUnknownRunLeavesThePresentedActivityAloneAndEndingIsIdempotent() throws {
        let store = FakeRoundTimerLiveActivityStore()
        let presenter = ActivityKitRoundTimerPresenter(store: store, now: { self.now })
        let id = UUID()

        presenter.presentActivity(id: id, content: makeContent(start: now))
        let activity = try #require(store.listedActivities.first)

        presenter.endActivity(id: UUID(), completionMessage: "Rounds complete")
        #expect(activity.endCalls.isEmpty)

        presenter.endActivity(id: id, completionMessage: "Rounds complete")
        presenter.endActivity(id: id, completionMessage: "Rounds complete")
        #expect(activity.endCalls.count == 1)

        // After the end, the id is no longer presented: a late transition
        // would request anew rather than update an ended activity.
        presenter.presentActivity(id: id, content: makeContent(start: now))
        #expect(store.requests.count == 2)
    }

    /// What `GymStreakApp` calls at launch: no run survives a relaunch, so every
    /// listed activity is a leftover, whatever its dates — unlike the rest
    /// timer's expired-only sweep.
    @Test
    func theLaunchSweepEndsEveryLeftover() {
        let store = FakeRoundTimerLiveActivityStore()
        let stillRunning = FakeRoundTimerLiveActivityHandle()
        let longOver = FakeRoundTimerLiveActivityHandle()
        store.listedActivities = [stillRunning, longOver]
        let presenter = ActivityKitRoundTimerPresenter(store: store, now: { self.now })

        presenter.dismissLeftoverActivities()

        #expect(stillRunning.endCalls.count == 1)
        #expect(stillRunning.endCalls.first?.dismissAfter == nil)
        #expect(longOver.endCalls.count == 1)
    }

    /// Once this process has presented, the listed activities include its own;
    /// the sweep must not touch it.
    @Test
    func theSweepDoesNothingAfterThisProcessHasPresented() throws {
        let store = FakeRoundTimerLiveActivityStore()
        let presenter = ActivityKitRoundTimerPresenter(store: store, now: { self.now })

        presenter.presentActivity(id: UUID(), content: makeContent(start: now))
        let activity = try #require(store.listedActivities.first)

        presenter.dismissLeftoverActivities()

        #expect(activity.endCalls.isEmpty)
    }

    /// Relaunching mid-run: the previous process's activity is still on the Lock
    /// Screen and this process cannot reach its handle, so the first present
    /// ends it or the user sees two.
    @Test
    func aLeftoverIsEndedBeforeTheFirstActivityIsPresented() {
        let store = FakeRoundTimerLiveActivityStore()
        let leftover = FakeRoundTimerLiveActivityHandle()
        store.listedActivities = [leftover]
        let presenter = ActivityKitRoundTimerPresenter(store: store, now: { self.now })

        presenter.presentActivity(id: UUID(), content: makeContent(start: now))

        #expect(leftover.endCalls.count == 1)
        #expect(store.requests.count == 1)
    }

    /// The sweep must not fire between two runs inside one process: the
    /// previous activity is deliberately still listed for a few seconds showing
    /// "Rounds complete".
    @Test
    func aCompletedActivityIsNotSweptWhenTheNextRunStarts() throws {
        let store = FakeRoundTimerLiveActivityStore()
        let presenter = ActivityKitRoundTimerPresenter(store: store, now: { self.now })
        let first = UUID()

        presenter.presentActivity(id: first, content: makeContent(start: now))
        let firstActivity = try #require(store.listedActivities.first)
        presenter.endActivity(id: first, completionMessage: "Rounds complete")

        presenter.presentActivity(id: UUID(), content: makeContent(start: now.addingTimeInterval(1)))

        #expect(firstActivity.endCalls.count == 1)
        #expect(firstActivity.endCalls.first?.completionMessage == "Rounds complete")
        #expect(store.requests.count == 2)
    }

    /// A failed request leaves nothing on screen, so the next transition for
    /// the same run must request again instead of updating nothing.
    @Test
    func aFailedRequestLeavesTheRunRetryable() {
        let store = FakeRoundTimerLiveActivityStore()
        store.requestError = ActivityKitTestError.denied
        let presenter = ActivityKitRoundTimerPresenter(store: store, now: { self.now })
        let id = UUID()

        presenter.presentActivity(id: id, content: makeContent(start: now))
        #expect(store.requests.count == 1)

        store.requestError = nil
        presenter.presentActivity(id: id, content: makeContent(start: now, round: 2))
        #expect(store.requests.count == 2)
        #expect(store.listedActivities.count == 1)
    }

    private enum ActivityKitTestError: Error {
        case denied
    }
}
