# Claude Command: Screenshots

Generate all App Store Connect screenshots (iPhone + Apple Watch) in dark mode using Fastlane.

## Instructions

Run the Fastlane `all_screenshots` lane from the project root directory to generate dark mode screenshots for both iPhone and Apple Watch.

1. Execute the following command from the project root:
   ```
   bundle exec fastlane all_screenshots
   ```
2. Monitor the output for errors. The lane will:
   - Run iPhone screenshots first (iPhone 17 Pro Max, with Watch dependency disabled)
   - Resize iPhone screenshots from 1320x2868 to 1284x2778 for App Store 6.5" display
   - Run Watch screenshots (Apple Watch Ultra 3 49mm + Series 11 46mm)
3. If the lane succeeds, report how many screenshots were generated and where they are located (`fastlane/screenshots/`)
4. If the lane fails, analyze the error output and suggest fixes
