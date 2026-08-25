# CloudKit sync and process suspension (0xDEAD10CC)

A `0xDEAD10CC` termination pulled off a physical device, why the lock was
Apple's rather than ours, and what was deliberately *not* built in response.
Read §4 before wrapping SwiftData work in a background task assertion or
re-attempting a background gate on `.cloudKitDataDidChange` — both were tried
and rejected here, for reasons that are easy to rediscover the hard way.

## 1. The crash

Pulled from a physical iPhone 16 Pro Max on 2026-08-25 with:

```sh
xcrun devicectl list devices
xcrun devicectl device info files --device <UDID> --domain-type systemCrashLogs --recurse
xcrun devicectl device copy from --device <UDID> --domain-type systemCrashLogs \
    --source "Retired/GymStreak-2026-08-24-161522.ips" --destination <local path>
```

`GymStreak-2026-08-24-161522.ips`, app 1.1.12 (build 1003), iOS 26.6 (23G71):

| Field | Value |
| --- | --- |
| `exception` | `EXC_CRASH` / `SIGKILL` |
| `termination` | `{namespace: RUNNINGBOARD, flags: 6, code: 3735883980}` |
| `code` in hex | **`0xDEAD10CC`** ("dead lock") |
| `procRole` | `unknown` (not a foreground role — the app was backgrounded) |
| lifetime | launched 15:39:44, killed 16:15:21 — 35 minutes |

Apple documents `0xDEAD10CC` as: *"The operating system terminated the app
because it held on to a file lock or SQLite database lock during suspension."*
The wording is **not** scoped to App Group containers, and our store is not in
one — `GymStreakApp.store` builds its `ModelConfiguration` without
`groupContainer:`, so the store is the app's own private
`Application Support/default.store`. Moving the store out of an App Group is
therefore not an available fix; it was never in one.

## 2. Root cause — two SQLite connections, one of them Apple's

The report has 18 threads. Two matter, and they are on **different SQLite
connections to the same store**:

**Thread 0 (main, labelled "triggered")** — `SQLQueue 0x1261c0000 for default.store`

```
sqlite3_step ← _executeNewValuesForRelationshipFaultRequest
  ← -[NSManagedObject objectIDsForRelationshipNamed:]
  ← SwiftDataRoutineRepository.fetchAll()
  ← RoutinesViewModel.fetchRoutines()
  ← closure #1 in closure #1 in RoutinesViewModel.observeCloudKitChanges()
```

**Thread 7** — `SQLQueue 0x1261c0480 for default.store`

```
guarded_pwrite_np ← sqlite3_step ← -[NSSQLiteConnection commitTransaction]
  ← -[NSManagedObjectContext save:]
  ← +[NSCKEvent finishEventForResult:withMonitor:error:]
  ← -[PFCloudKitExporter finishExportWithResult:] / exportIfNecessary
  ← -[NSCloudKitMirroringDelegate _openTransactionWithLabel:assertionLabel:andExecuteWorkBlock:]
```

**Thread 7 is the lock holder, not thread 0.** Three reasons:

1. A `0xDEAD10CC` report is `EXC_CRASH`/`SIGKILL` with `EXC_CORPSE_NOTIFY`.
   Per Apple, that note means the process was *explicitly quit by the OS* — so
   unlike `EXC_BAD_ACCESS`, "Triggered by Thread 0" is a reporting convention
   (usually the main thread), **not** a hardware-identified culprit. SIGKILL
   freezes every thread at once and the reporter snapshots all of them.
2. SQLite WAL mode allows many concurrent readers and exactly one writer;
   readers do not block writers. Thread 0 is a *reader* doing a relationship
   fault, which does not take the cross-process-blocking lock Apple's
   justification for this kill describes. Thread 7 is frozen **inside
   `guarded_pwrite_np`** — literally mid-syscall writing the WAL as part of
   `commitTransaction`, which is exactly the globally serialised lock.
3. RunningBoard's decision is process-scoped. From outside the process it
   cannot know *which* in-process lock offends; it only knows the process holds
   a flagged lock when its background budget expires.

Note `_openTransactionWithLabel:assertionLabel:andExecuteWorkBlock:` — the
mirroring delegate was running **inside its own background assertion** and was
killed anyway. An assertion only buys runtime; it is still the assertion
holder's job to finish and release the lock inside the granted window, and the
system can shorten that window under load. Apple has never published the
duration.

**Apple's own verdict on this exact stack.** DTS engineer Ziqiao Chen answered
two forum threads with essentially this backtrace: *"If it is Core Data +
CloudKit [that] triggers the long-time tasks, which lead to the crashes, it will
be a framework bug"*, with the recommended action being to file Feedback rather
than patch around it in-app. He explicitly distinguishes "your code held the
lock" (fixable with `beginBackgroundTask`) from "the framework's own sync
pipeline held the lock" (not fixable that way). No fixed-in-iOS-N statement
exists; as of the iOS 26 SDK this is open.

- <https://developer.apple.com/forums/thread/773361>
- <https://developer.apple.com/forums/thread/762093>

### Not a Debug-only artifact

Tempting but wrong. Debug uses `-Onone`, but every frame in both threads
(`sqlite3_step`, `guarded_pwrite_np`, `commitTransaction`, all of
`PFCloudKitExporter`) lives in Apple's precompiled `CoreData.framework` /
`libsqlite3.dylib`, which are optimised regardless of our build configuration.
`-Onone` only slows *our* Swift. No `-com.apple.CoreData.SQLDebug` or
`ConcurrencyDebug` argument exists in any checked-in scheme. Treat the crash as
realistic in Release.

## 3. What we changed

One change, and it is a main-actor-latency fix rather than a fix for this crash.

`RoutinesViewModel.refreshLastPerformedDates()` — reached on every routine fetch
*and* on every `.cloudKitDataDidChange` — used to call `fetchCompleted()`, which
hydrates every completed `WorkoutSession` on the main actor, and then read
`session.routine?.id` per row (one to-one relationship fault each) just to
compute one max `startTime` per routine. Two costs that scale with history, for
an answer whose size scales with the routine count.

Replaced with a bounded repository method,
`WorkoutSessionRepository.lastCompletedStartDates(forRoutineIds:)`: one
`FetchDescriptor` per routine with
`#Predicate { $0.endTime != nil && $0.routine?.id == routineId }`, sorted by
`startTime` descending, `fetchLimit = 1`. Main-actor work becomes O(routines)
instead of O(sessions) — a growth-direction win, since a routine library stays in
the tens while history accumulates forever. `docs/history-performance.md` §1.2a carries the API
reasoning: why N bounded queries rather than an aggregate (SwiftData has no
`MAX(...) GROUP BY` through iOS 26, and the Core Data escape hatch needs
private-API reflection into `ModelContext`), why `propertiesToFetch` doesn't
help, and why `#Index` was left out.

This does not reduce the crash's probability in any way I can defend — it reduces
how long this path occupies the main actor, which is worth doing on its own
merits. An earlier attempt to add `relationshipKeyPathsForPrefetching = [\.routine]`
to `fetchCompleted()` was superseded by this change and reverted: with the scan
gone, nothing traverses that relationship, so the prefetch was pure cost.

**`fetchCompleted()` was removed** along with this change. It had no remaining
production caller, and leaving a "hydrate the whole history on the main actor"
primitive on a `@MainActor` protocol is how the next feature rediscovers the
problem. Code that genuinely needs every completed session has a sanctioned
off-main path already: `SwiftDataHistorySnapshotStore.fetchCompletedSessions()`,
behind `@ModelActor`.

## 4. Considered and rejected

### 4.1 Deferring remote-change broadcasts while backgrounded

Built, reviewed, and reverted on 2026-08-25. The idea: `CloudSyncObserver` would
suppress `.cloudKitDataDidChange` while `applicationState == .background` and
emit one coalesced broadcast on foregrounding, on the reasoning that the four
consumers' fetches only exist to refresh UI and there is no UI to refresh in the
background.

**Why it was wrong: two of the four consumers are not UI refreshes.**

| Consumer | Reaction |
| --- | --- |
| `RoutinesViewModel` | `fetchRoutines()` → fetch + **`syncRoutinesToWatch()`** |
| `ExerciseCatalogSyncCoordinator` | `fetchAll()` + **`watchSync.syncExerciseCatalog(...)`** |
| `ExercisesViewModel` | `fetchExercises()` — pure UI cache |
| `WorkoutViewModel` | `refreshHistory()` — bumps a version counter, trivial |

Gating the notification therefore delays **watch propagation**: a routine or
exercise created on another device, arriving at a backgrounded phone over
CloudKit, would not reach the watch until the phone app was next foregrounded.
Routines have a partial recovery path (`.watchAppBecameAvailable` re-syncs when
the watch app appears); the exercise catalogue has none — its only other
triggers are the root `onAppear` at launch and local library edits.

So the deferral bought a *"real but second-order and weak"* reduction in reader
contention (§2: readers do not block the writer in WAL mode, and the offending
lock is the exporter's) at the cost of a concrete cross-device staleness window.
It also relocated the coalesced fetch burst onto the resume run-loop turn, where
it competes with the activation frame.

Two implementation defects were found in review and are recorded so a future
attempt does not repeat them: arming the flush only on
`willEnterForegroundNotification` is insufficient (UIKit does not guarantee
`applicationState` has left `.background` by the time those observers run, so a
change landing during activation can re-arm the deferred flag with no scheduled
flush — also observe `didBecomeActiveNotification`), and a `@MainActor () -> Bool`
seam is implicitly `@Sendable` under SE-0434, so a test cannot capture a mutable
local to drive it.

If this is ever revisited, the shape to try is narrower: keep broadcasting
always so watch sync keeps flowing, and defer only
`refreshLastPerformedDates()` — the one genuinely presentational, genuinely
O(history) piece. That needs an injected app-state seam in `RoutinesViewModel`
(never `UIApplication.shared` directly — Hard rule 2).

### 4.2 `beginBackgroundTask` around our reactive fetches

Apple's `0xDEAD10CC` text does name it as the remedy, but it can only protect a
lock *our* code holds. The lock here is the exporter's, and we have no hook into
`PFCloudKitExporter`'s commit. If a future crash shows *our* writer mid-commit at
suspension, revisit — that is the case the API is for.

### 4.3 Other dead ends

- **Tuning WAL / history-tracking / checkpoint behaviour.** No public knob.
  `NSPersistentCloudKitContainer` manages history tracking and WAL internally as
  a hard requirement of mirroring, and `ModelConfiguration` exposes no pragmas.
- **Pausing or scheduling the exporter.** Not possible from outside; it reacts to
  local saves and remote pushes. The only indirect lever is the size and
  frequency of local saves that feed it.
- **Moving the store into/out of an App Group.** Irrelevant — see §1.

Residual risk is Apple's. If it recurs in Release, file Feedback citing the two
forum threads in §2.

## 5. Related crash — same device, different cause (fixed)

`GymStreak-2026-08-23-120321.ips`, v1.1.10 build 1001: `EXC_BREAKPOINT`/`SIGTRAP`
in `_dispatch_assert_queue_fail` ← `swift_task_isCurrentExecutorWithFlagsImpl` ←
`-[WCSession _onqueue_notifyOfMessageError:messageID:withErrorHandler:]`. This is
the SE-0423 dynamic-isolation trap documented in
`docs/swift6-concurrency.md` §4a, fixed by commit `8df9374` ("mark
WatchConnectivity error handlers `@Sendable`") 5½ hours after this crash.
Verified against the installed iOS 26 SDK: `WCSession.h` and
`WatchConnectivity.apinotes` still carry **zero** `NS_SWIFT_SENDABLE`
annotations, so every `sendMessage`/`sendMessageData` handler and every
`WCSessionDelegate` method remains exposed to this. SE-0463 (Swift 6.2) would
close the class of bug, but only once Apple re-annotates the framework. There is
**no build flag** that turns it into a compile-time error — the compiler has no
isolation information to check against. (`-disable-dynamic-actor-isolation` goes
the wrong way: it silences the trap and permits the race.)

## 6. Sources

- [EXC_CRASH (SIGKILL) — Apple](https://developer.apple.com/tutorials/data/documentation/xcode/sigkill.md)
- [Examining the fields in a crash report — Apple](https://developer.apple.com/tutorials/data/documentation/xcode/examining-the-fields-in-a-crash-report.json)
- [Consuming relevant store changes — Apple](https://developer.apple.com/documentation/coredata/consuming-relevant-store-changes) (note: Apple's own sample has no assertion around the reaction)
- [`beginBackgroundTask(withName:expirationHandler:)`](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(withname:expirationhandler:))
- [`relationshipKeyPathsForPrefetching`](https://developer.apple.com/documentation/swiftdata/fetchdescriptor/relationshipkeypathsforprefetching) (iOS 17+)
- [SQLite WAL](https://sqlite.org/wal.html) — single-writer / readers-don't-block-writers semantics
- Apple DTS replies: [773361](https://developer.apple.com/forums/thread/773361), [762093](https://developer.apple.com/forums/thread/762093)

Related: `docs/swift6-concurrency.md` §4a, `docs/history-performance.md`,
`docs/watch-sync.md`.
