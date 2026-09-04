//
//  MuscleLoadAggregator.swift
//  GymStreak
//

import Foundation

/// Turns a recorded workout — or a routine that has yet to be trained — into the muscle picture
/// the muscle map renders.
///
/// Pure and synchronous, returning value types. Both readings share every rule (the
/// muscle-group-key → region resolution, "the first mapped key leads", primary wins, set counting,
/// the exercise-name list) and differ only in where the muscle groups and the sets come from:
///
/// - **A workout** reads the denormalized `WorkoutExercise.muscleGroups` copy and counts
///   *completed* sets, so history keeps describing what was actually performed even after the
///   library exercise is edited.
/// - **A routine** reads the live `Exercise` it points at and counts *planned* sets, because it
///   describes what will happen. Re-tagging an exercise therefore changes every routine's map
///   immediately — that is the intent, not a leak.
struct MuscleLoadAggregator {

    /// One exercise as the aggregation reads it, whichever side produced it. Projecting into this
    /// is the *only* difference between the two readings — the rules below run once, on both.
    private struct Contribution {
        let name: String
        let muscleGroupKeys: [String]
        let setCount: Int
    }

    /// - Parameter session: a workout session; its exercises are visited in `order`.
    /// - Returns: one entry per trained region. Regions absent from the result were not trained,
    ///   and a session that maps to nothing (only `General`, or no completed work) returns empty.
    static func aggregate(session: WorkoutSession) -> [MuscleMapRegion: MuscleLoad] {
        fold(
            session.workoutExercisesList
                .sorted { $0.order < $1.order }
                .map { exercise in
                    Contribution(
                        name: exercise.exerciseName,
                        muscleGroupKeys: exercise.muscleGroups,
                        setCount: exercise.setsList.count(where: \.isCompleted)
                    )
                }
        )
    }

    /// - Parameter routine: a routine; its exercises are visited in `order`.
    /// - Returns: one entry per planned region. Regions absent from the result are not planned,
    ///   and a routine that maps to nothing (empty, only `General`, or stripped of its sets)
    ///   returns empty.
    static func aggregate(routine: Routine) -> [MuscleMapRegion: MuscleLoad] {
        fold(
            routine.routineExercisesList
                .sorted { $0.order < $1.order }
                .compactMap { routineExercise in
                    // An unattached slot exists so insertion can happen before SwiftData
                    // relationships are wired. It names no exercise and no muscle group, so it
                    // plans nothing.
                    guard let exercise = routineExercise.exercise else { return nil }
                    // Alternatives are deliberately not folded in: the user performs the exercise
                    // *or* one of them, never both. See docs/muscle-map.md.
                    return Contribution(
                        name: exercise.name,
                        muscleGroupKeys: exercise.muscleGroups,
                        setCount: routineExercise.setsList.count
                    )
                }
        )
    }

    /// Merges the per-exercise readings into one region → load picture, in the order given.
    private static func fold(_ contributions: [Contribution]) -> [MuscleMapRegion: MuscleLoad] {
        var engagements: [MuscleMapRegion: MuscleEngagement] = [:]
        var setCounts: [MuscleMapRegion: Int] = [:]
        var exerciseNames: [MuscleMapRegion: [String]] = [:]

        for contribution in contributions {
            // An exercise with no sets contributes neither a highlight nor a name: history shows
            // work actually performed, and a routine exercise stripped of its sets plans nothing —
            // a primary region reading "0 sets" would be a lie about either.
            guard contribution.setCount > 0 else { continue }

            for (region, engagement) in Self.engagements(of: contribution.muscleGroupKeys) {
                if engagement == .primary {
                    // Primary wins: a region that leads anywhere renders primary.
                    engagements[region] = .primary
                    setCounts[region, default: 0] += contribution.setCount
                } else if engagements[region] == nil {
                    engagements[region] = .secondary
                }
                if exerciseNames[region]?.contains(contribution.name) != true {
                    exerciseNames[region, default: []].append(contribution.name)
                }
            }
        }

        return engagements.reduce(into: [:]) { result, entry in
            let (region, engagement) = entry
            result[region] = MuscleLoad(
                engagement: engagement,
                setCount: setCounts[region] ?? 0,
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
    /// has no belly for would otherwise drop its sets from every region it does hit.
    private static func engagements(of muscleGroupKeys: [String]) -> [MuscleMapRegion: MuscleEngagement] {
        var engagements: [MuscleMapRegion: MuscleEngagement] = [:]
        var hasPrimary = false
        for key in muscleGroupKeys {
            guard let region = MuscleMapRegion(muscleGroupKey: key) else { continue }
            guard engagements[region] != .primary else { continue }
            engagements[region] = hasPrimary ? .secondary : .primary
            hasPrimary = true
        }
        return engagements
    }
}
