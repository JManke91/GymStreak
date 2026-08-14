# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Things MCP Preference

When using the Things MCP for work in this repository, default to the Things project **"Gym Streak"** (UUID `7BZCT8CLX8v5iaLRqPBHXS`) unless the user explicitly specifies a different project.

## Agent Skills

### Issue tracker

Things is the source of parent work items; implementation slices are local Markdown files. See `docs/agents/issue-tracker.md`.

### Triage labels

Local implementation tickets use the standard engineering-skill status vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. See `docs/agents/domain.md`.

### MCP servers

Project MCP servers (context7, things) are declared in `.mcp.json` at the repo root and shared via git. See `docs/agents/mcp-servers.md` for setup and the secrets policy (env-var placeholders only — never commit keys).

### Things-to-local-ticket pipeline

When the user asks to implement or break down a Things task, first fetch the explicitly named or identified to-do from the **Gym Streak** Things project. Treat it as the parent work item: do not complete, edit, or duplicate it in Things unless the user explicitly asks (moving it to the "Plan is ready in Claude Code" heading is a sanctioned exception — see below).

Before drafting tickets, check whether the fetched description is sufficient and consistent: if it's thin, ambiguous, or conflicts with `CONTEXT.md`/existing code, run `/grill-with-docs` first to sharpen it and resolve the conflict (escalate to `/wayfinder` instead if the effort turns out too large or foggy for a single session). Only once the idea is sharp, invoke `/to-tickets` using the parent task's title, notes, checklist, and relevant codebase context. Draft tracer-bullet vertical slices, show their blocking edges, and ask the user to approve the granularity before publishing. On approval, create one local ticket per slice under `.scratch/<feature-slug>/issues/` in dependency order, then move the parent Things to-do under the **"Plan is ready in Claude Code"** heading in the Gym Streak project (`update_todo` with `id: <parent UUID>, heading: "Plan is ready in Claude Code"`). This heading move is a sanctioned Things edit specific to this pipeline — it only relocates the to-do to signal a ready plan and never changes its title, notes, checklist, or completion state. If the heading doesn't exist or the move fails, tell the user and continue — it never blocks ticket publication.

For a clearly atomic task, `/to-tickets` should still create a single `01` local ticket so its acceptance criteria and source remain recorded.

**Ticket creation and implementation are separate steps — never chain them implicitly.** Match the user's wording: a request to "create tickets" / "break down" ends the turn once the approved ticket files exist (offering to start ticket 01 is fine; starting it is not). Implementation begins only when the user explicitly asks for it ("implement", "start ticket 01", "work on it", …); then implement only the first unblocked local ticket unless directed otherwise. Never begin implementation while the breakdown is awaiting approval.

**Closing the loop:** when the last local ticket of a feature's `.scratch/<feature-slug>/issues/` set is completed — i.e., every implementation ticket derived from the parent Things task is done — proactively ask the user (via AskUserQuestion) whether the feature is finished and tested. Only on an explicit yes, mark the parent Things to-do as completed via the Things MCP (`update_todo` with `completed: true`). On a no or an unclear answer, leave the Things task untouched. This confirmed prompt is the one sanctioned path for completing the parent task; it does not authorize any other edits to it.

That same yes also closes out the local tickets, in this order: **harvest → mark → archive.** Confirm the feature's `docs/<feature>.md` carries the ticket bodies' durable knowledge (root causes, discarded approaches, verification records, and any follow-up work found but not applied) and port what's missing; set each ticket to `**Status:** done`; then **move** `.scratch/<feature-slug>/` to `.scratch/_done/<feature-slug>/`. The top level of `.scratch/` is the live work queue and shows open features only.

**Never delete anything under `.scratch/` on your own initiative.** It is gitignored, so removal is permanent and unrecoverable — archival is always a move, and deletion needs an explicit, specific instruction from the user. If a ticket records follow-up work that was never applied, surface it before archiving rather than burying it. See `docs/agents/issue-tracker.md` for the full procedure and `docs/agents/triage-labels.md` for the status vocabulary.

## Working Style

Principles for how to work in this repo. They apply to every model; they matter most on the capable, long-running models (Fable 5 / Opus) that can otherwise over-plan or over-build.

- **Act when you have enough to act.** Don't re-derive settled facts, re-litigate decided questions, or narrate options you won't pursue. Weighing a choice → give a recommendation, not a survey.
- **Do the simplest thing that works; don't over-build.** No refactors, abstractions, helpers, error handling, or fallbacks beyond what the task needs. A bug fix doesn't need surrounding cleanup. Don't design for hypothetical future requirements. Validate at system boundaries (user input, HealthKit, watch sync); trust internal code.
- **Steer with intent, not enumeration.** A brief instruction is enough — you don't need every case spelled out. When something is ambiguous, infer from the stated goal.
- **Assessment vs. action.** When the user is describing a problem, asking a question, or thinking out loud, the deliverable is your assessment: report findings and stop. Don't apply a fix until they ask.
- **Lead with the outcome.** The first sentence of a final summary answers "what happened / what did you find." Detail and reasoning come after. Terse shorthand is fine while working between tool calls; in the final message write complete sentences and spell out identifiers — readability beats compression.
- **Ground claims in evidence.** Before reporting progress, check each claim against an actual tool result. If the build fails, say so with output; if a step was skipped, say that; when something is verified, state it plainly.
- **Pause only when you truly need the user** — a destructive/irreversible action, a real scope change, or input only they can give. Otherwise proceed rather than ending on a promise.

## Development Commands

## Building new features/updating existing features

- After building a new feature, make sure the app still compiles
- When building a new feature make sure to create a .md file in the /docs folder that summarizes all the important details inlcuding what the feature does, how it works, how it's architecutlly structured, what components are involved etc. make sure to include the ios and watch target for documentation. the goal is to be able to reference this file later for quick context
- For every code change check if an existing feature is modified and if there already is a corresponsing .md file in the /docs folder make sure to update according to the criteria stated for building new .md files.
- **Run the risk-based architecture review** (see "Architecture Review (risk-based)" below) before reporting work as done — mandatory when the change has architectural surface, skippable with a one-line justification for trivial edits.

This is an iOS app built with Xcode:

- **Build & Run**: Open `GymStreak.xcodeproj` in Xcode and use Cmd+R to build and run
- **Clean Build**: Product → Clean Build Folder (Cmd+Shift+K)
- **iOS Target**: iOS 26.1+ (app target; bumped 2026-07-10 for `tabViewBottomAccessory(isEnabled:)` — widgets/tests targets are 26.0/26.2)
- **Xcode Version**: 26+ required (iOS 26 SDK)
- **Unit tests**: two targets, two schemes — iOS `GymStreakTests` and watchOS `GymStreakWatchTests`. There is no combined test plan (one `xcodebuild test` run resolves one destination platform), so run both via `bundle exec fastlane test_unit` (or `test_unit_ios` / `test_unit_watch`). **A change touching watch code must run the watch suite** — it asserts on the *watch* copies of per-target-duplicated logic, and skipping it is how a copy-drift ships. Watch tests are Swift Testing and must annotate suites `@MainActor` (the watch module is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). See `docs/watch-unit-tests.md`.

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

## Architecture Review (risk-based)

After completing a code change and before reporting it as done, decide whether the change has **architectural surface**.

**Run the `architecture-reviewer` agent** (`.claude/agents/architecture-reviewer.md`, via the Agent tool on the current diff) when ANY of these apply:

- New, moved, or deleted source files
- New or changed `import` statements, new types (class/struct/enum/protocol/actor), or new dependency wiring (anything touching `App/AppDependencies.swift`)
- Changes in `Domain/` or `Data/`, or a diff spanning more than one layer
- Refactors, or diffs beyond ~50 changed Swift lines
- **Rendering surface**, regardless of diff size: any change to a scrolling/list view, a row or cell view, or a view that reads SwiftData model properties — and any diff that adds a `ForEach`, a formatter, a collection operation, or a `@Model` property read to a view body (see "Performance: main thread and rendering")
- Any doubt about whether a Hard rule or deliberate decision is affected — when in doubt, review

When it runs: **CRITICAL findings must be fixed** and the reviewer re-run until it returns PASS (or PASS WITH WARNINGS with the warnings explicitly acknowledged), and include the verdict in your final report.

**Skip the reviewer** for changes with no architectural surface: localization/strings, comments/docs, asset or config tweaks, TestFlight notes, and small in-place edits inside existing function or view bodies (copy/layout/value tweaks, guard fixes, threshold changes) that add no files, types, imports, or dependencies. **The size-based skip does not apply to rendering surface** — a one-line edit that puts a formatter, a loop, or a relationship read into a view body is exactly the mistake this gate exists to catch, so it goes to review however small it is. When skipping, self-check the diff against the Hard rules and the main-thread rules above, and state in your final report that the review was skipped and why (one line).

This remains a second review layer — it does not replace compiling the app or self-review.

## iOS API Research (mandatory)

Whenever a task requires choosing, evaluating, or understanding an Apple/iOS/watchOS API or framework (which API to use, framework capabilities, version availability, HealthKit/WatchConnectivity/FoundationModels behavior, comparing implementation approaches):

1. Launch the **`ios-api-researcher`** agent (`.claude/agents/ios-api-researcher.md`) via the Agent tool — do NOT answer from training data.
2. This agent replaces direct Context7 MCP calls for Apple platform questions in this repository: the global rule to call Context7 directly is overridden here; the agent performs the Context7 research itself. (Context7 may still be called directly for non-Apple libraries/tools.)
3. Exceptions: trivial syntax questions verifiable from existing code in this repo, and questions already answered in `/docs` feature files.

## Multi-Agent Work: Teams and Model Selection

**Agent teams** (parallel Claude Code instances coordinating via a shared task list) may be used when they genuinely help — parallel research/review from different angles, independent modules (e.g. iOS vs. watch target), competing debugging hypotheses, or separable cross-layer work. Propose one and let the user confirm before teammates spawn; don't use them for sequential work, same-file edits, or tightly-coupled work. Teammates and subagents inherit only project context + the spawn prompt (not your conversation), so always hand off full, self-contained context.

**Model selection.** The currently selected model is the main brain: it holds context, makes decisions, lays out the plan. Default ranking (capability ↓, cost ↓): **Fable 5** (reserve for deep-context judgment, ambiguous tradeoffs, synthesizing many findings — most capable, most expensive) → **Opus 4.8** (strong default for substantial delegated work) → **Sonnet 5** (well-specified execution, mechanical refactors, straightforward lookups). **Reviews of plans/implementations use Fable 5 or Opus 4.8 — never Haiku.** The mandatory `architecture-reviewer` pass must run on a capable model.

**How to "hand execution to a cheaper model" (the mechanism matters).** The main brain **cannot change its own model** — `/model` is user-only and I can't invoke it on myself. "Handing off" therefore means *delegating to* a cheaper sub-instance, not *becoming* cheaper. Two patterns, chosen by whether execution can run cold and unattended:

- **Solution A — in-session delegation (I apply this automatically).** When the work splits into bounded chunks I can specify completely in a self-contained spawn prompt and I don't need the user mid-flight: I stay on the powerful model and spawn cheaper subagents via the Agent tool's `model` override (e.g. `model: "sonnet"`, which beats the agent's own frontmatter). The subagent's tokens bill at its own rate, so this genuinely saves money. Subagents start **cold** (project context + spawn prompt only, no conversation) and return only a summary — so the prompt must carry everything. *Trigger: bounded + self-contained + no user-in-the-loop.* Examples: writing tests from a spec, localizing new strings, a mechanical multi-file refactor spanning the iOS and watch targets.
- **Solution B — plan-to-disk + user re-model (I recommend it; only the user can execute it).** The only way to make the **main thread itself** cheap. When execution is long, iterative, or needs the live conversation/user input, I do the deep planning on the powerful model, persist a **chunked, independently-executable plan to a file on disk** (`docs/` or scratchpad — not a transient task list), then stop and tell the user to run `/clear`, `/model sonnet`, and re-seed with "read `<plan file>`, do task 1." I never claim this happened — I can't run those commands. *Trigger: long + interactive + user-in-the-loop.* Example: a large multi-file UI feature the user eyeballs chunk by chunk.

Escalate and redo work if a cheaper model's output misses the bar — escalating costs less than shipping mediocre work. For Apple/iOS/watchOS API questions, delegate to the `ios-api-researcher` agent (see "iOS API Research" above) rather than answering from training data.

## Context / Token Hygiene

Be deliberate about what occupies the main context window — wasted tokens are wasted budget, and a cluttered window degrades reasoning.

- **Keep exploration out of the main window.** Route broad file-scanning, research, and plan-drafting through a subagent (Explore/Plan/general-purpose). Subagents run in their own context and return only a summary, so the raw exploration never clutters the main thread. Prefer this over reading many files directly when I only need the conclusion.
- **Persist before you prune.** A plan or set of decisions is only safe to drop once it lives in a durable artifact (a file in `docs/`, the scratchpad, or a task list) — never only in chat history. Feature work is documented in `docs/` regardless (see "Feature Documentation").
- **Ask the user to clear/compact when it makes sense — never assume it's done.** `/clear` and `/compact` are user-only commands; I cannot invoke them on myself. When the main window is heavy with now-redundant context (e.g. an approved plan whose exploration is finished, or a completed sub-task) AND everything still needed is persisted to a file, proactively tell the user it makes sense to reset and ask them to run it: `/clear` (hard reset — re-seed from the plan/artifact file) or `/compact focus on <topic>` (keep a summary). State plainly what's safely captured and where. If anything still needed lives only in chat, don't suggest it.
- **Guide auto-compaction, don't fight it.** Auto-compact preserves this CLAUDE.md. Trust it for gradual context pressure; reserve an explicit clear/compact for clean task boundaries.

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

## Performance: main thread and rendering (hard rules)

SwiftUI re-evaluates `body` on every invalidation, and a non-lazy `VStack` builds every
child eagerly — so per-item work that looks trivial becomes a multi-hundred-millisecond
main-thread hang at real data volumes. This section is written as prohibitions rather
than preferences because exactly this shipped: see `docs/history-performance.md` for the
measured 630 ms hang, its seven causes, and the remediation.

1. **`ForEach` over user-scaled data belongs in a lazy container** — `LazyVStack` /
   `LazyHStack` / `LazyVGrid` / `LazyHGrid`, or `List`. A plain `VStack`/`HStack` +
   `ForEach` inside a `ScrollView` constructs and lays out every row, offscreen ones
   included, before the first frame. A bounded literal set (a 7-day strip, a 2-item
   segmented control) is fine in a plain stack.
2. **Never construct a formatter in `body`, in a computed property `body` reads, or in a
   per-row helper.** `DateFormatter`, `RelativeDateTimeFormatter`, `NumberFormatter`,
   `MeasurementFormatter`, `ISO8601DateFormatter`, `JSONEncoder`/`JSONDecoder` are all
   expensive to allocate and these sites run once per row per render. Hoist to `static let`.
3. **No aggregation in `body`.** If a computed property read by `body` iterates a
   collection (`reduce`, `filter`, `sorted`, `flatMap`, `Dictionary(grouping:)`) or calls a
   service, precompute it into `@State` or the ViewModel and pass the result in.
4. **Row and cell views take value structs, not `@Model` objects.** Reading a SwiftData
   `@Relationship` — or any computed property that walks one — is a potential disk fetch;
   doing it per row is an N+1 fault. Build the display struct once, hand that to the row.
5. **Prefetch relationships you know you will traverse.** A `FetchDescriptor` whose results
   feed a list that reads relationship-derived values sets
   `relationshipKeyPathsForPrefetching`.
6. **Observe narrowly.** Don't bind a view to a broad multi-purpose `ObservableObject` for
   two properties — every unrelated `@Published` change re-renders it. Be especially wary
   of view models that own a timer.
7. **`onAppear` does no heavy synchronous work.** `.task` is not a fix by itself: it runs
   synchronously up to its first `await`, so the work must actually become async or move
   off the main actor (`@ModelActor` for SwiftData aggregation).
8. **Use stable identifiers in `ForEach`** so diffing doesn't rebuild rows needlessly.

When a screen's cost scales with user data, measure rather than assume — Instruments'
SwiftUI template; `docs/history-performance.md` §5 has the click paths, the acceptance
targets and a before/after comparison method.

## Concurrency (hard rules)

The project compiles in **Swift 6 language mode** (`SWIFT_VERSION = 6.0`, project level)
with zero warnings across all six targets. **`docs/swift6-concurrency.md` is the
reference — read it before changing isolation, adding a singleton, or touching a
concurrency build setting.** Binding rules:

1. **`nonisolated async` does NOT guarantee off-caller execution.** Under SE-0461
   (enabled project-wide via `SWIFT_APPROACHABLE_CONCURRENCY`) it runs on the *caller's*
   actor. Any boundary whose purpose is to leave the main actor needs **`@concurrent` on
   the concrete method** — see `SwiftDataHistorySnapshotProvider`. Without it the History
   aggregation silently ran on main (~600 ms; build green, caught only by
   `largeSnapshotBuildKeepsMainActorResponsive`). Put `@concurrent` on the **conforming
   type's method** — whether annotating a protocol requirement also works is not
   documented (SE-0461 is silent on witnesses), so do not rely on it.
   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is watch-target-only, because a module
   default of `MainActor` misdescribes the isolation-agnostic `Domain/` layer.
2. **Shared service** = `@MainActor final class X { static let shared = X() }` behind a
   `@MainActor` Domain protocol, wired in `AppDependencies`. A `static let` of a
   non-`Sendable` type will not compile.
3. **`Domain/` stays isolation-agnostic.** Never add `@MainActor` to `Domain/Services/`
   pure logic — the `@ModelActor` History store calls it from its own executor.
4. **Apple delegate conformances**: `@MainActor` class, each delegate method
   `nonisolated`, hop with `Task { @MainActor in … }` (never `DispatchQueue.main.async`
   — SE-0431 ordering is relied on by watch sync; never `MainActor.assumeIsolated` for
   callbacks that are genuinely off-main). **Extract `Sendable` values before the hop**
   — never let `WCSession`, `WCSessionFile`, an `NSPersistentCloudKitContainer.Event` or
   a `[String: Any]` payload cross it.
5. **Escape-hatch ranking** — prefer left, justify right in a comment:
   `nonisolated` (checked; the compiler still rejects mutable/non-`Sendable` state
   inside) → `Sendable` boundary projection → `@preconcurrency import` (Apple's
   annotation gap) → `@unchecked Sendable` box (needs a written invariant) →
   `nonisolated(unsafe)` (avoid).
6. **`isolated deinit`** (SE-0371) for `@MainActor` classes tearing down `Timer`s or
   `NSObjectProtocol` observer tokens.
7. **`@MainActor` XCTest classes** must override `setUp() async throws` /
   `tearDown() async throws`, never the `…WithError() throws` variants (which are
   `nonisolated` and silently strip the class's isolation).
8. **After any isolation or concurrency-build-setting change, run the unit tests** —
   not just a build. A build cannot catch rule 1; only
   `largeSnapshotBuildKeepsMainActorResponsive` can.

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
