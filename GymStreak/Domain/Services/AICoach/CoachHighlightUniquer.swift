//
//  CoachHighlightUniquer.swift
//  GymStreak
//
//  Keeps a workout analysis to one highlight per exercise, whatever the model returned.
//  See docs/ai-coach.md § "4. Workout Analysis" and § "Prompt grounding rules", rule 4.
//

import Foundation

/// One highlight per exercise, first occurrence wins, order otherwise untouched.
///
/// The prompt asks for "the 1-4 most notable exercises" and `WorkoutAnalysisOutput`'s
/// `@Guide` bounds the array at 1…4, but neither makes the entries *distinct*: a device
/// check returned four highlights, all `Arnold Press`, three of them restating the same
/// top-set change (German, 2026-08-30). The count bound was satisfied by four rows about
/// one exercise. A prompt rule alone has already failed on this surface — the generated
/// headline that named an exercise the session did not contain — so the guarantee is here,
/// where it does not depend on the model obeying anything, and the `@Guide` carries the
/// same rule as the request half.
///
/// **Isolation-agnostic on purpose**, the same shape and the same reasoning as
/// `CoachCorrelationSanitizer`: pure logic over model output with no state, applied at
/// every boundary the output crosses rather than at one of them —
/// `AICoachCache.loadWorkoutAnalysis` (an analysis cached before this existed still holds
/// its duplicates, and a cache entry is never regenerated just because its prose is stale)
/// and both of `WorkoutAnalysisContent`'s mapping inits, which is where the *streaming*
/// snapshots arrive and never reach the cache path at all.
enum CoachHighlightUniquer {

    /// The generic form, for the display type the streaming snapshots are mapped into.
    ///
    /// Matching is on the trimmed, case-folded name because the name is the model's copy of
    /// the input's, not the input's own string. **An empty name is never a duplicate**: a
    /// streaming highlight exists before its name has finished arriving, and folding those
    /// together would collapse the rows the reader is watching fill in. A name that has
    /// arrived only as a *prefix* is likewise kept, and is dropped on the snapshot that
    /// completes it — accepted, and bounded at four rows.
    static func uniqued<Highlight>(
        _ highlights: [Highlight],
        exerciseName: (Highlight) -> String
    ) -> [Highlight] {
        var seen: Set<String> = []
        return highlights.filter { highlight in
            let key = exerciseName(highlight)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !key.isEmpty else { return true }
            return seen.insert(key).inserted
        }
    }

    /// The finished narrative, as the cache stores and returns it.
    static func uniqued(_ narrative: WorkoutAnalysisNarrative) -> WorkoutAnalysisNarrative {
        var uniqued = narrative
        uniqued.exerciseHighlights = self.uniqued(narrative.exerciseHighlights, exerciseName: \.exerciseName)
        return uniqued
    }
}
