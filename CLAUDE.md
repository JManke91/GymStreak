# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

## Building new features/updating existing features

- After building a new feature, make sure the app still compiles
- When building a new feature make sure to create a .md file in the /docs folder that summarizes all the important details inlcuding what the feature does, how it works, how it's architecutlly structured, what components are involved etc. make sure to include the ios and watch target for documentation. the goal is to be able to reference this file later for quick context
- For every code change check if an existing feature is modified and if there already is a corresponsing .md file in the /docs folder make sure to update according to the criteria stated for building new .md files.
- **After ANY code change, run the mandatory architecture review** (see "Architecture Review (mandatory)" below) before reporting the work as done.

This is an iOS app built with Xcode:

- **Build & Run**: Open `GymStreak.xcodeproj` in Xcode and use Cmd+R to build and run
- **Clean Build**: Product → Clean Build Folder (Cmd+Shift+K)
- **iOS Target**: iOS 18.5+ required
- **Xcode Version**: 15.0+ required

## Architecture

**`docs/architecture.md` is the single source of truth for the architecture.** Read it before structural work. Summary of what is binding:

### Layers (iOS target `GymStreak/`)

Pragmatic Clean Architecture. Dependency direction: **`Presentation → Domain ← Data`**, wired by the composition root in `App/`.

```
GymStreak/
├── App/            GymStreakApp, AppDependencies (composition root), ContentView, TestDataSeeder
├── Domain/
│   ├── Models/       SwiftData @Model classes + domain enums (these ARE the domain models)
│   ├── Repositories/ Repository protocols (RoutineRepository, ExerciseRepository, WorkoutSessionRepository)
│   ├── Interfaces/   System-gateway protocols (WatchSyncServicing, HealthKitWorkoutServicing, AICoach/*)
│   └── Services/     Pure business logic on model arrays
├── Data/           Implements Domain protocols; the ONLY layer that touches
│                   ModelContext/FetchDescriptor, HealthKit, WCSession, FoundationModels
├── Presentation/   ViewModels/ + Views/<FeatureArea>/ + DesignSystem
└── Extensions/     Cross-layer utilities
```

### Hard rules

1. No `ModelContext`/`FetchDescriptor` in `Presentation/` — go through repositories (documented AI-coach pass-through exception in docs/architecture.md §2).
2. No `.shared` singleton access inside ViewModels — inject protocols via init (`HapticManager.shared` in Views is tolerated).
3. No business logic in Views — persistence, domain computations, and service construction belong in ViewModels/Services.
4. `Domain/` never imports SwiftUI and never references concrete Data types.
5. New dependencies are wired in `App/AppDependencies.swift`, never constructed ad hoc.
6. New files go in their layer folder (`Presentation/Views/<FeatureArea>/`, `Presentation/ViewModels/`, `Domain/Services/`, `Data/Repositories/`, …) — never at the `GymStreak/` root.

### Deliberate decisions — do not "fix"

- Repository protocols return `@Model` types directly. **No DTO/mapper layer over the local store** (DTOs only at real external boundaries: watch sync, chart display models).
- **No UseCase-per-action layer** — coarse domain services + direct ViewModel→repository calls.
- Legacy ViewModels stay `ObservableObject`; **new ViewModels use `@Observable` + `@MainActor`**.
- watchOS: **never SwiftData** — `RoutineStore` (App Group UserDefaults) is the watch persistence layer.
- Workout history models are denormalized copies (history must survive routine edits/deletion).

## Architecture Review (mandatory)

After completing ANY code change (feature, fix, refactor) and before reporting it as done:

1. Launch the **`architecture-reviewer`** agent (`.claude/agents/architecture-reviewer.md`) via the Agent tool on the current diff.
2. **CRITICAL findings must be fixed** and the reviewer re-run until it returns PASS (or PASS WITH WARNINGS with the warnings explicitly acknowledged in your summary).
3. Include the reviewer's verdict in your final report to the user.

This is a second security layer — it does not replace compiling the app or self-review.

## General Coding

- Always prefer simple solutions
- Avoid code duplication whenever possible, whhich means checking for other areas of the codebase that might already have similar code and reuse it if possible
- write code that takes into account the different environments (development, staging, production)
- you are careful to only make changes that are requested or you are confident that you understood the requested changes well enough
- when fixing an issue or bug, do not introduce a new pattern or technology without first exhausting all other options for the existing codebase
- keep the codebase very clean and organized
- avoid writing scripts in files if possible, especially if the script is likely only to be run once
- avoid having files over 200-300 lines of code. Refactor at that point
- Mocking data is only needed for tests, never mock data for dev or prod

## Performance and Optimization

- Implement lazy loading for large lists or grid using `LazyVStack` or `LazyHStack`, or `LazyVGrid` or `LazyHGrid`
- Optimize ForEach loops by using stable identifiers

## Naming

- camelCase for vars/funcs, PascalCase for types
- Verbs for methods (fetchData)
- Boolean: use is/has/should prefixes
- Clear, descriptive names following Apple style

## Swift Best Practices

- Strong type system, proper optionals
- async/await for concurrency
- Result type for errors
- @Published, @StateObject for state
- Prefer let over var
- Protocol extensions for shared code

## Data Flow

- Use Observation Framework (`@Observable`, `@State`, `@Binding`) to build reactive UIs
- if necessary, implement loading states and views
- implement proper error handling and propagation

## UI Development

- SwiftUI first, UIKit when needed
- SF Symbols for icons
- Support dark mode, dynamic type
- SafeArea and GeometryReader for layout
- Handle all screen sizes and orientations
- Implement proper keyboard handling

### Color Contrast Guidelines

- **IMPORTANT**: Never use white text on the app's green tint color (`DesignSystem.Colors.tint`) - it lacks sufficient contrast
- Always use `DesignSystem.Colors.textOnTint` (black) for text/icons displayed on tint-colored backgrounds
- This applies to: badges, buttons with tint backgrounds, hint banners, and any UI element with a green background
- The design system provides `textOnTint` specifically for this purpose in both iOS (`DesignSystem.Colors.textOnTint`) and watchOS (`OnyxWatch.Colors.textOnTint`)

### Key Components

#### HealthKit Integration

- **HealthKitWorkoutManager** (`Data/HealthKit/`, conforms to `HealthKitWorkoutServicing`): authorization, workout save, deduplication via `externalUUID` metadata matching `WorkoutSession.id`
- **WatchHealthKitManager** (watch target): `HKWorkoutSession` + `HKLiveWorkoutBuilder` live workout recording

## Active Technologies

- Swift 6 with strict concurrency + SwiftUI, SwiftUI Charts framework (001-improve-progress-charts)
- SwiftData (unchanged — no persistence changes) (001-improve-progress-charts)
- N/A (display-only fix, no persistence changes) (002-fix-chart-display)

## Recent Changes

- 001-improve-progress-charts: Added Swift 6 with strict concurrency + SwiftUI, SwiftUI Charts framework

## Development Notes

- Always use the established architecture patterns when adding new features
- Follow the existing repository pattern for data access
- Use SwiftData for local persistence of user-created data
- Implement proper error handling for HealthKit operations
- Maintain localization for all user-facing strings
- Follow the existing theme system for consistent UI styling
- Widget functionality should remain independent of the main app

## Feature Documentation

Always document new features as well as updates on existing features in the appropriate markdown file

- Every time you create a new feature, create a markdown file <feature-name>.md in the "docs" folder and document the essential parts of this feature for later reference. this should include feature requirements, difficulties, edge cases, technical specifications, architecture decisions etc.
- Every time you extend/update an existing feature search in the "docs" folder, if there already is an .md file documenting this feature and if so update the file according to the changes being made while providing one fluid document
- **Capture research findings**: when a feature required external research (Apple APIs, OS mechanisms, framework behavior), document the findings in the feature's .md file — the exact API/mechanism used, minimum OS/hardware requirements, known OS bugs or version-specific regressions, and links to the sources (Apple docs, forum threads, reference implementations). Future work must be able to skip re-doing the research.
- **Capture root causes and dead ends**: when debugging a feature surfaced a non-obvious root cause (e.g. a silently ignored build setting) or an approach that turned out to be wrong, document both the root cause/fix and the discarded approaches with the reason — so they are not re-tried later.
- **Capture deliberate omissions**: if part of a capability was intentionally NOT implemented or was removed (product decision), record what, why, and how to restore it (e.g. pointer to git history).
- Keep the doc consistent as understanding evolves: when later findings contradict earlier statements in the doc, correct the earlier statements instead of appending — the doc must read as one coherent, current truth.

## Get Context

Context for features is documented in .md files within the "docs" folder

- when looking for context, before scanning the entire codebase look for a suitable file in the "docs" folder for feature documentation

## TestFlight Release Notes

The project uses static TestFlight release notes files that Xcode Cloud automatically picks up for TestFlight builds.

### Files

- `TestFlight/WhatToTest.en-US.txt` - English release notes (read by Xcode Cloud)
- `TestFlight/WhatToTest.de-DE.txt` - German release notes (read by Xcode Cloud)
- `CHANGELOG.md` - Historical archive of all release changes

### Workflow Rules

1. **After completing any user-facing change** (feature, fix, or improvement), append a bullet point to BOTH `TestFlight/WhatToTest.en-US.txt` (English) and `TestFlight/WhatToTest.de-DE.txt` (German translation)
2. **Format**: Each line is `- <description>` in plain text. Keep descriptions concise and user-facing (not developer jargon). Maximum 4,000 characters total per file.
3. **Do NOT update these files** for internal refactors, code cleanup, CI changes, or non-user-facing work
4. **When a version is bumped** (e.g., bumping MARKETING_VERSION):
   - Archive the current WhatToTest content into `CHANGELOG.md` under a new version heading
   - Clear both WhatToTest files and start fresh for the next release cycle
5. **CHANGELOG.md format**: Use Keep a Changelog style with `## [version] - date` headings and `### Added/Improved/Fixed` subsections
