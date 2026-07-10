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
- **Prep (agent-executable, no device needed): DONE (July 2026).** DEBUG-only auto-drill built: a `ladybug` toolbar button in `CoachChatView` fires `CoachChatService.runPhaseZeroDrill()` — 40 scripted EN/DE turns across all 3 tools (including a guaranteed no-match name and late repeats of PR/next-workout questions), run sequentially. Per turn it logs first-token latency (`chat first token after … ms`, always-on) and total duration; condensation already logs `chat proactively condensing`. Each tool logs its returned fact line (`ChatTool` category, DEBUG-only) so answers can be checked against ground truth. Everything drill-related is `#if DEBUG`-gated. Note: the drill aborts if the chat screen is left (onDisappear cancels the in-flight turn) — keep it open.
- **Overflow drill:** drive ~40 turns; confirm `chat proactively condensing` fires and no error bubble ever appears; confirm a PR/next-workout answer after condensation still matches the tool's fact log.
- **Latency:** prewarmed first token < ~3 s on iPhone 15 Pro-class hardware; time the not-found re-call path too.
- **No-arg tool:** confirm `getNextWorkout` (empty `@Generable` Arguments) is invoked reliably. Fallback if not: add a single dummy enum argument.
- **Done:** all three observed acceptable, or the failing one has a filed fix. If overflow/latency are unacceptable, revisit before Phase 1.

### Device-session script (run this, record results inline)

**Setup:** DEBUG build on an iPhone 15 Pro-class device with real or seeded workout history (`TestDataSeeder`); chat enabled via AI Coach settings → Experimental. Stream logs with `log stream --predicate 'subsystem == "app.gymstreak.aicoach"'` (or Console.app filtered to that subsystem — categories `CoachChatService` and `ChatTool`). Open the chat and tap the **ladybug** toolbar button. **Keep the chat screen open for the whole drill** — leaving it cancels the in-flight turn and aborts the drill.

Observe four things (~40 turns, passive):

1. **Overflow** — `chat proactively condensing (used=…, contextSize=…)` fires at least once; **no error bubble ever appears** in the chat; `chat context window exceeded after condense+retry` never appears in the log.
2. **Latency** — `chat first token after … ms` per turn: prewarmed first turn < ~3,000 ms. Turn 31 ("What's my PR on flurbelblatz?") times the `__NO_MATCH__` re-call path — expect it slower; note the number.
3. **No-arg tool** — every next-workout question (turns 1, 4, 7, 14, 18, 28, 34, 38 of `CoachChatService.drillPrompts`) must produce a `getNextWorkout → …` fact line (`ChatTool` category). If it reliably fails to fire → the dummy-enum-argument fallback above.
4. **Grounding after condensation** — turns 32–35 repeat the bench-PR / next-workout questions from the start; the on-screen numbers must match the `ChatTool` fact line logged immediately before each answer, verbatim.

**Then verify Phase 1 in the same session:** kill the app (swipe away) → relaunch → reopen chat → the drill conversation is still there. Ask a follow-up ("und was war mein Bestwert beim Bankdrücken?") → a `getExercisePR` fact line must appear (grounding survives restore). Tap "New chat" → kill + relaunch → chat starts empty.

**Results (fill in after the session):** _not yet run._

## Phase 1 — Persistence across launches — DONE (July 2026)

**Goal:** the conversation survives app termination (previously an in-memory singleton).

Built as planned; implementation notes:
- **Privacy decision taken: local-only.** `Data/AICoach/Chat/ChatConversationStore.swift` — JSON in `Application Support/AICoachChat/conversation.json`, mirroring `AICoachCache`; deliberately NOT a `@Model` in the CloudKit-synced container (no schema deploy, history never leaves the device). `CoachChatMessage` (+ `Role`/`Phase`) became `Codable` with String raw values.
- **Save points:** after every finished turn (success or failure, via the new `endTurn()`), and on `cancel()` when it finalizes a partial bubble. `.streaming` messages are filtered out at save time. `reset()` ("New chat") clears the store.
- **Session restore:** the `Transcript` is NOT persisted. `configure` loads the snapshot and rebuilds the session with `ChatOverflowPolicy.digest(...)` of the restored messages — exactly the condensation mechanism. Restored `.failed` bubbles are excluded from the digest automatically (it only digests `.final`).
- **Refactor note:** `send(_:)` was split into `beginTurn`/`endTurn` so the DEBUG drill can await turns; the turn Task now skips `endTurn()` when cancelled (`cancel()` already cleaned up), which also removes a pre-existing race where a stale task could clobber `isResponding`/`streamTask` of a newer turn.
- **Tests:** `GymStreakTests/ChatConversationStoreTests.swift` (round-trip, streaming filtered, failed kept, clear, overwrite) via the store's `directory:` test seam.
- **Done-criteria** (kill + relaunch → conversation visible; follow-up still grounds; "New chat" clears store + session): verify on the Phase 0 device session — grounding-after-restore is a live-model behavior.

## Phase 2 — Multiple conversations / history browsing

**Goal:** more than one conversation, browsable and deletable. **Build only if single-conversation persistence (Phase 1) proves insufficient in use** — for short grounded Q&A over a 4K context, one persistent thread + "New chat" may be all users need; don't over-build ahead of demand.

- **Files:** extend `ChatConversationStore` to a keyed collection (`conversationId → messages + topics`), add a lightweight `ChatConversationSummary` (id, title, lastUpdated); new `Presentation/Views/AICoach/Chat/ChatHistoryListView.swift`; `CoachChatViewModel`/service gain conversation selection + new/delete.
- **Session policy:** exactly **one live `LanguageModelSession`** — the selected conversation's. Switching conversations rebuilds the session from that conversation's `ChatOverflowPolicy.digest(...)` (the same mechanism Phase 1 uses for launch restore); never hold N tool-equipped sessions in memory.
- **Title:** derive from the first user message (truncated) — no model call.
- **Done:** create/switch/delete conversations; each retains its own messages; a follow-up after switching still grounds.

## Phase 3 — Prominent entry point

**Goal:** promote from the experimental settings toggle to a first-class surface.

- **Placement:** the app has no separate Progress tab — Fortschritt is a segmented sub-view inside the History tab, and `HistoryView` hides the navigation bar (`.toolbar(.hidden, for: .navigationBar)`), so a `ToolbarItem` is not an option. Put **one** chat entry (sparkle/chat icon, reuse `AISparkleView`) in `HistoryView`'s custom header — it covers both the Trainings and Fortschritt segments, which is where these questions arise.
- **Gating:** `AICoachAvailability` + opt-in; replace `chatExperimentalEnabled` with a normal per-surface toggle following the existing pattern in `AICoachPreferences` (`chatEnabled` + computed `isChatEffectivelyEnabled`, like `workoutDetailEnabled`/`isWorkoutDetailEffectivelyEnabled`).
- **Files:** `HistoryView.swift` header; `AICoachPreferences.swift` (rename toggle, keep the same UserDefaults default policy as the other surfaces); a per-surface toggle row in `AICoachSettingsView` replacing the experimental section; localization updates in `en/de.lproj/Localizable.strings` (`ai_coach.chat.*` keys exist — drop "experimental"/"early preview" copy).
- **Done:** reachable from the History tab (both segments) for eligible+opted-in users; unavailable/opt-in states reuse existing branching UX.

## Phase 4 — Expand the tool set (budget-aware)

**Goal:** answer more question classes. Expansion list: `getVolumeTrend`, `getRoutineDetails`. (`getStreakStatus` from the spike list is **dropped** — `workoutHistoryFacts` already appends the current streak line via `HistoryStatsService.streakWeeks`, so a dedicated tool would pay schema tokens on every turn for an already-reachable fact.)

- Each new tool: terse `Tool` conformance in `Data/AICoach/Chat/Tools/`, backed by an existing service (`FortschrittAggregator`/`ExerciseProgressService` for volume trend; `RoutineRepository` for routine details) via a new `ChatFactProviding` method.
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

Phase 0 (validate) → **Phase 1 (persistence)** → **Phase 3 (entry point)**. Phase 1 and the Phase 0 auto-drill can be built *before* the device session runs — persistence doesn't depend on Phase 0's outcomes (an overflow/latency problem would be fixed in the overflow policy or prewarming, not in message storage). Work continues on the `ai-coach-chat-spike` branch; merging to `main` waits for Phase 0 to pass.

Full order: Phase 0 → Phase 1 → Phase 3 → Phase 4 (more tools) → Phase 6 (polish) → Phase 5 (localization, if needed) → Phase 2 (multi-conversation, only if demanded). Persistence goes before promotion: a first-class surface that forgets everything on relaunch reads as broken, and Phase 1 is the cheaper of the two. Each phase is shippable behind the availability/opt-in gate.
