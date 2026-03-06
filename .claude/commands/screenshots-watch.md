# Claude Command: Watch Screenshots

Generate Apple Watch-only App Store Connect screenshots in dark mode using Fastlane.

## Instructions

Run the Fastlane `watch_screenshots` lane from the project root directory to generate dark mode screenshots for Apple Watch only.

1. Execute the following command from the project root:
   ```
   bundle exec fastlane watch_screenshots
   ```
2. Monitor the output for errors. The lane will:
   - Run UI tests on Apple Watch Ultra 3 (49mm) and Apple Watch Series 11 (46mm) simulators
   - Capture 4 screenshots per device per language: Routine List, Routine Detail, Active Workout, Set Editor
   - Output to `fastlane/screenshots/` without clearing existing iPhone screenshots
3. If the lane succeeds, report how many screenshots were generated and where they are located (`fastlane/screenshots/`)
4. If the lane fails, analyze the error output and suggest fixes
