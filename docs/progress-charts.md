# Progress Charts Feature

## Purpose

The progress charts feature allows users to track their exercise performance over time in the History tab. Users can view three metrics for any exercise they've completed in workouts: Max Weight, Estimated 1RM, and Total Volume.

See also: [history-redesign.md](./history-redesign.md) — the History tab UI that hosts these charts.

## Architecture

### Data Flow

```
HistoryView (History tab)
  → FortschrittTabView ("Fortschritt" sub-tab, replaces old ExerciseProgressListView)
    → ExerciseProgressChartView (chart + controls — stat triple, metric tabs, range pills, recent-sets list)
      → ExerciseProgressViewModel (async load + display state)
        → HistorySnapshotProviding  ── @concurrent hop ──▶  SwiftDataHistorySnapshotStore (@ModelActor)
                                                              → ExerciseProgressAggregator (pure Domain logic)
```

The screen renders exactly one boundary call, `fetchExerciseProgress(exerciseName:exerciseId:startDate:recentSessionLimit:)`,
which returns an `ExerciseProgressSnapshot` carrying both the chart series and the
recent-sets list. Only immutable `Sendable` values cross back; no `@Model` and no
relationship walk survives on the main actor.

### Off-main loading (2026-08-13, audit P1.2)

Everything above the `@concurrent` line used to run **synchronously on the main actor**.
`ExerciseProgressViewModel.loadData()` had no `await` anywhere in its chain: it called
`ExerciseProgressService.fetchProgressData`, which issued an unbounded
`FetchDescriptor<WorkoutSession>` with **no** `relationshipKeyPathsForPrefetching` and
then walked `session.workoutExercisesList` → `setsList` per session (an N+1 fault per
row). It ran from `init`, on every range-pill tap and on every exercise switch. Because
nothing yielded, `isLoading = true; …; isLoading = false` could never be observed, so the
spinner was dead code. `ExerciseProgressChartView.loadRecentSessions()` added a *second*
unbounded scan by calling `workoutSessionRepository.fetchCompleted()` straight from the
View.

**Measured, not inferred:** with `@concurrent` removed from the new provider method,
`largeExerciseProgressBuildKeepsMainActorResponsive` (240 sessions × 5 exercises × 4 sets)
records a **307 ms** main-actor stall. With it, the delay stays under the 100 ms budget.
The build is green either way — see `docs/swift6-concurrency.md` §1 for why SE-0461 makes
that failure invisible to the compiler.

What changed:

- The aggregation moved verbatim into `Domain/Services/ExerciseProgressAggregator.swift`,
  isolation-agnostic so the `@ModelActor` can call it from its own executor.
- The fetch reuses `SwiftDataHistorySnapshotStore.fetchCompletedSessions()`, which is
  already prefetch-correct (it fetches `WorkoutExercise` with `[\.sets, \.workoutSession]`
  first to register the graph, then the sessions).
- `ExerciseProgressViewModel.load()` is `async`, driven by `.task(id: viewModel.loadKey)`
  in the View. Range pills and the exercise switcher now only mutate state.
- `ExerciseProgressChartView` no longer holds a repository or a progress service.
- `SessionCardView`'s `DateFormatter` and `RelativeDateTimeFormatter` were hoisted to
  `static let` (they were allocated per row per render — audit P2.7's first item, folded
  in because this change re-typed that row view anyway).

**Why the fetch is still unbounded, deliberately.** The chart window is applied in Swift
after the fetch rather than in the `FetchDescriptor`. Narrowing it would require a
comparison across the optional `WorkoutExercise.workoutSession` relationship inside the
warm-up pass's `#Predicate`. SwiftData does not document support for optional-chained
comparison or `??` in predicates, and the reported failure mode is *silently wrong
results* rather than a thrown `SwiftDataError.unsupportedPredicate` — a bad trade against
a proven fetch. The cost this finding was actually about (unbounded fetch + full
traversal *on the main actor*) is paid on the model actor's executor now. Date-bounding
the fetch remains available as a later optimisation if a large-history profile calls for it.

**Why it shares History's actor rather than getting its own.** A second `@ModelActor`
means a second `ModelContext` faulting in the same rows, and this screen is pushed from
the History tab, so that context is already warm. Sharing is safe because Swift actors
are reentrant *only at suspension points*: every method on the store is `async` but
contains no internal `await`, so each runs to completion before the next is dequeued.
That invariant is written on the store — breaking it would open an interleaving window on
the shared, non-`Sendable` `ModelContext`.

### The vs-previous comparison (2026-08-14, audit P1.6)

The other half of this file's surface — "how did this compare with last time?", shown on
the save sheet, the workout detail screen and inside the AI Coach's workout analysis — was
left on the main actor by P1.2 and is now off it too. It was the stronger candidate all
along:

```
SaveWorkoutView / WorkoutDetailView / WorkoutAnalysisViewModel
  → ExerciseProgressProviding (@MainActor)
    → ExerciseComparisonBuilder.makeLookup(workout:)          ── main actor, bounded
    → HistorySnapshotProviding  ── @concurrent hop ──▶  SwiftDataHistorySnapshotStore
                                                          → PreviousPerformanceResolver
    → ExerciseComparisonBuilder.build(workout:previousPerformances:)  ── main actor, bounded
```

What it was: `compareWithPrevious(workout:)` called `previousPerformance` **once per
exercise**, and each call issued its own unbounded `FetchDescriptor<WorkoutSession>` with
no `relationshipKeyPathsForPrefetching`, then walked every session's exercises and sets —
faulting one row at a time. Each call *also* fetched the entire `Exercise` library to
decide name uniqueness, and `compareWithPrevious` fetched it once more per exercise on top,
so an eight-exercise workout meant 8 unbounded session fetches and 16 full library scans,
synchronously on the main actor. Unlike the chart, nothing gated it: it ran every time a
workout was finished and every time a past workout was opened.

**Measured, not inferred:** with `@concurrent` removed from the new provider method,
`previousPerformanceLookupKeepsMainActorResponsive` records a **213 ms** main-actor stall
(240 sessions × 5 exercises × 4 sets, an eight-exercise lookup). With it, under the 100 ms
budget. Build green either way. Fourth case in the shared tripwire suite, third on the
History actor.

**Why the workout crosses as values, not as an id to re-fetch.** This was the reason P1.2
left the item alone: an `@ModelActor` cannot accept a main-context `@Model`, so the obvious
port — pass `WorkoutSession.id`, re-fetch inside the actor — does not work here. It was
investigated and rejected, not overlooked:

- The save sheet compares a workout the user has **not saved yet** (it is presented
  straight after `pauseForCompletion()`, and while that does call `save()` today, the
  correctness of a user-visible screen must not rest on that ordering).
- SwiftData does not document whether one `ModelContext` sees another's unsaved changes.
  An Apple DTS engineer reproduced inconsistent behaviour on forum thread 763487 and
  explicitly declined to say which is expected. `ModelContainer.mainContext` has
  `autosaveEnabled == true` (documented) but the firing *timing* is unspecified — "key
  lifecycle events" with no bound.
- `PersistentIdentifier` is the documented cross-context handle and would be the right
  tool for a saved object, but it carries the same trap from the other side:
  `PersistentIdentifier.isTemporary` is `true` until the origin context saves, and Apple
  documents that temporary ids "should not be used to create durable maps to a model".
- The failure mode is the deciding factor. A miss returns *no predecessor*, which the UI
  renders as "New exercise" — a confident false statement about the user's history, not a
  visible error.

So the split runs along the cost, not along the object: only the unbounded history scan
crosses. `PreviousPerformanceLookup` carries the workout as `Sendable` values, and the
bounded current-workout read stays with the caller, which already holds that graph faulted
in and is about to render every set of it anyway.

**Other things this closed:**

- One fetch replaces N. `PreviousPerformanceResolver` filters and sorts the candidate
  sessions once for the whole workout and counts library names once, over the shared
  prefetch-correct `CompletedSessionFetch.withFullGraph`.
- `withFullGraph` now prefetches `\.routine` as well. The resolver compares
  `session.routine?.id` per candidate, and without it the N+1 would simply have moved to
  the model actor instead of being removed.
- `ExerciseProgressService` no longer owns a `ModelContext`; it is a thin `@MainActor`
  seam over the boundary call between the two pure builders.
- `ExerciseComparisonResult` gained `workoutExerciseId`. All three callers previously
  paired results with exercises **positionally** — a `zip` in `WorkoutDetailView`, an
  index in `WorkoutAnalysisAggregator`, and `ForEach(id: \.exerciseName)` in
  `SaveWorkoutView`, which gave two rows the same identity whenever a routine trained the
  same exercise twice. All three now key on the id.
- `WorkoutAnalysisAggregator` no longer constructs `ExerciseProgressService` ad hoc,
  bypassing `AppDependencies`; it takes the resolved comparisons as a parameter.
- A failed lookup returns an **empty array**, not rows without a predecessor. The latter
  would badge every exercise "new". Pinned by
  `failedHistoryLookupYieldsNoRowsRatherThanFalseFirstTimeRows`.

**Two tradeoffs taken knowingly, so they are not re-litigated as oversights:**

- **The AI analysis resolves the comparison before its own gates.** `compareWithPrevious`
  used to sit *inside* `WorkoutAnalysisAggregator.buildInput`, after its three
  insufficient-data guards; it now runs first, in `WorkoutAnalysisViewModel`, because the
  aggregator is `@MainActor` and this is the half that must not be. A gated-out analysis
  therefore pays one off-main resolve. Acceptable: the guard that rejects most often — no
  previous same-routine session — is already evaluated by `prepareCoachState`, so the
  button the user tapped would not be visible without one.
- **`WorkoutDetailView` resolves the comparison twice** — once in `.task` for the
  per-exercise strips, once when "Ask the Coach" is tapped. Now that results are keyed by
  `workoutExerciseId`, the second could reuse the first, but only by making the analysis
  depend on a sibling `@State` load having succeeded: an empty dictionary is
  indistinguishable from "no history", so a failed strip load would silently downgrade the
  analysis to *insufficient data*. An independent resolve on an explicit tap is the safer
  trade, and the old code scanned twice as well — on the main actor.

**Deliberately not done.** `WorkoutAnalysisAggregator`'s own two unbounded main-actor
fetches (`findPreviousSession`, `detectNewPRs`) are untouched — they are audit P2.1, which
covers all four AI-coach aggregators together and is gated behind the AI opt-in.

### The Fortschritt row counts sessions, not exercise instances (2026-08-23)

The Fortschritt list's own aggregation (`FortschrittAggregator.build`, feeding the row's
count, sparkline and trend badge) used to walk every `WorkoutExercise` of every session and
append **one accumulator entry per exercise instance**. A routine that trains the same
exercise twice in one workout — the common heavy/light pairing — therefore produced two
entries carrying the *same* `session.startTime`, and all three numbers on the row lied at once:

- **The count was an instance count.** 14 sessions, 7 of which trained "Biceps Curls" both
  heavy and light, reported **21 Workouts**, while the exercise detail screen — which has
  always emitted one data point per session — reported 14 for the same all-time window.
- **The sparkline was a zero-width sawtooth.** It alternated between the light usage's
  estimated 1RM (14 kg × 12 ≈ 19.6) and the heavy one's (20 kg × 5 ≈ 23.3) at no horizontal
  distance, because both points shared a date.
- **The trend read +0.0%.** Trend is first-value vs. last-value; with an even number of
  alternating entries both ends sampled the same usage and cancelled exactly.

**The rule now: the session is the unit.** Each `(session, live exercise)` pair contributes
exactly one entry *per usage*, and the count on the row is the number of distinct sessions
containing the exercise, so the two surfaces cannot disagree about how many workouts they are
summarising. (Usages arrived with the section below; when this rule first shipped a session's
repeats were folded into a single entry instead. The set-level reduction described here is
unchanged either way — it now reduces one usage's row rather than all of a session's rows.)

- **Effective-load series** (any resistance exercise, and counterweight assistance when the
  session carries a body-mass snapshot): fold with **max** — the heavier effective weight is
  the better set. (This folded to the best estimated 1RM until the metric was aligned; see
  "The Fortschritt row headlines one usage" below.)
- **Raw-assistance series** (counterweight assistance with no snapshot): fold with **min** —
  *least* assistance is the better set. This is why the fold tracks a `hasValue` flag
  instead of treating 0 as "unset": an assisted set performed with no counterweight at all is
  a legitimate best value, and a min-fold seeded at 0 would silently discard the better set
  or invert the pair. Inverting the sparkline against the series maximum, and inverting the
  trend's delta, both happen after the fold and are unchanged.

**The value space is a property of the series, not of a session (ticket 08, 2026-08-25).**
Whether a counterweight exercise's numbers are read as physical load or as the machine's raw
assistance is decided **once for the whole series**, exactly as
`ExerciseProgressAggregator.buildProgress` decides it: if *any* session in the series lacks
`WorkoutSession.bodyWeightKg`, *every* session is valued as raw assistance. That is the
conservative direction — it never manufactures a load from a body weight the user did not
record — and it is the rule `ExerciseLoadMetrics` was written around
(`docs/assisted-exercise-progress.md`).

It used to be decided per session, and the row for a partly snapshotted assisted exercise then
mixed units: a snapshotted workout contributed an estimated physical load (tens of kg), a
snapshot-less one the raw assistance entered on the machine, and the series-wide flag —
`allSatisfy` over the per-session flags — then inverted *both* against one common
`baseline − value`. The sparkline shape and the trend percentage were arithmetic over two
incompatible quantities, and the direction was wrong for one of them (a higher physical load is
better; a higher assistance number is worse). This predated the per-session fold and the usage
split; the divergence is now closed and the two surfaces pick the same space for the same
history.

**How it stays one traversal.** The decision needs the whole series, but the fold runs inside
the session loop, so `FortschrittAggregator.foldSets` reduces a counterweight row in **both**
spaces at once — `effectiveValue` (max effective weight, only when the session can be read as
load) and `assistanceValue` (min raw assistance, always) — and `SessionFold.value(usingEffectiveLoad:)`
picks one after the loop, when the series-wide flag is known. Re-reading the sets afterwards
would mean a second walk of the session graph inside the History `@ModelActor`, which is the
expensive part; folding both costs one extra `min` per set. A resistance exercise never reaches
the decision at all — `usesEffectiveLoad` is unconditionally true for it.

This slice deliberately did **not** separate the two usages into their own series — that is
"The Fortschritt row headlines one usage" below. It only stopped the row from misreporting how
many workouts it covers.

One pre-existing quirk in this aggregator, recorded so it is not mistaken for the fold's
doing: a session whose completed sets all fail the weight guard still contributes an entry
valued 0, which on a raw-assistance series renders as `baseline - 0` — i.e. as the best workout
ever. (A second quirk, a `reps > 0` guard with no counterpart in `buildProgress`, disappeared
with the 1RM fold when the metric was aligned — reps no longer enter the row at all.)

`GymStreakTests/FortschrittAggregatorTests.swift` pins it: a session with two usages, a mix
of single- and double-usage sessions (asserting a real +30% trend where the bug reported
+0.0%), the count agreeing with `ExerciseProgressAggregator.buildProgress`, and every assisted
path — least-assistance with an inverted sparkline/trend, highest-effective-weight once every
session carries a body-mass snapshot, and the partly snapshotted series in three shapes
(plain, trained twice in one workout, and asserted against the detail screen's own
`usesEffectiveLoad` for the all-time window) so tapping the row cannot change the unit under
the user. A resistance exercise across a snapshotted and a snapshot-less workout is pinned
too, because it must never see the decision.

### The recent-sets list shows every usage (2026-08-23)

The "Letzte Sätze" list under the chart used to read **one** `WorkoutExercise` per session —
`session.workoutExercisesList.first(where:)` — and silently drop the rest, while the chart
above it takes the **maximum** across all of them. A workout that trains the exercise both
heavy and light therefore rendered two different numbers side by side on the same screen, with
nothing explaining why. Confirmed on device: the chart's point for one day read 20 kg (the
4–6 rep usage) while the card for that same day read 14 kg × 12, 10, 8 (the 8–12 rep usage).

**The surviving instance was arbitrary, not "the first slot".** `workoutExercisesList` is
`workoutExercises ?? []` — the raw SwiftData to-many relationship, unsorted. A to-many array has
no documented stable order, so which usage reached the card was whichever the relationship
happened to materialise. The old behaviour could not even be described as "shows the first
usage", which is why the fix imposes an explicit order rather than inheriting the array's.

**The rule now: one card per usage, capped by session.** `ExerciseProgressAggregator.buildRecentUsages`
emits an `ExerciseRecentUsage` for every matching `WorkoutExercise` that has completed sets, so a
two-usage workout renders two cards:

- **Card identity** is the originating `WorkoutExercise.id`; the session id travels alongside as
  `workoutSessionId`, so every card of one workout can still be recognised as such (and, from
  ticket 03 on, filtered).
- **Block order within a session is `WorkoutExercise.order`** — the sequence the user actually
  performed — with `id` as a tiebreak so the sort is a total order even if two rows share an
  `order`. Sets keep their `WorkoutSet.order` sort inside each block. Nothing reads the
  relationship array's order, and `blockOrderFollowsWorkoutExerciseOrderNotTheRelationshipArray`
  pins it with two sessions whose insertion order is the opposite of their `order` values.
- **`recentSessionLimit` (8) is a session cap, not a card cap.** Showing every usage must not
  silently shrink how far back the list reaches, so a two-usage workout emits two cards and
  counts once against the limit. The rendered stack therefore scales with the routine's shape
  (a handful of cards per workout at most), not with history length, which is what keeps the
  plain non-lazy `VStack` in `recentUsagesSection` legitimate.

**Each card names its usage.** `ExerciseUsage` carries the routine slot the history rows were
recorded against (`WorkoutExercise.routineExerciseId`), the slot's denormalised rep-range goal
and the workout's `routineName`; the card renders them as a small badge ("4–6 reps · Push A")
opposite the relative date. Rows with **no** slot — history recorded before `routineExerciseId`
existed, and exercises added ad hoc mid-workout — resolve to the explicit
`ExerciseUsage.Slot.unattributed` case rather than to `nil` or to some other usage. Nothing new is persisted: `WorkoutExercise`
already denormalises all three fields precisely so they survive routine edits and deletion.
Carrying the identity here is what lets ticket 03's usage picker filter this panel.

**The badge always names the usage, never just the routine.** The rep range is what usually
identifies a usage, but it can be absent, and falling through to the routine name alone leaves
two usages of one routine both reading "Pull" — observed on device on 2026-08-23, where a "Pull"
routine holds Biceps Curls twice and only one slot has a rep-range goal. The two ways a rep range
can be missing are different facts and get different words:

| Case | Badge |
|------|-------|
| Slot with a rep-range goal | `4–6 Wdh. · Pull` (`workout.exercise.rep_goal`, the active-workout chip's wording) |
| Slot whose goal is not set | `Kein Ziel · Pull` (`rep_range.no_goal`, the routine editor's own wording for that setting, so the badge names what the user would go and change) |
| No slot at all | `Ohne Zuordnung · Pull` (`history.exercise.usage.unassigned`) |

Note that an alternative-exercise swap keeps the *slot's* `routineExerciseId` while adopting the
**alternative's** own rep-range goal and set scheme (`WorkoutViewModel.swapExercise`), so a slot
performed as its alternative is badged with the alternative's range. It also rewrites
`exerciseId` to what was actually performed, so the main exercise and the alternative are never
mixed into one series — the detail screen filters on `exerciseId` before usage even applies.

**Deliberate behaviour change: the list now applies the chart's `loadBehavior` filter**, which it
previously did not apply at all. Keeping a block the chart excluded is exactly how two panels end
up disagreeing about one workout, which is the defect this change exists to end. The list still
ignores the selected timeframe — it remains all-time.

The card's "Best" line inverts with the exercise's load behaviour (ticket 04): on a
counterweight-assisted exercise the best set is the **least**-assisted one, so `bestSet` is a `min`
there and a `max` everywhere else. `ExerciseRecentUsage` carries `loadBehavior` for exactly this —
before it did, the line named the *most*-assisted set, i.e. the worst one, directly under a record
card that said the opposite. Within one card every set shares the workout's body-mass snapshot, so
the least-assisted set is also the highest effective load whether or not the series is expressed as
effective load; no second rule is needed for the `usesEffectiveLoad` case.

`GymStreakTests/ExerciseProgressAggregatorTests.swift` pins the rule: a two-usage session (both
blocks present, in performed order, with the heaviest set shown equal to the value the chart
plots for that day), the explicit block ordering above, the session cap over a mix of one- and
two-usage workouts, a legacy row resolving to `.unattributed`, and the load-behaviour filter.

### The chart separates usages by routine slot (2026-08-23)

The reported bug: a user trains Biceps Curls two ways — 20 kg for 4–6 reps in one routine,
14 kg for 8–12 in another — and the chart plots a single series alternating between the two
loads. Estimated 1RM does not rescue it either (20 × 5 ≈ 23.3 kg vs. 14 × 10 ≈ 18.7 kg still
alternate), and a workout containing *both* usages collapses into one `max` describing neither.

**Exercise usage is now a first-class concept.** A usage is a distinct way an exercise is
trained, identified by the **routine slot** its history rows were recorded against and described
to the user by the slot's rep range plus the routine name. Nothing new is persisted:
`WorkoutExercise` already denormalises `routineExerciseId` and `targetRepMin`/`targetRepMax`
precisely so they survive routine edits and deletion.

**One matching rule, two surfaces.** The slot match lives in `ExerciseUsageResolver.slot(of:)`
and `PreviousPerformanceResolver` calls it for the exact-match it applies when answering "what did I lift last time?". The save sheet's comparison
had been segmenting by slot correctly all along while the chart had not; a second implementation
would let the two surfaces drift apart about what counts as the same piece of work, which is
exactly how the two panels of this screen came to contradict each other in the first place.

**What the picker does.** `ExerciseUsageMenu` sits next to the exercise switcher in the detail
screen's top bar and is rendered only when more than one usage exists (`showsUsagePicker`).
Selecting *4–6 Wdh. · Pull* charts that slot alone and filters the recent-sets list to it;
a combined entry, listed last, preserves the previous behaviour for anyone who wants it.

| Value | Where | Meaning |
|-------|-------|---------|
| `ExerciseUsage.Key` | `Domain/Models/ExerciseUsage.swift` | What identifies a usage: the **slot** plus the row's **occurrence index inside one workout** (2026-08-24, see below). Not the whole `ExerciseUsage`: the rep range and routine name are denormalised per row, so editing a slot's goal would otherwise split one slot into two series mid-window. |
| `ExerciseUsageSelection` | same | `.combined` or `.usage(key)`. |
| `ExerciseUsageOption` | same | One picker entry — the key, its descriptor from its **most recent** row, when it was last trained, and that row's `order` (menu ordering only). |
| `ExerciseUsagePickerItem` | same | The labelled entry the menu renders. Built once per load in the view model, never in `body`. |

**Rules the implementation honours:**

- **All-time options** (revised 2026-08-24 — they were window-scoped at first).
  `ExerciseUsageResolver.options(in:matching:)` walks **all** completed sessions, so the menu holds
  still while the user switches 1M / 1J / Alle. A usage with no completed sets anywhere is left
  out — selecting it would show an empty chart.
- **Default selection: the most recently trained usage**, not combined — computed over all
  history, so it does not move with the timeframe either. Opening on combined would show the
  reporter the exact sawtooth they filed. With one usage (or none) the selection resolves to
  `.combined` — identical to that usage's own series — and the picker stays hidden.
- **Resolution happens in `ExerciseUsageResolver.resolveSelection`**, and the snapshot reports
  back `snapshot.selectedUsage`, so the screen never has to fetch once to learn the options and
  again to apply one. A requested usage is **always kept**: since the options are all-time,
  narrowing the timeframe past the selected usage draws the existing empty-chart state
  (`chart.empty.title` / `chart.empty.message`) rather than silently swapping the user's choice.
- **`selectedUsage` vs. `resolvedUsage` (2026-08-27).** `selectedUsage` starts, and is reset on an
  exercise switch, at `.combined` — a placeholder, not an answer, since the default is usually a
  specific usage. `resolvedUsage` is the same value but `nil` until a load has actually resolved
  it. Anything whose per-usage work is expensive keys off `resolvedUsage`: the AI Coach
  deep-dive's cache probe is a full history fetch on the main actor, and keying it on
  `selectedUsage` ran it once against the placeholder and again against the answer on every
  screen open (`docs/ai-coach.md` §3). It is republished unchanged across a timeframe change, so
  it does not make such work repeat on every range tap — but `updateUsage` **clears** it, because
  after a usage tap the loaded answer describes the variant the user just left. That window is
  why the coach panel renders nothing until the reload lands: acting on the stale value would
  spend a monthly allowance unit on the wrong variant.
- **Rows with no slot are their own bucket.** `.unattributed` is selectable, appears in no other
  series, and is never dropped — a chart that quietly omits real workouts is the failure mode
  this whole feature exists to end.
- **Two slots, same rep range stay separate series.** Their labels are disambiguated only when
  they would actually collide (same routine *and* same rep range), by appending the
  **last-trained date** — `8–12 Wdh. · Pull · zuletzt 12.07.` (`chart.usage.last_trained`). See
  the label rule below for why the position in the workout was not enough.
- **Selection is part of `LoadKey`, so changing it reloads** through `.task(id:)` and the
  existing generation/cancellation guard. `requestedUsage` is `@Published` for exactly that
  reason — the re-render it triggers *is* the reload path, and it must not depend on some other
  published property happening to change in the same call. Filtering the already-loaded arrays instead would
  silently shrink the recent-sets list, whose cap counts *sessions*: eight workouts of
  alternating usages would leave four cards for whichever usage is selected. Reloading keeps the
  cap meaning "the last eight workouts **of this usage**".
- **Only `Sendable` values cross the boundary.** `fetchExerciseProgress` gained an
  `ExerciseUsageSelection?` parameter and returns the options as values; no `@Model` crosses in
  either direction, and the concrete provider method keeps its load-bearing `@concurrent`
  annotation (`largeExerciseProgressBuildKeepsMainActorResponsive` still passes).
- **The Pro gate is untouched.** The picker is not gated, and the stat triple still falls back to
  the free metric while a Pro-only one is selected, so no locked value is printed in plain text
  beside the blurred chart.

**Boundary design, validated against primary sources (2026-08-23).** Passing the selection
*into* the `@ModelActor` read as a `Sendable` value was checked against the proposals rather than
assumed, so it does not need re-deriving:

- A struct/enum is `Sendable` when every associated value is (`ExerciseUsageSelection` carries a
  `UUID`), which is the whole requirement — [SE-0302](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0302-concurrent-value-and-concurrent-closures.md).
  Both types are internal, so the conformance would even be synthesised; it is written out because
  this is a boundary type.
- **`sending` is the wrong spelling here, not a stricter one.**
  [SE-0430](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0430-transferring-parameters-and-results.md)
  exists to let **non-`Sendable`** values cross an isolation boundary by proving the value is in a
  disconnected region. For an already-`Sendable` value it adds nothing. Same for region-based
  isolation ([SE-0414](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0414-region-based-isolation.md)),
  which never engages for a plain `Sendable` parameter.
- **The added parameter cannot weaken the `@concurrent` hop.**
  [SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md)
  states the guarantee at function level — "`@concurrent` async functions switch to the generic
  executor" — with no dependence on parameter count or type. What the parameter does add is
  Sendable-checking at the call site, which a `Sendable` value passes with no extra hop. The
  tripwire test passing is what the proposal predicts, not a lucky result.
- **`@ModelActor` documents no parameter-type requirement** beyond the structural one:
  [`PersistentModel`](https://developer.apple.com/documentation/swiftdata/persistentmodel)
  conforms to `SendableMetatype`, **not** `Sendable`, so a model instance simply cannot cross the
  boundary in either direction. Nothing is documented about a value-type parameter violating
  `ModelContext` affinity — absence of a caveat, not a positive guarantee.
- **Enum vs. a plain `UUID?` is a modelling choice, not a concurrency one.** No Apple or Evolution
  guidance prefers primitives at actor boundaries; `Optional` is `Sendable` whenever its wrapped
  type is, and `@frozen`/library-evolution concerns need a *public* type crossing a *module*
  boundary, which this is not.

**Why the fetch is windowed in Swift rather than in the `FetchDescriptor`** (see also
`SwiftDataHistorySnapshotStore.fetchExerciseProgress`): narrowing it needs a `#Predicate`
comparison across the **optional** `WorkoutExercise.workoutSession` relationship. Apple documents
nothing about predicate support for that shape, and the Developer Forums carry repeated reports of
it failing — [nil-relationship predicates](https://developer.apple.com/forums/thread/732111),
[a "to-many key not allowed here" crash on optional to-many relationships](https://developer.apple.com/forums/thread/788624),
[enum/relationship filters crashing `@Query`](https://developer.apple.com/forums/thread/738145).
Forum evidence, not documentation — but the failure mode reported is silently wrong results or a
runtime crash rather than a thrown `unsupportedPredicate`, which is why this side stays in Swift.

**Rejected alternatives — recorded so they are not re-litigated as oversights:**

1. **One line per usage.** Drawing every usage as its own series was considered and rejected for
   now: it complicates the tap-to-inspect annotation and the Pro-gated blur, and one series at a
   time is the clearer read.
2. **Grouping by rep range instead of by slot.** Two slots sharing a rep range are different
   pieces of work — often different equipment — and the rep range is editable, so the grouping
   would silently re-partition history when a user changes a goal.
3. **Filtering the loaded snapshot in the view model.** See the cap argument above.

**Interaction with the recent-sets list (previous section).** Its guarantee — a session trained
twice shows *both* blocks — is now the guarantee of the **combined** selection; with a usage
selected the list shows that usage's blocks only, which is the point of the picker. The
aggregator test that pins the two-block behaviour asks for `.combined` explicitly.

`GymStreakTests/ExerciseProgressAggregatorTests.swift` covers: alternating usages across
sessions (per-usage progression vs. the combined sawtooth), both usages inside one session, the
default selection, a single usage resolving to combined, a slot whose routine was deleted, two
slots sharing a rep range at the **same** position (separate series **and** distinguishable
labels), two rows of one slot inside one session, a slot whose rep goal changed across sessions,
two sessions sharing an identical `startTime`, rows with no slot as their own selectable bucket,
history with no slot ids at all, a selected usage falling outside the window being kept, the
filtered recent list keeping its session cap, and the label de-duplication rules.

### A routine slot is not unique per workout (2026-08-24)

Ticket 03's picker was verified on the reporter's own device and failed on their real history in
three ways at once. All three came from the same wrong assumption — that one routine slot produces
at most one history row per workout — which every test fixture written for ticket 03 obeyed.

**The evidence** (exercise detail screen for Biceps Curls, 2026-08-24):

1. The menu listed **two rows reading character-for-character identically**
   (`4–6 Wdh. · Pull · #2` twice). Options are built in a dictionary keyed by the slot, so one slot
   cannot appear twice — the two entries are slot A's alternative and the **`.unattributed`
   bucket**, which is labelled identically whenever its rows carry a rep-range goal (see the
   correction below).
2. The same timeframe re-opened minutes later listed **different labels** for the same three
   usages (`4–6 Wdh.` became `8–12 Wdh.`), with no edit in between.
3. With one entry selected, the recent-sets list showed **both** Biceps Curls blocks of the
   12 Jul workout — 20 kg × 5/4/4 and 13 kg × 14/12/12 — and the stat row read *9 Workouts /
   10 Einträge*. The list filters by the selected usage, so both blocks share one usage: two rows,
   one workout. (They share the `.unattributed` bucket rather than a routine slot — correction
   below — which changes nothing about the fix.)

That a slot's rows legitimately carry different rep ranges over time is **not** a bug: an
alternative swap keeps the slot's `routineExerciseId` but adopts the *alternative's* rep-range
goal (`WorkoutViewModel.swapExercise`). It is the reason a slot's label is not a constant, which
is what defect 2 turned into visible nondeterminism.

**What changed:**

- **The usage key is `(slot, occurrence)`.** The occurrence index is the row's position among that
  slot's *own* rows within one session, ordered by `WorkoutExercise.order` with `id` as a
  total-order tiebreak. For normal history it is always 0 and nothing about the feature changes;
  for the mixed slot it splits the heavy and the light work into two clean series instead of one
  that `buildProgress`'s per-session `max` collapses — **the originally reported bug, alive inside
  a single usage**. `ExerciseUsageResolver.keyedRows(in:matching:)` is the one place the index is
  assigned, so the chart, the recent-sets list and the picker cannot disagree. It reuses an
  identity the codebase already had: `PreviousPerformanceResolver.occurrenceIndex` applies the
  same rule to legacy rows, and its caveat applies here too — if the user performs the two blocks
  in the opposite order in some workout, that workout's rows swap series. Accepted, for the same
  reason: it is the only ordering information the data carries.
- **The descriptor is chosen by an explicit comparison** — the greatest
  `(session.startTime, exercise.order, exercise.id)` — not by whichever row a loop visited last.
  Two orderings feeding the old code were undefined: `sorted(by:)` is not stable for sessions
  sharing a `startTime`, and a to-many relationship's order is undocumented. This is the same
  class of defect the recent-sets list fixed one section above ("Ordering is explicit, never
  inherited"), reintroduced in the new code path.
- **Labels carry the last-trained date, not an ordinal.** `· #\(order + 1)` could not
  disambiguate the reporter's two colliding slots because both sit at the same position in the
  workout — the tiebreaker collided along with the label. The date (`chart.usage.last_trained`,
  EN/DE) is also the more useful fact: it is how the user tells the slot their live routine still
  holds from a leftover one. If two entries still collide after the date, the fallback is the
  entry's **position in the menu**, which is unique by construction. The date is formatted by a
  hoisted `Date.FormatStyle` — a `static let DateFormatter` cannot exist in isolation-agnostic
  Domain code (non-`Sendable`), and the rendering rules forbid building one per row.
- **The menu is all-time** (see the bullets above): scoping it to the window made it reshuffle on
  every timeframe tap, which is what the user reported as the screen "suddenly showing different
  options".

**Dead slots are not merged into live ones.** Two entries can look like "the same" work to a human
and there is no sound rule to prove it; guessing would fabricate a progression across a slot
change, which is worse than showing two honest series. The consequence is accepted: this user's
picker lists **four** usages plus "Alle Varianten", because their history genuinely contains that
many distinct pieces of work. They are instead **marked** — see the next section.

**Correction after on-device verification of the fix (2026-08-24): there is no duplicate slot id, and
no dead third slot.** The third usage is the **`.unattributed` bucket**. With a single usage selected,
the recent-sets list showed cards badged `4–6 Wdh. · Pull` (12 Jul, 7 Jul) *and* `Ohne Zuordnung ·
Pull` (28 Jun, 11 Jun, 31 Mai) — the list is filtered to one key and "Ohne Zuordnung" renders only for
`.unattributed`, so those July rows are unattributed rows that happen to carry a rep-range goal.
`ExerciseUsage.repRangePart` prefers the rep range and falls through to the "Ohne Zuordnung" wording
only when there is none, so an unattributed usage is named exactly like a routine slot.

Every observation re-reads consistently under that: the two identical rows were slot A's alternative
and the bucket; the label flip-flop was the bucket's descriptor racing between its two 12 Jul rows;
and "one slot, two rows in one workout" was "the bucket, two rows in one workout" — ordinary for
legacy and watch-recorded history, where every row has `routineExerciseId == nil`. The
`(slot, occurrence)` key is unchanged by this: it is what splits those two rows, whichever bucket they
share. What dissolves is the hunt for a code path minting duplicate slot ids — there is no such path
to find.

**Fixed with the same verification: the marker always leads for `.unattributed`.**
`ExerciseUsage.displayLabel` prepends "Ohne Zuordnung" / "Unassigned" and keeps the rep goal after it
— `Ohne Zuordnung · 4–6 Wdh. · Pull`. Marker first because the recent-sets badge is `lineLimit(1)`
and truncates from the tail, so the half that survives is the one that says what this is; the goal is
kept because it is what tells two slot-less usages of the same workout apart. A `.routineSlot` label
is unchanged (`4–6 Wdh. · Pull`, or `Kein Ziel · Pull` with no goal set), so the two can no longer
collide. No new strings — both keys already existed.

**Loose end.** Slot A's primary reads "Biceps Curls" at 40 kg while its alternative and slot B are
the dumbbell one, suggesting **two library exercises share the name "Biceps Curls"**. If so,
`ExerciseProgressAggregator.isNameUnique` is false for that name and the legacy-row name fallback
in `matches(...)` deliberately **drops** every row with `exerciseId == nil` rather than
double-count it — which could be hiding old workouts from this screen entirely. Unverified.

### A usage you can no longer train says so (2026-08-24)

History legitimately holds routine slots that exist in no routine any more: `routineExerciseId` is
denormalized into `WorkoutExercise` precisely so a workout survives its routine being edited or
deleted. Those workouts are real, so such a usage can never be hidden — but with several
similarly-named entries, nothing on screen distinguished "the slot I trained yesterday" from "a slot
I deleted in June". The last-trained date added one section above only hints at it.

**What it looks like.** `ExerciseUsageOption.isArchived` is set when the usage's slot is absent from
the live routine library, and `ExerciseUsageLabeling.pickerItems` **leads** the label with
`chart.usage.archived` — `Nicht mehr im Plan` / `Not in a routine`. Leading, not trailing, for the
same reason `.unattributed` leads: the picker's collapsed button is `maxWidth: 150` and truncates
from the tail, so an appended marker is exactly the part the user never sees. The wording names what
was actually checked (the slot is in no routine) rather than implying a user action ("archived"),
and stays true whether the whole routine was deleted or just this exercise removed from it. The
marker is part of the **base** label, so a marked and an unmarked usage of the same rep range no
longer collide and neither needs the date suffix.

**Where the read happens.** `SwiftDataHistorySnapshotStore.fetchLiveRoutineSlotIds()` — one
`FetchDescriptor<Routine>` with `relationshipKeyPathsForPrefetching = [\.routineExercises]`, inside
the model actor, feeding `Set<UUID>` into `buildSnapshot(… liveRoutineSlotIds:)`. Fetching from
`Routine` rather than `RoutineExercise` makes "live" mean what the user sees — a slot belongs to a
routine that exists — so a slot orphaned from every routine counts as archived too. The set is
bounded by the routine library (dozens of slots), not by history; the boundary is unchanged (a
`Bool` on an existing `Sendable` value, no `@Model` and no relationship walk crossing it), and
`largeExerciseProgressBuildKeepsMainActorResponsive` still passes with the extra fetch. If it ever
regresses, make the fetch cheaper (ids only) — never drop the `@concurrent` annotation.

`liveRoutineSlotIds` is optional on purpose: `nil` means the caller did not look and nothing is
marked; an empty set means it looked and found nothing live. A required parameter defaulting to `[]`
would silently mark *every* usage archived wherever it was forgotten.

**Rules this marker obeys — all four are load-bearing:**

- **Never hides an archived usage, and never excludes it from `Alle Varianten`.** It holds real
  workouts; a chart that quietly omits them is the failure mode this whole feature exists to end.
- **`.unattributed` is never archived.** Slot-less rows (legacy history, ad-hoc exercises, watch
  recordings) have no slot to look up, so the routine library can say nothing about them. They keep
  their own `Ohne Zuordnung` labelling.
- **Never reorders the picker.** The sort stays last-trained-first; an archived usage trained
  yesterday belongs where its date puts it.
- **Never offers to delete or merge.** No rule can prove two slots are "the same" work — see the
  previous section.

Not shown on the **recent-sets badge**: a card describes one past workout, where "not in a routine"
is noise. The badge keeps `ExerciseUsage.displayLabel`, which is why the marker lives in
`pickerItems` rather than in `displayLabel`.

**Verified on device (2026-08-24, DE).** A routine holding one exercise twice (4–6 and 8–12), trained
once: both entries unmarked. Removing the 8–12 slot from the routine marked exactly that entry
(`Nicht mehr im Plan · 8–12 Wdh. · Archivtest`) and left the live entry, the other usages and the
order untouched. Building that fixture required a second change: the routine exercise picker used to
refuse an exercise already in the routine, so the same exercise could not be added twice at all — see
`docs/routines-exercises-redesign.md`.

### The empty chart says which emptiness it means (2026-08-24)

The exercise detail chart has two empty states with two different remedies, and until now both
printed the same copy — `Noch keine Daten` / *"Absolviere Workouts mit dieser Übung"*. That copy is
right for an exercise never trained and actively wrong for the other case: the reporter had **nine**
recorded workouts of the selected usage and was told to go and do one.

**Why the second state only just became reachable.** It is a direct consequence of the two sections
above. The usage options are all-time and a chosen usage is **never** swapped out, so selecting a
usage last trained on 12.07. and tapping **1M** legitimately charts nothing: the selection is kept,
the menu keeps all four usages, the stat row reads `-` / `-` / `0 Workouts`. Before the picker
existed, an empty window could essentially only mean "no history at all".

**How the two are told apart — no second fetch.** `ExerciseProgressViewModel.emptyChartReason`
returns `.neverTrained` when `usageOptions.isEmpty`, else `.outsideSelectedWindow`. That is sound
because `ExerciseProgressSnapshot.availableUsages` is built from **all** completed history and never
from the charted window: an empty menu means the exercise appears nowhere in history, so a populated
menu beside an empty series *is* the windowed case. The enum owns its own two localization keys, and
`emptyChart` in `ExerciseProgressChartView` reads them — one `isEmpty` check, no fetch and no
collection walk in the render path (`docs/history-performance.md`).

A failed load also renders `.neverTrained`: nothing is known about history then, so promising older
workouts behind a wider range would be a guess.

**New keys, not reworded ones.** `chart.empty.title` / `chart.empty.message` are shared with
`ChartSupportViews.EmptyChartView` and with the recent-sets list's own empty line, where anything
about a range would be nonsense — the recent-sets list is all-time and has no range to widen. So the
windowed case got its own `chart.empty.window.*` keys, whose only call site is `emptyChart`. That is
what later made the copy safe to reword in place (below) without touching the shared strings.

**The windowed message names the date, and instructs nothing** (2026-08-24, ticket 03d). It reads
EN *"Last trained on 07/12"* / DE *"Zuletzt trainiert am 12.07."* under the title *"No Data in This
Range"* / *"Keine Daten in diesem Zeitraum"*.

The date is the fact that makes the empty state actionable in one tap. Telling the user to "pick a
wider range" left them pill-hopping: the reporter's usage was last trained on 12.07., which **both**
1W and 1M miss — only the third pill along reaches it. Naming the date says which pill, without ever
naming a pill. It is also why the copy can drop the imperative safely: with gating on the free
windows end at 3M, so an instruction to widen can name an action a free user cannot complete, while a
statement of when the data is stays true in every entitlement state and needs no branch (see the
rejected gate-aware hint below). The **1J** / **Alle** pills carry lock badges, so which ranges are
theirs is already on screen.

- The date is resolved and formatted in `load()`, never in `body`: `ExerciseProgressViewModel`
  stores the finished string in `datedWindowEmptyMessage`, and `emptyChartMessage` — what the view
  reads — is a string lookup plus an optional read. `snapshot.availableUsages` carries
  `lastPerformed` already, so this costs no fetch; the picker items it is built beside drop the date,
  which is why one has to be kept separately.
- For a selected usage it is that usage's `lastPerformed`; for **`.combined`** it is the **newest**
  date across the usages — the combined series charts all of them, so the nearest one is the first
  window that would show anything.
- The formatting reuses `ExerciseUsageLabeling.lastTrainedDateText`, the same `Date.FormatStyle` the
  picker appends when two labels collide (a `FormatStyle` rather than a `DateFormatter` because that
  type is isolation-agnostic `Domain/` code). One rendering, so the date cannot read as two
  different facts on one screen.
- `chart.empty.window.message` survives as the **undated fallback**, reworded to drop its imperative
  half: EN *"This exercise has older workouts"* / DE *"Für diese Übung gibt es ältere Workouts"*. It
  renders when no date can be resolved. "Older" is always accurate: every window is "since X until
  now", so data can only fall out of it on the old side.

**What was deliberately not done.**

- **No re-selection once the screen is open.** Silently switching the timeframe or the usage *in
  response to what the user just did* is exactly the behaviour removed two sections above — it is
  what made the picker feel like it reshuffled itself. The range pills sit directly under the
  chart; one tap is the remedy, and the named date is what tells the user which tap. What ticket
  05b later added is a different thing and does not contradict this: the **opening** window is
  chosen once, before the user has expressed any preference, and never again (see "The screen opens
  on a range that has data" below). A tap on a pill still stands, permanently.
- **The opening window is not re-decided when the entitlement changes mid-session.** A free user
  parked on an empty 1M chart who buys Pro from another placement keeps that window: `chartTimeframe`
  does not move, so `loadKey` does not either, and the one-shot flag is already spent. It is one pill
  tap away, the newly unlocked pills lose their lock badges immediately, and 03d's copy names the
  date — whereas re-selecting a window under someone mid-session is the reshuffling this feature
  spent three tickets removing.
- **The recent-sets list is not hidden to "match" the empty chart.** It stays all-time and stays
  populated, which is also what keeps the empty chart from reading as a dead end.
- **The icon is unchanged** in both states. This was a wording defect, not a broken flow.
- **The windowed copy does not mention Pro** (decided 2026-08-24). With gating on, the free windows
  end at 3M, so a usage last trained longer ago than that is only reachable through a locked pill —
  and "pick a wider range" then names an action a free user cannot complete. A gate-aware branch was
  considered and rejected: §8 would have allowed it (placement **C** already lists "scrub the chart
  past 3 months", and placement **D** exists to "remove the surprise from placement C", so it would
  have been a D-style hint in front of an existing C gate), but the **1J** / **Alle** pills already
  carry lock badges, so the entitlement branch would restate what the badges say. The chosen fix is
  to make the sentence **descriptive** and name the last-trained date instead of instructing a tap —
  true in every entitlement state, no branch needed (shipped in ticket 03d, above). If this is ever
  revisited, Rule 4 binds: the workouts stay readable in **Letzte Sätze** directly below, so no copy
  may imply they are locked away, and placement C's own rule binds too: name the specific thing being
  unlocked, never "Go Pro".

Covered by `GymStreakTests/ExerciseProgressEmptyStateTests.swift`: all-time usages present with an
empty series ⇒ the window case (including a single usage, where the picker is hidden but the remedy
is the same), nothing anywhere ⇒ the never-trained case, a throwing load ⇒ the never-trained case,
repeated reads ⇒ still one fetch, and both key pairs resolve to distinct localized strings. Ticket
03d added: a known `lastPerformed` ⇒ the dated copy, `.combined` ⇒ the newest date across the usages
(the stub's options are dated so the newest is deliberately *not* the first one), an unresolvable
date ⇒ the undated fallback, and repeated reads of `emptyChartMessage` ⇒ the string stored by
`load()`.

Verified on device 2026-08-24 (DE, iPhone): the 12.07. usage on **1M** reads *"Keine Daten in diesem
Zeitraum / Zuletzt trainiert am 12.07."*, and 3M then draws the series.

### The stat cards describe the selected usage (2026-08-24)

The reporter's screenshot: **REKORD 20.0 kg** and **TREND +42.9%** above a list of sessions that
were mostly 14–15 kg work. Both numbers were arithmetically correct over the blended series and
both were useless — the record belonged to a slot the user was not looking at, and the +42.9% was
an artefact of a series alternating between two loads rather than any progression.

**The cards read the plotted series, and the plotted series is the selection.** Nothing had to be
recomputed for the first three criteria: `buildProgress` filters its rows by
`ExerciseUsageResolver.belongs(_:to:)` (previous section), so `ExerciseProgressData.dataPoints`
already holds exactly the points the chart draws. `personalRecord`, `progressPercentage(for:)` and
`sessionCount` are all defined over that array, so switching usage moves all three at once and a
stalling light day can no longer be masked by a heavy-day personal record.

**What each card means, per view:**

| Card | A usage selected | `.combined` (several usages) |
|------|------------------|------------------------------|
| **Rekord** | that usage's best — lowest number on a counterweight-assisted exercise | the exercise's all-time best across every usage. Defensible: it is the best this exercise was ever lifted, and the user asked for all of them |
| **Trend** | that usage's own first-to-last change over the plotted window | **withheld** — the card prints `Gemischt` / *Mixed* instead of a percentage |
| **Workouts** | the sessions plotted for that usage | every session plotted, i.e. every session that trained any usage |

**Why the combined trend is withheld rather than labelled.** It is the very number this bug is
about: with two usages the first-vs-last delta is decided by which usage happens to sit at each end
of the window, so it can print +42.9% for a series that never progressed and a loss for one that
did. Stating what it compares would make it honest and leave it useless — and it is rendered at the
same size, in the same green, as a real trend. So `ExerciseProgressViewModel.trendPercentage`
returns `nil` while `chartsSeveralUsagesTogether`, `trendValueString` prints `chart.trend.mixed`,
and `hasTrendValue` turns the card's accent neutral (a red "Gemischt" would read as a loss). The
chart headline's small trend badge reads the same optional, so it disappears with the number. The
remedy is one tap on the picker directly above, which is why the word is *Mixed* rather than a bare
dash.

**`.combined` over a single usage keeps its trend.** `chartsSeveralUsagesTogether` is
`selectedUsage == .combined && usageOptions.count > 1`; for an exercise with one usage, combined
*is* that usage. Without that clause the change would have removed a correct trend from nearly
every exercise in the app.

**Counterweight semantics are untouched by the selection.** The inversion lives in
`ExerciseProgressData` and keys off `loadBehavior`/`usesEffectiveLoad`, which describe the
*exercise*, not the usage: a selected assistance usage still reports its lowest number as the record
and reads a falling series as progress. The recent-sets card's "Best" line was brought in line with
it here too (see the section above).

**The Pro gate is unchanged and composes.** The cards still read `statMetric`, which falls back to
the free metric while a Pro-only one is selected, so no Pro number is printed beside the blurred
chart. The blend rule applies after that fallback: a combined view withholds the trend of whichever
metric the cards are reporting on.

Verified on device 2026-08-24 (DE, iPhone): `4–6 Wdh. · Pull` reads 20.0 kg / +0.0% / 5 Workouts,
`Ohne Zuordnung · 8–12 Wdh. · Pull` reads 13.0 kg / +0.0% / 2 Workouts, and `Alle Varianten` reads
20.0 kg / **Gemischt** / 5 Workouts with no trend badge beside the headline. The Workouts card
counting *sessions* is visible there: those days hold both a `4–6 Wdh.` and a `Kein Ziel` block, so
the combined count is 5 while **Letzte Sätze** lists 16 entries.

Covered by `GymStreakTests/ExerciseProgressStatCardTests.swift`: a two-usage history (20 kg in a 4–6
slot, 14 → 15 kg in an 8–12 slot, alternating) asserting record, trend and count per usage and for
`.combined`; the same history as a counterweight exercise, asserting the inverted record and a
negative trend for a rising assistance number; `bestSet` inverting with `loadBehavior` and the
aggregator propagating it; and the view-model rules — combined-with-two-usages prints the localized
*Mixed*, a selected usage and a single-usage combined view both print their percentage, and a locked
metric under gating still yields *Mixed* rather than a blended free number.

### The Fortschritt row headlines one usage (2026-08-24)

Counting sessions instead of instances (first section above) made the row's *count* honest but
left the summary itself blended: an exercise trained heavy in one routine slot and light in
another still got **one** sparkline and **one** percentage computed across both. That is the
number that read **+0.0% over 21 entries** in the original report, and after the picker landed
it became a cross-surface contradiction — tapping the row opened a screen that separated the
two usages and told a different story than the row that had been tapped.

**The row now describes one usage: the most recently trained one.**

- `FortschrittAggregator.build` resolves usages with the same `ExerciseUsageResolver` the
  chart, the recent-sets list and `PreviousPerformanceResolver` use, so "the same piece of
  work" has exactly one definition in the app. Each `(session, usage)` pair contributes one
  value; the occurrence index means a slot's second row in a workout is its own usage, so a
  session never contributes twice to one usage.
- **Keying happens per exercise, not per workout.** `.unattributed` is shared by every
  slot-less row, so keying a whole workout at once would number two different ad-hoc
  exercises `0` and `1` and invent a usage the detail screen — which only ever sees one
  exercise — never offers. The aggregator buckets a session's rows by live exercise first and
  calls `keyedRows` per bucket.
- **Rows with no completed set are filtered *after* keying**, exactly as
  `ExerciseUsageResolver.options` does it. Dropping them first shifts every later row of
  that slot by one, so a workout whose first block was left uncompleted would give the row
  occurrence `0` and the picker occurrence `1` — and the usage the row hands down would not
  exist in the menu it is handed to. A workout with no completed set of the exercise at all
  is still not counted, and never creates a row.
- **`sparkline` and `trendPct` are the headline usage's**, so the line is one coherent
  progression rather than an alternation between two loads.
- **`workoutCount` stays the exercise's total**, across usages, and so does `lastPerformed`.
  This is deliberate: the list is one row per exercise, and a user reads that number as "how
  much have I trained this". Scoping it to the headline usage would make an exercise trained
  15 times read "5 Workouts". The row says which usage its curve belongs to instead. The
  *date* costs nothing either way: the headline is the most recently trained usage, so its
  last session **is** the exercise's — the row cannot read "vor 21 Std." over a curve that
  stops in July.
- **`usageCount` and `headlineUsage` are `nil`/`1` for a single-usage exercise**, which then
  renders exactly as it did before — no marker, and the whole history in the sparkline.

**Headline selection: `resolveSelection`, not a second rule.** The aggregator calls
`ExerciseUsageResolver.resolveSelection(requested: nil, options:)` — literally the call the
detail screen makes when nothing has been picked — so the headline *is* the screen's default:
the **most recently trained** usage.

This replaced a most-sessions rule (2026-08-24, after the first on-device check), which read
well in tests and failed on real history. The reporter's `Ohne Zuordnung` buckets — legacy and
ad-hoc rows — hold more sessions than any live routine slot for almost every exercise, so
*every* multi-usage row headlined old work: Biceps Curls pointed at a usage last trained
**12.07.**, and tapping it opened the detail screen on its default 1M window with an empty
chart and a `-` record. The row also read `15 Workouts · vor 21 Std.` above a curve that
stopped in July. Recency fixes both at once and removes the need for a tie-break rule
altogether. What it gives up: a usage trained only once headlines with a single-point
sparkline and no trend — the honest rendering of "you started something new".

**Why not one row per usage.** Splitting the list would bury it under near-duplicate entries:
every routine slot of every exercise would become its own row, the muscle-group pills would
count slots rather than exercises, and the common case (one usage) would gain nothing. One row
per exercise, headlined and marked, keeps the list scannable and puts the full separation one
tap away on the screen that already has a picker for it.

**The row hands its usage to the screen it opens.** `FortschrittExerciseModel.headlineUsage`
travels as `ExerciseWithHistory.initialUsage` → `ExerciseProgressChartView(initialUsage:)` →
`ExerciseProgressViewModel.init(initialUsage:)`, where it becomes a *requested* selection.
Switching exercises inside the detail screen passes the switched-to exercise's own headline the
same way, so a switch lands where tapping that exercise's row would have. Two consequences:

- `ExerciseUsageResolver.resolveSelection` now **falls back to the default when the requested
  usage is absent from the options**. A usage the menu does not hold cannot have been chosen
  by the user (the options are all-time), so it can only arrive from outside the screen;
  honouring it would chart nothing while the picker read "all usages". This does not weaken
  03a's "a chosen usage is never swapped out" — narrowing the timeframe still keeps the
  selection and draws the empty state, because the options do not shrink with the window.
- The detail screen's default is unchanged (most recently trained). It only applies when
  nothing was requested — a push from somewhere without a row behind it, or an exercise with a
  single usage.

**The row's metric is max weight, and it says so.** The sparkline and the trend used to fold
to the best **estimated 1RM** of each session. That is a Pro-gated metric —
`ProFeatureCaps.freeChartMetric` is `.maxWeight`, and `ChartGatingPolicy.isMetricLocked` puts
`Gesch. 1RM` behind the paywall on the detail screen — so the free list was handing out a
number derived from something the screen it opens keeps locked, unlabelled. The fold is now the
**heaviest effective weight** of each session, the same reduction `buildProgress` applies to
`ExerciseProgressDataPoint.maxWeight`, which makes a row's sparkline the chart's own series for
that usage (pinned by an equality assertion, not a shape check). Two consequences:
reps no longer move the row at all, and the old `reps > 0` set guard — which `buildProgress`
never had — is gone. The last remaining disagreement, a *partly* snapshotted counterweight
series whose value space the two aggregators picked differently, was closed by ticket 08 —
see "The value space is a property of the series" above.

The metric is **named in the row**, in the caption style the detail screen already uses above
its headline number (`chart.metric.max_weight`, uppercased, 8pt). It carries the same
assistance exception as `ExerciseProgressViewModel.selectedMetricTitle`: a counterweight series
with no body-mass snapshot charts *assistance*, inverted, so the caption reads
`Unterstützung` rather than claiming a max weight. `FortschrittExerciseModel.chartsAssistance`
carries that fact out of the aggregator so the view does not have to know about load
behaviour.

**The row does not remember a usage the user picked on the detail screen.** Nothing persists that
choice — the headline is recomputed from history (most recently trained) on every load, so a user
who selects a different variant on the detail screen and comes back to the list sees the default
again. Making the row follow it would mean a per-exercise stored preference fed into the
aggregator; that was offered during ticket 05 and deferred as a slice of its own, not dropped.

**What is deliberately *not* aligned: the window.** The row is all-time; the detail screen is
windowed (1M by default). The same usage can therefore read +2.9% in the list and +0.0% on the
screen. The list's job is long-run direction — a windowed sparkline would go blank for anything
not trained this month — so the difference stays, and is recorded here rather than papered over.

**One consequence for an assisted exercise, recorded rather than fixed.** The value-space rule
above ("The value space is a property of the series") is the same rule on both surfaces, but each
applies it to the history *it* covers — all-time for the row, the selected window for the chart.
So a counterweight exercise whose *only* snapshot-less workout falls outside the opened window
reads as raw assistance in the list and as effective load on the screen it opens. The parity test
pins the two together for the all-time window only (`partlySnapshottedRowMatchesTheDetailScreensValueSpace`).
Aligning them would mean windowing the row, which is exactly what the paragraph above refuses.
A second, narrower residual has the same shape: `buildProgress` counts a session into `relevant`
as soon as a matching row exists, while the row skips a row with no completed set before folding,
so a workout that holds the assisted exercise but completes nothing in it moves the chart's
decision and not the row's. (Of the two, the chart is arguably the one in the wrong.) Both are
narrow enough that they are documented, not coded around.

**In the row.** On its **own full-width line** beneath the rest of the row (not sharing the
count line), `FortschrittExerciseRowView` renders the picker's own
`line.3.horizontal.decrease` icon, the headline usage's label inside `progress.row.curve_usage`
("Curve: %@" / "Kurve: %@"), and `progress.row.usage_of_total` ("of 2 usages" /
"von 2 Varianten"). The `Kurve:` prefix is there because the label alone did not say the curve
*belonged* to that usage — on device it was read as "this row covers 4 variants". The label is produced by the picker's own labeller,
`ExerciseUsageLabeling.pickerItems`, run inside the aggregator off the main actor — not from
the raw `displayLabel` — so two usages sharing a rep range carry the *same* disambiguating
suffix here as in the menu (`· zuletzt 12.07.`, `· #2`). Labelling from the descriptor alone
would have dropped exactly that suffix in exactly the case this feature is about. The row
stays a value struct (`FortschrittExerciseModel`); no `@Model`, no relationship read, no
formatter and no aggregation enters the row view. The label itself is built in the aggregator,
off the main actor; what `body` still does is two `NSLocalizedString` lookups (the `Kurve:`
wrapper and the caption), the same class of work as the `progress.workout_count` line that has
always been there.

The full-width line is a device-check correction too: sharing the count line, the label had to
fit beside the count suffix *and* the sparkline, and truncated to `Ohne Zuordnung · 4–…` for
any label carrying a marker plus a rep goal plus a routine name — which is most of them. The
line spans the card instead, label leading and `von N Varianten` trailing.

**It is rendered in metadata grey, deliberately.** The first build tinted it, and on device it
read as a control — tint plus a filter glyph looks like a button. It is not one, and cannot
usefully become one: the whole cell is the tap target and already opens this exact usage, so a
separate tap on the line could not do anything different.

**A second, narrower divergence, pre-existing:** `FortschrittAggregator.resolveLive` falls
back to a unique-name match when a row carries an `exerciseId` that points at nothing (a
deleted library entry), while `ExerciseProgressAggregator.matches` allows that fallback only
when `exerciseId` is `nil`. Such a row is counted by the list but invisible to the detail
screen, which can shift an occurrence index between the two surfaces. It degrades gracefully —
`resolveSelection` falls back to the default rather than charting nothing — and is recorded
here rather than fixed, because unifying the two match rules is a change to what the *chart*
includes, not to this row.

**Not carried over:** the row's label does not mark an archived usage. `fetchFortschrittSnapshot`
does not fetch live routine slot ids (the detail screen's `fetchExerciseProgress` does), and the
marker is worth a whole-library slot fetch on the list's hot path only if it turns out to matter.
The detail screen still marks it the moment the row is tapped. This is the one way a row's label
and the picker's can differ: where the marker is what separates two otherwise identical usages,
the row falls back to the date suffix the picker would have used without it.

Covered by `GymStreakTests/FortschrittAggregatorTests.swift`: max weight rather than 1RM (rising
reps at a constant weight must read 0.0%); the row's sparkline equalling the chart's `maxWeight`
series for the handed-down usage; the most recently trained usage
winning over an older one with more sessions, while the count stays the exercise's total; a single-usage row carrying no
headline; the row's series matching the detail snapshot for the handed-down usage point for
point; a tie landing on the detail screen's own default; two ad-hoc exercises in one workout
each keeping their own `.unattributed` usage; a colliding label carrying the picker's own
suffix; and a set-less row still counting towards the occurrence index (plus a workout of only
uncompleted sets counting for nothing). The fallback for an unknown requested usage is in
`ExerciseProgressAggregatorTests.swift`.

### The screen keeps the native swipe-back gesture (2026-08-24)

Tapping a Fortschritt row pushes this screen, and the leading-edge swipe-back did nothing — only
the custom chevron in `topBar` popped it. The cause is `.toolbar(.hidden, for: .navigationBar)`
(line 125), which the screen needs for its editorial canvas and hand-drawn back control: with no
system back-button affordance on the top view controller, `UINavigationController`'s own delegate
refuses `interactivePopGestureRecognizer`, so the gesture never begins.

**There is no pure-SwiftUI fix, still true on iOS 26.** Modifier ordering, the
`.navigationBarBackButtonHidden` variants and `UIGestureRecognizerRepresentable` all fail —
the last one installs a *new* recognizer rather than reinstating the system-owned one, and Apple
has published no API for it (DTS asked the community for workarounds on
[forum thread 818848](https://developer.apple.com/forums/thread/818848); the related
`.navigationTransition(.zoom)` inverse bug is open as FB22226720). The alternative that *is* fully
supported is to stop hiding the bar and keep a transparent system bar instead — what
`WorkoutDetailView` does. That was rejected here: this screen's custom top bar carries the usage
picker and the exercise switcher.

So the screen applies the pre-existing `.swipeBackEnabled()`
(`GymStreak/Extensions/View+SwipeBack.swift`) right after the `.toolbar(.hidden, …)` — a
`UIViewControllerRepresentable` that walks up to the hosting `UINavigationController` and swaps
`interactivePopGestureRecognizer.delegate` for a permissive one that only refuses to pop past the
stack root. It is reapplied on every `updateUIViewController` pass because UIKit reasserts its own
delegate around push/pop transitions. The helper shipped 2026-07-11 for `RoutineDetailView`; this
change is the audit the original fix deferred — `PeriodRecapView` and `ExerciseDetailView` were the
other two pushed destinations hiding their bar and got it as well. Tab roots
(`HistoryView`, `RoutinesView`, `ExercisesView`, `SettingsRootView`) do not need it: there is
nothing below them to pop.

**iOS 26 added a second recognizer.**
[`interactiveContentPopGestureRecognizer`](https://developer.apple.com/documentation/uikit/uinavigationcontroller/interactivecontentpopgesturerecognizer)
(iOS 26.0+) handles the "pan anywhere in the content area to go back" gesture and is a separate
property from the edge-only one — restoring swipe-back on iOS 26 means handling both. The helper
now sets `isEnabled = true` on it too, but deliberately **does not** replace its delegate: that
delegate is what arbitrates a content-area pan against scroll views, and a permissive replacement
would break vertical scrolling and the horizontal chip rows. If the content-area swipe still does
not fire on device, that is the remaining gap and the next thing to investigate — the edge swipe
this ticket was about is restored either way.

### The screen opens on a range that has data (2026-08-24)

The detail screen opened on `ChartTimeframe.month` unconditionally, so **any exercise last trained
more than a month ago opened empty**. Verified on device: **Chest Press** showed `REKORD -`,
`TREND -`, `0 Workouts` and *"Keine Daten in diesem Zeitraum / Zuletzt trainiert am 27.06."* — while
*Letzte Sätze* directly underneath listed **8 Einträge** and the Fortschritt row that pushed the
screen read `17 Workouts · vor 1 Monat` with a full sparkline. The screen held the data, drew none of
it, and said so in three places at once. One tap on **3M** fixed it, which is exactly why the
default was wrong rather than the data or the copy.

This is not about usages. Chest Press has a single usage and no picker, and it behaved identically
before the picker existed — every exercise was affected, so the fix belongs to the timeframe default.

**The rule.** `ChartGatingPolicy.narrowestUnlockedTimeframe(reaching:isPro:isGatingEnabled:now:)`
returns the first window in `ChartTimeframe.allCases` — declared narrowest-first — that is both
**unlocked for this user** and reaches back to the given date.
`ExerciseProgressViewModel.applyOpeningTimeframe(preferring:orAtLeast:)` asks it twice — for the
second-most-recent workout of the charted usage, then for the most recent one as a floor — and moves
`selectedTimeframe` to the first hit.

- **Two points where possible, one where not** (corrected 2026-08-24 after the device check). The
  window is asked to reach the **second**-most-recent workout of the charted usage, falling back to
  the most recent one. Anchoring only on the last workout shipped a chart that was non-empty just
  arithmetically: Biceps Curls, trained once in the past week, opened on **1W** showing a lone dot,
  `TREND -` and an axis invented around a single value, while 1M held the actual progression. This
  screen exists to show a curve, and a curve needs two points.

  **The two-point date is a preference, never a requirement**, and the distinction is load-bearing:
  a *gated* user's windows end at 3M, so a usage last trained 80 days ago whose previous workout
  was 100 days ago has no unlocked window reaching the preferred date. Requiring it would leave
  that user on an empty 1M chart with their sets listed underneath — verbatim the bug this section
  exists to remove. So the search runs twice, preferred date then last-workout date, and one real
  point beats none. The same fallback covers a usage trained exactly **once in all of history**.
- **Narrowest that works, not widest available.** 1W → 1M → 3M, first hit wins. Someone who trained
  twice this week still opens on the tightest window that holds both; widening past what is needed
  flattens the curve they came to see.
- **Only unlocked windows.** With gating on the search stops at 3M and returns `nil` for anything
  older, because auto-selecting **1J** / **Alle** would open a free user on a *blurred paywall*
  chart — worse than an empty one. For a Pro user (or with gating off) the unlocked set is all five,
  so an exercise last trained 200 days ago opens on **1J**, and one last trained over a year ago
  opens on **Alle** — its `startDate` is `distantPast`, so it is the last resort that matches
  anything, and for that exercise it is the only window that draws a curve at all. That costs no
  more to fetch than any other window: the exercise fetch is unbounded by design and the window is
  applied in Swift afterwards (see "Why the fetch is still unbounded, deliberately" above), so the
  only difference is how many sessions the aggregation folds.
- **1M stays the fallback** when nothing is found — never trained, a failed load, or data older than
  the widest unlocked window. The never-trained empty state is therefore unchanged, and 03d's dated
  copy remains the answer for a gated user whose data predates 3M. "1M" is precise only on first
  open: `updateExercise` resets the one-shot flag but deliberately does not reset the window, so
  switching to a never-trained exercise inside the screen keeps the window already on screen rather
  than snapping back — nothing is found, so nothing moves.
- **The window it tests is the window it will chart**: the *selected usage's* own workout dates, not
  the exercise's whole history. Otherwise the screen could still open empty on the very usage
  ticket 05 just handed down to it.

**Why it needs a second load, and why that is cheap.** The snapshot is fetched per window
(`startDate` is part of `LoadKey`), so "which is the narrowest window with a readable series" cannot
be answered before a load has happened. It does not need a probe fetch either — the first load
already carries both dates the rule needs:

- the **last**-workout date from `snapshot.availableUsages`, which is all-time (see the picker
  sections above) and is the same date 03d formats into the empty copy, resolved by the same
  `ExerciseProgressViewModel.lastPerformed(for:in:)` helper;
- the **second**-to-last from `snapshot.recentUsages`, which is likewise all-time, already filtered
  to the selected usage and capped by *sessions* — so its second distinct date is the second chart
  point. That is a sound proxy because both halves of the snapshot select sessions identically
  (completed sets of the selected usage, keyed by the same resolver), so a session there always has
  a point on the chart. `secondMostRecentWorkout(in:)` walks at most `recentSessionLimit` entries,
  in `load()`, deduplicating by session id — which is what a chart point is.

So the first load answers the question, and the window only moves when 1M is not already the right
answer:

- window already correct (trained inside the last month) ⇒ **one** fetch, the common case;
- window moves ⇒ **two**, and `isLoading` deliberately stays up across the swap so the screen shows
  its spinner instead of flashing the 1M state it is in the middle of replacing. The second load
  runs through the existing `.task(id: viewModel.loadKey)`, not through a nested call.

The window is resolved **before** the first snapshot is published, not after. `chartContent` is
gated on `isLoading`, but the **stat triple is not** — it reads `personalRecordString` /
`trendValueString` / `sessionCountString` unconditionally — so publishing the abandoned window's
snapshot would render one frame of `-` / `-` / `0 Workouts`, which is the exact screenshot this
ticket exists to remove. The handshake also compares `chartTimeframe`, never `selectedTimeframe`:
the second load is driven by `loadKey`, which carries `chartTimeframe`, and the two coincide only
while the selection is unlocked. Keying it on the selection would, the first time
`ProFeatureCaps.freeChartTimeframes` is retuned, suppress `isLoading = false` for a reload
`loadKey` never asks for — a permanent spinner behind a green build.

**It is a default, not a lock.** Two flags, and both are needed:

- `hasUserChosenTimeframe` is set by `updateTimeframe`, i.e. by a pill tap — including a tap on a
  locked pill, which is still a choice. From then on the default never fires again, for the life of
  the screen: not on a reload, not on a metric change, not on a usage switch, not on an exercise
  switch.
- `hasResolvedOpeningTimeframe` makes it one-shot **per exercise**, so a usage switch or a plain
  reload cannot move a window the screen has already opened on, while the in-screen exercise
  switcher (`updateExercise`, which resets it) still lands on the switched-to exercise's own
  narrowest window — the same thing tapping that exercise's Fortschritt row would have done.

**What was deliberately not done.** No widening in response to a user tap that lands on an empty
window: that tap is a choice, and 03d's dated copy is what explains the result. No probe fetch over
all-time history to find the exact narrowest window with data — the two dates already in the
snapshot bound it: the second distinct `recentUsages` session for the preferred window, and
`lastPerformed` as the floor.

`ChartGatingPolicy.narrowestUnlockedTimeframe` takes `now` as a parameter and compares against
`ChartTimeframe.startDate(from:)` rather than the clock-reading `startDate`, so it stays a pure
function of its arguments like the rest of that type and its boundaries are pinned exactly (one
second either side of the 1W and 1M bounds).

Covered by `GymStreakTests/ExerciseProgressOpeningRangeTests.swift`: two workouts inside 1W ⇒ opens
on 1W; one workout this week and the one before it 20 days back ⇒ opens on **1M** (the device
finding); a usage trained exactly once ever ⇒ the tightest window holding that single point;
data only inside 3M ⇒ opens on 3M with a drawn series and populated stat cards; a window that
already fits ⇒ kept, with no second fetch; a moving window ⇒ exactly one extra fetch and
`isLoading` still up in between; nothing anywhere ⇒ 1M and the never-trained copy; a gated free user
past 3M ⇒ 1M plus the dated windowed copy, never a locked pill; a Pro user past 3M ⇒ 1J; a gated
user whose *previous* workout is out of reach ⇒ the window that reaches the last one, with its
single honest point, while the same history charts a full curve on 1J for a Pro user; the policy
itself never returning a locked window across both gating states; and the "user's choice wins" cases
— chosen before the first load, and surviving a reload, a metric change and a usage switch.

**Verified on device 2026-08-24 (DE, iPhone).** Chest Press — the reported case, last trained
27.06. — opens on **3M** with the full curve, `90.0 kg` / `+12.5%` / `5 Workouts`, against the
`-` / `-` / `0 Workouts` of the bug report. An exercise trained 2–3 weeks ago still opens on 1M, the
in-screen switcher lands on the switched-to exercise's own window, a tapped pill survives metric and
usage changes, and with the entitlement simulated as free no locked pill is ever auto-selected.

That same check is what produced the two-point correction above — and the correction was then
verified in its own right: Biceps Curls, which had opened on 1W with a single dot, now opens on
**1M** with a multi-point series, while Chest Press stays on 3M.

### Two exercises with the same name are told apart (2026-08-24)

The reporter's library legitimately holds **two** "Biceps Curls": a barbell one and a dumbbell one.
The Fortschritt tab drew them as two visually identical rows — one `21 Workouts / +0.0%`, the other
`7 Workouts / +11.2%` — with nothing saying which was which, and the detail screen's exercise
switcher listed the same name twice. The data was right; the user simply could not navigate it.

This is **not** the usage work. A usage is two ways of training *one* library exercise; this is two
*different* library exercises that happen to share a display name. Both problems produce
"same-looking rows, different numbers", which is why they were reported as one bug, and they are
fixed in different places.

**The rule.** Where two or more **live** exercises share a display name case-insensitively, every
one of them prints its equipment as a qualifier. An exercise whose name is unique in the library
prints none — the overwhelmingly common case stays uncluttered, and a redundant "· Kurzhantel" on
every row would be noise.

- **Resolved once per list build.** `FortschrittAggregator.build` already indexes the library by
  lowercased name (`liveByName`, used for the legacy name fallback); the qualifier map is one extra
  pass over the buckets holding more than one exercise, keyed by exercise id. No view scans the
  library, and nothing about it is per row — `FortschrittExerciseModel.equipmentQualifier` arrives
  already decided, `nil` for the common case (main-thread rules 3 and 4).
- **The library decides, not the history.** The collision is computed over every live `Exercise`,
  including ones with no workouts yet, so a row's qualifier does not appear and disappear as the
  other variant is trained for the first time.
- **Two surfaces, one qualifier.** The Fortschritt row prints it as a small capsule beside the name;
  the switcher menu prints `"%1$@ · %2$@"` (`progress.exercise.with_equipment`) via
  `ExerciseWithHistory.displayName`, because a `Menu` entry is one line of text. The value is carried
  down the existing navigation payload, so the detail screen never re-derives it.
- **The detail screen's eyebrow, not its title.** With the switcher closed the headline is the
  only thing naming the exercise, so a bare "Biceps Curls" says nothing about which one. The
  qualifier joins the small tinted muscle-group line above the title — `BICEPS · LANGHANTEL` —
  rather than the 28pt headline, which would wrap. `currentEntry` (id-first, name as fallback)
  resolves the list entry once per title build and feeds both the muscle group and the qualifier;
  a screen pushed without a list behind it shows neither, exactly as before.
- **The switcher moved to its own file.** `ExerciseSwitcherMenu` is self-contained and
  `ExerciseProgressChartView.swift` was already far past this project's size convention, so it now
  lives in `Views/Charts/ExerciseSwitcherMenu.swift` beside `ExerciseUsageMenu`. Its grouping pass
  and its current-selection key are resolved in `init` — once per construction instead of twice per
  menu `body`. That is a reduction, not an escape from the render path: the owning screen's `body`
  still reconstructs the menu on its own invalidations.
- **The switcher was keyed by name.** `ForEach(…, id: \.name)` gave two same-named entries the same
  identity, and the checkmark matched on name too — so with the qualifier alone both entries would
  still have shown as selected. Both now key on `stableKey` (the exercise id). The screen's
  muscle-group label likewise resolves by id first, or a collision labelled the screen with the
  other exercise's muscle group.

**Known limitation.** Two same-named exercises that *also* share equipment stay indistinguishable —
the qualifier would print the same word twice. That combination is a duplicate the user can rename
or merge, and inventing an ordinal ("#2") would name nothing the user can recognise. If it turns out
to occur in real libraries, the next disambiguator is the muscle group, then the creation date.

### Unattributable legacy history stops disappearing silently (2026-08-25)

**The problem.** `WorkoutExercise.exerciseId` did not always exist. A row recorded before it
is matched to the live library **by name**, and both aggregators gate that fallback on the
name being unique — `ExerciseProgressAggregator.matches(…nameIsUnique:)` and
`FortschrittAggregator.resolveLive`. Where two live exercises share a name, every such row
is ambiguous and is **dropped** from the chart, the recent-sets list, the sparkline, the
trend and the record.

**Why dropping, and not guessing.** Only the user knows whether a 2024 "Biceps Curls"
session was the barbell or the dumbbell. Attaching it to one variant would silently rewrite
what they trained, and the number they then read would be wrong in a way nothing can
detect afterwards. Omitting it only hides work that is still in the database. Between an
unrecoverable wrong answer and a recoverable missing one, the missing one wins — that rule
stands and is not up for revision.

**What was actually wrong** was doing it in silence. The reporter created their own "Biceps
Curls" before the app shipped its predefined exercise library. Their library now holds two
exercises with that name, so every pre-`exerciseId` session against it is discarded, with no
indication anywhere that history is missing. The reasonable conclusion from that screen is
that the app lost their data.

**The change: say so, and offer the one action that resolves it.**

- `ExerciseProgressAggregator.unattributedLegacyHistory(in:exerciseName:)` counts the
  completed sessions holding at least one *completed* set of a matching legacy row, and
  reports them as `ExerciseProgressSnapshot.unattributedLegacy`. It is computed only when
  the name is ambiguous **and** the screen has an `exerciseId` — with no target exercise
  there is nothing to attribute to.
- `LegacyHistoryAttributionBanner` sits directly under the title, **above** the stat triple:
  every number below it is computed without the workouts it names, so the user has to read
  it first. It states how many workouts and from which period
  (`UnattributedLegacyHistory.periodText`, "Mär 2024 – Jul 2025"), because *when* is what
  lets a user decide *which* exercise those workouts were.
- Tapping the action opens a confirmation naming both the count and the exercise. On
  confirmation `LegacyHistoryAttributing.attributeLegacyRows(named:to:)` sets the missing
  link, the ViewModel posts `.historySourceDataDidChange` and reloads — and the same
  workouts then appear in the chart, the recent-sets list, the sparkline, the trend and the
  record, because they now match by id like any other row.

**What attribution may touch.** Exactly one field: `WorkoutExercise.exerciseId`. History is
denormalised on purpose so it survives routine and exercise edits — `exerciseName`,
`muscleGroups` and `loadBehaviorRaw` are a snapshot of what was performed, and re-deriving
them from today's library is how an old session would change meaning retroactively. A row
that already carries an `exerciseId` is never rewritten, which also makes the write
idempotent and makes it impossible to move a row the user resolved differently.

**No `@Model` change, so no CloudKit deploy.** `exerciseId` has existed on `WorkoutExercise`
since before this ticket; attribution only fills it in. The schema is untouched, so the
`-INITIALIZE_CLOUDKIT_SCHEMA` step in `docs/cloudkit-schema-automation.md` does not apply.

**Where the write lives, and why it is not on the read boundary.**
`HistorySnapshotProviding` is documented as a read boundary over the completed-session
graph, and its `@ModelActor` context is shared by several screens; committing a `save()`
through it would put a write on the context those reads run against. Attribution gets its
own seam — `Domain/Interfaces/LegacyHistoryAttributing.swift`, implemented by
`SwiftDataLegacyHistoryAttributionProvider` + `…Store` in `Data/History/`, wired in
`AppDependencies` — with the same `Task.detached` construction and the same **load-bearing
`@concurrent`**, since under `SWIFT_APPROACHABLE_CONCURRENCY` a plain `nonisolated async`
would run the fetch and the save on the calling `@MainActor` ViewModel's actor
(`docs/swift6-concurrency.md` §1). Its fetch is narrowed in the store to rows with no
`exerciseId`, so it never walks the full session graph; the case-insensitive name
comparison happens in Swift because `#Predicate` has no case-insensitive equality.

**Deliberate decisions.**

- **Confirmed, not undoable.** The ticket allowed either. Undo would mean persisting which
  rows a given attribution touched — a second record to keep in step with history, for an
  action a user performs approximately once. The dialog instead names the count, the
  exercise and the fact that it cannot be undone in the app. To restore, clear
  `exerciseId` on the affected `WorkoutExercise` rows.
- **Only the detail screen carries the banner.** It is where the withheld numbers are read
  in full and where the resolution target is unambiguous — the screen *is* one specific
  library exercise. The Fortschritt row has no such target to offer.
- **The count and the write have deliberately different scopes.** Both are restricted to
  **finished** workouts — a session still being performed is not history, and its rows are
  left alone. Within a finished session the count requires at least one *completed* set,
  because a row without one renders nowhere even once linked and promising it would be a
  second wrong number; the write links every matching row, because a row is a row and
  leaving one behind would keep the same workout half-legacy.
  `ExerciseProgressAggregator.isUnattributedLegacyRow` is the shared *row* predicate; each
  side adds its own session-level condition on top.
- **`loadBehavior` is not part of the finding.** The homogeneity filter (a library setting
  only describes future workouts) is a separate rule, and a row it excludes stays excluded
  after attribution. Folding it in here would make the banner's number depend on a rule the
  user cannot act on — but note the consequence: a legacy row whose `loadBehaviorRaw`
  differs from the target exercise's current behaviour is attributed and still not charted.
- **The finding is cleared on exercise switch.** `updateExercise` drops it along with the
  usage menu; keeping it would offer to attribute one exercise's legacy rows to another.

**One surface was applying the fallback ungated, and was fixed with this work.**
`ExerciseDeepDiveAggregator` (the AI Coach panel on this very screen) carried its own copy of
the matching rule *without* the uniqueness gate, so it claimed every ambiguous legacy row for
**both** same-named exercises instead of neither. That is worse than the drop documented here,
and attribution does not repair it — see `docs/ai-coach.md` §3. It now calls
`ExerciseProgressAggregator.matches` like everything else. Four copies of one rule is how three
stayed correct while the fourth drifted; the rule now has one implementation and three callers.

**Tests.** `GymStreakTests/LegacyHistoryAttributionTests.swift` — detection with its count
and period (and the set-less session that must not be counted), a unique name reporting
nothing, the write touching only the link while leaving an already-attributed row and
another exercise's legacy row alone, the attributed workouts entering the chart while the
other variant's screen sees nothing, idempotence, and the two ViewModel paths (resolved,
and a failed write that keeps the banner).

### The stat cards name the range they describe (2026-08-25)

**Found on the device check for ticket 07.** The Biceps Curls (Langhantel) screen read
`4 WORKOUTS` on 3M while *Letzte Sätze* directly beneath it announced `7 Einträge`. Both
numbers were correct and the screen looked like it was contradicting itself.

The two answer different questions, and neither said so:

- The **stat triple and the chart are windowed** by the selected range.
  `ExerciseProgressData.sessionCount` is `dataPoints.count`, and `buildProgress` filters by
  `startDate`. The record and the trend read the same windowed `progressData`, so **all
  three** cards are range-scoped, not just the count.
- ***Letzte Sätze* is deliberately all-time**, capped at
  `ExerciseProgressViewModel.recentSessionLimit` **sessions** — see "The recent-sets list
  shows every usage" above.

`ExerciseProgressViewModel.statLabel(_:)` now appends the loaded range to every card's
label — `REKORD · 3M`, `TREND · 3M`, `WORKOUTS · 3M`. **All three, not only the count:**
qualifying one would have implied the other two were all-time, which is the opposite of the
truth.

**The label must never move ahead of the numbers, and that decides where the range lives.**
`load()` deliberately keeps the previous snapshot published for the whole duration of a
reload — the stat triple is not gated on `isLoading`, and clearing `progressData` would flash
"- / - / 0 Workouts" (the defect ticket 05b removed). So between a range tap and its result
landing, the cards still show the *old* window's record, trend and count. Reading the label
off `chartTimeframe`, which `updateTimeframe` moves synchronously, therefore captioned those
numbers with the new range for that whole interval — the exact mismatch the qualifier exists
to remove, inverted, and caught in review rather than on the device.

The range is published instead: `statRange` is set beside `progressData = snapshot.data` from
a window captured at the top of `load()` alongside `startDate`, so caption and numbers move
together and cannot come apart. It is reset in the failure branch for the same reason. Nothing
else may write it — in particular it must not be cleared in `updateExercise`, which does not
clear `progressData` either.

A Pro-locked window needs no special case: a locked tap moves neither `chartTimeframe` nor
`loadKey`, so no reload starts and `statRange` still names the window the chart kept drawing.

The interpolation itself stays on the read side — three `String(format:)` calls at a fixed
three-card `HStack`, no `ForEach` over user data, no formatter *object* allocated and no
collection traversal, so the rendering rules are satisfied; correctness comes from `statRange`
being published, not from where the string is built. The card label is `lineLimit(1)` +
`minimumScaleFactor(0.7)` so the longest composed label ("WORKOUTS · ALLE") cannot wrap one
card taller than its neighbours.

**The banner's copy was reworded at the same time.** With the legacy-history banner directly
above the cards, the screen briefly showed "4 Workouts (Feb. 2026 – Apr. 2026)" immediately
over a `4 WORKOUTS` card — two different facts wearing the same shape. The banner now leads
with the period ("Aus Feb. 2026 – Apr. 2026 sind 4 Workouts … nicht enthalten"), so the count
sits mid-sentence and no longer parallels the card. The format string reorders its arguments
(`%2$@` before `%1$d`), which is pinned by an assertion on both the count *and* the period in
`LegacyHistoryAttributionTests`.

**Tests.** `ExerciseProgressStatCardTests` — every label carries the loaded range and still
contains its base label; a **pending** range change does not relabel the numbers still on
screen (this one fails against the `chartTimeframe` version); and a locked range labels the
*charted* window rather than the tapped one.

### Components

#### iOS Target

| Component | File | Purpose |
|-----------|------|---------|
| ExerciseProgressChartView | `Views/Charts/ExerciseProgressChartView.swift` | Main chart view with timeframe picker, metric picker + info button, and interactive chart. Its title eyebrow resolves the current list entry by id first, so a shared display name neither mislabels the muscle group nor hides which variant is charted |
| ProgressChartContent | `Views/Charts/ExerciseProgressChartView.swift` | SwiftUI Charts rendering with line/point marks, axis formatting, tap overlay, and data point annotation. Takes a **precomputed `ChartSeries`** plus the metric's *name* — never the progress data. It has no `yDomain` of its own: computing one here meant mapping the whole series once per point (`AreaMark`'s `yStart` read it from inside the drawing `ForEach`), and the marks and `chartYScale(domain:)` must agree on the display unit |
| ExerciseSwitcherMenu | `Views/Charts/ExerciseSwitcherMenu.swift` | Toolbar dropdown to switch between exercises grouped by muscle. Entries print `ExerciseWithHistory.displayName` (equipment-qualified only where the name collides) and are keyed/checkmarked by `stableKey`, never by name. Grouping and the current key are resolved in `init` — once per construction rather than twice per menu `body` |
| ExerciseUsageMenu | `Views/Charts/ExerciseUsageMenu.swift` | Usage picker beside the switcher — which routine slot the chart and the recent-sets list describe. Rendered only when the exercise has more than one usage; entries arrive pre-labelled from the view model |
| LegacyHistoryAttributionBanner | `Views/Charts/LegacyHistoryAttributionBanner.swift` | Warns that legacy workouts sharing this exercise's name are withheld from every number below it, and confirms the one-way write that resolves them. Takes pre-composed strings — no formatter, no history scan in `body` |
| ChartTimeframePicker | `Views/Charts/ChartTimeframePicker.swift` | Segmented button row for timeframe selection (1W, 1M, 3M, 1Y, All) |
| ChartDataPointAnnotation | `Views/Charts/ChartDataPointAnnotation.swift` | Floating tooltip card showing exact value + date for a tapped data point |
| MetricInfoPopover | `Views/Charts/MetricInfoPopover.swift` | Popover explaining what the selected metric measures and how it's calculated |
| SummaryStatsView | `Views/Charts/ChartSupportViews.swift` | Three stat cards: Personal Record, Trend, Sessions |
| StatCard | `Views/Charts/ChartSupportViews.swift` | Reusable stat card with icon, value, and label |
| EmptyChartView | `Views/Charts/ChartSupportViews.swift` | Placeholder shown when no workout data exists |
| RecentUsageCardView | `Views/Charts/RecentUsageCardView.swift` | One recent-sets card — **one usage's sets within one workout**, badged with the usage it belongs to. Takes an `ExerciseRecentUsage` value, never a `@Model`. Weights render through `WeightFormatting` in the user's unit |
| ChartSeries | `Presentation/Helpers/ChartSeries.swift` | The plotted series in **display** units plus the y-domain derived from those same converted numbers, built once per load / metric change / unit change. Each point carries its canonical `ExerciseProgressDataPoint`, so a tap resolves the selection in kilograms. In `Presentation/` on purpose: the conversion is display work (see `docs/weight-unit-preference.md` §8) |
| ExerciseProgressViewModel | `ViewModels/ExerciseProgressViewModel.swift` | Takes `WeightUnitPreferenceProviding` by init injection and owns every weight string on the screen — `headlineValue`/`headlineUnitWord`, the tap annotation, `personalRecordString` — plus `chartSeries` and its `refreshChartSeries()`, which reruns on a metric change (`selectedMetric.didSet`) and on a unit change; `async load()` behind a generation counter; `statLabel(_:)` scopes each stat card's label to `statRange` — the window the **published** numbers were computed over, not the tapped one (see "The stat cards name the range they describe" above); owns timeframe, metric, selection and the loaded snapshot; computed display properties; owns the **P2 Pro gate** (which metric/window is locked, what a locked selection renders, which paywall it raises), `emptyChartReason`, which tells "never trained" apart from "nothing inside this window", and `emptyChartMessage`, whose dated windowed line is formatted in `load()` |
| ChartGatingPolicy | `Domain/Services/ChartGatingPolicy.swift` | **Pure, isolation-agnostic.** Which metrics and windows the free tier may read, from `ProFeatureCaps` — plus the widest free window a lapsed user's chart clamps back to |
| ExerciseProgressModels | `Domain/Models/ExerciseProgressModels.swift` | Domain values: ChartTimeframe, ProgressMetric (+ **ProgressQuantity**), ExerciseProgressDataPoint, ExerciseProgressData, **ExerciseRecentUsage**, **ExerciseProgressSnapshot** (incl. `unattributedLegacy`), **UnattributedLegacyHistory**, SelectedDataPoint. Everything that crosses the actor boundary is explicitly `Sendable`. `ProgressMetric.unit: String` used to return the literal `"kg"`; it is `quantity: ProgressQuantity` (`.weight` / `.volume`) now, so this layer classifies the number and Presentation resolves the word. |
| ExerciseUsage | `Domain/Models/ExerciseUsage.swift` | The usage cluster: **ExerciseUsage** (+ `Slot`, `repRangeText`, `displayLabel`), **ExerciseUsageSelection**, **ExerciseUsageOption** (+ `isArchived`), **ExerciseUsagePickerItem** (the picker's entries *and* a Fortschritt row's headline), **ExerciseUsageLabeling**. One label implementation for the recent-sets badge and the picker; the "not in a routine" marker is added by `pickerItems` only. All `Sendable`. |
| ExerciseProgressAggregator | `Domain/Services/ExerciseProgressAggregator.swift` | **Pure, isolation-agnostic** chart + recent-sets aggregation. `buildRecentUsages` emits **one card per usage per session** — see "The recent-sets list shows every usage" above. The usage filter on `buildProgress` / `buildRecentUsages` comes from `ExerciseUsageResolver` — see "The chart separates usages by routine slot" above. `matches(_:exerciseId:exerciseName:nameIsUnique:)` resolves workout exercises to the chart target — an exact `exerciseId` match, OR a legacy row with `exerciseId == nil` whose name matches case-insensitively **and only when the name is unique in the live library**. Without the fallback, workouts logged before `WorkoutExercise.exerciseId` existed would be invisible and progress would look frozen; without the uniqueness gate, same-named equipment variants would double-count. `unattributedLegacyHistory(in:exerciseName:)` reports what that gate is currently withholding, and `isUnattributedLegacyRow` is the one definition the write side shares — see "Unattributable legacy history stops disappearing silently" above. |
| FortschrittAggregator | `Domain/Services/FortschrittAggregator.swift` (+ `FortschrittAggregator+Fold.swift`, the accumulators and the set-level reduction) | **Pure, isolation-agnostic.** Builds the Fortschritt list's rows (count, sparkline, trend, usage headline) from completed sessions + the live `Exercise` library. **One entry per session, not per `WorkoutExercise`** — see "The Fortschritt row counts sessions, not exercise instances" above — and the sparkline/trend describe the **most recently trained usage**, in **max weight**, while the count stays the exercise's total — see "The Fortschritt row headlines one usage" above. It also resolves the **equipment qualifier** for names shared by several live exercises, once per build — see "Two exercises with the same name are told apart" above. |
| FortschrittExerciseRowView | `Views/History/FortschrittExerciseRowView.swift` | One Fortschritt list row: badge, name (with an equipment capsule only when another live exercise shares that name), workout count, sparkline, trend %, and — only when the exercise has several usages — which usage the curve describes and how many there are. Takes a `FortschrittExerciseModel` value; no `@Model`, no string building, no formatter in `body`. |
| SwiftDataHistorySnapshotStore | `Data/History/SwiftDataHistorySnapshotStore.swift` | `@ModelActor` that performs the fetch and calls the aggregator off the main actor. `SwiftDataHistorySnapshotProvider.fetchExerciseProgress` is the `@concurrent` entry point. Also reads the live routine slots (`fetchLiveRoutineSlotIds`) that mark archived usages. |
| LegacyHistoryAttributing | `Domain/Interfaces/LegacyHistoryAttributing.swift` | The write seam, deliberately separate from the `HistorySnapshotProviding` read boundary. Sets `WorkoutExercise.exerciseId` on legacy rows and nothing else; idempotent, because a row that already has one is skipped |
| SwiftDataLegacyHistoryAttributionStore | `Data/History/SwiftDataLegacyHistoryAttributionStore.swift` | `@ModelActor` owning its own `ModelContext` for that one write. `SwiftDataLegacyHistoryAttributionProvider.attributeLegacyRows` is the **`@concurrent`** entry point — without it the fetch and the `save()` would run on the calling ViewModel's main actor |
| ExerciseProgressService | `Data/Progress/ExerciseProgressService.swift` | The vs-previous seam. Owns no `ModelContext`: `@MainActor` glue that runs `ExerciseComparisonBuilder` either side of one `@concurrent` boundary call. Does not feed the chart. |
| ExerciseComparisonBuilder | `Domain/Services/ExerciseComparisonBuilder.swift` | **Pure, isolation-agnostic.** `makeLookup` reduces the current workout to `Sendable` values; `build` assembles the comparison rows from it plus the resolved predecessors. Runs on the main actor because the workout may be uncommitted. |
| ExerciseUsageResolver | `Domain/Services/ExerciseUsageResolver.swift` | **Pure, isolation-agnostic.** The single definition of "the same piece of work": `slot(of:)`, `usage(of:in:)`, `belongs(_:to:)`, the picker's `options(in:liveSlotIds:matching:)` — which also flags a usage whose slot no live routine holds — the shared `sorted(_:)` order and `DescriptorRank`, and the default (plus the unknown-usage fallback) in `resolveSelection`. Shared by the chart aggregator, `FortschrittAggregator` and `PreviousPerformanceResolver`. |
| PreviousPerformanceResolver | `Domain/Services/PreviousPerformanceResolver.swift` | **Pure, isolation-agnostic.** Resolves every exercise of one workout against the most recent comparable session, in a single pass. Its slot match calls `ExerciseUsageResolver.slot(of:)` — the same rule the chart segments usages by. Runs inside the model actor. |
| PreviousPerformanceLookup | `Domain/Models/PreviousPerformanceLookup.swift` | The `Sendable` request: `before`, `routineId`, and one `Query` per exercise. Carries the workout's identity across the actor boundary without a `@Model` or a re-fetch. |

#### watchOS Target

No progress chart feature on watchOS. Watch app has real-time workout metrics only (elapsed time, heart rate, calories via MetricsView).

## Metrics

### Counterweight-assisted exercises

Exercises can declare that their entered load is **counterweight assistance** rather than added
resistance (for example, Assisted Pull-Up). Lower assistance is progress. For a workout that has
a body-weight snapshot, effective load is `body weight − assistance`, and the normal max-load,
estimated-1RM, volume, and PR calculations use that effective value. If any point in an assisted
exercise's selected chart range lacks a snapshot, the chart safely falls back to a single
**Assistance** metric: lower is better and the trend is inverted. It never presents a fabricated
1RM or volume in that case.

| Metric | Label (EN) | Label (DE) | Calculation |
|--------|-----------|-----------|-------------|
| Max Weight | Max Weight | Max. Gewicht | Highest weight lifted in any completed set during the session |
| Est. 1RM | Est. 1RM | Gesch. 1RM | Epley formula: weight × (1 + reps ÷ 30), best across all sets |
| Total Volume | Total Volume | Gesamtvolumen | Sum of (weight × reps) across all completed sets in the session |

### What each metric tab is named

`ExerciseProgressViewModel.title(for:)` is the single rule for naming a metric on the detail
screen, and it is **per metric, not per selection**. It returns `metric.localizedTitle` except in
one case: on a counterweight-assisted exercise charted in *entered* weight
(`loadBehavior.isCounterweightAssistance && !usesEffectiveLoad`), the max-weight axis carries
assistance rather than load, so `.maxWeight` reads `Unterstützung` / `Assistance`
(`exercise.assistance`). Charted in effective load, that same tab keeps the plain
`Max. Gewicht` / `Max Weight` wording. Nothing about the rename depends on which tab the user has
selected.

Both the tab row and the stat headline above the chart call through it — the headline via
`selectedMetricTitle`, which is now just `title(for: selectedMetric)`, so the assistance exception
exists in one place. Wiring the tab row through `selectedMetricTitle` instead is what produced the
bug fixed on 2026-08-25: selecting *Gesch. 1RM* made the tab row read
`Gesch. 1RM | Gesch. 1RM | Gesamtvolumen`, because the max-weight tab renamed itself to whatever
was selected and the first metric became unreachable by name. (Introduced in `d0e9727`, which
rewrote that line to add the Pro badge.) The Fortschritt row's caption applies the same exception
from its own precomputed `FortschrittExerciseModel.chartsAssistance` flag, so the list and the
detail screen name one metric rather than two. Pinned by
`GymStreakTests/ExerciseProgressMetricTitleTests.swift`.

**Known gap, deliberately left.** The ⓘ popover is the one surface on the detail screen that still
names a metric without `title(for:)`: `MetricInfoPopover(metric: viewModel.selectedMetric)` renders
`metric.localizedTitle` and `metric.localizedDescription`. On a counterweight-assisted exercise
charted in entered weight the single tab therefore reads `Unterstützung` while the popover header
reads `Max. Gewicht` and explains max weight. Fixing it properly needs an assistance-specific
description string, not just a title parameter, which is why it was left out of the 2026-08-25 tab
fix. To pick it up: give `MetricInfoPopover` a `title:` parameter fed by
`viewModel.title(for: viewModel.selectedMetric)` plus an `exercise.assistance.description` string
in `en`+`de`.

## Chart Interaction

- **Timeframe selection**: 1W, 1M, 3M, 1Y, All — filters data and adapts X-axis date granularity. Changing it changes `viewModel.loadKey` (via `chartTimeframe` — see "Pro gating" below), so `.task(id:)` cancels the in-flight load and starts a new one. The recent-sets list is deliberately **all-time** and unaffected by the range, matching the pre-existing behaviour.
- **Metric switching**: Segmented picker switches chart data without reloading (all metrics pre-fetched)
- **Info popover**: ⓘ button next to metric picker shows metric description
- **Data point tap**: Tap on chart area finds nearest data point, shows floating annotation with exact value + date. Tap empty area to dismiss. Selection clears on metric/timeframe/exercise change.

## Axis Formatting

- **Y-axis**: Compact number formatting with "kg" unit (e.g., "85 kg", "1.2k kg")
- **X-axis**: Timeframe-adaptive date labels (days for 1W, weeks for 1M, months for 3M/1Y, months+year for All)

## Pro gating (P2)

Gating **ships on** — `ProGating.shippedValue` has been `true` since the Phase 2 launch release
(2026-08-17, ticket 15 of `.scratch/pro-entitlements/`). A free user reads max weight over
1W / 1M / 3M; estimated 1RM, total volume, 1Y and All are Pro. With gating off (`-PRO_GATING_OFF`
in a Debug scheme, or a rollback per §9.6) none of this is active and the screen behaves exactly as
described above. That distinction matters for the opening-window rule: on the shipped
configuration, a free user whose data predates 3M takes the `nil` → keep-1M branch with 03d's dated
copy, **not** the `.all` branch — that one is reached only by a Pro user or with gating off. The rules live in `ChartGatingPolicy` and the full rationale in
`docs/pro-subscription.md` §5d; what matters for this screen:

- The metric tabs and the range pills **stay interactive** while the chart is locked. Only the
  chart headline and the chart itself sit inside `.proLocked`, which disables what it blurs — a
  user who could not switch back would be trapped behind the blur.
- Selecting a Pro-only metric or window still *selects* it (the tab/pill highlights) and raises
  `.chartMetric` / `.chartWindow`. Locked options carry an `OnyxProBadge(style: .icon)` so the gate
  is honest before the tap.
- **A locked window is previewed, never fetched.** `loadKey` and `load()` key off
  `chartTimeframe`, not `selectedTimeframe`: while a Pro-only window is selected the chart keeps
  drawing the last window the user is entitled to, so the blurred preview costs exactly what the
  free path costs. A locked *metric* costs nothing either — every `ExerciseProgressDataPoint`
  already carries all three values from the one fetch.
- The PR and Trend stat cards fall back to the free metric while the selected one is locked, so no
  Pro number is printed in plain text beside the blurred chart. The usage rules apply after that
  fallback: with several usages charted together the Trend card prints *Mixed* whichever metric the
  gate left it reporting on.
- **The opening window respects the gate.** The screen picks the narrowest window that has data
  when it opens (see "The screen opens on a range that has data"), and that search skips locked
  windows entirely: a free user is never auto-selected onto **1J** / **Alle**, which would open them
  on a blurred paywall chart. With gating on the search stops at 3M and falls back to 1M, where
  03d's dated empty copy explains what they are looking at.
- Entitlement changes are live: the gate reads the `@Observable` provider during `body`, so a
  purchase unblurs the chart and reloads the wider window through the existing `.task(id:)` with no
  refresh gesture, and a lapse blurs it and clamps the rendered window back to 3M. No workout,
  session or set is ever hidden in any entitlement state.
