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
is gated for that reason, and so are the three template writers that were left ungated by the first
pass; see "Known residual exposure" for what is still open.

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

**The two passing cases are now pinned permanently** by
`GymStreakTests/HistoryContextRefetchAssumptionTests.swift` — a whole session deleted between two
walks of one long-lived reader context, and a single `WorkoutSet` deleted under a surviving parent
exercise and session (the sharper case, where the re-fetch hands back an object the context already
holds and whose `sets` collection the first walk materialized). Both run against an on-disk store;
in-memory does not fault the same way. Because the assumption comes from observed behaviour rather
than an Apple guarantee, an OS update could revoke it while every other test in the suite still
passes, so it needs its own canary. If either test goes red — or traps — serialization alone is no
longer sufficient and every History reader has to take a fresh `ModelContext(container)` per pass
instead of reusing the model actor's.

Case 3 was deliberately **not** kept: it kills the test runner rather than failing an assertion (the
trap is an uncatchable `fatalError`), so it cannot live in the suite. `HistoryStoreGateTests` asserts
the gate's properties, and `HistoryDeleteRaceRegressionTests` drives the real reader against the real
writer.

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
  `WorkoutSet` rows). Both became `async` as a result. Writers enter through
  `withExclusiveAccess { … }`, **not** `withAccess` — see "Two entry points" below.
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
same flag: `loadAppliedOverloads` and `loadComparisons` both walked the session's exercises *after*
their own `await`, by which point a delete may have committed. Each now re-checks `isBeingDeleted`
on resume — sound because the flag is set on the main actor before the delete task is even created,
so seeing it `false` after a resume means the session is still alive. (`loadComparisons`'s own read
has since moved before the suspension — see "The adjacent bug" below — but the flag stays, because
publishing rows re-renders a screen that is on its way out.) `deleteWorkout` also calls
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

### Two entry points, and why they are not overloads

`HistoryStoreGate` exposes the acquire/release bracket twice:

| entry point | closure | who uses it |
|---|---|---|
| `withAccess` | `() async throws -> T` | the three `@ModelActor` reader providers, whose bodies must `await` their actor |
| `withExclusiveAccess` | `() throws -> T` | every writer — ViewModels, seeders, the watch ingestion coordinator |

The gate is not reentrant, so a writer that suspends inside the gated body while a History rebuild
queues behind it deadlocks the app permanently: no crash, no crash report, no log, and no test that
can catch it. Every writer body is a fetch/delete/save burst that has no reason to suspend, so the
writers' entry point takes a **synchronous** closure and the mistake becomes a compile error.

The two must carry **different names**. As overloads the guard would be worthless: a synchronous
closure converts freely to `() async throws -> T`, so both candidates stay viable — the synchronous
one wins while the body is await-free, and the moment someone adds an `await` it drops out of
overload resolution and the `async` one is silently selected instead. The deadlock would compile
exactly as it did before the guard existed.

Both brackets release on the success and the throwing path, asserted for each in
`HistoryStoreGateTests.aThrowingBodyStillReleasesTheGate`;
`aWriterWaitsBehindAReaderHoldingTheSameGate` asserts the two names really are one gate.

**On the name, since it will come up again.** The architecture reviewer argued that
`withExclusiveAccess` names the wrong axis — both entry points are equally exclusive, and the real
difference is a synchronous body versus an `async` one — and suggested `withSynchronousAccess`.
The argument is correct; the name was kept anyway, decided 2026-08-29. It is the name the ticket
specified, it is live at all 11 writer call sites and referenced from `docs/swift6-concurrency.md`
§9 and `docs/workout-planning.md`, and behaviour is identical either way. Renaming is a mechanical
change if the confusion ever costs someone real time — but re-open it as a rename, not as a bug.

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
a workout deleted on another device can land mid-walk exactly like a local delete. This is a real,
permanent limit on the gate, not an oversight: SwiftData exposes no way to pause, defer or veto an
import. Apple DTS's guidance for the CloudKit case is reactive only — observe
`.NSPersistentStoreRemoteChange` ([forums/thread/762022](https://developer.apple.com/forums/thread/762022)).

It was **not** the cause of the shipped crash: the persistent-history author column proved both
deletes were local app writes (a mirroring import reads `NSCloudKitMirroringDelegate.import`).

**Not the watch, though.** The watch app has no SwiftData store and no CloudKit container at all —
`RoutineStore` over App Group `UserDefaults` is its whole persistence layer — so it cannot originate
a mirroring import. Watch-completed workouts arrive over WatchConnectivity into
`WatchWorkoutIngestionCoordinator`, which takes the gate like any other writer. An earlier draft of
this section named the watch as a second import source; that was wrong.

#### What the store actually shows (measured 2026-08-29)

The device store was pulled again and its persistent history read the same way as the original
diagnosis — three days of it, 26.08.2026 15:15 (store creation) to 29.08.2026 11:54, with no
pruning, since transaction ids start at 1. Local writes on this store carry a **null** `ZAUTHORTS`;
only mirroring interns an author string, which makes the two sources trivially separable:

```sql
SELECT CASE WHEN s.ZNAME IS NULL THEN 'local' ELSE 'IMPORT' END src, p.Z_NAME entity, COUNT(*)
FROM ACHANGE c JOIN ATRANSACTION t ON c.ZTRANSACTIONID = t.Z_PK
LEFT JOIN ATRANSACTIONSTRING s ON t.ZAUTHORTS = s.Z_PK
LEFT JOIN Z_PRIMARYKEY p ON p.Z_ENT = c.ZENTITY
WHERE c.ZCHANGETYPE = 2 GROUP BY 1, 2;   -- 2 = delete
```

Every row deletion in those three days, by source:

| source | rows deleted | entities |
|---|---|---|
| local | **825** | `WorkoutSet` 573, `WorkoutExercise` 192, `WorkoutSession` 31, `ExerciseSet` 13, `RoutineSchedule` 6, `AlternativeExerciseSet` 4, `RoutineExercise` 3, `Routine` 2, `RoutineExerciseAlternative` 1 |
| **import** | **7** | `RoutineSchedule` 5, `Exercise` 2 |

So the gate covers **99.2%** of the delete pressure on this store, and the CloudKit residue is 0.8%.

Three things that residue does tell us, and they are not all reassuring:

1. **Imported deletes of in-scope entities do happen — this is no longer hypothetical.** Both
   entities that were hit are ones the reader actors hold and traverse: `Exercise` is fetched
   wholesale by `fetchFortschrittSnapshot`, `fetchExerciseProgress`, `fetchPreviousPerformances` and
   `ChatFactStore.exercisePRFacts`, and every one of those hands the rows to an aggregator that
   reads their properties; `RoutineSchedule` is prefetched by both reader actors and actually walked
   by `ChatFactBuilder.nextWorkoutFacts` (`routine.schedule` → `schedule.isActive`). A delete
   landing inside either walk is the same trap.
2. **No imported delete touched a completed-session row.** Zero `WorkoutSession`, `WorkoutExercise`
   or `WorkoutSet` deletions arrived from the cloud, while all 796 local ones did. That matters
   because the session graph is the *unbounded* walk — the ~600 ms one that crashed. The two
   entities that were hit are small bounded fetches whose walk is milliseconds, so the same event
   has far less window to land in.
3. **All seven arrived in a single 75 ms burst**, transactions 37–39 at 27.08. 16:48:40.815–.890.
   Their content is a signature, not noise: `RoutineSchedule` rows 6–10 deleted and 11–15 inserted
   in the same breath — `RoutinePlanLinkRepair`'s delete-then-reinsert, run on another device and
   mirrored in **ungated**. The pass that is carefully bracketed locally arrives from the cloud with
   no bracket at all. (`Exercise` 111/113 were likewise replaced by 118/119.)

#### The timing, which is the part worth knowing

Imports do not arrive uniformly — they cluster at launch, which is exactly when the readers do their
coldest, heaviest work. `ANSCKEVENT` records the container's own lifecycle (`ZCLOUDKITEVENTTYPE`
0 = setup, 1 = import, 2 = export):

- The delete burst above landed **5.1 s after container setup** — setup at 16:48:35.732, import
  event 16:48:35.764 → 16:48:40.896, deletes committed at 16:48:40.815. The previous local write was
  five hours earlier and the next one 54 s later, so this was a cold launch with the user in the app.
- The **initial** import after install (transactions 1–26) was **3,836 changes over 6.19 s**, a
  sustained ~620 changes/second beginning 0.5 s after the store was created. It contained no
  deletes — an import into an empty store structurally cannot — but it shows the shape: mirroring
  can hold the store in continuous mutation for six seconds straight at first launch, and a device
  that has been offline while another one deleted workouts replays that backlog into the same window.

Over the three days: 44 container setups, 236 import events, but only **29 import transactions that
changed anything**, in two bursts, one of which carried deletes. Most imports are no-ops.

#### Recommendation: leave it as a documented ceiling

No mitigation is being built, and the reason is stronger than "the frequency is low":

- **The only available signal fires too late.** `.NSPersistentStoreRemoteChange` — Apple's sole
  handle, already wired up in `CloudSyncObserver` — is posted *after* the import context commits. A
  reader walking the graph traps during the walk, before any notification can be processed. A
  reactive abort cannot prevent the trap; it can only notice it afterwards, which is what the
  crash report already does.
- **Deferring the rebuild until the import quiesces is not reliable either.** The app already tries
  this shape twice (`RoutinePlanLinkRepair.runIfNeeded`, `DefaultContentSeeder.recoverStrandedLibraryIfNeeded`),
  and the comment on the first one records why it is only *optimistic*: `CloudKitSyncStatusMonitor`
  restores its status from `UserDefaults` in `init`, so the first `.upToDate` of a cold launch can
  arrive before this session has imported anything. There is no signal in this app's sync model that
  proves an import finished.
- **The remaining option is structural** — stop holding `@Model` rows across the walk at all, i.e.
  project to value types inside the fetch. That is a rewrite of the reader layer, and it is the only
  thing that would actually close this. It is not worth doing for 0.8% of delete pressure that has
  never yet touched the unbounded walk.

**Revisit if** the trap recurs on a store whose history shows no local delete to blame (check the
author column first — that is a five-minute query), or if imported `WorkoutSession` /
`WorkoutExercise` deletions start appearing at all, which would mean cross-device workout deletion
has become a real usage pattern rather than a theoretical one. Either finding moves this from a
documented ceiling to the value-projection rewrite above.

### Routine-template writers other than `deleteRoutine` — now gated

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
`RoutinesViewModel`'s set, alternative and alternative-set removals. That scope was re-verified
against the reader code when these three were closed, and still holds.

The three that were genuinely exposed took the gate on 2026-08-29 (they had been left out of the
original fix on frequency grounds, not because they were safe):

- `RoutinesViewModel.removeRoutineExercise` — deletes `RoutineExercise`; the reachable one. Now
  `async`, with the snapshot capture, the delete, `SupersetOrderingService.normalizeOrdering` and
  the save all inside one `withExclusiveAccess` block; only the refetch sits outside, as in
  `deleteRoutine`.
- `RoutinesViewModel.removeSchedule` — deletes every `RoutineSchedule` row of a routine. Now
  `async`; the emptiness check moved *inside* the gate so the pass reads and writes one consistent
  store, and it reports back whether anything was removed so the refetch stays conditional.
- `RoutinePlanLinkRepair.repair()` — deletes `RoutineSchedule` rows to re-insert them. The whole
  pass is bracketed from `runIfNeeded()`, not just its deletes: its `hasChanges` guard, fetch,
  deletes, inserts, single save and `rollback()` recovery all depend on nothing else committing in
  between. It stays one-shot per device (the `UserDefaults` version flag is untouched) and still
  runs from its own `.task` in `GymStreakApp`, so its ordering relative to launch seeding is
  unchanged — the gate only serializes it against the seeders that already take it.

Two consequences worth knowing, both visible in the diff:

- **A gated mutation cannot be wrapped in a caller's `withAnimation`.** `RoutineDetailView` used to
  wrap `removeRoutineExercise` in one; an `async` call escapes that transaction entirely. The fix is
  a view-side `.animation(DesignSystem.Animation.spring, value: routine.routineExercisesList.count)`
  on `browsingModeContent`'s `LazyVStack` — the animation stays a view concern, and it now covers the
  add path too, which was never animated. Moving `withAnimation` into the ViewModel was tried first
  and reverted: it works, but it puts a SwiftUI transaction inside a gated write where it has no
  business being. Anything else that becomes gated has the same problem and the same answer.
- `SchedulePlanningSheet` dismisses *before* awaiting the removal, for the same reason
  `RoutineDetailView` dismisses before `deleteRoutine`: its body reads the plan it is deleting.

### `setSchedule`'s duplicate collapse — found late, also gated

A fourth writer surfaced while closing the three above: `RoutinesViewModel.setSchedule` deletes the
losing `RoutineSchedule` rows when a routine carries more than one plan (two devices planning
offline, or two repair passes). Same trap as `removeSchedule`, lower frequency — it fires only when
duplicates exist — and it was closed the same day rather than left open.

`setSchedule` is now `async`, with **the whole write inside the gate**: the survivor's field edits
and the losers' removal are one plan, so splitting them would leave exactly the half-applied state
this document warns about. The **paywall refusal stays outside** the gate — it writes nothing, and
presenting UI while holding the gate would make a History rebuild wait on a human. `ScheduleGatingTests`
and `RoutinePlanDuplicateTests` still pin both behaviours; their call sites simply became `await`.

`SchedulePlanningSheet.save()` awaits *before* dismissing, unlike its remove button: the success
haptic depends on the result, and this path deletes only duplicate rows the sheet never displays —
the plan its body reads is the survivor the write keeps.

With that, every routine-template writer that can delete a row a reader actor holds takes the gate.
What remains open is the CloudKit ceiling above, not app code.

### What the gate costs — measured

`acquire()` is FIFO and deliberately not cancellation-aware, and the gate serializes the read
fan-out across three `@ModelActor`s plus the watch drain, so a delete tapped while reads are queued
waits behind them and a row can visibly linger in History. **Measured 2026-08-29** on an iPhone 16
Pro Max (iOS 26.6, Debug build), five runs, at the crash store's volume. Verdict first: **accepted
as it stands, no change** — the realistic wait is ~134 ms, and the specific case the trade was
worried about costs 5 ms.

The harness is `GymStreakTests/HistoryGateLatencyTests.swift` over
`GymStreakTests/Support/HistoryGateLatencyHarness.swift`; re-run it with
`-only-testing:GymStreakTests/HistoryGateLatencyTests` and grep the log for `GATE-COST`. Its
fixture rebuilds the store that crashed — 49 completed sessions × 7 `WorkoutExercise` × 3
`WorkoutSet` (343 exercise rows against the device's 341), **on disk**, plus the full 96-row starter
catalog and four scheduled routines, because the readers fetch the entire `Exercise` table and every
`Routine` on each pass too.

Two things make the numbers mean what they claim. The waits are **staged, not raced**: a stand-in
holder takes the gate, the fan-out and then the write queue behind it, and the clock starts at the
release — so each number is that shape's **worst case**, the tap landing at the instant the reads
begin (a tap landing halfway through a rebuild waits about half as much). And every reader is
**warmed first**, because each provider awaits its `Task.detached` model-actor construction *before*
`gate.withAccess`: an unwarmed reader can still be constructing while the write enqueues ahead of
it, which silently drops it out of the measured wait. Each test asserts the intended FIFO order
actually happened rather than assuming it.

What a writer waits (median of 5 runs):

| The writer's wait | Median | What it is |
|---|---|---|
| Delete behind a **cancelled** rebuild | **4.8 ms** | the case `acquire`'s comment accepts |
| Delete behind **one** rebuild | **134 ms** | two History deletes in a row — the shipped scenario |
| In-workout set delete on a finished session behind one rebuild | **131 ms** | the `withHistoryGateIfVisible` path |
| Delete behind the **full eight-read fan-out** | **594 ms** (565–732) | the constructed ceiling |

And what the reads themselves cost, which is what those waits are made of:

| Gated read | Median |
|---|---|
| `fetchTrainingSnapshot` | 137 ms |
| `fetchFortschrittSnapshot` | 140 ms |
| `ChatFactStore.workoutHistoryFacts(.allTime)` | 128 ms |
| `fetchLifetimeTotals` | 127 ms |
| `fetchExerciseProgress` | 72 ms |
| `ChatFactStore.exercisePRFacts` | 72 ms |
| `ChatFactStore.nextWorkoutFacts` | 2 ms |
| `fetchCompletedWorkoutCount` | 0.1 ms |
| `attributeLegacyRows` (nothing to repair) | 0.2 ms |

Those nine sum to 606 ms against a measured 594 ms fan-out, which is the cross-check: the wait is
the reads, with nothing else hiding in it.

Four things the numbers say:

1. **The wait is the read, not the gate.** The delete behind a cancelled rebuild — which still pays
   the queue turn, the hand-off and the delete's own cascade and `save()` — totals 4.8 ms. So of the
   134 ms a real delete waits, essentially all of it is one `fetchTrainingSnapshot`, and the gate's
   own machinery is free.
2. **The cancelled-rebuild worry does not survive contact.** `acquire`'s comment concedes that a
   superseded rebuild still takes its FIFO turn "ahead of a queued delete", and that is true — but
   every `SwiftDataHistorySnapshotStore` method checks cancellation as its first statement (eight
   of them `try Task.checkCancellation()`; the two non-throwing deep-dive methods
   `guard !Task.isCancelled`), so the cancelled reader returns before it fetches anything and hands
   the gate straight on. The wait it admits to is 5 ms, not a walk. This does **not** generalize:
   `ChatFactStore` has no cancellation checks at all, so a cancelled coach fact lookup does pay in
   full — which is why the number to watch is the fan-out, not cancellation.
3. **The 594 ms ceiling is a construction, not a screen.** It stacks all eight gated reads — both
   History loads, the proactive-paywall totals and count, three coach fact lookups and the
   legacy-attribution repair — in front of one delete. No single interaction triggers all eight.
4. **The spread is small once the actors are warm** — 565–732 ms across five runs, and ±5 ms on the
   single-rebuild cases. An earlier unwarmed version of this harness produced outliers of 2.2 s and
   3.2 s; those were model-actor construction and cold SQLite pages landing inside the measurement,
   not the gate, and warming the readers removed them. Worth knowing if a future run looks wild:
   suspect cold start before suspecting contention.

All of this is a **Debug** build, so it is a pessimistic ceiling: the aggregation
(`HistorySnapshotBuilder`, `PersonalRecordService`, `ChatFactBuilder`) is unoptimized first-party
Swift, and a Release build walks the same graph faster.

**Does deletion feel laggy?** No, at this volume. 134 ms between the tap and the row leaving the
list is at the edge of perception and reads as an animation, not a stall — and it is the *same*
134 ms whether or not the gate exists, because the delete has to wait for that read either way to
avoid the crash at the top of this document.

### The decision, and the levers if it ever changes

**Accepted as it stands.** Neither candidate lever is worth pulling at these numbers:

- **Make `acquire` cancellation-aware** — the lever the concern pointed at. Measured value: ≈ 5 ms.
  It would buy back the hand-off, not a rebuild, and it costs the unconditional
  "every acquire is followed by exactly one release" pairing that makes the gate reasonable to
  reason about. Rejected on the measurement, not on taste.
- **Narrow what the readers hold the gate for** — there is nothing to narrow. Each reader holds it
  for exactly one whole-graph walk, and the walk *is* the dangerous part. The real lever the read
  table exposes is a different one: `fetchTrainingSnapshot`, `fetchFortschrittSnapshot` and
  `workoutHistoryFacts` each walk the same completed-session graph from scratch, at ~135 ms apiece.
  Collapsing those repeated walks would cut the ceiling roughly in half — but that is a
  History-performance change (`docs/history-performance.md`), not a gate change.

**Re-measure when** the single-rebuild wait passes ~250 ms — run the harness; the cost scales with
`WorkoutExercise` rows, so that is roughly a 700-row store, twice this one — or when a user reports
a row lingering after a delete. The harness's `#expect` ceilings are loose on purpose: they are
tripwires for someone putting a *new* unbounded read under the gate, not the measurement itself.

## The adjacent bug: the in-progress session read across a suspension

The same "read a `@Model` after an `await`" shape existed around the **in-progress** session, and
the gate does not address it: the reads there are main-actor continuations that resume holding a
tombstone, not a model actor mid-walk. It was deferred out of the gate change and fixed afterwards
(follow-up ticket 04).

Two screens capture `WorkoutViewModel.currentSession` and keep reading its exercise/set graph
across suspensions, while `cancelWorkout()` deletes exactly that session:

- **The post-workout recap.** `PostWorkoutRecapViewModel.run` checked availability first — a path
  that *sleeps two seconds* when the model is not ready yet — and only then walked the session for
  its set counts and its aggregated input, with the streaming call after that.
- **The save screen's comparison load.** `SaveWorkoutView.loadComparisons` awaited
  `ExerciseProgressService.compareWithPrevious`, and the danger was **inside** the service rather
  than at the call site: `ExerciseComparisonBuilder.build(workout:)` walked the session's exercises
  and sets *after* the off-main history scan returned. A guard at the call site could not have
  covered it, and the same exposure was reached from `WorkoutDetailView` and
  `WorkoutAnalysisViewModel`.

### How it is fixed

**Capture before the suspension, don't guard after it** — the second half of the pattern
`WorkoutDetailView` established with `isBeingDeleted`, and the stronger half wherever it fits,
because it removes the read rather than protecting it.

- `ExerciseComparisonBuilder` gained `makeSnapshot(workout:)`, which reduces the workout to values
  (per-set reps/weight/completion, the per-exercise aggregates, and the `PreviousPerformanceLookup`
  it already produced) in one synchronous main-actor stretch. `build(snapshot:previousPerformances:)`
  replaces `build(workout:)` and sees no `@Model` at all, so `compareWithPrevious` now touches the
  session exactly once, before its await — which fixes all three of its callers at once.
- `PostWorkoutRecapViewModel` split in two. `start(...)` is **synchronous** and does every session
  read in the caller's own turn on the main actor: preferences, the two *synchronous* availability
  verdicts (`deviceNotEligible` / `appleIntelligenceNotEnabled`), the set counts, the prior-session
  count, the cache probe and `buildInput`. Only then does it spawn the task, which runs the
  `.modelNotReady` retry that sleeps and then the stream, holding nothing but a
  `PostWorkoutRecapInput` and a `UUID`.

  Synchronous rather than "first in an async method" on purpose: a `Task` body is **not** ordered
  against the task that discards the workout — SE-0431 gives an implicitly-isolated closure no
  creation-order guarantee (`docs/swift6-concurrency.md` §4) — so reads placed before the first
  `await` *inside* the task can still resume onto a tombstone. Moving them out of the task closes
  that window rather than narrowing it.

  Two accepted consequences: a device whose model is not ready yet pays the aggregation before
  learning it cannot use it, and an insufficient-data session on such a device now reports
  `.insufficientData` where it used to report `.unavailable`.

**And cancel the work when the session goes away.** `generate`/`regenerate` are fire-and-forget
(`runTask`) with a `cancel()`, exactly like `WorkoutAnalysisViewModel`, because the recap has to
stop at the moment the *session* is discarded, which is not the moment the *view* disappears — the
sheet's `.task` cancellation only covered the latter. `SaveWorkoutView` calls `cancel()` from
`.onDisappear` and from `.onChange(of: viewModel.currentSession == nil)`, and the stream skips its
final state write and cache save when cancelled.

That `onChange` is qualified with `&& !isSaving`, because `currentSession` goes nil on **two**
paths: discarding, and `completeWorkout` — and the sheet deliberately stays up through the latter's
History-gate wait. Without the qualifier a recap still streaming when the user taps Save would be
killed mid-sentence and never cached, where before it streamed on until the sheet dismissed.

`WorkoutAnalysisViewModel.run` — the same shape on the History detail screen — gained the
`Task.isCancelled` check that makes `WorkoutDetailView`'s existing `analysisVM.cancel()` actually
protective rather than merely requested, and now takes `workout.id` once, on that check's line,
instead of reading it again after the two-second availability retry.

Where a read genuinely cannot move before the suspension, the guard is identity, not a new flag:
`SaveWorkoutView.loadComparisons` re-checks `viewModel.currentSession === session` on resume.
`cancelWorkout()` unpublishes `currentSession` **before** deleting the row and both happen on the
main actor, so a resume that still sees the same object is a resume that came before the delete —
the same proof `isBeingDeleted` provides in `WorkoutDetailView`.

`ExerciseProgressServiceTests.comparisonRowsSurviveTheWorkoutBeingDeletedMidScan` pins it: snapshot,
delete the session, build — and the rows still carry the workout's values.

## Related

- `docs/history-performance.md` — why the graph walk is on a model actor at all.
- `docs/swift6-concurrency.md` §1 — the `@concurrent` off-main guarantee the gate must not break.
- `docs/delete-workout.md` — the workout deletion feature.
- `docs/crash-report-retrieval.md` — pulling reports and store files off a device.
