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

## The Live Activity surface (audit P1.5, 2026-08-13)

The Lock Screen / Dynamic Island countdown was the last system integration
`WorkoutViewModel` drove directly — ~100 lines of ActivityKit inline in a
2,195-line file, with no test coverage. It now follows the same shape as the
notification scheduler:

- `Domain/Interfaces/RestTimerLiveActivityPresenting.swift` — `startActivity(id:content:)`,
  `endActivity(id:)`, `dismissExpiredActivities()`, plus the ActivityKit-free
  `RestTimerLiveActivityContent` value the ViewModel builds. `Domain/` and
  `Presentation/` no longer reference ActivityKit at all.
- `Data/LiveActivity/ActivityKitRestTimerPresenter.swift` — the only app-target
  file importing ActivityKit. `RestTimerAttributes.swift` moved here from
  `Domain/Models/` in the same change, since it imports ActivityKit and is the
  wire format of one system integration, not a domain model.
- `AppDependencies` owns one presenter, injected into both `WorkoutViewModel`s.

**Identity keying is not cosmetic.** Two `WorkoutViewModel` instances exist
concurrently (Routines tab and History tab) and now share one presenter, so
`endActivity(id:)` mirrors `cancelReminder(id:)`: it does nothing unless the id
matches the countdown actually on screen. The timer UUID is the same one the
notification request and the persisted timer state use — one identity across all
four surfaces.

`startActivity` is idempotent per id, which is what lets `restoreTimerState()`
call it unconditionally on every foreground instead of the ViewModel tracking
whether an activity object exists.

**Localization.** The two user-facing Live Activity strings were hardcoded
English before P1.5 and are now `live_activity.rest_timer.complete` and
`live_activity.rest_timer.workout_fallback` (the title when a rest runs outside a
routine-backed session). Both are localized **in the app process** before they
cross into `RestTimerAttributes.ContentState`; the widget extension renders
whatever string arrives and therefore needs no keys of its own.

### Behavior change: duplicate countdowns on relaunch

Previously, relaunching mid-rest produced **two** Live Activities — the previous
process's countdown was still on the Lock Screen, and `restoreTimerState()`
requested a second one because the fresh ViewModel's `currentRestActivity` was
`nil`. The presenter now ends leftovers before presenting a restored countdown.

The sweep is deliberately gated on "this process has never presented anything":
between two timers *within* one session the previous activity is still listed for
a few seconds showing "Rest Complete! 💪", and sweeping it there would cut that
state short on every set transition. `dismissExpiredActivities()` (called from
`WorkoutViewModel.init`) still only ends countdowns whose deadline has already
passed — ending a live one at construction time would kill a legitimate rest if
the app were ever launched into the background with no `restoreTimerState()` to
follow.

### Regression coverage

`ActivityKitRestTimerPresenterTests` asserts the policy against a fake
`RestTimerLiveActivityStore`: the authorization gate, idempotence, replacement,
identity-scoped ending, ending being idempotent, expired-only dismissal, the
leftover sweep, the completed-countdown carve-out above, retry after a failed
request, and rejection of an inverted timer range. `WorkoutViewModelTests` adds
two tests that the ViewModel drives it at the right moments and with the same
identity as the notification.

## ActivityKit findings (verified against the iOS 26.5 SDK interface)

Read out of `ActivityKit.swiftinterface` rather than inferred, because the
project's own comments had drifted from it:

- `Activity<Attributes>` is a **non-`Sendable` class with no isolation
  annotation**; `request`, `update` and `end` are plain `nonisolated async`.
  Nothing is `@concurrent`. See `docs/swift6-concurrency.md` §8 for why
  `@preconcurrency import` is still required and how that was verified.
- **`ActivityAuthorizationError` is a typed enum** with 12 cases
  (`attributesTooLarge`, `unsupported`, `denied`, `globalMaximumExceeded`,
  `targetMaximumExceeded`, `unsupportedTarget`, `visibility`,
  `persistenceFailure`, `missingProcessIdentifier`, `unentitled`,
  `malformedActivityIdentifier`, `reconnectNotPermitted`). *Root cause worth
  recording:* the code this replaced classified failures by string-matching
  `error.localizedDescription` against `"unsupportedTarget"`,
  `"activitiesDisabled"` and `"activityLimitExceeded"`. Two of those are not
  cases of the enum at all, and `localizedDescription` on a `LocalizedError`
  returns a localized sentence, never a case name — so **none of those branches
  could ever be taken**. The presenter catches the typed error instead.
- `Activity.request` is documented as foreground-only; the case for calling it
  while backgrounded is `visibility`.
- `dismissalPolicy: .after(_:)` has a documented four-hour *upper* bound and no
  minimum, so the 3-second completion display is within spec.
- The combined attributes + `ContentState` payload limit is 4 KB
  (`attributesTooLarge`); a `ClosedRange<Date>` is negligible against it.
- **Not documented, tracked as a known unknown:** Apple does not guarantee that
  the synchronous `Activity.activities` is fully populated at process start.
  `dismissExpiredActivities()` reads it at `WorkoutViewModel.init`. If expired
  leftovers ever survive a launch, `Activity.activityUpdates` is the documented
  async alternative.
- There is no supported way to fake ActivityKit; the `RestTimerLiveActivityStore`
  seam is the only route to unit tests, which is why it exists.

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
Existing timer and workout tests continue to cover their independent behavior.
(This line used to claim Live Activity tests among them; there were none until
audit P1.5 — see "Regression coverage" under the Live Activity section below.)

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
