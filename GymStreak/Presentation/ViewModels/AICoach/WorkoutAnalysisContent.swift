//
//  WorkoutAnalysisContent.swift
//  GymStreak
//
//  The UI-ready shape of a (partially) generated workout analysis, mapped out of
//  `WorkoutAnalysisOutput` and its streaming snapshots so no FoundationModels type reaches
//  the view layer. Split out of `WorkoutAnalysisViewModel.swift`, which is the orchestrator.
//

import Foundation
import FoundationModels

// MARK: - Display content

/// UI-ready representation of a (partially) generated workout analysis.
/// Mapped from `WorkoutAnalysisOutput` / its `PartiallyGenerated` snapshots
/// so the view never touches FoundationModels types.
///
/// `headline` never comes from those snapshots — it is composed by
/// `WorkoutAnalysisInput.headlineSentence` and handed in, so it is on screen from the
/// first frame of the stream instead of arriving as the model's first tokens.
struct WorkoutAnalysisContent: Equatable {
    struct Highlight: Equatable, Identifiable {
        let id: Int
        var exerciseName: String
        var trend: WorkoutAnalysisTrend?
        var detail: String
    }

    var headline: String = ""
    var highlights: [Highlight] = []
    var closingObservation: String = ""

    var isEmpty: Bool {
        headline.isEmpty && highlights.isEmpty && closingObservation.isEmpty
    }

    init(headline: String = "", highlights: [Highlight] = [], closingObservation: String = "") {
        self.headline = headline
        self.highlights = highlights
        self.closingObservation = closingObservation
    }

    /// A cached analysis, headline included — the cache is the only place the composed
    /// headline survives between visits.
    ///
    /// `AICoachCache.loadWorkoutAnalysis` has already uniqued what it hands over; the pass
    /// here is the same guard one boundary later, so a narrative arriving from anywhere
    /// else inherits it too — the arrangement `CoachCorrelationSanitizer` has.
    init(narrative: WorkoutAnalysisNarrative) {
        headline = narrative.headline
        highlights = CoachHighlightUniquer.uniqued(
            narrative.exerciseHighlights.enumerated().map { index, item in
                Highlight(
                    id: index,
                    exerciseName: item.exerciseName,
                    trend: item.trend,
                    detail: item.detail
                )
            },
            exerciseName: \.exerciseName
        )
        closingObservation = narrative.closingObservation
    }

    init(partial: WorkoutAnalysisOutput.PartiallyGenerated, headline: String) {
        self.headline = headline
        highlights = CoachHighlightUniquer.uniqued(
            (partial.exerciseHighlights ?? []).enumerated().map { index, item in
                Highlight(
                    id: index,
                    exerciseName: item.exerciseName ?? "",
                    trend: item.trend,
                    detail: item.detail ?? ""
                )
            },
            exerciseName: \.exerciseName
        )
        closingObservation = partial.closingObservation ?? ""
    }

    /// Converts to the cacheable narrative.
    func toNarrative() -> WorkoutAnalysisNarrative {
        WorkoutAnalysisNarrative(
            headline: headline,
            exerciseHighlights: highlights.map {
                WorkoutAnalysisHighlight(
                    exerciseName: $0.exerciseName,
                    trend: $0.trend ?? .unchanged,
                    detail: $0.detail
                )
            },
            closingObservation: closingObservation
        )
    }
}
