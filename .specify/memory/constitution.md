<!--
SYNC IMPACT REPORT
==================
Version change: [placeholder] → 1.0.0 (initial ratification)
Modified principles: N/A — initial population from template
Added sections:
  - Core Principles (I–V)
  - Platform Standards
  - Quality Gates
  - Governance
Removed sections: N/A
Templates checked:
  - .specify/templates/plan-template.md ✅ Constitution Check section references constitution for gates — aligns
  - .specify/templates/spec-template.md ✅ User stories, requirements, and success criteria structure aligns
  - .specify/templates/tasks-template.md ✅ Phase structure, testing as optional, and parallel task guidance aligned
Follow-up TODOs: None — all fields resolved from project context.
-->

# GymStreak Constitution

## Core Principles

### I. Code Quality & Architecture (NON-NEGOTIABLE)

The codebase MUST follow Clean Architecture with strict layer separation: Presentation → Domain ← Data.
No layer MUST import from a layer it is not permitted to depend on. ViewModels MUST contain only
UI state and async UseCase calls — business logic belongs exclusively in the Domain layer.
Files MUST NOT exceed 300 lines; refactor at that threshold. Code duplication MUST be avoided by
searching for reusable components before creating new ones. The simplest correct solution MUST be
preferred (YAGNI): no speculative abstractions, no premature generalization. New patterns or
third-party dependencies MUST NOT be introduced without first exhausting existing codebase options.

**Rationale**: Enforcing architectural boundaries keeps the codebase testable, navigable, and
resistant to entanglement as the app grows across iOS and watchOS targets.

### II. Testing Standards

UseCase implementations MUST be covered by unit tests. Features involving HealthKit,
WatchConnectivity, or SwiftData persistence MUST include integration tests. Tests MUST be written
before implementation (TDD) when explicitly requested; otherwise test coverage MUST accompany the
feature. UI tests for critical user flows (workout recording, routine management) MUST be maintained
and MUST pass before merge. Mocking MUST only be used in tests — never in production or development
builds. All tests MUST use stable, deterministic identifiers and MUST NOT depend on UI layout
implementation details.

**Rationale**: A fitness-tracking app handles real user health data; regressions in core flows
erode trust irreparably. Tests provide the safety net for rapid iteration across two targets.

### III. User Experience Consistency (NON-NEGOTIABLE)

All UI MUST use the shared `DesignSystem` — colors, typography, and spacing tokens are authoritative.
Text on tint-colored backgrounds MUST use `DesignSystem.Colors.textOnTint` (black) — white on green
is prohibited. All screens MUST support dark mode, dynamic type, and all iPhone/Apple Watch display
sizes. Every new screen MUST implement empty states, loading states, and error states for async
data-loading. Navigation MUST be consistent: navigation push for primary user flows; sheets for
supplementary or contextual content. Every interactive element MUST have an accessibility label.

**Rationale**: Fitness users interact with the app mid-workout; cognitive load must be minimized
and visual clarity is critical. Inconsistency signals low quality and breaks muscle memory.

### IV. Performance Requirements

All UI MUST maintain 60 fps during normal interaction; no blocking work MUST run on the main thread.
Large lists or grids MUST use `LazyVStack`, `LazyHStack`, `LazyVGrid`, or `LazyHGrid`. `ForEach`
loops MUST use stable, unique identifiers. SwiftData fetch operations MUST be predicated and sorted
at the query level — not filtered in-memory after fetch. HealthKit queries MUST run on background
actors and publish results to `@MainActor`. Watch ↔ iOS sync MUST NOT block the UI and MUST handle
connectivity failures gracefully without data loss.

**Rationale**: The app is used during physical activity; a laggy or unresponsive UI is a usability
and safety issue. Performance requirements are non-negotiable given the real-time workout context.

### V. Simplicity & Documentation

Every new feature MUST be documented in `/docs` with a `.md` file covering: purpose, architecture,
components involved, and both iOS and watchOS target considerations. Existing `/docs` files MUST be
updated whenever a covered feature changes. Scripts MUST NOT be committed unless they serve a
recurring purpose. `@Observable`, `@State`, and `@Binding` MUST be preferred; `ObservableObject`
is permitted only where the Observation framework is provably insufficient. No unnecessary
error-handling, fallbacks, or validation MUST be added for scenarios that cannot occur — only
validate at system boundaries (user input, external APIs, HealthKit, WatchConnectivity).

**Rationale**: This project is developed by a single engineer with AI assistance; documentation
is the primary mechanism for context continuity across sessions and the guard against knowledge loss.

## Platform Standards

- **Minimum Deployment**: iOS 18.5+, watchOS 11+
- **Language**: Swift 6 with strict concurrency; async/await for all asynchronous operations
- **UI Framework**: SwiftUI first; UIKit only when SwiftUI is provably insufficient
- **Persistence**: SwiftData for local storage; CloudKit deferred until watch sync is proven stable
- **Icons**: SF Symbols exclusively — no custom icon assets for standard system actions
- **Target Sharing**: Files shared between iOS and watchOS MUST use symlinks under the watch target
  directory (project uses `PBXFileSystemSynchronizedRootGroup` — no manual target membership)
- **Accessibility**: Dynamic Type MUST be supported on all text; interactive elements MUST carry
  accessibility labels and, where appropriate, accessibility values

## Quality Gates

A feature is "done" only when ALL of the following gates pass:

1. **Compiles** — both iOS and watchOS targets build without errors or warnings
2. **Tests pass** — all unit and UI tests pass on affected targets
3. **Documented** — `/docs/[feature].md` created or updated per Principle V
4. **UX consistent** — DesignSystem tokens used; no hardcoded colors, fonts, or sizes
5. **Performance verified** — no main-thread blocking introduced; lazy loading applied to lists
6. **No new duplication** — reuse audited before any new abstraction is added

Constitution violations introduced by necessity MUST be recorded in the Implementation Plan's
Complexity Tracking table with an explicit justification and a simpler alternative rejected rationale.

## Governance

This constitution supersedes all other informal practices. Amendments require:
1. Updating this file with a version bump following semantic versioning rules below.
2. Propagating changes to dependent templates in `.specify/templates/` and updating the Sync Impact
   Report at the top of this file.
3. Updating `CLAUDE.md` if any standing coding instruction is affected.

**Versioning policy**:
- **MAJOR**: Removal or backward-incompatible redefinition of a non-negotiable principle
- **MINOR**: New principle or section added, or material expansion of existing guidance
- **PATCH**: Clarifications, wording refinements, typo fixes, non-semantic adjustments

All implementation plans MUST include a Constitution Check gate (see `plan-template.md`). Runtime
development guidance lives in `CLAUDE.md`.

**Version**: 1.0.0 | **Ratified**: 2026-04-17 | **Last Amended**: 2026-04-17
