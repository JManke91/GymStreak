//
//  AICoachCache.swift
//  GymStreak
//
//  Disk-backed JSON cache for AI Coach generated outputs.
//  Stored in Application Support/AICoachCache/ — outside SwiftData to avoid
//  polluting the data model with ephemeral AI content.
//

import Foundation
import os

/// Disk-backed cache for AI Coach narrative outputs.
///
/// Three independent namespaces, each with typed load/save/invalidate APIs:
/// - **Post-workout recap**: keyed by `workoutId`.
/// - **Period recap**: keyed by `"\(range)|\(rangeStartISO)|\(lastWorkoutISO)"`.
/// - **Exercise deep-dive**: keyed by `"\(exerciseId)|\(lastSetTimestampISO)"`.
///
/// Files are written as JSON via `Codable`. Reads are synchronous; writes are
/// performed via `try?` so cache failures never surface to the user.
@MainActor
final class AICoachCache: AICoachCaching {

    // MARK: - Singleton

    static let shared = AICoachCache()

    // MARK: - Private state

    private let fm = FileManager.default
    private let root: URL
    private let logger = Logger(subsystem: "app.gymstreak.aicoach", category: "Cache")

    private init() {
        let support = try! fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.root = support.appending(path: "AICoachCache", directoryHint: .isDirectory)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: - Post-Workout Recap

    func loadPostWorkout(workoutId: UUID) -> PostWorkoutRecapOutput? {
        load(PostWorkoutRecapOutput.self, from: postWorkoutURL(workoutId))
    }

    func savePostWorkout(workoutId: UUID, output: PostWorkoutRecapOutput) {
        save(output, to: postWorkoutURL(workoutId))
    }

    func invalidatePostWorkout(workoutId: UUID) {
        remove(at: postWorkoutURL(workoutId))
    }

    // MARK: - Period Recap

    func loadPeriodRecap(key: String) -> PeriodRecapOutput? {
        load(PeriodRecapOutput.self, from: periodRecapURL(key))
    }

    func savePeriodRecap(key: String, output: PeriodRecapOutput) {
        save(output, to: periodRecapURL(key))
    }

    func invalidatePeriodRecap(key: String) {
        remove(at: periodRecapURL(key))
    }

    // MARK: - Exercise Deep-Dive

    func loadExerciseDeepDive(key: String) -> ExerciseDeepDiveOutput? {
        load(ExerciseDeepDiveOutput.self, from: exerciseDeepDiveURL(key))
    }

    func saveExerciseDeepDive(key: String, output: ExerciseDeepDiveOutput) {
        save(output, to: exerciseDeepDiveURL(key))
    }

    func invalidateExerciseDeepDive(key: String) {
        remove(at: exerciseDeepDiveURL(key))
    }

    // MARK: - Workout Analysis

    func loadWorkoutAnalysis(workoutId: UUID) -> WorkoutAnalysisOutput? {
        load(WorkoutAnalysisOutput.self, from: workoutAnalysisURL(workoutId))
    }

    func saveWorkoutAnalysis(workoutId: UUID, output: WorkoutAnalysisOutput) {
        save(output, to: workoutAnalysisURL(workoutId))
    }

    func invalidateWorkoutAnalysis(workoutId: UUID) {
        remove(at: workoutAnalysisURL(workoutId))
    }

    // MARK: - URL Helpers

    private func postWorkoutURL(_ id: UUID) -> URL {
        root.appending(path: "post_workout_\(id.uuidString).json", directoryHint: .notDirectory)
    }

    private func periodRecapURL(_ key: String) -> URL {
        let safe = key.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-_")).inverted).joined(separator: "_")
        // v2: fact-based content redesign (July 2026) — filename bump orphans
        // pre-redesign entries so they regenerate.
        return root.appending(path: "period_recap_v2_\(safe).json", directoryHint: .notDirectory)
    }

    private func exerciseDeepDiveURL(_ key: String) -> URL {
        let safe = key.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-_")).inverted).joined(separator: "_")
        return root.appending(path: "exercise_deep_dive_\(safe).json", directoryHint: .notDirectory)
    }

    private func workoutAnalysisURL(_ id: UUID) -> URL {
        // Version suffix: bumped whenever the content design changes so
        // pre-redesign cache entries are orphaned and regenerate.
        // v2: fact-based instead of volume-based. v3: first-time exercises
        // excluded from PRs/highlights, German glossary.
        root.appending(path: "workout_analysis_v3_\(id.uuidString).json", directoryHint: .notDirectory)
    }

    // MARK: - Generic IO

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            logger.error("Cache decode failed at \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Cache write failed at \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func remove(at url: URL) {
        try? fm.removeItem(at: url)
    }
}
