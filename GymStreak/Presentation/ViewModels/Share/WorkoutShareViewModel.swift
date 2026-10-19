//
//  WorkoutShareViewModel.swift
//  GymStreak
//
//  Sharing a just-finished workout as an image: the card's data, the preview sheet's layer
//  toggles and the render. See docs/workout-sharing.md.
//

import Observation
import SwiftUI

@Observable
@MainActor
final class WorkoutShareViewModel {

    /// The card as it renders now. Nil until a workout with completed work is prepared, and
    /// nil is what hides the entry row.
    private(set) var card: WorkoutShareCardModel?

    /// The entry row's second line, which counts the new PRs once they are known.
    private(set) var entrySubtitle = "share.entry.subtitle".localized

    /// The preview sheet's chips. Every change rebuilds the card.
    var layers = WorkoutShareLayers() {
        didSet { rebuildCard() }
    }

    /// The line that travels with the image: the wordmark and the attributable App Store link.
    let shareMessage = "share.message".localized(
        AppBrand.wordmark,
        SupportLinks.appStoreCampaignLink(campaign: SupportLinks.Campaign.shareSummary).absoluteString
    )

    @ObservationIgnored private let personalBests: PersonalBestsProviding
    @ObservationIgnored private var source: WorkoutShareSource?
    @ObservationIgnored private var weightUnit: WeightUnit = .kilograms

    init(personalBests: PersonalBestsProviding) {
        self.personalBests = personalBests
    }

    /// Reads the session once, then checks it against history for new PRs.
    ///
    /// Everything read from `session` is read before the `await`: the completion screen's
    /// workout is not saved yet and can be discarded while the history walk runs. Nothing here
    /// writes to it, so sharing never commits or alters the workout.
    func prepare(session: WorkoutSession, weightUnit: WeightUnit) async {
        let sessionBests = PersonalRecordService.sessionBests(of: session)
        let source = Self.source(from: session, sessionBests: sessionBests)
        guard source.completedSets > 0 else { return }
        // Projected to values now: the models may be deleted by the time the await returns.
        let exercises = session.workoutExercisesList.sorted { $0.order < $1.order }.map {
            (id: $0.id, name: $0.exerciseName,
             region: $0.muscleGroups.first.flatMap(MuscleMapRegion.init(muscleGroupKey:)))
        }
        let startTime = session.startTime
        let sessionID = session.id

        self.weightUnit = weightUnit
        self.source = source
        // The design turns the exercise line on for a one-exercise workout only.
        layers.exercises = source.exerciseNames.count == 1

        guard let priorBests = try? await personalBests.fetchPersonalBests(
            before: startTime,
            excludingSessionID: sessionID
        ) else { return }
        let winners = PersonalRecordService.records(from: sessionBests, priorBests: priorBests)
        let records = exercises.compactMap { exercise -> WorkoutShareSource.Record? in
            guard let detail = winners[exercise.id] else { return nil }
            return WorkoutShareSource.Record(
                exerciseName: exercise.name,
                region: exercise.region,
                weightKg: detail.weight,
                reps: detail.reps
            )
        }
        self.source?.records = records
        entrySubtitle = switch records.count {
        case 0: "share.entry.subtitle".localized
        case 1: "share.entry.subtitle_pr_one".localized
        default: "share.entry.subtitle_prs".localized(records.count)
        }
        rebuildCard()
    }

    /// The card at its full 1080 × 1920 pixels, always in dark mode. Called from the Share
    /// button, never from a body.
    func renderImage() -> UIImage? {
        guard let card else { return nil }
        let renderer = ImageRenderer(
            content: WorkoutShareCardView(model: card).environment(\.colorScheme, .dark)
        )
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }

    // MARK: - Private

    private func rebuildCard() {
        guard let source else { return }
        card = WorkoutShareCardModel.make(from: source, layers: layers, weightUnit: weightUnit)
    }

    /// One bounded walk of the session's own exercises — the same reads the completion
    /// screen's summary already makes.
    private static func source(
        from session: WorkoutSession,
        sessionBests: [String: PersonalRecordService.PRDetail]
    ) -> WorkoutShareSource {
        let aggregates = session.aggregates
        let performed = session.workoutExercisesList
            .sorted { $0.order < $1.order }
            .filter { $0.setsList.contains(where: \.isCompleted) }
        let topSet = performed.count == 1
            ? sessionBests[performed[0].stableKey]
                .map { WorkoutShareSource.TopSet(weightKg: $0.weight, reps: $0.reps) }
            : nil
        return WorkoutShareSource(
            title: session.routineName,
            date: session.startTime,
            duration: session.duration,
            completedSets: aggregates.completedSets,
            volumeKg: aggregates.volume,
            exerciseNames: performed.map(\.exerciseName),
            loads: MuscleLoadAggregator.aggregate(session: session),
            topSet: topSet
        )
    }
}
