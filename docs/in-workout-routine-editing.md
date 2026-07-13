# In-Workout Routine Editing

## Purpose and current scope

In-workout routine editing lets a user change the exercise plan while an iOS workout is already running. An added exercise is configured with its number of sets, repetitions, weight, and rest time before it joins the live session. At workout completion, the existing **Update Routine Template** option controls whether exercise additions and removals become the plan for future workouts.

## iOS flow

`AddExerciseToWorkoutView` owns the picker navigation path:

1. Selecting an available library exercise pushes `ConfigureExerciseSetsView`.
2. Creating a custom exercise through `AddExerciseView` returns the new library exercise, then routes it through the same configuration step.
3. The configuration screen uses the established routine set editor and shared controls from `SetInputComponents.swift`. Its alternatives section is hidden for the live-workout flow because alternatives belong to routine-template configuration.
4. On save, the finalized `[ExerciseSet]` scheme is passed to `WorkoutViewModel`, which translates it into `[WorkoutSet]` with `WorkoutSet(from:order:)`. That initializer copies each configured value into both planned and actual reps/weight.
5. `WorkoutViewModel.addExerciseToWorkout(exercise:configuredSets:)` attaches the workout exercise and every converted set to the current `WorkoutSession`, inserts them through `WorkoutSessionRepository`, and saves.
6. Removing an exercise continues to affect only the live session until workout completion.
7. On completion, leaving **Update Routine Template** disabled preserves the original routine. Enabling it reconciles the routine against the completed session:
   - Existing slots are matched by `WorkoutExercise.routineExerciseId`. The exercise identifier/name fallback is retained only for historical workout edits, where routine membership is deliberately not reconciled.
   - Routine slots absent from the session are deleted and remaining slots are reordered.
   - Ad-hoc workout exercises are appended as new `RoutineExercise` slots with their configured sets, and the new slot identifier is written back to `WorkoutExercise.routineExerciseId` for stable history identity.
   - Existing exercises continue using the established set-count reconciliation, including performed values for completed sets.

Cancelling or navigating back from configuration does not add anything to the session. The save action remains disabled until at least one set exists.

## Architecture

The implementation uses existing domain models and repository boundaries across the established layers:

- `Presentation/Views/Workout/AddExerciseToWorkoutView.swift`: UUID-based picker navigation and forwarding of the configured set scheme.
- `Presentation/Views/Routines/RoutineExercisePickerView.swift`: shared `ConfigureExerciseSetsView`; configurable title, save label, and alternatives visibility keep one set-editing UI for both routine and workout flows.
- `Presentation/ViewModels/WorkoutViewModel.swift`: `ExerciseSet` to `WorkoutSet` translation, session mutation, slot-identity matching, and opt-in routine membership/set reconciliation.
- `Domain/Repositories/ExerciseRepository.swift`: identifier lookup resolves the library `Exercise` linked to a newly persisted routine slot.
- `Domain/Repositories/RoutineRepository.swift`: explicit `RoutineExercise` insertion complements the existing child mutation API.
- `Data/Repositories/SwiftDataExerciseRepository.swift` and `SwiftDataRoutineRepository.swift`: implement those persistence operations with `ModelContext` contained in Data.
- `App/ContentView.swift` and `Presentation/Views/Routines/RoutinesView.swift`: inject the already shared `ExerciseRepository` into `WorkoutViewModel`.
- `Domain/Models/Models.swift`: existing `WorkoutSet(from:order:)` performs the value-preserving conversion.

No persisted property or relationship was added. The feature reuses `RoutineExercise`, `ExerciseSet`, `Exercise`, and `WorkoutExercise.routineExerciseId`, so it introduces no CloudKit schema change and requires no CloudKit deployment.

When a routine slot is synthesized after the routine is already persisted, `WorkoutViewModel` follows SwiftData's relationship-ordering requirement: it inserts the unattached `RoutineExercise`, then links the persisted `Exercise` and `Routine`, then inserts and links each `ExerciseSet`. This avoids establishing relationships between models in different contexts.

## Platform behavior

### iOS

Supported in the active-workout add flow. Both existing library exercises and newly created custom exercises use the same configuration screen.

### watchOS

Unchanged. The watch target continues using its existing active-workout editing and `RoutineStore` behavior; no SwiftData or cross-device payload changes were added.

## Edge cases and deliberate omissions

- An exercise is not added until configuration is saved.
- At least one set is required.
- Configured set ordering is normalized during conversion.
- Planned and actual values start equal so the new exercise behaves like one copied from a routine template.
- Adding or removing an exercise does not mutate the routine until the user enables **Update Routine Template** at completion.
- Alternative exercises are not configured from the live-workout add flow.
- Exercise membership reconciliation runs only for active-workout completion. Updating an edited historical workout can still reconcile set values/counts, but it does not delete routine exercises added after that workout occurred.
- A new routine slot is created only when its `Exercise` still exists in the exercise library; the session history remains intact if the library lookup cannot resolve it.
