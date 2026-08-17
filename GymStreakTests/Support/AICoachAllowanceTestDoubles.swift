//
//  AICoachAllowanceTestDoubles.swift
//  GymStreakTests
//
//  Doubles shared by the P4/P5 taster suites (tickets 08–09): a spying
//  allowance store, fakes for the three injected AI-coach protocols, and the
//  completed-workout history both aggregators read.
//  `ProGatingTestDoubles.swift` holds the entitlement/paywall/availability
//  stubs every Pro gate ticket shares.
//

import Foundation
import SwiftData
import FoundationModels
@testable import GymStreak


/// Counts what the ViewModels charge, on top of holding the counts. The
/// `consumeCount` is what proves a *refunded* generation still went through the
/// meter — a plain count of zero cannot tell "refunded" from "never charged".
@MainActor
final class SpyAllowanceStore: MonthlyAllowanceTracking {

    private(set) var consumeCount = 0
    private(set) var refundCount = 0
    private var counts: [MeteredAISurface: Int] = [:]

    func consumedCount(for surface: MeteredAISurface) -> Int {
        counts[surface] ?? 0
    }

    func count(for surface: MeteredAISurface) -> Int {
        consumedCount(for: surface)
    }

    func consume(_ surface: MeteredAISurface) {
        consumeCount += 1
        counts[surface] = consumedCount(for: surface) + 1
    }

    func refund(_ surface: MeteredAISurface) {
        refundCount += 1
        counts[surface] = max(0, consumedCount(for: surface) - 1)
    }

    /// Keeps the counts but forgets the calls, so a test can set up an
    /// exhausted allowance and then assert only on what the step under test
    /// charged.
    func resetCallCounts() {
        consumeCount = 0
        refundCount = 0
    }
}

/// An `AICoachServicing` that never reaches a model: every stream returns `nil`,
/// which is the production "surface disabled or device not eligible" answer and
/// the only generation outcome a test process can produce —
/// `LanguageModelSession.ResponseStream` cannot be constructed without the
/// on-device model.
@MainActor
final class FakeAICoachService: AICoachServicing {

    /// Kept for symmetry with the real service's two nil-returning reasons; the
    /// tests set it to say out loud which one they are exercising.
    var isUnavailable = false
    private(set) var prewarmCount = 0

    func streamPostWorkoutRecap(
        input: PostWorkoutRecapInput
    ) async throws -> LanguageModelSession.ResponseStream<PostWorkoutRecapOutput>? { nil }

    func streamPeriodRecap(
        buildInput: () -> PeriodRecapInput,
        buildCompactInput: () -> PeriodRecapInput
    ) async throws -> LanguageModelSession.ResponseStream<PeriodRecapOutput>? { nil }

    func streamExerciseDeepDive(
        input: ExerciseDeepDiveInput
    ) async throws -> LanguageModelSession.ResponseStream<ExerciseDeepDiveOutput>? { nil }

    func streamWorkoutAnalysis(
        input: WorkoutAnalysisInput
    ) async throws -> LanguageModelSession.ResponseStream<WorkoutAnalysisOutput>? { nil }

    func prewarm() { prewarmCount += 1 }
}

/// An in-memory `AICoachCaching`. The period-recap namespace answers *any* key
/// with the same output on purpose: the recap's cache key is built from private
/// aggregation, and what these tests assert is that a cache hit is free — not
/// how the key is spelled.
@MainActor
final class FakeAICoachCache: AICoachCaching {

    var periodRecap: PeriodRecapOutput?
    var deepDives: [String: ExerciseDeepDiveOutput] = [:]
    private(set) var invalidatedDeepDiveKeys: [String] = []

    func loadPostWorkout(workoutId: UUID) -> PostWorkoutRecapOutput? { nil }
    func savePostWorkout(workoutId: UUID, output: PostWorkoutRecapOutput) {}
    func invalidatePostWorkout(workoutId: UUID) {}

    func loadPeriodRecap(key: String) -> PeriodRecapOutput? { periodRecap }
    func savePeriodRecap(key: String, output: PeriodRecapOutput) { periodRecap = output }
    func invalidatePeriodRecap(key: String) { periodRecap = nil }

    func loadExerciseDeepDive(key: String) -> ExerciseDeepDiveOutput? { deepDives[key] }
    func saveExerciseDeepDive(key: String, output: ExerciseDeepDiveOutput) { deepDives[key] = output }
    func invalidateExerciseDeepDive(key: String) {
        invalidatedDeepDiveKeys.append(key)
        deepDives[key] = nil
    }

    func loadWorkoutAnalysis(workoutId: UUID) -> WorkoutAnalysisOutput? { nil }
    func saveWorkoutAnalysis(workoutId: UUID, output: WorkoutAnalysisOutput) {}
    func invalidateWorkoutAnalysis(workoutId: UUID) {}
}

/// Every AI surface on. The preference gate is a different feature from the
/// entitlement gate, and these tests are about the second one.
@MainActor
final class FakeAICoachPreferences: AICoachPreferencesProviding {
    var isPeriodRecapEffectivelyEnabled = true
    var isProactiveMonthlyEffectivelyEnabled = true
    var lastProactivePromptShownForPeriodId: String?
    var isExerciseDeepDiveEffectivelyEnabled = true
    var isPostWorkoutEffectivelyEnabled = true
    var isWorkoutDetailEffectivelyEnabled = true
}

/// An `AllowanceCloudStore` that forgets everything — the gate-level tests here
/// assert on the gate, and `CoachChatAllowanceTests` already covers the KVS
/// mirror. Writing the real `NSUbiquitousKeyValueStore` would stamp the
/// developer's simulator permanently.
final class NoopAllowanceCloudStore: AllowanceCloudStore, @unchecked Sendable {

    /// Main-actor-only access in practice; boxed because `AllowanceCloudStore`
    /// is `Sendable` by protocol.
    private var records: [String: MonthlyAllowanceRecord] = [:]

    func record(forKey key: String) -> MonthlyAllowanceRecord? { records[key] }
    func setRecord(_ record: MonthlyAllowanceRecord, forKey key: String) { records[key] = record }
}

// MARK: - History fixture

/// Seeds the completed-workout history the two aggregators read. Kept in one
/// place because the deep-dive needs sets on one exercise and the recap needs a
/// session count, and both walk the same object graph.
@MainActor
enum AICoachHistoryFixture {

    /// One exercise with `completedSets` completed sets, spread over two
    /// sessions so the deep-dive aggregator sees a progression.
    @discardableResult
    static func seedExercise(context: ModelContext, completedSets: Int) -> Exercise {
        let exercise = Exercise(name: "Bench Press", muscleGroups: ["Chest"])
        context.insert(exercise)

        let perSession = max(1, completedSets / 2)
        var remaining = completedSets
        var offsetDays = 14
        while remaining > 0 {
            let count = min(perSession, remaining)
            seedSession(
                context: context,
                exercise: exercise,
                setCount: count,
                start: Date().addingTimeInterval(-Double(offsetDays) * 86_400),
                weight: 60 + Double(offsetDays)
            )
            remaining -= count
            offsetDays -= 7
            if offsetDays < 0 { offsetDays = 0 }
        }

        try? context.save()
        return exercise
    }

    /// `count` completed sessions on distinct days, each with real sets — the
    /// period-recap aggregator narrates only from three sessions up.
    static func seedSessions(context: ModelContext, count: Int) {
        let exercise = Exercise(name: "Squat", muscleGroups: ["Legs"])
        context.insert(exercise)
        for index in 0..<count {
            seedSession(
                context: context,
                exercise: exercise,
                setCount: 3,
                start: Date().addingTimeInterval(-Double(index + 1) * 86_400),
                weight: 80 + Double(index)
            )
        }
        try? context.save()
    }

    private static func seedSession(
        context: ModelContext,
        exercise: Exercise,
        setCount: Int,
        start: Date,
        weight: Double
    ) {
        let routine = Routine(name: "Test Routine")
        context.insert(routine)
        let session = WorkoutSession(routine: routine)
        session.routineName = routine.name
        session.startTime = start
        session.endTime = start.addingTimeInterval(3_600)
        context.insert(session)

        let workoutExercise = WorkoutExercise(
            exerciseName: exercise.name,
            muscleGroups: exercise.muscleGroups,
            order: 0,
            exerciseId: exercise.id
        )
        context.insert(workoutExercise)
        workoutExercise.workoutSession = session

        for index in 0..<setCount {
            let set = WorkoutSet(
                plannedReps: 8,
                actualReps: 8,
                plannedWeight: weight,
                actualWeight: weight,
                restTime: 90,
                order: index
            )
            set.isCompleted = true
            context.insert(set)
            set.workoutExercise = workoutExercise
        }
    }
}
