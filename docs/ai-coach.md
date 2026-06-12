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

### File map

```
GymStreak/
  Models/AICoach/
    AICoachOutputs.swift              — @Generable + Codable output structs (4 surfaces)
    PostWorkoutRecapInput.swift       — input struct + toPromptText()
    PeriodRecapInput.swift            — input struct + toPromptText()
    ExerciseDeepDiveInput.swift       — input struct + toPromptText()
    WorkoutAnalysisInput.swift        — input struct + toPromptText()
  Services/AICoach/
    AICoachAvailability.swift         — SystemLanguageModel availability mapping
    AICoachPreferences.swift          — UserDefaults-backed preferences (@Observable)
    AICoachService.swift              — central façade, streamPostWorkoutRecap / streamPeriodRecap / streamExerciseDeepDive / streamWorkoutAnalysis
    AICoachCache.swift                — disk-backed JSON cache (Application Support/AICoachCache/)
    AICoachTelemetry.swift            — os.Logger wrapper (no prompt or narrative text logged)
    PostWorkoutRecapAggregator.swift  — builds PostWorkoutRecapInput from a WorkoutSession
    PeriodRecapAggregator.swift       — builds PeriodRecapInput from a date range
    ExerciseDeepDiveAggregator.swift  — builds ExerciseDeepDiveInput from historical sets
    WorkoutAnalysisAggregator.swift   — builds WorkoutAnalysisInput from a workout vs. previous same-routine
    ProactivePromptCoordinator.swift  — decides when to show the proactive period recap card
    SystemPrompts/
      PostWorkoutRecapInstructions.swift
      PeriodRecapInstructions.swift
      ExerciseDeepDiveInstructions.swift
      WorkoutAnalysisInstructions.swift
  ViewModels/AICoach/
    PostWorkoutRecapViewModel.swift
    PeriodRecapViewModel.swift
    ExerciseDeepDiveViewModel.swift
    WorkoutAnalysisViewModel.swift
  Views/AICoach/
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
      AICoachSettingsView.swift       — gear-icon settings screen from History toolbar
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
- **Cache key**: `"\(range.rawValue)|\(rangeStartISO)|\(lastWorkoutInPeriodISO)"`.
- **System prompt file**: `PeriodRecapInstructions.swift`.
- **Output struct**: `PeriodRecapOutput` — `headline`, `trendsNarrative`, `correlationHighlight: String?` (Optional), `closingSentence`.
- **`correlationHighlight` is `String?`**: the field is schema-Optional so the model produces `null` (not an empty string) when no correlation data is present. The UI skips the card entirely when `nil`. A belt-and-suspenders heuristic (`isApologeticCorrelation`) in `PeriodRecapViewModel` additionally filters out any short apology-text that slipped through (text under 120 chars that contains none of the known exercise/muscle-group names is treated as `nil`).
- **Stream cancellation**: `PeriodRecapViewModel` stores the active stream in a `streamTask: Task<Void, Never>?`. `setRange`, `load`, and `regenerate` all cancel the previous task before starting a new one. The for-await loop guards on `Task.isCancelled` and does not surface output after cancellation.

### 3. Exercise Deep-Dive

- **Entry**: `ExerciseProgressChartView`. A `.task(id: currentExerciseId)` silently checks cache on appear. If no cache hit, `CoachDeepDiveButton` ("Ask the Coach") is shown below the chart card.
- **Paragraph break handling**: `CoachDeepDiveSurface` renders the full narrative as a single `StreamingTextView`. SwiftUI's `Text` renders `\n\n` as a native paragraph break. The previous multi-`StreamingTextView` split-on-`\n\n` approach caused visible layout growth during streaming as each double-newline introduced a new view.
- **Layout reservation**: both `streamingSurface` and `successSurface` apply `.frame(minHeight: 260, alignment: .topLeading)` so the chrome reserves space immediately and does not snap from a sliver to full height on the first token.
- **Stream cancellation**: `ExerciseDeepDiveViewModel` stores the active stream in a `streamTask: Task<Void, Never>?`. `generate` and `regenerate` are now synchronous fire-and-forget (not `async`). `cancel()` is called from `ExerciseProgressChartView.onDisappear`.
- **Cache key**: `"\(exerciseId.uuidString)|\(lastSetTimestampISO)"` — auto-invalidates next time a new set for that exercise is logged.
- **System prompt file**: `ExerciseDeepDiveInstructions.swift`.
- **Output struct**: `ExerciseDeepDiveOutput` — single `narrative: String` field.
- **`findPeak` PR definition**: `ExerciseDeepDiveAggregator.findPeak` selects the session with the highest **raw weight** (ties broken by reps), matching the chart's PR marker. Previously it used max est-1RM, which could surface a lower raw weight than the chart's PR stat.

### 4. Workout Analysis

- **Entry**: `WorkoutDetailView` (tapping a past workout in the Verlauf/History tab). A `.task` silently checks cache on appear and whether a previous same-routine session exists. If yes, `CoachWorkoutAnalysisButton` ("Ask the Coach") is shown below the stats grid.
- **Comparison logic**: `WorkoutAnalysisAggregator.buildInput` finds the most recent previous `WorkoutSession` with the same `routineName` (case-insensitive). Uses `ExerciseProgressService.compareWithPrevious()` for per-exercise comparison data. Also detects new PRs via the Epley formula.
- **Data gates**: button hidden when (a) fewer than 2 completed sets, (b) no previous same-routine session, (c) AI Coach unavailable or workout detail preference off.
- **Layout**: `CoachWorkoutAnalysisSurface` replaces the button after tap. Uses `AISurface` + `StreamingTextView` with `minHeight: 200`. Header label: `"COACH · ANALYSE"`.
- **Cache key**: `workoutId.uuidString` — workout content is immutable once saved, so the key never changes.
- **System prompt file**: `WorkoutAnalysisInstructions.swift`.
- **Output struct**: `WorkoutAnalysisOutput` — single `narrative: String` field.
- **Token cap**: 300 tokens.
- **Preference**: `workoutDetailEnabled` (UserDefaults key: `aiCoachWorkoutDetailEnabled`, default: `true`). Toggle in AI Coach Settings under "Workout detail".

---

## Availability and Opt-in

- `AICoachAvailability` (@Observable singleton): maps `SystemLanguageModel.default.availability` to `isAvailable: Bool`. Re-checked on `.active` scene phase change via `.task`.
- `AICoachPreferences` (@Observable, UserDefaults-backed): `hasCompletedOptIn`, `isMasterEnabled`, `postWorkoutRecapEnabled`, `periodRecapEnabled`, `exerciseDeepDiveEnabled`, `workoutDetailEnabled`. Also stores `lastOptInDeclinedAt` for the 7-day re-prompt cooldown.
- **First-run opt-in**: `AICoachOptInView` is presented as `.fullScreenCover` when `AICoachAvailability.isAvailable && !preferences.hasCompletedOptIn`. "Enable Coach" → sets `hasCompletedOptIn = true` + `isMasterEnabled = true`. "Maybe later" → records decline timestamp.
- **Decline cooldown**: re-shown after 7 days if user still has not opted in.

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

Accessed via gear icon in the History tab toolbar → pushes `AICoachSettingsView`.

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
