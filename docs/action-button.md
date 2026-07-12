# Apple Watch Ultra Action Button — Complete Set

## Overview

During a running watch workout, pressing the **Action Button** (Apple Watch Ultra 1/2/3) completes the current set and advances to the next one — the hardware equivalent of tapping the on-screen complete button. If a rest timer is running, the press skips the rest instead. On non-Ultra watches with the S9 chip or newer (Series 9/10, Ultra 2/3), the **Double Tap** gesture triggers the same set completion via the on-screen button.

This matches the behavior of competitor apps like Strong ("Action Button: Next Set").

## How it works (mechanism)

The Action Button is **not** exposed as a button API. It works entirely through **App Intents** (watchOS 9+):

1. `GymStreakStartWorkoutIntent` conforms to `StartWorkoutIntent`. This makes GymStreak selectable under **Settings → Action Button → Workout** on the watch and is the *donation anchor*. Its `perform()` just opens the app (`openAppWhenRun = true`) and returns plain `.result()` — GymStreak workouts are routine-based, so a press with no active session cannot blind-start a workout.
2. When the workout session reaches `.running` (delegate callback in `WatchHealthKitManager`), the manager calls `WatchWorkoutViewModel.donateActionButtonIntent()`:
   ```swift
   try await GymStreakStartWorkoutIntent()
       .donate(result: .result(actionButtonIntent: GymStreakCompleteSetIntent()))
   ```
   This registers `GymStreakCompleteSetIntent` as the session's "next action". Per Apple's docs, *"Apple Watch Ultra runs the next action when someone presses the Action button while a workout session is already running."* The routing is **session-based**: the user does NOT need to start the workout via the button or assign the button to GymStreak — verified on device (June 2026) with the button set to the generic Workout function. Donation happens on `.running` (not during session startup, where it can fail silently) and re-fires on resume.
3. Each press calls `GymStreakCompleteSetIntent.perform()`, which calls `WatchWorkoutViewModel.handleActionButtonPress()` via the `AppStateProvider` singleton, then **re-donates itself** so the next press works too (the system only keeps the most recently donated intent).
4. `handleActionButtonPress()`:
   - no-op unless a workout is active
   - if `isResting` → `skipRest()`
   - otherwise completes the current set via `toggleSetCompletion(...)` — the same superset-aware path the on-screen button uses (rest timer rules, superset round detection, advance-to-next-set)
5. Double Tap: `.handGestureShortcut(.primaryAction)` on the complete button in `CompactActionBar` (both the multi-set and single-set layouts — they're mutually exclusive, so only one primary action is ever on screen).

**Deliberately NOT implemented** (product decision, June 2026): `PauseWorkoutIntent`/`ResumeWorkoutIntent` conformances and the `HKWorkoutEventType.pauseOrResumeRequest` handler (Action+Side press gesture). They existed briefly but were removed because the system education overlay then advertises "Pause Workout" on the Action Button, which confused users — the button should only ever complete sets. Pausing remains available via the on-screen workout controls. If hardware pause is ever wanted again, re-add the two intent structs and the `workoutSession(_:didGenerate:)` handler (see git history).

## Components involved

### watchOS target (`GymStreakWatch Watch App`)

| File | Role |
|------|------|
| `Intents/GymStreakIntents.swift` | All App Intents: `GymStreakWorkoutStyle` (AppEnum), `GymStreakStartWorkoutIntent`, `GymStreakCompleteSetIntent`, `AppStateProvider` singleton |
| `ViewModels/WatchWorkoutViewModel.swift` | `donateActionButtonIntent()`, `handleActionButtonPress()` |
| `Managers/WatchHealthKitManager.swift` | Triggers the donation when the session reaches `.running` |
| `Views/CompactActionBar.swift` | `.handGestureShortcut(.primaryAction)` on the complete buttons (Double Tap) |
| `GymStreakWatchApp.swift` | Registers the view model with `AppStateProvider` on launch |

### iOS target

Not involved — this is watch-only. (The intents live under the watch app's synchronized root group, so they are not compiled into the iOS target.)

## Configuration requirements

- `WKBackgroundModes` containing `workout-processing` in the watch app's Info.plist — **without it watchOS does not treat the app as a workout app and it never appears in the Action Button picker**, even with perfect intent metadata.
  - ⚠️ `INFOPLIST_KEY_WKBackgroundModes` is NOT a supported build setting — Xcode silently ignores it and the key never reaches the generated Info.plist (this was the root cause of the app missing from the Action Button settings). The key lives in a real `GymStreakWatch Watch App/Info.plist` merged via `INFOPLIST_FILE` (with `GENERATE_INFOPLIST_FILE = YES`, same pattern as the iOS target), plus a synchronized-group membership exception for `Info.plist` so it isn't double-produced as a resource.
- `workoutStyle` on the start intent **must** be `@Parameter`-annotated, otherwise Settings only offers "Open App".
- `caseDisplayRepresentations` on the AppEnum **must** be literal key-value pairs — dynamic construction breaks the `appintentsmetadataprocessor` silently and the app disappears from the Action Button settings picker.
- No entitlements needed.

## User-facing setup

The Action Button must be set to the **Workout** function (Settings → Action Button). Per Apple's docs the in-session routing is session-based — *"Apple Watch Ultra runs the next action when someone presses the Action button while a workout session is already running"* — so once GymStreak's session is running and the donation succeeded, presses run the complete-set intent without requiring GymStreak as the assigned workout app (Strong behaves the same way). The app picker assignment governs the **no-session** case: with GymStreak selected there, a press without an active workout opens GymStreak.

### Troubleshooting: app missing from Action Button picker / presses open Apple's Workout app

The system only knows the intents after it indexes a build that contains them. If GymStreak does not appear under Settings → Action Button → Workout → app picker, the watch is running a stale binary or watchOS hasn't re-indexed:

1. Build & run the **watch app scheme directly on the watch** (not just the iOS app) so the new binary is definitely installed.
2. Reboot the watch — the Action Button settings list and the intent index are known to refresh lazily.
3. Verify the picker now lists GymStreak (this is the cheap proof that the intents are registered — even if the user never assigns it).
4. Start a workout and check the Xcode console: `Action Button: complete-set intent donated` vs `donation failed: …`. A failure with `LNTranscriptErrorDomain error 1003` is the known watchOS 26.5 donation regression (see gotchas).
5. A press with no donated next action falls back to the assigned default (e.g. opens Apple's Workout app) — that symptom means the donation never registered, not that the routing requires reassignment.

## Edge cases & gotchas

- **Hardware**: Action Button exists only on Ultra models; the intents compile and ship everywhere but never fire elsewhere. Double Tap requires S9 chip+ (Series 9/10, Ultra 2/3).
- **No detection API**: the app cannot read or set the user's Action Button assignment, and cannot detect Ultra-specific capability cleanly — there is no in-app indicator of whether the button is configured.
- **Water Lock**: when active, the first press unlocks Water Lock; subsequent presses reach the app. OS behavior, not suppressible.
- **Donation lifetime**: donations only stick while a workout session is active. The donation is made when the session reaches `.running`; each intent `perform()` re-donates. Nothing to clean up at workout end — the chain dies with the session.
- **Already-completed set**: `handleActionButtonPress` guards against re-completing (`!set.isCompleted`) so a press on a completed set does nothing rather than un-completing it.
- **UI testing**: donation is skipped under `-UI_TESTING` (no HealthKit session exists there).
- **watchOS 26.5 regression**: donation override reportedly fails with `LNTranscriptErrorDomain error 1003` when the button is assigned to "Open App" (not the Workout function). Testing should cover both assignments.
- **Simulator**: the Action Button cannot be tested in the simulator (no hardware); on-device testing on an Ultra is required. (The KhaosT reference example notes `actionButtonIntent` does not work on simulator.)
- **Simulator donation noise (fixed 2026-07-12)**: in the simulator the donation itself always fails with `NSCocoaErrorDomain Code=4099 — connection to com.apple.linkd.transcript invalidated`, because `linkd` (the daemon backing the Siri/Shortcuts transcript store that donations write to) doesn't run there — the same "daemon absent in simulator" pattern known from other XPC services. Since the Action Button flow can't be exercised in the simulator anyway (see above), `donateActionButtonIntent()` is now compiled out with `#if !targetEnvironment(simulator)`. Note this simulator error is **distinct** from the on-device watchOS 26.5 `LNTranscriptErrorDomain 1003` regression above; the on-device `do/catch` logging is kept so that regression stays visible.

## References

- Apple: [Responding to the Action button on Apple Watch Ultra](https://developer.apple.com/documentation/appintents/actionbuttonarticle)
- Apple: [StartWorkoutIntent](https://developer.apple.com/documentation/appintents/startworkoutintent)
- Reference implementation: [KhaosT/WatchActionButtonExample](https://github.com/KhaosT/WatchActionButtonExample)
