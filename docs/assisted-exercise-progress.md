# Assisted Exercise Progress

## Purpose

Counterweight machines reverse the normal meaning of the selected stack: more selected kilograms
provide more help. GymStreak models this explicitly so reducing assistance is tracked as progress.

## Scope

**iOS:** Users select an exercise load behavior in the library. New workouts snapshot that behavior
onto `WorkoutExercise`; counterweight workouts expose one optional body-weight entry per session.
The History Progress tab uses effective load when every displayed assisted session has a body-weight
snapshot, otherwise it presents assistance only and treats lower values as better.

**watchOS:** Routine and completed-workout sync payloads carry the load behavior so watch-completed
counterweight exercises retain their direction on iPhone. The watch currently has no body-weight
entry, so these sessions use the safe assistance-only history fallback.

## Architecture

- `ExerciseLoadBehavior` in `Domain/Models/` has `.resistance` and `.counterweightAssistance`.
- `Exercise.loadBehaviorRaw` is the editable library setting; `WorkoutExercise.loadBehaviorRaw`
  is the immutable history snapshot.
- `WorkoutSession.bodyWeightKg` is optional. `ExerciseLoadMetrics` calculates effective load as
  `bodyWeightKg - enteredAssistance`; it never invents a value when the snapshot is absent.
- `ExerciseComparisonBuilder` / `PreviousPerformanceResolver` (the vs-previous comparison),
  `FortschrittAggregator`, `PersonalRecordService`, total-volume calculation, set deltas, and
  progressive overload use the behavior rather than assuming that larger entered weight is
  always better. Both halves of the comparison share one implementation,
  `ExerciseLoadMetrics.effectiveVolume(from:usePlannedValues:behavior:bodyWeightKg:)` — they
  run on different executors (audit P1.6), and duplicating it would let the current and
  previous sides of one comparison disagree about assisted load.

## Migration and catalog behavior

Existing data defaults to normal resistance for compatibility. The starter catalog's
`seed.exercise.assisted_pull_up` is reconciled at launch by stable seed key; linked recorded sets
are also reclassified. User-created exercises are never guessed from their name.

## Constraints

Counterweight assistance is intended for machines with a fixed displayed counterweight. It must
not be used for resistance bands because their assistance changes through the range of motion.
Apple Health body mass can be used only as a future optional prefill: HealthKit read access and
historical samples are not guaranteed, so stored workout snapshots remain authoritative.
