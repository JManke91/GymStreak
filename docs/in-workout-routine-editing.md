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

The original iOS editing slice added no persisted property or relationship: it reuses `RoutineExercise`, `ExerciseSet`, `Exercise`, and `WorkoutExercise.routineExerciseId`. Ticket 05 later added two optional `WorkoutSession` witness fields, described under Platform behavior below; those fields do require a CloudKit schema deployment.

When a routine slot is synthesized after the routine is already persisted, `WorkoutViewModel` follows SwiftData's relationship-ordering requirement: it inserts the unattached `RoutineExercise`, then links the persisted `Exercise` and `Routine`, then inserts and links each `ExerciseSet`. This avoids establishing relationships between models in different contexts.

## Platform behavior

### iOS

Supported in the active-workout add flow. Both existing library exercises and newly created custom exercises use the same configuration screen.

### watchOS

Active-workout editing behavior is unchanged so far. **Ticket 04** hardened the shared standalone completion path that ticket 06's structural editing will build on: every watch completion (especially ordinary Save Workout, `shouldUpdateTemplate == false`) now runs one terminal finalization state machine that freezes a single `CompletedWatchWorkout` into a durable, atomically-persisted outgoing queue *before* any HealthKit transition, phases the required external-UUID metadata and HealthKit finish as retryable steps, and separates transport from enqueue. iOS receives into a durable atomic inbox, ingests no-template workouts in an isolated single-save `ModelContext`, and records indefinitely-retained terminal receipts so duplicates/lost-acks/relaunches converge and only a semantic `workoutAck` retires watch state. `WorkoutSession.init` now takes `Routine?` so a workout whose routine was deleted produces `routine == nil` history instead of a resurrecting placeholder. Full architecture, crash boundaries, receipt retention/performance, and background behavior: see `docs/watch-sync.md` ("Reliability Architecture", "Background lifecycle", "Verification status (ticket 04)").

**Ticket 05** turned "Save & Update Template" into an ordered, all-or-nothing **template transaction**. The durable unit is now a generic `TemplateTransactionEnvelope` (stable transaction id, sender epoch, per-routine sequence, optional workout correlation, extensible payload); the completed workout is ticket 05's first payload kind, not the queue identity. The same atomic replacement allocates identity/counter/anchor, and only the oldest pending transaction per routine may use either transport path. On iOS, `WatchTemplateTransactionCoordinator` gates on the sequence ledger and `WatchTemplateTransactionService` validates the complete set-only intent before committing history + template in one isolated save. Phased receipts repair partial receipt/index/ledger writes before acknowledging; unresolved ready receipts use a bounded recovery-marker set, so later authority challenges can restage current routines without repeating mutation or scanning indefinite receipt history. `RoutineSyncAuthority` persists generations before transport, never reuses an ambiguously sent generation, and hands over epochs instead of overflowing; the watch sender likewise rotates its epoch if a per-routine sequence is exhausted. On the watch, `WatchSyncStateStore` is the one atomic owner; failed ack/retirement/migration writes roll back in-memory state and cannot release a successor. `RoutineStore` remains only the published `effectiveRoutines()` projection, and terminal ack + correlated context can arrive in either order. Old iOS/watch builds retain the legacy workout/ack/context compatibility paths. Full protocol and verification details: see `docs/watch-sync.md` ("Template Transactions").

The first physical-device pass exposed a cross-context visibility bug after that correct isolated commit: the coordinator serialized routines from an already-populated main `ModelContext`, so it sent and acknowledged old set values; the Watch then retired its optimistic update back to that stale base. The History reconciler similarly compared HealthKit against cached main-context sessions, falsely labeling already-ingested workouts as pending and allowing duplicate recovery. Post-commit routine authority and HealthKit correlation now use fresh read contexts mapped immediately to immutable values. The main UI cache is refreshed separately only when it has no pre-existing unsaved work. This preserves the one-save isolated transaction and prevents the transport protocol from depending on SwiftData's timing between contexts. Paired-device retesting confirmed History insertion and iOS template updates; see `docs/watch-sync.md` for the complete pass/fail matrix and Apple API research.

The next paired-device pass found a separate watch presentation snapshot: keeping a routine detail open across completion retained the full `WatchRoutine` value that had originally been pushed into `NavigationStack`, so Start could use old sets even though the running `RoutineStore` and its durable state were current. Watch navigation and full-screen workout presentation now carry typed routine IDs only. The detail resolves the current effective routine while visible, and `WatchWorkoutViewModel` resolves once more when Start is tapped; that moment is the deliberate boundary where future template state is copied into the new active workout. This follows Apple's guidance to keep navigation paths lightweight and prevents weights, reps, exercise order/count, names, or deletions from being retained as stale path snapshots. Paired-device verification passed for both one update and two consecutive updates: both platforms received the latest template and both workouts appeared in iOS History without adding false pending-sync entries.

The powered-off-iPhone pass then exposed a transport lifecycle gap: the Watch queue retained the workout, but neither iPhone launch nor foregrounding an already-running Watch app explicitly reconciled it. Watch foregrounding now reconciles directly, transient transfer failure schedules one bounded retry, and iOS sends a versioned queue-drain wake-up after valid WCSession activation/foreground/reachability recovery. A first attempt incorrectly treated a matching `outstandingUserInfoTransfers` item as stale and force-enqueued another copy; after an iPhone reboot that congested ordinary reachable delivery. Apple defines outstanding transfers as not failed or completed, so the corrected request never bypasses semantic-ID suppression. Reachable sessions send only the immediate request; unreachable sessions queue at most one durable request, with message-error fallback. Only the application acknowledgment retires the Watch entry. Automated coordinator coverage passes. The powered-off path is now confirmed by the three-workout test below; ordinary reachable sync after an iPhone reboot still awaits paired-device retesting.

A later three-workout offline pass exposed a second lifecycle edge: all three workouts used Save & Update Template for the same routine, so the per-routine FIFO correctly allowed only the oldest transaction onto the transport. After iOS acknowledged that head and sent its authoritative routine context, the Watch retired it but did not reconcile the newly eligible successor until the Watch app was foregrounded. Successful durable retirement now publishes a transport-eligibility change that immediately drives the existing transport coordinator; acknowledgment-first and context-first orderings both drain all successors without weakening FIFO ordering. WatchConnectivity background wakes also use an explicit delegate-work completion tracker before app-owned drains instead of assuming one scheduler yield means callbacks have finished. Focused regression tests pass, and paired-device retesting confirmed that all three workouts reach iOS History after the iPhone returns without reopening the Watch app.

Ticket 05 adds optional `WorkoutSession.watchTemplateTransactionID` and `watchTemplateOutcomeRaw` attributes. They are written in the same SwiftData save as history + template and distinguish a proven atomic commit from a legacy `didUpdateTemplate` flag whose former separate template save may have failed. Existing rows migrate with nil defaults and therefore take the legacy reconciliation path. Before release, run the repository's CloudKit schema initializer against Development, verify both fields, then deploy the Development schema to Production in CloudKit Console (see `docs/cloudkit-schema-automation.md`).

As the enabling infrastructure for the upcoming watch picker (ticket 06), the full exercise catalogue now syncs iOS → watch (ticket 03): versioned full-replacement JSON snapshots over tagged `WCSession.transferFile`, guarded by an authority-epoch/generation recency protocol with receiver-authorized handover, and cached on the watch in the file-based `ExerciseCatalogStore` (App Group state file + crash-resilient receive inbox + `.backgroundTask(.watchConnectivity)` cold-delivery handling). The store distinguishes never-synced, valid-empty, and populated states and exposes `items` / `hasReceivedCatalog` / `lastSyncDate` for ticket 06. Catalogue items intentionally carry exercise identity/metadata only (id, optional `seedKey` fallback identity for seed-dedup survivors, name, muscle groups, equipment + load-behavior raw values) — set-creation policy belongs to ticket 06, and ticket 07 resolves a watch-returned exercise by `Exercise.id`, then non-empty `seedKey`, never resurrecting deleted exercises. Full protocol, triggers, failure policy, and verification status: see `docs/watch-sync.md` ("Exercise Catalogue Sync").

## Edge cases and deliberate omissions

- An exercise is not added until configuration is saved.
- At least one set is required.
- Configured set ordering is normalized during conversion.
- Planned and actual values start equal so the new exercise behaves like one copied from a routine template.
- Adding or removing an exercise does not mutate the routine until the user enables **Update Routine Template** at completion.
- Alternative exercises are not configured from the live-workout add flow.
- Exercise membership reconciliation runs only for active-workout completion. Updating an edited historical workout can still reconcile set values/counts, but it does not delete routine exercises added after that workout occurred.
- A new routine slot is created only when its `Exercise` still exists in the exercise library; the session history remains intact if the library lookup cannot resolve it.
