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
SwiftData (WorkoutSession / WorkoutExercise / ExerciseSet)   — canonical kilograms
  ↓
Aggregator.build*(…) → *Input struct                         — still kilograms
  ↓
*Input.toPromptText(in: weightUnit) → String                 — CONVERTS, once
  ↓
AICoachService.streamXxx(input:weightUnit:) → LanguageModelSession.ResponseStream<OutputType>
  ↓
for snapshot in stream → snapshot.content → *Output.PartiallyGenerated
  ↓
ViewModel publishes partial text → StreamingTextView
  ↓
Final snapshot → full *Output → AICoachCache.save*()
```

The exercise deep-dive inserts one boundary into that first step: its aggregator runs on
the History `@ModelActor` behind `ExerciseDeepDiveFactProviding`, and what reaches the
ViewModel is a `Sendable` `ExerciseDeepDiveAggregate`, never a `ModelContext` or a
`@Model` (§3, ticket 02). The other three surfaces still aggregate on the caller.

### The weight unit (kg / lb)

Weights are stored in kilograms everywhere and converted **at the point a string is made**
— `toPromptText(in:)`, the two aggregator-rendered `magnitude` strings, `ChatFactBuilder`'s
fact lines, and the two sentences Swift composes for the reader. The input DTOs stay
kilograms, so their `…Kg` names and their `@Guide` descriptions stay true.

The unit travels **beside** the input (`streamXxx(input:weightUnit:)`) rather than inside
it: the inputs are `@Generable`, so a `WeightUnit` property would need `FoundationModels`
in a Domain type the watch copies verbatim. Views read `@Environment(\.weightUnit)` and
pass it in with `locale`.

Three rules that are easy to get wrong:

1. **Every prompt's worked examples carry the unit too.** These prompts teach exact
   echoing, so a hardcoded `87.5 kg` example teaches a pounds reader's model to write "kg".
2. **A `@Guide(description:)` cannot name the active unit** — it is a literal in a static
   schema. Output guides say *copy the input's unit word*; the prompt names the unit.
3. **kg-magnitude significance thresholds stay in kilograms** and are applied before
   conversion, or a pounds user's bar rises by 2.2×.

`Domain/Services/AICoach/AICoachUnitVocabulary.swift` does the rendering — `Presentation/`'s
`WeightFormatting` is off-limits to Domain, but both read the same `unit.weight.*` keys.
Full rationale in `docs/weight-unit-preference.md` §13.

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

Because the defaults resolve to the production singletons, these three arguments never appear at a view call-site. Tests inject fakes conforming to the three protocols instead.

**`ExerciseDeepDiveViewModel` takes no `ModelContext` at all** (ticket 02). Its history
reads go through a required, non-defaulted `facts: any ExerciseDeepDiveFactProviding`
handed down from `AppDependencies.exerciseDeepDiveFacts` — the same
`SwiftDataHistorySnapshotProvider` the chart on that screen uses. The other three coach
ViewModels still take a `ModelContext` per call and aggregate on the caller's actor. Its
allowance tests inject the **real** provider over an in-memory container rather than a
stub, since the boundary crossing is the thing under test.

**The one dependency that is *not* defaulted is the Pro allowance gate.** Since the P4/P5 taster (docs/pro-subscription.md §5e), `PeriodRecapViewModel` and `ExerciseDeepDiveViewModel` take a required `allowanceGate: AICoachAllowanceGate` first parameter. It carries the entitlement and the paywall seam, which per Hard rule 2 come from `AppDependencies.makeAICoachAllowanceGate(for:)` and never from a singleton — so both screens gained a thin outer view (`PeriodRecapView`, `ExerciseProgressChartView`) that reads `@EnvironmentObject AppDependencies` and hands the gate to the real, private screen. `PostWorkoutRecapViewModel` and `WorkoutAnalysisViewModel` take no gate: those two surfaces are free and unmetered by design.

`AICoachAvailability` is intentionally **not** protocol-ized or injected — it's a thin, side-effect-free wrapper around `SystemLanguageModel.default.availability` and stays a direct `.shared` reference in the VMs (and in view files, which also still reference `AICoachPreferences.shared` / `AICoachService.shared` / `AICoachCache.shared` directly for one-off reads — e.g. opt-in checks, prewarming — outside the injected VM pipeline).

**SwiftData queries live in the Data layer only.** Each AI Coach ViewModel used to build `FetchDescriptor`s and call `modelContext.fetch(...)` directly for cache-key/quick-lookup queries that fell outside the main `buildInput(...)` aggregation path. These were moved into the corresponding aggregator so the Presentation layer never constructs a query:

| Query (formerly inline in the ViewModel) | Now lives in |
|---|---|
| Period-recap cache key's "most recent session in range" lookup | `PeriodRecapAggregator.mostRecentSessionStart(in:modelContext:)` |
| Period-recap quick headline metrics (before/without full aggregation) | `PeriodRecapAggregator.headlineMetrics(in:modelContext:)` |
| Period-recap "known subjects" (apologetic-correlation heuristic) | `PeriodRecapAggregator.knownSubjects(in:modelContext:)` |
| Exercise deep-dive cache key's "last completed set timestamp" lookup | `ExerciseDeepDiveAggregator.lastCompletedSetTimestamp(exerciseId:modelContext:usageSelection:)`, reached through `ExerciseDeepDiveFactProviding` |
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
    ExerciseDeepDiveAggregate.swift   — Sendable pair (input + cache timestamp) crossing off the model actor
    ExerciseDeepDiveNarrative.swift   — what the cache stores and the surface renders: the generated paragraphs + the Swift-composed peak sentence
    WorkoutAnalysisInput.swift        — input struct + toPromptText() + the Swift-composed headlineSentence
    WorkoutAnalysisNarrative.swift    — what the cache stores and the surface renders: the generated highlights + the Swift-composed headline
  Domain/Interfaces/AICoach/
    AICoachServicing.swift            — protocol for AICoachService's streamXxx surface
    AICoachCaching.swift              — protocol for AICoachCache's loadXxx/saveXxx/invalidateXxx surface
    AICoachPreferencesProviding.swift — protocol for the 4 isXxxEffectivelyEnabled flags
    ExerciseDeepDiveFactProviding.swift — the deep-dive's off-main history read boundary (SwiftDataHistorySnapshotProvider conforms)
  Data/AICoach/
    AICoachAvailability.swift         — SystemLanguageModel availability mapping
    AICoachPreferences.swift          — UserDefaults-backed preferences (@Observable), conforms to AICoachPreferencesProviding
    AICoachService.swift              — central façade, streamPostWorkoutRecap / streamPeriodRecap / streamExerciseDeepDive / streamWorkoutAnalysis, conforms to AICoachServicing
    AICoachCache.swift                — disk-backed JSON cache (Application Support/AICoachCache/), conforms to AICoachCaching
    AICoachTelemetry.swift            — os.Logger wrapper (no prompt or narrative text logged)
    PostWorkoutRecapAggregator.swift  — builds PostWorkoutRecapInput from a WorkoutSession; also owns the prior-session-count query
    PeriodRecapAggregator.swift       — builds PeriodRecapInput from a date range; also owns the cache-key/headline/known-subjects lookup queries
    ExerciseDeepDiveAggregator.swift  — builds ExerciseDeepDiveInput + the cache-key timestamp from historical sets; called only from SwiftDataHistorySnapshotStore
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

- **Trigger**: `SaveWorkoutView.task` calls `PostWorkoutRecapViewModel.generate(session:locale:modelContext:)`, after the vs-previous comparison has loaded.
- **Lifetime**: fire-and-forget (`runTask`), like `WorkoutAnalysisViewModel`, with a matching `cancel()`. The view cancels on `.onDisappear` **and** the moment `viewModel.currentSession` becomes nil, because discarding the workout deletes the very session the recap describes. For the same reason `run` reads the session only before its first `await` — see `docs/history-delete-race.md`, "The adjacent bug".
- **Surface**: `AIRecapInline` embedded as a `Section` inside the save-workout `Form`. Renders `AISurface` (streaming/success) or `FallbackHintLine` (unavailable/error).
- **Cache key**: `workoutId.uuidString`.
- **Regenerate flow**: Clockwise-arrow in `AISurface` header calls `onRegenerate`, which invalidates cache and re-streams.
- **System prompt file**: `PostWorkoutRecapInstructions.swift`.
- **Output struct**: `PostWorkoutRecapOutput` — single `narrative: String` field.

- **Skeleton while preparing (2026-08-30).** `RecapState` has a `.preparing` case, set synchronously at the end of `PostWorkoutRecapViewModel.start` once every gate has passed. `AIRecapInline` renders it — and any `.streaming` snapshot whose text is still empty — as three `AISkeletonBar` rows cross-dissolving into the text, inside a `ZStack` with a `minHeight` so the card reserves its height from the first frame and the save sheet does not grow under the reader's thumb. Before this the card was `.idle` (nothing at all) through the availability retry, the prewarm and the first token, so the reader watched blank space and the finished paragraph appeared out of nowhere. Every other coach surface already had this: `WorkoutAnalysisViewModel` and `ExerciseDeepDiveViewModel` both call it `.preparing`, and `PeriodRecapView` has a full `loadingView`.

### 2. Period Recap

- **Entry points**:
  - `CoachEntryCard` — compact gradient-bordered card shown above `WeekHeroView` in `TrainingsTabView`. Pushes `PeriodRecapView` via `NavigationLink(value: PeriodRecapDestination)`.
  - `ProactivePeriodPromptCard` — shown once per month boundary (first app open after month rollover) by `ProactivePromptCoordinator.shouldShow`. Dismissed permanently for the current period on either CTA tap.
- **Time range selector**: `PeriodRange` enum with 6 cases (`.thisWeek`, `.lastWeek`, `.thisMonth`, `.lastMonth`, `.lastThreeMonths`, `.thisYear`); chip strip at top of `PeriodRecapView`.
- **Navigation**: `PeriodRecapView` hides the system navigation bar (`.toolbar(.hidden, for: .navigationBar)`) for its custom top bar, which also disables the native leading-edge swipe-back. It therefore applies `.swipeBackEnabled()` (2026-08-24) — see `docs/progress-charts.md` § "The screen keeps the native swipe-back gesture" for the root cause, why no pure-SwiftUI fix exists, and the iOS 26 second recognizer.
- **Editorial layout**: headline (large bold text) → stat strip (sessions / volume / new PRs) → `AISurface` trends section → correlation card (orange gradient border, `PATTERN` label) → closing `AISurface` → `AIPrivacyFooter(.full)`.
- **Skeleton loading**: full layout skeleton shown while `.loading` state is active; transitions to partial content as fields arrive.
- **Cache key**: `"\(range.rawValue)|\(rangeStartISO)|\(lastWorkoutInPeriodISO)"`, filename prefix `period_recap_v2_` (bumped with the fact-based redesign so old entries regenerate).
- **System prompt file**: `PeriodRecapInstructions.swift`.
- **Output struct**: `PeriodRecapOutput` — `headline`, `trendsNarrative`, `correlationHighlight: String?` (Optional), `closingSentence`.
- **Fact-based content redesign (July 2026, same doctrine as Workout Analysis)**: the first version let the model narrate freely — the headline restated total volume/session counts (redundant with the stat strip directly above and a metric the user doesn't care about), the trends narrative rambled and produced contradictions ("Plateau erreicht, wobei die Gewichte zurückgegangen sind" — because plateaued trends still carried a kg delta in the prompt), and the closing was pure motivational filler. Now `PeriodRecapInput.toPromptText()` resolves everything in Swift: a **Headline fact** (strongest est-1RM gain > declines > steady plateau), trend groups where **plateaued exercises are serialized by name only** (no delta → no contradiction fodder), a **Consistency line** (weeks trained of weeks covered, avg sessions/week, longest gap, regular/irregular flag — running periods only count elapsed weeks), and a **Closing fact**. The system prompt reduces the model to rephrasing, bans total volume and hype words (bemerkenswert/beeindruckend/spannend/…), and requires contradiction-free trend sentences.
- **Consistency + recommendation (July 2026)**: `ConsistencyMetrics` (totalWeeks/trainedWeeks/avgSessionsPerWeek/longestGapDays/isIrregular; irregular = skipped weeks or a gap ≥ 9 days) feeds the prompt. `buildRecommendation` resolves **at most one actionable suggestion**, only when stagnation demonstrably coincides with irregularity: (1) the adherence correlation fired (dips followed low-frequency weeks) → "keep frequency steady at ~X/week", or (2) training irregular AND no exercise improved → "more evenly spaced sessions". The closing fact is then marked as a recommendation and the system prompt allows a suggestion **only there** — the general no-prescriptive-advice rule stays for everything else. This is a deliberate product decision (user request): the Rückblick may give one concrete training-consistency recommendation; medical/nutrition advice remains banned.
- **`correlationHighlight` is `String?`, and the model is not trusted to leave it out.** The field is schema-Optional, and `@Generable` defaults to `representNilExplicitlyInGeneratedContent: false`, so a nil property is omitted from the generated content entirely — the affordance is real. The model still does not always take it: asked to *"return nil for this field"*, it wrote the literal string `nil`, which the card rendered under the `MUSTER` label (German, on device, 2026-08-30). Three things changed, and all three are described in § "Prompt grounding rules" rules 3 and 4: the prompt and the `@Guide` no longer name a programming construct; `PeriodRecapViewModel` drops the field outright when the input carried no "Detected patterns" section (`hasDetectedPatterns`, resolved in Swift from `sampleInput.correlations`); and `CoachCorrelationSanitizer.sanitized(_:)` rejects a placeholder token or an apology in the streamed partial, the final output **and** inside `AICoachCache.loadPeriodRecap`. The earlier subject-matching heuristic (short text without a known exercise name → apologetic) stays **removed**: the pre-written pattern statements are short and contain no exercise names, so it would have suppressed every real finding once the model started reproducing them verbatim.
- **Regenerate lives in the nav bar (2026-08-30).** Every other coach surface puts a circular `arrow.clockwise` in its `AISurface` header; this screen is a *tree* of cards rather than one surface, so the button sits at the trailing edge of `topNav` (36×36, matching the back button) and shows only in `.success` — regenerating replaces the whole recap, not one section of it, so a per-card button would have been wrong. It replaces a small "Regenerate" text link that used to end the cache sub-row, which appeared **only** on a cached recap (so a freshly generated one had no regenerate affordance at all) and which spent a metered reader's monthly recap with no prompt. **A metered reader is now asked first** — `PeriodRecapViewModel.regenerateConfirmationMessage`, `nil` for a Pro reader and while the kill switch is off: spending the month's single recap is meant to be a deliberate choice, the same reason `load` and `setRange` never generate for them. An *exhausted* reader gets no confirmation, because `AICoachAllowanceGate.requestGeneration` raises the paywall instead of running and a prompt there would be a second tap before a wall. Three tests in `PeriodRecapAllowanceTests` pin the three cases.
- **The correlation slot is reserved only when the input has a pattern.** `PartialContent.hasDetectedPatterns` carries the flag into the streaming state, so `PeriodRecapView` passes it as `showCorrelationWhenEmpty`. Reserving the slot unconditionally — what it did before — numbered the closing card `03` for the whole stream and then renumbered it to `02` in front of the reader the moment the empty card was dropped at `.success`.
- **Section ordinals are composed in the view, never baked into the localized string.** They used to be (`"02 · Auffälligkeit"`), and the moment the correlation card was correctly hidden — which is exactly what the `nil`-placeholder fix made happen — the reader saw `01 · Was sich verändert hat` directly above `03 · Ausblick` (device, German, 2026-08-30). `PeriodRecapView.sectionLabel(number:_:)` composes the label from an `ai_coach.period_recap.section.format` key (`"%1$02d · %2$@"`, so the ordinal's position and the `·` glue stay translatable), and `recapCardTree` passes `3` or `2` to the closing card depending on whether the correlation card is showing. The three `ai_coach.period_recap.section.*` title strings carry only the title in both languages.
- **Stream cancellation**: `PeriodRecapViewModel` stores the active stream in a `streamTask: Task<Void, Never>?`. `setRange`, `load`, `generateNow` and `regenerate` all cancel the previous task before starting a new one. The for-await loop guards on `Task.isCancelled` and does not surface output after cancellation.
- **Month label**: `PeriodRange.label(locale:)` formats `.thisMonth`/`.lastMonth` with `Date.FormatStyle` (`.locale(locale).month(.wide).year()`), not a `DateFormatter`. It is read from view bodies (title block, range chips, the free-tier offer card), where allocating a formatter is forbidden by the main-thread rules, and a cached `static let` formatter is not an option because `Domain/` stays isolation-agnostic and has no actor to hold a per-locale cache. `Date.FormatStyle` is a `Sendable` value usable from any isolation domain and honours the passed-in `locale` — which matters because `PeriodRecapAggregator` calls this with an explicit locale to build the model's prompt, not only for display. A hardcoded per-language month table was tried first and rejected for exactly that reason.
- **Free-tier metering (P4)**: two states — `.offer(HeadlineMetrics?)` and `.gated(HeadlineMetrics?)`, both rendered by `PeriodRecapAllowanceCard` — exist only for a metered user. On the free tier the screen never generates on arrival: `load`/`setRange` land on `.offer` with a "Generate recap" button, because one recap a month is a single irreversible choice and opening the screen (or following the proactive month-boundary prompt) must not be what spends it. `generateNow` is the only path that consumes; `regenerate` asks the gate before invalidating the cache so a refusal leaves the cached recap on screen. A cached recap, an unavailable device and an insufficient period are all resolved *before* the meter is touched. See docs/pro-subscription.md §5e.

### 3. Exercise Deep-Dive

- **Entry**: `ExerciseProgressChartView`. A `.task(id: DeepDiveContext(exerciseId:usage:))` silently checks cache once the screen's load has resolved which usage is charted, and again whenever the exercise or that usage changes. If no cache hit, `CoachDeepDiveButton` ("Ask the Coach") is shown below the chart card and `AICoachService.prewarm()` is called so the model is warm before the tap.
- **Tap responsiveness**: `DeepDiveState` includes `.preparing`, set synchronously in `generate()`/`regenerate()`. `CoachDeepDiveSurface` renders the streaming chrome with three `AISkeletonBar` rows while in `.preparing` or while the streamed text is still empty, and the button→surface swap cross-fades (`.animation(.easeInOut(0.3), value: state)`).
- **Paragraph structure is the output type, not a prose rule (2026-08-28).** `CoachDeepDiveSurface` renders one slot per generated field — `workload`, `progression`, `closing` — each filling independently as the stream delivers it, with `AISkeletonBar` placeholders inside the same layout for the slots that have not arrived (the shape `CoachWorkoutAnalysisSurface` already used). Only the paragraph currently being written carries `StreamingTextView`'s blinking cursor, so three slots never blink at once. This replaced a single `StreamingTextView` over one `narrative: String` split on `\n\n`: SwiftUI's `Text` renders `\n\n` as a native paragraph break, but the model never produced the breaks — asked in prose for "exactly 3 to 4 short paragraphs, 2-3 sentences each", it returned one undivided block on every device check, in both prompts. (The older multi-`StreamingTextView` split-on-`\n\n` approach is separately discarded: it caused visible layout growth during streaming as each double-newline introduced a new view. The per-field slots do not have that problem — the number of views is fixed by the type.)
- **Layout reservation**: both `streamingSurface` and `successSurface` apply `.frame(minHeight: 260, alignment: .topLeading)` so the chrome reserves space immediately and does not snap from a sliver to full height on the first token.
- **Stream cancellation**: `ExerciseDeepDiveViewModel` stores the active stream in a `streamTask: Task<Void, Never>?`. `generate` and `regenerate` are now synchronous fire-and-forget (not `async`). `cancel()` is called from `ExerciseProgressChartView.onDisappear` and from its `resetDeepDive()` (exercise or usage switch).
- **Free-tier metering (P5)**: `generate`/`regenerate` return `Bool` — `false` means the free monthly allowance is spent, the gate raised `.exerciseDeepDive`, and the state was left untouched so the "Ask the Coach" button stays where it was instead of collapsing into an empty surface behind the paywall. `checkCache` never touches the meter: a narrative already generated is free to re-read forever. `regenerate` asks the gate *before* invalidating the cache. See docs/pro-subscription.md §5e.
- **Cache key**: `"\(exerciseId.uuidString)|\(usageSelection.cacheToken)|\(lastSetTimestampISO)"` — auto-invalidates next time a new set of *that usage* is logged. The usage token is `ExerciseUsageSelection.cacheToken` (`all`, or `\(slotUUID)#\(occurrence)` / `unattributed#\(occurrence)`), defined on the value itself so there is one spelling of it. The timestamp half is resolved for the same usage, so training the light slot does not invalidate the heavy slot's narrative. **Both halves matter to the user's wallet**: without the token, switching usage serves the previous usage's sentences and switching back re-generates, and a free user pays a monthly allowance unit per generation (§5e). Adding the token orphaned every pre-2026-08-27 cached narrative — deliberately, because those were computed over the blend. **Filename prefix `exercise_deep_dive_v2_` since 2026-08-28**, bumped deliberately when the cached type changed from `ExerciseDeepDiveOutput` to `ExerciseDeepDiveNarrative`. `AICoachCache` treats a decode failure as a miss, so the bump is not strictly required — but a silent miss spends a free user's monthly allowance unit (§5e), and a deliberate bump makes that one-off regeneration an intended, documented cost rather than an accident. Same convention as `period_recap_v2_` and `workout_analysis_v4_`.
- **Output language: English instructions plus Apple's documented directive — *not* translated instructions (researched 2026-08-28).** German output read like literal machine translation: *"die die gesamte Zeitraum"*, *"des Bizeps-Curls-Übens"*, *"unterschiedlichen Trainingsschritten und **Zielgruppen**"* (*target audiences*, for rep-range goals), *Variation* and *Variante* used interchangeably one sentence apart despite a glossary line, and a "write exactly 2 paragraphs" rule ignored. **Writing the system prompts in German was implemented first and reverted**: Apple's [*Supporting languages and locales with Foundation Models*](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models) documents the opposite — "start with the exact phrase in English, which comes from the model's training, and reduces the possibility of hallucinations in multilingual situations", with `"You MUST respond in <language>."` as the pattern. English instructions with an explicit directive is the *supported* path, not a workaround, and there is no Apple guidance for translating instructions. `AICoachLocaleDirective.lines(forLocaleIdentifier:)` prepends `The person's locale is de_DE.` + `You MUST respond in German.` (language named in English, for the same reason), and returns `""` for US English — the model's own default, exactly as Apple's `localeInstructions(for:)` sample does. The old conditional rule ("write in the language indicated by the `locale` field") was removed: it asked the model to evaluate a condition instead of stating the answer.
- **`GenerationOptions(sampling: .greedy)` on this surface.** `.greedy` "always chooses the most likely token… deterministic output for a given input", and Apple uses it for its own must-not-hallucinate classification sample. Right for a surface whose entire job is restating figures it was handed. Applied to the deep-dive only; the other coach surfaces are unchanged and unverified. Caveat from WWDC25 session 301: determinism holds only for a given on-device model version, so an OS update can still change the wording.
- **Figures are written in the reader's own convention.** `toPromptText()` formats decimals with `String(format:locale:)` — `26,5 kg` for a German reader, `26.5 kg` for an English one — so the model copies rather than converts. A separator conversion is one more transformation it can get wrong, and `20.0 kg` beside a UI reading `44,1 lb` looks foreign.
- **Instructions were trimmed** toward Apple's "one to three paragraphs" guidance for prompts and instructions (*Prompting an on-device foundation model*, *Managing the context window*): instructions are placed verbatim in the prompt, so a long rule list spends context that instruction-following itself needs. The worked-anecdote parentheticals went; the load-bearing rules stayed, with all-caps emphasis on the critical negative constraint (WWDC25 session 248: the model "will respond well to an all caps command").
- **Shipped 2026-08-28: the output's shape is now the type's shape.** `ExerciseDeepDiveOutput` is three `@Guide`-described fields — `workload: String`, `progression: String?`, `closing: String` — one per paragraph, each carrying its own all-caps grounding constraint. This is the research's recommended lever: guided generation is Apple's documented mechanism for controlling output *shape*, `@Guide(description:)` is "effectively another way of prompting", and **no `@Guide` constraint enforces a sentence or paragraph count inside a single `String`** — which is exactly why three rounds of "output exactly N short paragraphs" were ignored. Flagged at the time as inference rather than an Apple claim: Apple documents the capability, not that splitting a prose field is *more reliable* than a prose count. Neither prompt asks for a paragraph count any more; what they still do is assign a *subject* to each field. Still unshipped: gating on `SystemLanguageModel.default.supportsLocale(_:)`, which is preferred over inspecting `supportedLanguages` because it accounts for language fallbacks, and would turn a `LanguageModelError.unsupportedLanguageOrLocale` into a clean unavailable state.
- **Two system prompts, not one with an exception** (`ExerciseDeepDiveInstructions.swift`, 2026-08-28). `systemPrompt(forBlendedView:)` returns `singleVariantPrompt` or `blendedViewPrompt`, chosen in `AICoachService.streamExerciseDeepDive` by `input.blendedUsageCount > 1`. The blended prompt never mentions progression, segments, percentages or frequency at all. **This replaced an "Exception — BLENDED VIEW" bullet inside the single-variant prompt, which failed on device:** given an input holding no trend, no segment and no frequency, the model followed the dominant four-paragraph progression structure and *invented* the missing figures — "1.5 kg mehr geschätztes 1RM", "zwischen 22.5 kg und 24.5 kg", "2.2 pro Woche", a "3-wöchige Phase zwischen April und Juni 2026". Fabricated numbers are strictly worse than the blended trend this feature withholds: that one was at least arithmetically real. A ~3B model will complete the shape its instructions describe, so the fix is to leave no shape — not to add a louder prohibition. Pinned by `blendedViewGetsItsOwnInstructions`, which asserts the blended prompt contains none of the progression vocabulary.
- **Output struct**: `ExerciseDeepDiveOutput` — `workload` / `progression?` / `closing`, deliberately **not** `Codable`. What the cache and the screen hold is `ExerciseDeepDiveNarrative` (`Domain/Models/AICoach/`), which is those three fields plus `peakSentence`, the one sentence composed in Swift and never generated. It carries `init(partial:peakSentence:statesProgression:)` for streaming snapshots and `init(output:peakSentence:statesProgression:)` for the finished response.
- **`findPeak` PR definition**: `ExerciseDeepDiveAggregator.findPeak` selects the session with the highest **raw weight** (ties broken by reps), matching the chart's PR marker. Previously it used max est-1RM, which could surface a lower raw weight than the chart's PR stat.
- **Exercise identity is `ExerciseProgressAggregator.matches(_:exerciseId:exerciseName:nameIsUnique:)`, not a local copy (fixed 2026-08-25).** `buildInput` resolves `nameIsUnique` once from the live `Exercise` library and hands it to `buildDataPoints`. This aggregator previously carried its own `matchesExercise` that applied the legacy name fallback (`exerciseId == nil` + case-insensitive name match) **without** the uniqueness gate the other three aggregators enforce. Where a library holds two exercises with the same display name — e.g. "Biceps Curls" as barbell and dumbbell — that claimed every ambiguous pre-`exerciseId` row for *both* of them. Found on a device check: the coach narrated *"in den letzten 19 Sitzungen … -43% Gesamtfortschrittsrate"* beside a chart and a Fortschritt row that both read 15 workouts, with the trend computed across two different exercises' loads. Double-counting is strictly worse than the drop the chart performs, and unlike the drop it is **not** repaired by the legacy-history attribution flow (`docs/progress-charts.md`) — an attributed row simply stops matching the other variant, whereas an ambiguous one was being counted twice. Pinned by `GymStreakTests/ExerciseDeepDiveIdentityTests.swift`, verified to fail against the ungated rule (8 sessions instead of 4, and a 40 kg barbell peak reported for the dumbbell exercise).
- **The cache-key query is on the same rule (fixed 2026-08-25).** `lastCompletedSetTimestamp` matched `we.exerciseId == exerciseId || we.exerciseId == nil` — no name check at all — so *any* legacy row with a completed set in the newest session advanced this exercise's cache key, however unrelated. A moved key is a cache miss, and for a free user a miss spends a monthly allowance unit (§5e) regenerating a narrative that had not changed. It now calls the shared rule, resolving the name and uniqueness from the live library; where the live entry is gone it matches on id alone, which is the conservative half of the rule.
- **The deep-dive describes the usage the screen is showing (fixed 2026-08-27).** `buildInput` takes the `ExerciseUsageSelection` the exercise detail screen has already resolved — handed down from `ExerciseProgressViewModel.selectedUsage`, never re-derived, because two resolutions could disagree — and applies the chart's remaining two filters alongside identity: `ExerciseUsageResolver.keyedRows(in:matching:)` + `belongs(_:to:)` for the usage, and `workoutExercise.loadBehavior == liveBehavior` for load-behaviour homogeneity. All three now live in one `RowFilter` value inside the aggregator, used by `buildAggregate`, `buildDataPoints` and `lastCompletedSetTimestamp` alike. Before this the coach folded every usage of an exercise into one series and narrated an est-1RM trend over the blend. Found on a device check: `Biceps Curls (Kurzhantel)` with `4–6 Wdh. · Pull` selected read **20.0 kg / +0.0% / 6 Workouts**, while the coach directly beneath it narrated *"in den letzten **15** Sitzungen … +4.4 kg … +22%"*. Both numbers were arithmetically right for what they measured, and nothing said they measured different things — the coach is the surface **most** likely to be believed, because it speaks in full sentences. The `loadBehavior` half matters on its own: a uniquely-named exercise whose library load behaviour changed after some workouts were logged otherwise had a narrative mixing counterweight *assistance* values with physical loads (`docs/assisted-exercise-progress.md`).
- **A blended `.combined` view states no progression at all.** `blendedUsageCount` is `options.count` for `.combined` and `1` for a selected usage; when it exceeds 1, `buildInput` returns `overallProgression`, `strongestSegment` and `currentSegment` as `nil`, `toPromptText()` emits a `BLENDED VIEW` block instead of the figures, and the system prompt switches to a two-paragraph shape: how much work is recorded, the all-time peak, and one sentence pointing at the variant menu. This mirrors the Trend stat card printing **Gemischt** rather than a percentage (`docs/progress-charts.md` §"The stat cards describe the selected usage") — the first-to-last delta across several usages measures which usage happened to fall at each end of the range, not progress. The segments go with the trend because a segment magnitude is a first-to-last delta of the same blend; a coach that withholds the percentage but announces "improving, +5.0 kg est. 1RM" has withheld nothing. **The peak and the session count survive**, exactly as the Rekord and Workouts cards do for the combined view. `.combined` over an exercise trained one way keeps its trend — combined *is* that usage, the same clause as `chartsSeveralUsagesTogether`. *Discarded alternative:* a per-usage summary (one progression figure per variant in one narrative). It is more informative on paper, but it asks the ~3B on-device model to keep several numbered series straight in prose, which is the failure mode that forced the workout-analysis surface onto structured output — and the withheld version is the one that cannot contradict the chart.
- **The variant and the period are rendered, not narrated (2026-08-27, device check).** `CoachDeepDiveSurface` draws a caption directly above the narrative reading `<usage label> · gesamte Historie` (`ai_coach.deep_dive.scope.all_time`, en `all time`), built from `ExerciseProgressViewModel.selectedUsageLabel` — so it is *Alle Varianten* on the combined view, and **`nil` where `showsUsagePicker` is false**, since on an exercise trained exactly one way that label would name a choice the screen never offers; the caption then prints the scope alone (`ai_coach.deep_dive.scope.all_time_only`). The label is handed down rather than re-derived, which is what `DeepDiveUsage` pairs with the selection: the picker renders `ExerciseUsageLabeling.pickerItems`, which prepends the archived marker and appends a disambiguator (`· zuletzt 12.07.`, `· #2`) where two usages would otherwise read alike, so deriving it from `ExerciseUsage.displayLabel` alone would caption a variant differently from the menu it was picked in. Both facts used to depend on the on-device model and it got both wrong: asked to name the variant it turned `4–6 Wdh. · Pull` into *"die 4-6-**Woche**-Biceps-Curls-Variante"*, reading the German abbreviation for *Wiederholungen* as *Woche* and dropping the routine, and it never mentioned the period at all. **The label is therefore withheld from the prompt entirely** — `ExerciseDeepDiveInput.usageLabel`'s *presence* emits a generic `Variant:` line, its *content* never crosses into the prompt. Do not hand a language model a string you need reproduced verbatim.
- **The deep-dive is all-time, and now says so, rather than being windowed (decided 2026-08-27).** On device with 1M selected the stat card read `+0.0%` while the coach beneath it read `+3%` — both correct, for different periods, neither naming its own. Two ways out, and the app already answered this exact shape once: §"The stat cards name the range they describe" resolved `4 WORKOUTS` vs `7 Einträge` by **naming** each surface's range, not by equalizing them. Same answer here. *Windowing the coach was rejected for two concrete reasons:* the cache key would have to include the timeframe, so every pill tap becomes a cache miss and a **free user's single monthly allowance unit** (`docs/pro-subscription.md` §5e) — one tap on 3M after generating on 1M and they have nothing left for the month; and a deep-dive over 1W has nothing to say (it falls under the four-set/two-session floor and renders `insufficientData`), while the surface's whole value is the long arc — peak, strongest segment, frequency correlation. So the scope stays the reader's complete history for the selected usage, the caption states it deterministically, and the prompt carries `History range (the reader's complete history, not the chart's selected range)` plus a rule forbidding the model from calling its figures "recent" or "the last month".
- **`historyRange` is localized month names.** It was `"2026-07 to 2026-08"`, a machine format handed to a language model, and the model echoed it: *"in den letzten 2026-07 und 2026-08"*. It now uses the same localized `MMMM yyyy` as the peak's `monthLabel` — `"Juli 2026 – August 2026"`, collapsing to one label when both ends share a month. Same failure the workout-analysis surface hit with raw ISO dates (§4).
- **Three further prompt rules came out of the same device check.** (a) The progression figure is an **estimated 1RM, never a weight** — the coach wrote *"Dein Gewicht hat sich um 0.7 kg erhöht"* for a variant whose every set was the same load, where the 0.7 kg was the Epley delta between a 5-rep and a 6-rep best. (b) **No date more precise than the input gives** — it wrote *"erreicht am 20.08.2026"* from an input carrying only `August 2026`. That rule did **not** hold: the same output came back on three later device checks, which is what the structural fix below replaced it with. Both prompts still carry it, as a hint rather than a guarantee. (c) A **German glossary**, as `WorkoutAnalysisInstructions` already carries: variant → *Variante*, never *Variable* (the blended narrative said "Variablen" four times), plus Wiederholungen / geschätztes 1RM / Topsatz / Bestwert, and *Sitzung*/*Training* for a session — the model wrote "im Vergleich zur ersten **Übung**", which means *exercise*. Both prompts also forbid the third person: the blended narrative referred to "der Benutzer" throughout.
- **The narrative stops inventing facts, structurally (2026-08-28).** Four failures survived three rounds of prose rules, measured on device in German on a freshly generated `4–6 Wdh. · Pull` narrative: an invented day (*"erreicht am 20.08.2026"* from an input whose only date was `August 2026`, the "20" plausibly lifted from the `20,0 kg` in the adjacent clause), an invented timeframe (*"in den letzten 6 Monaten"* for a `History range` of `Juli 2026 – August 2026`), invented vocabulary (*"in der Variantsuche"* — not a German word, and not what the control is called), and a single undivided paragraph. All four are one failure: **a prose rule inside an instruction list is a weak lever.** Instructions outrank prompts ("our model is trained to obey instructions over prompts", WWDC25 248) but Apple is explicit that this "is not bulletproof". The fix uses the two levers that are not prose:
  - **The peak is withheld from the model entirely.** `toPromptText()` emits no peak block at all — no weight, no reps, no est-1RM, and above all no month. `ExerciseDeepDiveInput.peakSentence` composes the finished sentence in Swift (`ai_coach.deep_dive.peak`, en+de, figures in the reader's decimal convention) and `CoachDeepDiveSurface` renders it as a fact line below the prose. A month is a date a language model can make more precise, so no month reaches one. This is the same move as the variant label, and the *only* grounding fix on this surface that has ever held: **nothing can mangle a string it never receives.**
  - **The shape moved into the type**, per the `ExerciseDeepDiveOutput` bullet above.
  - **A blended view's progression paragraph is dropped in Swift.** The blended prompt says `LEAVE THIS FIELD OUT ENTIRELY` and the field's `@Guide` repeats it, but `ExerciseDeepDiveViewModel.stream` passes `statesProgression: input.blendedUsageCount <= 1` into `ExerciseDeepDiveNarrative`, which discards the field whatever the model returned. The instructions are the hint; this is the guarantee.
  - **No prompt names a UI control any more.** The blended prompt used to point at "the variant menu at the top of the screen" and the model composed *Variantsuche* for it. It now says a single variant has to be selected and does not say where — the picker is on the same screen, and the caption above the narrative already names the current selection.
  - **Both prompts carry an explicit timeframe rule in all-caps**: the only periods nameable are the `History range` and `Period` values, copied exactly. All-caps is Apple's documented emphasis form (WWDC25 248: the model "will respond well to an all caps command"); Markdown emphasis is not, and is separately forbidden here because the model mirrors its prompt's style into a surface that renders plain text.
  - **Second device round, 2026-08-28 (DE, iPhone).** Every fabrication was gone — no day-level date, no invented timeframe, no `Variantsuche`, no progression figure on the blended view, and every number in the prose was a real input value. Four *new* defects, all in the same family (a field answered minimally, or a prompt label read as data), all fixed by moving the rule onto the field or into Swift:
    - **The `workload` guide opened with `COPY THE INPUT'S 'History range' VALUE EXACTLY AS WRITTEN`, and the model did exactly that and stopped** — the whole paragraph came back as the bare string `Juli 2026 – August 2026`. An all-caps copy order at the head of a field is answered by copying. Every guide now leads with what the paragraph must *say* and demotes the constraint; `workload` adds "a bare date range or a fragment is not an answer".
    - **`progression` was skipped on a single-variant view**, where it is the point of the surface. `String?` was read as discretionary rather than as "absent when there is no data". Its guide now says *required whenever the input contains an `Overall progression` block*, alongside the existing omit-when-blended rule.
    - **`Avg sessions/week: 1.3` came back as "1,3 Wochen pro Sitzung"** — the ratio inverted. The prompt now writes `Training frequency: 1,3 sessions per week`, so there is a phrase to copy rather than a direction to derive.
    - **`Current segment (last 4–8 weeks):` was quoted to the reader as "in den letzten 4–8 Wochen".** That window is the app's bucketing parameter, not a fact about the reader's training. The label is now `Recent segment:` and the real range stays on its `Period:` line — the same lesson as the variant label, applied to a label instead of a value.
    - **Prescriptive advice survived both prompts' ban**: *"ein guter Indikator dafür, dass du deine Intensität etwas reduzieren solltest"*. The rule moved onto `closing`'s own `@Guide` and both prompts now name the exact evasion in all-caps.
    - Also fixed while in there: `ProgressionSegment.magnitude` was built with a non-localized `String(format:)`, so it was the one figure in the prompt the model had to convert rather than copy (`0.7` → `0,7` in German). It now uses the reader's locale like every other figure.
  - **Third device round, 2026-08-29 (DE, iPhone), and the `ios-api-researcher` findings behind the fixes.** The blended view came back clean. The single-variant view produced its worst failure yet — *"Der geschätzte 1RM ist von **87,5 kg** im ersten Training auf **88,2 kg** im letzten Training gestiegen"*, for a reader whose actual best is 20,0 kg — plus formal *Sie* throughout, a third round of prescriptive advice, and broken German (*"Zuwächssumme"*, *"Der letzte Trainingseinheit … war zugeordnet"*).
    - **The fabricated figures had two causes, and the instruction literal was the second.** The *first* was a demand this surface's own design created: the prompt labelled the block `Overall progression (first → most recent session):` and the field guide asked for "how the estimated 1RM changed from the first session to the most recent" — **naming two endpoints the input has never carried.** It holds a delta and a percentage, nothing else. Asked for an endpoint, the model supplied one. The label is now `Overall progression across the whole history — a change only; no starting or ending 1RM value is available:`, the key is `Estimated 1RM change:`, and the guide says NEVER NAME A FIRST OR MOST-RECENT 1RM FIGURE. This is the ticket's own rule turned on itself: *never describe an output shape that presupposes data the prompt might not carry.*
    - **The second cause was a worked numeric example inside the instructions.** The copy-exactly rule read *"If the input says `87.5 kg`, output `87.5 kg` — not 85, not 87"*; the model lifted `87.5` and derived `88.2` from it plus the real `+0,7 kg`. Instructions are placed verbatim in the prompt, so an example number is indistinguishable from an input number. **No prompt on this surface may carry a data-shaped literal** — a number, a date or a frequency that could pass as data — and a regex test fails the build if one returns. `blendedViewPrompt` is the control: it has never carried one and has never invented a figure. Apple does not document this failure mode, but its own Landmarks sample guards against it with `"Here is an example, but don't copy it:"`, and the few-shot guidance already warns that "overly long or complex examples can lead to repetition or hallucination".
    - **Binding, and load-bearing for every coach surface:** Apple documents on-device models as *"not intended for tasks requiring basic math, code generation, or complex logical reasoning"* ([Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)). `88.2 = 87.5 + 0.7` was arithmetic. Hand the model finished figures to rephrase; never a starting point and a delta to combine.
    - **`.greedy` was removed from this surface.** It was adopted as "deterministic decoding for a surface whose whole job is to restate figures" and never delivered that — the invented date, the invented timeframe and the fabricated `87,5 kg` all happened under it. Apple documents the cost plainly: greedy responses "are statistically likely, but **may lack the human-like quality and variety of other sampling strategies**" ([`SamplingMode.greedy`](https://developer.apple.com/documentation/foundationmodels/generationoptions/samplingmode-swift.struct/greedy)), and every Apple example pairs `.greedy` with a categorical task (the `ImageLabel` enum sample), never with free narration. The German symptoms — an invented compound noun and broken agreement — are exactly that documented tradeoff. Grounding is carried by structure now, not by decoding: facts pre-resolved in Swift, shape in the type, prompts free of data-shaped literals. **Consequence: output is no longer reproducible for a given input**, so a regenerate genuinely re-rolls.
    - **The formal register had to be forbidden by name, and placed adjacent to the language directive.** Naming "du" as the preferred form inside a twenty-bullet list produced *Sie* throughout. The rule is now the **first line of both prompt bodies**, directly under the prepended `You MUST respond in German.`, which is where Apple's documented locale phrasing sits. Apple documents no register/formality control at all — this is placement and emphasis, per its "use emphasis with words like 'must' or 'do not', and repeat key instructions" guidance.
    - **Prescriptive advice, third occurrence, now attacked at the subject rather than the prohibition.** The advice always attached to `closing`, whose assigned subject — comparing two training frequencies — invites "…which suggests you should". That field is now told to state what the figures *are* and never what they *mean for future training*, and both prompts name the evasions ("this suggests you should…", "it might be worth…", "in order to avoid…") alongside rest/deload/injury. **If it recurs, the documented next step is not a fifth prose round**: Apple's [safety doc](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output) prescribes output verification before returning a response, and its classification recipe is a small `@Generable enum` session — so a second-pass `containsAdvice` classifier gating the prose is the escalation. Not built: it is a second model call per generation, and it should not be added before the cheaper fix has had a device check.
  - **Fourth device round, 2026-08-29 — every correctness criterion passes.** `du`-form throughout, no 1RM endpoint values, no prescriptive advice, three real paragraphs on the single variant and two on the blended view, frequency stated the right way round, no day-level date, peak line correct, and every figure on screen a real input value. What remained was German word choice and completeness, fixed with glossary-class rules rather than more grounding rules: invented compounds ("Zuwächsspanne", "Verbesserungsszenario") answered by naming the plain forms; "Variation" joining "Variable" on the forbidden list; the unit made mandatory on every frequency figure after *"von 1,3 auf 1,2 reduziert"* read as a session count; and the blended `workload` field told to carry ALL THREE of its facts after sampling variance dropped the variant count. **The glossary is the lever with a proven record on this surface** — *Variante* vs *Variable* has held since ticket 01 — and is a different class from the grounding rules this section warns against repeating.
  - **Honest record on `.greedy`'s removal:** justified by Apple's documented fluency tradeoff, but the German coinages survived it, so the fluency win did not clearly materialise on one sample. What it did introduce is content variance — the blended view dropped a fact it had stated under greedy. The removal stands on the documentation (every Apple `.greedy` example is categorical; greedy never delivered the grounding it was adopted for), but restoring it is a one-line revert in `AICoachService.streamExerciseDeepDive` if reproducibility proves to matter more than variety.
  - **Fifth device round, 2026-08-29 — signed off.** Single variant and blended view both clean: `du`-form, no fabricated figure, no endpoint value, no prescriptive advice, no day-level date, frequency carrying its unit (*"1,2 Mal pro Woche"*), the blended view naming its variant count again, and the peak line correct. Two of the three glossary fixes took — *Zuwachs* and *Phase* replaced the invented *Zuwächsspanne* and *Verbesserungsszenario*.
  - **Residue, accepted rather than fixed** (quality, not correctness; all acceptance criteria passed):
    - **"Variationen" still appears** for *Varianten*, in the same narrative that uses *Variante* correctly one clause later — so the glossary line forbidding it did **not** take, unlike the two compound-noun fixes beside it. A German reader understands it; it is merely off-vocabulary and inconsistent with the picker label *Alle Varianten*. Worth knowing that a glossary entry is not reliable just because a neighbouring one is.
    - **Gender slip** — *"Die geschätzte 1RM"* where the glossary says *geschätztes 1RM* (neuter).
    - **A real figure used in an adjacent slot**: *"In der aktuellen Phase hast du eine Zuwachsrate von 3% erreicht"* reuses the overall percent for the recent segment. Not a fabrication — the figure exists in the input — and on a two-month history the two periods largely coincide, so it is not demonstrably wrong. **Watch it on an exercise with a long history**, where the overall and recent figures genuinely differ; if it misattributes there, the fix is to stop putting two percentages in one prompt, not another prose rule.
  - **The through-line of all five rounds.** Six failures, six *different* levers, and **not one was fixed by writing a stronger prose rule**: the invented day by withholding the peak's month entirely; the invented timeframe by removing the window from the app's own prompt label; the undivided block by moving shape into the `@Generable` type; the fabricated `87,5 kg` by deleting an instruction literal *and* by no longer asking for an endpoint the input never held; the formal *Sie* by forbidding it by name adjacent to the language directive; the prescriptive advice by changing the field's *subject* from what figures mean to what they are. When this surface misbehaves again, the question to ask is what the structure is inviting — not how to word the prohibition more firmly.
  - **What the tests can and cannot prove.** `GymStreakTests/ExerciseDeepDiveGroundingTests.swift` pins the structure: no peak figure or peak month in the prompt, no day-level date in either locale (regex over `\d{1,4}[./-]\d{1,2}[./-]\d{2,4}`), the peak sentence carrying the peak's own figures in the reader's convention, and a blended narrative dropping a progression paragraph handed to it. **Adherence itself is a device check** — whether the model obeys a `@Guide` is not something a unit test can assert.

- **Known, tracked separately: the coach speaks kg while the app may be set to pounds.** The aggregator builds its input in kg and nothing converts, so a screen headlined `44,1 lb` carries a narrative saying `20.0 kg × 6`. This affects every AI Coach surface, not just the deep-dive, and needs `WeightUnit` threaded into the AI input layer — its own ticket. Since 2026-08-28 the peak line is app-composed (`ai_coach.deep_dive.peak`) rather than model prose, so it is now the cheapest place to close the gap — one string and one key, once `WeightUnit` reaches `ExerciseDeepDiveInput`. It deliberately still says kg, because fixing one line and leaving the prose in kg would be worse than one consistent divergence.
- **Selection changes retire the narrative on screen, and the probe runs once.** `ExerciseProgressChartView` builds a `DeepDiveUsage` from `viewModel.resolvedUsage` (never `selectedUsage`) and renders no coach section while that is `nil` — `updateUsage` clears it on the tap, so between a usage tap and the reload landing there is no button to press: generating there would have spent a monthly allowance unit on a narrative for the variant the user just left. It also resets the deep-dive ViewModel from `.onChange(of: viewModel.requestedUsage)` — the *request*, which changes on the tap, not `selectedUsage`, which only catches up when the reload lands, so the stale sentences never outlive the tap that invalidated them. Its `.task` is keyed on `DeepDiveContext(exerciseId:usage: viewModel.resolvedUsage)`, and `resolvedUsage` is `nil` until a load has answered which usage is charted (`docs/progress-charts.md`). Keying on `selectedUsage` instead ran `checkCache` twice per screen open — once against the `.combined` placeholder, once against the answer — and each run is a history fetch queued on the same model actor as this screen's chart load. `checkCache` still spends no allowance in any of this; only `generate`/`regenerate` do.
- **Still divergent: counterweight semantics.** `buildDataPoints` runs raw Epley over the entered number, while `buildProgress` inverts it through `ExerciseLoadMetrics.effectiveWeight` for `.counterweightAssistance`. So on an assisted exercise the coach still reads *rising assistance* as progress where the chart reads it as regression. Out of scope for the usage fix and not caused by it; the homogeneity filter above at least guarantees the series is all one kind of number.
- Covered by `GymStreakTests/ExerciseDeepDiveUsageTests.swift`: a two-usage exercise whose selected usage's count and trend differ from the blend's, the picker's label **never** reaching the prompt while a generic `Variant:` line does, a one-usage exercise emitting no `Variant:` line at all, `.combined` dropping any label handed to it, the history range being localized month names rather than a machine format, a blended `.combined` emitting no progression and no `Classification` line, `.combined` over one usage keeping its trend, a mixed-`loadBehavior` history filtered to the live behaviour, and the cache key both distinguishing usages and staying put when a *different* usage is trained.
- **The aggregation runs on the History model actor, and one generation walks history once (ticket 02, 2026-08-28).** `ExerciseDeepDiveAggregator` is a plain synchronous `nonisolated` type, and its only caller used to be the `@MainActor` `ExerciseDeepDiveViewModel` — so under SE-0461 (`SWIFT_APPROACHABLE_CONCURRENCY`) the entire unbounded fetch and relationship walk executed on the main actor, twice per generation (once for the narrative, once for the cache key) and a third time on the post-stream cache write. `checkCache` did the same on the screen's `.task`, i.e. on appear and on every exercise or usage switch, with no `.preparing` skeleton in front of it. The resolved shape:
  - **`ExerciseDeepDiveFactProviding`** (`Domain/Interfaces/AICoach/`) is the read boundary. `ExerciseDeepDiveViewModel` holds one and **never sees a `ModelContext`**; nothing that crosses is a `PersistentModel`, so the exercise travels as `id` + `name` and the answers come back as `ExerciseDeepDiveAggregate` (`Domain/Models/AICoach/`), a plain `Sendable` value pairing the prompt input with the cache timestamp.
  - **`SwiftDataHistorySnapshotProvider` conforms to it**, and its two new methods carry **`@concurrent` on the concrete type** — never only on the protocol requirement, since SE-0461 is silent on witnesses (`docs/swift6-concurrency.md` §1, §9b). This is the same `@ModelActor` that serves this screen's chart (`fetchExerciseProgress`), chosen deliberately over a third `ModelContext`: the narrative is read from the very sessions the chart above it is drawn from, so a separate actor would fault the same graph twice for one screen. The precedent is `LifetimeTrainingTotalsProviding` — a second protocol on the same concrete type.
  - **`buildAggregate` answers both questions from one fetch.** The prompt input and the cache timestamp come off the same `CompletedSessionFetch.withFullGraph` result, and `run` carries the resulting key through the cache check, the regeneration invalidation and the post-stream save. That helper's "model-actor only" warning is now satisfied rather than tolerated, and `buildInput` traverses the whole graph anyway (every session, every matching row, every completed set, plus a second all-time pass for `.combined`), so the prefetch makes its cost smaller rather than larger.
  - **The appear-time probe stays a separate, cheap fetch.** `lastCompletedSetTimestamp` still keeps its own newest-first `FetchDescriptor<WorkoutSession>` with `relationshipKeyPathsForPrefetching = [\.workoutExercises]` — one direct key path, the documented use, as in `CompletedSessionFetch.withRoutine` — and returns at the *first* matching session. Being off the main actor did not make it free: it shares the History actor with the chart load happening on the same screen at the same moment, so materializing the whole database to read one session would queue in front of it. Both paths derive the timestamp through one shared `hasCompletedSet` rule so they cannot key on different rows; `aggregateTimestampAgreesWithTheProbe` pins that. The newest-first sort is written at the site that depends on it and pinned by a test asserting the combined key *changes* when a later workout is logged; reversed, the key would freeze at the oldest session and narratives would stop invalidating.
  - **Pinned by two cases in `SwiftDataHistorySnapshotStoreTests`** — `exerciseDeepDiveAggregationKeepsMainActorResponsive` and `deepDiveCacheProbeKeepsMainActorResponsive`, both through the existential, both against 240 seeded sessions. Verified by deleting the `@concurrent` once (see `docs/swift6-concurrency.md` §1): the build stays green and the main actor stalls **311 ms**.
  - **Device-verified 2026-08-28**, which is the half the tripwire tests cannot cover: opening and switching exercises with a long history no longer stutters, generation streams normally, a cached narrative re-reads instantly without spending an allowance unit, each variant keeps its own cache across a switch-and-switch-back, and logging a new set of the described variant retires it while logging a set of another variant does not.
  - **`ExerciseDeepDiveViewModel.cacheKey` is a static pure function** taking the timestamp, and its `ISO8601DateFormatter` is a `static let`. It used to allocate one per call on the `.task` path — rule 2 of the rendering rules.

### 4. Workout Analysis

- **Entry**: `WorkoutDetailView` (tapping a past workout in the Verlauf/History tab). A `.task` silently checks cache on appear and whether a previous same-routine session exists. If yes, `CoachWorkoutAnalysisButton` ("Ask the Coach") is shown below the stats grid. When the button is showing (no cache hit), `AICoachService.prewarm()` is called so the model weights are warm before the user taps.
- **Comparison logic**: `WorkoutAnalysisAggregator.buildInput` finds the most recent previous `WorkoutSession` with the same `routineName` (case-insensitive). Receives per-exercise comparison data as a `comparisons:` parameter, resolved by `WorkoutAnalysisViewModel` through `ExerciseProgressProviding` before the aggregator runs (audit P1.6 — it previously constructed `ExerciseProgressService` ad hoc and ran that scan on the main actor). Comparisons are matched to exercises by `workoutExerciseId`, not by position. Also detects new PRs via the Epley formula — **only for exercises with prior history** (`priorBestByKey` lookup must hit; a first-time exercise trivially "beats" a nonexistent baseline and must not count as a PR) — and counts exercises done last time but skipped this session (`droppedExerciseCount`, matched by `stableKey`).
- **Data gates**: analysis suppressed when (a) fewer than 2 completed sets, (b) no previous same-routine session, (c) completion below 40% (`minimumCompletionThreshold` — an aborted workout produces a meaningless comparison), (d) every exercise is first-time (nothing to compare), (e) AI Coach unavailable or workout detail preference off. Gates (a)/(c)/(d) surface as the generic `insufficient_data` copy if the button was already visible.
- **Layout**: `CoachWorkoutAnalysisSurface` replaces the button after tap (cross-fade, `.animation(.easeInOut(0.3), value: state)` on the section). Renders the structured output: headline (15 pt semibold) → 1–4 highlight rows (trend icon in a tinted circle + exercise name + one-line detail) → dimmed closing sentence. `minHeight: 200`, header label `ai_coach.workout_analysis.header_label` (localized). Trend icon mapping: improved `arrow.up.right` (accent green), declined `arrow.down.right` (warning orange), unchanged `equal`, mixed `arrow.up.arrow.down`, new `plus`, still-streaming `ellipsis`.
- **States**: `WorkoutAnalysisViewModel.AnalysisState` includes `.preparing` — set **synchronously** in `generate()`/`regenerate()` before the async pipeline starts, so the surface (with skeleton bars in every content slot) appears on the same frame as the tap. Without it the button sat frozen through availability check (up to 2 s sleep when model not ready), aggregation, and time-to-first-token. Missing fields during streaming render as `AISkeletonBar` placeholders inside the same layout, so the card fills in progressively instead of jumping.
- **Cache key**: `workoutId.uuidString`, filename prefix `workout_analysis_v4_` — workout content is immutable once saved, so the key never changes. The version suffix is bumped whenever the content design changes (v2: fact-based redesign; v3: first-time-exercise exclusion + glossary, both July 2026; v4: Swift-composed headline, 2026-08-29): the struct still decodes old entries, so a filename bump (not decode failure) is what orphans pre-redesign caches and forces regeneration. The v4 bump is load-bearing rather than hygienic — a v3 file decodes cleanly into `WorkoutAnalysisNarrative` and would keep serving the generated headline the bump exists to retire. **Format migration**: even older caches stored `{narrative}`; decode failure in `AICoachCache` returns `nil` (treated as a cache miss), so those also silently regenerate — no migration code needed.
- **System prompt file**: `WorkoutAnalysisInstructions.swift`.
- **Output struct**: `WorkoutAnalysisOutput` — `exerciseHighlights: [WorkoutAnalysisHighlight]` (1–4 via `.minimumCount/.maximumCount` guides) and `closingObservation`; **no `headline`**, see the grounding entry below. What the cache and the screen hold is `WorkoutAnalysisNarrative` (Codable: the Swift-composed headline + those two generated fields), which is why `WorkoutAnalysisOutput` is deliberately not `Codable` — the same split as `ExerciseDeepDiveOutput` / `ExerciseDeepDiveNarrative`. Each highlight: `exerciseName`, `trend: WorkoutAnalysisTrend` (a native `@Generable enum: String, Codable`, copied from the input verdict tags), `detail` (one short sentence). The view consumes `WorkoutAnalysisContent` (plain Equatable struct mapped from the output / its `PartiallyGenerated` snapshots in the ViewModel) so FoundationModels types never reach the view layer.
- **Why structured output (research finding)**: the ~3B on-device model produced garbled free-text narratives — mixed units ("Wiederholungen um 30 kg"), echoed raw ISO dates, invented words ("Gesamtwertung"), unscannable walls of text. The free-form `narrative: String` approach was discarded. The `@Generable` schema constrains each field to one short sentence and forces the trend classification through a `@Generable` enum, leaving the model only the phrasing. Supporting input change: raw ISO dates replaced by `daysSincePrevious: Int` (the model echoed dates verbatim, prompt now forbids mentioning dates at all).
- **Fact-based content redesign (July 2026)**: the first structured version still let the model *choose* what to say — the headline was contractually about total volume (a metric users don't care about) and the per-exercise `detail` was composed by the model from raw per-set lines, which it tended to echo as bare stats ("37.5 kg x 6 reps") with no comparison. Both were replaced by fully pre-resolved facts computed in Swift (`WorkoutAnalysisInput.toPromptText()`): a **Headline fact** chosen by priority (new PR > all/majority improved > all/majority declined > unchanged > mixed, e.g. `"3 of 4 exercises improved"`) and one **Fact line per exercise** that leads with the top set — the number a lifter actually cares about (`"top set +2.5 kg: now 37.5 kg x 6 reps, was 35 kg x 6 reps"`, rep gains at same weight, extra sets). Raw per-set lines and all volume figures were removed from the prompt entirely so the model cannot fall back to echoing them; the system prompt now forbids mentioning total volume and reduces the model's job to translating/rephrasing the fact lines in the user's language. Verdict classification was also fixed so MIXED is reachable (weight up + reps down or vice versa was previously reported as IMPROVED/DECREASED by summed-weight sign alone). Edge cases fed as prompt notes: cut-short sessions (completion < 70% → closing must say "cut short", missing sets must not read as strength loss), skipped exercises (`droppedExerciseCount`), and first-time exercises — all three may be mentioned in the closing only. The closing observation additionally bans hedged praise-and-criticize sentences without a concrete fact.
- **First-time exercises are not content (user feedback, July 2026)**: "Erste Übung in dieser Routine" as a highlight is irrelevant to the user, and a first-time exercise falsely triggered the PR headline (no prior best to beat). First-timers are now excluded from PR detection (aggregator), excluded from the prompt's per-exercise fact list (they appear only as a "done for the first time" note), and forbidden as highlights by prompt + `@Guide`. Consequently `exerciseHighlights` allows `.minimumCount(1)` (was 2) so a session with a single comparable exercise doesn't force the model to invent a second highlight.
- **Translation glossary (user feedback, July 2026)**: the model left English fitness terms in German output ("Bestset", "Topset"). The system prompt now carries an explicit German glossary (top set → Topsatz, reps → Wiederholungen, PR → Bestwert, …) and states that "Topset"/"Bestset" are not words. **Exercise names are carved out of that rule** — see the next entry for why.
- **The headline is composed in Swift, not generated (device check, 2026-08-29)**: the surface headlined *"Neuer Bestwert bei Bankdrücken: 16 kg x 7 Wiederholungen."* for a session in which Bankdrücken was never trained — the routine's Bankdrücken slot had been swapped for its alternative *Flying Chest* (which matched its last session), and the figures were *Dip*'s real PR, correctly listed under Dip in the highlight rows directly below. Two causes, both in the prompt: the glossary rule above said "translate **every word** into the target language", which an English exercise name in a German sentence reads as an instruction to Germanise it; and the only German exercise name available was `Bankdrücken`, from the worked headline example in the very same instruction block (`"Neuer Bestwert bei Bankdrücken: 82,5 kg x 5."`). The closing sentence repeated the same substitution — the same failure mode as the deep-dive's `87,5 kg`, lifted from a worked example there. **The fix is structural, not another prompt rule**: `WorkoutAnalysisInput.headlineSentence` composes the sentence in Swift from a `WorkoutAnalysisHeadline` case (PR > all/majority improved > all/majority declined > unchanged > mixed) via `ai_coach.workout_analysis.headline.*` strings (en+de, locale-aware decimals, no trailing `,0`), `WorkoutAnalysisNarrative` carries it through the cache, and `headline` is gone from `WorkoutAnalysisOutput` — nothing can mangle a string it never receives. The same English fact still reaches the prompt as a `Session summary:` line (renamed from `Headline fact:`) purely as context for the closing sentence. Three prompt changes back the fields the model still owns: exercise names are the one explicit exception to the translate-everything rule, the prompt now contains **no example exercise name at all**, and the copy-exactly order moved onto the `exerciseName` `@Guide` and the `closingObservation` `@Guide` where the deep-dive found field-level constraints hold better than list items. Pinned by `GymStreakTests/WorkoutAnalysisHeadlineGroundingTests.swift` (structure only — adherence in the fields the model still writes stays a device check).
- **Discarded, 2026-08-29: three further attempts to improve the model's own two fields.** With the headline fixed, the closing sentence restated it, so the prompt was changed to mark the summary line as already-read, then to ask for "something else", then the instructions were cut to three paragraphs with every worked example deleted, the locale directive added and the token cap raised. Each round made the card worse on device, in a new way: a fabricated exercise ("Pull-ups") and Germanised names ("Deckelpresse", "Seitheben") when the closing was asked for novelty with no facts left to state; then tautological details ("Topsatz 16 kg x 7 Wiederholungen: jetzt 16 kg x 7 Wiederholungen") under the added prohibitions; then, with the examples gone, English spans copied straight out of the prompt ("16 kg x 7 reps", "Topset 32 kg x 12 reps"). **All of it was reverted** — the surface is the state described above and nothing more. Two things are worth keeping from it: the tautology appeared in a run whose examples were *unchanged*, so it was the added prohibitions and not the examples (Apple recommends 2–15 **simple** examples, and zero is not the safe end of that range); and a `PartiallyGenerated` optional property is `String?`, not `String??` — the snapshot flattens, verified by compiling `let x: String? = partial.closingObservation`. If this surface is revisited, the option researched and not taken is `DynamicGenerationSchema(name:description:anyOf: [String])` + `GenerationSchema(root:dependencies:)` + `session.streamResponse(to:schema:)`, which constrains a string field at the decoding level to a runtime value set — the only hard guarantee available for `exerciseName`, at the cost of typed `@Generable` decoding and `PartiallyGenerated` streaming.
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
- Deep-dive entries are keyed per **(exercise, usage, last-set timestamp)** and auto-invalidate via that timestamp, which is itself resolved for the selected usage. Filenames carry an `exercise_deep_dive_v2_` prefix and store `ExerciseDeepDiveNarrative` — the generated paragraphs plus the Swift-composed peak sentence, which has to be persisted because the appear-time cache probe fetches only a timestamp and never re-walks history.
- Workout analysis entries are permanent (keyed by immutable `workoutId`).
- **A unit switch does not invalidate anything.** Cached copy keeps the unit it was written
  in, and so does a chat turn already on screen; every subsequent generation uses the new
  unit. Regenerating instead would spend a free user's monthly allowance unit
  (`docs/pro-subscription.md` §5e) to rewrite text they have already read, for a rare
  one-time act whose own remedy is one tap on Regenerate. See
  `docs/weight-unit-preference.md` §13.
- **Format migration**: `AICoachCache.load` returns `nil` on a decode failure and the surface treats it as a miss, so a changed output shape needs no migration code. Bump the filename prefix anyway when the shape changes (`period_recap_v2_`, `exercise_deep_dive_v2_`, `workout_analysis_v4_`): a silent miss costs a free user a monthly allowance unit (`docs/pro-subscription.md` §5e), and a deliberate bump makes that a decision instead of an accident.

---

## Prompt grounding rules (binding, all surfaces)

These are properties of **every** coach prompt and every `@Guide`, not of one surface. They are
pinned by `GymStreakTests/CoachPromptGroundingTests.swift`, which scans all five coach surfaces
(post-workout recap, workout analysis, period recap, coach chat, and the deep dive — six prompt
strings, since the deep dive has two variants, and the three unit-parameterised ones are scanned in
both `kg` and `lb`) plus all four generation schemas. A green test
proves the *prompt* is clean; it can never prove the *output* is. That is always a device check.

### 1. No prompt carries a data-shaped literal

**No system prompt or `@Guide` may contain a number, date, frequency or exercise name that could
be mistaken for the reader's own data.** Instructions are placed verbatim into the prompt, so an
example number is indistinguishable from an input number, and a ~3B on-device model does not
distinguish them.

This is measured, not theoretical. `ExerciseDeepDiveInstructions` taught its copy-exactly rule
with a worked example — *"If the input says `87.5 kg`, output `87.5 kg` — not 85, not 87"* — and
on a device check (German, iPhone, 2026-08-29) the model lifted that literal out of the
instructions and presented it as the reader's training data: *"Der geschätzte 1RM ist von 87,5 kg
im ersten Training auf 88,2 kg im letzten Training gestiegen"*, for a reader whose actual best is
20,0 kg. The `88,2` was the real `+0,7 kg` delta added to the invented base. The same class of
failure produced a generated headline naming `Bankdrücken` for a session that did not contain it —
an exercise name lifted from a worked example. The control case was `blendedViewPrompt`, which has
never carried such a literal and has never invented a figure across five device rounds.

**How the rule is satisfied** (2026-08-30, `.scratch/ai-coach-prompt-literals` ticket 01):

- **State the rule abstractly.** The copy-exactly rule is now the same sentence on every surface:
  *"Copy each figure digit for digit, including its decimal separator. Do not round it, shorten
  it, or hedge it with 'about' or 'around'."* Same rule, nothing to copy.
- **Where an example teaches phrasing, strip the value out of it.** The German sentence patterns
  in `WorkoutAnalysisInstructions` and `PeriodRecapInstructions` exist to teach *phrasing*, not
  numbers, so their figures became `<Gewicht>` / `<Wdh>` / `<Anzahl>` / `<Übung>` placeholders and
  the pattern list is introduced as *"every angle-bracket placeholder is filled from the input and
  never with a value of your own"*. The unit word beside the placeholder still carries the
  reader's active unit (see § "The weight unit").
- Apple's documented alternative — prefixing an example with *"Here is an example, but don't copy
  it:"*, from the Landmarks sample — is the **second** choice, not the first. Apple's own few-shot
  guidance warns that *"overly long or complex examples can lead to repetition or hallucination"*
  ([Prompting an on-device foundation model](https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model)),
  and a pattern that still shows a plausible weight is still a literal the model can lift.

**Corollary — a figure the model copies must already be the figure the reader should see.**
Rule 1's abstract phrasing is *"copy each figure digit for digit, including its decimal
separator"*, and the model obeys that literally. Prompt figures used to be rendered in the C
locale (`en_US_POSIX`), so on device (German, 2026-08-30) the post-workout recap wrote *"ein
Gesamtvolumen von 1830.0 kg"* and the Rückblick wrote *"+10.0 kg geschätztes 1RM"* and *"2.0
Einheiten pro Woche"* — English decimal points inside German sentences. Every narrating surface
now writes its figures in the reader's own convention, which is what `ExerciseDeepDiveInput` has
always done:

- `AICoachUnitVocabulary.compact(_:in:locale:)`, `.decimal(_:in:locale:)` and
  `.plainDecimal(_:locale:)` all take the reader's locale.
- They format in the C locale and substitute **only the decimal separator** (`fixed(_:places:locale:)`).
  `String(format:locale:)` cannot be used directly: given a locale it also inserts grouping
  separators, turning an all-time tonnage into `1,234,567.8`, and German groups with the period
  while separating decimals with the comma — so `1.830,0` would put *two* locale-dependent
  characters into a string the model is told to copy character for character.
- Call sites: `PostWorkoutRecapInput.toPromptText`, `WorkoutAnalysisInput.toPromptText` (via its
  private `fmt`, threaded through `exerciseVerdict` / `promptFact` / `signed`),
  `PeriodRecapAggregator.buildTrends` and `buildRecommendation`, and
  `PeriodRecapInput.toPromptText`'s consistency line.
- Pinned by `germanPromptFiguresCarryTheGermanSeparator` (no `\d\.\d` anywhere in a German
  prompt, in both units) and `englishPromptFiguresKeepThePeriod` (the rule is "the reader's
  separator", not "always a comma", and never a grouping separator).

**The chat is deliberately excluded.** `ChatFactBuilder`'s fact lines are uniformly English by
design and the chat prompt tells the model to translate everything it is handed, including
weekday and month names — a different contract from "copy verbatim". It has not been observed
emitting an English separator into a German answer; if it ever does, the fix is the same one.

**What the scan does not cover, and why that is currently safe.** It reads the four *output*
generation schemas, not the `@Guide`s on the `@Generable` **input** structs — several of which do
carry data-shaped literals (`ExerciseDeepDiveInput`'s `'May 2024 – April 2026'` and `'March 2026'`,
`PostWorkoutRecapInput`'s `e.g. +12 or -8`). Those guides never reach a model: `AICoachService`
sends an input only as `input.toPromptText(...)` text and never hands an input's generation schema
to the session. **If that ever changes, those guides reintroduce exactly the bug this section
exists to prevent** — extend the scan at the same time.

**One deliberate exception, and one deliberate non-exception.** The chat prompt's ambient
`Today is <weekday, d MMMM yyyy>.` line carries a real four-digit year — it is genuine input, the
fact that makes "next workout" resolvable as "tomorrow", and the test strips exactly that line
before scanning. `CoachChatInstructions` does still carry example *exercise names*
("Bankdrücken", "Chest Press") in its translation and `__NO_MATCH__` rules; they are kept because
every chat answer is grounded in a tool result that names the exercise, and the rules are about
name handling and unteachable without one. If chat ever names an exercise the user does not have,
this is the first place to look.

### 2. No prompt asks the model to combine figures

Apple documents the on-device models as *"not intended for tasks requiring basic math, code
generation, or complex logical reasoning"*
([Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)),
and the fabricated `88,2 kg` was arithmetic. Every narrating surface hands the model **finished
values to rephrase**, never a base and a delta, and says so in the prompt: *"Every fact is already
resolved in the input. Never compute, combine, or re-interpret numbers yourself."* The chat prompt
states the same rule as *"Never do arithmetic yourself and never invent numbers."* Where a surface
needs a value picked out of several — the post-workout recap's muscle-group observation — the
percentages are pre-resolved in `toPromptText` and the prompt asks only for a *selection* ("pick
the one furthest from zero, in either direction"), never a computation.

### 3. No prompt names a programming construct

**Never write `nil`, `null`, `None` or "empty string" in a prompt or a `@Guide`.** Apple describes
`@Guide(description:)` as "effectively another way of prompting", so `nil` inside one is a *word to
write*, not an absence to produce.

Measured on device (German, 2026-08-30): `PeriodRecapOutput.correlationHighlight` was described as
*"Return nil when the input has no detected patterns … nil means the UI hides this section"*, and
for a period with no detected patterns the model wrote the four-character string `nil` into the
field. The Auffälligkeiten card rendered it verbatim, under the `MUSTER` label.

An absent field is asked for in plain language instead — *"OMIT THIS FIELD ENTIRELY … do not
return it empty, return nothing for it"* — matching the wording that already worked on
`blendedViewPrompt`'s `progression`. The prompt deliberately does **not** enumerate the forbidden
placeholder words ("do not write 'nil' or 'none'"), because naming a token in an instruction is
the very mechanism rule 1 exists to prevent; it describes the class instead ("never fill it with a
placeholder word, a dash, or a sentence explaining the absence").

**The schema was never the problem.** `@Generable` defaults to
`representNilExplicitlyInGeneratedContent: false`, which Apple documents as "nil properties are
omitted entirely" — the model had a real, constrained-decoding-supported affordance to skip the
key and chose not to use it. Wording, not schema, is the lever.

### 4. Presence is decided in Swift wherever Swift knows

A prompt rule is a request; a Swift-side drop is a guarantee. Where the app already knows whether
a field can exist, it does not leave the decision to the model:

- **`PeriodRecapViewModel`** passes `hasDetectedPatterns` (from `sampleInput.correlations`) into
  `stream(...)` and drops `correlationHighlight` outright when the input carries no "Detected
  patterns" section — the model's answer for that field is never rendered.
- **`CoachCorrelationSanitizer.sanitized(_:)`** (`Domain/Services/AICoach/`) rejects an answer
  that is *only* a placeholder token (`nil`, `null`, `none`, `keine`, `-`, …, matched against the
  **whole trimmed string**, never as a substring, so a real sentence containing "none" survives)
  and an answer that is an apology ("no correlation", "keine Auffälligkeiten", …). It is pure
  `String? -> String?` with no state, which is why it lives in `Domain/` rather than on the
  ViewModel. Applied at three sites: the streamed partial and the final output in
  `PeriodRecapViewModel`, and **`AICoachCache.loadPeriodRecap`** — the persisted format is the
  Data layer's concern, so every reader of `AICoachCaching.loadPeriodRecap` inherits the guard
  instead of having to remember it. The cache path matters because recaps written before this
  guard existed still hold a literal `nil`, and a cache entry is never regenerated just because
  its prose is stale.
- **`PeriodRecapAggregator.buildCompactInput`** keeps `correlations` at `prefix(1)`, never
  `prefix(0)`. `hasDetectedPatterns` is derived from the *full* input, so a compact fallback that
  emptied the array would leave the flag claiming a "Detected patterns:" block the prompt no
  longer has. Non-empty must stay non-empty.
- **`ExerciseDeepDiveNarrative`** drops the `progression` paragraph on a blended view whatever the
  model returned — the original instance of this pattern.

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

**Applied in Workout Analysis**: `@Generable` struct output (`[WorkoutAnalysisHighlight]` / closing; the headline is Swift-composed and not a generated field), `.minimumCount`/`.maximumCount` on the highlights array, and a native `@Generable enum WorkoutAnalysisTrend` for the per-exercise direction. The earlier `.anyOf` string for `trend` was replaced by the enum (same model-level guarantee, no string→enum mapping or invalid-value fallback in the ViewModel). Sources: Apple docs `foundationmodels/generationguide`, `foundationmodels/generable`, and `generating-swift-data-structures-with-guided-generation`.

---

## Streaming

- `LanguageModelSession.ResponseStream<T>` yields `Snapshot` values at ~30 Hz (~33 ms intervals).
- Each snapshot's content is accessed via `snapshot.content` (type: `T.PartiallyGenerated`). Fields are `String?` until that field begins generating.
- Render each snapshot in full (snapshot = cumulative state, not delta).
- Fields in `@Generable` structs stream in strict declaration order (framework-guaranteed). Field N is fully complete before field N+1 starts.
- `StreamingTextView` renders `text` **directly** as a `Text` view — no internal word-by-word timer. A blinking 7×14 pt accent cursor appears inline at the tail while `isStreaming == true`. `.animation(nil, value: text)` suppresses height-interpolation animations between snapshots.
- The old `wordDelay` parameter is now a no-op (source-compatible, no effect).
- `AISurface` shows a shimmer border gradient and a pulsing dot + `"writing"` label while `isStreaming == true`.
- **`AISkeletonLines(count:)`** (next to `AISkeletonBar`) is the paragraph-shaped placeholder every streaming coach surface draws while it waits: full-width bars with a short last line. `CoachDeepDiveSurface` and `AIRecapInline` both use it; it was extracted when the post-workout recap's `.preparing` state would have become the third hand-rolled copy of the same `VStack(spacing: 8)` of 12 pt bars.
- **`AISkeletonBar` shimmer — never animate `Gradient.Stop.location`, and don't animate a gradient's `startPoint`/`endPoint` either (fixed 2026-08-28)**: the bar originally animated a `phase` value into each stop's `location` and wrapped it with a modulo `clamp()` helper. That made the locations non-monotonic as soon as `phase > 0` (at `phase = 0.6`: `0.6, 0.1, 0.6`), which triggered the Xcode runtime warning *"Gradient stop locations must be ordered"* and made the highlight jump instead of travel. `LinearGradient(stops:)` requires monotonically ascending locations and has **no wrap-around/repeating stop mode** — the modulo approach is unfixable, not mis-tuned. The bar is now a `white04` base with a fixed `[clear, accent10, clear]` highlight band in an overlay, swept by `.offset(x: (phase * 2 - 1) * proxy.size.width)` under the usual `withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false))` — the same pattern the watch's `ShimmerView` already uses (`GymStreakWatch Watch App/Views/RoutineDetailView.swift`). Travelling exactly one bar width off each edge means the band is fully clear of the bar at both ends of the cycle, so the wrap is invisible. **The loop is re-armed by `.onDisappear { phase = 0 }`, not by the reset inside `startAnimation`**: both writes in `startAnimation` happen in one synchronous scope, so SwiftUI coalesces them and never renders the intermediate `0` — on a reappearance where `@State phase` survived at `1` (Reduce Motion toggled off mid-skeleton, a pop-back onto a still-loading screen) the offset would be `+width` both before and after, giving a zero delta, no installed animation, and a flat bar. The `onDisappear` reset lands in its own update, so the rendered offset is genuinely back at `-width` before the next appearance. **Two discarded approaches, both of which compile clean and fail silently at runtime** (researched 2026-08-28, verified against Apple's documentation JSON and Developer Forums, *not* blog posts): (a) **animating the gradient's `startPoint`/`endPoint`** — the obvious-looking fix, and the one implemented first. `LinearGradient` conforms only to `Sendable, SendableMetatype, ShapeStyle, View`; it has **no `Animatable` conformance**, so SwiftUI diffs the two gradients as a discrete swap and never interpolates. `UnitPoint` *is* `Animatable`, but that conformance is inert unless a containing type exposes it through its own `animatableData`, which `LinearGradient` does not. An Apple DTS engineer reproduced exactly this non-animating gradient swap in [forums thread 775746](https://developer.apple.com/forums/thread/775746). This is the dangerous one: with the highlight living only in the interpolated mid-states, a snap leaves a permanently flat bar that looks like an intentional static design. (b) **`.phaseAnimator` with `nil` returned for the wrap-back transition** — per [forums thread 792541](https://developer.apple.com/forums/thread/792541), a phase transition with no effective animatable change **stalls the loop**; DTS called this expected behaviour and a gap in SwiftUI. Apple documents `nil` only as "the transition doesn't animate" and says nothing about the loop still advancing. Also checked and rejected: `TimelineView(.animation)` and `.keyframeAnimator` re-invoke their content closure every frame, wrong for a component instantiated many times per skeleton screen; and `.redacted(reason:)` offers only `.placeholder`/`.privacy`/`.invalidated` — **iOS 26 still ships no built-in animated shimmer/skeleton style**. Note that `AISurface`'s border shimmer uses the same phase-into-`location` trick but keeps its locations ordered (`0+phase … 1.0+phase`), so it never warned — though at `phase = 1.0` every location is ≥ 1.0 and the border collapses to a flat colour before snapping back. Same class of bug, visual only, deliberately left alone.

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
- **Info**: "How the Coach works" (sheet with placeholder *copy* — the strings are localized, the content is still a stand-in) and "About Apple Intelligence" (opens Apple Support URL).
- Footer disclaimer (monospaced, on-device privacy statement).

When device is ineligible (`!availability.isAvailable`), an unavailability banner appears and the master toggle is disabled (0.55 opacity).

---

## Watch App

The Watch app is unaffected. FoundationModels is not available on watchOS. All AI surfaces are iOS-only. No watch-specific AI code was introduced in any wave.

---

## Localization

- German (`de.lproj/Localizable.strings`) and English (`en.lproj/Localizable.strings`) are both maintained.
- German is the locale the coach copy was originally *written* in, but **English is the app's fallback**: `CFBundleDevelopmentRegion` is `en`, so any device whose preferred-language list contains neither German nor English resolves to `en.lproj`. Do not treat German as a default for anything.
- All AI Coach keys are grouped under `// MARK: - AI Coach` at the bottom of both files.
- Keys follow the pattern `ai_coach.<surface>.<element>`.
- Interpolated strings use `String(format: "key".localized, arg1, arg2)` following the codebase's existing pattern.
- The `locale` field is embedded in every aggregator's `toPromptText(in:)` output as `Locale.current.identifier` (e.g. `de_DE`). **`Locale.current` is constrained to the bundle's available localizations**, not the raw system language — verified on a simulator whose preferred language is French: `Locale.current.identifier` comes back as `en_DE`, never `fr_*`. So this field can only ever be `en_*` or `de_*`, and it always agrees with the language the UI is rendering in.
- Output language is steered by `AICoachLocaleDirective.lines(forLocaleIdentifier:)`, which names the language in English ("You MUST respond in German.") per Apple's Foundation Models guidance — it does **not** ask the model to parse a `de_*`/`en_*` condition, which is what the reverted earlier rule did (see the type's own doc comment for the German the condition-parsing version produced). The directive short-circuits to an empty string only for exactly `en_US`; other English regions (`en_DE`, `en_GB`) get a redundant but harmless "You MUST respond in English."
- The same constraint governs the `locale.identifier.hasPrefix("de")` branches in `PeriodRange.label(locale:)` and `PeriodRecapAggregator.buildCorrelations` — they are binary German-or-English by construction and cannot be reached with a third language.
- **No coach string is hardcoded in a view.** `HowItWorksSheet`'s body and close button and the unavailability banner's accessibility label were German literals until 2026-09-04, rendering German to English users; they are now `ai_coach.how_it_works.body`, `action.close` and `ai_coach.settings.unavailable_banner.cta.accessibility`.
- **No coach string bakes a unit word into its value.** `ai_coach.deep_dive.peak` and `ai_coach.workout_analysis.headline.pr{,_multiple}` — the only coach copy the app composes itself — take a preformatted weight via `%@`, per `docs/weight-unit-preference.md` §7.

---

## Privacy

All inference runs on-device via Foundation Models. No prompt text, no narrative text, and no workout data is transmitted to any server. Every AI surface shows an `AIPrivacyFooter` with a lock icon and the message "Generated on your iPhone · Data never leaves the device". The Settings screen footer reiterates this in full.

---

## Known defects, found and not fixed

Surfaced by the `ai-coach-prompt-literals` device rounds (German, iPhone, 2026-08-30) and by the
architecture review of that work. None was in that ticket's scope — it was the literal-leak class
only — so all are recorded here rather than buried with the archived ticket.

1. **The post-workout recap states the planned set count, not the completed one.**
   `PostWorkoutRecapAggregator` passes `session.totalSetsCount`, which is
   `workoutExercisesList.flatMap(\.setsList).count` — every set, completed or not. A session whose
   own summary read `8/20 (40%)` was narrated as *"mit einem Gesamtvolumen von 1980,0 kg und 20
   Sätzen"*. The volume is right (it sums completed sets); the count is not. This is a **factual
   error in generated copy**, so it is the most serious entry here. Fix is a completed-set count in
   the aggregator, not a prompt change.
2. **Workout analysis can emit several highlights for the same exercise.** A device check returned
   four highlights, all `Arnold Press`, three of them restating the same top-set change. The prompt
   asks for "the 1–4 most notable exercises" and `@Guide` bounds the array at 1…4, but nothing
   dedupes by exercise name — neither the prompt nor `WorkoutAnalysisViewModel`. A Swift-side
   uniquing pass on `exerciseHighlights` is the reliable fix; a prompt rule alone has failed on
   this surface before.
3. **Workout analysis wrote "Topset".** `WorkoutAnalysisInstructions` names this exact word as one
   that does not exist and mandates "Topsatz"; the model used it anyway. A glossary line in the
   instruction list is evidently not enough — the same lesson as the paragraph-count rule that
   moved into `@Guide`s.
4. **The period-recap headline leaks English.** `PeriodRecapInput.toPromptText` appends
   `" (\(improved.count) exercises improved in total)"` to the headline fact, and the model
   translated it only partway: *"(4 Übungen verbessert in total)"*. Either drop the parenthetical
   or compose it in Swift like `WorkoutAnalysisInput.headlineSentence` already does.
5. **`WorkoutAnalysisAggregator.findPreviousSession` matches on the denormalized `routineName`
   string, not the routine id.** Renaming a routine orphans it from its own history, so the first
   analysis after a rename reports "nothing to compare". This also means a report of "no Coach
   analysis on a new workout" is only correct behaviour if the routine was *not* renamed.
6. **`PeriodRecapInput.recommendationFact`'s `@Guide` still reads "nil when none was detected".**
   Harmless today — `AICoachService` sends inputs only as `toPromptText(...)`, so an input's
   generation schema never reaches a model — but it is the same wording that made the model write a
   literal `nil` into `correlationHighlight`. If that type is ever used as a generation *output*,
   this is the bug, pre-made. See § "Prompt grounding rules", rule 3.

## TODO (next phase)

- Weekly bar chart inside Period Recap's stat strip.
- PR count in the Period Recap stat strip (currently shows "-" as a placeholder; requires efficient PR query).
- Share-as-image for Period Recap output.
- UITest coverage for all three surfaces.
- "How the Coach works" info sheet — the copy is still a placeholder (`HowItWorksSheet` in `AICoachSettingsView.swift`); its strings are localized (`ai_coach.how_it_works.body`), so replacing it is a strings-file edit, not a code change.
- "About Apple Intelligence" info sheet — currently opens external Apple Support URL; may become in-app.
