# AI Coach — Describe a routine, review the draft, save it

A person taps **Build a routine** in Coach Chat, a sheet opens, they type *"Push day: bench press 3
sets of 8 at 60 kg, incline dumbbell press 3 by 10 at 22 kg"*, and a few seconds later they are
looking at a draft of that routine — its name, and its exercises with their sets, reps and weights.
They tap **Create** and the routine is in the Routines tab and on their watch, indistinguishable
from one they built by hand. They tap **Discard** and nothing was ever written.

**Target:** iOS only. FoundationModels does not exist on watchOS; the watch receives the finished
routine through the ordinary sync path with no change of its own.

**Status:** tickets 01–05 of `.scratch/ai-coach-create-routine/`. 01 was the tracer bullet; 02 made
an exercise name the library could not place into a row the person can answer — see §6a and §9; 03
made the draft editable before Create — see §9a; 04 asks for what a thin description is missing
instead of inventing it — see §9c; 05 carries a stated rep-range goal and rest time — see §4a
(verified on device, round 11).

---

## 1. The one decision everything else follows from

**The model drafts; Swift decides and writes.**

This is deliberately *not* implemented as a FoundationModels `Tool` that creates the routine.
`GenerationOptions.ToolCallingMode` does not exist on iOS 26.x — its `.allowed` case is tagged
iOS 27.0+, and the iOS 26 `GenerationOptions` initializer
(`@backDeployed(before: iOS 27.0) init(samplingMode:temperature:maximumResponseTokens:)`) has no
`toolCallingMode` parameter at all. So a tool call can be *nudged* by prompt but never *forced*, and
this app has already measured the model silently skipping a registered tool and mangling tool
arguments (it called `getExercisePR("Bankdrücken")` for an English "bench press" despite an explicit
verbatim-copy `@Guide`, with opposite outcomes on identical runs).

A missed **read**-tool call is a wrong sentence. A missed **write**-tool call would mean the person
believes a routine was created when it was not. So: `streamResponse(to:generating:)` with a
`@Generable` draft type, and a Swift-side persist after the person confirms.

Two consequences that are load-bearing rather than stylistic:

- **Every exercise name is resolved in Swift, against the live library**, before it can reach the
  review sheet — never invented, never accepted on the model's word.
- **Nothing is written until Create.** Discard, dismissing the sheet, and cancelling mid-stream all
  write nothing, by construction rather than by cleanup.

## 2. Where the code lives

| Layer | File | What it owns |
|---|---|---|
| Domain/Models | `AICoach/RoutineDraftOutput.swift` | the `@Generable` schema + its `@Guide`s |
| Domain/Models | `AICoach/RoutineDraftEntry.swift` | `RoutineDraftEntry` — one exercise as the model wrote it (ticket 05 split it out) |
| Domain/Models | `AICoach/RoutineDraftModels.swift` | `RoutineDraftSnapshot` (what the model produced), `GroundedRoutineDraft` / `GroundedDraftExercise` + its `Match` (what Swift decided, and what it still has to ask) |
| Domain/Interfaces | `AICoach/RoutineDrafting.swift` | the drafting boundary |
| Domain/Services | `AICoach/RoutineDraftGrounder.swift` (+ `+Bounds.swift`) | the grounding pass — pure logic, isolation-agnostic |
| Domain/Services | `AICoach/RoutineDraftFigures.swift` | the figures the person typed — rest times, rep ranges, loads (ticket 05, §4a) |
| Data | `AICoach/RoutineDrafting/RoutineDraftInstructions.swift` | the system prompt |
| Data | `AICoach/RoutineDrafting/RoutineDraftService.swift` | the `LanguageModelSession` + snapshot mapping |
| Presentation | `ViewModels/RoutineCreating.swift` | a *name* for the existing creation seam |
| Presentation | `ViewModels/AICoach/RoutineDraftViewModel.swift` | preflight, stream, ground, resolve, persist |
| Presentation | `ViewModels/AICoach/RoutineDraftRows.swift` | `RoutineDraftRow` + the composer that builds the review list |
| Presentation | `ViewModels/AICoach/RoutineDraftConversation.swift` | which gap the sheet is asking about + the question text (ticket 04) |
| Presentation | `ViewModels/AICoach/GroundedRoutineDraft+Pending.swift` | draft → `[PendingRoutineExercise]` |
| Presentation | `Views/AICoach/RoutineDrafting/RoutineDraftSheet.swift` | the sheet |
| Presentation | `Views/AICoach/RoutineDrafting/RoutineDraftRowView.swift` | one review row, resolved or not |
| Presentation | `Views/AICoach/RoutineDrafting/RoutineDraftQuestionCard.swift` | the one open question (Review draft / Discard), and `RoutineDraftLeftOutNote` |
| Presentation | `Views/AICoach/RoutineDrafting/RoutineDraftExercisePickerView.swift` | "which exercise did you mean?" |
| Presentation | `Views/Exercises/ExercisePickerRowView.swift` | the library row both pickers use |
| App | `AppDependencies.swift` | `routinesViewModel`, `exercisesViewModel`, `makeRoutineDraftService()`, `makeRoutineDraftViewModel()` |

`Domain/` imports no SwiftUI and references no concrete Data type. `RoutineDraftOutput.swift` imports
FoundationModels, exactly as `AICoachOutputs.swift` already does.

## 3. The drafting boundary hands out plain values, not a `ResponseStream`

Every other AI-coach protocol (`AICoachServicing`) hands the ViewModel a
`LanguageModelSession.ResponseStream<Output>` directly. `RoutineDrafting` deliberately does not:

```swift
func draft(from description: String, weightUnit: WeightUnit)          // starts a conversation
    -> AsyncThrowingStream<RoutineDraftSnapshot, Error>
func answer(_ answer: String, to gap: RoutineDraftGap, weightUnit: WeightUnit)  // continues it
    -> AsyncThrowingStream<RoutineDraftSnapshot, Error>
```

**Why the deviation.** `ResponseStream` has no public initializer, so no test can produce one
carrying content — which is why every surface built on `AICoachServicing` can only be tested through
a double that returns `nil`, and why `AICoachAllowanceGate` had to be extracted as its own type to
get the metering under test at all. This surface's acceptance criteria are specifically about what
happens *while* and *after* a draft streams: one unit per session, refunded on failure, and never a
second unit for a second message. Drawing the boundary one step further out — `Data/` owns the
framework types and maps each snapshot — makes all of that assertable with an ordinary
`AsyncThrowingStream` and keeps `Presentation/` free of FoundationModels entirely.

`RoutineDraftService` wraps the framework stream and cancels the producing task from
`continuation.onTermination`, so a dismissed sheet actually stops the generation rather than leaving
the model running for an answer nobody will see.

## 4. The schema, and why it has no optionals

```swift
@Generable struct RoutineDraftOutput {
    let routineName: String                   // empty when the person gave no name (ticket 04)
    let exercises: [RoutineDraftExercise]     // .maximumCount(12) — no minimum, see below
}
@Generable struct RoutineDraftExercise {
    let name: String        // copied from the description, in the description's language
    let setCount: Int       // 0 == "the description did not say"
    let reps: Int           // 0 == "the description did not say"
    let weight: Double      // in the reader's display unit; 0 == no load / bodyweight
    let repRange: String    // the range as typed ("8 bis 12"), .pattern-guided; "" == none (ticket 05)
    let restUnit: RoutineDraftRestUnit  // .unstated / .seconds / .minutes — the word beside the number
    let restAmount: Double  // copied as written; 0 == none stated. Swift converts.
}
```

**No field is Optional, on purpose.** A `@Generable` optional has already produced the literal string
`nil` in rendered output in this app (the period recap's `correlationHighlight`, German, on device,
2026-08-30). Absence is carried by a sentinel number — `RoutineDraftGrounder.unstatedNumber` — and
decided in Swift. Zero is the sentinel because it is the one value the model can be asked for in
plain language without naming a programming construct, and because a real set count, rep count or
load of zero is meaningless anyway, so nothing legitimate is shadowed. Ticket 05 faced this again for
the rep goal and rest time — both genuinely absent most of the time — and kept the sentinel (§4a).

### 4a. Rep-range goal and rest time (ticket 05)

Both map onto fields that already exist — `RoutineExercise.targetRepMin`/`targetRepMax` (`Int?`, both
nil = no goal) and `ExerciseSet.restTime` (applied to every set of the exercise, as
`ConfigureExerciseSetsView`'s rest control does). **No schema change, no CloudKit deploy.**

**Still no optional in the generated type.** `@Generable(representNilExplicitlyInGeneratedContent:)`
exists, but its default *omits* an absent field — the shape that produced the literal `nil` — and a
prompt may not name `nil`/`null`/"empty" anyway. The goal is a `String` span — the words the person
used for the range — constrained by `@Guide(.pattern(/(\d+ ?(-|–|bis|to) ?\d+)?/))` so decoding can
only produce "number, separator, number" or nothing, with the empty string as "did not say" (§4a,
round 9); the rest is a `@Generable enum RoutineDraftRestUnit { unstated, seconds, minutes }` plus a
`restAmount: Double`, where `unstated` is a case rather than an optional. `Data/` maps the enum onto
the plain `RoutineDraftEntry.RestUnit`, so nothing past it sees a `@Generable` type.

**The model's figures are checked against the person's words** (`RoutineDraftFigures`, in
`Domain/Services/AICoach`). The model still decides *which exercise* a figure belongs to; Swift
decides whether the figure is one the person typed. It reads the words once per grounding into rest
times (a number followed by a seconds or minutes word — never a bare "m", which is metres — or a
clock time of at most ten minutes, so "um 18:30" is not a rest), rep ranges
("8-12", "8 – 12", "8 bis 12", "8 to 12") and loads.

- **Rep goal** (`repRangeGoal(span:figures:)`): the copied span is parsed in Swift
  (`RoutineDraftFigures.firstRange`); both ends stated, low < high, upper capped at 99 (the rep-goal
  stepper's ceiling), **and the exact pair typed**. Otherwise nil. No goal is the
  ordinary case, never something Swift fills in. With a goal, the sets' reps start at its low end
  when no rep count was stated, and a stated count is clamped into it (the seeded routines'
  convention; where progressive overload expects a set to begin).
- **Rest** (`restTime(_:amount:figures:)`): Swift converts the copied number by the named unit, and
  treats the unit as a hint — over ten "minutes" is seconds, five "seconds" or fewer is minutes. The
  result must be a typed rest time: matched exactly, then by the bare number (so "90" with the wrong
  unit is still the typed "90 Sekunden"), then — when the words hold exactly one rest time *and* say "Pause"/"rest" — that one
  (so "1:30 Pause" copied as 180 s is read back as 90 s). Unstated, or several rest times with no match,
  falls back to `defaultRestTime` (60 s). Capped at 600 s, the rest editor's ceiling. A rest time
  given once for the whole workout applies to every exercise (a prompt line and the guides say so).
- **Load** (`isStatedLoad`): kept when its number is typed with a weight unit ("60 kg", "135lbs"), or
  bare ("mit 60") unless it is a count — a range end, next to "x"/"×", after "à"/"of"/"je", before a set or rep
  word — or
  equals the drafted set or rep count. A number typed only as a time
  ("2 Minuten") or not typed at all is dropped to no load. **This fixes a defect older than ticket
  05**: the ticket-04 schema also drafted *"Bankdrücken 3 Sätze à 8, 2 Minuten Pause"* at 2 kg on
  every run.

**Typed text is a system boundary.** Range ends use `Int(exactly:)` and must be under 1000 — the
architecture review found that `Int(_:)` on a typed "100000000000000000000-5" traps and would take the
app down. Pinned by `hugeTypedNumberDoesNotCrash`.

**The trade-off is deliberate:** numbers written as words ("acht bis zwölf", "sechzig Kilo") are not
read, so their figure is dropped — no goal, the default rest, no load — which the review shows and
the set editor fixes. A figure the check wrongly accepted would be an invented one written to the
person's store.

**On screen:** each row gets a second line (`RoutineDraftRow.goals`), e.g. *"No rep goal • Rest 1m"*
or *"Goal 8–12 reps • Rest 1m 30s"*. "No rep goal" is spelled out rather than blank. An edited row
reads the line from what `ConfigureExerciseSetsView` returned, whose rest can be switched off
("No rest timer"). The editor opens seeded with the drafted goal and rest, so both are corrected
there — no new control.

**The figure bounds live in `RoutineDraftGrounder+Bounds.swift`**, split out of the grounder so both
stay under the 300-line convention.

#### Device round 8 (2026-09-27) — the first schema failed, and why

The first ticket-05 schema split rest into `restMinutes: Double` + `restSeconds: Int` so the model
would copy rather than convert. On iPhone, *"… 90 Sekunden Pause"* reviewed as **"Pause 10m"**: the
model wrote 90 into the *minutes* field (5400 s, capped at 600). The rep goal read "Kein Wdh.-Ziel".

**Reproduced off-device.** macOS 27 on Apple Silicon has the same on-device model
(`SystemLanguageModel.default.availability == .available`), so a command-line probe compiling the
app's own `RoutineDraftOutput.swift`, the prompt text and `RoutineDraftFigures.swift` measured each
variant five times per description — far faster than a device round. Findings:

- `restMinutes`/`restSeconds`: "90 Sekunden" → 90 minutes on every run. **Discarded.**
- Unit enum + amount: "90 Sekunden" → 90 seconds and "2 Minuten" → 2 minutes on every run, but
  "1:30" came back as 180 s, 30 s or 1.5 s.
- An extra `clock` enum case for "1:30": made it worse ("2 Minuten" → clock, "90 seconds" → minutes).
  **Discarded.**
- Declaring the load *after* the rest fields (to stop "2 Minuten" leaking into it): the range then
  grabbed the load (60–60) and the load became 20. **Discarded.**
- Guide wording "a number followed by a time word is not a weight": no effect. **Discarded.**
- Rep ranges typed in a sentence ("8 bis 12", "8-12", "8 to 12") come back right every time; the
  terse "3x8-12 60kg" comes back as 60–60 or 6–12.

Conclusion: no guide wording made the figures reliable, so the guarantee is Swift's
(`RoutineDraftFigures`). End to end through it, every probe description produced the right goal, rest
and load on every run, except the terse "3x8-12 60kg", which yields no goal on most runs — dropped,
never wrong. Replayed in `RoutineDraftGoalsTests` (the "Device probe replays" section); the figure reader's own
edge cases — huge typed numbers, counts from other exercises, distances, times of day — are in
`RoutineDraftFiguresTests`.

The probe is a throwaway, not in the repo: a `main.swift` that runs
`LanguageModelSession(instructions:).respond(to:generating: RoutineDraftOutput.self)` over a list of
descriptions, compiled with `swiftc -parse-as-library` together with copies of the schema, the figure
reader and the prompt literal. Worth rebuilding for any future schema change on this surface.

#### Device round 9 (2026-09-27) — rest fixed, rep goal still missing; the span schema

Round 9 on iPhone: *"… 90 Sekunden Pause"* now reviewed as "Pause 1m 30s", but the rep goal read
"Kein Wdh.-Ziel", and a dropped-names note listed **"no exercises"** — the model had written an
exercise literally named after the prompt's own sentence *"When they name no exercise, write no
exercises."* (dropped by provenance, §6b, but shown in the note). The iPhone model echoing a phrase
the Mac probe never produced is itself evidence that **the Mac probe is representative of the model
family, not identical to the device** — so the fix had to stop depending on the model getting two
integers right, rather than be tuned until the Mac passed.

**Research (2026-09-27, via ios-api-researcher):**

- `GenerationGuide.pattern(_:)` — `static func pattern<Output>(_ regex: Regex<Output>) ->
  GenerationGuide<String>`, iOS/macOS 26.0+ like `@Generable` — constrains a `String` field's
  decoding to a regex. It turns "compose a number" into "point at existing tokens".
  https://developer.apple.com/documentation/foundationmodels/generationguide/pattern(_:) ,
  WWDC25 session 301 "Deep dive into the Foundation Models framework".
- Properties generate in declaration order; nested `@Generable` structs and enums with associated
  values are supported.
  https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation
- `.range`/`.minimum` on an `Int` whose floor excludes 0 forces the model to invent a value when the
  field must be present — none of this schema's numeric fields carries one, deliberately.
  https://developer.apple.com/documentation/foundationmodels/generationguide/range(_:)
- `@Generable(representNilExplicitlyInGeneratedContent: true)` emits nil as `GeneratedContent.Kind.null`
  instead of omitting it. Not adopted: the no-optional rule (§4) stands, and the span needs no
  optional.
- `GenerationOptions(sampling: .greedy, …)` is Apple's suggestion "for consistent output".
  https://developer.apple.com/documentation/foundationmodels/adding-intelligent-app-features-with-generative-models
- One ~3B on-device model family ships across iOS/macOS per OS generation; Apple guarantees no
  identical sampling between a Mac and an iPhone build.
  https://machinelearning.apple.com/research/apple-foundation-models-2025-updates
- Filler array elements echo instruction phrasing; phrase the empty case without a quotable phrase.

**Probe results (macOS 27, 6–8 runs per description):**

- **Span + `.pattern` (adopted):** every stated range copied verbatim on every run — "8 bis 12",
  "8-12 Wiederholungen", "8 to 12", and the terse "3x8-12" / "3x10-12" that the Int pair drafted as
  6–12 on 6 of 8 runs. On a description *without* a range the span is junk ("8-60", "60-60", "8-2",
  once even "8-12") — none of it typed, so none survives `repRangeGoal(span:figures:)`. In a
  two-exercise description only the exercise that carries the range gets it.
- **Greedy sampling on the Int pair:** deterministic, but "3x8-12" was 6–12 on every run — greedy
  does not fix a schema that asks the model to compose numbers. (Greedy was adopted in round 10, on
  top of the span schema, for reproducibility.)
- **Nested goal struct / enum with associated values:** not pursued — the span fixed the measured
  failure with a smaller change.

**"no exercises":** the prompt and the `exercises` guide now say *"Add an exercise … only when the
description names it"* instead of *"write no exercises"*. On the Mac, *"eine push routine"* drafts no
rows. The iPhone behaviour is the device check.

The span's regex sits in the generation schema and so is read by the model; it carries no digit, no
number word and no example, so `CoachPromptGroundingTests` still passes over it.

#### Device round 10 (2026-09-27) — terse notation on iPhone; per-exercise figures and greedy

Round 10 passed *"Push-Test: Bankdrücken 3 Sätze à 8 bis 12 mit 60 kg, 90 Sekunden Pause"* end to end
(review, Create, routine detail: 8–12 goal, 1m 30s rest). The terse *"… Bankdrücken 3x8-12 mit
60kg, 90 Sekunden Pause"* failed on iPhone in two ways the macOS probe never reproduced (8 of 8 runs
correct there):

1. **The 60 kg was lost** — the iPhone model wrote no load, or one Swift correctly refused.
2. **"Pause" became a second exercise** — it passed provenance (§6b) because the person typed it, and
   the sheet asked "Wie viele Sätze für Pause?".

**Fixes, all Swift-side because the device model is the variable:**

- **Figure words are not exercises** (`RoutineDraftFigures.isFigureVocabulary`): a name made only of
  rest, count, unit or goal words ("Pause", "Sätze", "kg", "Wiederholungsziel") is skipped before it
  meets the library, and not listed as dropped. "Rest-Pause Bench" is kept.
- **Each exercise's own words, only to recover a missing figure**
  (`RoutineDraftFigures.segments(for:in:)`): the text from a drafted name up to the next one, or the
  end of its line. The model's load and range are still confirmed against the **whole** description
  first; only when they cannot be confirmed is the single load-with-unit / single range typed in that
  exercise's stretch used (`RoutineDraftGrounder.load(of:figures:segment:)`,
  `repRangeGoal(span:figures:segment:)`). That recovers the round-10 60 kg and corrects a drafted
  6–12 to the typed 8–12. **Segments are all-or-nothing:** they are used only when every drafted
  name occurs in the words exactly once, in order, before its figures — otherwise there is no
  fallback and the figure stays empty. The first version confirmed against the segment alone and
  used it unconditionally; the architecture review reproduced it moving loads and goals between
  exercises for an inflected neighbour ("Kniebeuge" for "Kniebeugen"), figures written before their
  names, and names repeated in a follow-up answer — all pinned in `RoutineDraftFiguresTests`. A stretch holding
  more than one set group ("3x8 … 5x5") is not used either: it means the model left an exercise out
  and the stretch ran over it (`omittedExerciseLendsNoFigures`). Known limit: mixed ordering such as
  *"Kniebeugen 5x5, 60kg Bankdrücken 3x8"* is read name-first, giving the squat the 60 kg — ambiguous
  to a human reader too. The
  fallback does **not** make cross-exercise attribution impossible: a model value confirmed by the
  whole text is kept even if it belongs to a neighbour, as before round 10. A load or rest span
  ("60-80 kg", "60-90 Sekunden") is never read as a rep range.
- **Greedy sampling** — `GenerationOptions(samplingMode: .greedy, maximumResponseTokens:)` (the
  `sampling:` label is deprecated in the iOS 27 SDK). Probe, 5 runs each, over the round-10 input,
  *"eine push routine"*, *"Bankdrücken und Kniebeugen"*, the round-1 Push-Tag, *"bench press three by
  eight"* and a two-exercise English legs day: greedy equal or better on every one, the terse input
  right 5/5, and the routine name stopped flipping between "Push-Test" and "Bankdrücken". A device
  round is now reproducible: the same words draft the same routine.

**Research (2026-09-27, via ios-api-researcher)** — besides greedy
(https://developer.apple.com/documentation/foundationmodels/generationoptions/samplingmode-swift.struct/greedy):

- There is **no "substring of the prompt" constraint** for a `String` field. `.pattern` shapes format
  only; `GenerationGuide.anyOf(_:)` takes a runtime `[String]`
  (https://developer.apple.com/documentation/foundationmodels/generationguide). **Not adopted:**
  constraining `name` to candidate substrings would need a `DynamicGenerationSchema` rewrite of the
  schema and its mapping, and the one failure it targets ("Pause") is closed deterministically above.
- Few-shot examples belong in the *prompt*, never the instructions, and instructions must not carry
  untrusted (user) content (https://developer.apple.com/documentation/foundationmodels/instructions,
  WWDC25 session 248). Consistent with this surface, which uses neither.
- Declaring a routine-level rest field before `exercises` was suggested as a weak lever. **Not
  adopted:** rest is per exercise here, and the vocabulary rule already handles "Pause".
- Normalising "60kg" to "60 kg" before the prompt is undocumented. **Not adopted:** the per-exercise
  load recovery makes it unnecessary.
- WWDC26 session 241 ("What's new in the Foundation Models framework") adds nothing aimed at span
  extraction. https://developer.apple.com/videos/play/wwdc2026/241/

**Found, not fixed (ticket 04 territory):** on *"Bankdrücken und Kniebeugen"* (no figures) the model
still drafts set and rep counts (3×8, 3×12). The figure check now drops the invented loads, ranges
and rests, but set/rep counts are not checked against the words, so the sheet does not ask "how many
sets?". The fix would be a count-provenance pass (`setCount`/`reps` must be typed in the exercise's
segment, else unstated), which would change ticket 04's shipped behaviour and belongs in its own
ticket.

Replayed in `RoutineDraftDeviceRoundTests`; the figure-reader cases in `RoutineDraftFiguresTests`.

#### Device round 11 (2026-09-27) — passed; ticket 05 closed

iPhone, German, the user confirmed all four checks: *"Push-Test: Bankdrücken 3x8-12 mit 60kg, 90
Sekunden Pause"* reviewed as one row, "3 Sätze • 8 Wdh. • 60 kg / Ziel 8–12 Wdh. • Pause 1m 30s",
with no "Pause" row and no question; the sentence form *"… à 8 bis 12 mit 60 kg …"* unchanged under
greedy sampling; *"… à 8 mit 60 kg …"* reviewed as "Kein Wdh.-Ziel • Pause 1m 30s"; *"eine push
routine"* asked which exercises, with no rows.

**Supersets are out of scope** (parent task doesn't ask; the manual creation flow can't create one
either; `SupersetOrderingService`'s contiguity invariant isn't called by `createRoutine`). If wanted:
a `supersetId`/`supersetOrder` pass over the pending graph plus a `normalizeOrdering` call, as its own
ticket.

**No minimum exercise count (since ticket 04).** Ticket 01 had `.minimumCount(1)`. Guided generation
cannot emit fewer elements than the schema demands, so for *"a push routine"* that constraint
*forced* an exercise out of the model. An empty list is now a legitimate answer, and Swift's cue to
ask (§9c). **Removing the minimum was necessary but not sufficient** — the device check showed the
model fills the list anyway (§6b), which is why the guarantee is the provenance check, not the schema.

**The exercise library is not in the schema.** A dynamic `@Guide(.anyOf:)` over all ~96 catalog names
was considered and rejected on per-request token cost: every value would ride in the prompt on every
request. The model emits a free-text name; Swift resolves it.

### Guided-generation facts this was built on (researched 2026-09-16, iOS 26.x SDK)

- `snapshot.content` is `RoutineDraftOutput.PartiallyGenerated`; its `exercises` is
  `[RoutineDraftExercise.PartiallyGenerated]?`, and each element's own properties are individually
  Optional. The macro generates `PartiallyGenerated` recursively.
- WWDC25 session 301 states properties are generated **in declaration order**. That makes
  "the last declared field is non-nil" a sound completeness signal — but the code checks all four
  fields anyway, because Apple documents no named "is this element complete" API and the order
  guarantee says nothing about whether the *array* has stopped growing.
- There is **no** `isComplete` flag on `Snapshot`, `PartiallyGenerated` or `GeneratedContent`.
  `ResponseStream.collect()` returns `Response<Content>` with a non-Optional `.content` and is the
  only *type-level* guarantee of a finished value; iterating leaves the last snapshot statically
  `PartiallyGenerated`. This surface iterates, because it needs the progressive snapshots, and treats
  the post-loop state as final.
- Array count guides are spelled `.minimumCount(_:)` / `.maximumCount(_:)` / `.count(_:)`; numeric
  guides are `.range(_:)` / `.minimum(_:)` / `.maximum(_:)`.
- `streamResponse` does **not** throw; failures surface when the stream is *iterated*, as
  `LanguageModelSession.GenerationError`. The guided-generation-specific case is `.decodingFailure`
  ("failed to deserialize a valid generable type from the model output… can occur if the generation
  process was terminated prematurely"), which `RoutineDraftService.log(_:)` names explicitly.
  Apple's docs mark the whole `GenerationError` enum deprecated in favour of a newer
  `LanguageModelError`, but several of that type's cases are tagged iOS 27.0+ Beta and
  `GenerationError` is what actually throws on 26.x — so 26.x code catches `GenerationError`.
- **On an iOS 27 device the errors are `LanguageModelError`, not `GenerationError`** (researched
  2026-09-25). `LanguageModelError` is 27.0+, `@nonexhaustive`, and replaces the deprecated
  `GenerationError` together with `LanguageModelSession.Error` and `SystemLanguageModel.Error`. Its
  case order **in the shipped iOS 27.0 SDK** (`FoundationModels.swiftinterface`) is
  `contextSizeExceeded`, `rateLimited`, `guardrailViolation`, `refusal`, `unsupportedCapability`,
  `unsupportedTranscriptContent`, `unsupportedGenerationGuide`, `unsupportedLanguageOrLocale`,
  `timeout` — Apple's web docs list a different order. There is **no** `decodingFailure` equivalent. A bridged `NSError.code` is only the case's position, which is not a documented contract
  and can shift; so `RoutineDraftService.log(_:)` logs the **case name** publicly (`caseLabel`) and the
  error's description only as `.private` — a refusal or guardrail payload can carry the person's own
  words (architecture review, 2026-09-25). Device, 2026-09-25: *"Push-Tag-Test: Bankdrücken 3 Sätze jeweils 8
  Wiederholungen mit 80kg"* failed every time with `LanguageModelError` code 3, which that order
  reads as `.timeout` — **wrong**: logged by name it was *"May contain sensitive content"*, Apple's
  safety guardrail. The documented order and the shipped code disagree, which is exactly why the log
  names the error rather than trusting its number.
- **A declined description is its own message** (`RoutineDraftingError.declinedByModel`).
  `RoutineDraftService.isDeclinedByModel` matches `guardrailViolation` / `refusal` by case on both
  `LanguageModelError` (iOS 27, behind `#available`) and `GenerationError` (iOS 26), and the sheet
  says the wording was declined and to phrase it differently — never "try again", since the same
  words are declined every time. The unit is refunded like any failed draft; a declined answer stays
  on its question. **Loosening the filter is not an option** (researched 2026-09-25):
  `SystemLanguageModel(guardrails: .permissiveContentTransformations)` (iOS 26.0+) is documented as
  "only applicable for generating string values"; for non-String (`@Generable`) generation it
  "behaves identically to the default guardrail mode". Guardrails check input and output. Apple's
  guidance for a user-originated prompt is to tell the person it is not supported and let them try
  different wording — which is what the sheet does. Sources:
  https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/guardrails/permissivecontenttransformations ,
  https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output .
  The same routine as *"Bankdrücken 3 Sätze à 8 mit 80 kg"* went through, so the
  filter reacts to wording, not content. Sources:
  https://developer.apple.com/documentation/foundationmodels/languagemodelerror ,
  https://developer.apple.com/documentation/foundationmodels/languagemodelerror/timeout(_:) ,
  WWDC26 session 339.
- `LanguageModelSession` conforms to `Sendable` (per its reference page's Conforms-To list). Whether
  it is *intended* to be driven off the main actor is still undocumented, so this service stays
  `@MainActor` like `CoachChatService`. `LanguageModelSession.Error.concurrentRequests` documents
  that two in-flight requests against one session instance are illegal.
- Sources: https://developer.apple.com/documentation/foundationmodels/languagemodelsession/responsestream ,
  .../responsestream/snapshot , .../generationoptions/toolcallingmode-swift.struct/allowed ,
  .../languagemodelsession/generationerror , "Adding intelligent app features with generative models",
  WWDC25 session 301.

## 5. The prompt

`RoutineDraftInstructions.build(unit:)`. It frames the model as **a transcriber, not a coach**, and
two properties are binding — both pinned by `CoachPromptGroundingTests`, which now scans this prompt
in `kg` and `lb` and both generation schemas:

1. **Nothing is data-shaped.** No exercise name, no weight, no rep count, no date. Instructions are
   placed verbatim into the prompt, so an example figure is indistinguishable from a figure the
   person typed — the failure that once presented an example `87.5 kg` to a reader as their own
   training data. This prompt contains no digits at all.
2. **It never describes a shape the description does not support.** A ~3B model completes the shape
   its instructions describe, so *"suggest three or four exercises"* is answered with three or four
   invented ones. **Every default is applied in Swift after generation**, never asked of the model.

The reader's unit is named in the prompt (`AICoachUnitVocabulary.englishName`) so the plain numbers
that come back can be converted to canonical kilograms exactly once, in the grounder. The routine
name is asked for in the description's own language, which is what makes a German description produce
a German routine name.

**Since ticket 04 the name is taken from the person's own words or left empty.** Ticket 01 told the
model to "name it after what it trains" when the description gave no name — a plausible default the
model made up. Now *"a push routine"* still yields *Push* (the person said what kind of workout it
is), but *"bench press three by eight"* yields no name, and Swift asks for one (§9c). The prompt also
says outright that a description naming no exercise gets no exercises, and it explains a message of
several lines: the first is the description, each later one an answer that names the question it
answers; draft from all of them as one description and fill nothing no line covers.
`RoutineDraftInstructions.answer(_:to:)` frames an answer ("Answer about which exercises the routine
should include — …") in English; the answer itself stays in the person's language.
`prompt(from:)` joins the lines, flattening line breaks inside one so a description typed over several
lines stays the first line.

## 6. The grounding pass

`RoutineDraftGrounder` is pure logic over already-fetched `Exercise` models — `Domain/`,
isolation-agnostic, no store access, no formatter. Two jobs:

**Resolve every name**, through the existing `ExerciseNameResolver` (folded, diacritic- and
case-insensitive, cross-language, `.resolved` / `.ambiguous` / `.noMatch`). **There is no second
matcher in this app.**

- `.resolved([Exercise])` → the first match. The resolver only aggregates rows that share one folded
  *name*, so this is not a coin toss between different exercises.
- `.ambiguous([String])` → `Match.ambiguous([Exercise])`. The reported names are mapped back to
  library rows, in the resolver's own order, because the person picks one of *their* exercises and a
  picker needs exercises rather than strings.
- `.noMatch` → `Match.unmatched`: nothing to offer but the whole library.

**Neither failing case is dropped.** Both stay in the draft, in the place the description gave them,
as rows the person can answer (§6a). They are excluded from what Create writes — `resolvedExercises`
is the only list that reaches the store — and the sheet says so before Create is tapped. The one
thing this surface may never do is quietly drop something that was asked for, or invent a library
entry to hold it.

### 6a. Resolving a name the library could not place (ticket 02)

An unresolved row is not a report; it is a question with an answer button.

**The two failing cases stay apart all the way to the screen.** `Match` is
`.resolved(Exercise)` / `.ambiguous([Exercise])` / `.unmatched`, and `GroundedDraftExercise` keeps the
`draftedName` whether or not it resolved — an unresolved row shows *what the person actually said*,
because that is the only thing they recognise it by. `.ambiguous` carries the few library exercises it
matched and the picker offers those first, under "Did you mean"; `.unmatched` carries none and the
picker is the whole library. Collapsing the two would throw away the only thing that makes the
ambiguous case answerable in one tap.

**Resolved in the UI, not with a second model round trip.** Coach Chat has a precedent for handing the
model a capped list of ≤60 library names to re-resolve against (the `__NO_MATCH__` payload in
`ChatFactBuilder`), but that exists because the chat has no UI to ask through. This sheet does. A
picker is deterministic, costs no tokens and no allowance, and cannot translate or invent a name —
all three of which the model has been measured doing in this app.

**Answering keeps everything the description gave.** `GroundedRoutineDraft.resolve(_:to:)` replaces
only the `Match`: same row identity, same position, same set count, reps and weight. That is what
makes the described order still the routine's order after an answer. `resolve` is a deliberate no-op
on an already-*resolved* row — swapping an exercise the library did place would be re-drafting it.
Removing a row is `remove(_:)`, which since ticket 03 drops any row, resolved or not (§9a).

**Create can never write an unresolved row**, by construction rather than by a check at the button:
`pendingExercises()` maps `resolvedExercises`, and `canCreate` is false when that list is empty. An
unresolved row is excluded and the sheet's note says so *before* Create is tapped, rather than Create
being disabled — a person whose exercise genuinely is not in their library would otherwise be stuck
with a button that never lights up.

**Answering costs no allowance.** The unit was consumed by the drafting session; correcting the
machine's reading of a name is not a second use of the coach. Nothing in `resolveRow`/`removeRow`
touches the gate. (The ticket-01 rule that an *all*-unmatched draft refunds its unit is unchanged: a
person who then answers every row and creates a routine got it for free. Deliberate — the alternative
charges for a session that ticket 01 refunded, which is a revenue-increasing change on an arguable
case, and §10 of the monetization strategy says an arguable gate stays free. There is no exploit
either: picking exercises out of a picker by hand is what building a routine manually already is.)

**The picker routes through the app's one search implementation.**
`ExercisesViewModel.sections(searchText:categoryKey:equipment:)` — the same one behind
`RoutineExercisePickerView` — so there is no third search/filter in the app. The library row itself is
`ExercisePickerRowView`, extracted from `RoutineExercisePickerView.pickerRow` so both pickers show the
same row rather than two copies of the same styling.

**`AppDependencies` owns the `ExercisesViewModel` the picker uses**, as a `lazy var`, for the same
reason it owns `routinesViewModel`: `ExercisesViewModel.init` registers a `cloudKitDataDidChange`
observer and never removes it, so a fresh instance per drafting sheet would leak one observer per
presentation — and this sheet is opened and dismissed repeatedly. The Routines and Exercises tabs keep
their own `@StateObject` instances; those are built once for the life of the app, which is the
property the shared one reproduces for a modal. The picker still calls `fetchExercises()` on appear,
because a shared instance that outlives any one sheet would otherwise be missing an exercise created
since it was built — on exactly the screen that exists to find one.

**Row identities are stable across snapshots.** `RoutineDraftGrounder.entryIDs` hands out one `UUID`
per drafted *position* and reuses it on every later snapshot. Each streamed snapshot is cumulative, so
the entry at a given index is the same entry throughout; minting a fresh id per snapshot gave every
row a new identity on every token burst, which makes SwiftUI rebuild the list rather than diff it
(rendering rule 8) and would leave a picker opened on a row pointing at an id that no longer exists.

### 6b. Provenance — every name must come from the person's words (ticket 04)

**Device round 5 (2026-09-24, German, iPhone) failed ticket 04's first criterion.** *"eine push
routine"* came back named *Eine Push Routine* with **twelve invented rows** — Push, Pull, Squat, Legs,
Chest, Shoulders, Back, Arms, Abs, Core, Legs, Back: its own word for the workout, then training
categories, repeating until `.maximumCount(12)` stopped it. The prompt said "when they name no
exercise, write no exercises"; a ~3B model handed an array field fills it. Eleven rows were caught by
the library (unmatched), but **"Pull" resolved confidently to *Face Pulls*** (the resolver's
word-boundary step: `pull` starts the word `pulls`) — an invented exercise presented as the person's
own, one tap from being saved. The question then asked for set counts of all twelve.

**Fix — a Swift guarantee, not a better prompt.** `RoutineDraftGrounder.ground(…, personWords:)`
receives everything the person typed in the conversation (the description plus every answer sent to
the model, collected by `RoutineDraftViewModel.personWords`) and applies two rules before a name meets
the library:

1. **Provenance.** Every word of the drafted name must be **a word the person used**, both folded
   with `ExerciseNameResolver.fold` (made internal for this — one fold in the app, not two). Equal,
   or differing only by an ending of up to two letters ("Squat"/"squats", "Kniebeuge"/"Kniebeugen"),
   because a false *drop* loses something the person said. **Not a substring:** the first version
   was, and device round 6 let "Rücken" through because `fold("Bankdrücken")` contains `ruecken` —
   a word hidden inside a longer one is not the person's. It never consults the library, so it is a
   provenance filter, not a second matcher.
2. **The workout's own name is not an exercise.** "Push" *is* in "eine push routine" — as the kind of
   workout, which the model also put in the routine name. An **unmatched** name whose words are all
   in the routine name is dropped. A name the library resolves is kept even so ("Squat Day: squat
   5×5").

Names dropped by rule 1 are kept in `GroundedRoutineDraft.droppedNames` and shown under the list
("Nicht aus deiner Beschreibung — … wurde weggelassen") so a real exercise the model rewrote is never
lost silently — **except while the draft has no exercises at all**, when the honest thing to show is
the "which exercises?" question, not a list of things the model made up. Rule-2 drops are not listed.

Replayed verbatim in `RoutineDraftQuestionTests.deviceReplayAsksInsteadOfInventing` /
`deviceReplayThroughTheViewModel`: the twelve rows ground to an empty draft whose only gap is
`.exercises`.

**Device round 7 (2026-09-25/26, German, iPhone, iOS 27) — passed; ticket 04 closed.** *"eine
push routine"* asked for exercises with no rows and no dropped-names note; *"Bankdrücken und
Kniebeugen"* either drafted both or stayed on the question, never with an invented row; *"je vier"*
reviewed at 4 sets each; a nameless description asked for a name. *"Push-Tag-Test: Bankdrücken 3 Sätze
jeweils 8 Wiederholungen mit 80kg"* was blocked by Apple's guardrail every time and now shows the
"reword it" message with the text kept (§4, logged as `guardrailViolation`); the same routine as
*"… 3 Sätze à 8 mit 80 kg"* drafted correctly. The streaming border and sparkle stop once the draft
lands (§9).

**Device round 6 (2026-09-24) — the answer turn invented too.** Rounds 1–3 of this surface passed
with the provenance check; answering *"Bankdrücken und Kniebeugen"* then came back with neither
exercise, but a fresh list of eleven categories and moves (Liegestütze, Bizeps, … Rücken). The
answer went to **the same session**, whose transcript held the model's own invented twelve-row reply;
the model reproduced that shape instead of transcribing. (The single most plausible reading; every
full description in rounds 1–4 was transcribed exactly from a fresh session.) Three fixes: the
whole-word rule above; **every turn in a fresh session** carrying the person's lines only (§9c); and
an answer that yields no exercise stays on its question (§9c) instead of falling through to an empty
review. Pinned by `answerThatYieldsNothingStaysOnTheQuestion` and `wordInsideACompoundIsNotProvenance`.

**Known trade-off:** a model that paraphrases a real name ("db press" → "dumbbell press") now has it
dropped, and the note says so. Rounds 1–4 measured the model copying names exactly, so this should be
rare; if a device round shows otherwise, loosen `isInPersonWords` rather than removing it.

**Follow-up, not applied:** the resolver's word-boundary step lets `pull` resolve to *Face Pulls* for
any caller, Coach Chat included — the same family as the round-1 compound defect. Provenance removes
it here; the shared leniency is untouched.

### Device rounds

#### Round 1 (2026-09-16) — the compound-word defect

The first device check produced the failure this whole surface is built to prevent.
*"Push-Tag: Bankdrücken 3 Sätze à 8 mit 60 kg, Schrägbankdrücken 3 Mal 10 mit 22 kg"* against a
library holding a plain **Bankdrücken** and no incline entry came back as **two rows both reading
"Bankdrücken"**, the second carrying the incline numbers. One tap from being written that way.

The model was not at fault — it transcribed 3 × 10 @ 22 kg exactly. **The grounding pass picked the
wrong exercise**, and presented it with full confidence.

**Root cause: `ExerciseNameResolver` step 2 was a plain substring test in both directions.**
`fold("Schrägbankdrücken")` is `"schraegbankdruecken"`, which *contains* `"bankdruecken"` — so the
library's Bankdrücken was the only candidate, a single distinct name, and therefore a confident
`.resolved`. Not `.ambiguous`, not `.noMatch`. German builds exercise names by compounding, and the
compounded qualifier is exactly what names a different movement; `"Frontkniebeugen"` →
`"Kniebeugen"` is the same defect.

**Fix: step 2 now requires a word boundary** (`ExerciseNameResolver.containsAtWordBoundary`). A
needle matches only at index 0 or after a non-alphanumeric character, so a compound suffix no longer
matches while every legitimate case survives — a query that is the start of a longer stored name
("Bankdrücken" → "Bankdrücken (Langhantel)"), and one separated by a space or bracket ("Curls" →
"Biceps Curls").

**The fix is in the shared resolver, not in this surface.** Coach Chat had the same defect and it was
the same class of failure there: a *"Was ist mein Bestwert beim Schrägbankdrücken?"* question was
answered with the Bankdrücken numbers — a fabrication, which is precisely what the grounding doctrine
forbids. Containing the fix in `RoutineDraftGrounder` would have meant a second matcher, which this
ticket forbids, and would have left the chat wrong.

**Deliberately not changed:** a qualifier standing as its *own word* still resolves — "Enges
Bankdrücken" against a library "Bankdrücken" is a qualified mention, not a different word, and that
leniency is long-standing shipped behaviour. The compound case was the unambiguous defect. Pinned by
`aSeparateQualifierWordStillResolves`.

Regression cover: `ExerciseNameResolverTests.compoundPrefixDoesNotResolveToTheStemExercise`,
`compoundResolvesWhenTheLibraryCarriesIt`, `twoCompoundVariantsStayAmbiguous`,
`aSeparateQualifierWordStillResolves`, and `RoutineDraftTests.germanCompoundIsNotSwappedForTheStem`,
which pins the consequence at the level the person sees it.

#### Round 2 (2026-09-17) — passed

Same input, same device. The routine came back named **Push-Tag**, with **Bankdrücken · 3 Sätze ·
8 Wdh. · 60 kg** resolved and transcribed correctly, and **Schrägbankdrücken** reported under
*"Weggelassen — nicht in deiner Übungsbibliothek"*. The silently-wrong second row is gone and the
exclusion is stated rather than hidden, which is the contract this surface is built on.

Worth reading as a product signal rather than a defect: the person *has* an incline press in their
library — it is stored as "Schrägbank-Kurzhanteldrücken" — and typing "Schrägbankdrücken" does not
reach it, because folded string matching cannot bridge two different German compounds. Being told so
is the correct behaviour for this ticket. **Being able to do something about it is ticket 02**, and
round 2 is the evidence for how often it will matter: on a two-exercise description, once.

#### Round 3 (2026-09-19) — ticket 02, passed

The same German description on the same device, now with the row answerable. Confirmed end to end:
**Schrägbankdrücken** came back as an unresolved row carrying *"3 Sätze • 10 Wdh. • 22 kg"* and the
hint *"Nicht in deiner Bibliothek — zum Auswählen tippen"*, under the *"Noch nicht hinzugefügt"*
note. Tapping it opened the picker titled *"Übung wählen"*, naming the drafted words in its subtitle;
choosing **Schrägbank-Kurzhanteldrücken** resolved the row **in second position with its figures
unchanged**, and the note disappeared. Create wrote *Push-Tag* with both exercises in the described
order, the second at 3 × 10 @ 22 kg. The free-request counter dropped by exactly one for the whole
session — answering the row cost nothing.

That closes the loop opened by round 2: the one name in a two-exercise description that folded string
matching could not bridge is now fixed by the person in two taps, and the figures the model
transcribed correctly survive the correction.

#### Round 4 (2026-09-24) — ticket 03, passed

Editing the draft before Create, on iPhone. A three-exercise push day (bench 3×8 @ 60 kg, rows 3×10
@ 50 kg, squat 4×5 @ 100 kg) was renamed to *Upper A*, Squat moved to the top with two Move ups, Row
removed, and Bench Press reopened in the set editor and cut to 2 sets — its row summary updated on
return. The free-request hint did not move while editing. Create wrote *Upper A* as Squat → Bench
Press with Bench at 2 sets: every edit reached the store, in the order the sheet showed.

**Bound every number.** The figures are copied from a sentence a person typed, not entered in a
stepper: unstated (`0`) falls back to `defaultSetCount` (3) / `defaultReps` (10); a stated value is
capped at `maximumSetCount` (20) / `maximumReps` (100); a weight is converted with
`WeightUnit.clampedKilograms(fromDisplay:)`, which also applies the app-wide 999 kg ceiling. A load of
zero is a drafted exercise *without* a load — which is what a bodyweight movement needs — not a
missing one.

**Grounding runs on every streamed snapshot**, not once at the end, so the review list fills with the
*library's* names as exercises complete rather than showing the model's spelling and correcting it
afterwards. `Data/` drops partially-generated entries before they get here, so a name still being
assembled token by token never walks the row through whatever "Ben", "Bench", "Bench pr" happen to
match.

**That is why the grounder is a class with a memo, and not a struct.** Each snapshot is cumulative, so
grounding one re-resolves the whole draft — and a single `ExerciseNameResolver.resolve` walks the
library up to *three* times (exact, then substring, then token overlap), folding every library name on
each pass at roughly four allocations per name per pass. Unmemoized, one drafting session costs
O(snapshots × drafted entries × library × 3) on the main actor: with a ~150-entry library, 12 entries
and a few dozen snapshots, on the order of 10⁵–10⁶ short-string allocations *while the sheet is
animating*. `RoutineDraftGrounder.matches` caches the answer per drafted name, so each distinct
name is resolved exactly once per session. The cache is keyed by name alone, so **one grounder
instance belongs to one library snapshot** — `RoutineDraftViewModel.loadLibrary()` builds a fresh one
with every fetch.

**The library itself is fetched on the chip tap, not in the sheet's `onAppear`.**
`ExerciseRepository.fetchAll()` is a synchronous full-library SwiftData fetch, and `onAppear` runs
while the sheet animates in — rendering rule 7. `requestDrafting()` loads it after the preflight
passes and before the sheet is presented, so the fetch is off the animation's critical path and a
refused tap reads nothing at all. `onAppear` keeps an `if library.isEmpty` fallback that normally
never runs.

## 7. Persisting — one write path, not a second

Create goes through `RoutinesViewModel.createRoutine(name:pendingExercises:)`, unchanged. It already
materializes routine + exercises + sets + alternatives in one transaction, calls `save()`, then
`fetchRoutines()` — and that re-fetch is what pushes the new routine to the watch. **There is no
extra sync call and no parallel write path.**

`GroundedRoutineDraft.pendingExercises(applying:)` is the whole mapping, over `resolvedExercises`
alone: `order` comes from position among those (which is how the order the sheet shows — described,
then possibly moved — becomes the routine's order, with the gaps left by unresolved rows closed up).
It is **always reassigned there**, never carried over from an edited `PendingRoutineExercise`, so a
row edited and then moved still lands where the sheet showed it. A row the person reopened in the set
editor writes exactly what that screen returned (the `edits` map, §9a); every other row becomes
`setCount` identical `ExerciseSet`s at the drafted rest time (stated, or 60 s) via
`GroundedDraftExercise.pendingExercise(order:)`, with the stated rep-range goal or none (§4a). The
drafted scheme leaves alternatives empty — nothing in a typed description expresses them, and
inventing one would be the app guessing on the person's behalf at the exact moment it writes to their
store. The person can add them by opening the row.

### `RoutineCreating`, and why `AppDependencies` owns the routines ViewModel

The drafting sheet opens from Coach Chat, which is presented from `ContentView` and has no routines
screen in scope. It needs both `createRoutine` and `isRoutineCapReached`.

`RoutineCreating` is a two-member protocol that `RoutinesViewModel` satisfies **as it already
stands** — a zero-body conformance. It is not a new write path; it is a name for the existing one,
and it is what lets the draft's preflight be asserted without a `ModelContext`. The cap is declared
beside the creation call on purpose: a creation entry point that can read one but not the other is
one that can let a person build something that cannot be saved.

`AppDependencies` now owns the app's single `RoutinesViewModel` as a `lazy var`, and `RoutinesView`
uses that instance instead of constructing its own. **This is required, not tidiness:**
`RoutinesViewModel.init` registers five `NotificationCenter` observers and removes none of them, so
building a throwaway instance per drafting sheet would leak a set of observers every time the sheet
opened, and a second live instance would mean two objects fetching routines and syncing them to the
watch. `lazy` keeps construction at first use (the Routines tab, at launch) rather than inside
`AppDependencies.init`, where it would fetch before the container is fully wired.

**One consequence of the `lazy` worth knowing:** `CoachChatView.body` calls
`makeRoutineDraftViewModel()`, which reads `routinesViewModel` and therefore *forces* it. In the
ordinary launch path the Routines tab renders first and nothing changes, but if a person somehow
reached Coach Chat before that, `RoutinesViewModel.init`'s side effects — `fetchRoutines()`, and with
it the watch sync, the calendar reconcile and the reminder refresh — would fire from the chat rather
than from the Routines tab. They are the same side effects either way; only the trigger moves.

## 8. Preflight order, and the allowance

**Availability → routine cap → allowance ticket.** The order is the whole point and is pinned by
three tests.

1. **Availability first.** A device that cannot run Apple Intelligence must never be shown a paywall
   for it (`monetization-strategy.md` §4.3): unavailable is a disappointment, not a conversion
   opportunity. It never even reaches the cap check. The chip itself is absent when the coach is
   unavailable, exactly as the coach bar already is.
2. **Then the routine cap.** `RoutineDraftViewModel.requestDrafting()` raises `.routineCap` and the
   sheet does not open — so a free user at `ProFeatureCaps.freeRoutineLimit` (3) is stopped *before*
   typing a description, not after. Same reasoning as `RoutinesViewModel.requestAddRoutine()`. An
   AI-drafted routine counts against the cap exactly as a hand-built one does.
3. **Then the allowance**, at `submit()` — still before any model call.

### Monetization verdict — AI routine draft

```
Tier          Free
Derivation    §3 Rule 1 — building a routine is the aha path
Mechanism     no new gate; reuses the existing .coachChat usage cap
Placement     PaywallPlacement.coachChat (existing) and .routineCap (existing) — no new case
Nudge         OnyxCapNudge, in the sheet and in the chat above the chip
Free residue  the whole feature, 5 drafting sessions a month, and every routine ever created
Founder note  n/a — no new gate, so nothing new to convert against §7's permanent grant
```

**Re-checked for ticket 05 (2026-09-26): unchanged.** A drafted rep goal and rest time are part of
the same draft the unit paid for — no new gate, unit, placement or model call. §3 Rule 1.

**Re-checked for ticket 04 (2026-09-24): unchanged.** Follow-up answers ride the session's single
unit and reserve nothing; Review draft and Discard are free; no new placement or cap. §3 Rule 1 —
this is the aha path made reachable from a one-line idea.

**Re-checked for ticket 03 (2026-09-24): unchanged.** Renaming, reordering, removing and re-configuring
rows are Swift-side edits of a draft the unit already paid for — no gate, no unit, no model call, no
new placement. §3 Rule 1.

**Re-checked for ticket 02 (2026-09-17): unchanged.** Resolving or removing an unresolved row raises
no gate, reserves no unit and adds no `PaywallPlacement`. It makes the free tier's routine draft work
in more cases, which is §3 Rule 1 territory, not a gating opportunity.

**One unit per drafting *session*, not per message.** The counting unit for `.coachChat` is
documented as "a sent message"; a drafting session is one unit however many turns it takes, because a
guided conversation (ticket 04, §9c) must never cost a free user their whole month for one routine.
The ViewModel holds the ticket for the life of the session and reserves nothing further — pinned by
`RoutineDraftQuestionTests.wholeConversationCostsOneUnit`.

**It is refunded when the session gave the person nothing:**

- the generation failed;
- it was cancelled mid-stream;
- it succeeded but **nothing in it could be resolved** — the generation worked, the outcome did not.

It is *not* refunded when a usable draft reached the screen and the person discarded it: they got
what the unit paid for. `isTicketRefundable` is tracked separately from the ticket itself, because the
ticket survives a successful draft — that is what makes ticket 04's follow-up message free — while
the refundability does not.

## 9. The UI

**Entry point:** a "Build a routine" capsule chip pinned above the Coach Chat input bar, so it is
reachable from an empty chat and from a full one. Present only while `isAvailable`.

**The sheet** has three faces over one layout — describe, draft, review. The same list streams and
reviews, so the list the person reads while it fills is the list they confirm. `AISurface` provides
the streaming chrome; `AISkeletonBar` fills the name and the first rows before anything has landed.

**The streaming chrome stops when the Coach does.** This sheet is the one place an `AISurface`
stays on screen after its answer lands, and it revealed that the border shimmer and the sparkle
pulse never stopped: both are `repeatForever` animations, which do not end when the flag flips —
only when their value is reset inside a `Transaction` with animations disabled
(`AISurface.stopShimmer()`, `AISparkleView.stopPulsing()`). Found on device 2026-09-25; the fix is in
the shared components, so every Coach surface that stops streaming in place benefits.

**A row is either an answer or a question.** `RoutineDraftRowView` renders a resolved row as the
library exercise's name and its set summary, and an unresolved one on a warning-tinted card: the words
the person used, the same set summary (the figures survive being answered, and showing them says so),
the reason it is unresolved, a chevron onto the picker, and an ✕ that removes it. The two controls sit
side by side rather than nested — a `Button` inside a `Button` swallows the inner tap. Tapping is a
no-op while the draft is still streaming, when the list under the finger is still moving.

**The picker is a push, not a second modal**, through the sheet's own `NavigationStack`
(`navigationDestination(item:)` keyed on the row). Choosing an exercise resolves the row and pops.
Its results are recomputed in `onChange(of: searchText)` into `@State` rather than filtered in `body`,
and the list is a `LazyVStack` — it is the one view here whose content scales with the person's own
library (rendering rules 1 and 3).

### 9a. Editing the draft before Create (ticket 03)

Once the draft is final (`.review`) it is a starting point, not take-it-or-leave-it:

- **Rename** — the name becomes a `TextField` bound to `RoutineDraftViewModel.routineName`. The
  stream writes that property only while `.drafting` (`republish()`), so an edit elsewhere in the list
  never puts the drafted name back. Create trims it and falls back to the default name when empty.
- **Reorder / remove** — a resolved row carries an ellipsis `Menu` (Move up, Move down, Remove);
  `RoutineDraftRow.canMoveUp/canMoveDown` are composed in `RoutineDraftRowComposer` so the menu
  disables the impossible direction without knowing the list. `GroundedRoutineDraft.move(_:by:)`
  (clamped) and `remove(_:)` mutate the draft's array; array position is only turned into the stored
  `RoutineExercise.order` at Create (§7). Chosen over a `List` with `onMove` because the rows sit in
  the `AISurface` card inside the sheet's scroll view — a `List` would have meant rebuilding the sheet.
- **Adjust sets** — tapping a resolved row pushes the app's existing `ConfigureExerciseSetsView`
  (edit mode: `configure_exercise.edit_title`, saves on back too) through the sheet's
  `NavigationStack`, seeded by `configuration(for:)` with the row's last edit or its drafted scheme.
  Its `onSave` lands in `updateConfiguration(_:sets:alternatives:targetRepMin:targetRepMax:)`, which
  stores a `PendingRoutineExercise` in the view model's `edits: [UUID: PendingRoutineExercise]`,
  keyed by drafted-row id. That also means the person can add alternatives and a rep goal here. No
  second set editor exists in the drafting sheet.
- **Value graph until Create** — nothing above touches a `ModelContext`; the `ExerciseSet`s the
  editor returns are uninserted `@Model` instances, exactly as in `CreateRoutineView`.
- **Free** — none of these reserve or refund a unit or call `RoutineDrafting`; asserted in
  `RoutineDraftEditingTests.editingIsFree`.

Removing a row also drops its edit; `clearDraft()` resets the map with the draft. Unresolved rows
keep their ticket 02 controls (picker + ✕); once answered they get the same menu and set editor.

### 9c. Asking for what is missing (ticket 04)

A person types *"a push routine"* or *"chest day"* rather than a specification. The sheet does not
fabricate a routine from it; it asks — one short question at a time — and each answer narrows the
draft until it is complete, then hands off to the same review (§9, §9a) with no separate
confirmation.

**What is missing is decided in Swift, never by the model.** `GroundedRoutineDraft.gaps` is the
completeness predicate, over the grounded draft:

| Gap | When | Question (en) |
|---|---|---|
| `.exercises` | the draft has no exercise — then it is the *only* gap | "Which exercises should this routine include?" |
| `.setCounts(exerciseNames:)` | any exercise has no **stated** set count (`GroundedDraftExercise.isSetCountStated`) | "How many sets for Bench Press, Squat?" |
| `.name` | the name is empty | "What should this routine be called?" |

Ordered most-useful-first, so a person who stops early is left with the most useful draft. Unstated
reps and load are *not* gaps — the ticket names exercises, set counts and name, and those keep their
ticket-01 Swift defaults.

**The questions are Swift's strings, not the model's.** `RoutineDraftQuestion` localizes them
(`ai_coach.routine_draft.question.*`), so they follow the app language, while everything the model
writes (the routine name, the transcribed exercise names) follows the language the person writes in
— without a locale directive, as in the chat. A model-phrased question was deliberately not built:
the predicate already knows exactly what to ask, and a question the model phrased is one more place a
"three is typical" default could slip in, the very thing this ticket forbids.

**How an answer flows.**

- Exercises and set counts go back to the model (`RoutineDrafting.answer(_:to:weightUnit:)`) as a
  **fresh session** whose message is every line the person has said — the description, then each
  answer framed with its question — and which drafts the whole routine from them. Only the
  **finished** re-draft replaces the one on screen: streaming a whole re-draft into the list would
  empty it and refill it under the person's eyes.
- **An answer that yields no exercise never replaces the draft.** When the question was which
  exercises, the sheet stays on it with "Aus der Antwort ließ sich keine Übung übernehmen…"
  (`question.no_exercises`) and the typed answer kept; a re-draft that lost everything the draft had
  gets the generic retry message.
- A **name** is applied in Swift with no model turn — the answer *is* the name.
- A name the draft already had survives a turn that does not restate it
  (`RoutineDraftViewModel.apply`).
- A gap that comes back **unchanged** after its answer is not asked again (`RoutineDraftConversation`
  remembers every gap asked): the answer did not fill it, and repeating the question is a loop. The
  review takes over, with Swift's default as a value the person can change.
- **Until the review, an unstated set count reads "Sets?"**, not "3 sets" — showing the default while
  asking how many would present a guess as data. `RoutineDraftRowComposer(showsDefaults:)`.

**Stopping early.** The question card offers **Review draft** (only when something a Create could
write exists — it moves to `.review` with the defaults) and **Discard** (writes nothing; refunds the
unit if nothing usable was drafted). Closing the sheet is the same as Discard. The stop button during
an answer's turn returns to the same question with the draft intact; a failed answer does the same
and says so under the question (`answerError`), keeping the typed answer. `createRoutine()` refuses
outside `.review`, and rows are not editable while a question is open.

**One allowance unit for the whole conversation.** The unit reserved at `submit()` covers every
answer; `submitAnswer()` never touches the gate. Charging per message would let one routine consume a
free user's month (§3 Rule 1). The refund rules are ticket 01's: the unit stays refundable until
something a Create could write is on screen; a follow-up failure does *not* refund (the session goes
on), and dismissing a session that never produced anything usable does.

**A fresh session per turn — and why there is no overflow handling.** The ticket settled on one
continuing session guarded by the chat's condense-and-retry policy (`ChatOverflowPolicy`, a
Swift-side digest, no prewarm before a respond call). **Device round 6 reversed that** (§6b): a
continuing session kept the model's own invented reply in the transcript, and the next answer
reproduced it. Now `RoutineDraftService` sends each turn to a new `LanguageModelSession` whose only
message is `RoutineDraftInstructions.prompt(from:)` over the person's lines (`turns`, which a line
joins only once its turn has finished, so a thrown or cancelled turn is not repeated; an answer the
ViewModel refuses stays, since it is still the person's own words). Consequences:

- the model never reads anything it wrote, so it cannot copy its own invention forward;
- a turn's context is instructions + schema + a few short lines of the person's, so it cannot
  overflow, and the condense/digest/token-count machinery was removed rather than kept as dead code
  (restore from this ticket's history if turns ever carry model output again);
- no two turns share a session, so the stale-turn and concurrent-request races the first review
  found cannot occur;
- `prewarm()` warms one session that the next turn takes; every later turn builds its own and never
  prewarms it (`prewarm()` needs ≥1 s before a respond call to help — the chat's post-condense
  failures came from exactly that).

**No tools.** Each session registers no `Tool`: structured generation only.

**Deliberately not built:** the person cannot type free-form corrections outside a question ("actually
make it four sets") — edits after the questions are the review's (§9a). A question per exercise for
set counts — one question names all of them and the answer can cover them at once ("four each").

### 9b. The "routine created" confirmation

Create used to close the sheet silently — the routine landed in a tab the person could not see from
the Coach's full-screen cover, with no sign anything had happened. Now the sheet **swaps to a success
face** (`RoutineDraftCreatedView`) and stays until the person taps **Done**:

- **Hero** — a checkmark that draws itself on (SF Symbols 7 *Draw On*, iOS 26:
  `.transition(.symbolEffect(.drawOn))` on a view inserted when the screen reveals — the insertion is
  the trigger), inside an accent disc that springs in, a soft radial glow, two rings rippling out
  once, and an `AISparkleView` popping in at the corner as the Coach's signature.
- **Headline** — `ROUTINE CREATED` eyebrow, the name as written, and a totals line
  ("3 exercises • 10 sets").
- **The exercises**, numbered in saved order with their (possibly edited) summaries, each arriving
  0.07 s after the previous one; then a line saying it is waiting in Routines.
- **A success haptic** — `.sensoryFeedback(.success, trigger:)` on the reveal flag.

Everything is driven by one `@State isRevealed` flipped in `onAppear`; each element carries its own
delayed `.animation(_:value:)`, so the stagger needs no timer. Under Reduce Motion the ripples are
dropped and every element only fades (no offsets, no scale, no delay chain); symbol effects simplify
themselves.

The data is a `CreatedRoutineSummary` value struct built once in `createRoutine()` from exactly what
was written — the resolved rows, numbered, and totals counted from the `PendingRoutineExercise`s —
so the view formats, counts and enumerates nothing (rendering rules 2–4). Plurals use separate
`.one` keys because the app has no stringsdict. `didCreateRoutine` is now derived from
`createdRoutine != nil`; `sheetWasDismissed()` clears it.

**Deliberately omitted: "Show in Routines".** The Coach is a full-screen cover over a `TabView`
with no selection binding, so jumping to the new routine would need app-wide tab-selection and
deep-link plumbing. Done returns to the chat. Restore by adding a tab selection to `ContentView` and
a routine-id deep link if it is wanted.

Research (2026-09-24, via ios-api-researcher): Draw On is iOS 26+ and per-symbol opt-in; plain
`checkmark` / `checkmark.circle` carry draw data, `.fill` variants are unconfirmed — hence the plain
`checkmark` over a drawn disc. Sources: WWDC25 session 337 "What's new in SF Symbols 7"
(https://developer.apple.com/videos/play/wwdc2025/337/),
https://www.hackingwithswift.com/quick-start/swiftui/how-to-make-sf-symbols-draw-themselves,
https://nilcoalescing.com/blog/AnimatingSFSymbolsInSwiftUI/. The success face cannot be reached in
the simulator (no on-device model); the file's `#Preview` is where its motion is checked.

**Verified on iPhone (2026-09-24, user confirmed):** checkmark draw-on, one-shot ripples and success
haptic; name, totals and numbered exercises in the draft's order; no ✕ on the success face; Done
returns to the chat and the routine is in the Routines tab; with Reduce Motion on, the screen only
fades in.

**The "left out" note is now an explanation, not a list.** The names are in the rows above it; the
note says what Create will do with them and that a tap fixes it.

The footer lives in its own `RoutineDraftFooter.swift`, and the "left out" note and the question
card in `RoutineDraftQuestionCard.swift`, so the sheet and its parts each stay under the project's
300-line convention rather than one file being over it.

Rendering rules held deliberately: rows are `RoutineDraftViewModel.Row` **value structs** with a
finished `name` and `summary` — no `@Model` read and no `WeightFormatting` call in a row `body`. The
summary is composed once per snapshot in the ViewModel, reusing the existing `routine.sets_count` /
`set.reps` keys and `WeightFormatting.label`, so it reads exactly like the Create-Routine screen's
own set summary. The "left out" line is likewise joined in the ViewModel
(`unmatchedSummary`), not in the `body`. The scroll content is a `LazyVStack`.

The drafted-exercise list inside `AISurface` is a `LazyVStack` too (since ticket 03), although
`RoutineDraftOutput.exercises` is capped at `.maximumCount(12)` — the rows are the user-scaled part of
the screen, and the `ForEach` is keyed by the stable drafted-row `UUID`.

Every user-facing string is in `en.lproj` and `de.lproj` under `ai_coach.routine_draft.*`; there are
no literal strings in the views.

## 10. Tests

`GymStreakTests/RoutineDraftTests.swift` (doubles in `Support/RoutineDraftTestDoubles.swift`):

- **Grounding** — resolved (library spelling wins over the model's), ambiguous (left out and named),
  no-match (left out and named), unmatched-name de-duplication, Swift-side defaults for unstated
  figures, bounds on absurd ones, pounds→kilograms conversion, order preservation.
- **Mapping** — sequential `order`, one `ExerciseSet` per set count with sequential set order, no
  invented alternatives, rep-range goals only when stated (see `RoutineDraftGoalsTests`), unmatched
  exercises never reaching the transaction.

`GymStreakTests/RoutineDraftGoalsTests.swift` covers ticket 05, each case through a real
`RoutinesViewModel` over an in-memory SwiftData store: a stated range persists as the goal with sets
starting at its low end; a stated rep count is clamped into the range; **no stated range persists
nil/nil and the row reads "No rep goal", never "nil"**; one count copied into both ends is not a
range; one end alone or a reversed pair is no goal; a stated rest lands on every set; the unit is
converted in Swift and corrected when implausible; unstated rest is 60 s; the set editor opens on the
drafted goal and rest and an edit replaces both. The **device probe replays** pin round 8: 90 seconds
drafted as 90 minutes, "1:30" drafted as 180 s, a 6–12 range for a typed 8–12, a "2 Minuten" rest
copied into the load, and loads the person never typed.
- **Preflight ordering** — an ineligible device is never paywalled *even while at the routine cap*;
  a capped free user gets `.routineCap` and spends no allowance; a clean preflight meters nothing.
- **Allowance** — one unit per session across two submits, refund on failure, refund on an
  all-unmatched draft, refund on cancel, `.coachChat` paywall on exhaustion with the typed text kept.
- **Creating** — one write through the shared transaction under the drafted name, the fallback name
  for a nameless draft, and discard/dismiss writing nothing.
- **Confirmation** — Create yields a `CreatedRoutineSummary` with the written name, the resolved
  exercises numbered in saved order (an unresolved row left out closes the gap), the totals line, and
  the singular keys for one exercise / one set; dismissing clears it.

`GymStreakTests/RoutineDraftResolutionTests.swift` covers ticket 02 on the same harness
(`RoutineDraftHarness` in `Support/RoutineDraftTestDoubles.swift`, shared by both files):

- **Ambiguous** — the matched library exercises are carried on the entry and handed to the picker.
- **No match** — no candidates, so the picker is the whole library.
- **The unresolved row** — shows the drafted name and its figures, never a blank or a placeholder.
- **Resolving** — in place, keeping set count, reps, weight and position, and it reaches the
  transaction that way; resolving an already-resolved row is a no-op.
- **Removing** — drops the row and writes nothing.
- **Create** — an unresolved row is excluded from what is written while the rest is created, and a
  draft of nothing but unresolved rows offers no Create at all.
- **Allowance** — resolving and removing consume no further unit.

`GymStreakTests/RoutineDraftQuestionTests.swift` covers ticket 04 on the same harness (the fake's
`answerSnapshots` scripts one stream per answer turn):

- **Provenance** — the device replay (twelve invented rows → empty draft, `.exercises` gap, no list
  shown); folded, plural and German names the person wrote survive; a resolved exercise inside the
  routine name is kept; an invented extra beside real exercises is dropped, noted and never written;
  answer words count as the person's words.
- **Predicate** — no exercises is the only gap; only unstated set counts are named, before the name;
  a named draft with every set count stated is complete; the default is kept but marked unstated;
  resolving a row keeps the flag.
- **Asking** — a thin description asks instead of drafting; answers advance the draft one question at
  a time straight into the review; the answer reaches the model tagged with its gap; unstated sets
  read "Sets?"; a name is applied without a model turn; an existing name survives a turn; an unfilled
  gap is not asked twice.
- **Cost** — a description plus two answers is three model turns and exactly one unit, with no
  prewarm in between.
- **Stopping** — Review draft uses the default; Create is refused while asking; Discard and dismiss
  write nothing and refund a session that gave nothing.
- **Failures** — a failed answer, a re-draft that dropped everything, and an exercises answer from
  which no exercise survives (device round 6 replayed) keep the draft, the question and the typed
  answer; stopping an answer's turn returns to the question.

`turnPromptIsThePersonsLines` pins the turn message (description first, framed answers after, line
breaks inside a line flattened). `CoachPromptGroundingTests` also scans
the three answer prompts, and `routineDraftPromptsNameNoDefault` pins that the drafting prompt (both
units), the answer prompts and both schemas contain no digit, no number word and no exercise name.

`GymStreakTests/RoutineDraftEditingTests.swift` covers ticket 03 on the same harness:

- **Rename** — reaches Create trimmed, and survives later row edits.
- **Reorder** — moves (clamped at the ends) renumber `order` to 0…n in the order the sheet shows.
- **Remove** — a resolved row is left out and the gap in `order` is closed; removing everything
  disables Create.
- **Edit sets** — the editor is seeded with the drafted scheme; a saved edit updates the row summary,
  reopens as edited, follows a later move and reaches Create with its sets and rep goal; untouched
  rows keep the drafted scheme; an unresolved row has nothing to configure.
- **Cost** — rename, move, edit and remove consume no unit and make no second model call.
- **SwiftData round trip** — a real `RoutinesViewModel` over an in-memory container: an edited set
  count, a move and a rename all land in the persisted `Routine`.

`CoachPromptGroundingTests` now also scans `RoutineDraftInstructions` (both units) and the
`RoutineDraftOutput` / `RoutineDraftExercise` generation schemas for data-shaped literals and
programming-construct words.

**A green test proves the prompt is clean, never that the output is.** Whether the model obeys what
it is handed is a device check, and nothing here stands in for one.

## 11. Known limits (by design)

- An unresolved name can be pointed at an existing library exercise or removed, but **not created** —
  there is no "add this to my library" from the picker. A movement genuinely absent from the library
  still has to be added on the Exercises tab first.
- **No adding exercises** to a draft — the sheet edits what was drafted; a missing exercise is
  added after Create on the routine itself, or described in a fresh draft.
- **Follow-ups only answer questions.** There is no free-form "change this" message; a draft is
  changed in the review (§9a).
- **One set scheme per exercise** — every set identical, one rest time for all of an exercise's
  sets; per-set variation is made in the set editor. No supersets (§4a).
- Device verification of the German path and of real model behaviour is a manual check; see §10.
  There is no on-device model in the simulator, so nothing automated stands in for one. Round 1
  (2026-09-16) found the compound-word defect above — fixed and regression-locked; rounds 2
  (2026-09-17) and 3 (2026-09-19, ticket 02's resolution flow) passed.
