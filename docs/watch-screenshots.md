# Apple Watch Screenshots Pipeline

Automated App Store screenshot generation for the Apple Watch app using Fastlane Snapshot.

## Overview

The watch screenshot pipeline captures 4 screenshots per device per language in dark mode, covering the main user flow of the watch app.

## Screenshot Scenarios

| # | Screen | View | Description |
|---|--------|------|-------------|
| 01 | Routine List | `RoutineListView` | Shows available workout routines |
| 02 | Routine Detail | `RoutineDetailView` | Exercise breakdown with "Start Workout" button |
| 03 | Active Workout | `ExerciseListView` | Running workout with progress header and exercise rows |
| 04 | Set Editor | `FullScreenSetEditorView` | Weight/reps editing interface |

## Target Devices

- **Apple Watch Ultra 3 (49mm)** - watchOS 26.2
- **Apple Watch Series 11 (46mm)** - watchOS 26.2

## Languages

- English (en-US)
- German (de-DE)

## How to Run

### Watch screenshots only
```bash
bundle exec fastlane watch_screenshots
```

### iPhone + Watch combined
```bash
bundle exec fastlane all_screenshots
```

### Claude Code slash commands
- `/screenshots` - iPhone + Watch combined
- `/screenshots-iphone` - iPhone only
- `/screenshots-watch` - Watch only

## Architecture

### Test Data Seeding

The watch app detects the `-UI_TESTING` launch argument and seeds sample data directly into the `RoutineStore`:

```
GymStreakWatchApp.connectServices()
  └── if -UI_TESTING flag present
        └── routineStore.updateRoutines(WatchTestDataSeeder.sampleRoutines())
      else
        └── WatchConnectivityManager.shared.setRoutineStore(routineStore)
```

**`WatchTestDataSeeder`** (`GymStreakWatch Watch App/TestData/WatchTestDataSeeder.swift`):
- Creates 3 routines: Push Day, Pull Day, Leg Day
- Includes localized names (en/de) matching the iOS `TestDataSeeder`
- Push Day includes a superset (Lateral Raises + Tricep Pushdowns)
- Uses realistic weights (kg) and rep schemes
- Language detection: reads `AppleLanguages` user default (set by Fastlane via `-AppleLanguages` launch argument), falls back to `Locale.current`

### HealthKit Bypass

`WatchWorkoutViewModel.startWorkout()` detects `-UI_TESTING` and:
- Skips HealthKit authorization and workout session start
- Immediately sets `workoutState = .running` (bypasses "Loading Metrics" spinner)
- Provides mock values: heart rate (142), calories (87), elapsed time ("12:34")

Notification permission requests are also skipped during UI testing.

### Test Flow

The UI test (`GymStreakWatchUITests.swift`) navigates through the watch app:

1. **Routine List** - App launches, wait for "Push Day", capture
2. **Routine Detail** - Tap "Push Day", wait for exercises, capture
3. **Active Workout** - Tap "Start Workout", workout starts with mock data, capture
4. **Set Editor** - Tap first exercise row, capture weight/reps editor

### Xcode Target

The `GymStreakWatchUITests` target was created programmatically via `fastlane/create_watch_ui_test_target.rb`:
- Type: UI test bundle
- Test host: GymStreakWatch Watch App
- SDK: watchOS / watchsimulator
- Uses a synchronized root group (`GymStreakWatchUITests/` directory)
- Shared scheme: `GymStreakWatchUITests.xcscheme`

## Key Files

| File | Purpose |
|------|---------|
| `GymStreakWatchUITests/GymStreakWatchUITests.swift` | UI test class with screenshot capture flow |
| `GymStreakWatchUITests/SnapshotHelper.swift` | Fastlane Snapshot helper (copy from iOS) |
| `GymStreakWatch Watch App/TestData/WatchTestDataSeeder.swift` | Sample routine data for UI testing |
| `GymStreakWatch Watch App/GymStreakWatchApp.swift` | `-UI_TESTING` flag detection in `connectServices()` |
| `GymStreakWatch Watch App/ViewModels/WatchWorkoutViewModel.swift` | HealthKit bypass for UI testing |
| `fastlane/Fastfile` | `watch_screenshots` and `all_screenshots` lanes |
| `fastlane/create_watch_ui_test_target.rb` | Script to create the Xcode test target |

## Output

Screenshots are saved to `fastlane/screenshots/{language}/` alongside iPhone screenshots.

Watch screenshot filenames follow the pattern:
```
Apple Watch Ultra 3 (49mm)-01-Watch-Routine-List-dark.png
Apple Watch Series 11 (46mm)-02-Watch-Routine-Detail-dark.png
```

## Troubleshooting

### Simulator not found
Ensure the correct watchOS simulator runtime is installed:
```bash
xcrun simctl list runtimes | grep watchOS
```

### Build fails with "No such module"
The `GymStreakWatchUITests` target depends on the watch app. Make sure the watch app builds first:
```bash
xcodebuild build-for-testing -scheme GymStreakWatchUITests -sdk watchsimulator \
  -destination "platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)"
```

### Test data not appearing
Verify the `-UI_TESTING` launch argument is being passed. The `WatchTestDataSeeder` only runs when this flag is present. Check `GymStreakWatchApp.connectServices()`.

### German locale shows English data
The `WatchTestDataSeeder` detects the language from the `AppleLanguages` user default, which Fastlane sets via the `-AppleLanguages` launch argument. On watchOS simulators, `Locale.current` may not reflect the launch argument override, so the seeder explicitly reads `UserDefaults.standard.array(forKey: "AppleLanguages")`.

### Set Editor screenshot fails
The exercise rows in `ExerciseListView` use `.accessibilityElement(children: .combine)`, so they appear as combined button elements. The test queries for exercise rows using `app.buttons.matching(NSPredicate(format: "label CONTAINS %@", exerciseName))` rather than `app.staticTexts[exerciseName]`.
