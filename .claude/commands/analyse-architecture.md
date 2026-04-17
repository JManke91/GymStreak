# Analyze Project Architecture

Analyze the entire project structure and create a comprehensive architecture documentation file.

## Scope

Analyze ONLY the structural and architectural foundation of the project.

**Explicitly excluded:**

- Feature specifications or requirements (covered in separate docs)
- Business logic descriptions of individual features
- Product decisions or user stories
- What individual features do

**Focus on:**

- How the codebase is structured and why
- Patterns and conventions that apply across ALL features
- Infrastructure that features build on top of

$ARGUMENTS can optionally specify a scope, e.g. "data layer only" or "focus on networking".
If no argument is given, analyze the full project.

## Instructions

Perform a thorough analysis of this codebase and write the results to `docs/architecture.md`
(create the file if it doesn't exist, overwrite if it does).

### 1. Project Overview

- What does this project do (one paragraph, no feature details)?
- Tech stack (languages, frameworks, key libraries with versions from package files)
- Monorepo or single project? Module structure?

### 2. Architecture Pattern

- Identify the primary architecture pattern (Clean Architecture, MVVM, MVC,
  feature-based, layered, etc.)
- Document layer boundaries and what belongs where
- How is dependency injection handled?
- How does data flow through the app? (e.g., UI → ViewModel → UseCase → Repository → DataSource)

### 3. Module & Directory Structure

Walk the directory tree and document every significant directory:

- What is its responsibility?
- What lives there, what doesn't?
- Any naming conventions?

For feature directories: document only the internal structure/pattern
(how a feature folder is organized), NOT what individual features do.

Produce a tree like:

```
src/
├── features/          # Feature modules — each follows: UI + ViewModel + domain + data
│   └── [feature]/     # Do not describe individual features
├── core/              # Shared infrastructure: network, storage, DI
└── ...
```

### 4. Key Patterns & Conventions

Document patterns used consistently across the codebase:

- **Naming conventions** (files, classes, functions, variables)
- **Error handling** (how are errors propagated and handled?)
- **State management** (how is UI state managed?)
- **Navigation** (how does navigation work?)
- **Async patterns** (async/await, coroutines, Combine, RxSwift, etc.)
- **Dependency Injection** (manual, Hilt, Koin, etc.)

### 5. Data Layer

- Data sources (REST, GraphQL, local DB, cache)
- Repository pattern implementation
- Models vs. Entities vs. DTOs — how are they separated?
- Networking setup (base client, interceptors, auth)

### 6. Testing Strategy

- What is tested? (Unit, Integration, UI/E2E)
- Test conventions and where tests live
- Mocking strategy

### 7. Key Components & Entry Points

List the most important files/classes an LLM should know about:

- App entry point
- DI setup
- Navigation root
- Base classes / protocols that many things extend
- Most-touched shared utilities

### 8. Anti-Patterns & Constraints

Be honest:

- Anything that deviates from the stated architecture pattern?
- Known tech debt areas?
- Things that LOOK like X but are intentionally Y?

### 9. LLM Working Instructions

Write a short "how to work in this codebase" section specifically for an AI agent:

- "When adding a new feature, always..."
- "Never put X in Y because..."
- "The pattern for Z is always..."
- "When in doubt, look at [reference file] as the canonical example"

## Output

Write everything to `docs/architecture.md`.

At the end, print a short summary to the terminal:

- How many files were analyzed
- Which architecture pattern was identified
- Any ambiguities or areas where the analysis is uncertain
