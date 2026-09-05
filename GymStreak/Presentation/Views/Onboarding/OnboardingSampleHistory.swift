//
//  OnboardingSampleHistory.swift
//  GymStreak
//
//  The one recorded session the onboarding tour shows. See docs/onboarding.md.
//

import Foundation

/// What the "History" slide previews, as plain values: one finished session of
/// the tour's own routine, and the session a week before it that the deltas are
/// measured against.
///
/// **This is copy, not data**, on exactly the terms `OnboardingSampleRoutine`
/// sets out: nothing here is inserted, seeded or synced, and the plate that
/// renders it is not interactive.
///
/// **Everything the plate compares is derived, never typed.** The per-set delta
/// chips, the top-weight delta, the volume percentage and the personal record
/// are all produced from `currentSets` and `previousSets` by the same production
/// code the History screen runs — `ExerciseComparisonBuilder` for the pairing,
/// `SetDeltaChip.Delta` for the chips, `ExerciseLoadMetrics` for the Epley
/// figures. A hand-written "+2.5 kg" would be a number that could disagree with
/// the sets printed next to it; there is nothing here that can.
enum OnboardingSampleHistory {

    /// One logged set. Canonical kilograms, like everything the store holds — the
    /// plate renders them in the user's own unit through `WeightFormatting`.
    struct LoggedSet {
        let kilograms: Double
        let reps: Int
    }

    // MARK: - Whose session this is

    /// The exercise is named by its `SeedExerciseCatalog` key so the tour cannot
    /// advertise it under a different name than the library the user lands in
    /// uses. Unlike steps 2–4 the muscle groups are *not* restated here: the
    /// history block draws no avatar, so there is nothing to keep in step with.
    static let seedKey = "seed.exercise.lat_pulldown"

    static var exerciseName: String { seedKey.localized }

    /// The tour's own routine, trained. Steps 2 and 3 build "Upper Body A"; this
    /// slide is what one session of it looks like afterwards, so the name is
    /// borrowed from step 2's key rather than restated and left to drift.
    static var routineName: String { "onboarding.routines.sample.routine_name".localized }

    /// Derived from the routine name exactly as the app derives it, so the chip
    /// cannot claim a type `WorkoutType.classify` would never produce — and so it
    /// stays right in both languages ("Upper Body A" / "Oberkörper A").
    static var workoutType: WorkoutType { WorkoutType.classify(routineName: routineName) }

    /// Two days ago, with the session it is compared against a week earlier.
    ///
    /// Relative rather than a fixed calendar date: "19 Apr" reads as stale the
    /// moment the year turns, and a weekday printed beside a hard-coded date is
    /// wrong in most years. These are real `Date`s formatted by the same
    /// templates the History screen uses, so the weekday, the month name and the
    /// field order are the reader's own locale's.
    static let sessionDate = Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now
    static let previousSessionDate = Calendar.current.date(byAdding: .day, value: -9, to: .now) ?? .now

    /// A little over the routine's own "~28 min" estimate.
    static let duration: TimeInterval = 31 * 60

    // MARK: - The exercise the block shows

    /// This session's four sets: the first one taken up 2.5 kg — which is the
    /// personal record — the second repeated exactly, the third one rep short,
    /// and a fourth set that the previous session did not have at all.
    ///
    /// The four are chosen so the block shows all four states a delta chip has:
    /// gain, unchanged, loss, and new. Reps declining across the sets is what
    /// fatigue actually looks like, and it is what makes the third set's "−1 rep"
    /// believable rather than arranged.
    static let currentSets: [LoggedSet] = [
        LoggedSet(kilograms: 57.5, reps: 11),
        LoggedSet(kilograms: 55, reps: 10),
        LoggedSet(kilograms: 55, reps: 9),
        LoggedSet(kilograms: 55, reps: 8)
    ]

    /// Last week's three sets, all at the routine's planned 55 kg.
    static let previousSets: [LoggedSet] = [
        LoggedSet(kilograms: 55, reps: 11),
        LoggedSet(kilograms: 55, reps: 10),
        LoggedSet(kilograms: 55, reps: 10)
    ]

    // MARK: - The session totals the stat tiles show

    /// The rest of the session: the superset step 3 shows, performed as planned.
    /// Borrowed so the four tiles describe *this* routine rather than numbers
    /// invented to look plausible beside it.
    private static let supersetSets = OnboardingSampleRoutine.supersetMembers.flatMap(\.plannedSets)

    /// Computed once, at first access — never per render (rendering rule 3).
    static let sessionSetCount: Int = currentSets.count + supersetSets.count

    static let sessionVolumeKilograms: Double = volume(of: currentSets)
        + supersetSets.reduce(0) { $0 + $1.kilograms * Double($1.reps) }

    /// `WorkoutSession.completionPercentage` is completed ÷ planned sets. Every
    /// set of the sample was logged, so it is 100 — the honest figure for the
    /// session described above, not a rounder-looking one.
    static let completionPercentage = 100

    // MARK: - What the production views are handed

    static let exerciseDisplay = WorkoutDetailExerciseDisplay(
        id: workoutExerciseId,
        name: exerciseName,
        sets: currentSets.enumerated().map { index, set in
            WorkoutDetailExerciseDisplay.SetValues(
                id: setIds[index],
                weight: set.kilograms,
                reps: set.reps,
                isCompleted: true
            )
        }
    )

    static let previousPerformance = PreviousExercisePerformance(
        date: previousSessionDate,
        routineName: routineName,
        sets: previousSets.map {
            PreviousExercisePerformance.SetPerformance(
                reps: $0.reps,
                weight: $0.kilograms,
                isCompleted: true
            )
        },
        effectiveTotalVolume: volume(of: previousSets)
    )

    /// The comparison the strip and the per-set chips render from, built by the
    /// **production** builder rather than assembled here.
    ///
    /// That is what makes the fourth set read "New": the builder pairs sets by
    /// position and leaves a set the previous session did not have without a
    /// counterpart. Reproducing that rule locally would be a copy of it that
    /// could fall behind — this way the slide follows the screen.
    ///
    /// Optional because `build` returns one result per snapshotted exercise and
    /// `first` is the honest way to take the only one; the block's parameter is
    /// optional anyway, so nothing here needs a force-unwrap or a crash path.
    /// `historySampleComparisonIsBuiltFromTheSets` pins that it is not nil.
    static let comparison: ExerciseComparisonResult? = ExerciseComparisonBuilder.build(
        snapshot: snapshot,
        previousPerformances: [workoutExerciseId: previousPerformance]
    ).first

    /// The record the gold chip and the PR strip describe: the set with the
    /// highest Epley estimate, which is how `PersonalRecordService` picks one,
    /// against the best estimate of the previous session.
    ///
    /// Both figures come from `ExerciseLoadMetrics.estimatedOneRepMax`, so the
    /// strip's "vs." line cannot disagree with the weights printed under it —
    /// and `historySamplePRIsAnActualRecord` pins that the current estimate
    /// really does beat the previous best, i.e. that the badge is earned.
    static let prDetail: PersonalRecordService.PRDetail? = {
        let estimates = currentSets.map(oneRepMax)
        guard let index = estimates.indices.max(by: { estimates[$0] < estimates[$1] }) else {
            return nil
        }
        return PersonalRecordService.PRDetail(
            // `WorkoutExercise.stableKey` in production. Nothing in the block or
            // the strip renders it — it is what the service keys records by —
            // so the seed key stands in for the identity the tour has no store
            // to give it.
            exerciseKey: seedKey,
            workoutExerciseId: workoutExerciseId,
            setId: setIds[index],
            weight: currentSets[index].kilograms,
            reps: currentSets[index].reps,
            estimatedOneRepMax: estimates[index],
            previousBest: previousSets.map(oneRepMax).max()
        )
    }()

    // MARK: - Private

    /// Stable for the life of the process; nothing persists them. The set ids are
    /// what the PR detail points at, so they are drawn once rather than per call.
    private static let workoutExerciseId = UUID()
    private static let setIds = currentSets.map { _ in UUID() }

    /// The sample session as `ExerciseComparisonBuilder` describes a workout.
    ///
    /// The `lookup` half is the input to the *other* half of the comparison — the
    /// history scan that finds the predecessor — which the tour never runs: it is
    /// handed the previous session directly. It is filled in truthfully anyway,
    /// so the snapshot is a complete description of the sample rather than a
    /// half-built one that would be wrong if anything ever read it.
    private static let snapshot = ExerciseComparisonBuilder.WorkoutSnapshot(
        lookup: PreviousPerformanceLookup(
            before: sessionDate,
            routineId: nil,
            exercises: [
                PreviousPerformanceLookup.Query(
                    workoutExerciseId: workoutExerciseId,
                    exerciseName: exerciseName,
                    exerciseId: nil,
                    loadBehavior: .resistance,
                    routineExerciseId: nil
                )
            ]
        ),
        exercises: [
            ExerciseComparisonBuilder.ExerciseSnapshot(
                workoutExerciseId: workoutExerciseId,
                exerciseName: exerciseName,
                loadBehavior: .resistance,
                sets: currentSets.map {
                    ExerciseComparisonBuilder.SetSnapshot(
                        reps: $0.reps,
                        weight: $0.kilograms,
                        isCompleted: true
                    )
                },
                totalVolume: volume(of: currentSets),
                // Equal to the raw volume for a `.resistance` exercise, which a
                // lat pulldown is. The distinction only bites on counterweight
                // assistance, and the tour deliberately shows neither that nor a
                // bodyweight lift here.
                effectiveTotalVolume: volume(of: currentSets),
                completedSetsCount: currentSets.count,
                totalReps: currentSets.reduce(0) { $0 + $1.reps }
            )
        ]
    )

    private static func volume(of sets: [LoggedSet]) -> Double {
        sets.reduce(0) { $0 + $1.kilograms * Double($1.reps) }
    }

    private static func oneRepMax(_ set: LoggedSet) -> Double {
        ExerciseLoadMetrics.estimatedOneRepMax(weight: set.kilograms, reps: set.reps)
    }
}
