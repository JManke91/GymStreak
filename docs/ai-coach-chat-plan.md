# AI Coach Chat — Full Feature Plan

**Status: in progress (2026-07-10) — Phases 0, 1, 3 DONE; next: Phase 4 (expand tool set). Spike validated — see `docs/ai-coach-chat-feasibility.md` (decision gate PASSED) and `docs/ai-coach-chat-eval.md`.** This is the productionization plan that turns the experimental chat spike into a shipped feature. It is written as chunked, independently-executable phases; each phase lists its goal, touched files, approach, and done-criteria so it can be executed incrementally (or handed to a cheaper model per CLAUDE.md Solution B).

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

## Phase 0 — Build-time validation checkpoints (do FIRST, on device) — DONE (July 2026, PASS with residuals)

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

**Results (device sessions run 2026-07-10, two full 40-turn drill passes):**

- **Latency:** PASS. First token 1565–3133 ms across both runs, comfortably under the ~3s bar.
- **No-arg tool (`getNextWorkout`):** PASS. Fired reliably across both runs; the rare cases where no fact-line appeared in the log still produced correct on-screen answers (short-distance recall from transcript, e.g. turn 4 repeating turn 1 three turns later).
- **Persistence (Phase 1 re-check):** PASS. Force-quit/relaunch retained history, follow-up grounded correctly, "New chat" + relaunch started empty. Confirmed twice.
- **Overflow — condensation itself:** PASS. `chat proactively condensing` fired reliably (11 times in run 1) whenever the transcript approached the budget.
- **Transient generation failures: FAIL.** `chat generation failed: NSError` (a non-`GenerationError` type, so it skips the built-in overflow retry and goes straight to a failed bubble) occurred on turns 29/32 (run 1) and turns 17/26 (run 2) — **4 user-visible error bubbles across 80 total turns (~5%)**. Shown to the user as "⚠️ Etwas ist schiefgelaufen. Bitte versuche es erneut." — violating the "no error bubble ever appears" done-criterion. Evidence against a condense-race as sole cause: run 1 turn 29 failed right after condensing, but run 1 turn 32 failed with NO preceding condense, and run 2 turn 34 condensed and succeeded. All 4 failures produced no first token and resolved in <1.8s; every failing question succeeded on the other run — i.e. transient, load-correlated (the drill fires 40 turns back-to-back with zero think-time), most likely daemon-side. Our tools cannot throw (`ChatFactProviding` methods are non-throwing), so the error is framework-internal. `logError` currently prints only the type name ("NSError") — domain/code/description are needed to classify further.
- **Grounding — doctrine violation confirmed (run 2):** the model fabricated data twice:
  - Turn 12 ("How long is my current streak?") → answered **"4 days"**; every other streak answer in the same conversation (turns 30, 37) correctly says "1 week." No tool call visible for turn 12 — invented, not grounded.
  - Turn 34 (a designated grounding-recheck turn) ("Wann ist mein nächstes Workout?") → answered **"...um 06:00 Uhr"**; `getNextWorkout` has never returned a time-of-day, only day-of-week. Fabricated detail.
  - Turn 25 (softer case): "your current streak of 34 workouts" — conflates the earlier "34 total workouts" fact with "streak," muddled but not fully invented.
- **Tool resolution is non-deterministic run-to-run:** "What's my PR on lat pulldown?" (turn 13) found the record cleanly in run 1, but declined with "couldn't find" in run 2 for the identical question against identical data. Root cause visible in run 2 turn 33: the model passed a TRANSLATED argument — `getExercisePR(Bankdrücken)` for the English question "What's my bench press PR?" (the surrounding conversation was German) — despite the verbatim-copy instruction. The `__NO_MATCH__` list mapping then failed to bridge it. Declines safely (no fabrication), but explains run-to-run variance.
- **Net verdict: Phase 0 does NOT pass cleanly.** Latency/persistence/basic tool-calling are solid, but ~5% of turns produced a user-visible error bubble, and grounding can silently fail into fabricated answers (not just declines) after conversation history grows — the exact risk case Phase 0 was designed to catch. Fixes below; re-run the drill to verify.

### Phase 0 follow-up fixes (2026-07-10)

Root-cause research (FoundationModels error semantics, via ios-api-researcher) and the resulting changes:

**Research findings (keep — future work must not re-do this):**
- `prewarm()` is documented by Apple as safe only when there is **≥1 second** before the next respond/stream call: "You should only use prewarm when you have a window of at least 1 second before the call to a respond method" ([prewarm docs](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm%28promptprefix%3A%29), [KV-cache guide](https://developer.apple.com/documentation/foundationmodels/optimizing-key-value-caching-in-language-model-sessions)). Our `condense()` called `prewarm()` and then `streamResponse` in the same breath — a documented anti-pattern and the strongest explanation for the post-condense failures.
- `LanguageModelSession.GenerationError` is **deprecated**; newer SDKs split it into `LanguageModelSession.Error` (`.concurrentRequests`, `.transcriptMutationWhileResponding`), `SystemLanguageModel.Error` (`.assetsUnavailable`), and `LanguageModelError`. Apps built with Xcode 26 keep catching `GenerationError` until rebuilt with Xcode 27 ([deprecation notice](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror)). When migrating to the Xcode 27 SDK, update `isContextOverflow`/`logError` in `CoachChatService`.
- A literal runtime type of `NSError` (what our log printed) means an ObjC/daemon-layer error escaped unwrapped — none of the Swift error types would print that way. Combined with: no nested model calls in our tools (ExerciseNameResolver is pure string matching; the `__NO_MATCH__` fallback is in-band), the single-session design, and the `isResponding` guard — reentrancy (`concurrentRequests`) is ruled out. The failures are transient daemon/IPC errors under sustained back-to-back load (the drill fires 40 turns with zero think-time).
- `LanguageModelSession.ToolCallError` exists (struct wrapping `tool` + `underlyingError`) and is thrown when a tool's `call` throws — impossible for us today (`ChatFactProviding` methods are non-throwing), but relevant if a future tool can throw.
- WWDC26 (session 241) added transcript-rollback semantics (`.revertTranscript`/`.preserveTranscript`) for tool errors/cancellation — relevant context for why a failed attempt may leave a session transcript in a bad state on current OS versions.

**Fixes applied (`CoachChatService.swift`, `CoachChatInstructions.swift`):**
1. `condense()` no longer calls `prewarm()` (a stream follows immediately; the ≥1 s window doesn't exist there). `prewarm()` remains in `reset()` and the public `prewarm()` — both genuinely idle paths.
2. `performTurn` now retries **any** non-overflow generation error once (previously only context overflow): the failed attempt is logged (see 3), the session is rebuilt from the digest (a failed attempt may leave the transcript wedged), and the turn re-runs. Only a second consecutive failure shows the error bubble.
3. `logError` logs NSError `domain`/`code`/`localizedDescription` for non-`GenerationError` failures — the next drill run identifies the exact daemon error instead of an opaque "NSError".
4. Instructions hardened against the two observed fabrications: (a) "call the tool again even when a similar question was answered earlier — the earlier answer may be outdated" (streak "4 days" came from stale transcript context, since every history fact line carries a streak sentence); (b) "the facts never include a time of day — never mention a clock time; a streak is always a number of weeks, never days" (the "um 06:00 Uhr" embellishment happened despite a correct tool call).

**Re-verify (device):** re-run the 40-turn drill → expect zero error bubbles (transient failures now logged as `chat transient generation failure — rebuilding session and retrying once` followed by a `domain=… code=…` line, but absorbed); spot-check streak and next-workout answers for fabricated units/times. Fabrication mitigation is instructions-only (no `ToolCallingMode` on iOS 26.x), so treat it as risk-reduction to be confirmed by observation, not a hard guarantee.

### Phase 0 verification run (run 3, 2026-07-10, post-fix build) — VERDICT: PASS with documented residuals

- **Error bubbles: FIXED.** One transient failure occurred (turn 17) and the new retry absorbed it invisibly — the turn completed successfully in 4.0 s total (failed attempt + rebuild + retry). Zero error bubbles on screen across 40 turns.
- **Error identity captured (research finding — keep):** the opaque failure is `domain=FoundationModels.LanguageModelSession.GenerationError code=-1, desc="Der Vorgang konnte nicht abgeschlossen werden."` — the framework's OWN error type degraded to a plain NSError with a generic code. `-1` maps to no enum case, so `error as? LanguageModelSession.GenerationError` can never catch it (the typed error loses its Swift identity crossing from the inference daemon — framework-level quirk). Generic transient failure; the single automatic retry is the correct and sufficient mitigation. Do NOT attempt to special-case this domain string for control flow.
- **Latency: PASS** (1658–3142 ms first token; the retried turn 4012 ms total).
- **Residuals (accepted for now — small-model verbalization slips, monitor via Phase 6 telemetry):**
  - One clock-time slip remained post-condense (turn 34: "um 00 Uhr" appended to an otherwise correct, tool-grounded answer). Milder than run 2's invented "06:00 Uhr" (a zero time reads as broken, not plausibly wrong), but proves the instructions-only mitigation is statistical.
  - Tool-skipping happens in clusters right after condensation (run 3 turns 24, 26–30: six of seven turns called no tool) — the fresh session's digest appears to tempt the model into answering from summary. Outcomes were declines or stale-but-correct repeats, not dangerous fabrications. If this worsens, the next lever is trimming assistant answers (the numbers) out of `ChatOverflowPolicy.digest` so stale facts aren't available to parrot — deliberately NOT done yet (don't over-engineer; digest verbatim pairs are what make follow-ups work).
  - Turn 30 leaked the internal tool name to the user ("Du kannst mit getWorkoutHistory überprüfen") → fixed with an instruction clause (never mention tool/function names); verify incidentally in the next device session.
  - Occasional reply-language slips (German answer to an English question) and clumsy phrasing ("Du hast diese Woche 1 Woche lang gearbeitet") — within the accepted 3B constraint from the eval.
- **Phase 0 exit decision:** all three gate items (overflow handling, latency, no-arg tool) now pass; the residuals are quality-of-phrasing risks, not data-integrity or stability risks. Proceed to Phase 3.

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

## Phase 3 — Prominent entry point — DONE (July 2026); entry point SUPERSEDED same day

**Superseded (2026-07-10, same day):** the History-header sparkle entry described below was replaced by the floating coach bar (`tabViewBottomAccessory`, iOS 26.1) — see `docs/ai-coach-entry-point-concepts.md`. Still current from this phase: the `chatEnabled` per-surface preference, the Surfaces settings row, and the removal of the Experimental section. The History header retains only the settings gear.

**Goal:** promote from the experimental settings toggle to a first-class surface.

Built as planned; implementation notes:
- **Entry point:** `AISparkleView` button (size 20) in `HistoryView`'s custom header next to the settings gear, covering both the Trainings and Fortschritt segments. Pushes `CoachChatView` via `.navigationDestination(isPresented:)` (the nav bar is hidden on the tab root, so no `ToolbarItem`). Shown only when `AICoachAvailability.shared.isAvailable && AICoachPreferences.shared.isChatEffectivelyEnabled`; `HistoryView` refreshes availability in `.task`. Accessibility label reuses `ai_coach.chat.entry.title`.
- **Preference:** `chatExperimentalEnabled` (key `aiCoachChatExperimentalEnabled`, default off) replaced by `chatEnabled` (NEW key `aiCoachChatEnabled`, default **on** like every other surface — cross-cutting decision 2 resolved as default-on). No migration from the old key: the spike opt-in state is deliberately discarded; the old key is orphaned in UserDefaults. Computed `isChatEffectivelyEnabled` follows the `isWorkoutDetailEffectivelyEnabled` pattern.
- **Settings:** the Experimental section (toggle + "Open chat" nav link) is gone; chat is now a fifth row in the Surfaces group of `AICoachSettingsView` (icon `bubble.left.and.text.bubble.right`). Settings no longer link to the chat — the header button is the single entry point.
- **Localization:** `ai_coach.chat.experimental.*` and `ai_coach.settings.section.experimental` removed; `ai_coach.settings.surface.chat.title/.detail` added (EN/DE, no "early preview" copy). All other `ai_coach.chat.*` keys unchanged.
- **Done-criteria met:** build succeeds; reachable from the History tab (both segments) for eligible+opted-in users; unavailable/not-opted-in users simply don't see the button (settings retain the existing unavailability branching).

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
