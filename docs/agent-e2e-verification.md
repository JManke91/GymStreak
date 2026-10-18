# Agent-run end-to-end verification (watch ↔ iPhone)

**What it is.** A scripted check that drives the real watch and iPhone apps on a
paired simulator — record a workout, save it to Apple Health, sync it to the
iPhone, crash the watch app mid-session — and asserts on the outcome without a
human tapping anything. It exists so a finished watch ticket arrives at the user
with only the few checks a simulator cannot make, instead of a 19-step manual list.

```
bundle exec fastlane e2e_watch                    # build, install, every suite
bundle exec fastlane e2e_watch suite:mat_session  # one suite
scripts/e2e/run.sh check_mat_suggestion_from_zones # one check
E2E_SKIP_BUILD=1 scripts/e2e/run.sh mat_session   # reuse the last build
```

It takes minutes: scenarios run in real time (a mat session must last 60 s to be
saved). Exit code is non-zero when any check fails; each check prints ✓ / ✗.

## How it works

| Piece | Where | Role |
|---|---|---|
| `WatchE2EScenarioRunner` | `GymStreakWatch Watch App/TestData/` (`#if DEBUG`) | Reads a scenario name at launch and drives the same view model the views drive; logs one `E2E …` line per step (category `E2E`), including a read-back of the newest Health workout's activity type and session kind |
| `scripts/e2e/lib.sh` | repo | Pair lookup, build/install, log reading, watch outbox and iPhone SwiftData store inspection, crash, Health grant |
| `scripts/e2e/<feature>.sh` | repo | One `suite_<name>` per feature, made of `check_…` functions |
| `scripts/e2e/run.sh` | repo | Sources everything, runs the requested suites, prints the tally |
| `e2e_watch` lane | `fastlane/Fastfile` | Wrapper — if `bundle exec fastlane` fails to load on a Mac whose system-Ruby bundler lacks gems, run `scripts/e2e/run.sh <suite>` directly; the lane does nothing else |

**Driving the watch.** A scenario is a launch argument
(`-E2E_SCENARIO mat-record -E2E_SPORT bjj -E2E_SECONDS 65`) **or** a
`defaults write <watch bundle> E2E_SCENARIO …` value, which is consumed on read.
The defaults route exists for crash checks: watchOS relaunches the app itself after
a crash, without arguments, so the scenario that should run on that relaunch is
written before the kill.

**Reading results.**
- Watch: `xcrun simctl spawn <watch> log show --start … --predicate 'category == "E2E"'`.
- iPhone: the SwiftData store in the phone simulator's App Group
  (`…/Library/Application Support/default.store`), queried with `sqlite3`
  (e.g. `ZMATSESSION.ZSPORTRAW`).
- Watch outbox: `Conditioning/mat-outbox.json` in the watch's App Group.

**Injected heart rate.** `-E2E_HEART_RATE <bpm>` makes the runner call the workout
manager's `onHeartRate` once a second while the session runs — the same callback
`HKLiveWorkoutBuilder`'s samples reach the view model on — so the zone tally, the
suggestion, the review and the sync all see it. The simulator's own ~60 bpm samples
keep arriving in between; the tally caps each gap at 15 s, so a 1 s feed dominates.
Not covered: the real sensor's samples crossing the zones, and the injected values
are not in the saved Health workout. Zones come from a profile written to the
iPhone simulator's defaults (`set_phone_heart_rate_profile`, key
`conditioning.heartRateProfile`), sent to the watch with the conditioning offer on
the next iPhone launch.

**Crash.** `kill -9` of the watch app's host process — watchOS sees a crash, not a
clean exit. With a workout running, watchOS relaunches the app **in the
background** within a second or two (asserted: a new process appears). The app's
launch work — `AppState.connectServices()`, which runs the recovery coordinator and
the scenario runner — hangs off the root view's `.task`, so it runs only once the
app is opened; the harness then launches it, as the user would by raising their
wrist. (2026-10-18: the first run omitted that step; the recovered session sat
unfinished and blocked the next check's start.)

**Relaunch throttling.** Carousel throttles an app that exits repeatedly
("next permitted launch date after 4 exits is in 480.0s"). Every
`--terminate-running-process` launch counts as an exit, so if the relaunch
assertion fails right after many runs, wait out the window before suspecting
the app.

**Health permission.** `simctl privacy` has no Health service, and the watch sheet
cannot be tapped headless (Simulator.app is not installed on this Mac). The
harness triggers the app's request once, then sets the rows in the watch
simulator's `Library/Health/healthdb.sqlite` `authorization` table while the
simulator is shut down: `102` for share requests (`request = 201`) and `103` for
read requests (`request = 202`). These values were copied from simulators where
the sheet had been approved by hand. They are undocumented — if the run starts
failing at "Health", re-derive them the same way.

## What the simulator does and doesn't prove (probed 2026-10-18, Xcode 26, watchOS 26.5)

| Behaviour | Simulator | Notes |
|---|---|---|
| `HKWorkoutSession` + live builder run, workout saves to Health | yes | read back via `HKSampleQueryDescriptor` |
| Heart-rate samples during a workout | yes, ~58–64 bpm, not steerable | Produced by a hard-coded `HDFakeDataCollector` in the simulator's HealthDaemon ("returning fake heartrate for simulator"); no simctl, defaults or Xcode control exists (researched 2026-10-18). Higher values come from injection, below |
| Crash relaunch via `handleActiveWorkoutRecovery()` | yes | Contradicts older notes and forum reports; see docs/watch-workout-recovery.md |
| Watch → iPhone `sendMessage`, application context | yes | |
| Watch → iPhone **`transferUserInfo`** | **no** | Handed to the system, never delivered, even after relaunching the iPhone app. Matches long-standing forum reports. Conditioning and mat sessions therefore also take the `sendMessage` fast path when reachable (as strength workouts always did) — on device that's simply a faster arrival, and the iPhone's idempotent ingest absorbs the duplicate |
| iPhone off, then back | yes, with a nudge | The phone simulator is shut down and rebooted; the session arrives once. The iPhone's ack and queue-drain request right after boot go out before it is reachable, by `transferUserInfo` only, and are lost between simulators — so the watch outbox stays non-empty until the watch app is opened again (the harness does that, as a user would). On hardware the queued ack delivers |
| Apple Health on the **iPhone** (Fitness app) | no | Watch Health data does not sync to the phone simulator |
| Physical sensor, wrist detection, real Bluetooth delivery | no | |

So a passing run proves the app's logic end to end — Health save and type,
payload, ingest, ack, outbox retirement, recovery from a real system relaunch —
but **not** that `transferUserInfo` itself delivers. On hardware that is Apple's
guaranteed queue, exercised by every user, and the fast path does not replace it.

## What still needs a human (per feature, short)

1. The real heart-rate sensor reaching the zones in a hard session (the logic after
   it is covered by injection).
2. The workout in the iPhone's Fitness app.
3. Delivery with the iPhone genuinely out of range (the guaranteed queue).

## Physical devices

`xcrun devicectl` installs and launches apps on the paired iPhone and Apple Watch,
and its `device copy from` lists `appDataContainer` and `appGroupDataContainer`
domains, so reading the watch's outbox and log-free results back from hardware
looks possible. It is untested (the watch was unavailable on 2026-10-18), and a
real workout on hardware still needs a wrist for heart rate and for the session
to count as worn. Treat it as the next thing to probe, not a capability.

## Adding a suite for a new watch feature

1. Add scenarios to `WatchE2EScenarioRunner` that drive the feature's view model
   and log every outcome worth asserting as `key=value` pairs.
2. Add `scripts/e2e/<feature>.sh` with `check_…` functions and a `suite_<name>`.
   Use a value unique to each check (here: one sport per check) so iPhone row
   counts tell "arrived exactly once" apart.
3. Run it before handing the ticket over, and list only the human-only checks above
   in the manual hand-off.

## Suites

- **`mat_session`** (positioning ticket 05, docs/fight-conditioning.md): record →
  save → Martial Arts in Health → one iPhone History row → outbox drained; iPhone
  off at Save → held in the outbox → arrives once after reboot; crash while running
  → resumes running with its elapsed time → saves as Wrestling; crash on the review
  → comes back on the review → saves; with a heart-rate profile on the iPhone and 165 bpm
  injected for 5+ minutes, hard sparring is suggested, preselected and synced
  (`check_mat_suggestion_from_zones`, ~6 min). Full suite 28 checks.
- **`round_timer`** (positioning ticket 07, docs/fight-conditioning.md "Round timer"): a
  custom 2 × 30 s / 15 s plan (`launch_watch_round`, sport `other`) logs each phase, ends
  itself into the review with `rounds=2`, saves as a mat session → Health activity type
  3000 (`other`) with kind `mat` and duration ≥ 70 s → one iPhone History row → outbox
  drained; the same run with "Don't save" ends in `finished-discarded`, queues nothing
  and leaves the iPhone count unchanged. 16 checks, ~4 min.
