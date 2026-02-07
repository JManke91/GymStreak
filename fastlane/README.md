fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Generate screenshots for App Store (light and dark mode)

### ios screenshots_light

```sh
[bundle exec] fastlane ios screenshots_light
```

Generate only light mode screenshots

### ios screenshots_dark

```sh
[bundle exec] fastlane ios screenshots_dark
```

Generate only dark mode screenshots

### ios test_ui

```sh
[bundle exec] fastlane ios test_ui
```

Run UI tests without capturing screenshots

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload screenshots to App Store Connect

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
