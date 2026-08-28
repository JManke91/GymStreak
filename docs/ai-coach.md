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

Because the defaults resolve to the production singletons, these three arguments never appear at a view call-site. Tests inject fakes conforming to the three protocols instead.

**The one dependency that is *not* defaulted is the Pro allowance gate.** Since the P4/P5 taster (docs/pro-subscription.md §5e), `PeriodRecapViewModel` and `ExerciseDeepDiveViewModel` take a required `allowanceGate: AICoachAllowanceGate` first parameter. It carries the entitlement and the paywall seam, which per Hard rule 2 come from `AppDependencies.makeAICoachAllowanceGate(for:)` and never from a singleton — so both screens gained a thin outer view (`PeriodRecapView`, `ExerciseProgressChartView`) that reads `@EnvironmentObject AppDependencies` and hands the gate to the real, private screen. `PostWorkoutRecapViewModel` and `WorkoutAnalysisViewModel` take no gate: those two surfaces are free and unmetered by design.

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
- **Navigation**: `PeriodRecapView` hides the system navigation bar (`.toolbar(.hidden, for: .navigationBar)`) for its custom top bar, which also disables the native leading-edge swipe-back. It therefore applies `.swipeBackEnabled()` (2026-08-24) — see `docs/progress-charts.md` § "The screen keeps the native swipe-back gesture" for the root cause, why no pure-SwiftUI fix exists, and the iOS 26 second recognizer.
- **Editorial layout**: headline (large bold text) → stat strip (sessions / volume / new PRs) → `AISurface` trends section → correlation card (orange gradient border, `PATTERN` label) → closing `AISurface` → `AIPrivacyFooter(.full)`.
- **Skeleton loading**: full layout skeleton shown while `.loading` state is active; transitions to partial content as fields arrive.
- **Cache key**: `"\(range.rawValue)|\(rangeStartISO)|\(lastWorkoutInPeriodISO)"`, filename prefix `period_recap_v2_` (bumped with the fact-based redesign so old entries regenerate).
- **System prompt file**: `PeriodRecapInstructions.swift`.
- **Output struct**: `PeriodRecapOutput` — `headline`, `trendsNarrative`, `correlationHighlight: String?` (Optional), `closingSentence`.
- **Fact-based content redesign (July 2026, same doctrine as Workout Analysis)**: the first version let the model narrate freely — the headline restated total volume/session counts (redundant with the stat strip directly above and a metric the user doesn't care about), the trends narrative rambled and produced contradictions ("Plateau erreicht, wobei die Gewichte zurückgegangen sind" — because plateaued trends still carried a kg delta in the prompt), and the closing was pure motivational filler. Now `PeriodRecapInput.toPromptText()` resolves everything in Swift: a **Headline fact** (strongest est-1RM gain > declines > steady plateau), trend groups where **plateaued exercises are serialized by name only** (no delta → no contradiction fodder), a **Consistency line** (weeks trained of weeks covered, avg sessions/week, longest gap, regular/irregular flag — running periods only count elapsed weeks), and a **Closing fact**. The system prompt reduces the model to rephrasing, bans total volume and hype words (bemerkenswert/beeindruckend/spannend/…), and requires contradiction-free trend sentences.
- **Consistency + recommendation (July 2026)**: `ConsistencyMetrics` (totalWeeks/trainedWeeks/avgSessionsPerWeek/longestGapDays/isIrregular; irregular = skipped weeks or a gap ≥ 9 days) feeds the prompt. `buildRecommendation` resolves **at most one actionable suggestion**, only when stagnation demonstrably coincides with irregularity: (1) the adherence correlation fired (dips followed low-frequency weeks) → "keep frequency steady at ~X/week", or (2) training irregular AND no exercise improved → "more evenly spaced sessions". The closing fact is then marked as a recommendation and the system prompt allows a suggestion **only there** — the general no-prescriptive-advice rule stays for everything else. This is a deliberate product decision (user request): the Rückblick may give one concrete training-consistency recommendation; medical/nutrition advice remains banned.
- **`correlationHighlight` is `String?`**: the field is schema-Optional so the model produces `null` (not an empty string) when no correlation data is present. The UI skips the card entirely when `nil`. A belt-and-suspenders heuristic (`isApologeticCorrelation`) in `PeriodRecapViewModel` additionally filters explicit "nothing found" phrasing ("keine Zusammenhänge", "no correlation", …). The earlier subject-matching heuristic (short text without a known exercise name → apologetic) was **removed**: the pre-written pattern statements are short and contain no exercise names, so it would have suppressed every real finding once the model started reproducing them verbatim.
- **Stream cancellation**: `PeriodRecapViewModel` stores the active stream in a `streamTask: Task<Void, Never>?`. `setRange`, `load`, `generateNow` and `regenerate` all cancel the previous task before starting a new one. The for-await loop guards on `Task.isCancelled` and does not surface output after cancellation.
- **Month label**: `PeriodRange.label(locale:)` formats `.thisMonth`/`.lastMonth` with `Date.FormatStyle` (`.locale(locale).month(.wide).year()`), not a `DateFormatter`. It is read from view bodies (title block, range chips, the free-tier offer card), where allocating a formatter is forbidden by the main-thread rules, and a cached `static let` formatter is not an option because `Domain/` stays isolation-agnostic and has no actor to hold a per-locale cache. `Date.FormatStyle` is a `Sendable` value usable from any isolation domain and honours the passed-in `locale` — which matters because `PeriodRecapAggregator` calls this with an explicit locale to build the model's prompt, not only for display. A hardcoded per-language month table was tried first and rejected for exactly that reason.
- **Free-tier metering (P4)**: two states — `.offer(HeadlineMetrics?)` and `.gated(HeadlineMetrics?)`, both rendered by `PeriodRecapAllowanceCard` — exist only for a metered user. On the free tier the screen never generates on arrival: `load`/`setRange` land on `.offer` with a "Generate recap" button, because one recap a month is a single irreversible choice and opening the screen (or following the proactive month-boundary prompt) must not be what spends it. `generateNow` is the only path that consumes; `regenerate` asks the gate before invalidating the cache so a refusal leaves the cached recap on screen. A cached recap, an unavailable device and an insufficient period are all resolved *before* the meter is touched. See docs/pro-subscription.md §5e.

### 3. Exercise Deep-Dive

- **Entry**: `ExerciseProgressChartView`. A `.task(id: DeepDiveContext(exerciseId:usage:))` silently checks cache once the screen's load has resolved which usage is charted, and again whenever the exercise or that usage changes. If no cache hit, `CoachDeepDiveButton` ("Ask the Coach") is shown below the chart card and `AICoachService.prewarm()` is called so the model is warm before the tap.
- **Tap responsiveness**: `DeepDiveState` includes `.preparing`, set synchronously in `generate()`/`regenerate()`. `CoachDeepDiveSurface` renders the streaming chrome with three `AISkeletonBar` rows while in `.preparing` or while the streamed text is still empty, and the button→surface swap cross-fades (`.animation(.easeInOut(0.3), value: state)`).
- **Paragraph break handling**: `CoachDeepDiveSurface` renders the full narrative as a single `StreamingTextView`. SwiftUI's `Text` renders `\n\n` as a native paragraph break. The previous multi-`StreamingTextView` split-on-`\n\n` approach caused visible layout growth during streaming as each double-newline introduced a new view.
- **Layout reservation**: both `streamingSurface` and `successSurface` apply `.frame(minHeight: 260, alignment: .topLeading)` so the chrome reserves space immediately and does not snap from a sliver to full height on the first token.
- **Stream cancellation**: `ExerciseDeepDiveViewModel` stores the active stream in a `streamTask: Task<Void, Never>?`. `generate` and `regenerate` are now synchronous fire-and-forget (not `async`). `cancel()` is called from `ExerciseProgressChartView.onDisappear` and from its `resetDeepDive()` (exercise or usage switch).
- **Free-tier metering (P5)**: `generate`/`regenerate` return `Bool` — `false` means the free monthly allowance is spent, the gate raised `.exerciseDeepDive`, and the state was left untouched so the "Ask the Coach" button stays where it was instead of collapsing into an empty surface behind the paywall. `checkCache` never touches the meter: a narrative already generated is free to re-read forever. `regenerate` asks the gate *before* invalidating the cache. See docs/pro-subscription.md §5e.
- **Cache key**: `"\(exerciseId.uuidString)|\(usageSelection.cacheToken)|\(lastSetTimestampISO)"` — auto-invalidates next time a new set of *that usage* is logged. The usage token is `ExerciseUsageSelection.cacheToken` (`all`, or `\(slotUUID)#\(occurrence)` / `unattributed#\(occurrence)`), defined on the value itself so there is one spelling of it. The timestamp half is resolved for the same usage, so training the light slot does not invalidate the heavy slot's narrative. **Both halves matter to the user's wallet**: without the token, switching usage serves the previous usage's sentences and switching back re-generates, and a free user pays a monthly allowance unit per generation (§5e). Adding the token orphaned every pre-2026-08-27 cached narrative — deliberately, because those were computed over the blend.
- **Output language: English instructions plus Apple's documented directive — *not* translated instructions (researched 2026-08-28).** German output read like literal machine translation: *"die die gesamte Zeitraum"*, *"des Bizeps-Curls-Übens"*, *"unterschiedlichen Trainingsschritten und **Zielgruppen**"* (*target audiences*, for rep-range goals), *Variation* and *Variante* used interchangeably one sentence apart despite a glossary line, and a "write exactly 2 paragraphs" rule ignored. **Writing the system prompts in German was implemented first and reverted**: Apple's [*Supporting languages and locales with Foundation Models*](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models) documents the opposite — "start with the exact phrase in English, which comes from the model's training, and reduces the possibility of hallucinations in multilingual situations", with `"You MUST respond in <language>."` as the pattern. English instructions with an explicit directive is the *supported* path, not a workaround, and there is no Apple guidance for translating instructions. `AICoachLocaleDirective.lines(forLocaleIdentifier:)` prepends `The person's locale is de_DE.` + `You MUST respond in German.` (language named in English, for the same reason), and returns `""` for US English — the model's own default, exactly as Apple's `localeInstructions(for:)` sample does. The old conditional rule ("write in the language indicated by the `locale` field") was removed: it asked the model to evaluate a condition instead of stating the answer.
- **`GenerationOptions(sampling: .greedy)` on this surface.** `.greedy` "always chooses the most likely token… deterministic output for a given input", and Apple uses it for its own must-not-hallucinate classification sample. Right for a surface whose entire job is restating figures it was handed. Applied to the deep-dive only; the other coach surfaces are unchanged and unverified. Caveat from WWDC25 session 301: determinism holds only for a given on-device model version, so an OS update can still change the wording.
- **Figures are written in the reader's own convention.** `toPromptText()` formats decimals with `String(format:locale:)` — `26,5 kg` for a German reader, `26.5 kg` for an English one — so the model copies rather than converts. A separator conversion is one more transformation it can get wrong, and `20.0 kg` beside a UI reading `44,1 lb` looks foreign.
- **Instructions were trimmed** toward Apple's "one to three paragraphs" guidance for prompts and instructions (*Prompting an on-device foundation model*, *Managing the context window*): instructions are placed verbatim in the prompt, so a long rule list spends context that instruction-following itself needs. The worked-anecdote parentheticals went; the load-bearing rules stayed, with all-caps emphasis on the critical negative constraint (WWDC25 session 248: the model "will respond well to an all caps command").
- **Recommended next, not done here** (from the same research): split `ExerciseDeepDiveOutput.narrative: String` into two or three `@Guide`-described `String` fields. Apple's documented mechanism for controlling output *shape* is guided generation, and no `@Guide` constraint enforces sentence or paragraph counts inside one `String` — which is why "exactly 2 short paragraphs" is ignored. Also unshipped: gating on `SystemLanguageModel.default.supportsLocale(_:)`, which is preferred over inspecting `supportedLanguages` because it accounts for language fallbacks, and would turn a `LanguageModelError.unsupportedLanguageOrLocale` into a clean unavailable state.
- **Two system prompts, not one with an exception** (`ExerciseDeepDiveInstructions.swift`, 2026-08-28). `systemPrompt(forBlendedView:)` returns `singleVariantPrompt` or `blendedViewPrompt`, chosen in `AICoachService.streamExerciseDeepDive` by `input.blendedUsageCount > 1`. The blended prompt never mentions progression, segments, percentages or frequency at all. **This replaced an "Exception — BLENDED VIEW" bullet inside the single-variant prompt, which failed on device:** given an input holding no trend, no segment and no frequency, the model followed the dominant four-paragraph progression structure and *invented* the missing figures — "1.5 kg mehr geschätztes 1RM", "zwischen 22.5 kg und 24.5 kg", "2.2 pro Woche", a "3-wöchige Phase zwischen April und Juni 2026". Fabricated numbers are strictly worse than the blended trend this feature withholds: that one was at least arithmetically real. A ~3B model will complete the shape its instructions describe, so the fix is to leave no shape — not to add a louder prohibition. Pinned by `blendedViewGetsItsOwnInstructions`, which asserts the blended prompt contains none of the progression vocabulary.
- **Output struct**: `ExerciseDeepDiveOutput` — single `narrative: String` field.
- **`findPeak` PR definition**: `ExerciseDeepDiveAggregator.findPeak` selects the session with the highest **raw weight** (ties broken by reps), matching the chart's PR marker. Previously it used max est-1RM, which could surface a lower raw weight than the chart's PR stat.
- **Exercise identity is `ExerciseProgressAggregator.matches(_:exerciseId:exerciseName:nameIsUnique:)`, not a local copy (fixed 2026-08-25).** `buildInput` resolves `nameIsUnique` once from the live `Exercise` library and hands it to `buildDataPoints`. This aggregator previously carried its own `matchesExercise` that applied the legacy name fallback (`exerciseId == nil` + case-insensitive name match) **without** the uniqueness gate the other three aggregators enforce. Where a library holds two exercises with the same display name — e.g. "Biceps Curls" as barbell and dumbbell — that claimed every ambiguous pre-`exerciseId` row for *both* of them. Found on a device check: the coach narrated *"in den letzten 19 Sitzungen … -43% Gesamtfortschrittsrate"* beside a chart and a Fortschritt row that both read 15 workouts, with the trend computed across two different exercises' loads. Double-counting is strictly worse than the drop the chart performs, and unlike the drop it is **not** repaired by the legacy-history attribution flow (`docs/progress-charts.md`) — an attributed row simply stops matching the other variant, whereas an ambiguous one was being counted twice. Pinned by `GymStreakTests/ExerciseDeepDiveIdentityTests.swift`, verified to fail against the ungated rule (8 sessions instead of 4, and a 40 kg barbell peak reported for the dumbbell exercise).
- **The cache-key query is on the same rule (fixed 2026-08-25).** `lastCompletedSetTimestamp` matched `we.exerciseId == exerciseId || we.exerciseId == nil` — no name check at all — so *any* legacy row with a completed set in the newest session advanced this exercise's cache key, however unrelated. A moved key is a cache miss, and for a free user a miss spends a monthly allowance unit (§5e) regenerating a narrative that had not changed. It now calls the shared rule, resolving the name and uniqueness from the live library; where the live entry is gone it matches on id alone, which is the conservative half of the rule.
- **The deep-dive describes the usage the screen is showing (fixed 2026-08-27).** `buildInput` takes the `ExerciseUsageSelection` the exercise detail screen has already resolved — handed down from `ExerciseProgressViewModel.selectedUsage`, never re-derived, because two resolutions could disagree — and applies the chart's remaining two filters alongside identity: `ExerciseUsageResolver.keyedRows(in:matching:)` + `belongs(_:to:)` for the usage, and `workoutExercise.loadBehavior == liveBehavior` for load-behaviour homogeneity. All three now live in one `RowFilter` value inside the aggregator, used by `buildInput`, `buildDataPoints` and `lastCompletedSetTimestamp` alike. Before this the coach folded every usage of an exercise into one series and narrated an est-1RM trend over the blend. Found on a device check: `Biceps Curls (Kurzhantel)` with `4–6 Wdh. · Pull` selected read **20.0 kg / +0.0% / 6 Workouts**, while the coach directly beneath it narrated *"in den letzten **15** Sitzungen … +4.4 kg … +22%"*. Both numbers were arithmetically right for what they measured, and nothing said they measured different things — the coach is the surface **most** likely to be believed, because it speaks in full sentences. The `loadBehavior` half matters on its own: a uniquely-named exercise whose library load behaviour changed after some workouts were logged otherwise had a narrative mixing counterweight *assistance* values with physical loads (`docs/assisted-exercise-progress.md`).
- **A blended `.combined` view states no progression at all.** `blendedUsageCount` is `options.count` for `.combined` and `1` for a selected usage; when it exceeds 1, `buildInput` returns `overallProgression`, `strongestSegment` and `currentSegment` as `nil`, `toPromptText()` emits a `BLENDED VIEW` block instead of the figures, and the system prompt switches to a two-paragraph shape: how much work is recorded, the all-time peak, and one sentence pointing at the variant menu. This mirrors the Trend stat card printing **Gemischt** rather than a percentage (`docs/progress-charts.md` §"The stat cards describe the selected usage") — the first-to-last delta across several usages measures which usage happened to fall at each end of the range, not progress. The segments go with the trend because a segment magnitude is a first-to-last delta of the same blend; a coach that withholds the percentage but announces "improving, +5.0 kg est. 1RM" has withheld nothing. **The peak and the session count survive**, exactly as the Rekord and Workouts cards do for the combined view. `.combined` over an exercise trained one way keeps its trend — combined *is* that usage, the same clause as `chartsSeveralUsagesTogether`. *Discarded alternative:* a per-usage summary (one progression figure per variant in one narrative). It is more informative on paper, but it asks the ~3B on-device model to keep several numbered series straight in prose, which is the failure mode that forced the workout-analysis surface onto structured output — and the withheld version is the one that cannot contradict the chart.
- **The variant and the period are rendered, not narrated (2026-08-27, device check).** `CoachDeepDiveSurface` draws a caption directly above the narrative reading `<usage label> · gesamte Historie` (`ai_coach.deep_dive.scope.all_time`, en `all time`), built from `ExerciseProgressViewModel.selectedUsageLabel` — so it is *Alle Varianten* on the combined view, and **`nil` where `showsUsagePicker` is false**, since on an exercise trained exactly one way that label would name a choice the screen never offers; the caption then prints the scope alone (`ai_coach.deep_dive.scope.all_time_only`). The label is handed down rather than re-derived, which is what `DeepDiveUsage` pairs with the selection: the picker renders `ExerciseUsageLabeling.pickerItems`, which prepends the archived marker and appends a disambiguator (`· zuletzt 12.07.`, `· #2`) where two usages would otherwise read alike, so deriving it from `ExerciseUsage.displayLabel` alone would caption a variant differently from the menu it was picked in. Both facts used to depend on the on-device model and it got both wrong: asked to name the variant it turned `4–6 Wdh. · Pull` into *"die 4-6-**Woche**-Biceps-Curls-Variante"*, reading the German abbreviation for *Wiederholungen* as *Woche* and dropping the routine, and it never mentioned the period at all. **The label is therefore withheld from the prompt entirely** — `ExerciseDeepDiveInput.usageLabel`'s *presence* emits a generic `Variant:` line, its *content* never crosses into the prompt. Do not hand a language model a string you need reproduced verbatim.
- **The deep-dive is all-time, and now says so, rather than being windowed (decided 2026-08-27).** On device with 1M selected the stat card read `+0.0%` while the coach beneath it read `+3%` — both correct, for different periods, neither naming its own. Two ways out, and the app already answered this exact shape once: §"The stat cards name the range they describe" resolved `4 WORKOUTS` vs `7 Einträge` by **naming** each surface's range, not by equalizing them. Same answer here. *Windowing the coach was rejected for two concrete reasons:* the cache key would have to include the timeframe, so every pill tap becomes a cache miss and a **free user's single monthly allowance unit** (`docs/pro-subscription.md` §5e) — one tap on 3M after generating on 1M and they have nothing left for the month; and a deep-dive over 1W has nothing to say (it falls under the four-set/two-session floor and renders `insufficientData`), while the surface's whole value is the long arc — peak, strongest segment, frequency correlation. So the scope stays the reader's complete history for the selected usage, the caption states it deterministically, and the prompt carries `History range (the reader's complete history, not the chart's selected range)` plus a rule forbidding the model from calling its figures "recent" or "the last month".
- **`historyRange` is localized month names.** It was `"2026-07 to 2026-08"`, a machine format handed to a language model, and the model echoed it: *"in den letzten 2026-07 und 2026-08"*. It now uses the same localized `MMMM yyyy` as the peak's `monthLabel` — `"Juli 2026 – August 2026"`, collapsing to one label when both ends share a month. Same failure the workout-analysis surface hit with raw ISO dates (§4).
- **Three further prompt rules came out of the same device check.** (a) The progression figure is an **estimated 1RM, never a weight** — the coach wrote *"Dein Gewicht hat sich um 0.7 kg erhöht"* for a variant whose every set was the same load, where the 0.7 kg was the Epley delta between a 5-rep and a 6-rep best. (b) **No date more precise than the input gives** — it wrote *"erreicht am 20.08.2026"* from an input carrying only `August 2026`. (c) A **German glossary**, as `WorkoutAnalysisInstructions` already carries: variant → *Variante*, never *Variable* (the blended narrative said "Variablen" four times), plus Wiederholungen / geschätztes 1RM / Topsatz / Bestwert, and *Sitzung*/*Training* for a session — the model wrote "im Vergleich zur ersten **Übung**", which means *exercise*. Both prompts also forbid the third person: the blended narrative referred to "der Benutzer" throughout.
- **Known, tracked separately: the coach speaks kg while the app may be set to pounds.** The aggregator builds its input in kg and nothing converts, so a screen headlined `44,1 lb` carries a narrative saying `20.0 kg × 6`. This affects every AI Coach surface, not just the deep-dive, and needs `WeightUnit` threaded into the AI input layer — its own ticket.
- **Selection changes retire the narrative on screen, and the probe runs once.** `ExerciseProgressChartView` builds a `DeepDiveUsage` from `viewModel.resolvedUsage` (never `selectedUsage`) and renders no coach section while that is `nil` — `updateUsage` clears it on the tap, so between a usage tap and the reload landing there is no button to press: generating there would have spent a monthly allowance unit on a narrative for the variant the user just left. It also resets the deep-dive ViewModel from `.onChange(of: viewModel.requestedUsage)` — the *request*, which changes on the tap, not `selectedUsage`, which only catches up when the reload lands, so the stale sentences never outlive the tap that invalidated them. Its `.task` is keyed on `DeepDiveContext(exerciseId:usage: viewModel.resolvedUsage)`, and `resolvedUsage` is `nil` until a load has answered which usage is charted (`docs/progress-charts.md`). Keying on `selectedUsage` instead ran `checkCache` twice per screen open — once against the `.combined` placeholder, once against the answer — and each run is a full history fetch on the main actor. `checkCache` still spends no allowance in any of this; only `generate`/`regenerate` do.
- **Still divergent: counterweight semantics.** `buildDataPoints` runs raw Epley over the entered number, while `buildProgress` inverts it through `ExerciseLoadMetrics.effectiveWeight` for `.counterweightAssistance`. So on an assisted exercise the coach still reads *rising assistance* as progress where the chart reads it as regression. Out of scope for the usage fix and not caused by it; the homogeneity filter above at least guarantees the series is all one kind of number.
- Covered by `GymStreakTests/ExerciseDeepDiveUsageTests.swift`: a two-usage exercise whose selected usage's count and trend differ from the blend's, the picker's label **never** reaching the prompt while a generic `Variant:` line does, a one-usage exercise emitting no `Variant:` line at all, `.combined` dropping any label handed to it, the history range being localized month names rather than a machine format, a blended `.combined` emitting no progression and no `Classification` line, `.combined` over one usage keeping its trend, a mixed-`loadBehavior` history filtered to the live behaviour, and the cache key both distinguishing usages and staying put when a *different* usage is trained.
- **Both fetches run on the main actor, and they are deliberately different fetches.** `buildInput` is synchronous and nonisolated, and its only caller (`ExerciseDeepDiveViewModel.run`) is `@MainActor`, so under SE-0461 the whole aggregation executes on main. It is user-tap-initiated behind the `.preparing` skeleton, which is why it has not surfaced as a hang. It uses `CompletedSessionFetch.withFullGraph`: that helper is documented model-actor-only because it materializes the entire workout graph, but `buildInput` traverses that whole graph anyway (every session, every matching row, every completed set, plus a second all-time pass for `.combined`), so the prefetch makes its cost smaller rather than larger. **`lastCompletedSetTimestamp` must not share it** — it runs from `checkCache` on the screen's `.task`, i.e. appear-time work, and returns at the *first* matching session, so paying for the whole database to read one session is the `docs/history-performance.md` hang bought for nothing. It therefore keeps its own newest-first `FetchDescriptor<WorkoutSession>` with `relationshipKeyPathsForPrefetching = [\.workoutExercises]` — one direct key path, the documented use, as in `CompletedSessionFetch.withRoutine`. Its newest-first sort is written at the site that depends on it and pinned by a test asserting the combined key *changes* when a later workout is logged; reversed, the key would freeze at the oldest session and narratives would stop invalidating. **The right fix for the main-actor half is still to move `buildInput` behind a model actor** (ticket 02), as `SwiftDataHistorySnapshotStore` does for the chart — deliberately not done in this slice, which was a correctness fix. Until it lands, do not add a second `withFullGraph` caller here.

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
- Deep-dive entries are keyed per **(exercise, usage, last-set timestamp)** and auto-invalidate via that timestamp, which is itself resolved for the selected usage.
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
