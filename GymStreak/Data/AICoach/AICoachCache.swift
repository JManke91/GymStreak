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

    /// The correlation field is sanitised on the way out, not only when generated.
    /// Recaps written before that guard existed can hold a literal `nil` — the string the
    /// model produced when its `@Guide` said "return nil" — and a cache entry is never
    /// regenerated just because its prose is stale. The persisted format is this layer's
    /// concern, so every reader of `AICoachCaching.loadPeriodRecap` inherits the guard
    /// rather than having to remember it. See docs/ai-coach.md § "Prompt grounding rules".
    func loadPeriodRecap(key: String) -> PeriodRecapOutput? {
        guard let stored = load(PeriodRecapOutput.self, from: periodRecapURL(key)) else { return nil }
        return PeriodRecapOutput(
            headline: stored.headline,
            trendsNarrative: stored.trendsNarrative,
            correlationHighlight: CoachCorrelationSanitizer.sanitized(stored.correlationHighlight),
            closingSentence: stored.closingSentence
        )
    }

    func savePeriodRecap(key: String, output: PeriodRecapOutput) {
        save(output, to: periodRecapURL(key))
    }

    func invalidatePeriodRecap(key: String) {
        remove(at: periodRecapURL(key))
    }

    // MARK: - Exercise Deep-Dive

    func loadExerciseDeepDive(key: String) -> ExerciseDeepDiveNarrative? {
        load(ExerciseDeepDiveNarrative.self, from: exerciseDeepDiveURL(key))
    }

    func saveExerciseDeepDive(key: String, narrative: ExerciseDeepDiveNarrative) {
        save(narrative, to: exerciseDeepDiveURL(key))
    }

    func invalidateExerciseDeepDive(key: String) {
        remove(at: exerciseDeepDiveURL(key))
    }

    // MARK: - Workout Analysis

    /// Uniqued on read, the same arrangement as `loadPeriodRecap`'s sanitizer: the
    /// persisted format is the Data layer's concern, and an analysis written before
    /// `CoachHighlightUniquer` existed still holds the duplicate highlights a device check
    /// found. A cache entry is never regenerated just because its prose is stale.
    func loadWorkoutAnalysis(workoutId: UUID) -> WorkoutAnalysisNarrative? {
        guard let stored = load(WorkoutAnalysisNarrative.self, from: workoutAnalysisURL(workoutId)) else {
            return nil
        }
        return CoachHighlightUniquer.uniqued(stored)
    }

    func saveWorkoutAnalysis(workoutId: UUID, narrative: WorkoutAnalysisNarrative) {
        save(narrative, to: workoutAnalysisURL(workoutId))
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
        // v2 (2026-08-28): one `narrative` string became per-paragraph fields plus the
        // Swift-composed peak sentence (`ExerciseDeepDiveNarrative`). The prefix is bumped
        // **deliberately** rather than letting the decode fail: a decode failure is a
        // silent cache miss, and for a free user a miss spends a monthly allowance unit
        // (`docs/pro-subscription.md` §5e). Bumping makes the one-off regeneration an
        // intended, documented cost instead of an accident, and orphans the stale files
        // under a name that says which format they hold.
        return root.appending(path: "exercise_deep_dive_v2_\(safe).json", directoryHint: .notDirectory)
    }

    private func workoutAnalysisURL(_ id: UUID) -> URL {
        // Version suffix: bumped whenever the content design changes so
        // pre-redesign cache entries are orphaned and regenerate.
        // v2: fact-based instead of volume-based. v3: first-time exercises
        // excluded from PRs/highlights, German glossary. v4 (2026-08-29): the headline
        // is composed in Swift rather than generated (`WorkoutAnalysisNarrative`) — the
        // prefix is bumped rather than letting the old JSON decode, because a v3 file
        // decodes cleanly into the new type and would keep serving the generated
        // headline this fix exists to remove.
        root.appending(path: "workout_analysis_v4_\(id.uuidString).json", directoryHint: .notDirectory)
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
