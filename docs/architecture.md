# GymStreak Architecture

## 1. Project Overview

GymStreak is a multi-platform fitness tracking app for iOS and Apple Watch that lets users create workout routines, execute workouts with set-by-set navigation (including superset support), track exercise progress over time, and sync data across devices. The app integrates with HealthKit for workout recording and uses CloudKit for cloud persistence.

### Tech Stack

| Technology | Purpose |
|---|---|
| **Swift** | Primary language |
| **SwiftUI** | 100% declarative UI on both iOS and watchOS |
| **SwiftData** | Persistence layer with CloudKit sync (iOS only) |
| **HealthKit** | Workout recording and health data integration |
| **WatchConnectivity** | Bidirectional iOS ↔ Watch communication |
| **ActivityKit** | Live Activities for rest timer display |
| **Fastlane** (~2.220) | Screenshot generation and App Store tooling |

**No external Swift package dependencies.** The project relies entirely on Apple frameworks.

### Targets

| Target | Platform | Files |
|---|---|---|
| GymStreak | iOS 18.5+ | 65 Swift files |
| GymStreakWatch Watch App | watchOS | 28 Swift files |
| GymStreakWidgets | iOS (widget extension) | 5 Swift files |
| GymStreakUITests | iOS UI tests | 4 Swift files |
| GymStreakWatchUITests | watchOS UI tests | 2 Swift files |
| **Total** | | **104 Swift files** |

---

## 2. Architecture Pattern

**Pragmatic MVVM** — ViewModels interact directly with SwiftData and system frameworks. The CLAUDE.md references Clean Architecture layers (Domain/Data/Presentation) as aspirational direction, but the current codebase uses a simplified two-layer approach:

```
┌──────────────────────────────────────────┐
│  PRESENTATION LAYER                      │
│  ├─ Views (SwiftUI)                      │
│  ├─ ViewModels (@MainActor ObservableObj)│
│  └─ Design System (Onyx components)      │
├──────────────────────────────────────────┤
│  DATA + DOMAIN LAYER (combined)          │
│  ├─ SwiftData @Model entities            │
│  ├─ Services (ExerciseProgressService)   │
│  ├─ Managers (HealthKit, WatchConn)      │
│  └─ Utilities (TimeFormatting, etc.)     │
└──────────────────────────────────────────┘
```

### Layer Boundaries

- **Views** own no business logic; they read from ViewModels and call ViewModel methods
- **ViewModels** own all state management, SwiftData queries, and orchestrate manager calls
- **Models** are SwiftData `@Model` classes with computed properties for domain logic (e.g., `exercisesGroupedBySupersets`)
- **Managers** are singletons for system integrations (HealthKit, WatchConnectivity)
- **Services** encapsulate query-heavy logic (exercise progress aggregation)

### What's NOT Present

- No repository protocol/implementation pattern — ViewModels query SwiftData directly
- No UseCase layer — business logic lives in ViewModels and Services
- No formal DI container — manual initialization and singletons

### Dependency Injection

Manual initialization, three patterns:

1. **ModelContext injection**: `@Environment(\.modelContext)` in Views → passed to ViewModel `init(modelContext:)`
2. **Singletons**: `WatchConnectivityManager.shared`, `CloudSyncObserver.shared`, `HapticManager.shared`
3. **EnvironmentObject (watchOS)**: `AppState` creates dependencies and injects via `.environmentObject()`

### Data Flow

```
User Action → View → ViewModel method
  → SwiftData mutation (insert/update/delete)
  → @Published property update → View re-render
  → Side effects (Watch sync, HealthKit save, notifications)
```

Cross-component communication uses `NotificationCenter`:
- `.cloudKitDataDidChange` — CloudKit remote changes trigger ViewModel refresh
- `.watchWorkoutCompleted` — Watch workout received, ViewModel creates WorkoutSession
- `.watchAppBecameAvailable` — Triggers routine sync to Watch

---

## 3. Module & Directory Structure

```
GymStreak/                              # iOS app target
├── GymStreakApp.swift                  # @main entry, ModelContainer setup, test seeding
├── ContentView.swift                  # TabView root (3 tabs: Routines, Exercises, History)
├── Models.swift                       # All SwiftData @Model definitions (7 models)
├── Models/
│   └── ExerciseProgressModels.swift   # Chart data types (not @Model, plain structs)
├── DesignSystem.swift                 # Onyx theme: colors, spacing, typography, haptics
├── ViewModels/
│   └── ExerciseProgressViewModel.swift
├── Services/
│   └── ExerciseProgressService.swift  # Progress data aggregation from workout history
├── Views/
│   ├── DesignSystem/                  # Reusable Onyx UI components (8 files)
│   │   ├── OnyxButton.swift
│   │   ├── OnyxCard.swift
│   │   ├── OnyxBadge.swift
│   │   ├── OnyxStepper.swift
│   │   ├── OnyxTextField.swift
│   │   ├── OnyxListRow.swift
│   │   ├── OnyxProgressRing.swift
│   │   └── OnyxEmptyState.swift
│   ├── Components/                    # Feature-specific reusable components
│   │   ├── Superset*.swift            # Superset UI components (5 files)
│   │   ├── MuscleGroup*.swift         # Muscle group badge + picker
│   │   ├── EquipmentTypePicker.swift
│   │   └── RestTimerConfigView.swift
│   ├── Charts/                        # Progress charting views
│   │   ├── ExerciseProgressChartView.swift
│   │   └── ChartTimeframePicker.swift
│   ├── Routines/
│   │   └── CreateRoutineFlow/         # Multi-step routine creation wizard
│   │       ├── CreateRoutineView.swift
│   │       ├── ExerciseSelectionView.swift
│   │       ├── ConfigureExerciseView.swift
│   │       └── PendingRoutineExercise.swift
│   └── ExerciseProgressListView.swift
├── Extensions/
│   ├── Color+AccentColor.swift
│   └── String+Localization.swift      # .localized computed property on String
├── Helpers/
│   └── SupersetLabelProvider.swift    # Superset letter labels (A, B, C...)
├── Resources/
│   ├── en.lproj/Localizable.strings   # English
│   └── de.lproj/Localizable.strings   # German
├── [Root-level view files]            # Legacy flat structure (see note below)
│   ├── RoutinesView.swift             # Routines tab list
│   ├── RoutineDetailView.swift        # Routine editing (primary set editing)
│   ├── RoutineExerciseDetailView.swift
│   ├── ExercisesView.swift            # Exercise library tab
│   ├── ExerciseDetailView.swift       # Exercise detail + progress
│   ├── ActiveWorkoutView.swift        # Live workout execution
│   ├── WorkoutHistoryView.swift       # History tab
│   ├── WorkoutDetailView.swift        # Completed workout detail
│   ├── SaveWorkoutView.swift          # Post-workout template update
│   ├── AddRoutineView.swift           # Routine creation sheet
│   ├── AddExerciseToRoutineView.swift # Exercise picker for routines
│   ├── AddExerciseView.swift          # New exercise creation
│   ├── AddExerciseToWorkoutView.swift # Add exercise during workout
│   ├── EditExerciseView.swift
│   ├── EditSetView.swift
│   ├── ExercisePickerView.swift
│   ├── SetInputComponents.swift       # HorizontalStepper, WeightInput
│   ├── RestTimerView.swift
│   └── ApplyToAllBanner.swift
├── [Root-level ViewModel files]       # Legacy flat structure
│   ├── RoutinesViewModel.swift        # Routine CRUD, superset ops, watch sync
│   ├── ExercisesViewModel.swift       # Exercise library CRUD
│   └── WorkoutViewModel.swift         # Workout execution, HealthKit
├── [Managers]
│   ├── WatchConnectivityManager.swift # iOS-side WatchConnectivity
│   ├── HealthKitWorkoutManager.swift  # HealthKit workout operations
│   └── CloudSyncObserver.swift        # CloudKit change notifications
├── [Support files]
│   ├── MuscleGroups.swift             # Muscle group definitions + localization
│   ├── EquipmentType.swift            # Equipment enum with SF Symbols
│   ├── WatchModels.swift              # Codable models for watch sync
│   ├── RestTimerAttributes.swift      # Live Activity attributes
│   ├── TimeFormatting.swift           # Time display utilities
│   └── TestDataSeeder.swift           # UI test data generation
└── Assets.xcassets/                   # App icons, colors

GymStreakWatch Watch App/               # watchOS target
├── GymStreakWatchApp.swift            # @main entry, AppState DI container
├── OnyxWatchDesignSystem.swift        # Watch-specific Onyx theme
├── Managers/
│   ├── RoutineStore.swift             # UserDefaults persistence (App Groups)
│   ├── WatchConnectivityManager.swift # Watch-side WatchConnectivity
│   └── WatchHealthKitManager.swift    # Watch HealthKit integration
├── ViewModels/
│   ├── WatchRoutinesViewModel.swift   # Routine display + sync handling
│   └── WatchWorkoutViewModel.swift    # Watch workout execution
├── Models/
│   └── WatchModels.swift              # Lightweight Codable sync models
├── Views/                             # All watch UI views (17 files)
│   ├── RoutineListView.swift          # Root navigation
│   ├── RoutineDetailView.swift
│   ├── ActiveWorkoutView.swift
│   ├── ExerciseListView.swift
│   ├── ExerciseSetView.swift
│   ├── SetListView.swift
│   ├── InlineSetEditorView.swift
│   ├── FullScreenSetEditorView.swift
│   ├── RestTimerView.swift
│   ├── RestTimerEditorSheet.swift
│   ├── MetricsView.swift
│   ├── ControlsView.swift
│   ├── CompleteSetButton.swift
│   ├── CompactSetNavigationBar.swift
│   ├── SetNavigationBar.swift
│   ├── CompactActionBar.swift
│   ├── CompactValueEditor.swift
│   └── ValueStepperView.swift
├── Intents/
│   └── GymStreakIntents.swift         # Siri / Action Button support
└── TestData/
    └── WatchTestDataSeeder.swift

GymStreakWidgets/                        # Widget extension
├── GymStreakWidgetsBundle.swift        # Widget bundle registration
├── GymStreakWidgets.swift              # Widget definitions
├── GymStreakWidgetsControl.swift       # Control widget
├── GymStreakWidgetsLiveActivity.swift  # Rest timer Live Activity UI
└── RestTimerAttributes.swift          # Activity attributes model

GymStreakUITests/                        # iOS UI tests
├── GymStreakUITests.swift             # Screenshot generation tests
├── GymStreakUITestsLaunchTests.swift
├── SnapshotHelper.swift               # Fastlane snapshot helper
└── UITestHelpers.swift

GymStreakWatchUITests/                   # Watch UI tests
├── GymStreakWatchUITests.swift
└── SnapshotHelper.swift

docs/                                   # Feature documentation
├── architecture.md                    # This file
├── superset-feature.md
└── watch-screenshots.md

fastlane/                               # CI/CD automation
├── Fastfile                           # Lane definitions (screenshots, upload)
├── Snapfile                           # Snapshot configuration
├── Appfile                            # App metadata
├── disable_watch_dependency.rb        # Build script for simulator
├── create_watch_ui_test_target.rb
├── screenshots/                       # Generated App Store screenshots
│   ├── en-US/
│   └── de-DE/
└── logs/
```

> **Note on root-level files**: Many views and ViewModels live at the GymStreak/ root level rather than in organized subdirectories. Newer files (Charts/, Components/, CreateRoutineFlow/) follow a directory-based organization. This is organizational debt, not a deliberate pattern.

---

## 4. Key Patterns & Conventions

### Naming Conventions

| Element | Convention | Examples |
|---|---|---|
| Types | PascalCase | `Routine`, `RoutinesViewModel`, `ExerciseProgressService` |
| Variables/Properties | camelCase | `routineExercises`, `currentSession` |
| Booleans | is/has/should prefix | `isCompleted`, `hasModifiedSets`, `isReachable` |
| Methods | camelCase verbs | `fetchRoutines()`, `updateSet()`, `syncRoutines()` |
| View files | PascalCase + View suffix | `RoutineDetailView.swift`, `ActiveWorkoutView.swift` |
| ViewModel files | PascalCase + ViewModel suffix | `RoutinesViewModel.swift`, `WorkoutViewModel.swift` |
| Design components | Onyx prefix | `OnyxButton`, `OnyxCard`, `OnyxBadge` |
| Watch design components | OnyxWatch prefix | `OnyxWatch.Colors`, `OnyxWatch.Spacing` |

### Error Handling

- **print-based logging** throughout — no unified logging framework (os.log)
- **Silent failures** with `try?` for non-critical operations (HealthKit queries)
- **do/catch with fallback** for critical paths (ModelContainer creation falls back to local-only)
- **No Result<T, E> types** — errors are typically logged and silently handled
- **@Published error state** in some ViewModels for user-facing errors

### State Management

| Pattern | Usage |
|---|---|
| `@Published` in `ObservableObject` | All ViewModels — primary state mechanism |
| `@State` | Local view-only UI state (expanded items, selection) |
| `@Binding` | Parent-to-child value passing (set editing) |
| `@Environment(\.modelContext)` | SwiftData access from views |
| `@EnvironmentObject` | watchOS DI (RoutineStore, WorkoutViewModel) |
| `@StateObject` | ViewModel lifecycle ownership |
| `NotificationCenter` | Cross-component communication |

### Navigation

**iOS**: Tab-based root with `NavigationStack` inside each tab.
- Navigation pushes for drill-down flows (routine → detail → exercise)
- Modal sheets for creation flows (`AddRoutineView`, `SaveWorkoutView`)
- `NavigationLink(value: UUID)` pattern — SwiftData models aren't Hashable, so `.navigationDestination(for: UUID.self)` is used

**watchOS**: Single `NavigationStack` from `RoutineListView`.
- Linear drill-down navigation
- Sheets for editors (rest timer, set editing)

### Async Patterns

- **async/await** exclusively — no Combine Publishers for async work
- **@MainActor** on all ViewModels and Managers
- **`Task { @MainActor in ... }`** for dispatching to main from nonisolated delegates (WCSessionDelegate)
- **`nonisolated func`** for delegate callbacks that can't be @MainActor

### Localization

- `String+Localization.swift` provides `.localized` computed property
- Keys use dot-notation: `"tab.routines"`, `"routine.detail.sets"`
- Two languages: English (`en.lproj`) and German (`de.lproj`)

### Haptics

- `HapticManager.shared` singleton in `DesignSystem.swift`
- Four levels: `.success()`, `.selection()`, `.light()`, `.medium()`
- Used at interaction points (completing sets, adding items)

---

## 5. Data Layer

### Persistence: SwiftData (iOS)

**Seven @Model entities** defined in `Models.swift`:

| Model | Purpose | Key Relationships |
|---|---|---|
| `Routine` | Workout template | → many `RoutineExercise`, → many `WorkoutSession` |
| `Exercise` | Exercise library item | → many `RoutineExercise` |
| `RoutineExercise` | Exercise-in-routine junction | → one Routine, → one Exercise, → many ExerciseSet |
| `ExerciseSet` | Set configuration (reps, weight, rest) | → one RoutineExercise |
| `WorkoutSession` | Completed workout record | → many WorkoutExercise, → one Routine |
| `WorkoutExercise` | Exercise in completed workout | → one WorkoutSession, → many WorkoutSet |
| `WorkoutSet` | Completed set data | → one WorkoutExercise |

**CloudKit sync**: Configured as `.private("iCloud.com.jmanke.gymstreak")` with fallback to `.none` if iCloud is unavailable.

**Change detection**: `CloudSyncObserver` watches `NSPersistentStoreRemoteChange` and posts `.cloudKitDataDidChange`.

### Persistence: UserDefaults (watchOS)

Watch does NOT use SwiftData. `RoutineStore` persists lightweight `WatchRoutine` Codable models to App Group UserDefaults. This is intentional — a CloudKit + SwiftData attempt on watchOS was reverted (commit `dc4a7d2`).

### Sync: WatchConnectivity

| Direction | Mechanism | Data |
|---|---|---|
| iOS → Watch | `updateApplicationContext` / `sendMessage` | JSON-encoded `[WatchRoutine]` |
| Watch → iOS | `transferUserInfo` | JSON-encoded `CompletedWatchWorkout` |

Sync models (`WatchModels.swift`) are lightweight Codable structs that mirror SwiftData entities without the framework overhead:
- `WatchRoutine`, `WatchExercise`, `WatchSet` — template sync
- `CompletedWatchWorkout`, `CompletedExercise`, `CompletedSet` — workout results

`Routine.toWatchRoutine()` and similar conversion methods live on the SwiftData models.

### HealthKit Integration

`HealthKitWorkoutManager` handles:
- Authorization requests
- Workout session creation and saving
- Deduplication via `externalUUID` metadata matching `WorkoutSession.id`

`WatchHealthKitManager` handles the watch side with `HKWorkoutSession` and `HKLiveWorkoutBuilder`.

### Services

`ExerciseProgressService` — encapsulates complex SwiftData queries for exercise progress charting. Aggregates data across `WorkoutSession` history to produce chart-ready data points. Uses Epley formula for estimated 1RM calculations.

---

## 6. Testing Strategy

### What's Tested

- **UI tests only** — no unit tests or integration tests detected
- **Screenshot generation** is the primary test purpose, using Fastlane `snapshot`

### Test Infrastructure

| Component | Purpose |
|---|---|
| `GymStreakUITests.swift` | iOS App Store screenshot generation |
| `GymStreakWatchUITests.swift` | watchOS App Store screenshot generation |
| `SnapshotHelper.swift` | Fastlane integration helper (copied into both test targets) |
| `UITestHelpers.swift` | iOS test utilities |
| `TestDataSeeder.swift` | Creates realistic test data (Push Day, Pull Day, Leg Day routines) |
| `WatchTestDataSeeder.swift` | Creates lightweight watch test data |

### Test Data Activation

Launch argument `-UI_TESTING` triggers test data seeding in both `GymStreakApp.onAppear` and `AppState.connectServices()`.

### Fastlane Lanes

| Lane | Description |
|---|---|
| `screenshots` | iOS dark mode screenshots (iPhone 17 Pro Max) |
| `watch_screenshots` | watchOS screenshots (Ultra 3 49mm, Series 11 46mm) |
| `all_screenshots` | Both iOS + Watch |
| `upload_screenshots` | Upload to App Store Connect via `deliver` |
| `test_ui` | Run UI tests without screenshots |

### Mocking Strategy

- No mocking framework
- In-memory `ModelContainer` for SwiftUI Previews
- Test data seeders for UI tests with realistic fixture data

---

## 7. Key Components & Entry Points

### Must-Know Files

| File | Why It Matters |
|---|---|
| `GymStreakApp.swift` | App entry, ModelContainer + CloudKit setup, test data seeding |
| `ContentView.swift` | Tab navigation root, WorkoutViewModel initialization |
| `Models.swift` | All 7 SwiftData entities, relationship definitions, conversion methods |
| `DesignSystem.swift` | Onyx theme definition — colors, spacing, typography, haptics |
| `RoutinesViewModel.swift` | Core business logic: routine CRUD, superset operations, watch sync |
| `WorkoutViewModel.swift` | Workout execution pipeline, HealthKit integration |
| `WatchConnectivityManager.swift` (iOS) | iOS → Watch sync, workout reception |
| `RoutineDetailView.swift` | Primary routine editing UI (inline set editing) |
| `ActiveWorkoutView.swift` | Live workout execution UI |
| `GymStreakWatchApp.swift` | Watch entry, AppState DI container |
| `WatchWorkoutViewModel.swift` | Watch workout execution |
| `RoutineStore.swift` | Watch persistence layer (UserDefaults) |
| `WatchModels.swift` (watch target) | Lightweight Codable sync models |

### Design System Components

All prefixed with `Onyx` in `Views/DesignSystem/`:
- `OnyxButton` — Primary/secondary/destructive button styles
- `OnyxCard` — Container with elevation states
- `OnyxBadge` — Pill badges with icons
- `OnyxStepper` — Integer stepper with ± buttons
- `OnyxTextField` — Styled text input with icons
- `OnyxListRow` — Consistent list item layout
- `OnyxProgressRing` — Circular progress indicator
- `OnyxEmptyState` — Empty list placeholder

Watch has its own `OnyxWatchDesignSystem.swift` with compact variants.

### Notification-Based Events

| Notification | Posted By | Handled By |
|---|---|---|
| `.cloudKitDataDidChange` | CloudSyncObserver | RoutinesViewModel (refetch) |
| `.watchWorkoutCompleted` | WatchConnectivityManager | RoutinesViewModel (create WorkoutSession) |
| `.watchAppBecameAvailable` | WatchConnectivityManager | RoutinesViewModel (trigger sync) |

---

## 8. Anti-Patterns & Constraints

### Organizational Debt

- **Mixed file placement**: Root-level views and ViewModels coexist with organized `Views/`, `ViewModels/` subdirectories. Newer files follow subdirectory organization; older files remain at root.
- **No shared code between targets**: iOS and Watch have separate implementations of similar logic (WatchConnectivityManager, WatchModels, DesignSystem). Code sharing uses symlinks due to PBXFileSystemSynchronizedRootGroup.

### Architecture Gaps vs. CLAUDE.md

The CLAUDE.md describes a Clean Architecture with Domain/Data/Presentation layers, Repository protocols, UseCases, and DTOs. The actual codebase:
- Has **no Repository protocol/implementation pattern**
- Has **no UseCase layer**
- Has **no DTOs or Mappers** (SwiftData models serve as both domain and persistence entities)
- Has **one Service** (`ExerciseProgressService`) that partially follows the service pattern

This isn't necessarily wrong — the simplified approach is appropriate for the app's scale — but the documented architecture doesn't match the implementation.

### Known Technical Debt

- **print() logging** throughout instead of `os.Logger` or a structured logging system
- **Large view files**: Some views exceed the project's own 200-300 line guideline significantly
- **Force-dark mode**: `preferredColorScheme(.dark)` is hardcoded — no light mode support
- **Full refetch pattern**: ViewModels call `fetchRoutines()` after every mutation rather than incremental updates

### Intentional Decisions That Look Like Issues

- **No SwiftData on Watch**: Intentionally uses UserDefaults — CloudKit + SwiftData on watchOS was attempted and reverted
- **Denormalized workout history**: `WorkoutSession`/`WorkoutExercise`/`WorkoutSet` copy routine data. This is intentional so history survives routine deletion
- **Singletons for managers**: WatchConnectivityManager and CloudSyncObserver use singletons. This is acceptable for system-level services that need app-wide lifecycle

---

## 9. LLM Working Instructions

### Adding a New Feature

1. Check `docs/` for existing documentation that might be affected
2. Follow the MVVM pattern: create a ViewModel if the feature needs state management, keep Views logic-free
3. Use the Onyx design system components (`OnyxButton`, `OnyxCard`, etc.) — never create one-off styled components
4. Use `DesignSystem.Colors.textOnTint` (black) for any text on green/tint backgrounds — never white
5. Add localization keys to both `en.lproj/Localizable.strings` and `de.lproj/Localizable.strings`
6. If the feature touches routines, ensure watch sync still works (`RoutinesViewModel.syncRoutinesToWatch()`)
7. After completion, create or update a `docs/[feature-name].md` file

### Where to Put Things

- **New views**: `Views/[FeatureArea]/` subdirectory (NOT root level)
- **New ViewModels**: `ViewModels/` directory
- **New Services**: `Services/` directory
- **New reusable components**: `Views/Components/` or `Views/DesignSystem/` (if truly generic)
- **New models**: Add to `Models.swift` if SwiftData @Model, or create `Models/[Name].swift` for plain structs
- **Watch features**: Mirror the iOS pattern in `GymStreakWatch Watch App/`

### Things to Never Do

- Never put business logic in Views — it belongs in ViewModels or Services
- Never use white text on the green tint color — use `DesignSystem.Colors.textOnTint`
- Never use SwiftData on watchOS — use `RoutineStore` (UserDefaults) instead
- Never make `@Model` classes `Hashable` — use `NavigationLink(value: model.id)` with UUID
- Never wrap `ObservableObject` classes with `@MainActor` at the class level if using `@StateObject` — it can break `objectWillChange` synthesis in Swift 6
- Never skip the `guard expandedItemId == item.id` check in `onChange` handlers for expandable set editors

### Canonical Reference Files

| Pattern | Reference File |
|---|---|
| ViewModel structure | `RoutinesViewModel.swift` |
| View with inline editing | `RoutineDetailView.swift` |
| Design system usage | `RoutinesView.swift` |
| Watch ViewModel | `WatchWorkoutViewModel.swift` |
| Service pattern | `ExerciseProgressService.swift` |
| Design system component | `Views/DesignSystem/OnyxButton.swift` |
| Watch sync model | `WatchModels.swift` |
| Test data | `TestDataSeeder.swift` |

### Common Gotchas

- **SwiftUI Animation + onChange**: When switching between expandable items with `withAnimation`, old views' `onChange` handlers fire with new values during animated removal. Always guard with `expandedItemId == item.id`.
- **Watch locale detection**: On watchOS simulators, `-AppleLanguages` launch arg may NOT change `Locale.current`. Read from UserDefaults instead.
- **PBXFileSystemSynchronizedRootGroup**: Files are auto-included by directory. To share between targets, use symlinks.
- **CloudKit fallback**: The app silently falls back to local-only storage. When debugging persistence, check which mode is active.
