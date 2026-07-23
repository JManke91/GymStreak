# Rest Timer Notifications

## Behavior

The iOS app schedules one local notification when a rest timer starts so the
user can return for the next set while GymStreak is backgrounded. Authorization
is requested only when that first timer needs a notification; constructing
`WorkoutViewModel` at app launch has no notification side effects.

Each timer gets one UUID and absolute deadline before any system work begins.
`UserNotificationRestTimerScheduler` first reads the current notification
settings. It schedules for `.authorized`, requests alert and sound authorization
for `.notDetermined`, and returns an observable outcome for denial, provisional
or unavailable alerts, an expired deadline, cancellation, and system failure.
The rest-timer view displays a localized warning when an alert cannot be
scheduled; the in-app countdown still runs.

Each request uses the deterministic `restTimer.<timer UUID>` identifier,
localized English/German title and body, default sound, and a one-shot
`UNTimeIntervalNotificationTrigger`. The trigger interval is calculated from
the deadline immediately before `add(_:)`, so time spent in the permission
prompt cannot make the notification late.

Stopping or replacing the timer invalidates the current generation, cancels
the in-flight authorization/scheduling task, and removes its identity-scoped
pending request.
The scheduler also re-checks the generation after `add(_:)` returns and removes
the old request if cancellation raced with that suspended call. Unique
identifiers ensure cleanup of an older request cannot remove its replacement.
Before scheduling it also queries pending requests and removes any stale
`restTimer.*` identifier left by a previous app process. Cancellation uses the
persisted timer UUID, so a recreated scheduler can remove the correct request
without broad cross-owner cancellation. The former stable `restTimer`
identifier is removed for upgrade compatibility.

`WorkoutViewModel` persists the timer UUID, start date, duration, and absolute
deadline. The deadline is authoritative: foreground ticks and restoration
derive remaining time from it instead of decrementing an in-memory counter.
The Live Activity receives the same date range and uses the deadline as its
`staleDate`.

## Architecture

- `Domain/Interfaces/RestTimerReminderScheduling.swift` is the semantic system
  gateway protocol used by Presentation.
- `Data/Notifications/UserNotificationRestTimerScheduler.swift` is the only
  iOS type that imports UserNotifications.
- `AppDependencies` owns one scheduler and injects it into both
  `WorkoutViewModel` instances.
- `WorkoutViewModel` owns timer identity/deadline state and calls the protocol.
  The on-screen countdown, persistence, reminder, and Live Activity are
  separate delivery surfaces driven by that shared state.

This follows `Presentation → Domain ← Data`: the ViewModel no longer talks to
`UNUserNotificationCenter` directly and the permission/scheduling boundary can
be replaced by a recording test double.

## Platform scope

- **iOS 26+:** behavior above is active. The notification permission prompt is
  no longer shown during startup.
- **watchOS:** the unused watch-local notification authorization and dead
  scheduling helpers were removed. The active watch workout continues to use
  its existing countdown and haptics; it does not request notification
  permission merely because the ViewModel was created.

## Regression coverage

`WorkoutViewModelTests` checks that initialization schedules and cancels
nothing, starting a timer schedules the exact identity/deadline, stopping it
cancels that identity, denial becomes a visible warning state, and restoration
derives the remaining seconds from the persisted deadline.
`UserNotificationRestTimerSchedulerTests` deterministically suspend the system
`add(_:)` boundary and verify that both cancellation and replacement remove a
late stale request without deleting the current one. They also recreate the
scheduler around a shared notification-center fake to verify cleanup after an
app relaunch, verify the post-authorization remaining interval, and cover
granted, denied, provisional, and expired-deadline outcomes.
Existing timer, Live Activity, and workout tests continue to cover their
independent behavior.

## Apple API findings

- Apple recommends asking for notification authorization in a context that
  explains the need, checking current settings, and requesting only the
  interaction types the app uses. GymStreak therefore requests `.alert` and
  `.sound` at first rest-timer use, not `.badge` at launch.
- The implementation uses the async `notificationSettings()`,
  `requestAuthorization(options:)`, and `add(_:)` APIs available within
  GymStreak's deployment range.
- A Live Activity is a glanceable countdown, not a future execution mechanism;
  `staleDate` marks stale content but does not alert the user.
- AlarmKit is available within the iOS 26 deployment range, but is deliberately
  not used. Its alarm semantics can break through silent mode and Focus, which
  is stronger than GymStreak's ordinary rest reminder requires. Adopting it
  would add authorization and lifecycle complexity without matching the
  requested product behavior.

Sources:

- [Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
- [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
- [UNTimeIntervalNotificationTrigger](https://developer.apple.com/documentation/usernotifications/untimeintervalnotificationtrigger)
- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [AlarmKit](https://developer.apple.com/documentation/alarmkit)
