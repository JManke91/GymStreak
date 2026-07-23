# iOS Startup Diagnostics

This document records the investigation of the debugger console lines observed
on iOS startup on 2026-07-23. The important distinction is whether GymStreak
owns the emitting code and whether changing it would weaken recovery behavior.

| Console line | Owner | Decision |
|---|---|---|
| `Couldn't read values in CFPrefsPlistSource … kCFPreferencesAnyUser` | CoreFoundation, triggered by opening the App Group defaults suite | Reduce correctly: legacy migrations now open the suite lazily and persist completion markers. An upgrade may still emit it once. |
| `Application context data is nil` | WatchConnectivity | Keep: one post-activation `receivedApplicationContext` read is required for process-relaunch recovery. |
| `Notification permission granted` twice | GymStreak | Fixed: two `WorkoutViewModel` initializers requested permission. iOS authorization is now just-in-time at first rest timer use; the unused watch startup request was removed. |
| `updateTaskRequest failed for com.apple.coredata.cloudkit.activity.export…` / `BGSystemTaskSchedulerErrorDomain Code=3` | Core Data + CloudKit system integration | No app change: GymStreak does not register or submit this Apple-owned task identifier. Do not add it to `BGTaskSchedulerPermittedIdentifiers`. |
| Duplicate `CatalogSync: challenge from watch …` | GymStreak | Fixed: identical cached/delegate challenges remain idempotent inputs but are logged only once per changed value. |
| `RoutineSync: routine challenge updated` | GymStreak | Expected state transition. |
| `WatchConnectivity: requested workout queue drain from Watch` | GymStreak | Expected recovery request. |
| `CloudSyncObserver: …` | GymStreak | Kept, but renamed to `Persistent store change detected`; `NSPersistentStoreRemoteChange` is not exclusive proof that CloudKit supplied the change. |

## Deliberate non-fixes

### Cached WatchConnectivity context

The delegate receives newly arriving application contexts, while
`receivedApplicationContext` exposes the most recently received value. A prior
delivery is not guaranteed to be delivered to a newly launched process as a
new delegate callback. GymStreak therefore performs one cached read only after
activation and feeds both paths into idempotent reducers. Removing that read to
silence the framework message would create a relaunch recovery regression.

### Core Data + CloudKit background task request

The failing identifier begins with `com.apple.coredata.cloudkit.activity` and
is produced below SwiftData/Core Data, not by an app `BGTaskScheduler.submit`
call. [Apple DTS addressed this exact Code 3 line](https://developer.apple.com/forums/thread/824836):
the framework owns it, apps cannot repair it, and Core Data schedules later
work when unsynchronized data or a previous failure requires another attempt.
GymStreak must not claim Apple's identifier in its Info.plist or add unrelated
Background Modes. Treat the line as diagnostic noise only while functional
CloudKit checks still pass. Escalate if remote data stops converging, mirroring
events report persistent import/export errors, or the same behavior reproduces
in a signed non-debug build; use TN3163/TN3164 and paired-device diagnostics in
that case.

### Persistent-store remote changes

`CloudSyncObserver` still posts the legacy-named `.cloudKitDataDidChange`
notification to avoid widening this cleanup into a cross-app rename. The
implementation comments and console message describe the actual generic Core
Data signal. Renaming the internal notification can be done separately if its
call sites are migrated together.

## Regression coverage and verification

- `WatchWorkoutInboxStoreTests` covers completed-marker skipping, malformed
  legacy data retry, migration write-failure recovery, migration ordering,
  duplicate delivery, and receipts.
- `WorkoutViewModelTests` covers no reminder action during initialization,
  identity/deadline scheduling at rest-timer start, outcome visibility,
  deadline restoration, and identity-scoped cancellation at stop.
- `UserNotificationRestTimerSchedulerTests` covers first-use authorization,
  denial/provisional states, expired deadlines, permission-delay timing,
  cancellation/replacement races, and cleanup after scheduler recreation.
- `ExerciseCatalogSenderTests` sends the same challenge twice and directly
  verifies one log while sync processing and transfer deduplication remain
  intact.
- Startup test output is checked for the absence of GymStreak's duplicate
  notification-permission messages; system WatchConnectivity and CloudKit
  diagnostics may remain.

## Primary sources

- [Apple DTS: the exact CFPrefs warning is safe log noise](https://developer.apple.com/forums/thread/765207)
- [WCSession.receivedApplicationContext](https://developer.apple.com/documentation/watchconnectivity/wcsession/receivedapplicationcontext)
- [WCSessionDelegate application-context delivery](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate/session(_:didreceiveapplicationcontext:))
- [Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
- [Apple DTS: exact SwiftData/CloudKit Code 3 answer](https://developer.apple.com/forums/thread/824836)
- [TN3163: Understanding the synchronization of NSPersistentCloudKitContainer](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer)
- [TN3164: Debugging the synchronization of NSPersistentCloudKitContainer](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer)
- [NSPersistentStoreRemoteChange](https://developer.apple.com/documentation/coredata/nspersistentstoreremotechange)
