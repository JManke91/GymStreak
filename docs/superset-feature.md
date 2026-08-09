# Superset Feature

> **Note (2026-07):** The Routines tab was visually redesigned (see [routines-exercises-redesign.md](./routines-exercises-redesign.md)). Superset logic (link buttons, edit mode, context menu, group colors/badges) is unchanged; each exercise is now a rounded card and `ExerciseHeaderView` moved to `RoutineDetailComponents.swift`. The superset-edit toolbar renders via `safeAreaInset` on the redesigned detail screen.

## Overview

Supersets allow users to group 2+ exercises together so they alternate sets during a workout. Instead of completing all sets of exercise A before moving to B, supersets interleave them: A1 → B1 → A2 → B2 → A3 → B3. Rest timers only trigger after completing a full round (all exercises at the same set level).

This feature is fully implemented on both iOS and watchOS with bidirectional data sync.

---

## Data Model

### Core Fields

Two fields on `RoutineExercise` power the entire feature:

| Field | Type | Description |
|-------|------|-------------|
| `supersetId` | `UUID?` | Shared UUID grouping exercises together. `nil` = standalone exercise |
| `supersetOrder` | `Int` | Position within the superset (0-indexed) |

These fields are mirrored on:
- **`WorkoutExercise`** - Denormalized copy for workout history (preserves structure even if routine changes later)
- **`WatchExercise`** (Codable) - For iOS → Watch sync
- **`ActiveWorkoutExercise`** - Watch app's in-memory workout state
- **`CompletedWatchExercise`** - For Watch → iOS sync after workout completion

All fields use iCloud-compatible defaults (`nil`, `0`) requiring no schema migrations.

### Contiguity invariant (2026-08)

**A superset's members always occupy an uninterrupted run of `order` slots in the routine.** The block sits at the position of its earliest member, the exercises it passed over shift down, and every non-member keeps its relative order. Creating a superset from exercises 1 and 5 therefore yields positions 1 and 2.

Within a block, member sequence follows routine `order` as well — `supersetOrder` is a mirror of position, not an independent axis. Consequences:

- Adding an exercise that sits *earlier* than the group pulls the whole block up to that exercise's slot and makes it the group's first member.
- Sorting mode drags whole units, so a drag never produces a split routine in the first place — see "Sorting mode: supersets drag as one unit" below. `normalizeOrdering` still runs after the move as the data-layer safety net.

**Why:** superset creation used to stamp `supersetId`/`supersetOrder` without ever touching positions, so members could sit scattered across the routine with unrelated exercises in between. No connecting line can span that, and the workout's interleaved execution order no longer matched what the routine screen showed.

**Where it is enforced:** `GymStreak/Domain/Services/SupersetOrderingService.swift`

| Member | Purpose |
|--------|---------|
| `contiguousOrder(for:)` | Pure: returns the exercises in contiguous-superset sequence. Deterministic even when stored `order` values collide |
| `normalizeOrdering(in:)` | Renumbers `order` to `0..<count` in that sequence and each superset's `supersetOrder` to `0..<memberCount`; returns whether anything moved |
| `units(for:)` | Pure: the routine as draggable units — a standalone exercise, or a whole superset as one unit |
| `moveUnits(from:to:in:)` | Applies a unit-level `List.onMove` and renumbers; whole units move, so no drag can split a block |

`RoutinesViewModel` calls `normalizeOrdering` before `updateRoutine` in every edit that can disturb positions: `createSuperset`, `addExerciseToSuperset`, `removeExerciseFromSuperset`, `dissolveSuperset`, `moveRoutineExerciseUnits` (via `moveUnits`), `removeRoutineExercise`, `restoreRoutineExercise`. `applySupersetEdit` inherits it through those methods, so a multi-select edit that adds and removes members in one pass still lands contiguous. Because normalization runs inside the same `updateRoutine` call, the new order reaches the watch through the ordinary routine-sync path — no separate propagation.

**Legacy data** is repaired on display: `RoutineDetailView.onAppear` calls `viewModel.normalizeSupersetOrdering(in:)`, which persists only when something actually moved (`normalizeOrdering` returns `false` for an already-contiguous routine, so a normal visit does no save). The operation is idempotent.

**Not covered:** `WatchTemplateTransactionService+Structural` keeps its own local `normalizeOrder` (gap-closing only). It deliberately mirrors the watch's optimistic fold step for step so both platforms converge on identical `order` values; making only the iOS side gather blocks would break that convergence. A watch-originated structural edit that scatters a superset is repaired the next time the routine detail is opened.

**Manual verification (iOS, 2026-08-09 — all passed).** Automated coverage is `SupersetOrderingServiceTests`; these are the click paths that exercise the wiring the unit tests cannot reach. Repeat them after any change to the superset CRUD methods or to `RoutineDetailView.onAppear`:

| # | Path (Routinen → routine detail) | Expected |
|---|----------------------------------|----------|
| 1 | Long-press exercise 1 → "Superset erstellen mit…" → pick exercise 5 | Exercise 5 moves to slot 2, exercise 1 keeps slot 1, 2–4 shift down |
| 2 | Long-press a distant exercise → "Zu Superset A hinzufügen" | It moves into the block instead of staying in place |
| 3 | Three-dot → "Superset bearbeiten": tick a far exercise, untick a current member, Done | Result is one uninterrupted block (add + remove in one edit) |
| 4 | Open a routine whose *stored* data has a scattered superset, leave, reopen | Contiguous on first open and it stays that way (the repair persisted) |
| 5 | Context menu → "Aus Superset entfernen", then "Superset auflösen" | No gaps, no duplicate positions, nothing else jumps |
| 6 | With the paired watch running, open the routine there after an edit | Same order as iOS |

Case 4 needs a container from a build older than this change — any superset created afterwards is contiguous by construction, so it cannot reproduce scattered data.

### Sorting mode: supersets drag as one unit (2026-08)

The routine detail's "Sortieren" mode is a `List` + `.onMove`. It used to be a flat list of exercises with a plain move handler that had no notion of supersets, so a drag could scatter a group's members or wedge an unrelated exercise between them — the contiguity invariant above then silently pulled things back, which read as the drag fighting the user.

**The list's rows are now units, not exercises.** `SupersetOrderingService.units(for:)` returns the routine as a sequence of `OrderingUnit`s — a standalone exercise, or a whole superset. Because a superset is a *single* `List` row:

- dragging anywhere on it moves every member together, internal order intact;
- there is no drop target between two members, so a standalone exercise landing "inside" a group resolves to just above or just below the whole block. This is a structural property of the row set, not a rule applied afterwards;
- both supersets and standalone exercises still reach the very top and the very bottom, and two supersets reorder against each other normally.

`RoutineDetailView+Sorting.sortingModeContent` computes the units and the label map once per list (both walk the whole routine — never per row) and hands each unit to `sortingRow(for:labels:)`. `moveExerciseUnits` forwards the unit offsets to `RoutinesViewModel.moveRoutineExerciseUnits`, which calls `moveUnits` + `updateRoutine` — one save, and the watch gets the new order through the ordinary routine-sync path like every other routine edit.

**Visual grouping** (`GymStreak/Presentation/Views/Routines/RoutineSortingRows.swift`): a superset draws as one framed block in the group's letter colour — handle, link glyph, "Superset A" and the member count on top, the members stacked underneath behind a tinted rail. `RoutineSortingRow` (standalone) and the members inside the block share `SortingRowContent`, so both read identically. Rows take `RoutineExerciseCardDisplay` value structs; no `@Model` object reaches a row body. The sorting hint reads "… · Supersets move as one · …" so the block movement is announced as well as shown.

**Manual verification (physical iPhone, 2026-08-09 — all passed).** `SupersetOrderingServiceTests` covers the unit algebra (block move, drop resolving beside the block, top/bottom, two supersets, contiguity after a sequence of drags); these are the click paths for the wiring around it, which the unit tests cannot reach. Setup: a routine with at least six exercises, two linked as Superset A and two as Superset B. Routinen → routine detail → "Sortieren". Repeat after any change to the sorting row set or to `moveUnits`:

| # | Path | Expected |
|---|------|----------|
| 1 | Look at the list | Each superset renders as one framed block in its group colour (letter + member count, members stacked inside) |
| 2 | Long-press the superset block, drag it past two standalone exercises | The whole block moves, members keep their internal order |
| 3 | Drag a standalone exercise onto the middle of a superset block | It lands above or below the block, never inside it |
| 4 | Drag a superset to the very top, then to the very bottom | Both reachable; block stays intact |
| 5 | Swap the two supersets | Neither breaks |
| 6 | "Fertig", reopen the routine | The new order persisted |
| 7 | With the paired watch running, open the routine there | Same order as iOS |

The failure mode to watch for is an exercise appearing to land *inside* a block and then jumping out — that would mean the rendered row set had desynced from the `.onMove` offsets. It did not occur.

**Deliberately not implemented: drag-to-unlink.** Pulling one member out of a superset by dragging is not a gesture — it neither unlinks nor splits the group. Sorting mode is for ordering only. Unlinking stays an explicit action: the link/unlink affordance between cards, the context menu ("Aus Superset entfernen" / "Superset auflösen"), and the superset editor. Rationale: a drag out is ambiguous (reorder or unlink?) and destructive-by-accident, and every unlink path already has an undo-free but obvious counterpart. Restoring it would mean per-member drag sources inside the group row plus a drop-outside intent, which `List.onMove` cannot express — it would need the hand-rolled `.onDrag`/`.onDrop` reorder that was already abandoned here (see `docs/routines-exercises-redesign.md`).

**Removed with the contiguity work:** `RoutinesViewModel.reorderSuperset(_:in:)`. It set `supersetOrder` independently of routine position, which the invariant now derives — and it had no callers (restore from git history at 2026-08-09 if within-block ordering ever needs to diverge from routine order again).

### Computed Properties

| Property | On | Purpose |
|----------|-------|---------|
| `isInSuperset: Bool` | `RoutineExercise`, `WorkoutExercise`, `ActiveWorkoutExercise` | Returns `supersetId != nil` |
| `exercisesGroupedBySupersets: [[RoutineExercise]]` | `Routine` | Groups exercises by `supersetId`. Standalone = `[[ex]]`, Superset = `[[ex1, ex2, ex3]]` sorted by `supersetOrder` |
| `exercisesGroupedBySupersets: [[WorkoutExercise]]` | `WorkoutSession` | Same grouping logic for active workouts |

**Files:**
- `GymStreak/Models.swift` - SwiftData models, `Routine.exercisesGroupedBySupersets` (~line 32), `WorkoutSession.exercisesGroupedBySupersets` (~line 212)
- `GymStreak/WatchModels.swift` - iOS-side Codable watch models
- `GymStreakWatch Watch App/Models/WatchModels.swift` - Watch-side models

---

## CRUD Operations (iOS)

All superset management is in `RoutinesViewModel` (~lines 155-230):

| Operation | Method | Behavior |
|-----------|--------|----------|
| **Create** | `createSuperset(from:in:)` | Stamps one new shared `supersetId` on 2+ exercises |
| **Add** | `addExerciseToSuperset(_:supersetId:in:)` | Stamps the group's `supersetId` on one more exercise |
| **Remove** | `removeExerciseFromSuperset(_:in:)` | Clears the fields. Auto-dissolves if only 1 exercise remains |
| **Dissolve** | `dissolveSuperset(_:in:)` | Clears `supersetId`/`supersetOrder` on all exercises in the group |
| **Normalize** | `normalizeSupersetOrdering(in:)` | Repairs the contiguity invariant on legacy/watch-edited data; saves only if something moved |

**These methods only change membership.** Positions — `order` in the routine and `supersetOrder` within the group — are owned by `SupersetOrderingService.normalizeOrdering`, which each one runs before its single `updateRoutine`; see "Contiguity invariant" above. That is why none of them assign `supersetOrder` themselves any more.

**Auto-dissolution**: Removing an exercise from a 2-exercise superset automatically dissolves it (prevents single-exercise supersets).

**File:** `GymStreak/Presentation/ViewModels/RoutinesViewModel.swift`

---

## Workout Execution

### Interleaved Navigation Pattern

```
Standard exercise:    A1 → A2 → A3
Superset [A, B]:      A1 → B1 → [REST] → A2 → B2 → [REST] → A3 → B3
Superset [A, B, C]:   A1 → B1 → C1 → [REST] → A2 → B2 → C2 → [REST] → ...
```

Handles uneven set counts gracefully (e.g., A has 3 sets, B has 4 → round 4 only includes B).

### Key Navigation Functions

**iOS** (`GymStreak/WorkoutViewModel.swift` ~lines 792-958):

| Function | Purpose |
|----------|---------|
| `findNextIncompleteSet()` | Global navigation using `exercisesGroupedBySupersets`. For supersets, iterates by set level across all exercises |
| `findNextIncompleteSetForSuperset(after:in:)` | Implements the interleaving pattern within a superset group |
| `isEndOfSupersetRound(completedSet:in:)` | Returns `true` when ALL exercises at a set level are complete |
| `supersetRoundRestTime(for:in:)` | Gets rest time from **last exercise's** set at that level |

**watchOS** (`WatchWorkoutViewModel.swift` ~lines 460-718) - mirrors identical logic:

| Function | Purpose |
|----------|---------|
| `findNextIncompleteSet()` | Same interleaving logic |
| `findNextIncompleteSetInSuperset(afterSetIndex:inExerciseIndex:)` | Superset-specific navigation |
| `isEndOfSupersetRound(exerciseIndex:setIndex:)` | Round completion detection |
| `supersetRoundRestTime(exerciseIndex:setIndex:)` | Rest time for completed round |
| `advanceToNextSetAfterCompletion(fromExerciseIndex:setIndex:)` | Post-completion navigation |

### Rest Timer Behavior

| Scenario | When rest starts |
|----------|-----------------|
| **Standalone exercise** | After each set |
| **Superset** | Only after completing a full round (all exercises at same set level) |

Rest time is stored on the **last exercise's sets** in the superset. Rationale: rest comes after completing all exercises in the round.

### Set Completion Flow

1. Mark set complete
2. Check `exercise.isInSuperset`
3. **If superset**: Check `isEndOfSupersetRound()` → start rest timer only if round complete → navigate to next set via interleaving
4. **If standalone**: Start rest timer → navigate to next set sequentially

**iOS:** `GymStreak/WorkoutViewModel.swift` - `completeSet(workoutExercise:set:)` (~lines 470-526)
**Watch:** `GymStreakWatch Watch App/ViewModels/WatchWorkoutViewModel.swift` - `applyToggleSetCompletion()` (~lines 280-313)

---

## iOS UI Components

### Multiple Supersets Per Routine

The app supports **multiple independent supersets** within a single routine. Each superset is identified by a unique `supersetId` UUID and gets a computed letter label (A, B, C...) assigned at display time by `SupersetLabelProvider`.

### Superset Label Provider

**File:** `GymStreak/Helpers/SupersetLabelProvider.swift`

- `SupersetLabelProvider.labels(for:)` - Computes `[UUID: String]` mapping from supersetId to letter (A, B, C...) based on exercise order
- `SupersetLabelProvider.color(for:)` - Returns a unique color per letter: green (A), indigo (B), orange (C), blue (D), pink (E), cycling
- `SupersetGroupable` protocol - Shared by `RoutineExercise` and `WorkoutExercise` for generic label computation

Labels are computed at render time, not stored. If superset A is dissolved, B automatically becomes A.

### Superset Visual Indicators

| Component | File | Purpose |
|-----------|------|---------|
| `SupersetBadge` | `GymStreak/Presentation/Views/Components/SupersetBadge.swift` | Position/total badge (e.g., "1/2", "2/3") with per-group color |
| `SupersetGroupContainer` | `GymStreak/Presentation/Views/Routines/SupersetGroupContainer.swift` | Wraps one superset's member cards in the routine detail and draws the group's continuous connecting line — see "The continuous connecting line" below |
| `SupersetRestTimerConfig` | `GymStreak/Presentation/Views/Components/SupersetRestTimerConfig.swift` | Single rest timer config for entire superset. Shows only on first exercise |

### The continuous connecting line (2026-08)

A superset in the routine detail reads as one visually connected unit: a single unbroken line in the group's colour runs from the first member's anchor dot down to the last member's, **crossing the gaps between the exercise cards**, and stays connected while cards expand/collapse and while the list scrolls.

**Structure — this is a layout problem, not a geometry problem.** Every exercise card is a rounded, clipped view. A child of one card can never draw into a sibling card, so a per-card line fragment is necessarily clipped to that card: what the user saw was a short stub per exercise, not a connector. The fix is structural:

- `RoutineDetailView.supersetRowGroups(for:)` folds the ordered exercises into `RoutineExerciseGroup` rows — consecutive members of one superset collapse into a single group (they are contiguous by the invariant above, so this is one linear pass, no lookahead).
- `groupRow(_:styling:)` renders a superset group inside `SupersetGroupContainer`, which is **one row of the outer `LazyVStack`**. The member cards stack inside it.
- The connector lives in that container's overlay — a *sibling* of the clipped cards, spanning the whole group including the 8pt gaps between cards.

**Endpoints via anchor preferences.** Each member card's header publishes the centre of its 16pt indicator gutter through `SupersetMemberAnchorKey` (`View.supersetConnectorAnchor(id:isActive:)`, applied in `ExerciseHeaderView`; inert for standalone cards). `SupersetGroupContainer` resolves the first and last member's anchors via `overlayPreferenceValue` + a `GeometryReader`. Because anchor preferences flow through the normal animation pipeline, the expand/collapse spring carries the endpoints along with no extra plumbing. The same key carries a second, optional anchor per member — the seam below it — so one `overlayPreferenceValue` can place both the line and the unlink controls (preferences flow up from the content subtree, so a second nested `overlayPreferenceValue` would read nothing).

**Lazy-container caveat (important).** Anchors are resolved **only inside the group container's own subtree**, which is small and always fully materialised. Resolving them across the outer lazy container does not work: offscreen rows are never built, their preference entries silently fall back to the default, and the line snaps or disappears mid-scroll. The outer container stays lazy — only the members of one superset (2–4 cards) build eagerly together.

**The lane must be free through the WHOLE card, not just the header.** All cards — superset members and standalone alike — reserve `ExerciseHeaderView.connectorLaneWidth` (24pt = 16pt indicator + 8pt spacing) before the avatar, which is what keeps every avatar on one x position. Reserving it in the *header only* was not enough: the chip strip and the expanded body start at the card's leading edge, so on a real device the line ran straight through the "Pause" chip (reported 2026-08-09 after the first implementation). A member card therefore also applies `.padding(.leading, connectorLaneWidth)` to its chip strip, its inline parameter editor and its expanded body (`RoutineDetailView.normalExerciseCard`, `laneInset`). Side effect worth keeping: a member card's chips and set rows now align with its avatar column instead of the card edge. Standalone cards get an inset of 0 and are visually unchanged; card rounding, padding, width and spacing are untouched for both.

Anything new added below a card's header must respect the same inset, or it will collide with the connector.

**Accessibility.** The connector *line* is decorative: `.accessibilityHidden(true)` and `.allowsHitTesting(false)` — the two modifiers sit on the line alone, not on the whole overlay, so the unlink controls that ride on it stay tappable and announced. Superset position is already announced by each card's `SupersetBadge`, and taps still reach the card underneath.

### Link and unlink as a matched pair (2026-08)

Creating and breaking a superset are equally quick, and the two controls read as a pair.

| Control | Where | Symbol | Tap target |
|---------|-------|--------|-----------|
| Link (`SupersetLinkButton`) | Between two adjacent, unlinked cards | `link.badge.plus` + the label "Link superset" / „Verknüpfen“ | whole row, `minHeight: 44` |
| Unlink (`SupersetUnlinkButton`, private to `SupersetGroupContainer`) | On the connecting line, at every seam between two adjacent members | `scissors` in a 26pt ringed circle | 44pt `contentShape(Circle())` around the 26pt glyph |

Before this change the app had a one-tap way to *create* a superset and no equivalent way to undo it — unlinking was buried in the long-press context menu and the multi-select editor.

**Split-at-seam semantics** (`RoutinesViewModel.splitSuperset(after:in:)`): the members up to and including the tapped seam's upper neighbour keep the group; the members below it become a new group. A side left with a single exercise becomes standalone, so a two-member superset dissolves entirely — the same lone-survivor rule `removeExerciseFromSuperset` already applies, not a parallel one. Positions are then restored by `SupersetOrderingService.normalizeOrdering`, so both halves come out as contiguous blocks. Covered by four tests in `GymStreakTests/RoutinesViewModelTests.swift`. The view wraps the call in the standard spring and fires `HapticManager.shared.success()` — the same confirmation linking gives.

**Layout: the control needs reserved space, but cannot live in it.** The line is an *overlay* of the group container, so anything placed between the cards as ordinary content would be stroked straight across. The gap is therefore reserved by an empty `SupersetSeamSpacer` (28pt, `Color.clear`) interleaved between member cards, which publishes only its centre as the seam anchor; the button itself is drawn in the overlay *after* the line, at `x` of the connector and `y` of that seam. Its opaque circular fill is what makes the line read as passing behind it. Total gap between two member cards is 36pt (28 + the cards' 2×4pt padding), so the 44pt hit circle bleeds ~4pt into each card — over the empty connector lane, not over any card control.

**VoiceOver.** The unlink control's meaning is purely positional, which a screen-reader user cannot see, so it names both exercises: "Break superset between %1$@ and %2$@" / „Supersatz zwischen %1$@ und %2$@ trennen" (`superset.unlink_between`). `SupersetGroupContainer` takes `[Member]` (id + name) rather than bare ids for exactly this.

**SF Symbols — verified against the runtime, not from memory.** iOS 26.1 ships **no** `link.slash`, `link.badge.minus` or `link.badge.xmark`; `link`, `link.circle(.fill)`, `link.badge.plus` and `link.icloud(.fill)` are the entire `link.*` family. An unknown symbol name renders as an *empty* view, not a placeholder — the first implementation used `link.slash` and shipped visibly empty circles on the connector (caught on the simulator, 2026-08-09). Hence `scissors` for unlink. The same bug was latent in the superset context menu, whose "remove from superset" and "dissolve" items had been requesting `link.badge.minus`/`link.badge.xmark` (no icon rendered); they now use `scissors` and `xmark.circle`. Checking a symbol: `plutil -convert xml1 -o - "<runtime>/System/Library/PrivateFrameworks/SFSymbols.framework/CoreGlyphs.bundle/symbol_order.plist"`.

**Per-card work stays out of the render path.** `SupersetCardStyling` now also carries the group's shared `restTime` (the last member's, since rest triggers after a round). It is resolved once per group inside `supersetStyling(for:)`; previously each member card resolved it in its own body via `lastExerciseInSuperset`, which filters + sorts the whole routine. With all members of a group now building in one frame, that walk would have been paid n times per group per render. `lastExerciseInSuperset` survives as a **write-path** helper only (`updateSupersetRestTime`).

**Abandoned approach — the per-card indicator.** `SupersetLineIndicator` (a `.first`/`.middle`/`.last`/`.only` line fragment drawn inside each card header) and the never-adopted `SupersetGroupView`/`SupersetConnectingLine`/`SupersetExerciseContainer` set, plus `SupersetIndicatorBadge`, were **deleted** with this change. No amount of measurement could have joined the fragments — the clip boundary is the wall. `SupersetCardStyling.linePosition` went with them; the styling struct now exposes `isMember` instead. (`onGeometryChange` was considered as an alternative to preferences and rejected: it adds a state write and re-render cycle for a value nothing else consumes.)

The active workout screen solves the same problem the same way (`SupersetWorkoutGroupView`), with a static rail instead of anchored endpoints because its cards are uniform there.

### Routine Detail - Exercise Actions

**File:** `GymStreak/RoutineDetailView.swift`

#### Leading Chevron Expand/Collapse

Exercise rows use a manual expand/collapse pattern (not `DisclosureGroup`) with a leading chevron button. The header row and expanded content are **separate list rows**, which allows `List` to smoothly animate row insertion/removal. A custom `DisclosureGroupStyle` was avoided because `List` cannot animate cell height changes within a single row.

**Layout:**
```
[Chevron ▸ (button)] [24pt connector lane] [MuscleGroupBadge] [Name+Sets] [Spacer] [SupersetBadge] [Menu ⋯]
```

Key details:
- Chevron rotates 90° when expanded with spring animation
- 28pt chevron frame provides adequate tap target
- Expanded sets content renders as a separate list row for smooth animation
- `.buttonStyle(.plain)` allows the nested `Menu` in the label to intercept its own taps
- Expanded content is indented 28pt (`.padding(.leading, 28)`) to align past the chevron
- The `isExpanded` binding setter already contains `withAnimation`

#### Three-Dot Menu (Ellipsis)

Each exercise row in normal mode displays a `Menu` (ellipsis icon) in `ExerciseHeaderView` at the **trailing edge**, well separated (~300pt) from the leading chevron.

Menu options:
- **Superset** / **Edit Superset** — Opens superset create or edit mode (only shown when routine has 2+ exercises)
- **Alternatives** — Expands the card with the first alternative open, or opens the picker when there are none

> **Removed 2026-07-29:** the **Edit Sets** entry (and the whole set-edit mode below) is gone. In routines-redesign v2 the expanded card's set rows are always editable (`RoutineSetsEditor`), so "Edit Sets" only swapped that editor for a strictly weaker reorder-only list — it read as the UI getting stuck. Set **reordering** was removed with it (see the note under "Set Edit Mode").

#### Set Edit Mode — REMOVED (2026-07-29)

Set add/delete now live permanently in the expanded card's `RoutineSetsEditor` rows (redesign v2), so the separate mode was deleted along with `setEditExerciseId`, `enterSetEditMode`/`exitSetEditMode`, `setReorderContent`, `moveSetUp`/`moveSetDown` and `RoutinesViewModel.moveExerciseSets(from:to:for:)`.

**Deliberate omission — set reordering.** It had no home outside that mode and was not reinstated: with always-editable rows, changing which set comes first is equivalent to retyping two values, and a routine has ~3–5 sets per exercise. If it is ever wanted back, restore `moveExerciseSets` from git history at 2026-07-29 and drive it from up/down buttons on `RoutineSetStepperRow` — note that `.onMove` is not an option, it only works on a `ForEach` that is a direct child of `List`/`Section` and these rows are nested in a card.

#### Context Menu (Long Press)

Per-exercise context menu (supports multiple supersets):

For exercises **in a superset**:
- "Remove from Superset A" → `viewModel.removeExerciseFromSuperset()`
- "Dissolve Superset A" → `viewModel.dissolveSuperset()`

For **standalone exercises** (not in any superset):
- "Create Superset With..." submenu → lists other standalone exercises → `viewModel.createSuperset(from:in:)`
- "Add to Superset A" / "Add to Superset B" → `viewModel.addExerciseToSuperset(_:supersetId:in:)`

For **all exercises**:
- "Alternatives" → expands the card with the first alternative open (or opens the picker)

For **deleting**:
- "Delete Exercise" → removes immediately and offers an Undo toast (the confirmation alert was dropped in redesign v2)

**Visual styling:**
- Each superset group gets a unique color from `SupersetLabelProvider`
- Superset exercises: `groupColor.opacity(0.08)` background
- 24pt connector lane (16pt indicator + 8pt spacing, `ExerciseHeaderView.connectorLaneWidth`) kept free at every card's leading edge — it aligns all avatars, and on a member card the chip strip and expanded body indent past it too so the group's line has a clear channel through the whole card
- Badges show position/total: "1/2", "2/2" (user-friendly format)

### Active Workout - Superset Display

**File:** `GymStreak/ActiveWorkoutView.swift`

| Component | Purpose |
|-----------|---------|
| `SupersetWorkoutGroupView` | Groups superset exercises in a card with header "Superset A (3)", per-group colored connecting line, rest time indicator |
| `WorkoutExerciseCardView` / `WorkoutExerciseCollapsedRow` | Show `SupersetBadge` (e.g., "1/3") with per-group color when part of a superset. The card hides its own Pause chip for superset members (the group owns the round's rest). Only the exercise holding the next set is expanded — see `active-workout-redesign.md`. |

Workout labels are computed from `WorkoutSession.workoutExercisesList` using `SupersetLabelProvider.labels(for:)`.

### Rest Timer Config

- **Standalone**: Regular `RestTimerConfigView` per exercise
- **Superset**: `SupersetRestTimerConfig` shown only on **first exercise** in the group
  - Updates rest time on **last exercise's sets**
  - Includes explanation: "Rest starts after completing all exercises in each round"

**Helper functions in RoutineDetailView** (all of them in `RoutineDetailView+Supersets.swift`):
- `supersetStyling(for:)` - Resolves every card's colour, position/total **and the group's shared rest time** in one pass per list render
- `supersetRowGroups(for:)` - Folds the ordered exercises into standalone rows and superset groups
- `supersetLabels` / `supersetLetter(for:)` - `[UUID: String]` from `SupersetLabelProvider`, and the per-exercise accessor
- `lastExerciseInSuperset(for:)` - The member that owns the group's rest time. Walks the routine, so it is a **write-path helper only**
- `updateSupersetRestTime(for:restTime:)` - Updates all sets of that last exercise

---

## watchOS Implementation

### Routine Preview

**File:** `GymStreakWatch Watch App/Views/RoutineDetailView.swift`

- Groups exercises using `exerciseGroups` computed property (by `supersetId`)
- Superset display:
  - Header: "Superset (N)" with link icon
  - Tinted background: `tint.opacity(0.1)`
  - Border: `tint.opacity(0.3)`
  - Dividers between exercises in the same group
- `ExercisePreviewRow` shows superset position badge when `showSupersetBadge: true`

### Active Workout

**File:** `GymStreakWatch Watch App/Views/ActiveWorkoutView.swift`

- TabView with 3 tabs: Exercises, Metrics, Controls
- Set editor (`FullScreenSetEditorView`) displays current exercise name, supports superset switching via ViewModel
- Rest timer overlay (full-screen or minimized) — full-screen view (`RestTimerLargeView`) shows total elapsed workout time (top-right, secondary styling) alongside the rest countdown

**File:** `GymStreakWatch Watch App/Views/ExerciseListView.swift`

- `WatchSupersetBadge` (~lines 337-361): Link icon + position number
- Badge colors: `textOnTint` (black) on `tint` (green) background
- Row background: `Color.accentColor.opacity(0.1)` for superset exercises

**File:** `GymStreakWatch Watch App/Views/CompactActionBar.swift`

- Complete button triggers `toggleSetCompletion()`
- Navigation (prev/next) delegates to ViewModel's superset-aware logic
- Shows exercise name to indicate which superset exercise is active

### Design System

**File:** `GymStreakWatch Watch App/OnyxWatchDesignSystem.swift`

- `OnyxWatch.Colors.tint` - Green color for superset indicators
- `OnyxWatch.Colors.textOnTint` - Black text for contrast on tint backgrounds

---

## Data Sync (iOS ↔ watchOS)

### iOS → Watch

1. `Routine.toWatchRoutine()` converts SwiftData models to Codable `WatchRoutine`
2. Preserves `supersetId` and `supersetOrder` on each `WatchExercise`
3. Sent via `WatchConnectivityManager.updateApplicationContext()` (background) or `sendMessage()` (foreground)

### Watch → iOS

1. Watch completes workout, creates `CompletedWatchWorkout` with superset metadata on each `CompletedWatchExercise`
2. Sent via `transferUserInfo()` (guaranteed delivery)
3. iOS `WatchConnectivityManager` receives via `didReceiveUserInfo`, persists workout to UserDefaults, and processes it directly (creates `WorkoutSession`, optionally updates routine template)
4. Posts `.watchWorkoutProcessed` notification so `RoutinesViewModel` refreshes the UI

**Files:**
- `GymStreak/WatchConnectivityManager.swift` - iOS side
- `GymStreakWatch Watch App/Managers/WatchConnectivityManager.swift` - Watch side

---

## First-Time UX

| Hint | Storage Key | Behavior |
|------|-------------|----------|
| Reorder hint | `hasSeenReorderHint` | Shows in edit mode, auto-dismisses after 4-5s |

Stored in `@AppStorage` (UserDefaults).

---

## Localization

Key strings in `GymStreak/Resources/en.lproj/Localizable.strings`:

- `superset.rest_timer.explanation` - "Rest starts after completing all exercises in each round"
- `superset.remove_from` / `superset.remove_from_named` - Remove from superset actions
- `superset.dissolve` / `superset.dissolve_named` - Dissolve superset actions
- `superset.create_with` - "Create Superset With..." context menu label
- `superset.add_to` - "Add to Superset %@" context menu label
- `superset.link_action` - Label on the link affordance between two unlinked cards ("Link superset" / „Verknüpfen")
- `superset.link_exercises` - VoiceOver label of that same control
- `superset.unlink_between` - VoiceOver label of the unlink control on the connector ("Break superset between %1$@ and %2$@")

---

## All Files Reference

### Data Models
| File | Contains |
|------|----------|
| `GymStreak/Models.swift` | `RoutineExercise.supersetId/supersetOrder`, `WorkoutExercise` mirrors, grouping computed properties |
| `GymStreak/WatchModels.swift` | `WatchExercise`, `CompletedWatchExercise` with superset fields |
| `GymStreakWatch Watch App/Models/WatchModels.swift` | `ActiveWorkoutExercise.isInSuperset`, watch-side models |

### Domain Services
| File | Contains |
|------|----------|
| `GymStreak/Domain/Services/SupersetOrderingService.swift` | Contiguity invariant: `contiguousOrder(for:)`, `normalizeOrdering(in:)`; sorting units: `OrderingUnit`, `units(for:)`, `moveUnits(from:to:in:)` |
| `GymStreak/Domain/Services/SupersetEditor.swift` | Pure set-algebra for the multi-select editor (`canApplyEdit`, `decideEdit`) |

### Helpers
| File | Contains |
|------|----------|
| `GymStreak/Helpers/SupersetLabelProvider.swift` | `SupersetGroupable` protocol, letter label computation (A/B/C), per-group color assignment |

### ViewModels
| File | Contains |
|------|----------|
| `GymStreak/RoutinesViewModel.swift` | Superset CRUD operations: create / add / remove / dissolve / `splitSuperset(after:in:)` (unlink at a seam) |
| `GymStreak/WorkoutViewModel.swift` | iOS workout superset navigation & rest timers (~lines 470-958) |
| `GymStreakWatch Watch App/ViewModels/WatchWorkoutViewModel.swift` | Watch workout superset logic (~lines 280-718) |

### iOS UI Components
| File | Contains |
|------|----------|
| `GymStreak/Presentation/Views/Components/SupersetBadge.swift` | `SupersetBadge` (position/total+color) |
| `GymStreak/Presentation/Views/Components/SupersetRestTimerConfig.swift` | Rest timer config wrapper for supersets |
| `GymStreak/Presentation/Views/Components/SupersetLinkButton.swift` | Labelled link affordance between two adjacent unlinked cards (44pt row) |

### iOS Views
| File | Contains |
|------|----------|
| `GymStreak/Presentation/Views/Routines/RoutineDetailView.swift` | Context menu-based superset management, group/standalone row assembly, `ExerciseHeaderView` with position/total badges |
| `GymStreak/Presentation/Views/Routines/SupersetGroupContainer.swift` | `SupersetMemberAnchorKey` (dot + seam anchors), `supersetConnectorAnchor(id:isActive:)`, `supersetSeamAnchor(below:)`, `SupersetSeamSpacer`, `SupersetGroupContainer` + its continuous connector line and the `SupersetUnlinkButton` nodes on it |
| `GymStreak/Presentation/Views/Routines/RoutineDetailView+Supersets.swift` | `SupersetCardStyling`, `RoutineExerciseGroup`, `supersetStyling(for:)`, `supersetRowGroups(for:)`, `linkExercises`, `unlinkSuperset(after:)`, edit mode, context menu |
| `GymStreak/Presentation/Views/Routines/RoutineDetailView+Sorting.swift` | Sorting mode: unit-based `List` + `.onMove`, `sortingRow(for:labels:)` |
| `GymStreak/Presentation/Views/Routines/RoutineSortingRows.swift` | `RoutineSortingRow` (standalone) and `RoutineSortingGroupRow` (superset as one framed block) |
| `GymStreak/Presentation/Views/Workout/ActiveWorkoutView.swift` | `SupersetWorkoutGroupView` with letter/color; `WorkoutExerciseCardView` / `WorkoutExerciseCollapsedRow` with position/total badges |

### watchOS Views
| File | Contains |
|------|----------|
| `GymStreakWatch Watch App/Views/RoutineDetailView.swift` | Superset group preview with badges |
| `GymStreakWatch Watch App/Views/ExerciseListView.swift` | `WatchSupersetBadge`, exercise list with superset tinting |
| `GymStreakWatch Watch App/Views/ActiveWorkoutView.swift` | Main workout flow |
| `GymStreakWatch Watch App/Views/FullScreenSetEditorView.swift` | Set editor with superset context |
| `GymStreakWatch Watch App/Views/CompactActionBar.swift` | Set completion and navigation controls |

### Sync
| File | Contains |
|------|----------|
| `GymStreak/WatchConnectivityManager.swift` | iOS-side sync, receives completed watch workouts |
| `GymStreakWatch Watch App/Managers/WatchConnectivityManager.swift` | Watch-side sync, sends completed workouts |
