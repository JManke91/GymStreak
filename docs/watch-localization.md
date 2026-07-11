# watchOS Localization (String Catalog)

## What it is
The watch target (`GymStreakWatch Watch App`) is localized in English (source) and German via a single String Catalog: `GymStreakWatch Watch App/Localizable.xcstrings`. Before 2026-07-11 the watch target had **no localization at all** — every string was a hardcoded English literal (while iOS localizes via legacy `en.lproj`/`de.lproj` `Localizable.strings` in `GymStreak/Resources/`).

## How it works
- The catalog is hand-authored JSON at the watch target root, next to `Assets.xcassets`. Because the project uses `PBXFileSystemSynchronizedRootGroup` (files auto-included by directory), no pbxproj edit was needed — the build compiles it into `en.lproj`/`de.lproj/Localizable.strings` in the app bundle automatically.
- Project `knownRegions` already contained `de` (from the iOS target), so no project-level change was needed.
- **Convention: the English text is the key.** SwiftUI `Text("...")`, `Label("...", ...)`, `.navigationTitle("...")`, `.accessibilityLabel("...")` literals resolve as `LocalizedStringKey` against the catalog with no code changes. `LocalizedStringResource` in App Intents (`Intents/GymStreakIntents.swift`) resolves the same way.
- Keys whose German equals the English ("Workout", "Pause" as a verb-label, "BPM", "kg") are **deliberately omitted** — a missing key falls back to the literal, which is already correct. Don't "fix" this by adding identical entries. ("Superset" is NOT such a key: German consistently uses "Supersatz", matching the iOS `superset.*` strings.)
- Plural-sensitive keys carry explicit plural variations for **both** en and de (en must be explicit there, otherwise "1 exercises"): `%lld exercises`, `%@, %lld exercises`, `%lld sets`, `You modified %lld sets. Update your routine template?`.

## Call sites that needed code changes (plain `String`, not auto-localized)
- `WatchWorkoutViewModel.swift` — `UNMutableNotificationContent` title/body (UserNotifications takes plain `String`) and the `?? "Workout"` summary fallback → wrapped in `String(localized:)`.
- `ExerciseListView.swift` — `ExerciseStatus.accessibilityLabel` switch literals → `String(localized:)`; the exercise-row accessibility label had English fragments (`", part of superset"`) buried inside one big interpolation (untranslatable as written) → restructured into `rowAccessibilityLabel` composing localized parts.
- `ActiveWorkoutView.swift` — hand-rolled English pluralization (`set\(count == 1 ? "" : "s")`) can't translate → replaced with the plural-variation key `You modified %lld sets. Update your routine template?`.
- `FullScreenSetEditorView.swift` / `WatchWorkoutSummaryView.swift` — `CompactValueEditor(label:unit:)` and `statRow(label:value:)` take `String` params, so literals at the call sites ("WEIGHT", "REPS", "reps", "Duration", "Sets", "Calories", "%lld cal") are wrapped in `String(localized:)` at the call site. The param types were intentionally left as `String` (no API churn).

## Deliberate omissions
- **Dead code is not localized**: `ExerciseSetView.swift`, `InlineSetEditorView.swift`, `ValueStepperView.swift`, `WatchRoutinesViewModel.swift` (never instantiated), and the fully commented-out `SetNavigationBar.swift` / `RestTimerEditorSheet.swift`. If any of these are revived, localize their strings then. Same for `WatchWorkoutViewModel.errorMessage` — set in three places but never bound to any UI.
- **Muscle group names are NOT localized on the watch**: `WatchExercise.muscleGroup` arrives from iOS as the raw English key (iOS localizes them only at display time via its own table in `Domain/Models/MuscleGroups.swift`). Localizing them on the watch would require syncing localized names or duplicating the iOS table — deferred as a product decision. A German watch user sees "Chest" etc. in exercise rows.
- Unit/abbreviation display inconsistencies ("CAL" in `MetricsView` vs "kCal" in `ExerciseListView`; dead views still saying "lbs" while the app is kg-based) were left as-is — display-design cleanup, not localization.

## How to add a new watch string
Write the English literal in SwiftUI as usual, then add a key + `de` entry to `Localizable.xcstrings`. If the string reaches the user through a plain `String` API (notifications, computed `String` properties, `String` function params), wrap the literal in `String(localized:)` or it will silently stay English.
