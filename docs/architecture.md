# GymStreak Architecture

> **This document is the single source of truth for the project's architecture.**
> CLAUDE.md references it; the `architecture-reviewer` agent enforces it.
> When the architecture evolves, update this file in the same change.

## 1. Project Overview

GymStreak is a multi-platform fitness tracking app for iOS and Apple Watch: workout routines, set-by-set workout execution (with supersets, alternatives, rep ranges, progressive overload), history & progress charts, and an on-device AI coach. HealthKit records workouts; CloudKit syncs iOS data; WatchConnectivity syncs with the watch.

### Tech Stack

| Technology | Purpose |
|---|---|
| **Swift** | Primary language (Swift 6 strict concurrency in newer code) |
| **SwiftUI** | 100% declarative UI on both iOS and watchOS |
| **SwiftData** | Persistence with CloudKit sync (iOS only) |
| **HealthKit** | Workout recording and health data |
| **WatchConnectivity** | Bidirectional iOS ↔ Watch communication |
| **ActivityKit** | Rest-timer Live Activity |
| **FoundationModels** | On-device AI coach generation |
| **Fastlane** | Screenshots and App Store tooling |

**No external Swift package dependencies.** Apple frameworks only.

### Targets

| Target | Platform | Notes |
|---|---|---|
| GymStreak | iOS 26+ | Main app — Clean Architecture layout below |
| GymStreakWatch Watch App | watchOS | Own lightweight architecture (no SwiftData) |
| GymStreakWidgets | iOS widget ext. | Rest-timer Live Activity UI |
| GymStreakUITests / GymStreakWatchUITests | UI tests | Screenshot generation |

File sharing between targets is by directory (`PBXFileSystemSynchronizedRootGroup`) — every file inside a target's folder is compiled into that target automatically. There is no per-file target membership (only Info.plist exceptions). Types needed by two targets exist as copies in each target's folder (e.g. `WatchModels`, `RestTimerAttributes`).

---

## 2. Architecture Pattern (iOS target)

**Pragmatic Clean Architecture** — three layers plus a composition root, chosen deliberately over textbook Clean Architecture (see "Deliberate decisions" below):

```
GymStreak/
├── App/            Composition root — may see everything
├── Domain/         Protocols + domain models + pure business logic
│                   (no SwiftUI, no concrete Data types)
├── Data/           Implements Domain protocols; owns ModelContext,
│                   HealthKit, WatchConnectivity, AI coach services
└── Presentation/   Views + ViewModels — depend on Domain protocols only
```

**Dependency direction: `Presentation → Domain ← Data`.** Domain depends on nothing. `App/` wires the two sides together.

### Layer contents

| Layer | Folder | Contains |
|---|---|---|
| App | `App/` | `GymStreakApp` (@main, ModelContainer), `AppDependencies` (composition root), `ContentView` (tab root), `TestDataSeeder` |
| Domain | `Domain/Models/` | SwiftData `@Model` classes (`Models.swift`), `MuscleGroups`, `EquipmentType`, `WorkoutType`, chart models, AI-coach input/output models, `IncomingWatchWorkout` (Domain input for watch-workout ingestion) |
| Domain | `Domain/Repositories/` | `RoutineRepository`, `ExerciseRepository`, `WorkoutSessionRepository` — `@MainActor` protocols |
| Domain | `Domain/Interfaces/` | System-gateway and async read protocols: `WatchSyncServicing`, `HealthKitWorkoutServicing`, `RestTimerReminderScheduling`, `HistorySnapshotProviding`, `AICoach/` (`AICoachServicing`, `AICoachCaching`, `AICoachPreferencesProviding`, `AICoachAvailabilityProviding`, `ProactivePromptCoordinating`) |
| Domain | `Domain/Services/` | Pure business logic on model arrays: `HistoryStatsService`, `PersonalRecordService`, `FortschrittAggregator`, `SupersetLabelProvider`, `SupersetEditor` (superset-editor set-algebra), `WatchWorkoutIngestionService` (`@MainActor`, materializes an `IncomingWatchWorkout` into a `WorkoutSession`) |
| Data | `Data/Repositories/` | `SwiftData*Repository` — `@MainActor final class`, `init(modelContext:)` |
| Data | `Data/HealthKit/` | `HealthKitWorkoutManager`, `HealthKitWorkoutReconciler` |
| Data | `Data/Notifications/` | `UserNotificationRestTimerScheduler` |
| Data | `Data/Sync/` | `WatchConnectivityManager`, `CloudSyncObserver`, `WatchModels` (sync DTOs + mappers) |
| Data | `Data/Progress/` | `ExerciseProgressService` (chart aggregation queries) |
| Data | `Data/History/` | `SwiftDataHistorySnapshotProvider` (detached off-main construction) + `SwiftDataHistorySnapshotStore` (`@ModelActor`; actor-owned History fetch and aggregation) |
| Data | `Data/AICoach/` | `AICoachService` (FoundationModels), cache, preferences, telemetry, availability, aggregators, system prompts |
| Presentation | `Presentation/ViewModels/` | `RoutinesViewModel`, `ExercisesViewModel`, `WorkoutViewModel`, `ExerciseProgressViewModel`, `AICoach/` VMs |
| Presentation | `Presentation/Views/<FeatureArea>/` | `Routines/`, `Exercises/`, `Workout/`, `History/`, `Charts/`, `AICoach/`, `Components/`, `DesignSystem/` |
| Presentation | `Presentation/DesignSystem.swift` | Onyx theme tokens + `HapticManager` |
| — | `Extensions/` | Cross-layer utilities (`String+Localization`, `Color+AccentColor`) |

### Dependency injection

- `AppDependencies` (`App/AppDependencies.swift`) is a `@MainActor final class … ObservableObject` built once in `GymStreakApp.init()` from `sharedModelContainer.mainContext`, injected via `.environmentObject(dependencies)`.
- It owns shared repository instances, the actor-owned `historySnapshotProvider`,
  `exerciseProgressService`, and `watchSync` (the `WatchConnectivityManager.shared` singleton —
  WCSession delegate identity must be the launch-time instance), and exposes
  `makeHealthKitWorkoutService()` as a **factory** (the two independent `WorkoutViewModel`
  instances each get their own HealthKit session — pre-existing behavior, kept deliberately).
- ViewModels receive dependencies via initializer injection, typed as protocols.
- History receives AI-coach preference, availability and proactive-prompt dependencies through
  Domain protocols wired in `AppDependencies`; its Presentation views never access their concrete
  Data singletons.
- Views that own a `@StateObject` ViewModel use the **outer/inner view split** (outer reads `@EnvironmentObject dependencies`, inner constructs the ViewModel in `init` — the environment isn't readable inside a plain `init`). See `RoutinesView.swift` for the canonical example.
- AI-coach ViewModels (`@Observable @MainActor`) default their protocol dependencies to the shared instances inside the `@MainActor` init body (`service ?? AICoachService.shared`) — NOT as `= Foo.shared` default arguments, which Swift 6 rejects (default args evaluate nonisolated).

Full design rationale, method-surface decisions, and edge cases: **`docs/repository-refactor.md`** and **`docs/ai-coach.md`**.

### Hard rules (enforced by the architecture-reviewer agent)

1. **No `ModelContext` / `FetchDescriptor` in `Presentation/`.** Repositories are the only persistence surface for queries and all mutations. *Documented exceptions:* (a) four views (`ExerciseProgressChartView`, `WorkoutDetailView`, `SaveWorkoutView`, `PeriodRecapView`) hold `@Environment(\.modelContext)` solely to pass through to AI-coach APIs, and AI-coach ViewModels pass it through to `Data/AICoach` aggregators without querying it themselves; (b) **read-only `@Query`** in Views is allowed — it is SwiftData's native live SwiftUI binding (e.g. the live `Exercise` library join that progress views require) and replacing it with repository + notification plumbing would re-implement observation the framework provides. Mutations via `@Query` results must still go through repositories/ViewModels.
2. **No singleton access inside ViewModels** — inject protocols via init (defaulted inits are fine). `HapticManager.shared` in Views is tolerated.
3. **No business logic in Views** — no persistence, no domain set-algebra/grouping, no service construction. Display-only formatting is fine.
4. **`Domain/` never imports SwiftUI** and never references concrete Data types. Styling for domain types (colors etc.) lives in `Presentation/Views/Components/DomainColorStyling.swift`.
5. **New dependencies are wired in `AppDependencies`**, never constructed ad hoc in views/ViewModels.
6. **New files go into their layer folder** — nothing new at the `GymStreak/` root.

### Deliberate decisions (do not "fix" these)

- **`@Model` classes ARE the domain models.** Repository protocols return them directly. No DTO/mapper layer over the local store — mapping to structs would forfeit SwiftData identity, observation tracking, relationship faulting, and CloudKit merge semantics. DTOs exist only at true external boundaries (`WatchModels` for WatchConnectivity, chart models for display).
- **No UseCase-per-action layer.** Coarse domain services (`Domain/Services/`) hold multi-entity business rules; simple CRUD is a ViewModel → repository call. A `CreateRoutineUseCase` wrapping one repository call is ceremony, not architecture.
- **Legacy ViewModels stay `ObservableObject`** (`@Observable` migration is a separate, deliberate ripple — `@StateObject`/`@EnvironmentObject` call sites everywhere). **New ViewModels use `@Observable` + `@MainActor`** (the AI-coach VMs are the pattern).
- **Denormalized workout history**: `WorkoutSession`/`WorkoutExercise`/`WorkoutSet` copy routine data so history survives routine deletion/edits.
- **No SwiftData on watchOS** — attempted and reverted (`dc4a7d2`). `WatchSyncStateStore` atomically persists the authoritative `WatchRoutine` base plus pending transaction overlays in one App Group file; `RoutineStore` is only the published UI projection.
- **Domain logic as computed properties on `@Model` classes** (e.g. `totalVolume`, `exercisesGroupedBySupersets`) is acceptable — they are the domain models.
- **`Domain/` may import `FoundationModels`** (AI-coach input/output models use `@Generable`; `AICoachServicing` exposes streaming response types). The SwiftUI ban stays absolute; FoundationModels coupling is accepted because the generable models ARE the coach's domain contract.

---

## 3. Data Layer

### SwiftData models (`Domain/Models/Models.swift`)

| Model | Purpose |
|---|---|
| `Routine` | Workout template → many `RoutineExercise` |
| `Exercise` | Exercise library item |
| `RoutineExercise` | Junction w/ superset, rep-range, alternatives config → many `ExerciseSet` |
| `ExerciseSet` | Template set (reps/weight/rest) |
| `RoutineExerciseAlternative` / `AlternativeExerciseSet` | Alternative exercise slots + their set schemes |
| `WorkoutSession` | Completed workout → many `WorkoutExercise` → many `WorkoutSet` (denormalized) |

All models: UUID ids, CloudKit-compatible defaults (every property has a default, relationships optional). **Any schema change requires manual CloudKit Console schema deploy before release** — otherwise sync silently fails in TestFlight/prod.

CloudKit: `.private("iCloud.com.jmanke.gymstreak")` with silent fallback to local-only. `CloudSyncObserver` posts the legacy-named `.cloudKitDataDidChange` whenever Core Data reports `NSPersistentStoreRemoteChange`; that signal is not exclusive proof of a CloudKit import.

### Repositories

- `RoutineRepository`: `fetchAll/fetch(id:)/fetch(name:)/insert/delete` + explicit `RoutineExercise`/`ExerciseSet` inserts and child deletes + `save()`
- `ExerciseRepository`: `fetchAll/fetch(id:)/insert/delete/save`
- `WorkoutSessionRepository`: `fetchAll/fetchCompleted/findSession(id:healthKitWorkoutId:)` (watch-workout dedup) + inserts/deletes + `save()`

Child models normally cascade-insert via relationship attachment; explicit `delete` is always required (removing from a relationship array does not delete the record).

### Watch sync

iOS → Watch routines use versioned `updateApplicationContext` snapshots owned by `RoutineSyncAuthority` (legacy unversioned snapshots remain available for old watches). Watch → iOS template mutations use a generic `TemplateTransactionEnvelope` over both `sendMessage` and `transferUserInfo`; ticket 05's payload is `completedWorkoutUpdate`, with `CompletedWatchWorkout.id` retained only as optional history correlation. No-template workouts keep the legacy workout envelope. Both routes first enter `WatchWorkoutInboxStore`; the composition-root `WatchWorkoutIngestionCoordinator` performs isolated one-save ingestion and durable receipt/ack handling. Wire DTOs + `Routine.toWatchRoutine()` mapper: `Data/Sync/WatchModels.swift` and `WatchTemplateTransactionModels.swift`.

The wire DTO `CompletedWatchWorkout` never crosses into Presentation. `WatchConnectivityManager` maps pending correlation views through `CompletedWatchWorkout.toIncomingWatchWorkout()`, while the Data-layer ingestion coordinator supplies the Domain-owned input to `WatchWorkoutIngestionService` / `WatchTemplateTransactionService`. Presentation therefore depends only on Domain protocols/models; wire evolution stays isolated at the Data boundary.

### Cross-component events (NotificationCenter)

| Notification | Posted by | Handled by |
|---|---|---|
| `.cloudKitDataDidChange` | CloudSyncObserver | RoutinesViewModel, ExercisesViewModel (refetch) |
| `.watchAppBecameAvailable` | WatchConnectivityManager | RoutinesViewModel (sync routines) |
| `.workoutHistoryDidChange` | Domain ingestion services | WorkoutViewModel (refresh history) |
| `.historySourceDataDidChange` | RoutinesViewModel, ExercisesViewModel after successful local saves | WorkoutViewModel (invalidate actor-owned History snapshot) |
| `.routineTemplateDidChange` / `.routineTemplateDidChangeLocally` | ViewModels / transaction coordinator | RoutinesViewModel (syncing / non-syncing refresh) |

Accepted as the inter-ViewModel event mechanism; don't add new notification names when a direct repository/service call works.

---

## 4. watchOS target

Cleaner, smaller architecture — keep it that way:

- `Managers/WatchSyncStateStore.swift` — the one atomic App Group owner for outgoing sync work, routine authority/base, and optimistic anchors
- `Managers/RoutineStore.swift` — published projection of `WatchSyncStateStore.effectiveRoutines()`; no independent persistence
- `Managers/WatchConnectivityManager.swift`, `WatchHealthKitManager.swift` — system gateways
- `ViewModels/` — constructor-injected (`WatchRoutinesViewModel(routineStore:)`), `AppState` in `GymStreakWatchApp` is the DI container via `.environmentObject`
- `Views/` — UI only
- **Never** SwiftData/CloudKit on the watch.

---

## 5. Conventions

### Naming & style

- PascalCase types, camelCase members, `is/has/should` booleans, verb methods
- Design system components: `Onyx` prefix (iOS), `OnyxWatch` (watch)
- New Swift files ≤ 300 lines — extract instead of growing
- async/await only; `@MainActor` ViewModels; `nonisolated` delegate callbacks hop via `Task { @MainActor in }`; prefer `@preconcurrency` conformance over `@unchecked Sendable` for pre-concurrency Apple delegate protocols

### UI

- Onyx design system components — no one-off styled components
- **Never white text/icons on the green tint** — use `DesignSystem.Colors.textOnTint` / `OnyxWatch.Colors.textOnTint`
- Localization: every user-facing string in BOTH `en.lproj` and `de.lproj` via `.localized` dot-notation keys
- Navigation: `NavigationLink(value: model.id)` + `navigationDestination(for: UUID.self)` — `@Model` classes are never made `Hashable`

### Known gotchas (hard-won — keep respecting them)

- **Expandable set editors**: `onChange` handlers of a collapsing item fire with the *new* item's values during animated removal — always `guard expandedItemId == item.id`.
- **Every `@Model` relationship MUST declare an inverse** (on one side). CloudKit validation rejects the schema otherwise — `ModelContainer` creation fails at launch and the app silently falls back to local-only storage. This does not fail the build; check the launch log for "Failed to create CloudKit container".
- **Retroactive conformances on `@Model`**: never re-state `Identifiable` (or anything `PersistentModel` already provides) via a protocol that inherits it in an `extension SomeModel: SomeProtocol` — duplicate conformance descriptor → linker error.
- **`@MainActor` + `ObservableObject`** can fail to synthesize `objectWillChange` in Swift 6 — one more reason new ViewModels use `@Observable`.
- **`= Foo.shared` default arguments** on `@MainActor` singletons are evaluated nonisolated (Swift 6 error) — use `nil` defaults resolved in the init body.
- **watchOS simulators** may ignore `-AppleLanguages` for `Locale.current` — read `UserDefaults` `AppleLanguages` instead.

---

## 6. Testing

- **UI tests** (`GymStreakUITests`, `GymStreakWatchUITests`): fastlane screenshot generation; `-UI_TESTING` launch arg triggers `TestDataSeeder`.
- **Unit testing strategy**: repositories and ViewModels are protocol-injected so they can be tested against an **in-memory `ModelContainer`** (`ModelConfiguration(isStoredInMemoryOnly: true)`) — real `@Model` fetch/predicate semantics, no mocking framework. Gateway protocols (`WatchSyncServicing`, `HealthKitWorkoutServicing`, AI-coach protocols) get hand-written test doubles.
- Mock data only ever exists in tests/seeders — never in dev/prod code paths.

---

## 7. Risk-based architecture review

Changes with architectural surface (new/moved files, new types or imports, dependency wiring, changes in `Domain/`/`Data/`, multi-layer diffs, refactors, larger diffs) get a second review layer: the **`architecture-reviewer` agent** (`.claude/agents/architecture-reviewer.md`). It diffs the working tree, checks the hard rules in §2 and conventions in §5, and returns PASS/FAIL with file:line findings. CRITICAL findings must be fixed before a change is reported as done. Trivial edits (strings, comments, small in-place value tweaks) may skip the reviewer with a stated one-line justification. The exact trigger/skip criteria are defined in CLAUDE.md → "Architecture Review (risk-based)".

---

## 8. Canonical reference files

| Pattern | File |
|---|---|
| Composition root / DI | `App/AppDependencies.swift` |
| Repository protocol | `Domain/Repositories/RoutineRepository.swift` |
| Repository implementation | `Data/Repositories/SwiftDataRoutineRepository.swift` |
| Legacy ViewModel (ObservableObject + repos) | `Presentation/ViewModels/RoutinesViewModel.swift` |
| Modern ViewModel (@Observable + injected protocols) | `Presentation/ViewModels/AICoach/PeriodRecapViewModel.swift` |
| Outer/inner view DI split | `Presentation/Views/Routines/RoutinesView.swift` |
| Domain service | `Domain/Services/HistoryStatsService.swift` |
| Gateway protocol + conformance | `Domain/Interfaces/WatchSyncServicing.swift` + `Data/Sync/WatchConnectivityManager.swift` |
| Actor-owned value read model | `Domain/Interfaces/HistorySnapshotProviding.swift` + `Data/History/SwiftDataHistorySnapshotStore.swift` (`SwiftDataHistorySnapshotProvider` is the composition-root entry point) |
| Domain-type styling in Presentation | `Presentation/Views/Components/DomainColorStyling.swift` |
| Watch ViewModel + DI | `GymStreakWatch Watch App/ViewModels/WatchRoutinesViewModel.swift` |
