//
//  LegacyHistoryAttributionTests.swift
//  GymStreakTests
//
//  Ticket 07: legacy workout history that cannot be attributed by name stops
//  disappearing silently, and the user can resolve it.
//
//  The drop itself is deliberate and is pinned here too: attribution must be the only
//  thing that brings an ambiguous row back, and it must change nothing but the link.
//

import Foundation
import SwiftData
import Testing
@testable import GymStreak

@Suite(.serialized)
@MainActor
struct LegacyHistoryAttributionTests {

    // MARK: - Detection

    @Test("Ambiguous legacy workouts are reported, with the count and period the user sees")
    func ambiguousLegacyHistoryIsReported() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let barbell = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        let dumbbell = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(barbell)
        context.insert(dumbbell)

        let first = makeSession(at: 1_000, in: context)
        addRow(named: "Biceps Curls", exerciseId: nil, sets: [(20, 10, true)], to: first, context: context)
        let second = makeSession(at: 9_000, in: context)
        addRow(named: "Biceps Curls", exerciseId: nil, sets: [(22, 10, true)], to: second, context: context)
        // No completed set: this workout would render nowhere even once attributed, so
        // counting it would promise the user something attribution cannot deliver.
        let abandoned = makeSession(at: 12_000, in: context)
        addRow(named: "Biceps Curls", exerciseId: nil, sets: [(25, 10, false)], to: abandoned, context: context)
        try context.save()

        let snapshot = ExerciseProgressAggregator.buildSnapshot(
            sessions: try fetchSessions(context),
            liveExercises: try context.fetch(FetchDescriptor<Exercise>()),
            exerciseName: "Biceps Curls",
            exerciseId: barbell.id,
            startDate: .distantPast,
            recentSessionLimit: 8
        )

        let finding = try #require(snapshot.unattributedLegacy)
        #expect(finding.sessionCount == 2)
        #expect(finding.earliest == Date(timeIntervalSince1970: 1_000))
        #expect(finding.latest == Date(timeIntervalSince1970: 9_000))
        // Still dropped — being visible does not mean being counted.
        #expect(snapshot.data.dataPoints.isEmpty)
        #expect(snapshot.recentUsages.isEmpty)
    }

    @Test("A uniquely named exercise reports nothing, because its legacy rows already match")
    func uniqueNameReportsNothing() throws {
        let context = ModelContext(InMemoryModelContainer.make())
        let curls = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        context.insert(curls)

        let session = makeSession(at: 1_000, in: context)
        addRow(named: "Biceps Curls", exerciseId: nil, sets: [(20, 10, true)], to: session, context: context)
        try context.save()

        let snapshot = ExerciseProgressAggregator.buildSnapshot(
            sessions: try fetchSessions(context),
            liveExercises: try context.fetch(FetchDescriptor<Exercise>()),
            exerciseName: "Biceps Curls",
            exerciseId: curls.id,
            startDate: .distantPast,
            recentSessionLimit: 8
        )

        #expect(snapshot.unattributedLegacy == nil)
        // The name fallback carried it, which is why there is nothing to report.
        #expect(snapshot.data.dataPoints.count == 1)
    }

    // MARK: - Attribution

    @Test("Attribution links the rows and leaves the denormalised snapshot untouched")
    func attributionOnlyWritesTheLink() async throws {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        let barbell = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        let dumbbell = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(barbell)
        context.insert(dumbbell)

        let legacy = makeSession(at: 1_000, in: context)
        let legacyRow = addRow(
            named: "biceps curls",  // recorded with different casing than the library entry
            exerciseId: nil,
            sets: [(20, 10, true)],
            to: legacy,
            context: context
        )
        legacyRow.muscleGroups = ["Arms"]
        let legacyRowId = legacyRow.id

        // Already resolved to the *other* variant: attribution may never move it.
        let tagged = makeSession(at: 5_000, in: context)
        let taggedRow = addRow(
            named: "Biceps Curls",
            exerciseId: dumbbell.id,
            sets: [(14, 12, true)],
            to: tagged,
            context: context
        )
        let taggedRowId = taggedRow.id

        // A different exercise's legacy row must stay legacy.
        let other = makeSession(at: 6_000, in: context)
        let otherRow = addRow(named: "Bench Press", exerciseId: nil, sets: [(80, 5, true)], to: other, context: context)
        let otherRowId = otherRow.id
        try context.save()

        let store = SwiftDataLegacyHistoryAttributionStore(modelContainer: container)
        let updated = try await store.attributeLegacyRows(named: "Biceps Curls", to: barbell.id)
        #expect(updated == 1)

        let rows = try ModelContext(container).fetch(FetchDescriptor<WorkoutExercise>())
        let resolved = try #require(rows.first { $0.id == legacyRowId })
        #expect(resolved.exerciseId == barbell.id)
        // The denormalised record of what was performed is deliberately not re-derived
        // from the live library — an old session must not change meaning.
        #expect(resolved.exerciseName == "biceps curls")
        #expect(resolved.muscleGroups == ["Arms"])
        #expect(resolved.loadBehaviorRaw == ExerciseLoadBehavior.resistance.rawValue)

        #expect(rows.first { $0.id == taggedRowId }?.exerciseId == dumbbell.id)
        #expect(rows.first { $0.id == otherRowId }?.exerciseId == nil)
    }

    @Test("Attributed workouts enter the chart, and the finding disappears")
    func attributedWorkoutsAppearInTheChart() async throws {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        let barbell = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        let dumbbell = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(barbell)
        context.insert(dumbbell)

        let first = makeSession(at: 1_000, in: context)
        addRow(named: "Biceps Curls", exerciseId: nil, sets: [(20, 10, true)], to: first, context: context)
        let second = makeSession(at: 9_000, in: context)
        addRow(named: "Biceps Curls", exerciseId: nil, sets: [(24, 10, true)], to: second, context: context)
        try context.save()

        let store = SwiftDataLegacyHistoryAttributionStore(modelContainer: container)
        #expect(try await store.attributeLegacyRows(named: "Biceps Curls", to: barbell.id) == 2)

        let readContext = ModelContext(container)
        let after = ExerciseProgressAggregator.buildSnapshot(
            sessions: try fetchSessions(readContext),
            liveExercises: try readContext.fetch(FetchDescriptor<Exercise>()),
            exerciseName: "Biceps Curls",
            exerciseId: barbell.id,
            startDate: .distantPast,
            recentSessionLimit: 8
        )

        #expect(after.unattributedLegacy == nil)
        #expect(after.data.dataPoints.count == 2)
        #expect(after.data.dataPoints.map(\.maxWeight) == [20, 24])
        #expect(after.recentUsages.count == 2)

        // The other variant's screen sees nothing: the rows now belong to the barbell.
        let otherVariant = ExerciseProgressAggregator.buildSnapshot(
            sessions: try fetchSessions(readContext),
            liveExercises: try readContext.fetch(FetchDescriptor<Exercise>()),
            exerciseName: "Biceps Curls",
            exerciseId: dumbbell.id,
            startDate: .distantPast,
            recentSessionLimit: 8
        )
        #expect(otherVariant.unattributedLegacy == nil)
        #expect(otherVariant.data.dataPoints.isEmpty)
    }

    @Test("Re-running attribution changes nothing")
    func attributionIsIdempotent() async throws {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        let barbell = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        let dumbbell = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(barbell)
        context.insert(dumbbell)
        let session = makeSession(at: 1_000, in: context)
        addRow(named: "Biceps Curls", exerciseId: nil, sets: [(20, 10, true)], to: session, context: context)
        try context.save()

        let store = SwiftDataLegacyHistoryAttributionStore(modelContainer: container)
        #expect(try await store.attributeLegacyRows(named: "Biceps Curls", to: barbell.id) == 1)
        // Now attributed, so a second run — including one naming the other variant —
        // finds nothing and cannot overwrite the user's choice.
        #expect(try await store.attributeLegacyRows(named: "Biceps Curls", to: dumbbell.id) == 0)

        let rows = try ModelContext(container).fetch(FetchDescriptor<WorkoutExercise>())
        #expect(rows.allSatisfy { $0.exerciseId == barbell.id })
    }

    @Test("A workout still in progress is not history, and is left alone")
    func inProgressWorkoutsAreNotAttributed() async throws {
        let container = InMemoryModelContainer.make()
        let context = ModelContext(container)
        let barbell = Exercise(name: "Biceps Curls", equipmentType: .barbell)
        let dumbbell = Exercise(name: "Biceps Curls", equipmentType: .dumbbell)
        context.insert(barbell)
        context.insert(dumbbell)

        let finished = makeSession(at: 1_000, in: context)
        // No completed set, so the banner never counts it — but it belongs to a finished
        // workout, and leaving it behind would keep that workout half-legacy.
        let abandonedRow = addRow(
            named: "Biceps Curls",
            exerciseId: nil,
            sets: [(20, 10, false)],
            to: finished,
            context: context
        )
        let abandonedRowId = abandonedRow.id

        let live = WorkoutSession(routine: nil)
        live.startTime = Date(timeIntervalSince1970: 20_000)
        live.endTime = nil
        context.insert(live)
        let liveRow = addRow(named: "Biceps Curls", exerciseId: nil, sets: [(20, 10, true)], to: live, context: context)
        let liveRowId = liveRow.id
        try context.save()

        let store = SwiftDataLegacyHistoryAttributionStore(modelContainer: container)
        #expect(try await store.attributeLegacyRows(named: "Biceps Curls", to: barbell.id) == 1)

        let rows = try ModelContext(container).fetch(FetchDescriptor<WorkoutExercise>())
        #expect(rows.first { $0.id == abandonedRowId }?.exerciseId == barbell.id)
        #expect(rows.first { $0.id == liveRowId }?.exerciseId == nil)
    }

    // MARK: - The screen

    @Test("The screen offers the resolution, then reloads without it once it is applied")
    func viewModelSurfacesAndResolvesTheFinding() async throws {
        let target = UUID()
        let provider = StubLegacyFindingProvider(
            finding: UnattributedLegacyHistory(
                sessionCount: 12,
                earliest: Date(timeIntervalSince1970: 1_700_000_000),
                latest: Date(timeIntervalSince1970: 1_730_000_000)
            )
        )
        let attribution = RecordingLegacyHistoryAttribution(rowsToReport: 14)
        let viewModel = ExerciseProgressViewModel(
            exerciseName: "Biceps Curls",
            exerciseId: target,
            provider: provider,
            legacyAttribution: attribution,
            proEntitlements: StubProEntitlements(),
            paywalls: RecordingPaywallPresenter(),
            isGatingEnabled: false
        )

        await loadUntilSettled(viewModel)
        #expect(viewModel.canAttributeLegacyHistory)
        // Composed in `load()`, never in a view body: the count and the period are already
        // in the string by the time the banner reads it.
        //
        // Both are asserted because the copy leads with the **period** while the count is
        // still argument 1 — the format string reorders them (`%2$@` … `%1$d`), and a
        // positional specifier that silently failed to reorder would drop or transpose one
        // of them rather than throw.
        let message = try #require(viewModel.unattributedLegacyMessage)
        #expect(message.contains("12"))
        let period = UnattributedLegacyHistory(
            sessionCount: 12,
            earliest: Date(timeIntervalSince1970: 1_700_000_000),
            latest: Date(timeIntervalSince1970: 1_730_000_000)
        ).periodText
        #expect(message.contains(period))

        await provider.stopReportingTheFinding()
        await viewModel.attributeLegacyHistory()

        #expect(attribution.calls.count == 1)
        #expect(attribution.calls.first?.name == "Biceps Curls")
        #expect(attribution.calls.first?.exerciseId == target)
        // Reloaded, so the banner is gone rather than merely hidden.
        #expect(viewModel.unattributedLegacy == nil)
        #expect(viewModel.unattributedLegacyMessage == nil)
        #expect(viewModel.canAttributeLegacyHistory == false)
    }

    @Test("A failed write keeps the banner, so the user can retry")
    func failedAttributionKeepsTheBanner() async throws {
        let provider = StubLegacyFindingProvider(
            finding: UnattributedLegacyHistory(
                sessionCount: 3,
                earliest: Date(timeIntervalSince1970: 1_700_000_000),
                latest: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        let viewModel = ExerciseProgressViewModel(
            exerciseName: "Biceps Curls",
            exerciseId: UUID(),
            provider: provider,
            legacyAttribution: RecordingLegacyHistoryAttribution(rowsToReport: nil),
            proEntitlements: StubProEntitlements(),
            paywalls: RecordingPaywallPresenter(),
            isGatingEnabled: false
        )

        await loadUntilSettled(viewModel)
        await viewModel.attributeLegacyHistory()

        #expect(viewModel.canAttributeLegacyHistory)
        #expect(viewModel.isAttributingLegacyHistory == false)
    }

    // MARK: - Fixtures

    private func fetchSessions(_ context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(
            FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endTime != nil })
        )
    }

    private func makeSession(at timestamp: TimeInterval, in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(routine: nil)
        session.startTime = Date(timeIntervalSince1970: timestamp)
        session.endTime = Date(timeIntervalSince1970: timestamp + 600)
        context.insert(session)
        return session
    }

    @discardableResult
    private func addRow(
        named name: String,
        exerciseId: UUID?,
        sets: [(Double, Int, Bool)],
        to session: WorkoutSession,
        context: ModelContext
    ) -> WorkoutExercise {
        let row = WorkoutExercise(
            exerciseName: name,
            muscleGroups: ["Arms"],
            order: 0,
            exerciseId: exerciseId,
            routineExerciseId: nil,
            loadBehavior: .resistance
        )
        row.workoutSession = session
        context.insert(row)
        for (index, entry) in sets.enumerated() {
            let set = WorkoutSet(
                plannedReps: entry.1,
                actualReps: entry.1,
                plannedWeight: entry.0,
                actualWeight: entry.0,
                restTime: 60,
                order: index
            )
            set.isCompleted = entry.2
            set.workoutExercise = row
            context.insert(set)
        }
        return row
    }
}

/// Returns one exercise-progress snapshot whose only interesting field is the legacy
/// finding. Everything else is empty on purpose: what is under test is that the screen
/// surfaces the finding and stops surfacing it once the write has happened.
private actor StubLegacyFindingProvider: HistorySnapshotProviding {
    struct Unused: Error {}

    private var finding: UnattributedLegacyHistory?

    init(finding: UnattributedLegacyHistory) {
        self.finding = finding
    }

    /// Stands in for the write having landed — the next fetch sees resolved rows.
    func stopReportingTheFinding() {
        finding = nil
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
        ExerciseProgressSnapshot(
            data: ExerciseProgressData(
                exerciseName: exerciseName,
                dataPoints: [],
                loadBehavior: .resistance,
                usesEffectiveLoad: false
            ),
            recentUsages: [],
            availableUsages: [],
            selectedUsage: .combined,
            unattributedLegacy: finding
        )
    }

    func fetchPreviousPerformances(
        _ lookup: PreviousPerformanceLookup
    ) async throws -> [UUID: PreviousExercisePerformance] { [:] }
}
