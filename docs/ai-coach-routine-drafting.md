# AI Coach — Describe a routine, review the draft, save it

A person taps **Build a routine** in Coach Chat, a sheet opens, they type *"Push day: bench press 3
sets of 8 at 60 kg, incline dumbbell press 3 by 10 at 22 kg"*, and a few seconds later they are
looking at a draft of that routine — its name, and its exercises with their sets, reps and weights.
They tap **Create** and the routine is in the Routines tab and on their watch, indistinguishable
from one they built by hand. They tap **Discard** and nothing was ever written.

**Target:** iOS only. FoundationModels does not exist on watchOS; the watch receives the finished
routine through the ordinary sync path with no change of its own.

**Status:** ticket 01 of `.scratch/ai-coach-create-routine/` — the tracer bullet. Ticket 02 makes
unmatched names resolvable, 03 makes the draft editable, 04 lets the conversation ask questions
back, 05 makes the sets richer.

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
| Domain/Models | `AICoach/RoutineDraftModels.swift` | `RoutineDraftSnapshot` / `RoutineDraftEntry` (what the model produced), `GroundedRoutineDraft` / `GroundedDraftExercise` (what Swift decided) |
| Domain/Interfaces | `AICoach/RoutineDrafting.swift` | the drafting boundary |
| Domain/Services | `AICoach/RoutineDraftGrounder.swift` | the grounding pass — pure logic, isolation-agnostic |
| Data | `AICoach/RoutineDrafting/RoutineDraftInstructions.swift` | the system prompt |
| Data | `AICoach/RoutineDrafting/RoutineDraftService.swift` | the `LanguageModelSession` + snapshot mapping |
| Presentation | `ViewModels/RoutineCreating.swift` | a *name* for the existing creation seam |
| Presentation | `ViewModels/AICoach/RoutineDraftViewModel.swift` | preflight, stream, ground, persist |
| Presentation | `ViewModels/AICoach/GroundedRoutineDraft+Pending.swift` | draft → `[PendingRoutineExercise]` |
| Presentation | `Views/AICoach/RoutineDrafting/RoutineDraftSheet.swift` | the sheet |
| App | `AppDependencies.swift` | `routinesViewModel`, `makeRoutineDraftService()`, `makeRoutineDraftViewModel()` |

`Domain/` imports no SwiftUI and references no concrete Data type. `RoutineDraftOutput.swift` imports
FoundationModels, exactly as `AICoachOutputs.swift` already does.

## 3. The drafting boundary hands out plain values, not a `ResponseStream`

Every other AI-coach protocol (`AICoachServicing`) hands the ViewModel a
`LanguageModelSession.ResponseStream<Output>` directly. `RoutineDrafting` deliberately does not:

```swift
func draft(from description: String, weightUnit: WeightUnit)
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
    let routineName: String
    let exercises: [RoutineDraftExercise]     // .minimumCount(1), .maximumCount(12)
}
@Generable struct RoutineDraftExercise {
    let name: String        // copied from the description, in the description's language
    let setCount: Int       // 0 == "the description did not say"
    let reps: Int           // 0 == "the description did not say"
    let weight: Double      // in the reader's display unit; 0 == no load / bodyweight
}
```

**No field is Optional, on purpose.** A `@Generable` optional has already produced the literal string
`nil` in rendered output in this app (the period recap's `correlationHighlight`, German, on device,
2026-08-30). Absence is carried by a sentinel number — `RoutineDraftGrounder.unstatedNumber` — and
decided in Swift. Zero is the sentinel because it is the one value the model can be asked for in
plain language without naming a programming construct, and because a real set count, rep count or
load of zero is meaningless anyway, so nothing legitimate is shadowed. Ticket 05 revisits this
deliberately when rep goals and rest times arrive.

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

## 6. The grounding pass

`RoutineDraftGrounder` is pure logic over already-fetched `Exercise` models — `Domain/`,
isolation-agnostic, no store access, no formatter. Two jobs:

**Resolve every name**, through the existing `ExerciseNameResolver` (folded, diacritic- and
case-insensitive, cross-language, `.resolved` / `.ambiguous` / `.noMatch`). **There is no second
matcher in this app.**

- `.resolved([Exercise])` → the first match. The resolver only aggregates rows that share one folded
  *name*, so this is not a coin toss between different exercises.
- `.ambiguous` and `.noMatch` → **excluded from the draft and named on screen.** For this ticket they
  are the same outcome: there is no library exercise the draft may safely claim. Ticket 02 splits
  them apart and makes both answerable by the person. The one thing this surface may never do is
  quietly drop something that was asked for, or invent a library entry to hold it.

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
animating*. `RoutineDraftGrounder.resolutions` caches the answer per drafted name, so each distinct
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

`GroundedRoutineDraft.pendingExercises()` is the whole mapping: `order` comes from the draft's own
position (which is how the described order becomes the routine's order), and each drafted exercise
becomes `setCount` identical `ExerciseSet`s at `RoutineDraftGrounder.defaultRestTime`. Alternatives
and rep-range goals are left empty — nothing in a typed description expresses them, and inventing
either would be the app guessing on the person's behalf at the exact moment it writes to their store.

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

**One unit per drafting *session*, not per message.** The counting unit for `.coachChat` is
documented as "a sent message"; a drafting session is one unit however many turns it takes, because a
guided conversation (ticket 04) must never cost a free user their whole month for one routine. The
ViewModel holds the ticket for the life of the session and reserves nothing further.

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

The footer lives in its own `RoutineDraftFooter.swift` — the sheet and its bottom bar are each under
the project's 300-line convention rather than one file over it.

Rendering rules held deliberately: rows are `RoutineDraftViewModel.Row` **value structs** with a
finished `name` and `summary` — no `@Model` read and no `WeightFormatting` call in a row `body`. The
summary is composed once per snapshot in the ViewModel, reusing the existing `routine.sets_count` /
`set.reps` keys and `WeightFormatting.label`, so it reads exactly like the Create-Routine screen's
own set summary. The "left out" line is likewise joined in the ViewModel
(`unmatchedSummary`), not in the `body`. The scroll content is a `LazyVStack`.

The one `ForEach` that is *not* in a lazy container is the drafted-exercise list inside `AISurface`.
That is deliberate and bounded: `RoutineDraftOutput.exercises` is capped at `.maximumCount(12)`, so it
does not scale with user data. **If ticket 05 raises that cap, this needs a lazy container.**

Every user-facing string is in `en.lproj` and `de.lproj` under `ai_coach.routine_draft.*`; there are
no literal strings in the views.

## 10. Tests

`GymStreakTests/RoutineDraftTests.swift` (doubles in `Support/RoutineDraftTestDoubles.swift`):

- **Grounding** — resolved (library spelling wins over the model's), ambiguous (left out and named),
  no-match (left out and named), unmatched-name de-duplication, Swift-side defaults for unstated
  figures, bounds on absurd ones, pounds→kilograms conversion, order preservation.
- **Mapping** — sequential `order`, one `ExerciseSet` per set count with sequential set order, no
  invented alternatives or rep-range goals, unmatched exercises never reaching the transaction.
- **Preflight ordering** — an ineligible device is never paywalled *even while at the routine cap*;
  a capped free user gets `.routineCap` and spends no allowance; a clean preflight meters nothing.
- **Allowance** — one unit per session across two submits, refund on failure, refund on an
  all-unmatched draft, refund on cancel, `.coachChat` paywall on exhaustion with the typed text kept.
- **Creating** — one write through the shared transaction under the drafted name, the fallback name
  for a nameless draft, and discard/dismiss writing nothing.

`CoachPromptGroundingTests` now also scans `RoutineDraftInstructions` (both units) and the
`RoutineDraftOutput` / `RoutineDraftExercise` generation schemas for data-shaped literals and
programming-construct words.

**A green test proves the prompt is clean, never that the output is.** Whether the model obeys what
it is handed is a device check, and nothing here stands in for one.

## 11. Known limits (this ticket, by design)

- An unmatched or ambiguous name is reported but not **resolvable** — no "did you mean?" and no
  "create this exercise". Ticket 02.
- The draft is **read-only**: no editing a set count, reordering, or removing an exercise before
  Create. Ticket 03.
- **One turn.** The session is retained and the allowance already treats a session as one unit, but
  there is no UI for a follow-up message. Ticket 04.
- **One set scheme per exercise** — every set identical, no rep-range goals, no per-set rest.
  Ticket 05.
- Device verification of the German path and of real model behaviour is a manual check; see §10.
  Round 1 (2026-09-16) found the compound-word defect above; it is fixed and regression-locked, and
  the round needs repeating.
