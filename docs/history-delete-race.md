# The History delete race (SwiftData cross-context invalidation)

A shipped crash, its diagnosis from the device's own database, and the gate that fixes it.
Diagnosed 2026-08-29 against build 1.1.12 (1003) on iOS 26.6, iPhone 16 Pro Max.

## The crash

```
data store did not return a snapshot for: PersistentIdentifier(id: SwiftData.PersistentIdentifier.ID(
  backing: …managedObjectID(0x90ba15765f3b293e <x-coredata://8B5F190C-…/WorkoutExercise/p385>)))
SwiftData/BackingData.swift:1039: Fatal error: This model instance was invalidated because its
backing data could no longer be found the store.
```

Reported as "happened after deleting a routine". **This particular crash was not a routine
deletion** — see the evidence below — because deleting a routine cannot reach a `WorkoutExercise`:
`Routine.workoutSessions` carries no delete rule, so SwiftData's default `.nullify` applies and
history survives by design (`Models.swift:10-11`, `:330-334`).

The instinct was still half right, though, and worth stating plainly: routine deletion posts
`.historySourceDataDidChange`, which bumps `historyVersion` and starts the very same History
rebuild that crashed — *and* the actor's graph contains `Routine` and `RoutineExercise` rows of its
own (the session fetch prefetches `\.routine`, `HistorySnapshotBuilder` faults `session.routine?.id`
mid-walk, and `fetchLiveRoutineSlotIds` walks `routine.routineExercisesList`). So a routine delete
landing inside a rebuild is the identical trap on a different entity. `RoutinesViewModel.deleteRoutine`
is gated for that reason; see "Known residual exposure" for the routine writers that are not.

## How it was diagnosed

No `.ips` existed: the debugger was attached, so lldb caught the trap and no crash report was
written. The device's SwiftData store was read instead.

The store is **not** in the app data container — `ModelConfiguration`'s `groupContainer` defaults to
`.automatic`, and the app holds exactly one App Group, so SwiftData put it in
`group.com.gymstreak.shared/Library/Application Support/default.store`.

```bash
# NOTE: `info files` takes --username, `copy from` takes --user. See docs/crash-report-retrieval.md.
xcrun devicectl device info files --device "iPhone von Julian" \
  --domain-type appGroupDataContainer --domain-identifier group.com.gymstreak.shared \
  --username mobile

for f in default.store default.store-shm default.store-wal; do
  xcrun devicectl device copy from --device "iPhone von Julian" \
    --domain-type appGroupDataContainer --domain-identifier group.com.gymstreak.shared \
    --user mobile --source "Library/Application Support/$f" --destination "./store/$f"
done
```

Copy **all three** files (store, `-shm`, `-wal`) into one directory — sqlite3 replays the WAL only
when it finds it alongside the main file, and the most recent transactions live there.

CloudKit mirroring turns on Core Data **persistent history**, which is the whole diagnosis: the
`ATRANSACTION` / `ACHANGE` tables record every insert (`ZCHANGETYPE` 0), update (1) and delete (2)
with a timestamp and an author.

```sql
-- Life story of the row named in the crash. Z_ENT 8 = WorkoutExercise (see Z_PRIMARYKEY).
SELECT c.ZCHANGETYPE,
       datetime(t.ZTIMESTAMP + 978307200, 'unixepoch', 'localtime') AS ts
FROM ACHANGE c JOIN ATRANSACTION t ON c.ZTRANSACTIONID = t.Z_PK
WHERE c.ZENTITY = 8 AND c.ZENTITYPK = 385;
-- 0 | 2026-08-28 22:42:28     inserted
-- 2 | 2026-08-29 00:19:14     deleted
```

Author and context name are interned — join `ATRANSACTIONSTRING` on `ZAUTHORTS` / `ZCONTEXTNAMETS` /
`ZBUNDLEIDTS`, not the (always null) `ZAUTHOR` text columns. Doing so proved the delete was a local
app write and **not** a CloudKit import (author would read `NSCloudKitMirroringDelegate.import`).

What the last transactions actually contained:

| txn | time | contents |
|---|---|---|
| 112 | 28.08. 22:42:28 | insert `WorkoutSession` 60 + 7 `WorkoutExercise` (382–388, incl. **385**) + 20 `WorkoutSet` |
| 113 | 28.08. 22:45:37 | insert `WorkoutSession` 61 + 7 exercises + 20 sets |
| 114 | 29.08. **00:19:10** | **delete** `WorkoutSession` 59 + 7 exercises + 24 sets |
| 115 | 29.08. **00:19:14** | **delete** `WorkoutSession` 60 + 7 exercises **incl. 385** + 20 sets |

No `Routine` was deleted that day (the last two were 27.08.). Two **workouts** were deleted from
History, four seconds apart, and the app trapped on the second.

## Root cause

1. Delete #1 (00:19:10) → `WorkoutViewModel.deleteWorkout` → `save()` → `refreshHistory()` bumps the
   `@Published historyVersion` → `HistoryView`'s `.task(id: dataToken)` starts a rebuild on the
   History `@ModelActor`.
2. `SwiftDataHistorySnapshotStore.fetchTrainingSnapshot` runs `CompletedSessionFetch.withFullGraph`,
   pulling **every** completed `WorkoutExercise` (341 rows here) and session into *its own*
   `ModelContext`, then walks `session → workoutExercises → sets` **synchronously** through
   `PersonalRecordService.computePRs` and `HistorySnapshotBuilder.build`.
3. Delete #2 (00:19:14) lands on the **main** `ModelContext` mid-walk and cascades rows 382–388 away.
4. The actor's next fault on `WorkoutExercise/p385` finds no row → uncatchable `fatalError`.

`Task.checkCancellation()` does not help. `.task(id:)` does cancel the superseded rebuild, but the
checks sit only *between* the coarse phases and `HistorySnapshotBuilder.build` is one uninterrupted
walk — cancellation is cooperative, the delete is not.

The crash names the **child**, not the session, because the parent was still resolvable while the
cascade-deleted children were not.

## Why serialization is the only fix

Researched against Apple's docs and DTS forum answers, 2026-08-29:

- **No query generations.** Core Data's `NSManagedObjectContext.setQueryGenerationFrom(.current)` —
  which pins a context to a consistent store snapshot and is exactly the mechanism for this — has no
  SwiftData counterpart. Apple DTS, on this precise scenario: *"SwiftData doesn't have query
  generations, and so I don't see an ideal pattern to handle the kind of issue."*
  ([forums/thread/800316](https://developer.apple.com/forums/thread/800316))
- **No cross-context merge.** `ModelContext` has no `automaticallyMergesChangesFromParent`. The
  iOS 18 History API (`fetchHistory`, `HistoryToken`) only *reports* changes; it never invalidates or
  refreshes live objects another context holds. (`HistoryObserver` is iOS 27 beta — not available on
  our 26.1 target, and it surfaces events rather than guaranteeing safe materialization.)
- **`isDeleted` is useless here.** It reflects only a delete staged in the object's *own* context, and
  resets to `false` once the deleting context saves. The actor never called `delete` on its copies, so
  it stays `false` right up to the trap. `registeredModel(for:)` only reports in-memory registration
  and `model(for:)` fabricates a placeholder — neither tests whether the row still exists.
- **The trap is not catchable.** It is an unconditional `fatalError` inside SwiftData's lazy backing-
  data resolution, not a throwing API. No `do/catch`, delegate or notification reaches it.
- **`relationshipKeyPathsForPrefetching` is not a shield.** It removes N+1 *queries*; it does not copy
  data out of the store's reach, and another context's save can turn a materialized object back into a
  fault.

So the reads and the writes have to be made mutually exclusive by the app. That is DTS's own
recommendation, and it is what `HistoryStoreGate` does.

Apple DTS, on the main-actor-vs-model-actor case specifically: *"The only issue is that you may hit
a conflict when the main actor and a model actor access the data store simultaneously. If this can
happen in your case, you might consider avoiding that carefully."*
([forums/thread/805409](https://developer.apple.com/forums/thread/805409)) — the problem named, and
avoidance prescribed, with no primitive offered.

### Confirmed by experiment, not only by inference

The diagnosis above was reached from persistent history alone. It was afterwards **reproduced**, with
a throwaway probe against an on-disk store and two `ModelContext`s (2026-08-29). Three cases, and the
two negative results matter as much as the positive one:

| case | sequence | result |
|---|---|---|
| delete lands **while** the reader holds the materialized graph, walk continues over held objects | mid-walk — the shipped crash | **trapped**, identically |
| whole session deleted **between** two walks of the same long-lived context | re-fetch, then walk | passed, 18 sets, no trap |
| single `WorkoutSet` deleted between walks, its exercise and session **surviving** | re-fetch returns the registered parent | passed, 26 sets, no trap |

The reproduction is exact — same message, same entity type, and the stack names the `@Persisted`
macro's generated getter:

```
data store (…) did not return a snapshot for: PersistentIdentifier(…<…/WorkoutExercise/p8>)
SwiftData/BackingData.swift:1039: Fatal error: This model instance was invalidated…
  4  GymStreak.debug.dylib  WorkoutExercise.exerciseName.getter + 160
     (@__swiftmacro_…WorkoutExerciseC12exerciseName18_PersistedPropertyfMa_.swift:9)
```

**The two passing cases are the load-bearing finding.** The `@ModelActor`'s `ModelContext` is created
once and lives for the whole app session — never reset, never rolled back — so the obvious worry is
that it accumulates stale registered objects and stale materialized to-many relationships between
locked sections, in which case a mutex would be *necessary but not sufficient* and the real fix would
be a fresh `ModelContext(container)` per read. It does not. Re-running `CompletedSessionFetch`'s
fetches refreshes the registered objects and their relationship caches, including the sharper case
where the parent survives and only a child was deleted. Secondary sources claim the opposite; on this
codebase's actual fetch path they are wrong.

That is what makes serialization **sufficient** here rather than merely necessary, and it is why the
gate does not also need to discard the actor's context between passes. If that fetch path ever
changes — a walk that traverses relationships it did not just fetch, or objects retained across
calls — this conclusion has to be re-tested, because it is a property of the fetch, not a guarantee
from Apple.

The probe was deliberately not kept: case 3 kills the test runner rather than failing an assertion
(the trap is an uncatchable `fatalError`), so it cannot live in the suite. `HistoryStoreGateTests`
asserts the gate's properties instead.

## The fix

`GymStreak/Domain/Services/HistoryStoreGate.swift` — an exclusive, FIFO, non-reentrant async gate.
`AppDependencies` owns the one instance. The three Data-layer providers take it **without a
default**, because a provider handed its own gate compiles, looks wired and excludes nothing;
tests opt out visibly with `HistoryStoreGate.unshared()`. `acquire()` is deliberately not
cancellation-aware — see the comment there for the latency trade that buys.

- **Readers:** every method of `SwiftDataHistorySnapshotProvider` **and of `ChatFactProvider`**
  wraps its model-actor call in `gate.withAccess { … }`. The chat fact actor is a *second*
  `@ModelActor` with its own `ModelContext`, but two of its three reads go through the same
  `CompletedSessionFetch.withFullGraph`, so it was exposed to exactly the same race. Both are
  handed the **same** `AppDependencies.historyStoreGate` instance — two gates over one store
  serialize nothing against each other. `withAccess` is `nonisolated`, so under SE-0461 it runs on the caller's
  executor — inside a `@concurrent` provider method that is the global executor, preserving the
  off-main guarantee documented in `docs/swift6-concurrency.md` §1. It must **not** be an isolated
  method that awaits the body, because actor reentrancy would then let a second caller in — which is
  precisely the exclusion the type exists to provide.
- **Writers:** the two `WorkoutViewModel` methods that delete rows of a **completed** session take it
  — `deleteWorkout(_:)` and `saveEditedWorkout(_:exerciseDrafts:updateTemplate:)` (its step 1 deletes
  `WorkoutSet` rows). Both became `async` as a result.
- **Conditionally gated:** `cancelWorkout`, `removeSetFromExercise`, `removeExerciseFromWorkout`
  and `swapExercise` route their deletes through `withHistoryGateIfVisible`, which takes the gate
  only when `session.endTime != nil`.

  This is the correction of a wrong first attempt, and it is the subtlety of the whole change.
  The first version excluded these outright, reasoning that in-workout rows have `endTime == nil`
  and so are never in the actor's graph. **That is false.** `WorkoutViewModel.pauseForCompletion()`
  sets *and saves* `session.endTime` when the user taps Finish — and automatically the moment the
  last set is completed — while the session remains `currentSession` and fully editable;
  `resumeAfterCompletionPrompt()` ("Continue workout") never clears it, and nothing else assigns
  `endTime` afterwards. In that window an ordinary set deletion removes rows the History actor is
  walking, and a rebuild can be in flight for reasons unrelated to what the user is doing (the
  CloudKit remote-change fan-out calls `refreshHistory()` too). Testing `endTime != nil` at the
  call site rather than assuming it keeps the common case free — during a normal workout nothing
  waits on a rebuild — while closing the hole.

- **Also gated:** `SwiftDataLegacyHistoryAttributionProvider`, a third `@ModelActor`, which fetches
  `WorkoutExercise` rows and then traverses `workoutSession?.endTime` on each before writing; and
  `RoutinesViewModel.deleteRoutine`, whose cascade removes `RoutineExercise` rows the actor holds.

- **The `Exercise` table writers** — added in a second pass, once it was noticed that the actor
  fetches the **entire** `Exercise` table three times over
  (`SwiftDataHistorySnapshotStore.swift:254`, `:302`, `:344`, in `fetchFortschrittSnapshot`,
  `fetchExerciseProgress` and `fetchPreviousPerformances`). Deleting an `Exercise` is therefore
  exactly as dangerous as deleting a `WorkoutExercise`, which the first pass had missed:
  `ExercisesViewModel.confirmDeleteExercise` and `confirmDeleteAllExercises` are now `async` and
  gated, and `DefaultContentSeeder.deduplicate` is covered by gating that seeder's whole `run()`.

- **The launch seeders.** `DefaultContentSeeder.run()` and `ExampleRoutineSeeder.run()` are `async`
  and take the gate around the entire pass (`runLocked()` holds the old body unchanged). They delete
  duplicate `Exercise` rows and superseded/duplicate `Routine` rows respectively, and they run at
  launch — precisely when a History rebuild can already be in flight. `GymStreakApp` awaits the two
  in one `Task`, preserving the load-bearing ordering (catalog → example routine → catalog sync).
  `recoverStrandedLibraryIfNeeded` needs no gate: it only inserts.

- **`completeWorkout(updateTemplate:notes:)`.** The `updateTemplate` branch calls
  `RoutineTemplateSyncService.applyPerformedValues(reconcileExerciseMembership: true)`, which
  **deletes** `RoutineExercise` and `ExerciseSet` rows — and by then `pauseForCompletion()` has
  already persisted `endTime`, so the session is in the actor's fetch as well. `SaveWorkoutView`
  awaits it before dismissing and gained an `isSaving` flag, because that reconciliation is **not
  idempotent** and the sheet now stays up across the wait. (The other `applyPerformedValues` caller,
  `commitEditedWorkout`, was already inside the gate.)

- **The whole watch ingestion drain**, which closes what the first pass listed as residual.
  `WatchWorkoutIngestionCoordinator.drainInbox()` and `routineAuthorityDidChange()` are `async` and
  take the gate around the **entire** pass; the pass itself
  (`drainInboxLocked()`) stays exactly as synchronous as it was. That is the point: the reentrancy
  coalescing, the oldest-first ordering and the one-save-per-entry commits gain **no** suspension
  point, so none of their invariants change — only the entry points moved. This is what makes it
  safe to gate ordering-critical code that could not otherwise be made `async` without restructuring
  it. Two deleters come under the gate for free: `WatchWorkoutIngestionService.stageHistory` (the
  HealthKit-recovered placeholder session it supersedes) and
  `WatchTemplateTransactionService.liveRoutine` (a legacy placeholder `Routine`), plus the
  `RoutineExercise`/`ExerciseSet` deletions in `WatchTemplateTransactionService+Structural`.

  **The internal follow-up pass must call `drainInboxLocked()`, never `drainInbox()`** — the gate is
  not reentrant and re-entering it there would deadlock the pipeline permanently.

Two suspension bugs were introduced by making these methods `async` and then fixed — both are the
kind that only exists once a synchronous block gains an `await` in the middle:

- `cancelWorkout` cleared `currentSession` *after* the gated delete. `withAccess` suspends again on
  `release()`, and `ActiveWorkoutView` — still mounted through the dismissal — does
  `if let session = viewModel.currentSession` and walks its exercises. It now unpublishes the
  session before deleting it.
- `removeSetFromExercise` computed a positional index before the gate and used it after. Another
  edit queued behind the same gate would make that index wrong or out of bounds; it now matches on
  `id` inside the closure.

Row-removal animations moved from the call sites into the ViewModel: `withAnimation { Task { … } }`
animates nothing, because the `Task` body lands in a later transaction.
- `refreshHistory()` is called **outside** the gate: it only bumps a counter, and the rebuild it
  starts must be free to take the gate itself.

### The view-side half

`dismiss()` does not unmount a view synchronously, and the delete is now `async`, so the window in
which a detail screen can re-read a tombstoned model got *longer*. Three call sites were hardened:

- `WorkoutDetailView` — content moved into a `content` property behind a new `isBeingDeleted` @State
  flag, set before `dismiss()`. Its `body` walks `workout.workoutExercisesList` twice
  (`qualifyingOverloadExercises`, `exercisesSection`) and it observes the same `WorkoutViewModel`
  whose `historyVersion` the delete bumps, so it *will* be re-evaluated mid-pop. The
  `.deleteWorkoutConfirmation(hasHealthKitWorkout:)` argument sits outside that guard and is
  short-circuited with `!isBeingDeleted &&` for the same reason.
- `HistoryView` — `workoutToDelete` is cleared *before* the `await`, because the alert's
  `hasHealthKitWorkout:` argument reads that same `@Model` on every re-render.
- `EditWorkoutSessionView` — awaits the commit *before* dismissing. `WorkoutDetailView` reloads
  its derived state from this sheet's `onDismiss`, so dismissing first raced that reload against a
  commit still queued behind a rebuild and could leave the detail screen on pre-edit values with
  nothing to re-trigger it. Staying presented meanwhile is safe: that body renders only the
  value-type drafts and never reads `workout`.

The gate does **not** cover main-actor continuations, so `WorkoutDetailView`'s loaders needed the
same flag: `loadAppliedOverloads` and `loadComparisons` both walk the session's exercises *after*
their own `await`, by which point a delete may have committed. Each now re-checks `isBeingDeleted`
on resume — sound because the flag is set on the main actor before the delete task is even created,
so seeing it `false` after a resume means the session is still alive. `deleteWorkout` also calls
`analysisVM.cancel()`: the coach analysis stream task captures the `WorkoutSession` and reads its
graph across several suspensions, and nothing used to stop it when the screen went away.

### Tests

`GymStreakTests/HistoryDeleteRaceRegressionTests.swift` is the canary, and it is the only test
that would notice a *reader* quietly dropping the gate. It runs the real
`SwiftDataHistorySnapshotProvider` over a real on-disk store while the real
`WorkoutViewModel.deleteWorkout` cascades rows out from underneath it, 12 iterations, three
deletes per iteration fired at 25/50/75 ms into the walk.

**It does not fail red — it kills the runner.** The trap is an uncatchable `fatalError`, so a
crashed run *is* this test failing. That is also why the raw reproduction cannot live in the
suite: it would take every other test with it.

Two tuning lessons, both measured, because a race test that never races is worse than no test:

| variant | detection of the ungated regression |
|---|---|
| one delete, fired immediately | 2 runs in 5 |
| one delete, after warming the provider | **0 in 8** — warming shrinks the walk, closing the window |
| one delete, 30 ms head start | 4 in 6 |
| **three deletes at 25/50/75 ms** | **8 in 8** |

The warm-up was actively harmful and the single well-timed delete is a guess: fire it too early
and it commits before the model actor has finished starting up, too late and the walk is over.
Spreading several across the walk removes the need to know how long the walk takes on the
machine running it. Verified red by handing the provider `HistoryStoreGate.unshared()` instead
of the shared instance — precisely the "looks wired, excludes nothing" mistake the initialisers
are shaped to prevent.

`GymStreakTests/HistoryStoreGateTests.swift`. The crash itself cannot be asserted — reproducing it
would `fatalError` the test runner rather than fail a test — so the tests pin the two properties that
make it impossible: the gate is exclusive under contention (`maxConcurrent == 1` across 12 racing
holders, all completing), it releases on the throwing path, and `WorkoutViewModel.deleteWorkout`
genuinely blocks while another holder has the gate.

### Two ordering bugs the `async` conversion introduced

Both are the same shape — making something `async` silently moved when it runs — and both were
caught in review rather than by a test:

- **A bare `Task { … }` does not preserve enqueue order.** The watch drain's call sites were
  first written `Task { await ingestion?.drainInbox() }`. SE-0431 guarantees creation-order
  start only for closures with an **explicit** isolation marker and deliberately excludes
  implicitly-isolated ones, so that spelling still ran on the main actor but with unspecified
  ordering. They are now `Task { @MainActor in … }`. The practical exposure was narrower than
  it first looked — payload order comes from `inbox.entries()` sorting by arrival timestamp,
  not from task scheduling — but the explicit form is free and strictly stronger. See
  `docs/swift6-concurrency.md` §4 for the full scoping.
- **`recovery?.reconcile()` fell outside the drain.** It used to run after a synchronous
  `drainInbox()`; wrapping the drain in a `Task` left it running *before*. It reads
  `healthKitWorkoutIDs()` and `pendingWorkouts()`, both of which the drain mutates. It now sits
  inside the task, after the `await`.

### Where the gate has to be taken

Anything that walks the completed-session graph off the main actor, and anything that deletes a row
the History actor can hold. `CompletedSessionFetch.withFullGraph`'s own doc comment says so for the
readers, since it is the shared entry point both reader actors go through.

For writers, the graph is **wider than the completed-session tree**, which is what the first pass
got wrong. `fetchTrainingSnapshot` also fetches every `Routine` with `\.schedules` prefetched, and
three other methods fetch the **entire** `Exercise` table. So all six of these are in scope:

| entity | why it is in the actor's graph |
|---|---|
| `WorkoutSession`, `WorkoutExercise`, `WorkoutSet` | `CompletedSessionFetch.withFullGraph` |
| `Exercise` | fetched wholesale by `fetchFortschrittSnapshot`, `fetchExerciseProgress`, `fetchPreviousPerformances` |
| `Routine` | `fetchTrainingSnapshot`; `HistorySnapshotBuilder` faults `session.routine?.id` |
| `RoutineExercise` | `fetchLiveRoutineSlotIds` walks `routine.routineExercisesList` |
| `RoutineSchedule` | prefetched via `relationshipKeyPathsForPrefetching = [\.schedules]` |

`ExerciseSet` is the one template entity that is **not** in it.

When a writer sits on a synchronous, ordering-critical path that cannot be made `async` piecemeal,
gate the **whole pass** from its entry point rather than the individual deletions — see the watch
drain above. The interior stays synchronous and keeps every invariant it had; only the entry point
suspends.

## Known residual exposure

### CloudKit mirroring imports — the ceiling no app-level gate can reach

The store is `NSPersistentCloudKitContainer`-backed, and mirroring applies remote deletes on
`NSCloudKitMirroringDelegate`'s **own** context. Nothing the app locks can serialize against it, so
a workout deleted on another device — or on the watch — can in principle land mid-walk exactly like
a local delete. This is a real, permanent limit on the gate, not an oversight: SwiftData exposes no
way to pause, defer or veto an import. Apple DTS's guidance for the CloudKit case is reactive only —
observe `.NSPersistentStoreRemoteChange`
([forums/thread/762022](https://developer.apple.com/forums/thread/762022)).

It was **not** the cause of the shipped crash: the persistent-history author column proved both
deletes were local app writes (a mirroring import would have read
`NSCloudKitMirroringDelegate.import`). Nothing has been built against it, because doing so means
either aborting a walk on a remote-change notification or refetching around it, and the frequency
does not yet justify either. If this trap recurs on a store with no local delete to blame, this is
the first place to look.

### Routine-template writers other than `deleteRoutine`

**Three** writers, not the six an earlier draft of this section listed. The correction matters,
because the difference is exactly the entity-scope question this document exists to pin down. The
reader actors touch only three template entities:

| in the actor's graph | where |
|---|---|
| `Routine` | `FetchDescriptor<Routine>` in `fetchTrainingSnapshot` and `ChatFactStore` |
| `RoutineSchedule` | prefetched on both, via `relationshipKeyPathsForPrefetching = [\.schedules]` |
| `RoutineExercise` | `fetchLiveRoutineSlotIds` → `routineExercisesList.map(\.id)` |

They never traverse `routineExercise.setsList` or `.alternativesList`. So `ExerciseSet`,
`RoutineExerciseAlternative` and `AlternativeExerciseSet` deletions are **out of scope** — deleting
a child does not invalidate the parent row the actor holds — which rules out
`RoutinesViewModel:601`, `:996` and `:1031`.

That leaves the genuinely exposed, still-ungated writers:

- `RoutinesViewModel.removeRoutineExercise` (`:524`) — deletes `RoutineExercise`. The reachable one.
- `RoutinesViewModel` schedule removal (`:783`) — deletes `RoutineSchedule`.
- `RoutinePlanLinkRepair` (`Data/Sync/RoutinePlanLinkRepair.swift:197`) — deletes `RoutineSchedule`.

Left out on frequency grounds, not because they are safe. Tracked in
`.scratch/history-delete-race-followups/`.

### Adjacent, deliberately not fixed here

The same "read a `@Model` after an `await`" shape exists around the **in-progress** session —
`PostWorkoutRecapViewModel.run` and `SaveWorkoutView.loadComparisons` capture
`WorkoutViewModel.currentSession` across suspensions while `cancelWorkout()` can delete it. That is
a different bug — the reads there are main-actor continuations rather than the History actor's
walk, so the gate does not address them — and it was left alone rather than folded into this
change.

### What the gate costs

`acquire()` is FIFO and deliberately not cancellation-aware, and the gate now serializes the read
fan-out across three `@ModelActor`s plus the watch drain. A delete tapped while a rebuild is queued
waits behind all of it, so a row can visibly linger in History. The trade is argued in
`HistoryStoreGate.acquire`'s own comment and is the right one — correctness over latency — but it
has **not** been measured on device at a realistic data volume (341 `WorkoutExercise` rows was the
size of the store that crashed). If deletion ever feels sluggish, this is why.

## Related

- `docs/history-performance.md` — why the graph walk is on a model actor at all.
- `docs/swift6-concurrency.md` §1 — the `@concurrent` off-main guarantee the gate must not break.
- `docs/delete-workout.md` — the workout deletion feature.
- `docs/crash-report-retrieval.md` — pulling reports and store files off a device.
