# History (Verlauf) — main-thread hang remediation

**Status: root cause isolated and removed 2026-07-26. The automated 60-session
main-run-loop regression passes five repeated runs; 308/308 unit tests pass; the
GymStreak iOS scheme returns `BUILD SUCCEEDED`; final architecture review is
`PASS WITH WARNINGS` with no critical findings.**

The post-1.1.5 regression was the custom `SwipeToDeleteContainer` added in `0ffd13c`.
At 60 sessions, the released 1.1.5 code measured a 41 ms fast-scroll main-run-loop delay;
the post-release wrapper measured 298 ms; reverting only that wrapper in the same commit
restored 45 ms. The production code now uses native `NavigationLink<UUID>` rows, a
context-menu delete shortcut and the visible delete menu in workout detail. The custom
gesture/focus/accessibility/offset graph and its shared swipe state were deleted.

**Phase 1 alone made the screen worse on device, and that is the most important lesson in this
document.** Laziness landed *before* the row models it depends on, so the four
`workoutExercises → sets` traversals per card moved out of the one-time entry burst and into
scroll realisation — where a `LazyVStack` re-pays them every time a row is destroyed and
rebuilt. The user reported the original entry hang unchanged plus a *new* multi-second stall
after scrolling stopped. **Sequencing rule: precompute the row models first, make the container
lazy second.** Phase 2 (below) is what actually removes the cost; Phase 1's laziness is only
correct in combination with it.

Phase 1 and 2 removed rendering-time repetition but did not remove the unbounded SwiftData
fetch and O(history) aggregation interval from `MainActor`. The release regression test made
that distinction visible, so Phase 3 moved snapshot loading behind a model actor. That work
improved the pre-existing scaling cost but did not solve the reported post-release scroll
freeze. The commit-level A/B above identified the independent row-interaction regression.

This document is the durable, self-contained brief for the fix. It carries the
diagnosis, the code evidence with file:line references, the measured Instruments
baseline, the phased plan, and the acceptance targets. It is written to be picked up
cold, with no prior conversation context.

Related: [history-redesign.md](./history-redesign.md) (what the screen is),
[delete-workout.md](./delete-workout.md) (why the list is not a `List`),
[architecture.md](./architecture.md) (layer rules).

---

## 1. Symptom

The Verlauf tab's **Trainings** sub-section ignores all touch input for roughly 1–2
seconds after it appears. The same stall reproduces when toggling the in-screen
segmented control Fortschritt → Trainings. Scrolling afterwards feels clunky.

## 2. Diagnosis

A **busy** main-thread hang, not a blocked one — the main run loop is saturated with
synchronous work, so touches are never dispatched. Apple's discriminator (Instruments
"Identifying a Hang": high main-thread CPU across the hang interval = busy) matches.

The release regression had one narrow cause: a custom interaction graph attached to every
Trainings row. The existing screen also contained synchronous aggregation and eager rendering
costs that amplified entry time as histories grew. Both matters are documented separately
below because the broad scaling refactor alone did not remove the device-visible freeze.

### Contributors, ranked by cost

#### 2.1 Post-1.1.5 custom row interaction — the release regression

`HistoryView.swift:62` is `ScrollView { VStack { … } }`; `TrainingsTabView.swift:195`
and `:233` are plain `VStack` + `ForEach`. Every `WorkoutCardView` in the *entire*
history is constructed and laid out up front. Per card:

- `WorkoutCardView.swift:124-140` — **two `DateFormatter`s** allocated (`dowText`,
  `monthText`), each via `setLocalizedDateFormatFromTemplate`.
- `WorkoutCardView.swift:27,98,99` — `completionPercentage`, `completedSetsCount` and
  `totalVolume` → **three full traversals** of the SwiftData
  `workoutExercises → sets` graph (relationship faulting, N+1 against SQLite).
- `SwipeToDeleteContainer.swift` — per card: `.focusable()`, `.contextMenu`,
  `.accessibilityElement(children: .combine)`, a `DragGesture`, a `TapGesture`, an
  opaque background and two `.onKeyPress` handlers. `.contextMenu` installs a
  `UIContextMenuInteraction` per row.

At 100 sessions that was ~200 `DateFormatter`s + ~300 relationship traversals + one
custom drag/tap/focus/accessibility graph per card. The container arrived in `0ffd13c`.
The exact commit A/B recorded 298 ms during a fast scroll versus 41–45 ms without it,
so it was removed rather than micro-optimized.

#### 2.2 Five whole-history aggregations computed inside `body`

`TrainingsTabView.body` recomputes all of these on every render:

- `HistoryStatsService.weekStats` → `totalVolume` per session, plus `streakWeeks`.
- `HistoryStatsService.swift:216` `weekKey` — allocates a `DateFormatter` **per session**
  and again **per streak-loop iteration**, purely to build a `String` dictionary key.
- `weekDayStatuses` → 7 more `DateFormatter`s (`weekdayLabel`, `:224`).
- `groupByMonth` (`:125`) → `totalVolume` for **every session in history**, plus one
  `DateFormatter` per month (`monthLabel`, `:234`).
- `plannedWeek` → `WorkoutPlanningService.plannedWeek` walks routines × sessions and
  touches `session.routine?.id` (a to-one fault) twice per routine
  (`WorkoutPlanningService.swift:72` and `:98`).
- `lastMonthStats` (`TrainingsTabView.swift:50`) → `totalVolume` over last month.

#### 2.3 `refresh()` is two full-history passes on the main actor

`HistoryView.refresh()` (`:262`) calls `PersonalRecordService.computePRs` and
`FortschrittAggregator.build`. Both are `@MainActor` and O(sessions × exercises × sets)
with faulting. It runs from `onAppear`, on every history-count change, and on every
exercise-library change — and `FortschrittAggregator.build` runs even when the visible
section is `.trainings`.

#### 2.4 Unbounded synchronous fetch in `onAppear`

`onAppear` (`:153`) → `viewModel.fetchWorkoutHistory()` →
`SwiftDataWorkoutSessionRepository.fetchAll()`, a bare
`FetchDescriptor<WorkoutSession>` with no `fetchLimit` and no
`relationshipKeyPathsForPrefetching`, so every later relationship access faults
individually.

#### 2.5 `exerciseLibrarySignature` rebuilt every body evaluation

`HistoryView.swift:53` maps the whole `@Query`'d `Exercise` library (~96 seeded entries
plus user additions) into interpolated `String`s, purely to feed `.onChange(of:)`.
Allocation plus an `Equatable` array compare on every render.

#### 2.6 Over-broad observation

`HistoryView` holds `@ObservedObject var viewModel: WorkoutViewModel` — 15 `@Published`
properties including `elapsedTime`, driven by a 1 Hz `Timer`
(`WorkoutViewModel.swift:1278-1288`). Any tick invalidates the entire History body.

#### 2.7 Fortschritt has the same shape

`FortschrittTabView.swift:145-166` — non-lazy `VStack` + nested `ForEach`, every row
rendering a `MiniSparkline` `Canvas`. `FortschrittExerciseRowView.swift:76-81` allocates
a `RelativeDateTimeFormatter` **per row, per render**. `navigationValue(for:)` (`:180`)
attaches `allExercisesForNavigation` — itself a computed property re-mapped each render
— to every row's link value.

### Why the stall is intermittent

`WorkoutViewModel.swift:154-164` re-runs `fetchWorkoutHistory()` on every
`.cloudKitDataDidChange` notification. A CloudKit import landing just after tab entry
re-fires the whole cascade.

---

## 3. Measured baseline

Instruments Run 1, ~25 s trace. Template: SwiftUI + Time Profiler + Hangs + Hitches.
Profiled via Cmd-I, so this is a **Release** build — the figures reflect shipping
configuration, not a debug artifact.

| Metric | Value |
|---|---|
| Marked hang | **630.57 ms**, single event at ~00:08.810 |
| Long Updates, count | **336** |
| Long Updates, total duration | **1.89 s** |
| Long Updates, avg | 5.62 ms |
| Long Updates, **max single body update** | **107.51 ms** |

Reading of the trace:

- **Confirmed busy, not blocked.** The Time Profiler CPU lane spikes to its trace maximum
  precisely across the hang marker.
- **630 ms measured vs. 1–2 s perceived — both correct.** The Hangs instrument marks only
  the contiguous interval where the run loop stops servicing events. Immediately after
  it, the Long View Body Updates and Hitches lanes stay dense from ~00:09 to ~00:22; in
  that band touches *are* delivered but frames cost 20–100 ms each. Hang + hitch tail is
  the full perceived stall.
- **107.51 ms for one body update is the eager-`VStack` signature** — ~6 dropped frames at
  60 Hz from a single `body` call. No per-card increment explains that; building the whole
  hierarchy at once does.
- **336 long updates is a re-render *count* problem**, separate from per-render cost.
  Independent evidence for Phase 2 and 3.2.
- **Unconfirmed:** the App Lifecycle lane breaks at ~00:07.6 with a second
  "Foreground – Active" band at ~00:08.8, and the hang sits on that transition. If that
  was a background → foreground round trip, `HistoryView`'s `onChange(of: scenePhase)` →
  `reconcileWatchWorkouts()` is a fourth trigger worth checking.

---

## 4. Fix, in three phases

### Phase 1 — stop doing O(history) work before the first frame

**1.1 `LazyVStack` for both lists.** `TrainingsTabView.swift:195` and `:233`, plus
`FortschrittTabView.swift:145`. Apple: "A VStack renders all its subviews
simultaneously, even if they are offscreen"; lazy stacks "load and render subviews
on-demand" ([Creating performant scrollable stacks](https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks)).
Use a plain `LazyVStack` — **no** `Section`/`pinnedViews`, so month dividers keep their
current inline look and nothing changes visually.

> **Do not convert the screen to a `List` as part of this fix.** A single `List` is the
> deployable native route to swipe actions on iOS 18–26, but it would require turning the
> header, banners, coach cards, calendar, dividers and cards into list rows. That is a separate
> layout redesign, not a prerequisite for a performant lazy stack
> ([Picking container views](https://developer.apple.com/documentation/swiftui/picking-container-views-for-your-content)).

**1.2 Prefetch the relationship graph.** In
`SwiftDataWorkoutSessionRepository.fetchAll()`:

```swift
descriptor.relationshipKeyPathsForPrefetching = [\.workoutExercises]
```

Apple: prefetching "enables SwiftData to obtain any related models in a single fetch,
instead of incurring subsequent access to the persistent storage as you access each
related model"
([doc](https://developer.apple.com/documentation/swiftdata/fetchdescriptor/relationshipkeypathsforprefetching)).
Measure whether adding `\.workoutExercises.sets` helps further or merely inflates the
fetch — `totalVolume` needs the sets, so it probably helps.

**1.3 Kill the per-item `DateFormatter` allocations.** WWDC23 "Demystify SwiftUI
performance" calls out formatters allocated per body evaluation as a thing to hoist.

| Location | Fix |
|---|---|
| `WorkoutCardView.swift:124-140` (2 per card, per render) | `static let` |
| `HistoryStatsService.swift:216` `weekKey` (1 per session + 1 per streak iteration) | **Delete it** — use the `Date` from `weekInterval(containing:).start` as the `Set`/dictionary key. No string, no formatter. |
| `HistoryStatsService.swift:224` `weekdayLabel` (7×), `:234` `monthLabel` | `static let` |
| `FortschrittExerciseRowView.swift:76-81` (`RelativeDateTimeFormatter` per row) | `static let` |
| `HistoryCalendarView.swift:101,136,353` | `static let` |

### Phase 1 — as implemented (2026-07-26)

All three items landed. Diff: `TrainingsTabView`, `FortschrittTabView`, `WorkoutCardView`,
`FortschrittExerciseRowView`, `HistoryCalendarView` (Presentation), `HistoryStatsService`
(Domain), `SwiftDataWorkoutSessionRepository` (Data). No new types, no new files, no
dependency wiring, no visual change.

Two deviations from the plan as written:

- **Four `LazyVStack` conversions, not three.** 1.1 named `FortschrittTabView.swift:145`
  (the muscle-group stack) but not the inner per-row stack below it. Converting only the
  outer one would have left every row of every *visible* group — each with its own
  `MiniSparkline` `Canvas` — built eagerly, which is the cost §2.7 actually describes. The
  inner stack was converted too, matching the outer+inner pair done in `TrainingsTabView`.
- **Only the first relationship hop is prefetched.** 1.2 suggested measuring whether
  `\.workoutExercises.sets` helps further. It cannot be expressed: `workoutExercises` is a
  to-many `[WorkoutExercise]?`, and Swift key paths do not traverse collections, so
  `relationshipKeyPathsForPrefetching` can only name `[\.workoutExercises]`. The
  `sets` hop still faults per exercise. If SQL logging still shows N+1 on sets, the
  remedy is the Phase 2 single-pass `WorkoutCardModel` build (2.2) or Phase 3.1, not a
  richer descriptor.

**The `Date` week key needs an explicit `startOfDay` — root cause worth not rediscovering.**
1.3 replaced the `"yyyy-MM-dd"` String week key in `streakWeeks` with the `Date` from
`weekInterval(containing:).start`, which is correct *except* in time zones that shift the
clock **at midnight**. `weekInterval` does `startOfDay(for:)` and then subtracts days, so on
a day whose midnight does not exist (America/Havana 2026-03-08, America/Santiago 2026-08-31)
it returns the week's Monday at 01:00, while every other weekday of that same week returns
00:00. One calendar week then produces two distinct `Date` keys, the `Set` lookup misses, and
the streak breaks a week early — once a year, for those users only. The String key collapsed
that hour implicitly. `HistoryStatsService.weekStartKey(for:calendar:)` restores it with a
second `startOfDay`, no formatter involved. Europe/Berlin (02:00 transitions) never showed
the fault, which is exactly why it needs a test rather than a manual check.

Covered by `GymStreakTests/HistoryStatsServiceStreakTests.swift`: two tests pin the
midnight-DST week (both directions — workout on the transition day, and reference date on it),
verified to fail with `streak → 0` when the `startOfDay` normalisation is removed; two more
pin ordinary streak accumulation across a 02:00 DST change and the unfinished-session case.

One incidental signature change: `HistoryStatsService.weekdayLabel(for:calendar:)` lost its
`calendar` parameter — the hoisted static formatter carries the calendar, so the argument
had no remaining use. Both `HistoryStatsService` static formatters and the three in
`HistoryCalendarView` are configured with `isoGermanCalendar()`, preserving the
Monday-first, `Locale.current` behaviour of the per-call formatters they replaced.

Known consequence of hoisting: `locale` is frozen at first use, because every one of them
sets `Locale.current` explicitly and `setLocalizedDateFormatFromTemplate` bakes the pattern at
configuration time (`HistoryCalendarView.veryShortWeekdaySymbols` freezes the resolved symbol
array outright). A *language* change relaunches the app, so that path is safe; a **region**
change or the 24-hour toggle does not, so labels can keep the previous region's formatting
until the process restarts. Low impact, accepted; the exact fix would be `Date.FormatStyle`
(a value type, no allocation problem, reads the locale per call). The **time zone is not**
frozen: `DateFormatter.timeZone` is independent of an assigned `calendar`, and a formatter
that never sets it re-resolves the system zone on each use — verified empirically — so a
resident app that crosses time zones still formats correctly.

The seven view-level statics (`WorkoutCardView` ×2, `HistoryCalendarView` ×3,
`FortschrittExerciseRowView` ×1, `TrainingsTabView` ×1) are annotated `@MainActor`. **This is
redundant, not required** — verified against the iOS 26.5 SDK: a `static let` inside a type
conforming to SwiftUI's `View` is *already* MainActor-isolated by global-actor inference, the
unannotated form type-checks clean under `-swift-version 6`, and an off-main read is diagnosed
either way (warning under Swift 5, error under Swift 6). The annotation is kept as explicit
documentation — a shared mutable formatter is only sound while every access comes from a view
body, and `RelativeDateTimeFormatter` carries no documented thread-safety guarantee at all —
and so the isolation stays correct if one of these types is ever extracted out of `View`.

**Do not read this as a migration debt sweep.** The unannotated static formatters elsewhere in
the app (e.g. `Components/PendingSyncBannerView.swift`) are not latent Swift 6 breakage for the
same reason, and annotating them buys nothing. If a project-wide guarantee is ever wanted, the
lever is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app target — currently set on the
**watch** target only. The two `HistoryStatsService` statics need no annotation either: that
type is already `@MainActor`.

Three further rendering-rule violations found by the `architecture-reviewer` pass were fixed
in the same change: `TrainingsTabView.lastMonthLabel` still allocated a `DateFormatter` in a
property `body` reads (a 1.3 site the table above simply never listed); the month `ForEach`
used index identity, so a new month re-identified every later group and made the now-lazy
stack rebuild realised rows (`MonthSectionInfo` is now `Identifiable` on `"year-month"`); and
`FortschrittTabView.navigationValue` rebuilt the entire `allExercisesForNavigation` array for
every row's link value — harmless while the stack was eager and everything was built in one
burst, but laziness relocates that O(rows × exercises) cost **into the scroll path**, working
against the "hitches during scroll" target. It is now built once per render and passed in.

#### Known-open after Phase 1 (deliberately not fixed here)

- **`weekInterval` itself still returns an un-normalised start**, and `weekStats` /
  `weekDayStatuses` use it for `DateInterval.contains` rather than as a key. Same
  midnight-DST-zone window as the streak bug above: verified in America/Havana for the week of
  2026-03-08, the current week is `[Mon 01:00, next Mon 01:00)` while the previous week ends
  `Mon 00:00`, so a session on Monday 2026-03-02 at 00:30 falls into **neither** week (no
  volume, no count, no day dot). Pre-existing, unrelated to performance, and in a different
  code path from the streak key, so it is not folded into Phase 1. The consistent fix is one
  line — `startOfDay` the `start` in `weekInterval` (`HistoryStatsService.swift:213`), after
  which `weekStartKey` becomes a thin wrapper and the streak tests stay green — but it changes
  week-filtering semantics for `weekStats`/`weekDayStatuses`, which have no test coverage, so
  it wants its own change plus tests.
- **`HistoryCalendarView.swift` is over the 300-line convention** (359 lines before this
  change, ~380 after). Extracting the formatters or `DayCell` + `buildCells()` into
  `Components/` is the obvious split; deferred rather than bundled into a performance change.
- **Nested lazy stacks carry an estimated-height caveat.** The nesting itself realises rows
  lazily, but nested estimates make scroll-indicator jumpiness and scroll-position drift more likely, and
  `Section`/`pinnedViews` — Apple's recommended shape for grouped lazy content — was
  deliberately rejected here. Worth eyeballing during the §5 verification run.

### Phase 2 — as implemented (2026-07-26)

The screen now renders a precomputed `HistorySnapshot` and derives nothing. New files:
`Domain/Models/HistorySnapshot.swift` (`HistorySnapshot`, `HistoryListRow`, `MonthSectionModel`,
`WorkoutCardModel`), `Domain/Services/HistorySnapshotBuilder.swift`,
`Presentation/ViewModels/HistoryViewModel.swift`.

**What was actually costing the time**, measured against the code rather than assumed:

- **Four traversals per card, not three.** `completionPercentage` (`Models.swift`) internally
  called *both* `totalSetsCount` and `completedSetsCount`, so `WorkoutCardView`'s three property
  reads walked the set graph four times. Now `WorkoutSession.aggregates` returns set counts and
  volume from **one** traversal, and `totalVolume`/`completionPercentage` delegate to it — the
  volume formula exists in exactly one place. Pinned by `HistorySnapshotBuilderTests`.
- **3.5 whole-history walks per render**, from `groupByMonth`, `weekStats`, `lastMonthStats` and
  `plannedWeek` — the last of which was a computed property *read twice* per render, each read
  faulting `session.routine?.id` for every routine × session. `HistorySnapshotBuilder` visits
  each session exactly once and accumulates every aggregate from that visit.
- **`refresh()` fired up to three times per appearance** (`onAppear` + `onChange(history.count)`
  + `onChange(exerciseLibrarySignature)`), each running two full aggregations. Now two
  `.task(id:)`s, which also cancel superseded rebuilds. The token's library component is a count
  plus a combined hash instead of ~96 interpolated strings rebuilt and compared on every render.
  (`Hasher` is seeded per process, so that value must never be persisted or compared across
  launches.)

  **The token keys on `WorkoutViewModel.historyVersion`, never on `workoutHistory.count`.** A
  count-keyed token cannot see the mutations that matter: `EditWorkoutSessionView` rewrites an
  existing session's sets, finishing a workout sets `endTime` on an already-counted session, and a
  CloudKit import can modify rather than add — none change the count, so the cards kept rendering
  pre-edit sets, volume and completion values, and the week/streak/month/calendar figures with
  them. Before Phase 2 the cards read the `@Model` directly, so SwiftData observation hid this;
  precomputing made staleness possible for the first time. `historyVersion` increments inside
  `fetchWorkoutHistory()`, which every mutation path already funnels through, closing the whole
  class of bug at one point. Pinned by `WorkoutViewModelTests`.

  **Section is a separate token.** Folding it into the data token made the segmented toggle re-run
  `computePRs` plus the entire snapshot build, neither of which depends on which tab is visible —
  which would have left the Fortschritt→Trainings stall (one of the two reported symptoms) only
  half fixed. `.task(id: dataToken)` rebuilds the snapshot; `.task(id: fortschrittToken)` rebuilds
  Fortschritt and returns immediately unless that tab is showing.
- **`FortschrittAggregator.build` ran while Trainings was visible** — a whole extra graph walk
  for an offscreen tab. Now gated on the visible section.

**Rows no longer touch SwiftData at all.** `WorkoutCardView` takes a `WorkoutCardModel` and is
`Equatable`; `HistoryCalendarView` takes `[Date: WorkoutCardModel]` and no longer rebuilds a
session dictionary twice per render or reads `@Model` per cell.

**Per-day data cannot answer per-session questions.** `cardsByDay` holds one card per day, so the
calendar's month header and legend must *not* be derived from it: on a two-workout day that
undercounts the sessions, drops the earlier workout's volume from the month total outright, and can
drop a workout type from the legend — and it made the same month report different numbers in
calendar mode than the list's own divider did. The snapshot therefore carries `monthTotals` and
`typesByMonth` (per **session**, keyed by `MonthSectionModel.id(year:month:)`, which is the single
definition of that key format), accumulated in the same pass. Note the calendar cannot read the
totals out of `rows` either — the newest month deliberately has no divider row. Pinned by three
tests, including one asserting every divider agrees with `monthTotals`. Delete and push callbacks carry
a `UUID`, resolved against the repository in `HistoryView`, so the list holds no `@Model` object.

**The nested lazy stacks from Phase 1 are gone — in both tabs.** `HistoryListRow` pre-interleaves
month dividers with cards and `FortschrittTabView.GroupedRow` does the same for muscle-group
headers, so each list is **one** flat `LazyVStack`. Nesting a `LazyVStack` inside a `LazyVStack` is
an undocumented shape with corroborated reports of scroll stutter and at least one reproducible
hang ([stutter](https://developer.apple.com/forums/thread/685461),
[hang](https://developer.apple.com/forums/thread/814208)); flattening avoids the question and also
removes the index-identity problem, since rows now carry stable string ids. Because the flat stacks
have no `spacing:`, cards carry their own 8pt bottom padding — which is why the month divider's top
padding is 10pt, not the original 18pt (18 + 8 would have widened the gap above every divider).

An intermediate attempt lazily mounted the custom row's delete-button subtree only after its
first swipe. The device issue persisted, and the later commit-level A/B proved the wrapper itself
was the scaling boundary. That optimization was discarded with the entire container. Separately,
`DayCell.id` and `WeekDayStatus.id` were fresh `UUID()`s per build, so the calendar grid and
weekday strip were replaced rather than updated on every render; both now key on their date.

**The empty state is gated on `hasLoaded`.** `.task` cannot run before the first body evaluation, so
the screen renders `HistorySnapshot.empty` for one frame — which without the gate flashed "no
workouts yet" and a zeroed WeekHero at a user who has hundreds.

**The builder normalises its own input** (drops unfinished sessions, sorts newest-first) rather than
trusting the caller, because month ordering, in-month card ordering and every count silently depend
on both. `PersonalRecordService` already set that precedent.

**Dead code removed:** `HistoryStatsService.groupByMonth` and `.monthStats`, both of which walked
every session's `totalVolume` and were called from inside `body`.

#### Still open after Phase 2

- **`.tabBarMinimizeBehavior(.onScrollDown)` was not the root cause.** It remains enabled.
  Removing only the custom row wrapper restored the post-release commit to the 1.1.5 scroll
  measurement without changing tab-bar behavior.
- **`TabView` + `.tabItem`** constructs all three tab views at launch. Whether it also evaluates
  their bodies (which would run the History aggregation before the tab is ever opened) is
  **unverified** — check with a signpost in `TrainingsTabView.body` while launching onto Routines.
- **`HistoryView` still holds `@ObservedObject var viewModel: WorkoutViewModel`**, so any of its
  15 `@Published` properties invalidates the screen. Confirmed *not* the cause here: there are two
  `WorkoutViewModel` instances, and `startTimer()` only runs via the active-workout path, so the
  History instance never ticks. Migrating it to `@Observable` remains correct cleanup, not a fix.
- `HistoryCalendarView` is still over the 300-line convention.

#### API findings (researched, do not re-derive)

- **`relationshipKeyPathsForPrefetching` cannot express a nested to-many hop.** Key paths do not
  traverse collections, so `\.workoutExercises.sets` is impossible. The way around it is to fetch
  the child entity directly — `FetchDescriptor<WorkoutExercise>` with
  `relationshipKeyPathsForPrefetching = [\.sets, \.workoutSession]`, both single-hop — and group
  in memory. Worth doing if the entry cost is still visible.
- **SwiftData cannot push aggregates into SQLite.** `fetchCount` and `#Expression` count
  subqueries exist; sum/average/group-by over a to-many do not (`.map` in a predicate is a
  compile error). So there is no query that avoids materialising the sets.
- **Native swipe API availability.** On iOS 15–26, `.swipeActions` is supported for rows in
  `List`; Apple provides no row-recycling contract that makes `List` inherently faster than a
  `LazyVStack`. iOS 27/Xcode 27 adds `swipeActionsContainer()` for swipe actions on arbitrary
  views. It is absent from the installed Xcode 26.5 SDK and cannot serve the app's iOS 18.5
  deployment range. The shipping design therefore uses native links plus context-menu/detail
  deletion rather than another custom gesture.
- **`@ModelActor` is still current** (no successor at WWDC24/25; Xcode 26 fixed a view-update bug
  under it). `PersistentModel` is not `Sendable`; `PersistentIdentifier` is.

### Phase 2 — the original plan

WWDC23: `body` must be "as cheap as possible", with string interpolation, filtering and
heap allocation moved to a cached model layer.

**2.1 One cached snapshot.** Compute `weekStats`, `weekDayStatuses`, `groupByMonth`,
`plannedWeek` and `lastMonthStats` **once** in `HistoryView.refresh()`, store in
`@State`, and pass plain value structs into `TrainingsTabView`. The services stay pure
and untouched — only the call site moves.

**2.2 Precompute the card rows.** Give `WorkoutCardView` a `WorkoutCardModel` value
struct (date parts, duration, set count, volume, completion %, PR count) built during
`refresh()`. This removes three relationship traversals per card, and note that
`groupByMonth` and `weekStats` *also* each recompute `totalVolume` for the same
sessions — one pass replaces all of it. The card stops touching SwiftData, becomes
`Equatable`, and diffs cheaply. `onDeleteRequested`/`onSelectWorkout` switch to `UUID`,
resolved in `HistoryView`.

**2.3 Don't build the invisible tab.** Gate `FortschrittAggregator.build` on
`section == .fortschritt`.

**2.4 Replace `exerciseLibrarySignature`** (`HistoryView.swift:53`) with a cheap change
token — count plus a combined hash — or fold the check into the aggregation.

**2.5 Collapse the three refresh triggers.** `onAppear` + `onChange(count)` +
`onChange(signature)` can fire `refresh()` three times per appearance. Use a single
`.task(id:)`. Caveat: `.task` "begins execution synchronously until it hits its first
suspension point", so this is a de-duplication and cancellation win — **not** a
threading win. That needs Phase 3.

### Phase 3 — as implemented (2026-07-26)

`SwiftDataHistorySnapshotStore` is a Data-layer `@ModelActor` backed by the shared
`ModelContainer`. It owns its own `ModelContext`, directly fetches `WorkoutExercise` with
`sets` and `workoutSession` prefetched, fetches completed sessions and routines, performs
PR/Trainings/Fortschritt aggregation on its serial model executor, then returns immutable
`Sendable` values through `HistorySnapshotProviding`.

The boundary is deliberately value-only:

- `PersistentModel` objects never cross the actor boundary.
- `HistoryViewModel` is `@Observable @MainActor`; it only publishes completed values and
  loading/error state.
- Trainings and Fortschritt have separate async requests, so switching sections never
  rebuilds the hidden section.
- cancellation checks occur between synchronous SwiftData/aggregation phases; generation
  checks prevent an older request from publishing after a newer invalidation.
- detail/delete resolves exactly one main-context `WorkoutSession` by UUID.
- routine/exercise mutations post one explicit invalidation after a successful save, while
  workout/CloudKit events continue through their existing notifications. This replaces
  `@Query` library hashing and broad whole-history observation.
- the Fortschritt search/group projection is cached by `FortschrittListViewModel` whenever its
  immutable exercise input, search text or selected group changes; SwiftUI `body` only reads the
  prebuilt group statistics and flat rows.
- the rebuild token includes the current calendar day. History updates it on foreground and at
  the next local day boundary so week/calendar/month prompt values cannot remain stale overnight.
- `OSSignposter` intervals cover fetches and each aggregation phase, with publish/selection
  events for correlation in Instruments.

**Construction is part of the concurrency contract.** The first implementation instantiated the
`@ModelActor` directly inside MainActor-isolated `AppDependencies`. A 240-session integration
test then measured a 713 ms MainActor heartbeat delay and confirmed the model actor itself was
running on the main thread in the installed SDK. Apple does not document construction-site
affinity as a `@ModelActor` guarantee, so that causal link is recorded as measured behavior, not
general API law. `SwiftDataHistorySnapshotProvider` now acts as the Data-layer front door: it is
safe to create in `AppDependencies`, while a user-initiated `Task.detached` constructs only the
stable model actor outside inherited MainActor isolation. Fetches remain structured actor calls
with cooperative cancellation. The same test now passes. Do not replace that provider with direct
`SwiftDataHistorySnapshotStore(...)` construction in the composition root, and do not move model
processing into the detached construction task.

The model actor requires iOS 17; the app's deployment target is newer, so no fallback exists.
No SwiftData schema or CloudKit migration is involved. `FortschrittExerciseModel` moved from
Presentation to `Domain/Models` so Domain no longer returns a Presentation-owned type.

Official API basis:
[`@ModelActor`](https://developer.apple.com/documentation/swiftdata/modelactor%28%29),
[`ModelActor`](https://developer.apple.com/documentation/swiftdata/modelactor),
[`PersistentIdentifier`](https://developer.apple.com/documentation/swiftdata/persistentidentifier),
[`relationshipKeyPathsForPrefetching`](https://developer.apple.com/documentation/swiftdata/fetchdescriptor/relationshipkeypathsforprefetching),
[`OSSignposter`](https://developer.apple.com/documentation/os/ossignposter).

---

## 5. Verification

Re-record the **same interaction script** each time: cold launch → open Verlauf → scroll
Trainings to the bottom → switch to Fortschritt → switch back to Trainings.

### Acceptance targets

| Metric | Baseline | After Phase 1 | After Phase 2 |
|---|---|---|---|
| Marked hangs | 1 × 630.57 ms | none > 250 ms | **zero** |
| Max single body update | 107.51 ms | < 30 ms | **< 16 ms** (one 60 Hz frame) |
| Long Updates, count | 336 | < 150 | **< 50** |
| Long Updates, total | 1.89 s | < 0.6 s | **< 0.2 s** |
| Hitches during Trainings scroll | dense, ~00:09–00:22 | sparse | **none** |

Max-single-update tracks Phase 1 (laziness); count and total track Phase 2 (caching and
fewer invalidations). If Phase 2 lands and the count is still high, that isolates the
cause to 3.2 rather than the aggregation path.

The automated UI fixture launches with 60 completed sessions. A common-mode 20 ms timer inside
the app records delayed main-run-loop service, so the assertion measures the user's actual
"touches are not dispatched" condition rather than XCUI's tap duration. The test covers opening
History, switching Fortschritt → Trainings and fast scrolling. Thresholds are 400 ms, 250 ms and
150 ms respectively; the custom wrapper's 298 ms fast-scroll result makes the scroll assertion
red, while the native-link row measured 41–45 ms and passed five repeated runs.

The test is a regression gate, not a substitute for the Release/Instruments run above.

Final automated verification on 2026-07-26:

- History responsiveness: 5/5 repeated 60-session runs passed.
- Workout deletion/navigation UI: 4/4 tests passed.
- Unit tests: 308 passed, 0 failed, 0 skipped.
- Actual `GymStreak` iOS scheme: `BUILD SUCCEEDED`.
- Architecture review: `PASS WITH WARNINGS`; the sole warning is the documented broad legacy
  `WorkoutViewModel` observation. This History-owned instance never starts workout timers, so
  narrowing that dependency remains deferred cleanup rather than part of this regression fix.

### Instruments click paths (Xcode 26)

Per-view attribution — pure disclosure-triangle expansion, there is no grouping selector:

1. Select the **Long View Body Updates** subtrack in the SwiftUI track lane.
2. In the detail pane, expand `GymStreak (<pid>)` → **module** rows.
3. Expand the module row → individual **View Name** rows.

Cause & Effect Graph — per *view*, not per update, and reached from the table row, **not**
from the `Summary: Long Updates` popup:

4. Hover a View Name row; an **arrow** appears next to the name.
5. Click the arrow → context menu with **"Show Updates"** and
   **"Show Cause & Effect Graph"**.
6. Choose **Show Cause & Effect Graph** to see what triggered that view's updates.

Time Profiler scoped to a hang:

7. Control-click the hang interval in the Hangs track → **"Set Inspection Range"** (from
   a long-update row the equivalent is **"Set Inspection Range and Zoom"**). This scopes
   every detail pane below.
8. Click the **Time Profiler** track, then the **Call Tree** button in the detail pane's
   bottom toolbar; enable **Invert Call Tree** and the hide-system-libraries option.
9. Expect `DateFormatter` initialization and SwiftData fault handling near the top. If
   they are absent, the phase ordering above is wrong and must be revisited before coding.

Sources: [WWDC25 session 306](https://developer.apple.com/videos/play/wwdc2025/306/),
[Instruments: Identifying a Hang](https://developer.apple.com/tutorials/instruments/identifying-a-hang/index),
[Analyzing CPU profiles with call tree views](https://developer.apple.com/documentation/xcode/analyzing-cpu-profiles-with-call-tree-views).

**Unverified — do not assume:** whether view-name symbolication needs a particular build
setting (Apple's material is silent); whether the SwiftUI instrument supports the
Simulator (the session implies a device but never rules it out); the instrument's own
profiling overhead (undocumented). Because of the last, treat absolute milliseconds as
indicative and judge the fix on **relative before/after deltas**.

### Supporting checks

- `-com.apple.CoreData.SQLDebug 1` as a launch argument to observe the N+1 fault pattern
  before 1.2 and its disappearance after.
- `Self._printChanges()` in `HistoryView.body` / `TrainingsTabView.body` to confirm how
  many times each state change re-evaluates the body, and which dominates.

---

## 6. Scope and process notes

- `PersonalRecordServiceTests` was the only existing test over these services;
  `HistoryStatsServiceStreakTests` (added with Phase 1) now covers `streakWeeks`. Phase 2
  changes call sites, not service semantics, so both must stay green.
- Phases 1–2 touch `Presentation/` plus one line in `Data/Repositories/`. New value types
  (`WorkoutCardModel`, the snapshot struct) belong in `Presentation/` — they are display
  models, not domain models, consistent with the "DTOs only at real external boundaries"
  decision in `docs/architecture.md`.
- **`architecture-reviewer` pass is required** (new types, multi-layer diff). CRITICAL
  findings must be fixed and the reviewer re-run until PASS.
- App must still compile before the work is reported as done.
- `docs/history-redesign.md` needs updating with the caching/laziness architecture once
  implemented, and this file's status header updated with actual measured results.
- This is a user-facing improvement → append a bullet to **both**
  `TestFlight/WhatToTest.en-US.txt` and `TestFlight/WhatToTest.de-DE.txt`.

### Rejected approaches (do not re-try)

- **Converting the history screen to a `List`** — deferred, not rejected forever. It is the only
  native route to swipe actions on iOS 18–26, but it restructures the hero, segmented control,
  banners, calendar, dividers and both History modes and therefore carries a large visual-
  regression surface. `swipeActionsContainer()` becomes the smaller native option once iOS 27
  is the minimum deployment target. "`List` recycles rows" is not a supporting argument; Apple
  documents no such contract.
- **Another custom horizontal row gesture** — explicitly rejected. The exact post-1.1.5 A/B
  proved the gesture/focus/accessibility wrapper caused the release-critical scroll stall.
- **`LazyVStack(pinnedViews:)` with `Section`** for the month dividers — would change the
  established visual design; the dividers are deliberately inline.
- **Starting with the `@ModelActor` rewrite (3.1)** — a large architectural change whose
  necessity is unproven until Phases 1–2 are measured.
