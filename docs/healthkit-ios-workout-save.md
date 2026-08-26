# Saving an iPhone Workout to Apple Health

## What it is
How a workout recorded **in the iPhone app** reaches Apple Health, and why it is written once
after the fact instead of being recorded live.

Target: **iOS app only** (`GymStreak`). The watch has its own, independent implementation
(`WatchHealthKitManager`, live `HKWorkoutSession` + `HKLiveWorkoutBuilder`) which is unaffected by
anything here — see [Watch Sync](./watch-sync.md).

Related: [Delete a Recorded Workout](./delete-workout.md), [Watch Workout Recovery](./watch-workout-recovery.md).

## Why it exists in this shape
Two facts drive the design:

1. **The external UUID is the only link between a `WorkoutSession` and its Apple Health workout.**
   `HKMetadataKeyExternalUUID` is stamped at save time and mirrored into
   `WorkoutSession.healthKitWorkoutId`. Everything downstream depends on it: the delete
   confirmation only offers *Delete in GymStreak and Apple Health* when it is non-`nil`,
   `HealthKitWorkoutManager.deleteWorkout(externalUUID:)` looks the workout up by it, and the
   watch-workout recovery ledger correlates on it.
2. **The iPhone has nothing to record live.** No heart-rate sensor, and calories are estimated
   from duration (`estimateCaloriesBurned`, 4.5 kcal/min). A live session would add a background
   dependency and buy nothing.

## How it works

### At workout start — authorization only
`WorkoutViewModel.startWorkout(routine:)` calls `prepareHealthKitAuthorization()`, which only
primes share authorization (skipped under `-UI_TESTING`, when the user disabled Health sync, or
when authorization is already granted). **No `HKWorkoutSession` is created.**

### At completion — one after-the-fact write
`WorkoutViewModel.completeWorkout` → `saveWorkoutToHealthKit(session:)` builds the metadata and
always calls `HealthKitWorkoutManager.saveWorkoutDirectly(...)`:

```
metadata = [
  HKMetadataKeyWorkoutBrandName: routine.name (or "GymStreak"),
  "RoutineName": routine.name,
  "Notes": session.notes            // when non-empty
]
      ↓
HKWorkoutBuilder(.traditionalStrengthTraining, .indoor, device: .local())
  beginCollection(at: session.startTime)
  addSamples([activeEnergyBurned])          // BEFORE endCollection
  addMetadata(metadata + HKMetadataKeyExternalUUID)   // BEFORE endCollection
  endCollection(at: session.endTime ?? Date())
  finishWorkout()
      ↓
session.healthKitWorkoutId = healthKitWorkoutId ; save()
```

**Order is load-bearing.** `endCollection(at:)` "stops the collection of data, sets the workout's
end date, **and deactivates the workout builder**". Samples and metadata must be added before it.

A failure only sets `healthKitSyncStatus = .failed(...)`; the local session is already committed and
is never rolled back. The consequence of a failure is a session with `healthKitWorkoutId == nil`,
which correctly presents a single *Delete* in the delete confirmation.

**Nothing surfaces a failed write to the user.** `healthKitSyncStatus` is written by the ViewModel
and read by no view, so a refused Health write is silent — the workout simply never appears in
Health and the delete confirmation quietly drops the Apple Health option. This is a known gap, not
a decision; the delete side has `HealthDeleteFailureBanner` and the save side has no equivalent.

### Sharing authorization is per type
`isAuthorized` reflects **only** `HKObjectType.workoutType()`. This save writes two types, and
Apple Health can allow one while refusing the other:

| Type | Needed for | If refused |
| --- | --- | --- |
| `workoutType()` | `beginCollection` / `finishWorkout` | nothing is written; the whole save fails |
| `activeEnergyBurned` | the `addSamples` energy sample | **the sample is skipped and the workout is still saved** |

The energy write is therefore guarded by `canShareActiveEnergy` (its own
`authorizationStatus(for:) == .sharingAuthorized`) *and* wrapped in its own `do/catch`. A calorie
figure is a nice-to-have; the workout record carries the routine name and the external UUID that
the delete confirmation, the recovery ledger and Fitness's display all depend on, so it must never
be lost to a refused sample.

Because HealthKit reports the same `errorAuthorizationDenied` (`HKError` code 4) for every write, the
failure log names the awaited call — `Failed to save workout directly at <step>: …` — otherwise
"Not authorized" cannot be attributed to a step.

## Root cause: iPhone workouts had no routine name and no external UUID (fixed 2026-08-24)

### Symptom
For a workout recorded **on the iPhone**:
- Apple Health/Fitness listed it under the generic activity name (`Traditionelles
  Krafttraining` / "Traditional Strength Training") instead of the routine name, while
  watch-recorded workouts correctly showed `Push` / `Pull`.
- Deleting it in GymStreak offered only a single *Delete* — never the *Delete in GymStreak and
  Apple Health* choice, which watch-recorded workouts did offer.

The generic name is the fingerprint: **no metadata reached the workout**, and the external UUID
travels in that same metadata dictionary.

### Cause
`saveWorkoutToHealthKit` had two branches and took the wrong one. If `healthKitManager.isWorkoutActive`
it called `endWorkoutSession(...)`, otherwise the `HKWorkoutBuilder` fallback. On iPhone the manager
*did* start a live session at workout start, so the session branch is the one that ran, and it was
broken in three ways:

1. It called `session.end()` **before** any builder call, driving the session terminal while the
   builder work was still pending — an interaction Apple does not document.
2. It called `addSamples(_:)` and `addMetadata(_:)` **after** `endCollection(at:)`, i.e. after the
   builder was deactivated. This is the inverse of Apple's canonical order and of what
   `saveWorkoutDirectly` already did correctly.
3. It never called `stopActivity(with:)`, so the workout's `HKWorkoutActivity` never got an end
   date. `HKWorkout.duration` is aggregated from its activities, not from the collection interval.

The net effect: the workout landed in Health without metadata and the app got an error instead of
the external UUID, so `session.healthKitWorkoutId` stayed `nil`.

**This never worked for iPhone-recorded workouts** — it is not a regression of the delete feature.
The delete confirmation, `deleteWorkout(_:alsoFromHealthKit:)` and
`HealthKitWorkoutManager.deleteWorkout(externalUUID:)` were intact the whole time; they simply had
nothing to correlate on. The reason it looked like a regression is that the option *does* work for
watch-recorded workouts, which is how the app is normally used.

Why the broken branch was reachable at all: `HKWorkoutSession(healthStore:configuration:)` and
`HKLiveWorkoutDataSource` only became available on **iOS 26.0**, and this project has targeted
iOS 26 since the HealthKit integration landed (`2b7aa24`, 2025-11-18). Before iOS 26 an iPhone
could not originate a workout session at all, so this code shape could not have shipped on an
earlier target.

### Fix
Removed live-session recording from the iOS target entirely and made the after-the-fact builder
save the single write path:

- `WorkoutViewModel`: `startHealthKitSession()` → `prepareHealthKitAuthorization()` (no session
  start); `saveWorkoutToHealthKit` always calls `saveWorkoutDirectly`; `cancelWorkout()` no longer
  cancels a session that is never started.
- `HealthKitWorkoutServicing`: dropped `isWorkoutActive`, `startWorkoutSession()`,
  `cancelWorkoutSession()`, `endWorkoutSession(...)`.
- `HealthKitWorkoutManager`: dropped those methods plus `pauseWorkoutSession`/`resumeWorkoutSession`,
  the `HKWorkoutSession`/`HKLiveWorkoutBuilder` properties, the `HKWorkoutSessionDelegate` and
  `HKLiveWorkoutBuilderDelegate` conformances (and therefore its `NSObject` base), and the
  now-unreachable `HealthKitError` cases `workoutAlreadyActive` / `noActiveWorkout` /
  `sessionStartFailed`.

The dead code was removed rather than left in place because `isWorkoutActive` is what selected the
broken branch — keeping the flag keeps the trap.

### Discarded alternative: fix the live session instead
Rejected. Making it correct would need Apple's full lifecycle (`prepare()` → `startActivity` →
`stopActivity` → add samples/metadata → `endCollection` → `finishWorkout` → `session.end()`) **and**
the `workout-processing` background mode, which the iOS target does not declare (only the watch's
`WKBackgroundModes` does). Without that mode an iPhone workout session does not survive the app
being backgrounded — locking the phone mid-workout in a gym is the normal case. The payoff would be
live energy on a device with no heart-rate sensor, for calories the app estimates anyway.

To restore live iPhone tracking later: re-add `UIBackgroundModes: workout-processing` to the app
target, then reinstate the session lifecycle in Apple's order — the removed code is in git history
before this change (`GymStreak/Data/HealthKit/HealthKitWorkoutManager.swift`), but note it is the
*broken* order and should not be copied back verbatim.

### Second blocker, found on device the same day: `errorAuthorizationDenied`
Removing the live-session branch exposed a failure the old path had been masking. On a physical
iPhone with the fix in place, a phone-recorded workout reached Health **not at all**:

```
Failed to save workout directly: Error Domain=com.apple.healthkit Code=4 "Not authorized"
Failed to sync workout to HealthKit: saveFailed("Not authorized")
```

That print comes from inside `saveWorkoutDirectly`'s `catch`, so the app's own
`guard isAuthorized` had already passed — Workouts *write* was granted and HealthKit itself refused
one of the builder calls. The only other type in the sequence is `activeEnergyBurned`, so a
per-type denial of Active Energy is the cause consistent with all the evidence: it also explains
why the old session path still produced *something* (it added the sample **after** `endCollection`,
where the throw could no longer prevent the already-collected workout from being persisted).

Fixed by making the energy sample non-fatal (see "Sharing authorization is per type" above) and by
naming the failing step in the log. **Confirmed on device the same day:** with the sample guarded
and no other change, the workout saved with its routine name and became deletable from Apple Health
— which settles the attribution, since only the energy write stopped being required.

The lesson generalizes beyond this bug: a HealthKit write sequence that mixes types fails as a unit
under a per-type denial, so an optional sample must be added defensively or the primary record is
lost with it. Note also what the old code's *wrong* call order was accidentally providing — writing
the sample after `endCollection` meant its failure could not block the workout. Doing it in the
correct order made the sample's authorization newly load-bearing, which is why this surfaced only
after the first fix.

### Consequence: iPhone workouts now enter the recovery ledger
Stamping the external UUID has a side effect worth knowing about. `HealthKitAnchoredWorkoutDrain.facts(from:)`
admits a workout into the [watch-workout recovery](./watch-workout-recovery.md) ledger when it is
GymStreak-authored **and** carries `HKMetadataKeyExternalUUID`. Before this fix, iPhone-written
workouts were filtered out by the second condition — accidentally. They now qualify, so phone
workouts flow through the ledger for the first time.

On the normal path this is inert: `session.healthKitWorkoutId` is saved in the same `Task`
immediately after `finishWorkout()`, so the observer-triggered drain finds committed history and
reconciles the candidate to `.resolvedByHistory` (the 60 s grace period covers the race), and
`WorkoutRecoveryReconciler.decide` returns `.resolve` for terminal states before evaluating
anything else.

Residual exposure, both narrow: if the SwiftData `save()` right after the write fails — or the app
dies in the millisecond window between `finishWorkout()` and it — or if the drain first discovers
the workout only *after* the user deleted the session with *Delete in GymStreak Only*, then a
phone-authored workout can be offered in the pending-sync banner and confirming it creates a
placeholder session alongside the real one. Note that phone workouts have no receipt fallback:
only `WatchWorkoutIngestionCoordinator` writes `WorkoutIngestReceipt`s. This is untested and
accepted rather than guarded — the offer ("this workout is in Health but not in the app") is not
wrong in itself, and the window is small.

**Rejected guard: filtering the ledger on `fromWatch == false`.** It looks like the obvious fix and
it would break recovery outright. `DiscoveredWorkoutFacts.fromWatch` is derived from
`bundleId.hasSuffix(".watchkitapp")`, but a workout recorded by the watch app is saved with the
**iPhone app's** bundle identifier — confirmed on a physical device on 2026-07-26
([delete-workout.md](./delete-workout.md), "Watch-recorded workouts"). So `fromWatch` does not
reliably identify watch provenance, which is exactly why the existing code uses it for diagnostics
only and why `decide` ignores it. Any future provenance filter must key off something other than
the source bundle id.

### Deliberately not changed
- **Existing broken Health entries are not repaired.** Workouts already written by the old path
  carry no external UUID, so they stay un-correlatable and their delete keeps offering a single
  *Delete*. They can be removed by hand in the Health app. A migration would have to guess
  ownership from timestamps, which is worse than leaving them.
- `WorkoutDetailView.loadHealthKitKcal()` still constructs its own `HKHealthStore()` inline — a
  pre-existing layer violation, untouched here (also noted in [delete-workout.md](./delete-workout.md)).
- Read authorization for `HKObjectType.workoutType()` is still requested, but the delete path no
  longer depends on it: since 2026-08-26 `deleteWorkout(externalUUID:)` uses
  `deleteObjects(of:predicate:)`, which needs only *share* authorization. It also re-requests that
  authorization in place when this install has never been asked — the state a reinstalled app is in,
  because `healthKitWorkoutId` comes back over CloudKit while the grant does not. Root cause and
  fix in [delete-workout.md](./delete-workout.md).

## HealthKit research findings (iOS 26)
Verified against Apple's documentation and WWDC25 before the fix. **Do not re-research these.**

- **`HKWorkoutSession(healthStore:configuration:)` — iOS 26.0+** (watchOS 5.0+); the class itself and
  `startActivity(with:)` annotate iOS 17.0+, which is the older, narrower **mirroring** surface
  (`startMirroringToCompanionDevice` on the watch, `workoutSessionMirroringStartHandler` on iOS).
  Originating a standalone workout session on iPhone/iPad is what iOS 26 newly enables.
- **`HKLiveWorkoutDataSource` — iOS 26.0+.** It does collect on iPhone, but heart rate requires an
  external Bluetooth sensor since the phone has none.
- **`HKWorkout.duration` aggregates its `HKWorkoutActivity` objects**, spanning the earliest
  activity's start to the latest activity's end — not the builder's collection interval. Every
  `HKWorkout` has at least one activity; HealthKit synthesizes one matching the activity type if the
  app sets none. `startActivity(with:)` sets that activity's start date and `stopActivity(with:)`
  sets its end date, so skipping `stopActivity` leaves the activity without an end date. *(The last
  step — skipping `stopActivity` collapsing the displayed duration — is a well-evidenced inference
  from those two documented facts, not a verbatim Apple statement.)*
- **Canonical end-of-workout order** (Apple's "Running workout sessions" article + the WWDC25
  sample): `stopActivity(with:)` → await the `.stopped` state change → `addSamples` → `addMetadata`
  → `endCollection(at:)` → `finishWorkout()` → `session.end()` last. Apple's sample also calls
  `session.prepare()` before `startActivity`.
- **Adding samples/metadata after `endCollection` is not *explicitly* documented as an error**, and
  the only stated prohibition in the `HKWorkoutBuilder` header is calling `addSamples` after
  `finishWorkout`. But `endCollection` is documented to "deactivate the workout builder" and no
  Apple sample ever adds afterwards, so the app must not rely on it. Same contract for
  `HKLiveWorkoutBuilder` (a subclass).
- **Ending a session does not persist a workout by itself.** `finishWorkout()` is documented as
  what "creates and saves an `HKWorkout`".
- **`HKWorkoutBuilder` (no session) is not deprecated** and remains a legitimate way to save a
  completed workout after the fact on iOS 26; `HKWorkoutActivity` (iOS 16+) is additive.
- **iPhone workout sessions need the `workout-processing` background mode.** The watch target
  declares it (`WKBackgroundModes`); the iOS target declares only `remote-notification`.

Sources: [HKWorkoutSession](https://developer.apple.com/documentation/healthkit/hkworkoutsession) ·
[init(healthStore:configuration:)](https://developer.apple.com/documentation/healthkit/hkworkoutsession/init(healthstore:configuration:)) ·
[startActivity(with:)](https://developer.apple.com/documentation/healthkit/hkworkoutsession/startactivity(with:)) ·
[stopActivity(with:)](https://developer.apple.com/documentation/healthkit/hkworkoutsession/stopactivity(with:)) ·
[Running workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions) ·
[HKWorkoutBuilder](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder) ·
[endCollection(withEnd:completion:)](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/endcollection(withend:completion:)) ·
[HKWorkoutActivity](https://developer.apple.com/documentation/healthkit/hkworkoutactivity) ·
[HKLiveWorkoutDataSource](https://developer.apple.com/documentation/healthkit/hkliveworkoutdatasource) ·
[WWDC25 session 322 — Track workouts with HealthKit on iOS and iPadOS](https://developer.apple.com/videos/play/wwdc2025/322/)

## Architecture
- `GymStreak/Domain/Interfaces/HealthKitWorkoutServicing.swift` — the gateway protocol
  (`@MainActor`), now authorization + save + delete + calorie estimate only.
- `GymStreak/Data/HealthKit/HealthKitWorkoutManager.swift` — the only implementation; the sole
  place that touches `HKHealthStore` for workout writes. 218 lines after the removal.
- `GymStreak/Presentation/ViewModels/WorkoutViewModel.swift` — `prepareHealthKitAuthorization()`
  and `saveWorkoutToHealthKit(session:)`.
- `GymStreak/App/AppDependencies.swift` — `makeHealthKitWorkoutService()` returns a fresh
  `HealthKitWorkoutManager()` per `WorkoutViewModel`; **unchanged**, no new wiring.

Layer compliance: the capability is declared in `Domain/Interfaces/`, implemented in `Data/HealthKit/`,
consumed in `Presentation/` through the injected protocol. No `@Model`/schema change, no migration.

## Watch target
**Unchanged.** The watch keeps its live `HKWorkoutSession`/`HKLiveWorkoutBuilder` recording — it has
the `workout-processing` background mode, real sensors, and its own metadata stamping
(`WatchHealthKitManager.endCollectionAndAddMetadata(externalId:)`), which is why watch workouts
always carried the routine name and the external UUID. Per-target duplication means the iOS removal
cannot affect it.

## Tests
`GymStreakTests/WorkoutViewModelTests.swift`:

- `completingWorkoutStampsExternalUUIDAndRoutineNameForItsHealthCounterpart` — completing a workout
  performs exactly one `saveWorkoutDirectly`, stores the returned external UUID on the session, sends
  the routine name as `HKMetadataKeyWorkoutBrandName`, and passes the session's real end time. This is
  the regression guard: it fails if completion ever routes through a live session again.

`GymStreakTests/Support/MockHealthKitWorkoutServicing.swift` records every `saveWorkoutDirectly` call
(dates, energy, metadata, returned id) and can be made to throw via `saveError`.

The five delete-path tests in the same file continue to cover what happens *once* a session carries
an external UUID (see [delete-workout.md](./delete-workout.md)).

## Verification
- `xcodebuild build -scheme GymStreak` — succeeded.
- `bundle exec fastlane test_unit_ios` — full iOS suite passed, including the new test. The watch
  suite was not run: no watch code is touched by this change.
- **Device validation — PASSED** (physical iPhone, 2026-08-24). A workout recorded on the phone:
  1. reached Apple Health under its **routine name** (not the generic "Traditionelles
     Krafttraining"),
  2. offered *Delete in GymStreak and Apple Health* in the delete confirmation, and
  3. was actually removed from Apple Health on confirming.

  This closes the loop end to end and confirms the per-type authorization diagnosis: the save
  started succeeding as soon as the `activeEnergyBurned` sample stopped being a hard requirement,
  with nothing else changed. `finishWorkout()` and `beginCollection` were never the refused writes.
