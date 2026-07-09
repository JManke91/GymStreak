# AI Coach Chat — Full Feature Plan

**Status: planned (2026-07-10). Spike validated — see `docs/ai-coach-chat-feasibility.md` (decision gate PASSED) and `docs/ai-coach-chat-eval.md`.** This is the productionization plan that turns the experimental chat spike into a shipped feature. It is written as chunked, independently-executable phases; each phase lists its goal, touched files, approach, and done-criteria so it can be executed incrementally (or handed to a cheaper model per CLAUDE.md Solution B).

## What already exists (from the spike — do not rebuild)

A working, architecture-clean, tested foundation on `Data/AICoach/Chat/` + `Domain/…/AICoach` + `Presentation/…/AICoach/Chat`:
- Retained multi-turn `LanguageModelSession` with 3 tools (`getNextWorkout`, `getExercisePR`, `getWorkoutHistory`) over existing domain services; fact-resolution doctrine intact (model verbalizes, never computes).
- Free-form + cross-language exercise-name resolution (`ExerciseNameResolver`: folded matching + model-assisted `__NO_MATCH__` fallback + same-name aggregation).
- Automatic context-overflow handling (`ChatOverflowPolicy`: proactive condense + reactive retry; visible message list decoupled from transcript).
- Streaming chat UI, EN/DE, opt-in Experimental toggle entry point, markdown stripping, operational logging.
- 18 unit tests locking the deterministic behavior.

## Accepted constraints (from the eval — design around, don't fight)

- **No `ToolCallingMode` on iOS 26.x** → tool invocation is instructions-driven; keep tool descriptions terse and disambiguating.
- **3B phrasing slips** (e.g. "last weekend" for "last week") occur even when grounding is correct — acceptable for chat; do not over-engineer.
- **4,096-token context** shared by instructions + tool schemas + transcript → every added tool costs budget on every turn; curate the tool set.
- **On-device only** (no watchOS FoundationModels); chat is read-only over user data.

---

## Phase 0 — Build-time validation checkpoints (do FIRST, on device)

Close the two items the simulator can't (they gate heavy investment). One device session.
- **Overflow drill:** drive ~40 turns; confirm `chat proactively condensing` fires and no error bubble ever appears; confirm a PR/next-workout answer after condensation still matches the tool's fact log.
- **Latency:** prewarmed first token < ~3 s on iPhone 15 Pro-class hardware; time the not-found re-call path too.
- **No-arg tool:** confirm `getNextWorkout` (empty `@Generable` Arguments) is invoked reliably. Fallback if not: add a single dummy enum argument.
- **Done:** all three observed acceptable, or the failing one has a filed fix. If overflow/latency are unacceptable, revisit before Phase 1.

## Phase 1 — Persistence across launches

**Goal:** the conversation survives app termination (today it's an in-memory singleton).

- **Decision required (privacy):** chat history is on-device today. Persist **local-only** (no CloudKit) to preserve that guarantee and avoid a CloudKit schema deploy (see MEMORY: schema changes must be deployed before release). Recommend a JSON store mirroring `AICoachCache` (Application Support), NOT a new `@Model` in the CloudKit-synced container.
- **Files:** new `Data/AICoach/Chat/ChatConversationStore.swift` (load/save `[CoachChatMessage]` + per-turn topics as JSON); `CoachChatService` loads on `configure`, saves after each finalized turn / reset.
- **Session restore:** do NOT persist/restore the `Transcript`; on launch, rebuild a fresh session whose instructions carry a `ChatOverflowPolicy.digest(...)` of the restored messages (same mechanism as condensation). The visible list restores fully from JSON.
- **Done:** kill + relaunch → prior conversation visible; a follow-up question still grounds; "New chat" clears store + session.

## Phase 2 — Multiple conversations / history browsing

**Goal:** more than one conversation, browsable and deletable.

- **Files:** extend `ChatConversationStore` to a keyed collection (`conversationId → messages`), add a lightweight `ChatConversationSummary` (id, title, lastUpdated); new `Presentation/Views/AICoach/Chat/ChatHistoryListView.swift`; `CoachChatViewModel`/service gain conversation selection + new/delete.
- **Title:** derive from the first user message (truncated) — no model call.
- **Done:** create/switch/delete conversations; each retains its own messages; the service holds one active session per selected conversation.

## Phase 3 — Prominent entry point

**Goal:** promote from the experimental settings toggle to a first-class surface.

- **Placement:** toolbar entry (sparkle/chat icon) on the History and Progress tabs — where these questions arise. Reuse `AISparkleView`.
- **Gating:** `AICoachAvailability` + opt-in (`AICoachPreferences.isEffectivelyEnabled`); retire the `chatExperimentalEnabled` sub-toggle (or fold into a normal per-surface toggle like the other AI surfaces).
- **Files:** toolbar items in the History/Progress tab roots; a per-surface toggle row in `AICoachSettingsView` replacing the experimental section; localization updates (drop "experimental"/"early preview" copy).
- **Done:** reachable from History/Progress for eligible+opted-in users; unavailable/opt-in states reuse existing branching UX.

## Phase 4 — Expand the tool set (budget-aware)

**Goal:** answer more question classes. Spike expansion list: `getVolumeTrend`, `getRoutineDetails`, `getStreakStatus`.

- Each new tool: terse `Tool` conformance in `Data/AICoach/Chat/Tools/`, backed by an existing service (`FortschrittAggregator`/`ExerciseProgressService` for volume trend; `RoutineRepository` for routine details; `HistoryStatsService.streakWeeks` for streak) via a new `ChatFactProviding` method.
- **Budget guard:** measure `tokenCount(for: tools)` after each addition; if the tool set + instructions crowd the answer/transcript budget, curate (merge overlapping tools, trim descriptions). Add a test asserting each new fact method's output like `ChatFactServiceTests`.
- **Done:** new question classes answered and grounded; tool-schema token cost measured and within budget.

## Phase 5 — Fact-line localization (optional, measure first)

Today fact lines are canonical English translated on-device (a DE glossary is in the instructions). If Phase 0/build testing shows term leakage or mistranslation, localize the fact lines in `ChatFactService` (via `.localized` keys, embedding the user's locale) instead of relying on the model. Decision driven by observed quality, not upfront.

## Phase 6 — Telemetry, accessibility, polish

- **Telemetry:** route chat events (generation started/completed/failed, condensation, tool-not-found) through `AICoachTelemetry` — event types only, never prompt/answer/exercise names (matching existing rules).
- **Accessibility:** VoiceOver reads bubbles in order; Dynamic Type on bubbles/input; `StreamingTextView` already VO-safe. Verify the input bar + suggested-question buttons.
- **Polish:** retry affordance on `.failed` bubbles; refine empty/unavailable states; ensure `textOnTint` on all tinted chrome (already correct in spike).
- **Done:** telemetry visible in Instruments/Console; VoiceOver + Dynamic Type pass; no `.shared`/layer regressions (run `architecture-reviewer`).

---

## Cross-cutting decisions to confirm before/while building

1. **Chat-history privacy:** local-only persistence (recommended) vs. CloudKit-synced across the user's devices (adds a schema deploy + a privacy-copy change).
2. **Default-on vs opt-in** once promoted out of "experimental".
3. **Fact-line localization** (Phase 5) — only if measured quality warrants.

## Explicitly still out of scope

watchOS chat (no FoundationModels), writing/mutating tools (chat stays read-only), Siri/App Intents integration. Record here if any is later pulled in.

## Suggested sequencing

Phase 0 (validate) → Phase 3 (entry point, cheap, high user value) → Phase 1 (persistence) → Phase 2 (multi-conversation) → Phase 4 (more tools) → Phase 6 (polish) → Phase 5 (localization, if needed). Each phase is shippable behind the availability/opt-in gate.
