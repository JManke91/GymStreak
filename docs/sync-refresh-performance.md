# Sync refresh performance

How much main-thread work one CloudKit remote change is allowed to cost.

## 1. The problem

`NSPersistentStoreRemoteChange` is posted by `NSPersistentCloudKitContainer` after every
import batch it merges. `CloudSyncObserver` translates it into `.cloudKitDataDidChange`,
which four long-lived handlers listen to:

| Handler | Work per notification |
| --- | --- |
| `RoutinesViewModel.observeCloudKitChanges` | `fetchRoutines()` |
| `ExercisesViewModel.observeCloudKitChanges` | `fetchExercises()` |
| `WorkoutViewModel.observeCloudKitChanges` | `refreshHistory()` |
| `ExerciseCatalogSyncCoordinator` | `exerciseRepository.fetchAll()`, then a watch send |

So one notification costs four main-actor SwiftData fetches. In steady state that is a
handful of notifications per session and irrelevant. In a **bulk import** it is not: a new
device, a reinstall, or a `ServerChangeTokenExpired` reset (`CKError` 21 — CloudKit
discards its sync state and re-downloads the entire private database) posts well over a
hundred of them in one session.

Measured on device 2026-08-25/26: 100+ `Persistent store change detected` lines in a single
session while the store grew 8.5 MB → 33.5 MB, with `WAL checkpoint: Database busy`
throughout. That window — first launch on a new device — is exactly when the app should
feel fastest.

The individual refreshes are correct and idempotent. Only their **frequency** was wrong.

### Measured after the fix (2026-08-26, fresh install on device)

`RoutinesViewModel.fetchRoutines()` calls `syncRoutinesToWatch()`, and with no watch app
installed `WatchConnectivityManager.canSyncRoutines` logs
`phone: cannot sync routines — Watch app not installed` **before** any duplicate
suppression — so that line is an exact per-fan-out counter on such a device. In a
fresh-install import log extract:

| Signal | Count |
| --- | --- |
| `Persistent store change detected` (notifications) | 34 |
| `cannot sync routines` (refresh passes actually run) | 4 |

~8.5× fewer refresh rounds, so roughly 120 main-actor SwiftData fetches avoided across the
four handlers. The clearest single case is a block of **nine consecutive** notifications
with nothing interleaved, collapsed into one fan-out.

Two caveats for anyone repeating this. The counter only works while the watch app is *not*
installed — once it is, `canSyncRoutines` returns `true` and logs nothing, and the
duplicate-payload suppression downstream makes routine sends a poor proxy. And the two
signals travel different log paths, so their interleaving in the Xcode console is not
strictly ordered; the counts are meaningful, the exact positions are not.

## 2. The fix

Coalescing lives in `Data/Sync/CloudSyncObserver.swift`, at the single source, not in the
four consumers — they are unchanged.

**Leading-edge first, then one trailing fan-out per window:**

1. The first change after a quiet period fans out **immediately** — no delay at all.
2. That opens a coalescing window. Everything arriving inside it sets a pending flag.
3. When the window elapses with something pending, one fan-out goes out and the window
   re-arms — so a sustained burst costs at most one fan-out per window.
4. When a whole window passes with nothing pending, the window closes and the next
   isolated change is immediate again.

A burst of N notifications therefore costs ~2 fan-outs (leading + trailing) when it fits
inside one window, and `burst duration / window` fan-outs when it does not — instead of N.

### Why two seconds

`CloudSyncObserver.defaultCoalescingWindow = .seconds(2)`.

- **Upper bound on the burst side:** two seconds sits above the sub-second spacing of the
  notifications inside one CloudKit import batch, so a batch collapses to a single refresh.
- **Lower bound on the latency side:** CloudKit's own end-to-end delivery latency for a
  change made on another device is already many seconds. Two seconds of coalescing is
  invisible against the transport it is throttling.
- It only ever applies to a change landing within the window of a previous one. The first
  change of any quiet period — the steady-state case, and the one a user would notice — is
  never delayed.

### What is deliberately *not* coalesced

`DefaultContentSeeder.seedStrandedLibrary()` posts `.cloudKitDataDidChange` **directly**,
bypassing the observer. That post is the mechanism by which the recovered library reaches
the view models and the watch, it happens at most once per session, and delaying it would
delay the recovery it announces. Pinned by
`directCloudKitDataDidChangePostIsNotCoalesced`.

`RoutinePlanLinkRepair` does not observe this notification at all — it gates on
`CloudSyncStatusProviding` — so it is unaffected.

### The release `print`

`handleRemoteChange()` used a bare `print`, which is not `#if DEBUG`-guarded and ran in
release once per notification (100+ times during the import above). It is now
`Logger(subsystem: LogSubsystem.sync, category: "RemoteChange").debug(_:)`: `.debug` is not
written to the on-disk log store, so it costs nothing in release and is still readable from
a live `log stream --level debug`.

## 3. Semantics that changed

`CloudSyncObserver.syncVersion` now increments once per **fan-out** rather than once per
notification. It stays in lockstep with `.cloudKitDataDidChange` — the two are emitted
together — and no consumer reads it as a notification count.

## 4. Coverage

`GymStreakTests/CloudSyncObserverCoalescingTests.swift`, with a 100 ms window injected
through `CloudSyncObserver(coalescingWindow:)` (the initializer is internal only for this;
production always goes through `shared`):

- `isolatedRemoteChangeFansOutWithoutWaitingForTheWindow` — asserted a quarter of a window
  in, so a purely trailing debounce would read 0 and fail.
- `burstOfRemoteChangesCollapsesToLeadingAndTrailingFanOut` — 20 notifications, 2 fan-outs.
- `changeAfterTheWindowClosesFansOutImmediatelyAgain` — the window really closes.
- `directCloudKitDataDidChangePostIsNotCoalesced` — the seeder's path is untouched.

Both notification names are process-wide, so overlapping tests would count each other's
posts. `.serialized` orders the tests within this suite; what actually keeps *other* suites
out is `GymStreak.xctestplan` declaring `GymStreakTests` `"parallelizable": false`. Every
assertion is made after enough real time has passed for the opposite behaviour to have
shown itself — a count checked too early also passes against a coalescer that never fires.

## 5. Related, still open

Each fan-out invalidates `RoutinesView`, which rebuilds every routine card eagerly with
three `RoutineMetricsService` calls apiece. Coalescing reduces how *often* that happens;
the per-refresh cost is `.scratch/sync-refresh-performance/issues/02`. The two multiply
each other; neither blocks the other.

A second per-fan-out cost sits at the root: `GymStreakApp` holds
`@StateObject private var cloudSyncObserver = CloudSyncObserver.shared`, so every
`syncVersion` bump invalidates `GymStreakApp.body` — even though no app code reads
`syncVersion` at all (only the tests do). Pre-existing, and strictly improved by the
coalescing, but dropping either the `@Published` or the `@StateObject` binding would remove
a whole-root invalidation per fan-out. Not done here: it changes the observer's published
shape, which this ticket deliberately left alone.

Prior art on the same class of bug: `docs/history-performance.md` (630 ms main-thread hang,
seven causes). The watch **transport** half of this storm was already mitigated on
2026-07-14 with payload-level duplicate suppression in `syncRoutines` — that saved the
radio, not the query; see `docs/watch-sync.md`.
