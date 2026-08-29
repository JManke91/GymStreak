//
//  WorkoutAnalysisNarrative.swift
//  GymStreak
//

import Foundation

/// One workout analysis as the screen renders it and the cache stores it: the highlights
/// and closing sentence the model wrote, plus the headline Swift composed.
///
/// **`headline` is not generated, and the model never has authority over it.** It used to
/// be a generated field, and a device check returned *"Neuer Bestwert bei Bankdrücken: 16
/// kg x 7 Wiederholungen"* for a session in which Bankdrücken was not trained: the figures
/// were Dip's real PR, the name came from a worked example in the instructions.
/// `WorkoutAnalysisInput.headlineSentence` composes the finished sentence instead, and this
/// type carries it through the cache so a re-read shows it without re-aggregating the
/// session — the same split as `ExerciseDeepDiveNarrative` and its peak sentence.
struct WorkoutAnalysisNarrative: Codable, Equatable, Sendable {

    /// The session's story, composed in Swift. Never generated, never streamed.
    var headline: String
    /// The 1–4 exercises the model picked out, in its own order.
    var exerciseHighlights: [WorkoutAnalysisHighlight]
    /// One closing observation about the session as a whole.
    var closingObservation: String

    init(
        headline: String = "",
        exerciseHighlights: [WorkoutAnalysisHighlight] = [],
        closingObservation: String = ""
    ) {
        self.headline = headline
        self.exerciseHighlights = exerciseHighlights
        self.closingObservation = closingObservation
    }
}
