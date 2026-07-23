# Apple Watch Ultra Action Button — Complete Set

## Overview

During a running watch workout, pressing the **Action Button** (Apple Watch Ultra 1/2/3) completes the current set and advances to the next one — the hardware equivalent of tapping the on-screen complete button. If a rest timer is running, the same press stops that timer first, completes the currently selected next set, and starts its next applicable timer. The rest screen's on-screen Skip control remains skip-only. On non-Ultra watches with the S9 chip or newer (Series 9/10, Ultra 2/3), the **Double Tap** gesture triggers the same set completion via the on-screen button.

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
3. Each press calls `GymStreakCompleteSetIntent.perform()`, which calls `WatchWorkoutViewModel.handleActionButtonPress()` via the `AppStateProvider` singleton and returns a **plain `.result()`**. The donated next action is session-persistent: Apple's workout example donates once after collection begins, then every later press during that session runs the same action without another donation. The intent declares `static let supportedModes: IntentModes = .background` — it runs **without foregrounding the app** (do not reintroduce `openAppWhenRun`). `perform()` logs `started`/`finished` lines so a stuck press is diagnosable from the console.
4. `handleActionButtonPress()`:
   - no-op unless a workout is active
   - if `isResting`, stops and clears the current timer without returning
   - completes the selected incomplete set via `toggleSetCompletion(...)` — the same superset-aware path the on-screen button uses (new rest-timer rules, superset round detection, advance-to-next-set)
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
2. Reboot the watch — the Action Button settings list and the intent index are known to refresh lazily. **This also applies to changes in an existing intent's metadata** (`supportedModes`, result shape): confirmed on device 2026-07-21, where without a reboot the shell kept routing presses with the previous build's cached registration — including one state where presses stopped being delivered entirely — and after a reboot the same binary worked perfectly. Never judge an intent-metadata change without a reboot in between.
3. Verify the picker now lists GymStreak (this is the cheap proof that the intents are registered — even if the user never assigns it).
4. Start a workout and check the Xcode console: `Action Button: complete-set intent donated` vs `donation failed: …`. A failure with `LNTranscriptErrorDomain error 1003` is the known watchOS 26.5 donation regression (see gotchas).
5. A press with no donated next action falls back to the assigned default (e.g. opens Apple's Workout app) — that symptom means the donation never registered, not that the routing requires reassignment.

## Edge cases & gotchas

- **Hardware**: Action Button exists only on Ultra models; the intents compile and ship everywhere but never fire elsewhere. Double Tap requires S9 chip+ (Series 9/10, Ultra 2/3).
- **No detection API**: the app cannot read or set the user's Action Button assignment, and cannot detect Ultra-specific capability cleanly — there is no in-app indicator of whether the button is configured.
- **Water Lock**: when active, the first press unlocks Water Lock; subsequent presses reach the app. OS behavior, not suppressible.
- **Donation lifetime**: the current next action persists while the workout session is active. Donation is awaited when the session reaches `.running` (and again after a resume). Nothing runs a per-press donation and there is nothing to clean up at workout end — the action dies with the session.
- **Already-completed set**: `handleActionButtonPress` guards against re-completing (`!set.isCompleted`) so a press on a completed set does nothing rather than un-completing it.
- **Press during rest (regression fixed 2026-07-22):** the intent was delivered correctly, but `handleActionButtonPress()` called the skip-only action and returned before set completion. The Action Button now stops the active timer and continues into the shared completion path in the same press; the next selected incomplete set completes and starts its own applicable timer. The on-screen Skip control still only skips.
- **UI testing**: donation is skipped under `-UI_TESTING` (no HealthKit session exists there).
- **Press hung with "»Satz abschließen« … ist fehlgeschlagen" + "Einstellungen öffnen" (fixed 2026-07-21, two-part)**: on device (Ultra, watchOS 26.x) a press showed the orange intent overlay with the correct title (so donation/resolution worked), hung for seconds, then failed with the generic system intent-failure alert. Two independent problems were fixed:
  1. `GymStreakCompleteSetIntent` used the legacy `static var openAppWhenRun: Bool { true }`, **deprecated in watchOS 26** and equivalent to `supportedModes = .foreground(.immediate)` — every press forced a full foreground-activation handshake *before* `perform()`, even with the app already frontmost during the workout, and that handshake can stall past the system's intent timeout. Fix: `static let supportedModes: IntentModes = .background` — `perform()` only calls into the live view model and presents no UI, so no foregrounding is needed; a press also works from the watch face. `GymStreakStartWorkoutIntent` deliberately keeps `openAppWhenRun = true` — the `StartWorkoutIntent` protocol requires it per Apple's Action Button article.
  2. The failure persisted after (1), with device logs showing the press's set completion actually running (rest timer started) while the overlay still hung — so the hang was in **closing the press's transaction**, not in `perform()`'s work. Returning `.result(actionButtonIntent: …)` redundantly supplies a follow-on action while closing the transaction. The static complete-set action is already session-persistent, so `perform()` now returns plain `.result()`.
  **Follow-up regression fixed 2026-07-21:** the first plain-result implementation also launched a fire-and-forget re-donation after every press. That is not Apple's documented workout pattern; the unawaited `linkd` registration raced intent completion and could leave the next press—most visibly the press during the newly started rest timer—with no working action. The per-press donation was removed, and the one session-start/resume donation is awaited instead.
  **Device verification still required after this correction** (Ultra, watchOS 26.x, after a watch reboot — see the reboot note under Troubleshooting): first press completes a set and starts rest; second press during rest stops that timer, completes the next set, and starts its timer, with one donation log at session start rather than after each press.
  **Discarded earlier theory**: an interim fix attributed the failure to the workout UI being frozen during HealthKit finalization (`isEnding` gating input) — that freeze was real and separately fixed, but it was not what broke the intent. Sources: [`openAppWhenRun` deprecation](https://developer.apple.com/documentation/appintents/appintent/openappwhenrun-475kn), [`supportedModes`](https://developer.apple.com/documentation/appintents/appintent/supportedmodes), WWDC25 session 275 ("Explore new advances in App Intents"), [Apple Community thread showing the identical generic failure alert for Shortcuts on watchOS 26](https://discussions.apple.com/thread/256153401).
- **Press hangs then fails after a REINSTALL or hard-close+relaunch — cleared only by a watch reboot (watchOS 26 OS regression, diagnosed 2026-07-23, NOT an app bug)**: on the first re-install over an existing install (Xcode reinstall observed; TestFlight/App Store update path still unverified) — and also after a hard-close + relaunch of the watch app — a press during a running workout shows the orange overlay with the correct localized title ("Satz abschließen"), hangs several seconds, then fails with the generic *"»Satz abschließen« in GymStreakWatch ist fehlgeschlagen"* alert. A full **watch reboot** is the only thing that fixes it; afterwards the identical binary works perfectly until the next reinstall/relaunch.
  - **The failure is upstream of our code — `perform()` never runs.** In the failing case the app's own `"Action Button: complete-set perform() started"` line does NOT appear in the console, while `"Action Button: complete-set intent donated"` DOES (the fresh donation succeeds every time). So donation/title-resolution work; the system simply never dispatches the intent into our process. Nothing in `perform()` or `donateActionButtonIntent()` can fix this, and there is **no app-facing API** to invalidate or refresh the stale state (the only surfaces are `perform()`, `donate(result:)`, `supportedModes`; `updateAppShortcutParameters()` only refreshes static AppShortcut metadata, not dynamic follow-on donations or session-service state). Re-donating on launch does not help — donation already succeeds; the break is downstream of it.
  - **Root cause (OS daemon state).** The telltale device log at the failing press is:
    ```
    -[SPRemoteInterface _appRecoverAnyExtendedRuntimeSession:]_block_invoke:4350: Got no sessions back
    from -[CSLSSessionService existingRunningSessions:] or -[CSLSSessionService existingScheduledSessions:]
    after receiving a PUICInitializeSessionServiceAction
    ```
    This is watchOS's **private extended-runtime / workout-session bookkeeping** reporting it has no session record for our process — even though the `HKWorkoutSession` is genuinely `.running` and the donation just succeeded. A `.background`-mode Action Button intent needs the system to attach its dispatch to that session context (the reason `workout-processing` in `WKBackgroundModes` is mandatory). After a reinstall/relaunch the App-Intents dispatch layer and the session-service layer are out of sync; with no session record to attach to, the system tries, hangs, times out, and shows the generic failure alert. A reboot restarts those daemons and reconciles them.
  - **Corroboration (this is Apple's bug, acknowledged).** [Apple Developer Forums #804276](https://developer.apple.com/forums/thread/804276) shows the *identical* `CSLSSessionService`/`SPRemoteInterface` "Got no sessions back" signature in a different feature (workout mirroring); Apple DTS confirmed it, filed it as a duplicate of radar **FB20723311**, still unresolved through 26.1 RC, reboot-only fix. Broader Action Button freeze/failure regression on all Ultra generations is acknowledged by Apple support ([heise](https://www.heise.de/en/news/watchOS-26-Problems-with-the-Action-button-on-the-Apple-Watch-Ultra-11089620.html), [Apple Community #256253839](https://discussions.apple.com/thread/256253839)) — third-party workout apps' only known fix there is also a reboot. This is the same OS fragility as the metadata-change reboot note under Troubleshooting, resurfacing under a reinstall/relaunch trigger.
  - **Open question — TestFlight/App Store update path (UNTESTED, decision-critical).** An Xcode reinstall-over-existing is a full uninstall+reinstall with fresh code-signing — a materially different install-record transition than an atomic store version-replace, so store updates *might* dodge it (precedent that these daemons key state to install identity: [FB13281659](https://github.com/feedback-assistant/reports/issues/425)). BUT the corroborating evidence above shows this bug class reproducing under normal use with no reinstall at all, so "store updates are safe" is optimism, not a finding. **Must be tested explicitly:** install build N, update to N+1 over it, then WITHOUT rebooting start a workout and press the Action Button.
  - **Decision / mitigation.** Do NOT attempt a code fix (no reachable API; `perform()` is already correct and minimal). If the TestFlight-update test reproduces it, mitigate with a **user-facing note** (one-time post-update tip and/or release note: "If the Action Button doesn't complete a set after updating, restart your Apple Watch once"), mirroring how Apple and other workout apps handle the broader regression. If the update path does NOT reproduce it, this is a dev-only annoyance and can be ignored. Worth filing Feedback against FB20723311 with our console excerpt — it is likely the most precisely-isolated repro of this specific reinstall→reboot cycle currently documented.
- **`WAGUIPrimaryActionSpotlightView` / `WAGUIPrimaryActionFocusHighlightOverlayView` console warnings** ("Adding … as a subview of UIHostingController.view is not supported"): the system's Double-Tap primary-action highlight overlay failing to attach to the SwiftUI hierarchy around `.handGestureShortcut(.primaryAction)`. Appears at workout-view presentation; watchOS-side noise, not app-controllable, and unrelated to the Action Button intent flow (the orange overlay is system-shell UI, not injected in-app). Verify Double Tap still highlights/works when touching this area.
- **watchOS 26.5 regression**: donation override reportedly fails with `LNTranscriptErrorDomain error 1003` when the button is assigned to "Open App" (not the Workout function). Testing should cover both assignments.
- **Simulator**: the Action Button cannot be tested in the simulator (no hardware); on-device testing on an Ultra is required. (The KhaosT reference example notes `actionButtonIntent` does not work on simulator.)
- **Simulator donation noise (fixed 2026-07-12)**: in the simulator the donation itself always fails with `NSCocoaErrorDomain Code=4099 — connection to com.apple.linkd.transcript invalidated`, because `linkd` (the daemon backing the Siri/Shortcuts transcript store that donations write to) doesn't run there — the same "daemon absent in simulator" pattern known from other XPC services. Since the Action Button flow can't be exercised in the simulator anyway (see above), `donateActionButtonIntent()` is now compiled out with `#if !targetEnvironment(simulator)`. Note this simulator error is **distinct** from the on-device watchOS 26.5 `LNTranscriptErrorDomain 1003` regression above; the on-device `do/catch` logging is kept so that regression stays visible.

## References

- Apple: [Responding to the Action button on Apple Watch Ultra](https://developer.apple.com/documentation/appintents/actionbuttonarticle)
- Apple: [StartWorkoutIntent](https://developer.apple.com/documentation/appintents/startworkoutintent)
- Apple: [AppIntent `supportedModes`](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)
- Apple: [Intent result with an Action Button continuation](https://developer.apple.com/documentation/appintents/intentresult/result(actionbuttonintent:))
- Reference implementation: [KhaosT/WatchActionButtonExample](https://github.com/KhaosT/WatchActionButtonExample)
- watchOS 26 regression (same `CSLSSessionService` signature, Apple-acknowledged, radar FB20723311, reboot-only fix): [Apple Developer Forums #804276](https://developer.apple.com/forums/thread/804276)
- watchOS 26 Action Button regression (broad, Apple support acknowledged): [heise](https://www.heise.de/en/news/watchOS-26-Problems-with-the-Action-button-on-the-Apple-Watch-Ultra-11089620.html), [Apple Community #256253839](https://discussions.apple.com/thread/256253839)
- Install-path-dependent App Intents daemon state precedent: [FB13281659 / feedback-assistant#425](https://github.com/feedback-assistant/reports/issues/425)
