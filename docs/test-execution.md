# Test Execution & Selection (test plan, schemes, timings)

## What this is

How tests are *selected and run* in this project — which targets a given scheme executes,
what the default `Cmd+U` / `xcodebuild test` action covers, and why. For what the unit tests
actually cover, see `docs/unit-testing.md`; for the screenshot pipeline see
`docs/watch-screenshots.md`.

## The problem this solves

Before the test plan existed, the `GymStreak` scheme's `TestAction` listed both
`GymStreakTests` and `GymStreakUITests` as `Testables`. There was **no `.xctestplan` in the
project at all**, so test selection was all-or-nothing per scheme: every `Cmd+U` and every
`xcodebuild test -scheme GymStreak` without an explicit `-only-testing:` ran the entire UI
suite, including the App Store screenshot generators.

Measured on 2026-07-30 (iPhone 17 Pro Max, iOS 26.2, warm DerivedData):

| Selection | Wall clock | Time inside test bodies |
|---|---|---|
| `GymStreakTests` (383 unit tests) | 69 s | **8.0 s** |
| `GymStreakUITests` (8 UI tests) | **408 s** | 205 s |

97 % of the default test action was the UI target. The unit suite is effectively free — its
69 s is almost entirely build, install and host-app launch, not test execution (only three
tests exceed 0.6 s, and those are deliberate performance budgets).

Per-test UI breakdown from that run:

```
 35 s  HistoryResponsivenessUITests/testHistoryInteractionsDoNotBlockMainRunLoop   real regression value
101 s  WorkoutDeletionUITests (4 tests)                                            real regression value
 60 s  GymStreakUITests/testGenerateScreenshots{,DarkMode}                         FAILED — see below
  9 s  GymStreakUITestsLaunchTests/testLaunch                                      asserted nothing
```

## The test plan

`GymStreak.xctestplan` (repo root, next to `GymStreak.xcodeproj`) is the scheme's single,
default test plan. `GymStreak.xcscheme`'s `TestAction` now holds a `<TestPlans>` reference
instead of `<Testables>`.

It runs:

- `GymStreakTests` — everything, `parallelizable: false` (the suites are `@Suite(.serialized)`;
  see `docs/unit-testing.md` gotcha #4).
- `GymStreakUITests` — everything **except** the two screenshot generators, which are listed
  under `skippedTests`:
  - `GymStreakUITests/testGenerateScreenshots()`
  - `GymStreakUITests/testGenerateScreenshotsDarkMode()`

To add or remove a skip, edit the `skippedTests` array in the plan (Xcode's test-plan editor
writes the same JSON).

### Why the screenshot tests are skipped, not deleted

`testGenerateScreenshots` and `testGenerateScreenshotsDarkMode` are **App Store asset
production**, not regression tests. Fastlane invokes them explicitly through `only_testing:`
(`fastlane/Fastfile`, `snapshot` in the `screenshots` / `screenshots_dark` lanes), and they
depend on the erased + reinstalled simulator and the language file that `snapshot` sets up
(`Snapshot.deviceLanguage`, `erase_simulator: true`, `reinstall_app: true` in
`fastlane/Snapfile`).

Run from a plain `xcodebuild test` they **fail** —
`XCTAssertTrue failed - Bench Press exercise should be visible` — because the seeded state
and language setup aren't there. So they were not merely slow in the default action, they
were permanently red. They stay in the target because Fastlane needs them; the plan just
keeps them out of the default selection. **Skipping them here does not affect screenshot
generation** — Fastlane's `only_testing:` bypasses the plan's skip list.

### Deliberate omission: no second "Screenshots" test plan

An obvious-looking addition is a second plan that selects only the screenshot tests. It was
deliberately not added: Fastlane already targets them by name via `only_testing:` against the
`GymStreakUITests` scheme (`fastlane/Snapfile` sets `scheme("GymStreakUITests")`), so a second
plan would be an unused parallel mechanism. Add one only if a non-Fastlane caller ever needs
that selection.

## Removed: `GymStreakUITestsLaunchTests`

Deleted. It was unmodified Xcode template boilerplate — launch the app, attach a screenshot,
assert nothing — costing 9 s per run. `runsForEachTargetApplicationUIConfiguration = true`
did **not** multiply it in practice (the app declares a single UI configuration, so it ran
once), but the test had no value either way. Restore from git history if a launch-performance
baseline is ever wanted.

## Fixed alongside

### UI-test deployment target was ahead of the app

`GymStreakUITests` was built with `IPHONEOS_DEPLOYMENT_TARGET = 26.2` while the app target is
`26.1`. This is not cosmetic — it makes the tests unrunnable on the simulator runtime the app
itself supports:

```
Cannot test target "GymStreakUITests" on "iPhone 17 Pro": iPhone 17 Pro's iOS Simulator 26.1
doesn't match GymStreakUITests's iOS Simulator 26.2 deployment target.
```

Both its Debug and Release configurations are now `26.1`, matching the app. A test target's
deployment target should track the app target; raising it only narrows where the suite can run.

### Copy-pasted testables in unrelated schemes

`GymStreakWatch Watch App.xcscheme` and `GymStreakWidgetsExtension.xcscheme` both listed
`GymStreakUITests` as their testable — so testing either scheme launched the *iOS* UI suite.

- Watch App scheme → now references `GymStreakWatchUITests`.
- Widgets scheme → `Testables` removed entirely (there is no widget test target).

## Running tests

```bash
# Default action — unit tests + UI regressions, screenshot generators skipped
xcodebuild test -project GymStreak.xcodeproj -scheme GymStreak \
  -destination 'platform=iOS Simulator,id=<UDID>'

# Fast inner loop — 383 of the 391 tests, ~69 s
xcodebuild test -project GymStreak.xcodeproj -scheme GymStreak \
  -destination 'platform=iOS Simulator,id=<UDID>' -only-testing:GymStreakTests

# Screenshots (unaffected by the plan)
bundle exec fastlane screenshots
```

`-only-testing:` / `-skip-testing:` still compose on top of the plan, so the plan constrains
the default without taking away ad-hoc selection.

## Known remaining cost (not yet addressed)

The surviving UI tests still spend a large share of their runtime waiting rather than
asserting:

- `dismissSystemAlerts` waits 2 s for an "Allow" button and then 2 s for "Don't Allow"
  (`GymStreakUITests/WorkoutDeletionUITests.swift`), on every launch — but the app is launched
  with `-DISABLE_NOTIFICATIONS`, so neither alert ever appears. That is ~4 s of guaranteed
  dead time per test.
- `dismissCoachOptIn` adds a 5 s `waitForExistence` timeout on the same path.
- `GymStreakUITests.swift` contains 15 hardcoded `sleep()` calls (~17 s per screenshot pass)
  where `waitForExistence` would return as soon as the UI settles.

Replacing these with event-driven waits is the next available win; it was left out of this
change to keep the selection fix separate from behavioural edits to the tests.

Note also that `GymStreakTests` is a **hosted** test bundle (`TEST_HOST` → `GymStreak.app`)
and the watch app is embedded in `GymStreak.app` via an "Embed Watch Content" phase, so any
test build also builds the watch app. Fastlane works around this for screenshots with
`fastlane/disable_watch_dependency.rb` (it rewrites `project.pbxproj` and restores it in an
`ensure` block). That trick is deliberately **not** used for ordinary test runs — mutating the
project file mid-run is too fragile for the everyday loop.
