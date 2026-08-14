# AI Coach

## Overview

AI Coach is an on-device AI feature that generates short, fact-based workout narratives from the user's own SwiftData training history. It uses Apple's Foundation Models framework (iOS 26+, Apple Intelligence required) and never sends any data off the device.

Four surfaces:
1. **Post-Workout Recap** — a 2–3 sentence recap auto-generated on the save-workout screen after finishing a workout.
2. **Period Recap** — a multi-section editorial analysis accessible from the History tab, supporting any of six time ranges (this week through this year).
3. **Exercise Deep-Dive** — a 3–4 paragraph analysis of a single exercise's progression, surfaced on the exercise progress chart screen.
4. **Workout Analysis** — a 3–5 sentence comparison of a past workout against the previous session of the same routine, surfaced in the workout detail view (Verlauf tab).

Voice and tone constraints (enforced via system prompt):
- Factual, analytical, grounded — never hyped.
- Direct second person ("you" / "du"). No emoji. No exclamation marks.
- Use **exact** numeric values from the input — no rounding, estimating, or paraphrasing. This rule appears as the first item in "Strict rules" across all three system prompt files to give it highest model weighting.
- No medical, nutritional, or prescriptive advice.

---

## iOS / Framework Requirements

- iOS 26.0+ deployment target.
- `import FoundationModels` — `SystemLanguageModel`, `LanguageModelSession`, `Instructions`, `Prompt`, `@Generable`, `GenerationError`.
- Apple Intelligence must be available (`SystemLanguageModel.default.availability == .available`).
- `tokenCount(for:)` is gated at `@available(iOS 26.4, *)` and wrapped accordingly.
- Watch app: explicitly does not use FoundationModels. All AI surfaces are iOS-only.
- Widget: out of scope.

---

## Architecture

### Data flow (per surface)

```
SwiftData (WorkoutSession / WorkoutExercise / ExerciseSet)
  ↓
Aggregator.build*(…) → *Input struct
  ↓
*Input.toPromptText() → String with embedded locale identifier
  ↓
AICoachService.streamXxx(input:) → LanguageModelSession.ResponseStream<OutputType>
  ↓
for snapshot in stream → snapshot.content → *Output.PartiallyGenerated
  ↓
ViewModel publishes partial text → StreamingTextView
  ↓
Final snapshot → full *Output → AICoachCache.save*()
```

### Four-layer pattern

| Layer | Responsibility |
|---|---|
| **Aggregators** | Query SwiftData, compute metrics, build Input structs with `toPromptText()` |
| **Output @Generable structs** | Typed response shapes; also `Codable` for cache serialisation |
| **AICoachService façade** | Creates `LanguageModelSession`, streams response, handles token budget |
| **ViewModels** | State machines per surface (4 total); integrate cache; publish to SwiftUI |

This maps onto the app's Clean Architecture layers as: Aggregators + `AICoachService`/`AICoachCache`/`AICoachPreferences` in **Data**, the `Xxx*Input`/`Xxx*Output` structs in **Domain/Models**, the `AICoachXxxing`/`AICoachPreferencesProviding` protocols in **Domain/Interfaces**, and the ViewModels in **Presentation**.

### Testability / Dependency injection

The three AI Coach singletons (`AICoachService`, `AICoachCache`, `AICoachPreferences`) are exposed to the ViewModels through protocols so the VMs are unit-testable without touching the real Foundation Models runtime, disk cache, or `UserDefaults`:

- `AICoachServicing` — the `streamXxx(...)` generation surface (`Domain/Interfaces/AICoach/AICoachServicing.swift`).
- `AICoachCaching` — the `loadXxx`/`saveXxx`/`invalidateXxx` surface (`Domain/Interfaces/AICoach/AICoachCaching.swift`).
- `AICoachPreferencesProviding` — the four `isXxxEffectivelyEnabled` flags the VMs read (`Domain/Interfaces/AICoach/AICoachPreferencesProviding.swift`).

`AICoachService`, `AICoachCache`, and `AICoachPreferences` each conform to their respective protocol. All four AI Coach ViewModels take these as constructor-injected dependencies, defaulting to the shared singletons:

```swift
init(
    service: AICoachServicing = AICoachService.shared,
    cache: AICoachCaching = AICoachCache.shared,
    preferences: AICoachPreferencesProviding = AICoachPreferences.shared
) { ... }
```

Because the defaults resolve to the production singletons, **no view call-site changed** — views still construct e.g. `ExerciseDeepDiveViewModel()` with no arguments. Tests can inject fakes conforming to the three protocols instead.

`AICoachAvailability` is intentionally **not** protocol-ized or injected — it's a thin, side-effect-free wrapper around `SystemLanguageModel.default.availability` and stays a direct `.shared` reference in the VMs (and in view files, which also still reference `AICoachPreferences.shared` / `AICoachService.shared` / `AICoachCache.shared` directly for one-off reads — e.g. opt-in checks, prewarming — outside the injected VM pipeline).

**SwiftData queries live in the Data layer only.** Each AI Coach ViewModel used to build `FetchDescriptor`s and call `modelContext.fetch(...)` directly for cache-key/quick-lookup queries that fell outside the main `buildInput(...)` aggregation path. These were moved into the corresponding aggregator so the Presentation layer never constructs a query:

| Query (formerly inline in the ViewModel) | Now lives in |
|---|---|
| Period-recap cache key's "most recent session in range" lookup | `PeriodRecapAggregator.mostRecentSessionStart(in:modelContext:)` |
| Period-recap quick headline metrics (before/without full aggregation) | `PeriodRecapAggregator.headlineMetrics(in:modelContext:)` |
| Period-recap "known subjects" (apologetic-correlation heuristic) | `PeriodRecapAggregator.knownSubjects(in:modelContext:)` |
| Exercise deep-dive cache key's "last completed set timestamp" lookup | `ExerciseDeepDiveAggregator.lastCompletedSetTimestamp(exerciseId:modelContext:)` |
| Post-workout recap's "prior session count" data-threshold gate | `PostWorkoutRecapAggregator.countPriorSessions(excludingSession:modelContext:)` |

The ViewModels still accept `ModelContext` as a pass-through parameter (views hand it in from `@Environment(\.modelContext)`) — they just no longer construct `FetchDescriptor`s or call `.fetch(...)` themselves.

### File map

```
GymStreak/
  Domain/Models/AICoach/
    AICoachOutputs.swift              — @Generable + Codable output structs (4 surfaces)
    PostWorkoutRecapInput.swift       — input struct + toPromptText()
    PeriodRecapInput.swift            — input struct + toPromptText()
    ExerciseDeepDiveInput.swift       — input struct + toPromptText()
    WorkoutAnalysisInput.swift        — input struct + toPromptText()
  Domain/Interfaces/AICoach/
    AICoachServicing.swift            — protocol for AICoachService's streamXxx surface
    AICoachCaching.swift              — protocol for AICoachCache's loadXxx/saveXxx/invalidateXxx surface
    AICoachPreferencesProviding.swift — protocol for the 4 isXxxEffectivelyEnabled flags
  Data/AICoach/
    AICoachAvailability.swift         — SystemLanguageModel availability mapping
    AICoachPreferences.swift          — UserDefaults-backed preferences (@Observable), conforms to AICoachPreferencesProviding
    AICoachService.swift              — central façade, streamPostWorkoutRecap / streamPeriodRecap / streamExerciseDeepDive / streamWorkoutAnalysis, conforms to AICoachServicing
    AICoachCache.swift                — disk-backed JSON cache (Application Support/AICoachCache/), conforms to AICoachCaching
    AICoachTelemetry.swift            — os.Logger wrapper (no prompt or narrative text logged)
    PostWorkoutRecapAggregator.swift  — builds PostWorkoutRecapInput from a WorkoutSession; also owns the prior-session-count query
    PeriodRecapAggregator.swift       — builds PeriodRecapInput from a date range; also owns the cache-key/headline/known-subjects lookup queries
    ExerciseDeepDiveAggregator.swift  — builds ExerciseDeepDiveInput from historical sets; also owns the cache-key timestamp lookup query
    WorkoutAnalysisAggregator.swift   — builds WorkoutAnalysisInput from a workout vs. previous same-routine
    ProactivePromptCoordinator.swift  — decides when to show the proactive period recap card
    SystemPrompts/
      PostWorkoutRecapInstructions.swift
      PeriodRecapInstructions.swift
      ExerciseDeepDiveInstructions.swift
      WorkoutAnalysisInstructions.swift
  Presentation/ViewModels/AICoach/
    PostWorkoutRecapViewModel.swift
    PeriodRecapViewModel.swift
    ExerciseDeepDiveViewModel.swift
    WorkoutAnalysisViewModel.swift
  Presentation/Views/AICoach/
    Components/
      AISurface.swift                 — gradient-bordered card chrome for all surfaces
      AIPrivacyFooter.swift           — on-device lock-icon footer (inline / full variants)
      AISparkleView.swift             — animated sparkle icon
      AISkeletonBar.swift             — shimmer skeleton for loading states
      StreamingTextView.swift         — renders partial text safely for VoiceOver
      FallbackHintLine.swift          — dashed-border fallback for unavailable/error states
    PostWorkout/
      AIRecapInline.swift             — embedded in SaveWorkoutView
    PeriodRecap/
      PeriodRecapView.swift           — full-screen period recap
      CoachEntryCard.swift            — compact tap-to-open card in TrainingsTabView
      ProactivePeriodPromptCard.swift — proactive monthly prompt card
    ExerciseDeepDive/
      CoachDeepDiveButton.swift       — "Ask the Coach" button entry point
      CoachDeepDiveSurface.swift      — expanded surface in ExerciseProgressChartView
    WorkoutAnalysis/
      CoachWorkoutAnalysisButton.swift  — "Ask the Coach" button in WorkoutDetailView
      CoachWorkoutAnalysisSurface.swift — expanded surface in WorkoutDetailView
    Settings/
      AICoachOptInView.swift          — first-run opt-in fullscreen cover
      AICoachSettingsView.swift       — settings screen pushed from the Settings tab / chat toolbar
```

---

## Three Use Cases

### 1. Post-Workout Recap

- **Trigger**: `SaveWorkoutView.onAppear` calls `PostWorkoutRecapViewModel.start(session:modelContext:)`.
- **Surface**: `AIRecapInline` embedded as a `Section` inside the save-workout `Form`. Renders `AISurface` (streaming/success) or `FallbackHintLine` (unavailable/error).
- **Cache key**: `workoutId.uuidString`.
- **Regenerate flow**: Clockwise-arrow in `AISurface` header calls `onRegenerate`, which invalidates cache and re-streams.
- **System prompt file**: `PostWorkoutRecapInstructions.swift`.
- **Output struct**: `PostWorkoutRecapOutput` — single `narrative: String` field.

### 2. Period Recap

- **Entry points**:
  - `CoachEntryCard` — compact gradient-bordered card shown above `WeekHeroView` in `TrainingsTabView`. Pushes `PeriodRecapView` via `NavigationLink(value: PeriodRecapDestination)`.
  - `ProactivePeriodPromptCard` — shown once per month boundary (first app open after month rollover) by `ProactivePromptCoordinator.shouldShow`. Dismissed permanently for the current period on either CTA tap.
- **Time range selector**: `PeriodRange` enum with 6 cases (`.thisWeek`, `.lastWeek`, `.thisMonth`, `.lastMonth`, `.lastThreeMonths`, `.thisYear`); chip strip at top of `PeriodRecapView`.
- **Editorial layout**: headline (large bold text) → stat strip (sessions / volume / new PRs) → `AISurface` trends section → correlation card (orange gradient border, `PATTERN` label) → closing `AISurface` → `AIPrivacyFooter(.full)`.
- **Skeleton loading**: full layout skeleton shown while `.loading` state is active; transitions to partial content as fields arrive.
- **Cache key**: `"\(range.rawValue)|\(rangeStartISO)|\(lastWorkoutInPeriodISO)"`, filename prefix `period_recap_v2_` (bumped with the fact-based redesign so old entries regenerate).
- **System prompt file**: `PeriodRecapInstructions.swift`.
- **Output struct**: `PeriodRecapOutput` — `headline`, `trendsNarrative`, `correlationHighlight: String?` (Optional), `closingSentence`.
- **Fact-based content redesign (July 2026, same doctrine as Workout Analysis)**: the first version let the model narrate freely — the headline restated total volume/session counts (redundant with the stat strip directly above and a metric the user doesn't care about), the trends narrative rambled and produced contradictions ("Plateau erreicht, wobei die Gewichte zurückgegangen sind" — because plateaued trends still carried a kg delta in the prompt), and the closing was pure motivational filler. Now `PeriodRecapInput.toPromptText()` resolves everything in Swift: a **Headline fact** (strongest est-1RM gain > declines > steady plateau), trend groups where **plateaued exercises are serialized by name only** (no delta → no contradiction fodder), a **Consistency line** (weeks trained of weeks covered, avg sessions/week, longest gap, regular/irregular flag — running periods only count elapsed weeks), and a **Closing fact**. The system prompt reduces the model to rephrasing, bans total volume and hype words (bemerkenswert/beeindruckend/spannend/…), and requires contradiction-free trend sentences.
- **Consistency + recommendation (July 2026)**: `ConsistencyMetrics` (totalWeeks/trainedWeeks/avgSessionsPerWeek/longestGapDays/isIrregular; irregular = skipped weeks or a gap ≥ 9 days) feeds the prompt. `buildRecommendation` resolves **at most one actionable suggestion**, only when stagnation demonstrably coincides with irregularity: (1) the adherence correlation fired (dips followed low-frequency weeks) → "keep frequency steady at ~X/week", or (2) training irregular AND no exercise improved → "more evenly spaced sessions". The closing fact is then marked as a recommendation and the system prompt allows a suggestion **only there** — the general no-prescriptive-advice rule stays for everything else. This is a deliberate product decision (user request): the Rückblick may give one concrete training-consistency recommendation; medical/nutrition advice remains banned.
- **`correlationHighlight` is `String?`**: the field is schema-Optional so the model produces `null` (not an empty string) when no correlation data is present. The UI skips the card entirely when `nil`. A belt-and-suspenders heuristic (`isApologeticCorrelation`) in `PeriodRecapViewModel` additionally filters explicit "nothing found" phrasing ("keine Zusammenhänge", "no correlation", …). The earlier subject-matching heuristic (short text without a known exercise name → apologetic) was **removed**: the pre-written pattern statements are short and contain no exercise names, so it would have suppressed every real finding once the model started reproducing them verbatim.
- **Stream cancellation**: `PeriodRecapViewModel` stores the active stream in a `streamTask: Task<Void, Never>?`. `setRange`, `load`, and `regenerate` all cancel the previous task before starting a new one. The for-await loop guards on `Task.isCancelled` and does not surface output after cancellation.

### 3. Exercise Deep-Dive

- **Entry**: `ExerciseProgressChartView`. A `.task(id: currentExerciseId)` silently checks cache on appear. If no cache hit, `CoachDeepDiveButton` ("Ask the Coach") is shown below the chart card and `AICoachService.prewarm()` is called so the model is warm before the tap.
- **Tap responsiveness**: `DeepDiveState` includes `.preparing`, set synchronously in `generate()`/`regenerate()`. `CoachDeepDiveSurface` renders the streaming chrome with three `AISkeletonBar` rows while in `.preparing` or while the streamed text is still empty, and the button→surface swap cross-fades (`.animation(.easeInOut(0.3), value: state)`).
- **Paragraph break handling**: `CoachDeepDiveSurface` renders the full narrative as a single `StreamingTextView`. SwiftUI's `Text` renders `\n\n` as a native paragraph break. The previous multi-`StreamingTextView` split-on-`\n\n` approach caused visible layout growth during streaming as each double-newline introduced a new view.
- **Layout reservation**: both `streamingSurface` and `successSurface` apply `.frame(minHeight: 260, alignment: .topLeading)` so the chrome reserves space immediately and does not snap from a sliver to full height on the first token.
- **Stream cancellation**: `ExerciseDeepDiveViewModel` stores the active stream in a `streamTask: Task<Void, Never>?`. `generate` and `regenerate` are now synchronous fire-and-forget (not `async`). `cancel()` is called from `ExerciseProgressChartView.onDisappear`.
- **Cache key**: `"\(exerciseId.uuidString)|\(lastSetTimestampISO)"` — auto-invalidates next time a new set for that exercise is logged.
- **System prompt file**: `ExerciseDeepDiveInstructions.swift`.
- **Output struct**: `ExerciseDeepDiveOutput` — single `narrative: String` field.
- **`findPeak` PR definition**: `ExerciseDeepDiveAggregator.findPeak` selects the session with the highest **raw weight** (ties broken by reps), matching the chart's PR marker. Previously it used max est-1RM, which could surface a lower raw weight than the chart's PR stat.

### 4. Workout Analysis

- **Entry**: `WorkoutDetailView` (tapping a past workout in the Verlauf/History tab). A `.task` silently checks cache on appear and whether a previous same-routine session exists. If yes, `CoachWorkoutAnalysisButton` ("Ask the Coach") is shown below the stats grid. When the button is showing (no cache hit), `AICoachService.prewarm()` is called so the model weights are warm before the user taps.
- **Comparison logic**: `WorkoutAnalysisAggregator.buildInput` finds the most recent previous `WorkoutSession` with the same `routineName` (case-insensitive). Receives per-exercise comparison data as a `comparisons:` parameter, resolved by `WorkoutAnalysisViewModel` through `ExerciseProgressProviding` before the aggregator runs (audit P1.6 — it previously constructed `ExerciseProgressService` ad hoc and ran that scan on the main actor). Comparisons are matched to exercises by `workoutExerciseId`, not by position. Also detects new PRs via the Epley formula — **only for exercises with prior history** (`priorBestByKey` lookup must hit; a first-time exercise trivially "beats" a nonexistent baseline and must not count as a PR) — and counts exercises done last time but skipped this session (`droppedExerciseCount`, matched by `stableKey`).
- **Data gates**: analysis suppressed when (a) fewer than 2 completed sets, (b) no previous same-routine session, (c) completion below 40% (`minimumCompletionThreshold` — an aborted workout produces a meaningless comparison), (d) every exercise is first-time (nothing to compare), (e) AI Coach unavailable or workout detail preference off. Gates (a)/(c)/(d) surface as the generic `insufficient_data` copy if the button was already visible.
- **Layout**: `CoachWorkoutAnalysisSurface` replaces the button after tap (cross-fade, `.animation(.easeInOut(0.3), value: state)` on the section). Renders the structured output: headline (15 pt semibold) → 1–4 highlight rows (trend icon in a tinted circle + exercise name + one-line detail) → dimmed closing sentence. `minHeight: 200`, header label `ai_coach.workout_analysis.header_label` (localized). Trend icon mapping: improved `arrow.up.right` (accent green), declined `arrow.down.right` (warning orange), unchanged `equal`, mixed `arrow.up.arrow.down`, new `plus`, still-streaming `ellipsis`.
- **States**: `WorkoutAnalysisViewModel.AnalysisState` includes `.preparing` — set **synchronously** in `generate()`/`regenerate()` before the async pipeline starts, so the surface (with skeleton bars in every content slot) appears on the same frame as the tap. Without it the button sat frozen through availability check (up to 2 s sleep when model not ready), aggregation, and time-to-first-token. Missing fields during streaming render as `AISkeletonBar` placeholders inside the same layout, so the card fills in progressively instead of jumping.
- **Cache key**: `workoutId.uuidString`, filename prefix `workout_analysis_v3_` — workout content is immutable once saved, so the key never changes. The version suffix is bumped whenever the content design changes (v2: fact-based redesign; v3: first-time-exercise exclusion + glossary, both July 2026): the struct still decodes old entries, so a filename bump (not decode failure) is what orphans pre-redesign caches and forces regeneration. **Format migration**: even older caches stored `{narrative}`; decode failure in `AICoachCache` returns `nil` (treated as a cache miss), so those also silently regenerate — no migration code needed.
- **System prompt file**: `WorkoutAnalysisInstructions.swift`.
- **Output struct**: `WorkoutAnalysisOutput` — `headline`, `exerciseHighlights: [WorkoutAnalysisHighlight]` (1–4 via `.minimumCount/.maximumCount` guides), `closingObservation`. Each highlight: `exerciseName`, `trend: WorkoutAnalysisTrend` (a native `@Generable enum: String, Codable`, copied from the input verdict tags), `detail` (one short sentence). The view consumes `WorkoutAnalysisContent` (plain Equatable struct mapped from the output / its `PartiallyGenerated` snapshots in the ViewModel) so FoundationModels types never reach the view layer.
- **Why structured output (research finding)**: the ~3B on-device model produced garbled free-text narratives — mixed units ("Wiederholungen um 30 kg"), echoed raw ISO dates, invented words ("Gesamtwertung"), unscannable walls of text. The free-form `narrative: String` approach was discarded. The `@Generable` schema constrains each field to one short sentence and forces the trend classification through a `@Generable` enum, leaving the model only the phrasing. Supporting input change: raw ISO dates replaced by `daysSincePrevious: Int` (the model echoed dates verbatim, prompt now forbids mentioning dates at all).
- **Fact-based content redesign (July 2026)**: the first structured version still let the model *choose* what to say — the headline was contractually about total volume (a metric users don't care about) and the per-exercise `detail` was composed by the model from raw per-set lines, which it tended to echo as bare stats ("37.5 kg x 6 reps") with no comparison. Both were replaced by fully pre-resolved facts computed in Swift (`WorkoutAnalysisInput.toPromptText()`): a **Headline fact** chosen by priority (new PR > all/majority improved > all/majority declined > unchanged > mixed, e.g. `"3 of 4 exercises improved"`) and one **Fact line per exercise** that leads with the top set — the number a lifter actually cares about (`"top set +2.5 kg: now 37.5 kg x 6 reps, was 35 kg x 6 reps"`, rep gains at same weight, extra sets). Raw per-set lines and all volume figures were removed from the prompt entirely so the model cannot fall back to echoing them; the system prompt now forbids mentioning total volume and reduces the model's job to translating/rephrasing the fact lines in the user's language. Verdict classification was also fixed so MIXED is reachable (weight up + reps down or vice versa was previously reported as IMPROVED/DECREASED by summed-weight sign alone). Edge cases fed as prompt notes: cut-short sessions (completion < 70% → closing must say "cut short", missing sets must not read as strength loss), skipped exercises (`droppedExerciseCount`), and first-time exercises — all three may be mentioned in the closing only. The closing observation additionally bans hedged praise-and-criticize sentences without a concrete fact.
- **First-time exercises are not content (user feedback, July 2026)**: "Erste Übung in dieser Routine" as a highlight is irrelevant to the user, and a first-time exercise falsely triggered the PR headline (no prior best to beat). First-timers are now excluded from PR detection (aggregator), excluded from the prompt's per-exercise fact list (they appear only as a "done for the first time" note), and forbidden as highlights by prompt + `@Guide`. Consequently `exerciseHighlights` allows `.minimumCount(1)` (was 2) so a session with a single comparable exercise doesn't force the model to invent a second highlight.
- **Translation glossary (user feedback, July 2026)**: the model left English fitness terms in German output ("Bestset", "Topset"). The system prompt now carries an explicit German glossary (top set → Topsatz, reps → Wiederholungen, PR → Bestwert, …) and states that "Topset"/"Bestset" are not words.
- **Token cap**: 300 tokens.
- **Preference**: `workoutDetailEnabled` (UserDefaults key: `aiCoachWorkoutDetailEnabled`, default: `true`). Toggle in AI Coach Settings under "Workout detail".

---

## Availability and Opt-in

- `AICoachAvailability` (`@Observable @MainActor` singleton): maps `SystemLanguageModel.default.availability` to `isAvailable: Bool`. Re-checked on `.active` scene phase change via `.task`.
- `AICoachPreferences` (`@Observable @MainActor`, UserDefaults-backed): `hasCompletedOptIn`, `isMasterEnabled`, `postWorkoutRecapEnabled`, `periodRecapEnabled`, `exerciseDeepDiveEnabled`, `workoutDetailEnabled`. Also stores `lastOptInDeclinedAt` for the 7-day re-prompt cooldown.

> **`@MainActor` added 2026-08-12** to both, and to their Domain protocols
> (`AICoachAvailabilityProviding`, `AICoachPreferencesProviding`). Both were plain
> `@Observable` classes holding mutable state behind a `static let shared`, which under
> Swift 6 strict concurrency is global shared mutable state (a non-`Sendable` static).
> Global-actor isolation makes them implicitly `Sendable`, and the protocols had to
> follow because SE-0470 rejects a `@MainActor` type satisfying a nonisolated
> requirement. This also let `AICoachAvailability.refresh()` drop its
> `await MainActor.run { … }` wrapper. The rest of the AI-coach protocol surface was
> already `@MainActor`, so this made it uniform. See `docs/swift6-concurrency.md` §2.
>
> **One deliberate exception since 2026-08-13:** `ChatFactProviding` is *not*
> `@MainActor` — audit P1.3 made it a `Sendable`, `async`, actor-backed read boundary,
> because it is the one AI-coach protocol that reads the user's whole workout history
> rather than a UserDefaults flag. Uniformity is not the goal; keeping unbounded fetches
> off the main actor is. See `docs/ai-coach-chat-feasibility.md` delta 6.
- **First-run opt-in**: `AICoachOptInView` is presented as `.fullScreenCover` when `AICoachAvailability.isAvailable && !preferences.hasCompletedOptIn`. "Enable Coach" → sets `hasCompletedOptIn = true` + `isMasterEnabled = true`. "Maybe later" → records decline timestamp.
- **Decline cooldown**: re-shown after 7 days if user still has not opted in.
- **Opt-in layout (fixed 2026-08-14)**: the screen's content (hero sparkle + headline + body + three feature rows) is taller than a compact screen at longer localisations — in German on an iPhone 17 it overflowed by roughly 50 pt. It was laid out in a fixed `VStack` inside a `ZStack`, so SwiftUI resolved the overflow by compressing the `Text` views: the feature descriptions silently collapsed to one truncated line ending in "…". The fix is structural, not cosmetic: the content lives in a `ScrollView` (`.scrollBounceBehavior(.basedOnSize)` so it feels static when nothing overflows, `.scrollIndicators(.hidden)`) and the two CTAs + privacy footer are pinned via `.safeAreaInset(edge: .bottom, spacing: 0)` — the same pattern as `ConfigureExerciseSetsView`. `.ignoresSafeArea` is scoped to the inset's *background* only (a `Color.black` plus a 32 pt transparent→black fade offset above the bar, so content scrolling underneath dissolves instead of being cut mid-line); putting it on the inset's content would corrupt the inset height and let the buttons drift under the home indicator. The vertical rhythm was also tightened (hero 88→74 pt sparkle in a 132 pt glow, top spacer 14→4, gaps 24→18 and 28→20, feature row padding 14→11 pt) so the German copy now fits without scrolling on 6.3" and larger; on smaller devices (iPhone 16e) it scrolls with the fade. Every multiline `Text` additionally carries `.fixedSize(horizontal: false, vertical: true)` — belt-and-braces against a future ancestor reintroducing a height constraint, not the mechanism doing the work.
- **Known limitation**: the opt-in screen uses fixed `.font(.system(size:))` values throughout, so it does not respond to Dynamic Type. Verified 2026-08-14 — the layout renders identically at `accessibility-medium`. Making it scale is a separate piece of work; the `ScrollView` above is what would absorb the extra height if it is done.

---

## Caching

- Location: `Application Support/AICoachCache/*.json`.
- `AICoachCache` is an `@MainActor` singleton.
- Typed `save*` / `load*` / `invalidate*` methods for each surface.
- Cache hit → surface renders instantly with "Cached" label + "Regenerate" link in `PeriodRecapView`.
- Post-workout entries are permanent (invalidation only via explicit regenerate).
- Period recap entries are invalidated when any workout in that period changes.
- Deep-dive entries auto-invalidate via timestamp in the key.
- Workout analysis entries are permanent (keyed by immutable `workoutId`).

---

## Guided Generation reference (WWDC25)

The framework's structured-output mechanism is **Guided Generation** (`@Generable` + `@Guide`). Constraints below are enforced at the **decoding level** — the model literally cannot emit a value outside them, so they are far stronger than asking for a format in the prompt. Use these instead of free-text + prompt instructions wherever the shape is known.

| Mechanism | Signature / usage | When to use |
|---|---|---|
| `@Generable enum` | `@Generable enum Trend: String, Codable { case … }` used as a property type | Closed set of options. Type-safe; preferred over `.anyOf`. Raw-value + `Codable` confirmed to compile, giving clean JSON for the cache. |
| `.anyOf([String])` | `@Guide(description:, .anyOf(["a","b"]))` on a `String` | Same decoding guarantee as an enum but stays a `String`. Use only when the option set is dynamic/data-derived. |
| `.count(n)` | `@Guide(description:, .count(3))` on an `Array` | Exact array length. |
| `.minimumCount(n)` / `.maximumCount(n)` | on an `Array` | Bounded array length (we use 1…4 for `exerciseHighlights`). |
| `.range(a...b)` | on `Int`/`Double`/`Decimal` | Clamp a numeric field to a range. |
| `.pattern(Regex)` | on a `String` | Force a string to match a regex (e.g. an ID format). |

Supported field types out of the box: `Bool`, `Int`, `Float`, `Double`, `Decimal`, `String`, `Array`, nested `@Generable` structs, and `@Generable` enums (including enums with associated values). The model generates fields in declaration order.

**Applied in Workout Analysis**: `@Generable` struct output (headline / `[WorkoutAnalysisHighlight]` / closing), `.minimumCount`/`.maximumCount` on the highlights array, and a native `@Generable enum WorkoutAnalysisTrend` for the per-exercise direction. The earlier `.anyOf` string for `trend` was replaced by the enum (same model-level guarantee, no string→enum mapping or invalid-value fallback in the ViewModel). Sources: Apple docs `foundationmodels/generationguide`, `foundationmodels/generable`, and `generating-swift-data-structures-with-guided-generation`.

---

## Streaming

- `LanguageModelSession.ResponseStream<T>` yields `Snapshot` values at ~30 Hz (~33 ms intervals).
- Each snapshot's content is accessed via `snapshot.content` (type: `T.PartiallyGenerated`). Fields are `String?` until that field begins generating.
- Render each snapshot in full (snapshot = cumulative state, not delta).
- Fields in `@Generable` structs stream in strict declaration order (framework-guaranteed). Field N is fully complete before field N+1 starts.
- `StreamingTextView` renders `text` **directly** as a `Text` view — no internal word-by-word timer. A blinking 7×14 pt accent cursor appears inline at the tail while `isStreaming == true`. `.animation(nil, value: text)` suppresses height-interpolation animations between snapshots.
- The old `wordDelay` parameter is now a no-op (source-compatible, no effect).
- `AISurface` shows a shimmer border gradient and a pulsing dot + `"writing"` label while `isStreaming == true`.

### Period Recap layout stability

`PeriodRecapView` maintains an identical card tree for both `.streaming` and `.success` states:

```
statStrip → headlineCard → trendsCard → [correlationCard] → closingCard
```

The correlation card is optional: during streaming it appears whenever `correlationHighlight` is non-nil; in success it is omitted entirely when the field is `nil` (no dead space, no apologetic copy).

**Canonical correlation card pattern**: The card uses an outer `VStack` as the layout root (not `ZStack`). The background is applied via `.background { ZStack { … } }` and clipped with `.clipShape(…)`. This ensures the card's height is determined by its content, not by Shape intrinsic sizes, which previously collapsed to 0 pt and caused the card to escape into the next sibling's layout slot.

Each content slot pre-reserves vertical space via `minHeight` constants (calibrated for 14 pt body, lineSpacing 5, ~320 pt content width):

| Card | minHeight |
|---|---|
| Headline | 60 pt |
| Trends | 140 pt |
| Correlation | 90 pt |
| Closing | 44 pt |

While a field is `nil`/empty, three muted placeholder bars (opacity 0.08) are shown inside the reserved frame. When the field first receives content, the placeholder cross-dissolves to the streaming `StreamingTextView` via `.animation(.easeInOut(duration: 0.25), value: content.isEmpty)` — a discrete boolean transition, not a per-snapshot one.

The stat strip is rendered **first** (before the headline card) in both states. During streaming it uses the `HeadlineMetrics` already computed by the aggregator; in success it uses the `metrics` value stored on the `.success` enum case. `PeriodStatStripBridge` (the old separate-fetch sub-view) has been removed.

`sectionLabel` wraps its `Text` in `.drawingGroup()` to prevent garbled-character rendering during ancestor layout animations.

---

## Token Budget and Fallback

- Model context: `SystemLanguageModel.default.contextSize` (synchronous, ~4096 tokens typical).
- Token counting: `tokenCount(for:)` is `@available(iOS 26.4, *)` and `async throws`. On iOS 26.0–26.3, the full input is used without checking.
- Period recap compact fallback: if `fullTokens + instructionTokens + 700 (output reserve) > contextSize`, `PeriodRecapAggregator.buildCompact(…)` is called instead. The compact variant omits exercise-by-exercise trend rows, keeping only aggregate stats.
- **Output token caps** (set via `GenerationOptions(maximumResponseTokens:)` passed to `session.streamResponse(to:generating:options:)`):

| Surface | Cap |
|---|---|
| Post-workout recap | 200 tokens |
| Period recap (full) | 600 tokens |
| Period recap (compact fallback) | 400 tokens |
| Exercise deep-dive | 400 tokens |
| Workout analysis | 300 tokens |

The caps are applied in `AICoachService.stream(instructions:promptText:outputType:useCase:maximumResponseTokens:)` via an optional parameter, keeping each call site responsible only for its own budget.

---

## Error Handling

**Where errors surface (changed 2026-08-12).** `LanguageModelSession.streamResponse(…)`
is **non-throwing** in the current SDK — a generation failure arrives when the returned
stream is *iterated*, not when it is created. `AICoachService.stream(…)` is therefore
`async` (not `async throws`) and contains no `do`/`catch`: a creation-time
`catch` + `mapError` had become unreachable dead code and was removed. Error
classification and telemetry live in each ViewModel's `for try await` catch block,
which is where the error actually arrives — all four consumers of `stream()` already
call `AICoachTelemetry.recordError` (`ExerciseDeepDiveViewModel`, `PeriodRecapViewModel`,
`PostWorkoutRecapViewModel`, `WorkoutAnalysisViewModel`; chat streams through
`CoachChatService` instead).

The public `streamXxx` methods keep their `async throws` signatures (they are the
`AICoachServicing` protocol contract, and `streamPeriodRecap` still calls the throwing
`tokenCount`).

*Deliberate omission:* the old `mapError` also logged one line per `GenerationError`
case (guardrail vs. context-overflow vs. rate-limited). That per-case logging went away
with the dead code. If it is wanted back it belongs at the iteration sites, not at
stream creation — see git history for the original switch. Two cases the SDK has since
added, `.concurrentRequests` and `.refusal`, had already made that switch
non-exhaustive.

`prewarm()` is likewise synchronous now (no `await`); the wrapping `Task` is kept
deliberately so constructing the session never blocks the caller's main-actor turn.

`GenerationError` cases handled across all ViewModels:

| Case | Strategy |
|---|---|
| `.guardrailViolation(_)` | Silent fallback — show `FallbackHintLine` without surface. Do not expose message to user. |
| `.exceededContextWindowSize(_)` | Log via `AICoachTelemetry`, show fallback. |
| `.unsupportedLanguageOrLocale(_)` | Show fallback. |
| `.decodingFailure(_)` | Show error state with retry button. |
| Other / unknown | Show error state with retry button. |

The ViewModel's `.error(String)` state carries a user-facing message string. For guardrail violations, the ViewModel transitions to `.unavailable` to avoid implying the user triggered a safety filter.

---

## Telemetry

`AICoachTelemetry` wraps `os.Logger`. Logged events (all without user data):
- Generation started / completed / failed (surface, duration, error type).
- Cache hit / miss per surface.
- Opt-in accepted / declined.

Never logged:
- Prompt text.
- Narrative output text.
- Exercise names, weights, reps, or any health data.

---

## Settings

Accessed from the Settings tab: the "AI Coach" section's row (`SettingsRootView` →
`SettingsDestination.aiCoach`) pushes `AICoachSettingsView`; the gear in the expanded chat's
toolbar (`CoachChatView`) pushes the same screen. Until 2026-08 it was reached via a gear in
the History header — that button is gone, see [Settings Tab](./settings-tab.md).

Sections:
- **Coach**: master toggle (enable/disable all AI features).
- **When the Coach appears**: per-surface toggles for post-workout, monthly recap, exercise detail, workout detail.
- **Info**: "How the Coach works" (placeholder sheet) and "About Apple Intelligence" (opens Apple Support URL).
- Footer disclaimer (monospaced, on-device privacy statement).

When device is ineligible (`!availability.isAvailable`), an unavailability banner appears and the master toggle is disabled (0.55 opacity).

---

## Watch App

The Watch app is unaffected. FoundationModels is not available on watchOS. All AI surfaces are iOS-only. No watch-specific AI code was introduced in any wave.

---

## Localization

- German (`de.lproj/Localizable.strings`) and English (`en.lproj/Localizable.strings`) are both maintained.
- German is the primary/source locale (the original inline strings).
- All AI Coach keys are grouped under `// MARK: - AI Coach` at the bottom of both files.
- Keys follow the pattern `ai_coach.<surface>.<element>`.
- Interpolated strings use `String(format: "key".localized, arg1, arg2)` following the codebase's existing pattern.
- The `locale` field is embedded in every aggregator's `toPromptText()` output as `Locale.current.identifier` (e.g. `de_DE`). The system prompt instructs the model: for `de_*` use German; for `en_*` use English; for any other locale, use English.

---

## Privacy

All inference runs on-device via Foundation Models. No prompt text, no narrative text, and no workout data is transmitted to any server. Every AI surface shows an `AIPrivacyFooter` with a lock icon and the message "Generated on your iPhone · Data never leaves the device". The Settings screen footer reiterates this in full.

---

## TODO (next phase)

- Weekly bar chart inside Period Recap's stat strip.
- PR count in the Period Recap stat strip (currently shows "-" as a placeholder; requires efficient PR query).
- Share-as-image for Period Recap output.
- UITest coverage for all three surfaces.
- "How the Coach works" info sheet — currently a placeholder (`HowItWorksSheet` in `AICoachSettingsView.swift`).
- "About Apple Intelligence" info sheet — currently opens external Apple Support URL; may become in-app.
