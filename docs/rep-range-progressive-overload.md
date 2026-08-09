# Rep Range Goal & Progressive Overload

> **Note (2026-07):** The Routines tab was visually redesigned (see [routines-exercises-redesign.md](./routines-exercises-redesign.md)), and the routine detail again in **redesign v2 (2026-07-28)**. Rep-range/overload *logic* is unchanged throughout. In v2 the rep goal is a tappable **"Ziel %d–%d Wdh." chip** on every exercise card (ghost/dashed when unset) that opens `RepRangeInlineEditor` in place — `RepRangeConfigView` was deleted. `ExerciseHeaderView` lives in `RoutineDetailComponents.swift`; `RoutineSetRowView` was replaced by `RoutineSetStepperRow` in `RoutineSetsEditor.swift`.

## Feature Description

Adds a **rep range goal** (e.g., 8-12 reps) to exercises within routines. When all sets reach the upper limit, the app celebrates and suggests a weight increase with options to auto-apply (new weight + reset reps to lower limit). This implements the "Double Progression" model - the industry-standard approach for progressive overload.

## User Flow

1. **Configure**: Either **while adding the exercise** — the "Wiederholungsziel" section of `ConfigureExerciseSetsView` (added with the configure-screen redesign, 2026-08-09; the goal travels through `onExerciseConfigured` → `RoutinesViewModel.addConfiguredExercise` / `PendingRoutineExercise` → `createRoutine`, and through `WorkoutViewModel.addExerciseToWorkout` for exercises added mid-workout) — or afterwards in the routine editor via the "Ziel" chip on any exercise card
2. **Train**: During workouts, rep progress badges show how close each set is to the upper limit
3. **Achieve**: When all sets reach the upper limit, a gold banner appears suggesting a weight increase
4. **Progress**: Tap "Increase" to open the weight increase sheet, select an increment (1.25/2.5/5 kg), and apply
5. **Reset**: All sets update to the new weight with reps reset to the lower limit
6. **Second chance (completion screen)**: If the mid-workout banner was skipped or dismissed, the post-workout completion screen (`SaveWorkoutView`) shows an actionable "Ready for More Weight" card per qualifying exercise — same increment sheet, same apply path — with an Undo while the screen is still open
7. **After the fact (history)**: Opening a past session in `WorkoutDetailView` re-surfaces the same card for any exercise that maxed its rep range. Applying here bumps the **live routine template only** for future workouts — it never rewrites the immutable history — so there is no Undo. If the routine/exercise no longer exists, the achievement still shows but the CTA becomes a muted no-op note. An increase already applied from the Watch recap shows as confirmed rather than actionable (see "Correlation" under ticket 05)
8. **On Apple Watch**: the same two chances exist — a mid-workout suggestion (ticket 04) and an actionable prompt in the post-workout recap (ticket 05), both applying to the routine template only

## Architecture

### Shared Domain Logic — `ProgressiveOverloadService`

**`Domain/Services/ProgressiveOverloadService.swift`** (added 2026-07) is the single source of truth for the overload domain logic. It is pure value math (Foundation only — no SwiftData/SwiftUI), so future surfaces (completion screen, history, watch — the watch target gets its own file copy per the project's target-sharing convention) apply identical rules:

- `templateQualifiesForIncrease(reps:targetRepMax:)` — routine editor qualify: every template set's reps ≥ max (no completion concept)
- `workoutQualifiesForIncrease(sets:targetRepMax:overloadAlreadyApplied:)` — workout qualify: all sets completed AND actual reps ≥ max; `overloadAlreadyApplied` short-circuits to `true`
- `increasedWeight(_:increment:loadBehavior:)` — direction-aware weight step: counterweight assistance *subtracts* the increment (clamped at 0), resistance adds it
- `applyIncrease(toWeights:increment:targetRepMin:loadBehavior:)` — returns the new weight per set + the reps every set resets to (range minimum)

`ProgressiveOverloadIncrement` lives alongside it and is the **shared weight-step scale for both platforms**, so they cannot drift apart again (they did: the watch gained 0.5 first, on 2026-07-27).

- `options` = `[0.5, 1.25, 2.5, 5.0]`, `default` = 2.5 — the **presets**. 0.5 is the micro-loading step; the rest are standard plate steps. iOS `WeightIncreaseSheet` renders exactly these as a radio list, and the watch offers them as quick-select chips.
- `minimum` / `maximum` / `step` = 0.25 / 50 / 0.25 — **free selection**, used by the watch's Digital Crown so a user wanting an unusual jump is not boxed into the presets (2026-07-29). `normalized(_:)` clamps and snaps to the grid.

Two constraints worth keeping: the 0.25 stride exists so every preset — 1.25 included — lands exactly on the grid and stays reachable/highlightable, and the maximum is finite on purpose. Apple's unbounded `digitalCrownRotation(_:onChange:onIdle:)` overload carries **no stride and no haptic detents**, so it is the wrong tool for a stepped value; the bounded/strided overload with a generous ceiling is the idiomatic choice.

**Display all of these with two fraction digits, through the locale-aware `Measurement` path** — `%.2g` (two *significant* digits) and the default `Measurement` precision both round 1.25 to a misleading "1.2" (shipped on both surfaces before 2026-07-28), and a bare unit-less number sits inconsistently beside a converted one in a non-metric locale.

The model computed properties (`RoutineExercise.allSetsAtUpperLimit`, `WorkoutExercise.allCompletedSetsAtUpperLimit`) and both ViewModels delegate to this service; no qualify/apply math is duplicated anywhere else. Covered by `GymStreakTests/ProgressiveOverloadServiceTests.swift` (Swift Testing).

**Root cause fixed during consolidation:** `RoutinesViewModel.applyProgressiveOverload` previously always did `weight += increment`, even for counterweight-assistance exercises — while `WeightIncreaseSheet` displayed "−increment" and `WorkoutViewModel` correctly subtracted. Applying an increase from the **routine editor** on an assistance exercise therefore *raised* the assistance weight (making the exercise easier) despite the sheet promising a reduction. The shared service's direction-aware math now applies in both paths. The same +only math also existed in `ActiveWorkoutView`'s post-apply confirmation chip (display only); it now uses `increasedWeight` too.

### Data Model

**`RoutineExercise`** (Models.swift):
- `targetRepMin: Int?` - Lower bound of rep range (e.g., 8)
- `targetRepMax: Int?` - Upper bound of rep range (e.g., 12)
- `hasRepRangeGoal: Bool` - Computed: both fields non-nil
- `allSetsAtUpperLimit: Bool` - Computed: all sets at/above max reps

**`WorkoutExercise`** (Models.swift):
- `targetRepMin: Int?` / `targetRepMax: Int?` - Denormalized from RoutineExercise at workout creation
- `progressiveOverloadApplied: Bool` - Flag set when progressive overload is applied during a workout
- `hasRepRangeGoal: Bool` / `allCompletedSetsAtUpperLimit: Bool` - Computed properties
- `allCompletedSetsAtUpperLimit` returns `true` immediately when `progressiveOverloadApplied` is set (the user already hit the upper limit to trigger overload)
- Both `allSetsAtUpperLimit` (RoutineExercise) and `allCompletedSetsAtUpperLimit` (WorkoutExercise) delegate to `ProgressiveOverloadService` — the properties are thin adapters mapping model sets to plain values

**Design decisions:**
- Optional `Int?` fields with nil defaults for seamless CloudKit/SwiftData lightweight migration
- Rep range on `RoutineExercise` (not `Exercise`) so different routines can use different ranges
- Denormalized to `WorkoutExercise` so history shows the range active at workout time
- When progressive overload is applied, `plannedWeight`/`plannedReps` on `WorkoutSet` are snapshotted from the current `actualWeight`/`actualReps` to preserve the user's actual performance, and `progressiveOverloadApplied` switches all comparison/history/chart logic to read the planned values. **`actualWeight`/`actualReps` are left at the performance** — the increase belongs to the next workout, not this one (see "The increase never touches the workout in progress" below).

### Watch Models

**WatchExercise** / **CompletedWatchExercise** / **ActiveWorkoutExercise** (WatchModels.swift on both targets):
- `targetRepMin: Int?` / `targetRepMax: Int?` added to all exercise structs
- Backward compatible: optional Codable fields default to nil when absent in JSON
- `ActiveWorkoutExercise` gains `hasRepRangeGoal` and `allCompletedSetsAtUpperLimit` computed properties
- `ExerciseSummary` gains `repGoalAchieved: Bool` for watch workout summary

### ViewModel

**`RoutinesViewModel`**:
- `updateRepRange(for:min:max:)` - Sets/clears rep range on a RoutineExercise
- `applyProgressiveOverload(for:weightIncrement:)` - Increases weight and resets reps to min for all sets, via `ProgressiveOverloadService.applyIncrease`

**`WorkoutViewModel`**:
- `applyProgressiveOverload(for:weightIncrement:)` - Gets the new weights/reps from `ProgressiveOverloadService.applyIncrease` **for the routine template only** (the workout in progress is never rewritten — see "The increase never touches the workout in progress"), and owns the persistence workflow around it: planned-value snapshotting, setting `progressiveOverloadApplied`, recording the announced new weight for the confirmed card, and saving. Also captures an in-memory pre-apply snapshot (per-set planned/actual values + template set values) keyed by `WorkoutExercise.id` to power Undo
- `routineExercise(for:)` - Resolves the routine-template slot a `WorkoutExercise` originated from, swapped or not: matches by `routineExerciseId` (stable slot identity) first, falls back to the originally-planned exercise id/name for legacy data (mirroring `updateRoutineTemplate`)
- `performedExercise(for:)` / private `alternativeEntry(for:)` - For a swapped exercise, resolve the performed alternative's library `Exercise` and its `RoutineExerciseAlternative` entry. **Swap rule (2026-07 fix):** applying overload on a swapped exercise writes into the *alternative's own set scheme* (`AlternativeExerciseSet`), never the primary slot's sets — the same rule `updateRoutineTemplate` follows. Before this fix the whole overload path was dead for swaps: the mid-workout banner resolved the slot by performed-exercise name, which never matches the primary, so "Increase" was a silent no-op
- `overloadSuggestionExercises` - The completion screen's eligibility list: rep goal maxed AND (already applied OR a persistable template target exists — the slot's sets, or the alternative's set scheme for swaps)
- `undoProgressiveOverload(for:)` / `canUndoProgressiveOverload(for:)` - Reverts an overload applied during this session from the completion screen: restores the sets' pre-apply planned/actual values, clears `progressiveOverloadApplied`, and restores the template's set scheme. Snapshots are in-memory only and cleared when the session ends (save or discard), so undo is available exactly while the completion screen can still be shown
- `applyProgressiveOverloadFromHistory(from:for:weightIncrement:)` - The **history (after-the-fact)** apply path. Resolves the live template from the *completed session's* `routine` (not `currentSession`) via the routine-parameterized `routineExercise(in:for:)`/`alternativeEntry(in:for:)`, bumps the slot's sets (or the swapped alternative's set scheme) through `ProgressiveOverloadService.applyIncrease`, and returns the new weight. **Never touches the historical `WorkoutExercise`/`WorkoutSet` or the `progressiveOverloadApplied` flag** — history is immutable. Returns `nil` (no-op) if the routine/exercise was edited/deleted. `hasResolvableOverloadTemplate(from:for:)` and `performedExercise(in:for:)` are its resolution/display companions. The generic `applyOverloadToTemplateSets(_:weightKey:repsKey:…)` bumps either template set type (`ExerciseSet`, `AlternativeExerciseSet`) via key paths, avoiding duplicated increment/reset math

## Components

### iOS Components

| Component | File | Description |
|-----------|------|-------------|
| `RepRangeInlineEditor` | Views/Routines/RoutineParameterEditors.swift | Chip-triggered inline editor: 4–6 / 8–12 / 12–15 preset segments + an "Eigen" mode with min/max `CompactStepper`s + "Kein Ziel". Replaced `RepRangeConfigView` (deleted) in redesign v2, 2026-07-28 |
| `ProgressiveOverloadBanner` | Views/Components/ProgressiveOverloadBanner.swift | Gold/orange banner shown when all sets reach upper limit |
| `WeightIncreaseSheet` | Views/Components/WeightIncreaseSheet.swift | Bottom sheet for selecting weight increment. Reads `ProgressiveOverloadIncrement.options` (+0.5/+1.25/+2.5/+5 kg) — the same list the watch picker uses. Value-based with two inits: `init(routineExercise:)` shows template values (routine editor), `init(workoutExercise:)` shows performed actual values (active workout + completion screen — correct for swapped exercises, whose weights never live on the primary template sets) |
| `ProgressiveOverloadCard` | Views/Components/ProgressiveOverloadCard.swift | Achievement card (from the Claude Design "Progressive Overload" handoff, Surface 1): orange actionable state with per-set recap + full-width increase CTA, and a quiet confirmed state with the new weight and Undo. Reuses `ExerciseAvatarView` (muscle color + equipment glyph — the app's avatar idiom, deliberately not the mock's initials). Set recap hides at accessibility Dynamic Type sizes; title + action always stay visible. Shared by the completion screen and history: history-only params (`appliedOverride`/`appliedWeight` force the confirmed state and supply its weight because the immutable history can't be read for it; `isTemplateUnavailable` swaps the CTA for the muted no-op note) default to the completion-screen behavior |

### Integration Points

| View | Integration |
|------|-------------|
| `RoutineDetailView` | "Ziel" chip → `RepRangeInlineEditor` (always visible, works on a collapsed card) + `ProgressiveOverloadBanner` at the top of the expanded body |
| `ExerciseHeaderView` | Subtitle shows "3 sets \| 8-12 reps" when configured |
| `RoutineSetStepperRow` | Rep value colored by range position (at/above max → warning orange, in range → tint, below → muted). The v1 "X/max" badge was dropped in redesign v2 — the row now carries two steppers and had no room for it |
| `ActiveWorkoutView` | Rep progress badges on sets + ProgressiveOverloadBanner |
| `SaveWorkoutView` | "Ready for More Weight" section: one `ProgressiveOverloadCard` per exercise in `WorkoutViewModel.overloadSuggestionExercises` (replaced the passive trophy section 2026-07), section header shows a pending-suggestion counter (orange; turns green once one was applied). Applying opens `WeightIncreaseSheet(workoutExercise:)` and calls `WorkoutViewModel.applyProgressiveOverload`; exercises overloaded mid-workout appear in their confirmed state. No persistable template target (slot or alternative entry) → no CTA |
| `WorkoutDetailView` | "Ready for More Weight" section (after the stat grid): one `ProgressiveOverloadCard` per exercise whose completed sets maxed the rep range — re-surfacing the achievement the history redesign dropped. Applying opens `WeightIncreaseSheet(workoutExercise:)` and calls `WorkoutViewModel.applyProgressiveOverloadFromHistory`, which bumps the **live routine template only** — the historical `WorkoutExercise`/`WorkoutSet` are never rewritten. Applied state (and the shown new weight) is tracked in view-local `@State` since the immutable history can't hold it; no Undo. Exercises overloaded during that workout show their confirmed state directly. If the source routine/exercise was edited/deleted, the card keeps the achievement but replaces the CTA with a muted "routine no longer available" note (`rep_range.overload_card.routine_unavailable`) |

### Watch Integration

| View | Integration |
|------|-------------|
| `WatchWorkoutSummaryView` | Actionable per-exercise overload prompt (applied / superseded / actionable) — see "Post-workout summary progressive overload" below. The plain trophy icon remains only where no prompt applies |
| `ActiveWorkoutView` | Mid-workout suggestion capsule, increment picker, and confirmation — see "Mid-workout progressive overload on Apple Watch" below |

Between 2026-07-25 and ticket 04 below, `targetRepMin`/`targetRepMax` rode along
in the watch payload but **no watch view rendered them**: the only rep-range goal
text + color coding lived in the unused legacy `ExerciseSetView`, deleted with the
rest of the dead watch views, and the live set screen (`FullScreenSetEditorView`)
never had it. The rep range is now *used* on watch — it drives overload
qualification — but there is still no dedicated goal indicator on the set screen;
recover that rendering from git history if it is wanted.

## Mid-workout progressive overload on Apple Watch (ticket 04, 2026-07-27)

Applying a weight increase is now possible from the Watch, mid-workout, without
the iPhone being reachable. The flow is **one modal sheet** whose steps switch
internally:

1. Completing a set that makes every set of an exercise reach the rep-range
   maximum presents the **suggestion**: what happened, the exercise, and one
   recommended action.
2. One tap on "+2.5 kg · all sets" applies the default increment. "Change" swaps
   in the Digital-Crown **increment picker** with a live preview of the resulting
   weight — its Apply and Back live in the navigation bar, and it never scrolls
   (see "Why the picker has no `ScrollView`"); "Later" dismisses for that
   exercise only.
3. A green **confirmation** reports the new weight and the reps the template
   resets to, then returns to the workout.

Dismissing the sheet (swipe or crown) is routed by step: suggestion/picker mean
"Later", confirmation means "acknowledged", and a dismissal during the in-flight
apply is ignored. The user is mid-workout and must never be trapped.

The confirmation means **durably applied on this Watch for future workouts** — not
that the iPhone has already committed it. That distinction is deliberate: the
transaction may still be pending while the phone is unreachable.

**Why a sheet** (revised 2026-07-29 after device testing and an API-research
pass). This shipped first as a bottom-anchored floating card over the live
workout, following the design mock literally. On device that read as un-native and
left the workout's set controls visible and apparently tappable around it. Apple's
HIG points custom-content prompts at **sheets** — `alert` and `confirmationDialog`
are plain title/message/button anatomy and cannot carry the icon, computed weight,
and resulting-weight preview — and on watchOS **a sheet is always modal**, so it
blocks interaction with the presenter for free. That is the idiomatic answer to
the exposed-controls problem; a dimming scrim is an iOS habit that would waste
scarce space on a 41 mm screen.

Two things that fix did *not* change, and must not be assumed:

- **It is not what protects the data.** Set completion was already blocked by
  `isWorkoutInputSuspended` (`canMutateWorkout` folds it in, and
  `toggleSetCompletion` guards on it), so a stray tap under the old card silently
  no-opped rather than completing a set. The sheet fixes *perceived* correctness.
- **The Action Button is unaffected by presentation style.** It arrives as a
  donated App Intent that calls the view model directly, bypassing the SwiftUI
  hierarchy entirely, so no sheet/cover/alert suppresses it. `handleActionButtonPress`
  guarding `isWorkoutInputSuspended` remains the only thing that stops it.

The steps switch content inside that one sheet rather than pushing, because the
workout owns exactly one `NavigationStack` and the in-workout-editing tickets
forbid a second one or a competing sheet. The former
`WorkoutRoute.overloadPicker` case was deleted with that change.

If the target stops being resolvable while its step is on screen (slot removed or
swapped before `revalidateOverloadPresentation` closes the flow), the sheet shows
an explicit "no longer part of the workout" message with a Close button — never a
blank modal, and never a silent auto-apply.

### It is a payload kind, not a second sync system

Progressive overload is a **template-only kind** of the generic
`TemplateTransactionEnvelope` established by in-workout-editing ticket 05. It adds
no queue, inbox, receipt ledger, acknowledgment protocol, routine authority, or
WatchConnectivity lifecycle owner. It reuses, unchanged: the stable transaction
id + persistent sender epoch, the per-routine monotonic sequence and FIFO head
gate shared with **all** template-mutating kinds, the throwing atomic
`WatchSyncStateStore` write, the `sendMessage` fast path plus `transferUserInfo`
durable path with `outstandingUserInfoTransfers` suppression, the serialized iOS
inbox with receiver-side sequence enforcement, the
`committedAwaitingContext` → `readyToAcknowledge` receipt phases, the versioned
terminal acknowledgment, and the receiver-authorized routine epoch/generation.
Full protocol: `docs/watch-sync.md`.

**The envelope's `workoutID` is nil for this kind, and that is load-bearing.**
`TemplateTransactionEnvelope.isInternallyConsistent` enforces it, and
`WatchWorkoutInboxStore.store(transactionData:)` rejects a violation. The reason:
`WatchSyncStateStore.entry(id:)`, `advance`, `quarantine`, and `retire` all match
on `workoutID`, so an overload envelope carrying the *active workout's* id would
make the later `enqueue(workout)` find the overload entry and return it — silently
never enqueueing the completed workout at all (no history, no HealthKit ingest).
Source-workout correlation, if ever needed, belongs inside the payload.

### Wire contract

`WatchProgressiveOverloadModels.swift` (identical copy in both targets):

- `WatchProgressiveOverloadIntent` — `schemaVersion`, `routineExerciseID`,
  optional `alternativeID`, `targetRepMin`, `setChanges`.
- `WatchTemplateSetChange` — `setID`, `expectedReps/Weight`, `proposedReps/Weight`.

Values are **absolute, never deltas**, so duplicate delivery cannot increment
twice. Expected values come from the latest **effective routine template scheme**
(authoritative base + pending optimistic overlay), never from the workout's
performed values — so consecutive overloads in one workout build on each other,
and a template the user edited on iPhone is detected as a conflict instead of
being overwritten. `isWellFormed` checks supported schema, positive rep minimum,
non-empty unique set ids, finite non-negative weights, and that every
`proposedReps` equals `targetRepMin`.

A counterweight-assistance exercise already at zero assistance does **not**
qualify: the zero clamp would make every proposed value equal its expected value,
so applying would stage a no-op transaction and still announce "Increased to
0 kg". `isAlreadyAtMinimumAssistance` suppresses the suggestion in that case.

`CompletedWatchWorkout` also gains optional `overloadAppliedExerciseIDs` and
`WatchExerciseAlternative` gains optional `targetRepMin`/`targetRepMax`. Both
decode as absent on old builds.

### iOS application (three-way, all-or-nothing)

The Domain layer never sees the Codable wire type: the coordinator maps it into
`Domain/Models/IncomingProgressiveOverload.swift` via
`WatchProgressiveOverloadIntent.toIncomingProgressiveOverload()`, the same
boundary rule `IncomingWatchWorkout` exists to state. The mapper is deliberately
total — an unsupported `schemaVersion` becomes `isSchemaSupported == false` rather
than nil, so the receiver can still return a versioned terminal rejection instead
of stranding the Watch's transaction.

`WatchTemplateTransactionService+ProgressiveOverload.swift` resolves the target by
stable id only — slot, then the alternative's own scheme when `alternativeID` is
set, never by display name — and compares each set against the **current**
template:

| Current value | Outcome |
|---|---|
| equals `expected` | stage `proposed` |
| equals `proposed` | already satisfied, idempotent no-op |
| a third value, or the set/slot/alternative/routine is missing | **reject the entire transaction** |

A rejection leaves the routine byte-for-byte untouched and converges the Watch's
optimism through the ordinary acknowledgment + authoritative-context flow. It
never creates workout history: a template-only transaction legitimately has no
workout, and fabricating a placeholder session would invent training the user
never did.

### Why the completed workout can't regress the overload

This is the subtle part. The iOS invariant
(`WorkoutViewModel.applyProgressiveOverload`) is that the flag and the planned
snapshot are **one unit**: applying mirrors the performance into
`plannedReps/plannedWeight` and sets `progressiveOverloadApplied` — which
switches every aggregator (`WorkoutSession.aggregates`, charts, personal
records, all four AI Coach aggregators) to read the planned values. Setting one
without the other corrupts volume, charts, and records: the flag alone makes
them report the original *template* numbers as if they had been performed.

The Watch mirrors that snapshot exactly and reports the affected slots in
`overloadAppliedExerciseIDs`. On ingest, `WatchWorkoutIngestionService` sets
`progressiveOverloadApplied` for exactly those exercises, so history reads the
performed values back out of the planned fields.

Because those sets now legitimately have `actual != planned`, the generic
completed-workout set writeback would otherwise replay the *performed* values over
the template weights the overload transaction just committed. Both sides exclude
them: `WatchTemplateTransactionService+Validation.validateMerge` and the Watch's
`WatchRoutineTemplateFold`. The product rule this encodes: **once overload is
applied for a target during a workout, later edits to those performed sets stay
history-only and cannot silently replace the chosen next-workout template.** The
same slots are also excluded from `hasModifiedSets`/`modifiedSetsCount`, so the
finish dialog does not prompt to persist a change that already has its own
transaction. Structural add/remove intent for the same slot is unaffected.

### Ordering against completed-workout transactions

The per-routine FIFO orders both kinds against each other. A mid-workout overload
takes sequence N; the later "Save & Update Template" workout takes N+1 and cannot
overtake it. **Consequence accepted deliberately:** while an overload is pending
(iPhone off), that routine's later template workout waits behind it — identical to
two consecutive template workouts today. A workout saved *without* the template
update carries no template intent, is never FIFO-gated, and reaches History
immediately.

### Alternatives

Ticket 04 activates the documented alternative-rep-range restore path.
`RoutineExerciseAlternative.targetRepMin/Max` now populate into routine snapshots.
On swap, `ActiveWorkoutExercise` captures the primary range into
`originalTargetRepMin/Max` and adopts the alternative's own range, so a swapped
exercise qualifies against the range it was actually performed under. Revert
restores the primary range through the *same* code path (`swapTargets` carries the
captured range on the synthetic revert entry), so there is no separate branch to
drift. The fields survive full held-routine anchors and optimistic overlay folding.

### Watch lifecycle integration (extended, never duplicated)

One `WatchOverloadPresentation` value drives the whole surface — not competing
booleans — and every case carries the **stable slot UUID**, never an array index
or a model copy. `setOverloadPresentation` is the single mutation point, which is
what keeps the coupled side effects from drifting:

- **Input suspension** reuses ticket 06's existing `isWorkoutInputSuspended`, so
  the Action Button and Double Tap cannot complete another set during the flow.
- **The rest timer keeps running**; only `isRestTimerMinimized` is set, so its
  full-screen overlay steps aside and cannot cover the sheet's dismissal chrome.
  The suggestion is raised *after* the rest timer starts, because `startRestTimer`
  resets that flag. The overlay is **not** unmounted while the sheet is up: a
  watchOS sheet is a separate presentation layer above the presenter, so a sibling
  view can never cover it anyway, and removing it would discard the
  `@Namespace` the large↔minimized morph depends on (see the ownership note in
  `WorkoutRestTimerOverlay.swift`).
- **Display data is resolved once per step** into `WatchOverloadDisplay`, not per
  render. The sheet's `body` reads only that value and the presentation state —
  the earlier version called back into the view model for the exercise, its
  template scheme, and its load behavior, which walked the routine list on every
  heart-rate/elapsed-time tick because the view model publishes those too.
- **Auto-finish**: a qualifying *final* set cancels the retained delayed
  auto-finish task and opens the suggestion instead; Apply or Later re-enters the
  one `autoFinishWorkout()` path exactly once. No second, unretained finish task.
- **Terminal transition** reuses the single `isEnding` owner; entering it dismisses
  any overload surface without staging a transaction.
- **Navigation**: the increment picker is a content step inside the one overload
  sheet — no competing sheet, no pushed route on the workout's stack. The picker
  step does host its own `NavigationStack`, which is the root of the **sheet's**
  hierarchy: a modal presentation is a separate context, so it is not the
  "second stack in the workout hierarchy" the in-workout-editing rule forbids.

### Why the picker has no `ScrollView` (2026-07-29)

The picker binds the Digital Crown to the weight value, so **the crown cannot
also scroll the screen** — a crown-focused control and a scroll container compete
for the same physical input, and focus does not reliably return to the control
after a touch-scroll. Its first version wrapped everything in a `ScrollView` and
pushed the Apply button below the fold, reachable only by touch-scrolling. That
is the failure this layout exists to prevent, so **do not reintroduce a
`ScrollView` here.**

Everything fits instead, bought with two structural moves:

- the exercise name is an **inline navigation title**, not a content row;
- Apply and Back are **toolbar items** (`.confirmationAction` / `.cancellationAction`,
  which watchOS places in the navigation bar), not full-width content buttons.

The "current → new weight" subtitle was dropped as redundant: the value card
already shows the resulting weight. The `‹` `›` step buttons stay — HIG requires
crown interactions to have a touch equivalent, and they cost no vertical space by
sitting inline with the card. The card is sized with `containerRelativeFrame`
rather than a fixed height so it adapts to the case size.

At accessibility Dynamic Type sizes the **preset chips row is dropped**
(`dynamicTypeSize.isAccessibilitySize`) rather than allowing overflow — the crown
still reaches every value the chips offered. If a future change makes even the
crown row overflow, the correct fallback is to collapse the card's second line,
never to restore scrolling.

The suggestion step keeps its `ScrollView` deliberately: nothing there claims the
crown, so crown-scrolling behaves normally.
- **Invalidation**: undoing a completion, lowering reps, removing the slot, or
  swapping the target all call `revalidateOverloadPresentation()` and dismiss
  without staging anything.
- **Per-slot state**: `appliedOverloadSlots` and `deferredOverloadSlotIDs` mean
  several qualifying exercises never overwrite one another. "Later" defers one slot
  and never marks overload applied, preserving ticket 05's summary opportunity.
- **Recovery** (ticket 08): the checkpoint persists `appliedOverloads` and
  `deferredOverloadSlotIDs`, so relaunch never re-prompts or applies twice. The
  surface itself returns as `.none` and is re-derived from live state; transient
  animation state is deliberately not checkpointed. Pending-transaction truth comes
  only from the sync-state owner.

Order of operations is the contract: **the atomic sync-state write happens first**,
and only after it succeeds do the active workout mutate, the success haptic play,
the confirmation appear, and transport be attempted. A failed write enqueues
nothing, consumes no sequence counter, leaves the suggestion actionable, and shows
localized failure feedback. One stable transaction id per slot means repeated taps
and retries reuse the same transaction rather than allocating a second.

### Mixed versions

New Watch + old iOS: the added `TemplateTransactionPayload` case fails to decode,
so `WatchWorkoutInboxStore.store(transactionData:)` throws, no acknowledgment is
sent, and the Watch retains the transaction in its atomic FIFO until iOS is
upgraded — the same policy `acknowledgePlain` already applies to template intent.
Note the blast radius: because it stays FIFO head, that routine's later template
transactions wait behind it too. Old Watch + new iOS: absent overload fields decode
as "no overload intent".

### Paired-hardware verification (2026-07-27)

Run on a physical iPhone + Apple Watch pair. **All core, ordering/history, and
lifecycle cases pass.**

*Core.* Reachable apply with the default increment; the Crown increment picker
(+1.25 / +2.5 / +5) with live resulting-weight preview; "Later" dismissing
without marking overload applied; **offline apply with the iPhone powered off**,
converging after the phone returns without reopening the Watch app; and the
**conflict case** — an iPhone edit to the same exercise while the transaction is
pending wins, the Watch drops its optimistic value through the normal
acknowledgment/context retirement, and the user gets non-blocking feedback rather
than a silent claim that both devices match.

*Ordering and history.* With the iPhone offline, a mid-workout overload followed
by **Save & Update Template** applies in FIFO order and the workout's performed
values do **not** overwrite the overload. History shows the values actually
performed (not the new target), and volume plus the exercise's progress chart
read those performed values — confirming the `progressiveOverloadApplied` +
planned/actual snapshot contract end to end. A workout saved **without** the
template update reaches History immediately even while an overload is pending.

*Lifecycle.* A qualifying final set suppresses auto-finish and raises the
suggestion instead, with auto-finish resuming exactly once after Apply/Later; a
non-final qualifying set keeps the rest timer running with only its full-screen
overlay minimized; un-completing a set invalidates an on-screen suggestion
without staging anything; and force-quitting the Watch app mid-workout and
relaunching resumes with the applied state intact — no re-prompt, no second
transaction, exactly one overload delivered to iPhone.

*Counterweight assistance.* Direction and zero-clamp behave correctly (assistance
goes down, and an exercise already at zero assistance produces no suggestion).
**One bug found and fixed:** the confirmation headline read "Erhöht auf" /
"Increased to" even though assistance had been *reduced*. The Watch confirmation
now branches on load behavior and uses the same wording iOS already used
(`rep_range.overload_card.reduced_to` → "Assistance reduced to" /
"Unterstützung reduziert auf"). The suggestion capsule was already correct — it
renders the signed step through `ProgressiveOverloadFormat.increment`, which
shows a minus for assistance.

*Two UI defects found and fixed.* (1) The pushed increment picker drew the
exercise name at the top of its own content, where it collided with the
navigation back chevron **and** with the minimized rest-timer pill (which sits in
the top-trailing status-bar overhang). The name now goes in the navigation bar
via `navigationTitle`, the content scrolls, and
`WatchOverloadPresentation.hidesRestTimerOverlay` withholds the pill for the
full-screen surfaces (picker, applying, confirmation) — the timer keeps
**running**, only its overlay is hidden. The bottom-anchored suggestion capsule
does not collide, so the pill stays visible there. (2) The smallest step read
"+1,2 kg": the default `Measurement` precision rounded 1.25 to one fraction
digit. `ProgressiveOverloadFormat.weight` now formats with
`.fractionLength(0...2)`. Following up on that, the increment list gained a 0.5
micro-loading step and moved next to `ProgressiveOverloadService` so **iOS and
watchOS read one list**; the iOS `WeightIncreaseSheet` had the same rounding bug
via `%.2g` and was fixed the same way.

*Not yet exercised on hardware:* the swapped-alternative apply path and two
simultaneously qualifying exercises (both have automated coverage), and the
mixed-version combinations (new Watch + old iOS, and the reinstall/epoch
handover).

### Deliberate omissions

Ticket 04 intentionally did **not** build the source-workout correlation
machinery its ticket text described, because it had no caller. Ticket 05 below
adds it — in a different shape than that text assumed, for the reason recorded
under "Why the history record is not marked".

## Post-workout summary progressive overload on Apple Watch (ticket 05, 2026-07-30)

The Watch recap (`WatchWorkoutSummaryView`) turns its passive rep-goal trophy into
an actionable prompt. It is the last chance for an increase the user tapped
"Later" on mid-workout, and the *only* chance when the qualifying exercise was not
the last one performed.

**One operation, two entry points.** The recap row calls
`applyProgressiveOverload(slotID:increment:)` — ticket 04's single deep operation —
through the same `ProgressiveOverloadSheet`, the same
`WatchOverloadPresentation` owner, the same increment picker, the same math,
transaction identity, atomic enqueue, per-routine FIFO, transport, receipts and
acknowledgment. The recap adds no second path for any of those. The sheet is
already attached to `ActiveWorkoutView`'s outer `ZStack` (a sibling of the summary
branch), so it presents over the recap with no new presentation plumbing.

### What the recap must not touch

By the time the recap appears, `onFrozen` has already committed the completed
payload to the durable queue, and it may be transferred or ingested. So the recap
apply path branches on `isShowingWorkoutSummary` and, unlike mid-workout:

- it does **not** swap the performed values into `planned*` — the recorded sets
  stay exactly as performed;
- it does **not** amend, rebuild or resend the frozen payload, and creates no
  second history record;
- it does **not** rewrite the active checkpoint — finalization owns the workout.

Everything else is the mid-workout path unchanged. `qualifiesForProgressiveOverload`
lifts only its `isEnding`/`isWorkoutFrozen` guards while a summary is showing
(those exist to protect the *workout*, which the recap never mutates); every other
rule — rep-range math, already-applied, minimum-assistance clamp, target
resolution — is shared, so the recap is not a looser second eligibility definition.
Mid-workout **Later** deliberately does not suppress the recap: `deferredOverloadSlotIDs`
dismissed one interruption, it did not decline the increase.

### Row state machine

`WatchSummaryOverloadPolicy` is a **pure decision duplicated into both targets**
(same arrangement as `WatchWorkoutInteractionPolicy` and
`ProgressiveOverloadService`) — there is no watch unit-test target, so the iOS
copy is what `WatchSummaryOverloadTests` exercises. **Keep the two copies in sync.**

| State | When |
|-------|------|
| `.actionable` | qualified, unapplied, and the template target still resolves |
| `.applied(newWeight:isAssistance:)` | applied from either surface; `newWeight` nil for a nonuniform scheme |
| `.superseded` | the transaction left the queue and the effective routine no longer holds its value |
| *(no row)* | never qualified, or the target was deleted on iPhone — the plain trophy stays |

**An applied row never returns to an Apply button.** That is the invariant the
policy exists to hold: silently restoring one after iOS overrode the change is how
a user applies the same increase twice without being told the first did not stick.

`.superseded` needs **no outcome ledger**. `WatchAppliedOverload` keeps a probe
(the first affected template set + the weight this transaction proposed). While
`syncState.hasPendingTransaction(id:)` is true there is no verdict yet, so a
pending *offline* apply always reads as confirmed. Once the entry is gone — which
only happens on a terminal ack whose routine generation also applied locally — the
effective routine **is** the verdict. Rows re-derive on a `routineStore.$routines`
publish, which is exactly when retirement happens, so a recap the user is still
looking at updates in place.

Rows are resolved once into `summaryOverloadRows` (slot-keyed) by
`refreshSummaryOverloadRows`, never computed in a body: one row's state walks the
routine, its slots and their alternatives.

### Correlation: why iOS History stops re-offering it

A recap increase is a template-only transaction, so the recorded workout carries
no trace of it and `WorkoutDetailView`'s after-the-fact card would offer the same
increase again — a second tap raising the template twice.

The intent therefore carries optional `sourceWorkoutID` + `sourceRoutineExerciseID`
(nil for mid-workout, which reports itself via `overloadAppliedExerciseIDs`).
They live in the **payload, not the envelope**: `TemplateTransactionEnvelope`
requires `workoutID == nil` without a workout, and a non-nil value there would
collide with the workout-id matching the outgoing queue dedupes on (ticket 04
deviation 1). Both are additive optionals — no schema bump — and `isWellFormed`
rejects a half-filled pair.

On `.applied`, `WatchTemplateTransactionCoordinator+ProgressiveOverload` writes
`workoutID → [slotID: AppliedOverloadRecord]` into `WorkoutIngestReceiptStore`'s
`OverloadCorrelation/` directory (`WorkoutIngestReceiptStore+OverloadCorrelation.swift`
— the same durable ledger that already owns receipts, and the same indefinite
retention policy). `WorkoutDetailView.loadAppliedOverloads` reads it through the
`AppliedOverloadCorrelationReading` Domain protocol wired in `AppDependencies`,
and seeds the confirmed state ticket 03 already had.

`AppliedOverloadRecord.newWeight` is **optional and stays optional all the way to
the card**: for a nonuniform scheme the Watch refuses to name one weight, so
History must not either. `WorkoutDetailView` therefore tracks
`appliedOverloadExerciseIDs` separately from `appliedTemplateWeights` — "applied"
and "applied to X kg" are different facts — and `ProgressiveOverloadCard` gains
`hasAmbiguousAppliedWeight`, which switches the confirmed row to
`rep_range.overload_card.all_sets_adjusted`. Collapsing the two would have made
iOS assert exactly the number the recap avoided.

The read is `async` and hops off the main actor (`Task.detached`), with hoisted
`static let` coders: it is a disk read on the History detail load path, and
`.task` runs synchronously up to its first `await`.

**Order-independent by construction.** It is written when the transaction applies
and read when the workout is displayed, so it does not matter which arrived first,
or whether the workout is ever ingested. This matters: a recap overload is
transport-eligible immediately while a history-only workout is still awaiting
HealthKit and is not FIFO-gated, so the overload genuinely can reach iOS first
(`aRecapOverloadCanReachTheIPhoneBeforeItsOwnWorkout`).

#### Why the history record is not marked

The obvious alternative — set `WorkoutExercise.progressiveOverloadApplied` — was
**rejected**. That flag redirects 8+ aggregators (volume, charts, records, AI
Coach, history detail) to read `planned*`. On the mid-workout path that is correct
because the watch swapped the performance *into* `planned*` before freezing. A
recap apply performs no such swap, so `planned*` still holds the original template
values: setting the flag would make history report the template, not the workout.
Making iOS perform the swap at correlation time was also rejected — it mutates a
recorded workout for a display concern, and the history set order and template set
order are not guaranteed to correspond after in-workout set editing. The read-side
correlation keeps the record byte-for-byte what was performed.

### Ordering and recovery

The completed workout is enqueued first (at `endWorkout`) and takes sequence N; a
recap overload for the same routine takes N+1 in the same per-routine lane and
cannot overtake it. A workout acknowledgment never retires the overload
transaction — different entries, different identities. The recap may be dismissed
immediately after Apply because the transaction and the optimistic overlay are
already durable.

**Recovery: the recap itself is not restored after process termination**, and that
is deliberate — ticket 08 clears the checkpoint once finalization completes, so
there is no live state to rebuild, and `resumeInterruptedFinalization` resumes the
frozen workout without minting new ids. The *transaction* is durable in the
sync-state owner and converges on its own; a killed process therefore loses the
row, never the applied increase. It can never come back as a fresh actionable row
because there is no row at all.

### Nonuniform target schemes

A pyramid or drop scheme has no single resulting weight, so `WatchOverloadDisplay`
carries `hasUniformWeights` and the picker preview, the confirmation headline and
the recap row all switch to copy stating that *all sets* were adjusted rather than
naming a weight the other sets do not have.

### Mixed versions (ticket 05 delta)

New Watch + a ticket-04 iOS build: the correlation keys decode and are ignored, so
the template still applies correctly and only the History re-offer suppression is
missing. New Watch + pre-ticket-04 iOS is unchanged — the envelope cannot be
decoded at all and the transaction is retained until iOS is upgraded.

### Paired-hardware verification (ticket 05, 2026-07-30)

**Passed with no defects.** Deliberately scoped to this ticket's *delta* rather
than repeating ticket 04's matrix: the recap reuses that ticket's apply operation
unchanged — same picker, crown, increments, enqueue, transport, FIFO and
retirement — all verified on 2026-07-27.

Two workouts on a physical iPhone + Watch pair. Test routine: one uniform-weight
exercise (3 × 12 @ 60 kg) and one pyramid exercise (3 × 12 @ 50/55/60 kg), both
with an 8–12 rep goal and **planned reps set to the maximum**, which is the
shortcut that makes simply completing the sets qualify — otherwise every set
needs its reps edited up on the Watch.

*Workout A — the new surface.* After tapping mid-workout **Later** on both, the
recap showed an actionable "Increase weight" row per qualifying exercise in place
of the passive trophy. Applying the uniform exercise confirmed to "Increased to
62.5 kg" / "Now 62.5 kg next workout" and left the pyramid row **actionable and
unchanged**. Applying the pyramid exercise showed **"All sets increased"** with no
number and **"All sets adjusted for your next workout"**, moving the template to
52.5 / 57.5 / 62.5. On the iPhone: that workout's History still read **12 × 60 kg
as performed**, both History cards rendered **confirmed** rather than actionable,
and both routine templates carried the new values.

*Workout B — mid-workout apply.* Applying during the workout produced a recap row
already confirmed with **no button**, so no second transaction can be allocated.

That exercises the four invariants this ticket rests on: the recorded workout is
never mutated, an applied row is never actionable again, the same increase never
applies twice, and a nonuniform scheme never names a single weight.

**Still unexercised on hardware** for this surface — all have automated coverage,
and all reuse ticket-04 paths verified 2026-07-27: offline apply from the recap,
the `.superseded` row (its observation window needs an iPhone edit landing while
the recap is still open), immediate dismissal after apply, force-quit before
acknowledgment, assistance-direction and swapped-alternative targets *from the
recap specifically*, mixed-version combinations, and largest Dynamic Type /
VoiceOver on the new row.

Unlike ticket 04, this run found nothing — the one defect of the same class
(History naming a single weight for a pyramid scheme) was caught earlier, by the
architecture review, and fixed before the device ever saw it.

### Deliberate omission (ticket 05)

There is **no durable rejection ledger**. `.superseded` is derived from the
effective routine, which means it is only readable while the recap is open and the
routine context has arrived. A conflict that resolves after the recap is dismissed
is never surfaced as a message — the authoritative routine value simply stands,
which is what the user sees next time they open the routine. Building a retained
outcome store for a transient surface was judged not worth its weight; the hard
requirement (never silently reverting to an Apply button) holds without it.

## Color Scheme

| State | Color | Meaning |
|-------|-------|---------|
| Below min | `.secondary` | Not yet in target range |
| In range (min to max-1) | `DesignSystem.Colors.tint` (green) | Working within target |
| At upper limit (>= max) | `.orange` | Achievement / ready to progress |

## Patterns Reused

- `RestTimeInlineEditor` and `RepRangeInlineEditor` share `ParameterChipButton` + `ParameterEditorPanel` (chip opens an editor panel beneath the strip)
- `ApplyToAllBanner` pattern for `ProgressiveOverloadBanner` (contextual action banner)
- `CompactStepper` for min/max rep inputs (v2; previously `HorizontalStepper`)
- Superset denormalization pattern for rep range fields in `WorkoutExercise`
- Per-exercise state dictionaries (`[UUID: Bool]`) for expansion/dismissal tracking

## Progressive Overload Data Integrity

When `applyProgressiveOverload` is called during a workout:

1. **`WorkoutSet.plannedWeight/plannedReps`** are snapshotted from `actualWeight/actualReps` — preserving the user's actual performance before overload
2. **`WorkoutSet.actualWeight/actualReps`** are left untouched: they are the performance, and the increase is for the next workout (see "The increase never touches the workout in progress")
3. **`WorkoutExercise.progressiveOverloadApplied`** is set to `true`
4. **Routine template** (`ExerciseSet`) is updated with the new weight/reps for future workouts

The following services check `progressiveOverloadApplied` and use planned values when set:
- `ExerciseProgressService.fetchProgressData()` — chart data points
- `ExerciseProgressService.previousPerformance()` — historical lookup for comparison
- `ExerciseProgressService.compareWithPrevious()` — summary/detail comparison
- `WorkoutSession.totalVolume` — session volume calculation

This ensures the summary screen, workout detail view, and progress charts all show the user's actual performance rather than the overloaded values.

The completion screen's apply path is the **same** `applyProgressiveOverload` call, so applying there never rewrites the session's history either — the just-performed reps/weights survive in `plannedReps`/`plannedWeight` via the identical snapshot. Undo (completion screen only) restores both the session sets' pre-apply planned/actual values and the template's set scheme (the alternative's for swapped exercises) from the in-memory snapshot; it is intentionally unavailable after the session ends.

### The increase never touches the workout in progress (fixed 2026-08-07)

Applying an increase used to also write the proposal into the live sets:
`actualWeight = newWeight`, `actualReps = targetRepMin`, on both platforms
(`WorkoutViewModel.applyProgressiveOverload`,
`WatchWorkoutViewModel+ProgressiveOverloadApply`). That was wrong on its own
terms: the suggestion only appears once **every set of the exercise is completed**
at the rep max (`ProgressiveOverloadService.qualifies`), so there is nothing left
to perform at the new weight. The user saw sets they had just finished re-labelled
with a weight they never lifted, and the recap/summary reported those numbers back
to them.

Both platforms now raise only the template. What stayed is the planned snapshot —
`plannedX = actualX` — because `progressiveOverloadApplied` redirects every
aggregator to the planned fields; dropping it would make history, volume, charts
and records report the original template values as the performance.

Two consequences worth knowing:

- **No surface may read the announced weight off the workout's sets any more** —
  they hold the performance, which is exactly the weight the increase moved
  *away from*. `ProgressiveOverloadCard.confirmedWeight` therefore uses only what
  the caller supplies: the completion screen passes
  `WorkoutViewModel.appliedOverloadWeight(for:)` /
  `hasNonUniformAppliedOverload(for:)`, and History passes the weight from the
  Watch correlation ledger. When nobody knows it — a nonuniform pyramid/drop
  scheme, or an increase applied on iPhone during a workout, which leaves no
  correlation record — the row says "all sets adjusted" instead of naming a
  number that would be wrong. The actionable CTA's struck-through weight and the
  `WeightIncreaseSheet` preview likewise show the **template** value
  (`WorkoutViewModel.overloadTemplateFirstSet(for:)`, and its
  `from:session:` variant for History), so the picker can never preview one
  number and the confirmation announce another. On the Watch the confirmation
  already announced the template-derived weight and needed no change.

- **A set added during an overloaded workout joins the raised scheme.** It has no
  template counterpart the increase could have raised, so `updatePrimary/
  AlternativeTemplateSets` seeds it from the last raised template set rather than
  from the performance — otherwise Save left the template mixing raised and
  unraised sets.
- **iOS's end-of-workout template writeback needed an exclusion.**
  `updateRoutineTemplate` → `updatePrimary/AlternativeTemplateSets` writes each
  completed set's `actual*` back into the template, and the default-on "Update
  routine template" toggle means it runs on nearly every save. It only ever
  agreed with an applied increase by accident — `actual*` had been overwritten
  with the overload target. With the performance left in place it would write the
  *pre-increase* weight back and silently undo the increase, re-qualifying the
  exercise immediately. Exercises with `progressiveOverloadApplied` are now
  skipped for set VALUES (count, order and rest time still reconcile; a set added
  during such a workout still seeds from the performance, having no counterpart
  the increase could have raised). Both Watch paths already had this rule via
  `overloadAppliedExerciseIDs` — `WatchRoutineTemplateFold` and
  `WatchTemplateTransactionService+Validation`; only the iOS-native path was
  unprotected.

- **What it does NOT change: the Watch's End-workout template prompt.** An
  exercise with an applied increase never counts as "modified" — the planned
  snapshot equalises planned and actual, and
  `WatchWorkoutViewModel.isOverloadResolved` excludes it regardless. That is
  deliberate and unchanged: the completed workout's writeback skips those slots,
  so offering "Update your routine template?" for them would promise a change
  that is never written. If every exercise the user edited also received an
  increase, the End dialog therefore still shows no template question — the
  increase *is* that exercise's template update.

**Root cause fixed (2026-07, swapped exercises):** every overload surface used to resolve the template slot by comparing the *performed* exercise name against slot primaries (`exercise?.name == workoutExercise.exerciseName`). For a swapped exercise the names never match, so the mid-workout banner's "Increase" silently did nothing (nil sheet item) and the mid-workout template write no-opped. Resolution now goes through `WorkoutViewModel.routineExercise(for:)` (stable `routineExerciseId`, then planned-exercise fallback) and swapped exercises persist into the alternative's own set scheme. Do not reintroduce name-based slot matching against performed names.

## Localization

All user-facing strings are localized in both English and German via `Localizable.strings`. Keys are prefixed with `rep_range.*` (card copy under `rep_range.overload_card.*` — including `rep_range.overload_card.routine_unavailable` for the history no-op note — plus `rep_range.ready_for_more` and `action.undo`). The card's description/confirmation strings embed `**bold**` markdown markers that `ProgressiveOverloadCard` parses and colors with the accent (orange/green) — keep the markers when editing translations.
