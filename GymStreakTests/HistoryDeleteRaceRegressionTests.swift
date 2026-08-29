//
//  HistoryDeleteRaceRegressionTests.swift
//  GymStreakTests
//
//  The canary for the History delete race (docs/history-delete-race.md).
//
//  `HistoryStoreGateTests` asserts the gate's *properties* — exclusivity, release on throw,
//  and that specific delete paths block. Those would catch someone removing the gate from
//  `deleteWorkout`; they would not catch a reader that stops taking it, because they never
//  run a real reader against a real writer.
//
//  This suite does. It drives the actual `SwiftDataHistorySnapshotProvider` over an actual
//  on-disk store while the actual `WorkoutViewModel.deleteWorkout` cascades rows out from
//  underneath it, and repeats the race enough times to be more than anecdote.
//
//  **How this test fails.** Not with a red assertion. If the gate stops excluding these two,
//  SwiftData traps — `BackingData.swift:1039`, "This model instance was invalidated because
//  its backing data could no longer be found the store" — and that is an uncatchable
//  `fatalError`, so the whole test runner dies and the run reports a crash rather than a
//  failure. A crashed run *is* this test failing. That is also why the reproduction itself
//  cannot live in the suite: it would kill every other test with it.
//
//  Verified to actually detect the regression: handing the provider its own
//  `HistoryStoreGate.unshared()` instead of the shared one — i.e. exactly the "looks wired,
//  excludes nothing" mistake the initialisers are shaped to prevent — crashes this suite.
//  See `docs/history-delete-race.md`.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
struct HistoryDeleteRaceRegressionTests {

    /// How many times the race is run. Each iteration is an independent store, so this is a
    /// sample size rather than a loop over shared state: the race is timing-dependent, and a
    /// single pass proves very little either way.
    private static let raceIterations = 12

    /// Big enough that the actor's synchronous walk takes real time on the global executor —
    /// which is what gives the concurrent delete a window to land inside it. A handful of
    /// rows completes before the delete is even scheduled and would pass with no gate at all.
    private static let sessionCount = 60
    private static let exercisesPerSession = 8
    private static let setsPerExercise = 5

    /// When each delete is fired, measured from the start of the read. Several deletes
    /// spread across the walk rather than one, because a single well-timed delete is still a
    /// guess: too early and it commits before the model actor has even finished starting up,
    /// too late and the walk is already over. Spreading them means at least one lands inside
    /// the walk without the test having to know how long the walk takes on this machine.
    /// Measured detection of the ungated regression: 4 runs in 6 with one delete, 6 in 6 with
    /// these three.
    private static let deleteOffsets: [Duration] = [
        .milliseconds(25), .milliseconds(50), .milliseconds(75)
    ]

    @Test
    @MainActor
    func aHistoryRebuildAndACompletedSessionDeleteNeverOverlap() async throws {
        var completedReads = 0
        var completedDeletes = 0

        for _ in 0..<Self.raceIterations {
            let (container, cleanUp) = try FileBackedModelContainer.make()
            defer { cleanUp() }

            let context = ModelContext(container)
            let sessionRepository = SwiftDataWorkoutSessionRepository(modelContext: context)
            try Self.seedCompletedGraph(into: context, repository: sessionRepository)

            // THE point of the test: one gate instance, shared by the reader and the writer,
            // exactly as `AppDependencies` wires them. Two gates here would compile, read as
            // wired, and serialize nothing.
            let gate = HistoryStoreGate()
            let provider = SwiftDataHistorySnapshotProvider(modelContainer: container, gate: gate)
            let viewModel = Self.makeViewModel(context: context, gate: gate)

            let doomed = Array(
                try context.fetch(FetchDescriptor<WorkoutSession>()).prefix(Self.deleteOffsets.count)
            )
            #expect(doomed.count == Self.deleteOffsets.count)
            let doomedIDs = doomed.map(\.id)

            // Started first so the walk is already underway when the delete arrives; the
            // delete then cascades this session's exercises and sets out from under it.
            // The read is `@concurrent`, so it genuinely leaves the main actor while the
            // delete task runs on it — that is the overlap being tested.
            async let snapshot = provider.fetchTrainingSnapshot(referenceDate: Date())

            // Deletes fired at spread offsets while the walk runs — see `deleteOffsets`.
            // `Task { @MainActor in … }` rather than a second `async let`: a `WorkoutSession`
            // is a `@Model` and therefore non-`Sendable`, so it must not cross into a
            // concurrent child task. Same shape as `HistoryStoreGateTests`.
            var deletions: [Task<Void, Never>] = []
            var elapsed = Duration.zero
            for (index, session) in doomed.enumerated() {
                try await Task.sleep(for: Self.deleteOffsets[index] - elapsed)
                elapsed = Self.deleteOffsets[index]
                deletions.append(Task { @MainActor in await viewModel.deleteWorkout(session) })
            }

            let built = try await snapshot
            for deletion in deletions { await deletion.value }

            // Both sides have to have actually done their work — a gate that deadlocked, or a
            // read that silently returned nothing, must not read as a pass.
            #expect(built.sessionCount > 0, "the reader produced an empty snapshot")
            completedReads += 1

            for doomedID in doomedIDs {
                #expect(
                    sessionRepository.findSession(id: doomedID, healthKitWorkoutId: nil) == nil,
                    "a delete did not land"
                )
            }
            completedDeletes += 1
        }

        #expect(completedReads == Self.raceIterations)
        #expect(completedDeletes == Self.raceIterations)
    }

    // MARK: - Fixture

    @MainActor
    private static func seedCompletedGraph(
        into context: ModelContext,
        repository: SwiftDataWorkoutSessionRepository
    ) throws {
        for sessionIndex in 0..<sessionCount {
            let session = WorkoutSession(routine: nil)
            session.routineName = "Race \(sessionIndex)"
            // `endTime != nil` is the predicate both History fetches select on — without it
            // these rows are invisible to the reader and the test proves nothing.
            session.endTime = session.startTime.addingTimeInterval(3600)
            context.insert(session)

            for order in 0..<exercisesPerSession {
                let exercise = WorkoutExercise(
                    exerciseName: "Exercise \(order)",
                    muscleGroups: ["Chest"],
                    order: order,
                    exerciseId: UUID(),
                    routineExerciseId: UUID(),
                    loadBehavior: .resistance
                )
                exercise.workoutSession = session
                context.insert(exercise)

                for setOrder in 0..<setsPerExercise {
                    let set = WorkoutSet(
                        plannedReps: 8,
                        actualReps: 8,
                        plannedWeight: 60,
                        actualWeight: 60,
                        restTime: 90,
                        order: setOrder
                    )
                    set.isCompleted = true
                    set.workoutExercise = exercise
                    context.insert(set)
                }
            }
        }
        try repository.save()
    }

    @MainActor
    private static func makeViewModel(context: ModelContext, gate: HistoryStoreGate) -> WorkoutViewModel {
        let routineRepository = SwiftDataRoutineRepository(modelContext: context)
        return WorkoutViewModel(
            workoutSessionRepository: SwiftDataWorkoutSessionRepository(modelContext: context),
            routineRepository: routineRepository,
            healthKitManager: MockHealthKitWorkoutServicing(),
            watchSync: MockWatchSyncServicing(),
            workoutHistoryCorrelation: EmptyHistoryCorrelation(),
            restTimerReminders: NoopRestTimerReminders(),
            restTimerLiveActivity: RecordingRestTimerLiveActivity(),
            routineTemplateSync: RoutineTemplateSyncService(
                routineRepository: routineRepository,
                exerciseRepository: SwiftDataExerciseRepository(modelContext: context)
            ),
            historyStoreGate: gate
        )
    }

    private final class EmptyHistoryCorrelation: WorkoutHistoryCorrelationProviding {
        func healthKitWorkoutIDs() throws -> Set<UUID> { [] }
        func sessionID(forHealthKitWorkoutId id: UUID) throws -> UUID? { nil }
    }

    private final class NoopRestTimerReminders: RestTimerReminderScheduling {
        func scheduleReminder(id: UUID, deadline: Date) async -> RestTimerReminderOutcome { .scheduled }
        func cancelReminder(id: UUID) {}
    }
}
