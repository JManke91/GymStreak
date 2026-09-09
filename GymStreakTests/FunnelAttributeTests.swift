//
//  FunnelAttributeTests.swift
//  GymStreakTests
//
//  What the funnel coordinator actually reads, and what it refuses to report
//  (docs/funnel-instrumentation.md). The bucket spelling itself is
//  `FunnelAttributeBucketTests`.
//
//  Three of these are ways the lever could ship looking fine and answer the
//  wrong question:
//
//  1. **The seeded starter routine is not a created routine.** A raw routine
//     count reports `"1"` for a user who built nothing, which inverts the one
//     question `routinesCreated` exists to answer.
//  2. **`buildChannel` fails toward `"other"`.** It exists to *exclude* noise
//     (§1.1: 30% of customers were on builds that were never on the App Store),
//     so anything short of a verified production transaction must not read as an
//     App Store install.
//  3. **A failed read reports nothing.** "Nobody trains" is precisely the
//     conclusion this lever is here to test, so it may never be manufactured by
//     a count that threw.
//

import Foundation
import StoreKit
import SwiftData
import Testing
@testable import GymStreak

@Suite
@MainActor
struct FunnelAttributeTests {

    // MARK: - What the coordinator reads

    @Test("A fresh install reports all four attributes")
    func freshInstallReportsEverything() async {
        let fixture = makeFixture()

        await fixture.coordinator.reportCurrentState()

        #expect(fixture.reporter.reported.count == 1)
        #expect(fixture.reporter.reported.last?.onboardingCompleted == "false")
        #expect(fixture.reporter.reported.last?.workoutsCompleted == "0")
        #expect(fixture.reporter.reported.last?.routinesCreated == "0")
        #expect(fixture.reporter.reported.last?.buildChannel == "other")
    }

    @Test("The seeded starter routine is not a created routine")
    func seededRoutineIsNotCreated() async {
        let fixture = makeFixture()
        insertRoutine(named: "Full Body Starter", seedKey: "seed.routine.full_body_starter", into: fixture)

        await fixture.coordinator.reportCurrentState()

        #expect(fixture.reporter.reported.last?.routinesCreated == "0")
    }

    @Test("A routine the user built counts, alongside the seeded one")
    func userCreatedRoutineCounts() async {
        let fixture = makeFixture()
        insertRoutine(named: "Full Body Starter", seedKey: "seed.routine.full_body_starter", into: fixture)
        insertRoutine(named: "Push Day", seedKey: "", into: fixture)

        await fixture.coordinator.reportCurrentState()

        #expect(fixture.reporter.reported.last?.routinesCreated == "1")
    }

    @Test("Finishing the tour is reported from the record, not from a flag of its own")
    func onboardingIsReadFromTheRecord() async {
        let fixture = makeFixture()
        fixture.onboarding.recordCompleted()

        await fixture.coordinator.reportCurrentState()

        #expect(fixture.reporter.reported.last?.onboardingCompleted == "true")
    }

    @Test("The workout bucket moves as sessions are completed")
    func workoutBucketMovesWithTheCount() async {
        let counts = StubWorkoutCount(0)
        let fixture = makeFixture(counts: counts)

        await fixture.coordinator.reportCurrentState()
        await counts.set(3)
        await fixture.coordinator.reportCurrentState()
        await counts.set(9)
        await fixture.coordinator.reportCurrentState()

        #expect(fixture.reporter.reported.map(\.workoutsCompleted) == ["0", "2-4", "5+"])
    }

    // MARK: - Build channel

    @Test("Only a verified production transaction reads as an App Store install")
    func productionReadsAsAppStore() async {
        let fixture = makeFixture(
            downloads: StubDownloads(.download(.verified(environment: .production, originalAppVersion: "1")))
        )

        await fixture.coordinator.reportCurrentState()

        #expect(fixture.reporter.reported.last?.buildChannel == "appstore")
    }

    @Test(
        "Everything that is not a verified production transaction reads as other",
        arguments: [
            StubDownloadOutcome.download(.verified(environment: .sandbox, originalAppVersion: "1")),
            .download(.verified(environment: .xcode, originalAppVersion: "1")),
            .download(.unverified),
            .failure
        ]
    )
    func everythingElseReadsAsOther(outcome: StubDownloadOutcome) async {
        let fixture = makeFixture(downloads: StubDownloads(outcome))

        await fixture.coordinator.reportCurrentState()

        #expect(fixture.reporter.reported.last?.buildChannel == "other")
    }

    @Test("StoreKit is asked once per process, not once per report")
    func buildChannelIsResolvedOnce() async {
        let downloads = StubDownloads(.download(.verified(environment: .production, originalAppVersion: "1")))
        let fixture = makeFixture(downloads: downloads)

        await fixture.coordinator.reportCurrentState()
        await fixture.coordinator.reportCurrentState()
        await fixture.coordinator.reportCurrentState()

        #expect(downloads.callCount == 1)
        #expect(fixture.reporter.reported.count == 3)
    }

    @Test("A lookup that failed is not remembered — the next report asks again")
    func failedLookupIsRetried() async {
        let downloads = StubDownloads(.failure)
        let fixture = makeFixture(downloads: downloads)

        await fixture.coordinator.reportCurrentState()
        downloads.outcome = .download(.verified(environment: .production, originalAppVersion: "1"))
        await fixture.coordinator.reportCurrentState()

        #expect(fixture.reporter.reported.map(\.buildChannel) == ["other", "appstore"])
    }

    // MARK: - The tour reports in the session it ended

    @Test("Finishing the tour reports in the same session, not on the next launch")
    func tourEndingReportsImmediately() async {
        let fixture = makeFixture()
        let tour = OnboardingFlowViewModel(
            completion: fixture.onboarding,
            funnelAttributes: fixture.coordinator
        )

        tour.skip()

        // The tour detaches the report so its dismissal never waits on
        // analytics, so this waits for it rather than calling the coordinator
        // itself — the point of the test is the wiring, not the coordinator.
        await settle(until: { !fixture.reporter.reported.isEmpty })

        #expect(fixture.reporter.reported.last?.onboardingCompleted == "true")
    }

    // MARK: - What is never reported

    @Test("A workout count that threw reports nothing at all, rather than reporting zero")
    func failedCountReportsNothing() async {
        let counts = StubWorkoutCount(0)
        await counts.setUnreachable(true)
        let fixture = makeFixture(counts: counts)

        await fixture.coordinator.reportCurrentState()

        #expect(fixture.reporter.reported.isEmpty)
    }

    // MARK: - Fixtures

    /// Yields until `condition` holds, or gives up. Bounded rather than a sleep:
    /// the work being waited on is a `Task` hop plus an `actor` read, so it
    /// completes in a handful of yields on a passing run and the bound only
    /// exists so a failing one reports the assertion instead of hanging.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }

    private struct Fixture {
        let coordinator: FunnelAttributeCoordinator
        let reporter: SpyReporter
        let onboarding: OnboardingCompletionStore
        let context: ModelContext
        let routineRepository: RoutineRepository
    }

    /// The routine count runs against a **real** repository over an in-memory
    /// store, not a stub: "the seeded starter routine does not count" is a
    /// property of `seedKey` and of the fetch, and a stubbed count would assert
    /// it away.
    private func makeFixture(
        counts: StubWorkoutCount = StubWorkoutCount(0),
        downloads: StubDownloads = StubDownloads(.failure)
    ) -> Fixture {
        let context = ModelContext(InMemoryModelContainer.make())
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        let onboarding = OnboardingCompletionStore(
            defaults: UserDefaults(suiteName: "FunnelAttributeTests.\(UUID().uuidString)")!
        )
        let reporter = SpyReporter()
        return Fixture(
            coordinator: FunnelAttributeCoordinator(
                onboarding: onboarding,
                totals: counts,
                routineRepository: routineRepository,
                downloads: downloads,
                reporter: reporter
            ),
            reporter: reporter,
            onboarding: onboarding,
            context: context,
            routineRepository: routineRepository
        )
    }

    private func insertRoutine(named name: String, seedKey: String, into fixture: Fixture) {
        let routine = Routine(name: name)
        routine.seedKey = seedKey
        fixture.routineRepository.insert(routine)
        try? fixture.routineRepository.save()
    }
}
