//
//  MuscleLoadAggregator.swift
//  GymStreak
//

import Foundation

/// Turns a completed workout into the trained-muscle picture the muscle map renders.
///
/// Pure and synchronous: it reads the denormalized `WorkoutExercise.muscleGroups` already stored
/// on history — no schema change, no live `Exercise` lookup — and returns value types. One
/// traversal of the session graph produces every region's level, set count and exercise list.
struct MuscleLoadAggregator {

    /// - Parameter session: a workout session; its exercises are visited in `order`.
    /// - Returns: one entry per trained region. Regions absent from the result were not trained,
    ///   and a session that maps to nothing (only `General`, or no completed work) returns empty.
    static func aggregate(session: WorkoutSession) -> [MuscleMapRegion: MuscleLoad] {
        var engagements: [MuscleMapRegion: MuscleEngagement] = [:]
        var completedSets: [MuscleMapRegion: Int] = [:]
        var exerciseNames: [MuscleMapRegion: [String]] = [:]

        let exercises = session.workoutExercisesList.sorted { $0.order < $1.order }
        for exercise in exercises {
            // History shows work actually performed: an exercise nobody completed a set of was
            // not trained, so it contributes neither a highlight nor a name.
            let completed = exercise.setsList.count(where: \.isCompleted)
            guard completed > 0 else { continue }

            for (region, engagement) in Self.engagements(of: exercise) {
                if engagement == .primary {
                    // Primary wins: a region that leads anywhere in the session renders primary.
                    engagements[region] = .primary
                    completedSets[region, default: 0] += completed
                } else if engagements[region] == nil {
                    engagements[region] = .secondary
                }
                if exerciseNames[region]?.contains(exercise.exerciseName) != true {
                    exerciseNames[region, default: []].append(exercise.exerciseName)
                }
            }
        }

        return engagements.reduce(into: [:]) { result, entry in
            let (region, engagement) = entry
            result[region] = MuscleLoad(
                engagement: engagement,
                completedSets: completedSets[region] ?? 0,
                exerciseNames: exerciseNames[region] ?? []
            )
        }
    }

    /// One exercise's regions. The first muscle group is the primary mover and every later one is
    /// secondary — the same reading of `muscleGroups` the primary-muscle badge and Fortschritt
    /// grouping already use. Keys can collapse onto the same region (Shoulders + Rear Delts), so
    /// primary wins here too and the region is counted once.
    ///
    /// Primary is the first *mapped* key rather than index 0: an exercise led by a key the figure
    /// has no belly for would otherwise drop its completed sets from every region it does hit.
    private static func engagements(of exercise: WorkoutExercise) -> [MuscleMapRegion: MuscleEngagement] {
        var engagements: [MuscleMapRegion: MuscleEngagement] = [:]
        var hasPrimary = false
        for key in exercise.muscleGroups {
            guard let region = MuscleMapRegion(muscleGroupKey: key) else { continue }
            guard engagements[region] != .primary else { continue }
            engagements[region] = hasPrimary ? .secondary : .primary
            hasPrimary = true
        }
        return engagements
    }
}
