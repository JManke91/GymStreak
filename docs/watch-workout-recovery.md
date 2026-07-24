# Watch Active-Workout Recovery (ticket 08, in-workout routine editing)

## What this feature does

If watchOS terminates and relaunches GymStreak while a workout is in progress
(a crash, a memory-pressure jetsam, or a system relaunch), the workout is
recovered instead of lost. Two independent things are restored:

1. **The app-owned workout state** — the routine, the exercises/sets with their
   stable IDs and completion values, the current position, the workout start
   time, and the ticket-06 structural add/remove baseline — from a durable
   **checkpoint** file the app writes throughout the session.
2. **The live HealthKit session** — the `HKWorkoutSession` and its
   `HKLiveWorkoutBuilder` — via Apple's `recoverActiveWorkoutSession`, so live
   heart rate / calories / elapsed time keep flowing and the same `HKWorkout` is
   finished exactly once.

The user is dropped back into the exact same workout and can continue or finish
it. No second HealthKit workout, workout/correlation UUID, history row, or
template mutation is ever created by recovery.

**Targets:** watchOS only (the iOS app is unaffected at runtime; the
dual-copied model/store/planner exist in the iOS target purely so the iOS test
target can cover them — there is no watch unit-test target).

## Architecture

### The durable checkpoint (crash boundary)

`WatchActiveWorkoutCheckpoint` (dual-copied: watch `Models/`, iOS
`Data/Sync/`) is a `Codable` snapshot of the live workout:

- `workoutID` — the stable GymStreak workout UUID (`CompletedWatchWorkout.id`).
- `healthKitWorkoutID` — the preallocated `HKMetadataKeyExternalUUID`.
- `routine` — the `WatchRoutine` resolved at start (identity + name + planned
  structure), restored verbatim, never re-resolved from the store.
- `exercises` — `[ActiveWorkoutExercise]` (now `Codable`) with stable slot/set
  IDs, actual reps/weight, per-set `completedAt`, swap metadata, and
  `isPendingWatchAddition` provenance.
- `currentExerciseIndex` / `currentSetIndex`, `startTime`.
- `structuralBaseline` — `WatchWorkoutStructuralBaseline` (now `Codable`), so
  ticket-06 add/remove membership intent survives relaunch and a later removal
  can still cancel a pending addition.

`WatchActiveWorkoutCheckpointStore` (dual-copied: watch `Managers/`, iOS
`Data/Sync/`) persists it as a **throwing, atomically-replaced App Group file**
at `App Group/WorkoutSync/active-workout-checkpoint.json` — the same
persistence discipline as `WatchSyncStateStore` (the atomic replace is the
crash boundary; `UserDefaults` is deliberately NOT used). An undecodable file
is quarantined as `.corrupt` and reported as "no checkpoint" rather than
silently overwritten.

**Preallocated identifiers.** `WatchWorkoutViewModel.startWorkout` now mints
`pendingCompletedWorkoutId` and `pendingHealthKitWorkoutId` at workout **start**
(previously they were minted at finalization). This is what lets a crash
mid-workout recover the exact same GymStreak workout / HealthKit external UUID
and never mint a second.

**When it's written.** `persistActiveCheckpoint()` is called at *bounded
meaningful mutations only* — start, set completion toggle, set value edit, rest
edit, exercise swap, add/remove exercise, and explicit exercise/set navigation.
It is deliberately **never** written on sensor samples or high-frequency
statistics (heart rate / calories / elapsed time), and it is suspended once
finalization begins (`isEnding`) because the frozen durable payload in
`WatchSyncStateStore` then owns the workout. Writes are best-effort: a failed
write costs at most one mutation's worth of resume fidelity, never the workout.

**When it's cleared.** On finalization completing past HealthKit (the finalizer
returns `.completed`), on discard, and on summary dismissal (`resetState`). A
crash in the small window between "past HealthKit" and "checkpoint cleared" is
reconciled to `.finalizationComplete` on the next launch (below).

### Recovery entry points

`WatchAppDelegate` (a `WKApplicationDelegate`, wired with
`@WKApplicationDelegateAdaptor` on `GymStreakWatchApp`) receives watchOS's
documented crash-relaunch callback `handleActiveWorkoutRecovery()`. Because that
callback is **not guaranteed** after a normal force-quit and is reported as
**not firing after a watch reboot**, recovery is also kicked from
`applicationDidFinishLaunching()` and from `AppState.connectServices()` (the
foreground launch path). All three funnel into the idempotent
`WatchWorkoutRecoveryCoordinator`, which performs the actual recovery **exactly
once per process** and buffers the request if the live ViewModel / HealthKit
manager are not registered yet (the callback can fire before any UI exists).

### The recovery coordinator + pure planner

`WatchWorkoutRecoveryCoordinator` (`@MainActor` singleton, watch-only) runs:

1. Load the checkpoint (nil if absent/corrupt).
2. Identify the workout under recovery — the checkpoint's `workoutID`, else the
   oldest durable entry left mid-HealthKit (`interruptedFinalizationWorkoutIDs()`).
3. Ask `WatchHealthKitManager.recoverActiveSession()` for a still-active session
   and adopt it (`adoptRecoveredSession`).
4. Classify via the **pure, HealthKit-free** `WatchWorkoutRecoveryPlanner.plan`,
   then execute the decision.
5. Sweep any *other* stranded finalizations via
   `WatchSyncStateStore.promoteInterruptedFinalizations()` and trigger transport.

`WatchWorkoutRecoveryPlanner.plan(hasCheckpoint:frozenEntryPhase:didRecoverLiveSession:)`
is the crash-point classification (exhaustively unit-tested):

| Checkpoint | Frozen entry phase | Live session? | Decision | Action |
|---|---|---|---|---|
| — | `awaitingHealthKitMetadata`/`awaitingHealthKitFinish` | yes | `resumeFinalization(true)` | finish the recovered HK workout (also ends a still-running session so it can't leak) |
| — | `awaitingHealthKit*` | no | `resumeFinalization(false)` | promote the durable payload; reconcile via external UUID |
| yes | `transportEligible`/`quarantined` | any | `finalizationComplete` | clear the stale checkpoint |
| — | `transportEligible`/`quarantined` | any | `none` | nothing to do |
| yes | none | yes | `resumeLiveWorkout(true)` | rebuild the ViewModel; live metrics resume |
| yes | none | no | `resumeLiveWorkout(false)` | rebuild the ViewModel; constrained (HK recording lost) |
| — | none | yes | `constrainedOrphanSession` | preserve the HK workout, no routine fabrication |
| — | none | no | `none` | nothing to do |

The resumed live workout re-presents the active-workout cover via
`WatchWorkoutViewModel.resumedWorkoutRoutineID`, observed by `RoutineListView`.
`WatchWorkoutViewModel.startWorkout` is now resume-aware — it no-ops when a
workout for that routine is already live, so the cover's `.task` can't start a
second HealthKit session.

## Crash boundaries (explicit outcomes)

The documented HealthKit end sequence is `stopActivity → .stopped →
endCollection → finishWorkout → session.end()`. GymStreak's finalizer
(`WatchHealthKitManager.endCollectionAndAddMetadata`) calls `session.end()` then
`endCollection` then stamps metadata (advancing to `awaitingHealthKitFinish`),
then `finishWorkout()` (advancing to `transportEligible`).

- **Crash while live (no frozen entry).** Checkpoint present → resume the live
  workout. If the HK session is still active it is reconnected (metrics resume);
  if not, a **constrained resume** — HealthKit live recording is lost but the
  workout is fully usable and GymStreak history is preserved.
- **Crash in `awaitingHealthKitMetadata` (session still running).** The session
  is recoverable; finalization resumes and finishes it properly. This is why the
  eager launch-time promotion was removed from `WatchConnectivityManager.init`
  (see below): a blind promotion here would abandon a running session that could
  block the next workout with `errorAnotherWorkoutSessionStarted`.
- **Crash in `awaitingHealthKitFinish` (`session.end()` already called).** The
  session is typically no longer active, so no live recovery; the durable
  payload is promoted so the workout still reaches iOS. Whether Apple Health
  kept the record is reconciled (diagnostic) via
  `savedWorkoutExists(externalUUID:)`.
- **Crash after `finishWorkout()` completed.** The `HKWorkout` is already saved;
  the entry is `transportEligible`; only stale-checkpoint cleanup remains
  (`finalizationComplete`).

**Active-session recovery is never treated as proof the workout ended.** A
recovered session in a HealthKit phase resumes finalization; it does not skip to
`finalizationComplete`. (Unit test: `planMidHealthKitPhasesResumeFinalization`.)

## Interaction with the ticket-04 promotion

`WatchSyncStateStore.promoteInterruptedFinalizations()` (ticket 04) used to run
eagerly in `WatchConnectivityManager.init`. Ticket 08 **removed that eager call**
so foreground recovery gets first chance to reconnect and finish a still-running
session. Promotion now runs:

- as the coordinator's **final sweep** for entries other than the primary
  (the system allows only one active session, so those can't be live), and
- as a **cold-background-wake backstop** in
  `handleWatchConnectivityBackgroundWake()` (a background wake has no UI and no
  recovery coordinator, but the durable payload must still transport).

## Missing / corrupt checkpoint

If HealthKit reports an active session but there is no valid app checkpoint
(`constrainedOrphanSession`), the session is **preserved** — adopted and
finished via `finishOrphanRecoveredSession()` (ends collection, stamps only a
`GymStreak` brand name, finishes) so the user's effort is saved to Apple Health.
It does **not** fabricate routine or template membership. The finished
`HKWorkout` then surfaces through the existing iOS orphan reconciler's "Add to
history" banner (see docs/watch-sync.md → "HealthKit reconciliation").

**Deliberate omission:** a richer in-app "constrained recovery/finish" screen
was intentionally NOT built for this rare corruption path — the safe,
non-fabricating behavior (preserve to Apple Health + iOS orphan surfacing) is
the simplest thing that works. To expand it later, present a dedicated view
before calling `finishOrphanRecoveredSession()` rather than fabricating a
routine.

## Idempotency

Apple does not document what happens if the recovery callback fires more than
once, so the app guards it itself:

- `WatchWorkoutRecoveryCoordinator.recoverIfNeeded()` runs the recovery once per
  process (`hasAttempted`/`isRecovering` flags).
- `WatchHealthKitManager.adoptRecoveredSession` no-ops if a session is already
  owned (prevents attaching a second data source / delegate pair).
- `WatchWorkoutViewModel.resumeRecoveredWorkout` no-ops if a workout is already
  active.
- The finalizer rejects reentrancy, and enqueue is idempotent by workout id.

## Official API research (verified 2026-07-23)

- `HKHealthStore.recoverActiveWorkoutSession()` — async form used; returns the
  recovered `HKWorkoutSession?` (nil when nothing active to recover). watchOS
  5.0+. Recovers ONLY a still-**active** session, not one already ended/finished.
  <https://developer.apple.com/documentation/healthkit/hkhealthstore/recoveractiveworkoutsession(completion:)>
- Builder reattachment: `session.associatedWorkoutBuilder()`, then set
  `session.delegate` and `builder.delegate` **before**
  `builder.dataSource = HKLiveWorkoutDataSource(healthStore:workoutConfiguration: session.workoutConfiguration)`.
  Delegates-before-dataSource is a defensive ordering (a freshly-assigned data
  source can immediately surface buffered samples through the builder delegate).
  Without the data source, the OS keeps recording to the store but the app's
  builder receives/aggregates nothing.
  <https://developer.apple.com/documentation/HealthKit/running-workout-sessions>
- Entry point: `WKApplicationDelegate.handleActiveWorkoutRecovery()` (watchOS
  7.0+, **not** deprecated — the `WKExtensionDelegate` variant was deprecated in
  watchOS 9.2). NOT reliably called after a force-quit; reported as not called
  after a watch reboot → also call recovery from launch.
  <https://developer.apple.com/documentation/watchkit/wkapplicationdelegate>
- Enabling capability: `WKBackgroundModes = ["workout-processing"]` in the watch
  Info.plist (already present for the Action Button feature). No separate
  "opt into recovery" plist key exists.
- Correlation: `HKMetadataKeyExternalUUID` queried via
  `HKQuery.predicateForObjects(withMetadataKey:allowedValues:)` — the same
  cross-device key `HealthKitWorkoutManager` uses on iOS.

### Known OS caveats (verify on hardware)

- **Simulator does not reliably trigger `handleActiveWorkoutRecovery()`** — test
  recovery on a physical Apple Watch.
- **Recovery is crash-scoped, not reboot-scoped.** `recoverActiveWorkoutSession`
  reattaches a session the system `workoutd` daemon kept alive across an app
  crash/force-quit. A device **reboot** terminates `workoutd`, so no session
  survives to recover — after a reboot the app recovers its own checkpoint but
  the HealthKit half is a constrained resume (no live session). Confirmed via
  WWDC25 Session 322 ("Crash Recovery") + DTS forum corroboration.
- **Paused-session elapsed time bug** (Apple DTS-acknowledged): a recovered
  session that was paused before the crash reports elapsed time as if never
  paused. Not worked around here (GymStreak uses HealthKit's elapsed time for
  display only; the durable payload's duration is `endTime − startTime` from the
  checkpoint's stable `startTime`). File Feedback if observed.
- `session.end()` can hang for 1–2 min in mirrored/multi-device sessions
  (GymStreak is single-device Watch-only, so not expected).

## Key files

- `WatchActiveWorkoutCheckpoint.swift` — model + `WatchWorkoutRecoveryPlanner` (dual copy)
- `WatchActiveWorkoutCheckpointStore.swift` — atomic App Group file store (dual copy)
- `GymStreakWatch Watch App/Managers/WatchWorkoutRecoveryCoordinator.swift` — orchestrator (watch-only)
- `GymStreakWatch Watch App/WatchAppDelegate.swift` — recovery callback wiring (watch-only)
- `WatchHealthKitManager.swift` — `recoverActiveSession` / `adoptRecoveredSession` / `restoreRoutineMetadata` / `savedWorkoutExists` / `finishOrphanRecoveredSession`
- `WatchWorkoutViewModel.swift` (+`+StructuralEditing`) — checkpoint writes, resume paths, preallocated IDs
- `WatchSyncStateStore.swift` — `interruptedFinalizationWorkoutIDs()` (dual copy)
- `WatchConnectivityManager.swift` (watch) — promotion moved to the background-wake backstop

## Verification status

Automated (iOS test target — `WatchActiveWorkoutRecoveryTests`, 10 tests):
the full planner decision table incl. "active session is not proof of a finished
workout"; checkpoint round-trip preserving stable workout/HK/slot/set IDs, swap
metadata, completion values, and structural baseline; store save/load/clear and
reopen-after-relaunch; undecodable-checkpoint quarantine → nil;
`interruptedFinalizationWorkoutIDs` FIFO filtering. Full suite: **257 tests in
34 suites pass**. Both the `GymStreak` iOS scheme and `GymStreakWatch Watch App`
scheme compile. No `@Model`/CloudKit-schema change (the checkpoint is a plain
Codable App Group file).

### Paired-hardware matrix — results (2026-07-24, first pass)

Physical iPhone + Apple Watch pair. Force-quit was used to trigger termination
(the recovery callback is reliably invoked only on abnormal termination; the
`applicationDidFinishLaunching`/registration fallback covers force-quit and
reboot).

**Passing:**

- **Core live-workout recovery** — mid-workout force-quit + relaunch restores the
  same routine, exercises, completed sets, and position, and live heart-rate /
  calories / elapsed time resume. Holds with iPhone reachable and with iPhone
  unreachable / powered off; finishing after recovery produces exactly one
  History row and one Apple Health workout with correct values and no false
  "waiting to sync". **One exception — see open issue 1 (rest timer).**
- **Structural / edited state survives** — add exercise, remove exercise, swap to
  an alternative, and edited set values all persist across force-quit + relaunch;
  "Save & Update Template" updates the routine once on both devices afterwards.
- **Terminal / crash boundaries** — killing during finishing / at the terminal
  boundaries produces exactly one workout in History and Apple Health, no stuck
  "waiting to sync", and a new workout can be started immediately (no leaked
  active session). Idempotent across repeated relaunches.

**Open issues (found this pass):**

1. **Rest timer is not restored on resume.** If a rest timer was running when the
   app was killed, it is not shown after recovery. Root cause: the checkpoint
   (`WatchActiveWorkoutCheckpoint`) intentionally captures workout structure and
   completion but not the transient rest-timer state (`isResting`,
   `restTimeRemaining`, `restDuration`, `restTimerState`, `isRestTimerMinimized`),
   and `resumeRecoveredWorkout` does not re-arm the timer. Low severity (a
   countdown, not workout data), but visible. Fix would add those fields to the
   checkpoint and re-arm the timer from remaining time on resume.
2. **Reboot during a workout → constrained resume with no HealthKit metrics or
   running timer.** After a full watch reboot, relaunching correctly restores the
   completed exercises/state, but heart rate and calories do not update and the
   total timer stays at 00:00 — the app is running with **no live HealthKit
   session**. See the dedicated analysis in "Open issue: reboot metrics/timer"
   below.
3. **Pause state is not preserved.** Pausing the workout, killing the app, and
   relaunching resumes the workout as *running* rather than paused. Root cause:
   the checkpoint does not persist `isPaused`, and `adoptRecoveredSession` /
   `resumeRecoveredWorkout` do not read or restore a recovered session's paused
   state. Low severity (the user can re-pause); a fix would persist `isPaused`
   and, when a live session is recovered in a paused state, keep it paused.

**Not yet exercised on hardware:** injected HealthKit metadata/finish failure,
duplicate recovery *callbacks* (vs. repeated relaunch, which was covered),
missing/corrupt-checkpoint-with-active-session, and the paused-then-crashed
elapsed-time bug. Re-run after the open issues are triaged.

### Open issue: reboot metrics/timer — analysis (2026-07-24)

Observed (edge case 10): a watch reboot mid-workout, then relaunch → app-owned
state and completed exercises recover correctly, but no live HR/calories and the
total time is stuck at 00:00, i.e. the app did not attach to a HealthKit workout.

**Root cause (confirmed against Apple docs + DTS forums).**
`recoverActiveWorkoutSession()` is Apple's **crash-recovery** mechanism, not a
reboot-continuity one (WWDC25 Session 322 frames the feature literally as "Crash
Recovery"). An `HKWorkoutSession` is owned by the system `workoutd` daemon, not
by our app: a crash/force-quit leaves `workoutd` (and the session) alive, so the
app can reattach; a **reboot terminates every process including `workoutd`**, so
no active session exists to return and `recoverActiveWorkoutSession()` yields
nil. Our code is behaving correctly — the launch fallback *does* attempt recovery
(the callback itself is not delivered after a reboot), and the planner correctly
resolves to `resumeLiveWorkout(hasLiveSession: false)` (constrained resume).
Because the pre-reboot session was never taken through `finishWorkout()`, its
staged HR/energy samples are lost with the session; **no `HKWorkout` was saved
for it**, so there is normally nothing in Apple Health to collide with.

This splits into two sub-problems with different verdicts:

- **Live HR / calories after a reboot — unavoidable platform limitation.** There
  is no supported API to resume metric collection into a session that no longer
  exists. The only workaround is to start a *fresh* `HKWorkoutSession` for the
  remainder (`beginCollection(at:)` with the original past start date is
  syntactically possible but the backdate distance is unverified for hours-old
  gaps). It carries real cost: (1) an inherent HR/energy **data gap** for the
  reboot window that no API can fill; and (2) it risks the "one `HKWorkout` per
  `HKMetadataKeyExternalUUID`" invariant that iOS `HealthKitWorkoutReconciler`
  assumes (it maps each fetched workout to an `OrphanedWorkout` keyed by the
  external UUID without de-duping) — so a continuation session must either be
  guarded by `savedWorkoutExists(externalUUID:)` first or mint a distinct UUID
  and teach the reconciler to merge two into one history row.
  **Recommendation: document as a platform limitation; do NOT build the
  continuation session** unless product explicitly wants best-effort partial HR
  data at that cost. GymStreak history stays the primary record and is fully
  preserved either way.

- **Total timer stuck at 00:00 — a genuine, cheap, safe fix (separate from the
  above).** The elapsed-time display need not come from the HealthKit builder
  (there is no HealthKit requirement that it does — the app already computes it
  from a stored `workoutStartDate` in the normal case). On a constrained resume
  the ViewModel can drive the displayed elapsed time from the checkpoint's stable
  `startTime` (wall clock) even with no live session, so the total time keeps
  running. HR/calories would still read "—" (no session), which is the honest
  representation of the platform limitation above. **Recommendation: apply this.**

### Recommended fixes for the open issues (not yet applied — awaiting go-ahead)

1. **Rest timer (issue 1):** add the rest-timer fields (`isResting`,
   `restTimeRemaining`, `restDuration`, `restTimerState`, `isRestTimerMinimized`,
   plus enough to recompute remaining time) to `WatchActiveWorkoutCheckpoint`
   and re-arm the timer in `resumeRecoveredWorkout` from the remaining time. Low
   severity, low risk.
2. **Reboot timer (issue 2, timer half only):** drive the constrained-resume
   elapsed-time display from the checkpoint `startTime`. HR/calories after a
   reboot remain an accepted platform limitation (above).
3. **Pause state (issue 3):** persist `isPaused` in the checkpoint, and in
   `adoptRecoveredSession` read `HKWorkoutSession.state` — if `.paused`, keep it
   paused instead of resuming as running (`.pause()` re-pause is safe;
   `session.state` is a readable property). Low severity.
