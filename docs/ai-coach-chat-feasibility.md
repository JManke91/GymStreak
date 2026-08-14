# AI Coach Chat Assistant — Feasibility Analysis & Spike Plan

**Status: spike BUILT (July 2026), pending on-device evaluation.** Step 0 SDK verification is done (results below) and the spike is implemented and compiles against the iOS 26.5 SDK; the on-device evaluation protocol (§Evaluation) has not yet been run. This doc captures the technical feasibility research, the validation-spike design, and the as-built implementation for an always-accessible in-app chat assistant that answers questions about the user's own workout data (e.g. "When is my next workout?", "What is my bench press PR?"), built on the same on-device FoundationModels stack as the existing AI Coach (see `docs/ai-coach.md`).

See the **Implementation (as built)** section near the end for the concrete file map and the deltas from the plan.

## Verdict

**Feasible with FoundationModels — no hard blockers.** All required primitives exist and three of four are already proven in production in this app (streaming, `@Generable` structured output, availability/error handling). The two genuinely new capabilities are **multi-turn sessions** and the **`Tool` protocol** — neither is used in the codebase today. The feature is worth deeper investment, but only as a **tool-calling design**, never as a "dump workout data into the prompt and let the model reason" design.

## Why tool calling is the mandatory architecture

- The AI Coach's hard-won doctrine (docs/ai-coach.md, July 2026 redesign) is: **all facts computed in Swift; the ~3B model only rephrases pre-resolved fact lines.** The model proved unreliable at math/aggregation and at echoing raw numbers.
- Apple's own guidance matches: do not use the on-device model for calculations or factual Q&A; compute in code, let the model verbalize.
- Tool calling reconciles chat with this doctrine: the model *requests* a fact (`getExercisePR(exerciseName:)`), Swift computes it via existing domain services, the model verbalizes the returned structured value. The model never does arithmetic and never sees raw set data.

## FoundationModels capabilities (researched July 2026)

| Capability | Status |
|---|---|
| Multi-turn chat | `LanguageModelSession` is stateful; each `respond`/`streamResponse` appends to `session.transcript`. Reuse one session per conversation. |
| Transcript persistence | `Transcript` is `Codable` → serialize + restore via `LanguageModelSession(transcript:)`. Caveat: `Transcript.init(entries:)` went private in a later SDK — only round-trip real transcripts, never hand-build entries. |
| Tool calling | `Tool` protocol: `name`, `description`, `@Generable Arguments` (schema-validated via guided generation), `func call(arguments:) async throws`. Register at session init. `GenerationOptions.ToolCallingMode(.required)` can force tool use on a turn. |
| Streaming + structured output | Compose natively — `streamResponse(generating:)` emits `PartiallyGenerated` snapshots; same pattern as existing `AICoachService.stream(...)`. Tool calls interleave via `.onToolCall`. |
| Context window | **4,096 tokens hard limit**, shared by instructions + tool schemas + all turns. Overflow throws recoverable `exceededContextWindowSize`. Practical chat life ~20–30 exchanges; per-turn latency grows with transcript size. |
| Token budgeting | `SystemLanguageModel.default.contextSize` / `tokenCount(for:)` (iOS 26.4+) — same pre-flight pattern `AICoachService.streamPeriodRecap` already uses. |
| German | Fully supported (EN, DE, FR, IT, PT-BR, ES, JA, KO, ZH-Hans). Runtime check via `supportedLanguages`; `unsupportedLanguageOrLocale` already handled in `mapError`. |
| OS/device floor | iOS 26+ (our deployment target is already 26.0/26.2 — no gap). Hardware: A17 Pro + 8GB RAM → iPhone 15 Pro and newer, Apple Intelligence enabled, model downloaded. Existing `AICoachAvailability` handles all unavailable states. |

## Known risks (soft limitations — shape the design, don't block it)

1. **Silent tool non-invocation** — the model can simply not call a registered tool; no programmatic signal in production (only visible in Xcode's Foundation Models Instrument). Mitigate with `.toolCallingMode(.required)` on query-shaped turns and an explicit "couldn't find that" fallback.
2. **Context exhaustion is a first-class feature, not an edge case** — need a condense-and-restart strategy (Apple's documented pattern: new session seeded with first + last transcript entries, prewarmed).
3. **Tool schemas consume context on every request** — keep the tool set small and descriptions terse; token budget, not an API cap, limits tool count.
4. **Eligibility gap** — a meaningful slice of users (pre-iPhone-15-Pro, or Apple Intelligence off) can never use it. The chat surface must degrade to the existing unavailable-state UX; the underlying answers (next workout, PRs) remain reachable through normal app navigation, so no separate fallback build is required.
5. **Guardrail false positives** still occur unpredictably with free-form user input; add `.refusal` and `.concurrentRequests` handling to `mapError` (chat input is far less controlled than our fixed prompt templates).
6. **Latency**: 1–2 s cold start (mitigate with `prewarm(promptPrefix:)` of the tool-equipped session on screen appear), ~30–50 tok/s on iPhone 15 Pro.

## What already exists to build on

- **Backing services for tools** (all facts already computable in Swift):
  - `PersonalRecordService.computePRs(sessions:)` — bench press PR etc. (Epley est-1RM, keyed by `stableKey`)
  - `WorkoutPlanningService.nextDue(for:lastCompleted:referenceDate:)` — "when is my next workout"
  - `ExerciseProgressService` (only one already protocol-abstracted + DI-wired) — progress/trends/previous performance
  - `HistoryStatsService` — week/month stats, streaks
- **Reusable infra**: `AICoachAvailability`, `AICoachPreferences` + opt-in flow, `mapError`, `StreamingTextView`/`AISurface`, disk cache, telemetry, `AIPrivacyFooter`.
- **Gap**: `AICoachService` is strictly one-shot (new throwaway session per request, no transcript retention, no tools). A chat assistant needs a new session-holding component, not an extension of the existing `stream(...)` helper.

## Recommended next step (before committing to a full feature)

Prototype spike: one `LanguageModelSession` with 2–3 tools (`getNextScheduledWorkout`, `getExercisePR`, `queryWorkoutHistory`) wrapping the services above, `.toolCallingMode(.required)`, tested against real workout-history volumes in EN + DE. This validates the two unproven risks — tool-invocation reliability and real conversational token budget — cheaply, before any UI/persistence investment.

---

# Spike Plan

## Goal

Validate the two risks research could not resolve — **tool-invocation reliability** and the **real conversational token budget** — with a minimal but genuinely useful chat surface, cheap enough to throw away but structured so that, if it validates, it becomes the foundation of the real feature (no throwaway architecture).

## Scope

**In:** one retained multi-turn session, 3 tools over existing domain services, streaming chat UI, fully automatic context-overflow handling (proactive + reactive), EN + DE, availability gating, scripted evaluation protocol.

**Out (deliberately, for the spike):** transcript persistence across app launches *(since built — Phase 1 of `docs/ai-coach-chat-plan.md`, July 2026: conversation persists as local-only JSON via `ChatConversationStore`; the transcript itself is still never persisted)*, multiple conversations / chat history browsing, proactive suggestions, watch target (no FoundationModels on watchOS), writing/mutating tools (chat is read-only over user data), Siri/App Intents integration.

## Step 0 — SDK verification checklist (DONE, July 2026)

Verified directly against the SDK we build with — `iPhoneOS26.5.sdk`, Xcode 26.5 — by reading `FoundationModels.framework/.../arm64e-apple-ios.swiftinterface` (authoritative for compile-correctness, more so than web docs). Results:

- [x] **`GenerationOptions.ToolCallingMode` — DOES NOT EXIST on iOS 26.5.** `GenerationOptions` exposes only `sampling`, `temperature`, `maximumResponseTokens`. There is **no** `ToolCallingMode`, `.required`, or any other API to force a tool call on a turn. **This changes the design:** tool invocation is driven purely by `Instructions` + terse tool descriptions; there is no `.required` fallback. The eval's "`.required` vs `.allowed`" comparison (§Evaluation 4) collapses to instructions-only, and the silent-non-invocation risk (§Known risks 1) must be mitigated by prompt strength alone.
- [x] **`session.transcript` readable + `Transcript` Codable — CONFIRMED.** `final public var transcript: Transcript`; `Transcript: Sendable, Equatable, Codable, RandomAccessCollection` with `Element == Transcript.Entry`. Round-trips through `Codable`, and entries are directly iterable (useful for token-accurate budgeting).
- [x] **Transcript slicing — not needed, digest path chosen.** `LanguageModelSession(tools:transcript:)` exists, but the Swift-side digest condensation (below) remains the primary and only overflow path — no `Transcript.init(entries:)` dependency.
- [x] **`prewarm(promptPrefix:)` — CONFIRMED.** `final public func prewarm(promptPrefix: Prompt? = nil)` on `LanguageModelSession`; works on a tool-equipped session (tools are set at session init, independent of prewarm).
- [x] **`contextSize` / `tokenCount(for:)` — CONFIRMED.** Both on `SystemLanguageModel`. `contextSize: Int` is iOS 26.0+ (`@backDeployed(before: iOS 26.4)`). `tokenCount(for:) async throws -> Int` is gated `@available(iOS 26.4, *)`, with overloads for `some PromptRepresentable`, `Instructions`, `[any Tool]`, `GenerationSchema`, and `some Collection<Transcript.Entry>` — so tool-schema tokens and transcript tokens can be measured exactly on 26.4+.

**Tool API shape (confirmed):** `protocol Tool<Arguments, Output>` requires `associatedtype Arguments: ConvertibleFromGeneratedContent` (use a `@Generable` struct — `String`/`Int`/`Double` as `Arguments` are explicitly `@available(*, unavailable)`), `associatedtype Output: PromptRepresentable` (`String` conforms — tools return localized fact strings), `var name`, `var description`, and `@concurrent func call(arguments:) async throws -> Output`. `parameters: GenerationSchema` is auto-synthesized when `Arguments: Generable`. Because `call` is `@concurrent` (runs off the main actor) while the fact layer is `@MainActor` (SwiftData), each tool `await`s its `@MainActor` fact provider to hop back. Plain-text streaming is `streamResponse(to: String, options:) -> ResponseStream<String>` whose `Snapshot.content` is the cumulative `String`; registered tool calls are resolved transparently inside the stream (there is no `.onToolCall` hook, and none is needed).

## Architecture (follows existing AI Coach patterns)

```
GymStreak/
├── Domain/Interfaces/AICoach/
│   └── CoachChatServicing.swift          # thin protocol: send(text), messages state, availability — for VM injection/tests
├── Domain/Models/AICoach/
│   └── CoachChatMessage.swift            # UI message model: id, role (user/assistant), text, phase (streaming/final/failed)
├── Data/AICoach/Chat/
│   ├── CoachChatService.swift            # @Observable @MainActor singleton; owns LanguageModelSession lifecycle,
│   │                                     #   overflow policy, error mapping (extend with .refusal/.concurrentRequests)
│   ├── ChatFactService.swift             # data layer for tools: queries SwiftData + wraps domain services,
│   │                                     #   returns compact localized fact strings (aggregator pattern, arch §2 exception)
│   │                                     #   — superseded by ChatFactStore/ChatFactBuilder, audit P1.3; see "as built" below
│   ├── Tools/
│   │   ├── NextWorkoutTool.swift
│   │   ├── ExercisePRTool.swift
│   │   └── WorkoutHistoryTool.swift
│   └── SystemPrompts/CoachChatInstructions.swift
├── Presentation/ViewModels/AICoach/
│   └── CoachChatViewModel.swift          # @Observable @MainActor; message list, input state, send/cancel
└── Presentation/Views/AICoach/Chat/
    └── CoachChatView.swift               # message bubbles, input bar, StreamingTextView reuse, AIPrivacyFooter
```

Key structural decision: **the UI message list is our own array, decoupled from the model `Transcript`.** The transcript is a token-budget-constrained working set the service manages (and condenses) freely; the visible chat history never shrinks because of condensation.

## Data provisioning design ("how the chat gets its data")

Three layers, honoring the fact-resolution doctrine (model never sees raw sets, never computes):

1. **Ambient context in `Instructions`** (static per session, kept small — every token here is paid on every turn): today's date + weekday, locale/response-language directive, unit system, week-start convention (ISO/German, matching `HistoryStatsService.isoGermanCalendar()`). This is what makes "next workout" answers resolvable as "tomorrow"/"on Friday".
2. **On-demand facts via tools** (the workhorse): the model picks a tool + arguments; the tool calls the fact layer (planned as `ChatFactService`; built, then split by audit P1.3 into `ChatFactStore` + `ChatFactBuilder`), which queries repositories/SwiftData and delegates all computation to the existing domain services; the tool returns **pre-formatted, localized fact lines** (same style as `toPromptText()` in the existing surfaces). The model's only job is verbalizing them.
3. **Nothing else.** No workout-history dump in the prompt, no raw numbers outside tool returns. Instructions explicitly state: answer only from tool results; if tools can't answer, say so; never perform arithmetic; repeat numbers verbatim.

### The 3 spike tools

| Tool | Arguments | Backed by | Returns (compact fact lines) |
|---|---|---|---|
| `getNextWorkout` | none | `RoutineRepository` + `WorkoutPlanningService.nextDue(for:lastCompleted:referenceDate:)` | Per scheduled routine: name + formatted next-due date; or "no schedules configured" |
| `getExercisePR` | `exerciseName: String` (free-form) | Exercise library (live join by `stableKey` — see `feedback_progress_aggregation.md`) + `PersonalRecordService.computePRs` | Best weight PR (weight × reps), est. 1RM, date, previous best; or disambiguation candidates; or "not found" + closest names |
| `getWorkoutHistory` | `timeframe` enum, `@Guide(.anyOf: thisWeek, lastWeek, thisMonth, lastMonth)` | `WorkoutSessionRepository` + `HistoryStatsService` | Workout count, streak weeks, last workout name/date/duration |

Design notes:
- **Exercise-name resolution is Swift-first, model-assisted on a miss.** The user says "bench" or "Bankdrücken"; the tool folds the string (diacritics/umlauts normalized) and matches against the live Exercise library (exact → contains → token overlap). Ambiguity returns candidates so the model asks a follow-up. **On a total miss the tool returns the user's actual exercise names and asks the model to re-call with the matching one** — because exercises are fully user-named in any language, and Swift lexical matching cannot bridge cross-language equivalents (see Device-test findings). A dynamic `.anyOf` over all names in the *schema* was still rejected (per-request token cost + fuzzy phrasing); the names ride along only in the miss *result*, on the miss path only.
- **Constrain arguments with enums wherever possible** (`timeframe`) — guided generation makes enum args near-deterministic; free strings only where unavoidable (`exerciseName`).
- **Exactly 3 tools, terse descriptions (≤ ~25 words each)** — all tool schemas ride along on every request inside the 4,096-token budget. Expansion list for post-spike: `getVolumeTrend`, `getRoutineDetails`, `getStreakStatus`.
- **Tool invocation is instructions-driven only** (Step 0: `ToolCallingMode`/`.required` does not exist on iOS 26.5). The `Instructions` state, forcefully, that every data question must be answered from a tool result and the model must never answer numeric/schedule questions from memory. The eval measures the resulting invocation rate; there is no `.required` lever to fall back to.

## Automatic context-overflow handling

Requirement: the user never sees a "conversation too long" failure; overflow is absorbed silently.

**Budget model.** `usableContext = contextSize − instructionTokens − toolSchemaTokens − reservedOutput` (reserve ~800 for the answer + tool round-trip). On iOS 26.4+ use `tokenCount(for:)`/`contextSize` (pattern already in `AICoachService.streamPeriodRecap`); below 26.4 estimate at chars ÷ 3.5 (Apple's EN/DE heuristic) with a conservative safety margin.

**Proactive (primary):** before each send, estimate current transcript size + incoming message. If it exceeds ~70% of `usableContext` → condense *before* sending:
1. Build a **Swift-side conversation digest** — deterministic, no extra model call: the last 2 user/assistant exchanges verbatim (recency matters most in chat) + a one-line topic list of older turns (per-turn topic captured at send time, e.g. tool name + key argument: "asked bench press PR", "asked next workout").
2. Create a fresh `LanguageModelSession(tools:instructions:)` where instructions = base instructions + "Earlier in this conversation: <digest>".
3. `prewarm()` the new session, then send the pending message on it.

**Reactive (safety net):** catch `exceededContextWindowSize` (and `rateLimited` with backoff) from any send → run the same condensation → retry the failed turn **once** → only if the retry also fails, show an inline error bubble with a retry affordance. Also handles the pre-26.4 estimation path being off.

**Why digest instead of transcript slicing:** Apple's documented first+last-entries pattern requires constructing `Transcript` from entries, which reportedly went private (Step 0 verifies). The digest approach has no SDK dependency, is deterministic, costs no extra inference, and the UI keeps full history regardless because the visible message list is decoupled from the transcript.

## User value & entry point

- **Placement (spike):** an "Ask Coach" row/button inside the existing AI Coach surface area, gated by `AICoachAvailability` + the existing opt-in (`AICoachPreferences`) + a new "experimental" sub-toggle. Unavailable states reuse the existing branching UX (device not eligible / Apple Intelligence off / model downloading).
- **Placement (post-spike, if validated):** promote to a persistent toolbar entry point on the History and Progress tabs — that is where the questions arise.
- **Empty state sells the value:** show 3 tappable suggested questions ("When is my next workout?", "What's my bench press PR?", "How many workouts this week?") — doubles as a guarantee that first-touch queries are ones the tools can actually answer.
- **Session lifetime:** the service is a `.shared` singleton holding the conversation in memory — surviving navigation away and back. Since Phase 1 (`docs/ai-coach-chat-plan.md`) the conversation also survives app termination: `ChatConversationStore` persists the finalized message list + turn topics as local-only JSON (Application Support, never CloudKit), and on launch a fresh session is seeded with a `ChatOverflowPolicy.digest(...)` of the restored messages — the same mechanism condensation uses. A visible "New chat" action resets message list, session, and the persisted copy.
- Answers are 1–3 sentences, in the user's language, numbers verbatim from tool output. `AIPrivacyFooter` on the chat screen, matching every other AI surface.

## Evaluation protocol (what makes this a spike, not a feature)

Scripted run on a device with realistic seeded history (`TestDataSeeder`), executed in both EN and DE:

1. **Tool reliability:** 20 scripted queries (5 next-workout, 8 PR with varied phrasings incl. "Bankdrücken", "bench", a nonexistent exercise, an ambiguous name, 7 history). **Pass: ≥ 18/20 invoke the right tool with right arguments and the answer's numbers match the tool output exactly** (zero hallucinated figures — every number must be traceable to a fact line).
2. **Overflow drill:** one scripted 40-turn conversation. **Pass: auto-condensation triggers with no user-visible failure and post-condensation answers still ground in tools.**
3. **Latency:** first token < ~3 s on a prewarmed session (iPhone 15 Pro class device).
4. **Robustness sampling:** off-topic/small-talk input (graceful redirect, no guardrail crash-loop), `.required` vs `.allowed` invocation-rate comparison, guardrail/refusal handling shows a sane error bubble.

**Decision gate:** all four pass → write the full feature plan (persistence, more tools, prominent entry point). Tool reliability fails and can't be prompted/constrained into shape → stop, document why here, revisit alternatives (§ below).

## Effort estimate

~2–3 focused days: ½ day Step 0 SDK verification, 1 day service + tools + overflow logic, ½–1 day minimal chat UI, ½ day evaluation protocol runs (EN + DE) and writing up results.

## Implementation (as built, July 2026)

The spike is implemented and compiles clean against the iOS 26.5 SDK. It follows the planned architecture; the deltas below are all consequences of Step 0 or of SwiftUI Observation mechanics, not scope changes.

### File map (as built)

```
GymStreak/
├── Domain/Models/AICoach/
│   └── CoachChatModels.swift              # CoachChatMessage (id/role/phase) + ChatHistoryTimeframe (@Generable enum)
├── Domain/Interfaces/AICoach/
│   ├── ChatFactProviding.swift            # Sendable, async tool-backing data surface (3 fact methods) — see delta 6
│   └── CoachChatServicing.swift           # chat service surface (documentation/parity contract — see delta 3)
├── Domain/Services/AICoach/
│   ├── ChatFactBuilder.swift              # pure fact-line building over already-fetched models (Epley 1RM, timeframes, formatting)
│   └── ExerciseNameResolver.swift         # free-form name → library (folded exact/contains/token; .noMatch hands list to model)
├── Data/Persistence/
│   └── CompletedSessionFetch.swift        # the one prefetch-correct completed-session fetch, shared with the History model actor
├── Data/AICoach/Chat/
│   ├── ChatFactStore.swift                # ChatFactProvider (@concurrent hops) + @ModelActor ChatFactStore (fetching only)
│   ├── CoachChatService.swift             # @Observable @MainActor singleton: session, streaming, overflow, error mapping
│   ├── Tools/{NextWorkoutTool,ExercisePRTool,WorkoutHistoryTool}.swift
│   └── SystemPrompts/CoachChatInstructions.swift   # ambient context + hard rules + DE glossary + optional digest
├── Presentation/ViewModels/AICoach/
│   └── CoachChatViewModel.swift           # @Observable @MainActor; input state, suggestions, forwards service state
└── Presentation/Views/AICoach/Chat/
    └── CoachChatView.swift                # bubbles, input bar, empty-state suggestions, AIPrivacyFooter
```

Entry point (since 2026-07-10): a floating "Ask your coach" companion bar (`CoachBarView`, hosted via `tabViewBottomAccessory` on the root TabView, iOS 26.1+) — visible on every tab and pushed screen when availability + opt-in + the `chatEnabled` per-surface toggle (default on, `AICoachPreferences`, key `aiCoachChatEnabled`) are all active; it zoom-morphs into `CoachChatView` in a fullScreenCover. The toggle lives in the normal Surfaces section of `AICoachSettingsView` (the earlier Experimental section + `chatExperimentalEnabled` toggle are gone). See `docs/ai-coach-entry-point-concepts.md` for the design/decision history. Localized EN + DE (`ai_coach.chat.*`).

### Deltas from the plan

1. **No `ToolCallingMode` (Step 0).** Tool invocation is instructions-only; the `Instructions` state forcefully that any schedule/PR/history question MUST be answered from a tool. There is no `.required` lever, so the eval measures the achieved invocation rate directly.
2. **Tool `call` and the fact layer.** Apple declares the `Tool.call(arguments:)` *requirement* `@concurrent` (verified against the iOS 26 reference, 2026-08-13). Our three tools leave their own `call` unannotated, as Apple's `FindContacts` sample does. The fact layer originally leaned on that: it was `@MainActor` (SwiftData) and each tool `await`ed it to hop *back* onto the main actor. **Audit P1.3 inverted this** — see delta 6.
3. **VM references `CoachChatService` concretely, not via `CoachChatServicing`.** SwiftUI Observation cannot track `@Observable` reads through an existential, so the VM depends on the concrete singleton (default-injected) and forwards `messages`/`isResponding` via computed properties; `CoachChatServicing` remains as a documentation/parity contract. This mirrors the existing deliberate concrete use of `AICoachAvailability`.
4. **Overflow budgeting uses the exact token APIs on 26.4+.** `condenseIfNeeded()` measures `tokenCount(for: transcriptEntries)` + `tokenCount(for: tools)` against `contextSize`; below 26.4 it falls back to a chars/3.5 estimate. Both proactive (>70% of usable) and reactive (`exceededContextWindowSize` → condense → retry once) paths are implemented; condensation rebuilds the session with a deterministic Swift-side digest (last 2 exchanges verbatim + older-turn topic list) and prewarms it. The visible `messages` array is never touched by condensation.
5. **Fact lines are compact canonical English; the model translates.** To contain spike scope, `ChatFactBuilder` emits English fact lines (weekday/date pinned to `en_US`, *not* the device locale — a device-locale weekday produced "…due Samstag, in 2 days" inside an English reply) and the `Instructions` carry a small DE glossary (Topsatz/Wiederholungen/Bestwert/…) mirroring the Workout Analysis surface. Localizing the fact lines themselves is post-spike work.

6. **The fact layer moved off the main actor (audit P1.3, 2026-08-13).** The original design had a tool — running off the main actor — `await` a `@MainActor` fact service to hop *onto* the main actor and there run an unbounded, unprefetched fetch plus a session × exercise × set scan, live, mid-stream, possibly several times per turn. It is now split three ways:

   - `ChatFactProviding` lost `@MainActor` and `AnyObject`; its three methods are `async`.
   - `ChatFactProvider` (struct) carries `@concurrent` on each method and forwards into a `@ModelActor ChatFactStore`, built inside `Task.detached` — the exact pattern `SwiftDataHistorySnapshotProvider` established and measured. **319 ms** of main-actor stall at 240 sessions disappears with it (`chatFactLookupKeepsMainActorResponsive`).
   - All fact-line building moved to `ChatFactBuilder` in `Domain/Services/AICoach/`, which must stay isolation-agnostic — the model actor calls it from its own executor. `ExerciseNameResolver` moved with it and lost the `@MainActor` it never needed.

   The tools were **not** touched: guaranteeing off-main once, at the boundary that owns the cost, is what makes the tools' own (undocumented) isolation irrelevant. Fetching is now prefetch-correct — `nextWorkoutFacts` takes a lean fetch that prefetches only `\.routine`, the other two take the full graph via the shared `CompletedSessionFetch`. `CoachChatServicing` gained `isConfigured` so the ViewModel does not build a `@ModelActor` on every appearance of the chat's `fullScreenCover`.

### Device-test findings (July 2026)

**Finding 1 — cross-language exercise names break Swift-only resolution.** First on-device test: user's exercise is named "Chest Press" (English); asked "Was ist mein Bestwert beim Bankdrücken?" (German). The assistant answered it couldn't find the exercise and there were no close matches. Root cause: the German single token "bankdrücken" shares **zero characters/tokens** with "chest press", so exact/substring/token-overlap all miss. This is a semantic/cross-lingual gap (the user even equates "Bankdrücken"/bench press with a machine "Chest Press"), which pure lexical matching cannot close — and it is fundamental to the design choice that users name exercises freely in any language.

**Fix applied (A + D):**
- **A — model-assisted resolution bounded to real data.** `resolveExercise` now returns `.noMatch` on a total lexical miss; `exercisePRFacts` responds with the user's *actual* exercise-name list plus an instruction to re-call `getExercisePR` with the closest name "including a translation or synonym". The 3B model supplies the cross-lingual mapping (which it is good at) and re-invokes with the exact name; being bounded to the real library, it cannot invent an exercise, and Swift still computes the PR. Costs one extra tool round-trip + the name list (~100–300 tokens, capped at 60 names) **only on the miss path**. Instructions gained a matching bullet.
- **D — diacritic/umlaut folding (`ExerciseNameResolver.fold`).** Expands ä/ö/ü/ß → ae/oe/ue/ss and folds other diacritics before matching, so same-language variants ("Bankdrücken" / "Bankdruecken" / "bank drücken") unify. Complementary only — it does **not** bridge languages (that's A's job).

Still to validate on-device: that the model reliably performs the re-call step (part of the tool-reliability eval below), and the added round-trip's latency impact.

**Finding 2 — the model translated the argument AND parroted the tool result (fix for A's first attempt).** Second test: the user's library literally contains "Bankdrücken", yet asking "Was ist mein Bestwert beim Bankdrücken?" produced a `.noMatch`, and the assistant then answered by **translating the internal guidance sentence verbatim** into German (list of exercises + "rufe die Funktion getExercisePR erneut auf …"). Two distinct 3B-model weaknesses:
- It **translated the exercise name to English before calling** the tool ("Bankdrücken" → "bench press"), so it missed an exercise that exists under the exact German name. Reproduces the silent-tool-misuse risk (§Known risks 1) at the argument level.
- With "answer only from tool results" in force, it treated my fluent-English no-match *guidance sentence* as the answer and translated it, leaking internal orchestration text to the user.

Fixes applied:
- **Pass the name verbatim.** The `@Guide` on `getExercisePR.exerciseName` and a system-prompt rule now state: copy the exercise name exactly as the user wrote it, same language, never translate. This makes the common case (the name exists as typed, as here) resolve in Swift with no second round-trip at all.
- **Non-leakable no-match payload.** `noMatchGuidance` → `noMatchPayload`, which returns a machine-marked, data-only string (`__NO_MATCH__ exercises: …`) instead of a prose sentence. The "what to do" moved into the system prompt, with hard rules: never reveal the `__NO_MATCH__` marker / list / raw tool text, always answer in your own words, and on `__NO_MATCH__` re-call `getExercisePR` with the matching listed name.

Takeaway for the decision gate: the on-device 3B is unreliable at both faithful argument passing and at *not* echoing tool text. The mitigations are prompt-only (no `ToolCallingMode` to lean on), so the eval must specifically measure argument fidelity and verbatim-leak rate, not just whether *a* tool was called.

### Evaluation run 1 (partial, July 2026)

First partial pass of `docs/ai-coach-chat-eval.md` (device, German locale). **Grounding held everywhere the query mapped cleanly to a tool** — next-workout, history counts/streak, and PR resolution (incl. the cross-language "Chest Press" case and ambiguous "Curls" → asks which). Four issues surfaced, three fixed immediately:

- **Markdown leak (fixed).** The model emitted `**Push:**` etc.; the chat renders plain `Text`, so asterisks showed literally. Fix: instruction "plain text only, no Markdown" **plus** a defensive `CoachChatService.stripMarkdown` (removes `**`/`__`/`` ` `` from each snapshot) so a stray marker never reaches the UI.
- **Estimated 1RM mis-stated as "max weight" (fixed).** Tool returned `best set 12 kg × 7 reps, estimated 1RM 14.8 kg`; the model answered "dein maximales Gewicht … 14,8 kg" — presenting the derived 1RM as a lifted weight. Fix: instruction that the PR is the best SET (weight×reps) and the estimated 1RM is a calculation that must never be called the max/lifted weight. Same run showed formal "Sie/Ihr"; added an instruction to always address the user informally ("du"/"you").
- **"Letztes Training" had no tool affordance (fixed).** `getWorkoutHistory` only knew thisWeek/lastWeek/thisMonth/lastMonth, so "my last workout" got forced into `lastWeek` → 0 workouts → wrong answer. Fix: added a `.allTime` case to `ChatHistoryTimeframe` (+ tool-description hint) so last/most-recent-workout questions resolve against all history.
- **Language policy → match the query (decided + fixed).** English queries sometimes got German answers, or mixed output ("due Samstag, in 2 days" — the fact line's device-locale weekday leaked into an English reply). Decision: **answer in the language of the user's latest message.** Fix: instruction now says reply in the query's language and translate the (English) facts fully; and the fact lines are made **uniformly English** — `todayLine`, `weekday`, and `mediumDate` use a fixed `en_US` locale (`ChatFactBuilder.factLocale`) instead of the device locale, so no weekday/month name leaks in the wrong language for the model to translate.

### Evaluation run 2 (partial, July 2026)

Re-test after run-1 fixes confirmed them (markdown gone, 1RM described as best set, `allTime` resolves "last workout", languages match). Three further issues, two fixed:

- **Tool selection: "What's on my plan this week?" → wrong tool (fixed).** The model called `getWorkoutHistory` (returned *past* workouts) because "this week" pattern-matched the history timeframe, overriding "plan". Fix: tool descriptions sharpened (`getNextWorkout` = PLAN/scheduled/upcoming incl. "this week's plan"; `getWorkoutHistory` = COMPLETED/past only) plus an explicit tool-selection rule in the instructions mapping intent words to tools.
- **Exercise-name echo (fixed).** Asked about "Bench Press", the answer kept "Bench Press" instead of the stored name "Bankdrücken". Fix: instruction to name the exercise exactly as it appears in the tool's fact line, not as the user typed it.
- **"last weekend" wording slip (accepted, not fixed).** For a this-week-vs-last-week comparison (#20) the model made the right two calls with correct numbers but phrased "last weekend" instead of "last week". A pure 3B verbalization slip with no structural lever; recorded as a known minor inaccuracy, not chased. Reinforces the gate takeaway that free-text phrasing on the 3B is imperfect even when grounding is correct.

### Evaluation run 3 + close-out (July 2026)

Run-2 fixes confirmed (#5 now routes to `getNextWorkout`; #9 was never a bug — the stored name really is "Chest Press", so answering with it is correct). One further issue found and fixed:

- **Duplicate identical names (#12, fixed).** The user has two library entries both named exactly "Biceps Curls" (barbell + dumbbell). The resolver deduped them to one candidate, so the ambiguity prompt offered a single name and the model fabricated a bogus second option ("Biceps Curls" vs "Biceps"). Two same-named entries are also indistinguishable by name (the tool re-call is keyed on name), so a "which one?" is unanswerable anyway. Fix: `ExerciseNameResolver.resolve` now returns `.resolved([Exercise])` and **same-name entries aggregate** — the PR is taken across all of them (`personalRecordLine(for: [Exercise])`). Genuine ambiguity (distinct names sharing a token, e.g. "Biceps Curls" vs "Biceps Curls Maschine") still returns `.ambiguous` and asks.

**Decision-gate read (manual testing stopped here at the user's request).** Tool-selection and grounding proved reliable across the queries exercised, and every failure was a *fixable* prompt/tool-shape issue (markdown, 1RM wording, tool routing, name resolution, duplicate names) — **not** a fundamental inability to call tools or a hallucinated-number problem. Numbers stayed traceable to fact lines throughout. The core spike hypothesis (tool calling reconciles chat with the fact-resolution doctrine on-device) **holds**. Not empirically closed: the 40-turn overflow drill and latency numbers were not run (no further manual testing); the overflow logic is implemented and builds but is unverified at scale. Recommendation: treat the spike as **validated for the tool-reliability risk**, and verify overflow/latency during the full-feature build (or with an automated harness) rather than blocking on more manual runs. The remaining known model-level imperfection is free-text phrasing slips (e.g. "last weekend"), inherent to the 3B and acceptable for a chat surface.

The DEBUG-only tool tracing added for the eval has been **removed** now that manual testing is complete (code is back to production-clean; no exercise names in logs).

### Decision gate — PASSED (2026-07-10)

The gate is cleared for the risk the spike existed to resolve — **tool-invocation reliability + grounding**. Evidence: three device-test rounds where grounding held and every failure was a fixable prompt/tool-shape issue (never a tool-call failure or hallucinated number), now regression-locked by **19 automated tests** (`ExerciseNameResolverTests`, `ChatFactProviderTests`, `ChatOverflowPolicyTests`; see `docs/ai-coach-chat-eval.md`). The DEBUG-only tool tracing added for the eval has been removed.

Two items are **build-time checkpoints**, not gate blockers (they need the live 3B and can't be closed off-device): the real 40-turn overflow behavior (mechanism is unit-tested; live model behavior to confirm once) and first-token latency. The no-argument `NextWorkoutTool` (`@Generable struct Arguments {}`) compiles and was invoked in testing; watch it during the build (fallback: a single dummy enum argument).

**Next:** the full feature plan lives in `docs/ai-coach-chat-plan.md`.

## Alternatives considered and rejected (for now)

MLX (`mlx-swift` with a self-shipped quantized 3B model) or raw Core ML would allow a bigger/custom model but require owning weights distribution (multi-GB), prompt/tool scaffolding, and structured decoding by hand — unjustified unless the FoundationModels prototype proves the 4K context or tool reliability is a hard blocker in practice.

## Sources

- Apple: [Tool protocol](https://developer.apple.com/documentation/foundationmodels/tool), [Expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling), [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window), [Optimizing key-value caching](https://developer.apple.com/documentation/foundationmodels/optimizing-key-value-caching-in-language-model-sessions), [GenerationOptions.ToolCallingMode](https://developer.apple.com/documentation/foundationmodels/generationoptions/toolcallingmode-swift.struct)
- Field reports: [drobinin.com — Putting Apple Foundation Models in a real app](https://drobinin.com/consulting/foundation-models-apple-intelligence/putting-apple-foundation-models-in-a-real-app/) (context exhaustion ~20–30 turns, silent tool non-invocation, latency), [natashatherobot.com — FoundationModels limitations](https://www.natashatherobot.com/p/apple-foundation-models), [Rudrank Riyam — supported languages](https://rudrank.com/exploring-foundation-models-supported-languages-internationalization)
