# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

This is an iOS app built with Xcode:

- **Build & Run**: Open `GymStreak.xcodeproj` in Xcode and use Cmd+R to build and run
- **Clean Build**: Product → Clean Build Folder (Cmd+Shift+K)
- **iOS Target**: iOS 18.5+ required
- **Xcode Version**: 15.0+ required

## Project Architecture

### Core Technologies
- **SwiftUI**: Declarative UI framework
- **SwiftData**: Local persistence layer (replacing Core Data)
- **MVVM Pattern**: ViewModels handle business logic, Views handle UI

### Data Model Relationships
```
Routine (1) ←→ (Many) RoutineExercise (Many) ←→ (1) Exercise
                    ↓
                (Many) ExerciseSet
```

### Key Models (Models.swift)
- `Routine`: Workout routines containing multiple exercises
- `Exercise`: Reusable exercise definitions with muscle group categorization
- `RoutineExercise`: Links exercises to routines with routine-specific configurations
- `ExerciseSet`: Individual set data (reps, weight, rest time)

### ViewModels
- `RoutinesViewModel`: Manages routines, routine exercises, and sets
- `ExercisesViewModel`: Manages standalone exercise library

### Main Views Structure
- `ContentView.swift`: Tab-based navigation (3 tabs)
- **Tab 1**: Routines management (`RoutinesView.swift`, `RoutineDetailView.swift`)
- **Tab 2**: Exercise library (`ExercisesView.swift`, `ExerciseDetailView.swift`)  
- **Tab 3**: Workout recording (`WorkoutView.swift` - placeholder)

### Key User Flow
1. **Exercise Addition Flow**: Uses navigation push (not sheets) to `ExercisePickerView.swift`
2. **Set Management**: Immediate set addition with inline editing via `EditSetView.swift`
3. **Streamlined UX**: "Add Set" button creates sets instantly with default values

### Muscle Group Categories
Arms, Legs, Chest, Back, Shoulders, Core, Glutes, Calves, Full Body, General

## Development Notes

### SwiftData Configuration
- Models are registered in `GymStreakApp.swift`: `[Routine.self, Exercise.self, RoutineExercise.self, ExerciseSet.self]`
- All models use UUID primary keys and include created/updated timestamps

### Current Status
- **Completed**: Tabs 1 & 2 (Routines and Exercise Library)
- **In Progress**: Tab 3 (Workout Recording with HealthKit integration)

### Code Patterns
- ViewModels handle all data operations and business logic
- Views focus purely on UI and user interaction
- Inline editing pattern used for set configuration
- Navigation-based flows preferred over modal sheets for main user paths

## Architecture

### Clean Architecture Pattern
The app follows Clean Architecture principles with clear separation of concerns:

- **Domain Layer**: Contains business logic, entities, and use cases
  - `Domain/Models/`: Core data models (Challenge, CyclingStats, Workout)
  - `Domain/Repositories/`: Protocol definitions for data access
  - `Domain/UseCases/`: Business logic encapsulation

- **Data Layer**: Handles data persistence and external APIs
  - `Data/Repositories/`: Concrete implementations of repository protocols
  - `Data/Mappers/`: Convert between external and domain models

- **Presentation Layer**: UI components and view models
  - `Presentation/Views/`: SwiftUI views
  - `Presentation/ViewModels/`: ObservableObject classes managing UI state

## Layer Responsibilities

### 1. Presentation Layer (`Presentation/`)

- Implements **MVVM** using `View`, `ViewModel`, and `State/Intent`
- Uses `ObservableObject` and `@Published` to bind data to the UI
- Depends only on the `Domain` layer
- Contains **no business logic** or `Data`-specific code

### 2. Domain Layer (`Domain/`)

- Defines core **business rules**, logic, and **use cases**
- Contains:
  - `UseCase` protocols and implementations
  - `Entity/Model` structs (framework-agnostic)
  - `Repository` protocols
- Has **no dependency** on other layers
- Fully **unit testable** and pure Swift

### 3. Data Layer (`Data/`)

- Handles data operations from:
  - Remote APIs (e.g., REST, GraphQL)
  - Local storage (e.g., CoreData, SwiftData)
- Implements the `Repository` interfaces defined in the `Domain` layer
- Contains:
  - `DataSource` (Remote & Local)
  - `DTOs` (Data Transfer Objects)
  - `Mappers` (for translating between DTOs and Domain Models)

---

## Allowed Dependencies
Presentation can depend on Domain
Domain has no dependencies
Data depends on Domain

## Architectural Conventions
- ViewModels
Only include UI state and logic
Use async UseCase calls to fetch or mutate data
Must not depend on the Data layer
Use @MainActor or `@Published` to manage state updates
- UseCases
Encapsulate single business actions (e.g., FetchUserProfile, SubmitOrder)
Are injected into ViewModels
Are implemented in the Domain layer using pure Swift
- Repositories
Are protocols in the Domain layer
Are implemented in the Data layer
Must return domain models (never DTOs)
- Models
Domain Models: Core app entities, framework-independent
DTOs: External representations for APIs or databases
Use Mappers to translate DTO <-> Domain Model

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

### Key Components

#### HealthKit Integration
- **HealthKitCyclingStatsRepository**: Manages all HealthKit interactions
- **Workout deduplication**: Prevents double-counting workouts from multiple sources
- **Authorization handling**: Manages HealthKit permissions