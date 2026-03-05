# Claude Command: Screenshots

Generate App Store Connect screenshots in dark mode using Fastlane.

## Instructions

Run the Fastlane `screenshots` lane from the project root directory to generate dark mode screenshots for App Store Connect.

1. Execute the following command from the project root:
   ```
   bundle exec fastlane screenshots
   ```
2. Monitor the output for errors. The lane will:
   - Temporarily disable the Watch app dependency for simulator builds
   - Run UI tests to capture dark mode screenshots on iPhone 17 Pro Max
   - Resize screenshots from 1320x2868 to 1284x2778 for App Store 6.5" display
   - Restore the Watch app dependency when done
3. If the lane succeeds, report how many screenshots were generated and where they are located (`fastlane/screenshots/`)
4. If the lane fails, analyze the error output and suggest fixes
