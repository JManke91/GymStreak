# Muscle Map

Visualization of the muscle groups a workout trained — and, on the routine screen, the ones a
routine *plans* to train: a schematic human body, drawn front and back, with the affected muscle
bellies lit in the app's accent color. One figure, one aggregation and one card serve both
screens; only the wording differs.

**Status:** shipped on both screens. Tickets 01–04 of `.scratch/muscle-map/issues/` built the
figure, the aggregation, the card on workout detail and the tap-to-inspect interaction; tickets
01–02 of `.scratch/routine-muscle-map/issues/` added the planned reading of a routine and put the
card on routine detail. The map is a control, not a picture.

**Targets:** iOS only. There is no watchOS counterpart and none is planned — the watch target
is untouched by this feature.

## What the user sees

### On a recorded workout — Verlauf → workout detail

Opening a recorded workout from Verlauf shows, between the workout header and the four stat
tiles, a card titled **"Trainierte Muskelgruppen"**. It holds two schematic bodies side by
side — captioned VORNE and HINTEN — with the regions that workout trained lit in the app's
accent color: solid for the primary movers, a 42 % tint for the supporting ones, idle grey
everywhere else. The card header carries the title and a two-dot legend explaining the
shades.

Beneath the figures the same regions are spelled out as a wrapping row of pills, so the map
can be read without decoding the drawing: an accent-tinted pill per primary region carrying
its name and completed set count, ordered heaviest first, then muted pills for the supporting
regions in anatomical order.

Tapping a trained muscle on either figure — or its pill — selects that region: every other
belly dims to 30 %, and the pill row is replaced by a detail chip naming the region, its set
count (or "Sekundär" for a supporting mover), and the exercises that trained it. Tapping the
selected muscle again, or the chip's **Zurücksetzen** control, restores the pill row and full
opacity. See [Interaction](#interaction) for what is and is not tappable.

A workout that maps to no region at all — one whose exercises only carry `General`, or one
with nothing completed — **hides the card entirely**. An all-grey body would claim the
workout trained nothing rather than admitting the app cannot tell, and it would cost a third
of the screen to say it. The check is `MuscleMapCardModel.hasTraining`, inside the card view,
so the call site in `WorkoutDetailView` stays a single line.

### On a routine — Routinen → routine detail

The same card sits between the schedule card and the exercise list, titled **"Geplante
Muskelgruppen"** and lit with the regions this routine's exercises are going to train.
Everything else behaves identically — two captioned figures, the legend, the wrapping pill row,
tap a belly or a pill to inspect one region. What changes is that every count is phrased as a
plan: the detail chip reads "12 SÄTZE GEPLANT" where history reads "12 SÄTZE", and VoiceOver
speaks "Quadrizeps, primär, 12 Sätze geplant". There is no extra subline and no extra chrome —
the wording carries the distinction (see [One card, two readings](#one-card-two-readings)).

The card is hidden in **sorting mode** and in **superset-edit mode**: both take the list over,
and a decorative figure competing with a drag interaction is noise. It hides for a routine that
maps to no region too — an empty routine, one whose exercises only carry `General`, or one
stripped of its sets — the same `hasTraining` call history makes.

**Two muscle readings share this screen and must not be confused.** The chips under the routine
title come from `RoutineMetricsService.primaryMuscleGroups(for:)`: the raw muscle-group
vocabulary (the app's 19 keys), one chip per distinct `Exercise.primaryMuscleGroup`, in exercise
order. The figure speaks the 13 coarser regions and applies the primary/secondary rule below.
They can word the same fact differently — "Lats" as a chip, "Rücken" as a region — but they
cannot contradict each other, because both read the live exercise the routine points at. They
are deliberately not merged: different output type, different definition of "primary".

**Open follow-up on those chips.** `RoutineDetailView`'s `titleBlock` calls
`RoutineMetricsService.primaryMuscleGroups(for: routine)` *inline in a `ForEach` inside `body`* —
a Domain service call plus a relationship walk on the render path, which is exactly what
CLAUDE.md's rendering rule 3 forbids and what `docs/history-performance.md` was written about. It
is **pre-existing** and was deliberately left alone by the muscle-map work (found by the
architecture review, 2026-09-04, outside that change's scope), but it sits on the same screen and
describes the same subject. The fix is the one the muscle map already applies next to it:
precompute it off the render path — ideally into the same `@State` the map uses, since both are
recomputed by the same edits and keyed by the same `Routine.updatedAt`.

## Pieces

`MuscleFigureView` draws one figure — front or back — at a caller-supplied width, coloring
each muscle belly from a `[MuscleMapRegion: MuscleEngagement]` dictionary. Regions absent
from the dictionary render in the idle grey. It reports taps on trained bellies back through
`onSelect` and dims everything but `selection`, but owns no selection state itself. Nothing
in the view reads workout data, SwiftData, or a repository, so it is fully exercisable from
its SwiftUI preview.

```swift
MuscleFigureView(
    face: .front,
    highlights: [.chest: .primary, .triceps: .secondary],
    width: 128,
    selection: selectedRegion,          // dims the rest; nil = full strength
    regionLabels: model.accessibilityLabels,
    onSelect: { region in ... }         // only fires for trained regions
)
```

`MuscleLoadAggregator` produces what a workout — or a routine — should light up, and
`MuscleMapCardModel.make(from:reading:)` turns that into everything the card renders — the
`highlights` dictionary the figures take, the ordered `pills`, the per-region `details` the
chip shows, the per-region accessibility labels, and the pre-joined VoiceOver summary:

```swift
// In WorkoutDetailView.task — once, off the render path.
muscleMap = MuscleMapCardModel.make(
    from: MuscleLoadAggregator.aggregate(session: workout),
    reading: .performed
)
```

## Architecture

| File | Layer | Role |
|---|---|---|
| `Domain/Models/MuscleMapRegion.swift` | Domain | The 13 regions the figure is drawn in, `MuscleEngagement` (primary / secondary), and the muscle-group-key → region resolver |
| `Domain/Models/MuscleLoad.swift` | Domain | What one reading does to one region: engagement, `setCount`, contributing exercise names |
| `Domain/Services/MuscleLoadAggregator.swift` | Domain | Turns a `WorkoutSession` **or** a `Routine` into `[MuscleMapRegion: MuscleLoad]` |
| `Presentation/Views/MuscleMap/MuscleMapPathParser.swift` | Presentation | Path-string parser and `MuscleMapPathShape`, the `Shape` that maps design space into the view frame |
| `Presentation/Views/MuscleMap/MuscleMapGeometry.swift` | Presentation | The static path data, the parsed layered `MuscleMapFigure` values, and each figure's `MuscleMapRegionOutline` list (one merged path per region, for the accessibility proxies) |
| `Presentation/Views/MuscleMap/MuscleFigureView.swift` | Presentation | The view itself: drawing, per-belly hit-testing, dimming, per-region accessibility |
| `Presentation/Views/MuscleMap/MuscleMapCardModel.swift` | Presentation | `MuscleMapReading` (which of the two readings a card speaks) and the finished values it renders: `MuscleMapCardModel` / `MuscleMapPill` / `MuscleMapDetail` |
| `Presentation/Views/MuscleMap/MuscleMapCardView.swift` | Presentation | The card: header, legend, two captioned figures, and the pill row or detail chip |

The card and its model **moved out of `Presentation/Views/History/Components/`** into the
muscle-map folder when routine detail became the second caller (routine-muscle-map ticket 02).
Files are target-included by directory here (`PBXFileSystemSynchronizedRootGroup`), so the move
needed no project-file edit. Nothing about the card is History-specific any more; do not move it
back next to one of its callers.

`MuscleMapRegion` lives in `Domain/` rather than alongside the view because it is shared
vocabulary: the aggregation service produces it and the figure consumes it.
Putting it in `Presentation/` would have forced a duplicate enum in `Domain/` (which cannot
depend on `Presentation/`). It imports only Foundation.

It is deliberately *not* the existing `BodyRegion` enum in `Domain/Models/MuscleGroups.swift`
— that one has three cases (upper body / core / lower body) and only drives muscle-group
badge coloring.

## Aggregation

### The two readings

One aggregator answers two questions, and `MuscleLoad` is deliberately neutral about which one
produced it — its count field is `setCount`, not `completedSets`, because nothing in a plan is
completed. Only the projection differs; every rule below runs on both, once, in
`MuscleLoadAggregator.fold(_:)`.

| | Workout — `aggregate(session:)` | Routine — `aggregate(routine:)` |
|---|---|---|
| Muscle groups | `WorkoutExercise.muscleGroups`, the denormalized copy | the live `Exercise` the slot points at |
| Sets counted | completed sets | planned sets |
| Contributes nothing | an exercise with no completed set | a slot with no attached exercise, or none planned |

**History reads its own copy on purpose.** `WorkoutExercise.muscleGroups` is already denormalized
onto every recorded exercise, so the map reads history as it stands — **no schema change, no
`@Model` property, and therefore no CloudKit schema deploy** — and a workout keeps describing what
was actually performed even after the library exercise is edited.

**A routine reads the live library on purpose.** It describes what *will* happen, so there is no
copy to fall back on: re-tagging an exercise's muscle groups changes every routine's map
immediately, at its next recompute. That is the intent, not a leak.

**Alternative exercises are not aggregated.** They are choices — the user performs the exercise
*or* one of its alternatives, never both — so folding them in would light up regions the routine
will most likely not train. The exclusion is simply that `aggregate(routine:)` projects
`routineExercise.exercise` and never touches `alternativesList`; a future "everything this routine
could hit" reading would add each alternative as its own contribution rather than change this one.

**An unattached routine slot contributes nothing.** `RoutineExercise` allows a nil `exercise` so
insertion can happen before SwiftData relationships are wired; such a slot names no exercise and
no muscle group, so it plans nothing.

### Key → region

The app's 19 muscle-group keys (`MuscleGroups.allKeys`) collapse onto the 13 regions:

| App key(s) | Region |
|---|---|
| Upper Back | trapezius |
| Shoulders, Front Delts, Side Delts, Rear Delts | shoulders |
| Chest, Upper Chest | chest |
| Biceps | biceps |
| Triceps | triceps |
| Forearms | forearms |
| Abs, Obliques | abs |
| Lats | back |
| Lower Back | lower back |
| Glutes | glutes |
| Quadriceps, **Hip Flexors** | quadriceps |
| Hamstrings | hamstrings |
| Calves | calves |
| General | *(unmapped — contributes no highlight)* |

`Hip Flexors` has no belly of its own in the design body and is folded into quadriceps, the
nearest region it sits behind. `General` is the seed catalogue's fallback and deliberately
highlights nothing rather than lighting up the whole figure. A test asserts the table covers
every key, so adding a key to the catalogue without a region fails the suite.

### Rules

- The **first mapped** entry of an exercise's `muscleGroups` is its primary mover; every
  later one is secondary. This mirrors how the app already treats `muscleGroups.first` for
  the primary-muscle badge and Fortschritt grouping. It keys off the first *mapped* entry
  rather than index 0 so an exercise led by an unmapped key (`["General", "Quadriceps"]`)
  still counts its sets somewhere instead of silently dropping them. A routine reads this off the
  live exercise; a workout off its recorded copy.
- **Primary wins.** A region that is secondary for one exercise and primary for another
  renders primary. The same applies within a single exercise, whose keys can collapse onto
  one region (Shoulders + Front Delts) — the region is then counted once, as primary.
- **Set counts are the sets of the exercises the region led** — completed ones for a workout,
  planned ones for a routine. Supporting work adds no sets (the design shows a number for primary
  regions and the word "secondary" for the rest) but still records the exercise name.
- **An exercise with no sets contributes nothing at all** — no highlight, no name. History shows
  work actually performed and a routine exercise stripped of its sets plans nothing, so a primary
  region reading "0 sets" would be a lie about either. Removing sets one by one is reachable in
  the routine UI, so this case is real rather than theoretical.
- Exercise names per region are distinct and follow the source's exercise `order`.
- A source that maps to nothing — only `General`, no exercises, or no sets — yields an empty
  dictionary, which the card reads as "hide me".

### Consuming it

Both entry points walk two SwiftData relationship levels — `workoutExercises` → `sets`, and
`routineExercises` → `exercise` / `sets` — so either is a service call rule 3 forbids in a
`body`. Both screens therefore run it in a `loadMuscleMap()` of their own and store the finished
`MuscleMapCardModel` in `@State`; its output is a value type precisely so the card and the
figures never touch a `@Model` per belly.

`WorkoutDetailView` calls `aggregate(session:)` once from `.task` when the screen opens, and
again from `reloadAfterEdit()` after the session is edited. A recorded session changes rarely and
only through that one door.

`RoutineDetailView` calls `aggregate(routine:)` from `.task` **and from
`.onChange(of: routine.updatedAt)`**, because unlike workout detail this screen mutates the very
thing it draws: exercises are added, removed and restored, sets are added, removed and edited,
units are reordered, supersets are formed and dissolved. A one-shot load would go stale seconds
after the screen opens.

That single scalar covers the whole edit surface because **every** mutation on this screen reaches
the store through `RoutinesViewModel.updateRoutine(_:)`, which stamps `Routine.updatedAt` — that
was checked path by path (add configured exercise, remove and restore exercise, add/remove/update
set, move units, rest time and apply-to-all, rep ranges, progressive overload, all five superset
methods, alternatives) rather than assumed. It is one cheap read that faults no relationship. Keep
it that way: a new mutation path that skips `updateRoutine` silently freezes the map, and the fix
belongs in that path — not in a second trigger here.

It is deliberately **not** a computed property. Routine detail re-evaluates its body on every
keystroke in a set editor, and `aggregate(routine:)` is a service call plus two relationship
traversals — precisely what CLAUDE.md's rendering rule 3 forbids on the render path.

Two details of `RoutineDetailView.loadMuscleMap()` are deliberate and were added on review:

- It is explicitly **`@MainActor`**, like its workout-detail twin, even though both current call
  sites already are. It reads `Routine`, `RoutineExercise.exercise` and `setsList` — non-`Sendable`
  `@Model` objects — so a future caller from a nonisolated context has to fail to compile rather
  than read SwiftData off-main with no diagnostic.
- It **compares before it assigns** (`guard next != muscleMap`). `updatedAt` is the whole edit
  surface, which means it is also stamped by reps and weight changes that cannot move a single
  belly — a stepper tap would otherwise re-render the card on every press. The traversal itself
  still runs and is accepted: it is bounded by the routine's size and is small beside the `save()`
  + `fetchRoutines()` that same path already pays, and a narrower trigger would mean one per
  mutation, which is exactly the plumbing this design avoids.

`MuscleMapCardModel.make(from:reading:)` is unit-tested in `GymStreakTests/MuscleMapCardModelTests.swift`
— specifically that the reading reaches the strings. A mistyped key renders the raw key with a
perfectly green build, and the routine screen would be the one showing it.

`MuscleEngagement`'s raw values are storage vocabulary, not display strings. Region names are
display strings and live in `MuscleMapRegion.displayName` under the `muscle_region.*` keys —
their own set rather than a reuse of `muscle.*`, because the regions are coarser than the
muscle-group keys and read differently (region `back` is the lats, region `trapezius` is what
the catalogue calls Upper Back).

## Geometry

The geometry is not invented in the app. Source of truth is `muscle-map.jsx` in the Claude
Design project `0d4ac3f4-2c40-43cc-b80e-84bd411c334a`
(`https://claude.ai/design/p/0d4ac3f4-2c40-43cc-b80e-84bd411c334a`), fetched with the
`DesignSync` tool. Any change to the figure starts there, not in the Swift file.

- Paths are authored on a **200 × 474** grid using only absolute `M`, `L`, `C` and `Z`
  commands. `MuscleMapPathParser` covers exactly those four; no SVG library is pulled in.
- The body is authored as a **left half only**. Every shape flagged `mirror` is drawn twice,
  the second time reflected across the midline `x = 100` (the design expresses this as
  `translate(200,0) scale(-1,1)`). The mirrored path is computed once, at geometry-build
  time, and stored alongside the original in `MuscleMapShape.paths`.
- The visible viewport is `14 0 172 474` — the figure is cropped horizontally, so the
  aspect ratio is `172 / 474`, not `200 / 474`. `MuscleMapPathShape` applies that viewport
  crop, and the view derives its height from the width.
- **Draw order matters:** silhouette (darkest body contour) → fillers (head, joints, hands,
  feet, and on the front the pelvis) → muscle bellies → the midline detail stroke on top.
  Front and back share the silhouette and the fillers; only the front adds the pelvis plate.
- Regions repeat within a figure — the abdominals are six separate bellies, the calves two
  or three. `ForEach` therefore keys on the shape's own id, never on its region.

### Colors and weights

| Element | Fill | Stroke |
|---|---|---|
| Silhouette | white @ 5.5% | near-black `#0b0b0b`, 1.4 |
| Fillers | white @ 12% | near-black, 1.4 |
| Idle muscle | white @ 20% | near-black, 1.5 |
| Primary highlight | `DesignSystem.Colors.tint` | near-black, 1.5 |
| Secondary highlight | `DesignSystem.Colors.tint` @ 42% | near-black, 1.5 |
| Midline detail | none | black @ 45%, 1.2 |

The accent comes from the app's `DesignSystem` token rather than the design file's hex, so
the map follows the app's theme. Stroke weights are in design-space units and are scaled by
`width / 172` so they stay proportional at any size. Fill changes animate over 0.3 s
(`easeInOut`), matching the design's fill transition.

## The card

Chrome follows `workout-detail.jsx` / `muscle-map.jsx` in the same design project: white 3 %
fill, a white 6 % hairline border, a 22 pt continuous corner radius and 14 pt padding (12 at the
bottom). Each figure is **128 pt wide**, so the pair plus the 6 pt gap needs 262 pt — comfortably
inside the 315 pt of card interior on the narrowest device the app supports (iOS 26 requires a
375 pt-wide screen or larger), so no responsive sizing is needed.

The design's 16 pt **outer margin is the caller's**, not the card's: `horizontalMargin` is a
parameter defaulting to 0. Workout detail lays its sections out edge to edge and passes 16;
routine detail's scroll content is already inset by 16 and passes nothing. It is a parameter
rather than a `.padding` at the call site because the card hides itself for a source that maps to
nothing — padding wrapped around the hidden card would still reserve its insets, and a caller
fighting that with negative padding is how this goes wrong. Applied inside the card's
`hasTraining` guard, a hidden card costs exactly zero. The same reasoning is why routine detail
asks `muscleMap.hasTraining` itself before adding the 10 pt spacer beneath the card — that spacer
is the screen's, so the screen has to answer the question too.

The pills follow the design's two treatments: primary is accent @ 14 % fill with an accent
@ 26 % capsule border, the name in white 11.5 pt semibold and the set count in the accent
itself; secondary is white @ 4 % fill, white @ 7 % border, name in white @ 60 % medium and no
count. They wrap through the existing `FlowLayout` in `Views/Components/RedesignControls.swift`
(spacing 6) rather than a new layout type.

The detail chip that replaces the pill row while a region is selected follows the design's
chip: accent @ 9 % fill, accent @ 22 % border, 12 pt continuous radius, 11 pt horizontal and
9 pt vertical padding, 8 pt above. Its first row is the region name (13 pt bold rounded,
white), the state — set count or "Sekundär" — in the accent at 10 pt bold uppercase with
0.5 tracking, and the reset control pushed right; the second row lists the contributing
exercises joined with " · " in white @ 60 %.

Nothing in the card puts text on an accent-filled surface, so `textOnTint` does not come up
here — the accent pill fill is a 14 % tint over black and the chip's is a 9 % tint, not solid
green plates, and the legend dots carry no text. Should either ever become a solid accent
fill, its text has to switch to `DesignSystem.Colors.textOnTint`.

### One card, two readings

`MuscleMapReading` — `.performed` for a recorded workout, `.planned` for a routine — is the only
thing that separates the two screens, and it is consumed entirely inside
`MuscleMapCardModel.make(from:reading:)`: it selects a set of localization keys, the finished
values are built from them, and the card renders whatever it is handed without knowing which
screen it is on. That is what keeps this one implementation instead of two.

Only the strings that name the card or a set count differ:

| Value | `.performed` — `history.detail.muscle_map.*` | `.planned` — `routine.detail.muscle_map.*` |
|---|---|---|
| card title | Trained Muscle Groups | Planned Muscle Groups |
| `sets_count` (detail chip) | %d sets | %d sets planned |
| `a11y.region_sets` (summary) | %1$@ %2$d sets | %1$@ %2$d sets planned |
| `a11y.belly_primary` | %1$@, primary, %2$d sets | %1$@, primary, %2$d sets planned |
| idle belly | %@, not trained | %@, not planned |

Everything else is deliberately shared and stays on the `history.*` keys, because it says the
same thing under either reading: the legend (Primär / Sekundär), the VORNE and HINTEN captions,
the secondary state label, the reset control, and the "Primär: … Sekundär: …" summary wrapper.
Region names are shared too (`muscle_region.*`) — a region is a region either way. The planned
strings live under their own `routine.detail.*` prefix rather than as extra `history.*` keys: a
routine screen reading history keys is exactly the kind of thing that gets "tidied up" wrongly
later.

The primary **pill** shows a bare number and needs no reading of its own; VoiceOver reads it with
the region's `a11y.belly_primary` label, which does carry the distinction.

### Placement and the scroll anchor

On workout detail the order is header → **muscle map card** → stat grid → the rest; on routine
detail it is title → schedule card → **muscle map card** → exercise list.

Because the card is inserted above the fold only once its aggregation lands (one frame after the
screen appears), `WorkoutDetailView`'s scroll view compensated by keeping the content below
anchored, and the screen opened already scrolled past the workout title. Its `ScrollView`
therefore carries `.defaultScrollAnchor(.top)`. Do not remove it — the symptom returns
immediately, and it is not obvious from reading the card's code.

`RoutineDetailView` was checked for the same symptom when the card was added there and does
**not** exhibit it — it opens at its title — so it carries no anchor override. If a future change
inserts more late-arriving content above its fold, this is the first thing to suspect and
`.defaultScrollAnchor(.top)` is the fix.

It did surface a *different* scroll problem, around **superset-edit mode**: that mode hides this
card and the schedule card and swaps every exercise card for a compact row, so the routine's
content collapses, the scroll offset is clamped to it, and the user is dropped at the top going in
and coming back out. This card is not the cause — the row collapse is, and the schedule card was
already doing the same thing — but it makes the collapse larger. It is **an open known issue**, and
two `proxy.scrollTo`-based attempts were tried and reverted; see [Superset
Feature](./superset-feature.md), "KNOWN ISSUE: edit mode loses the scroll position", before
attempting a third.

## Interaction

Selecting a region is **local `@State` in `MuscleMapCardView`**. It deliberately lives
nowhere else: changing it redraws the card and nothing more — no re-aggregation, no
re-parsed geometry, both of which are finished and static by the time the card appears.

- **What is tappable:** the individual muscle bellies of a *trained* region on either figure,
  and the region's pill. An untrained belly gets no tap handler at all
  (`allowsHitTesting(false)`), so tapping it does nothing rather than selecting something
  invisible.
- **Toggling:** tapping the selected region again clears the selection, as does the chip's
  reset control. Tapping a *different* region switches to it directly.
- **Mirroring:** a shape's authored half and its mirrored counterpart are separate path
  views carrying the same handler, so the left and the right biceps select the same region.
  The same region on the other figure is one selection too — selecting the trapezius lights
  it on both the front and the back body.
- Selection changes animate over 0.25 s (`easeInOut`); non-selected bellies drop to 30 %
  opacity, the design's dim level. Dimming is purely visual — see accessibility below.

### Hit-testing facts that this depends on

- Every belly is a `MuscleMapPathShape` that **fills the whole figure frame**, and SwiftUI
  hit-tests the layout frame rather than the painted path. Each tappable shape therefore
  carries `.contentShape(MuscleMapPathShape(designPath:))`; without it the topmost belly
  would swallow every tap on the figure.
- Non-interactive shapes drawn *on top* (the silhouette, the fillers, the midline detail
  stroke) would block taps to the bellies beneath them for the same reason, so every shape
  view without a handler carries `.allowsHitTesting(false)`.
- The reset control started as a bare 11 pt `Text` inside a `Button` and was effectively
  unhittable — its hit area is the glyph box. It now carries its own padding plus
  `.contentShape(Rectangle())`. Any small text button in this card needs the same.

### Accessibility

The figures are the accessible map. Each one attaches
**`.accessibilityChildren(children:)`** — Apple's documented pattern for giving custom
drawing a small set of synthetic elements — containing one proxy per region the figure draws.
`accessibilityChildren` hides the real subtree itself, so the ~55 path shapes never reach the
tree and no `.accessibilityHidden` is needed alongside it.

- Each proxy is the region's merged outline (`MuscleMapFigure.regionOutlines`, built once
  with the geometry) and carries `.contentShape(.accessibility, shape)` so VoiceOver's focus
  frame follows the actual bellies instead of the full figure rect.
- Labels come pre-built from `MuscleMapCardModel.accessibilityLabels` — "Quadrizeps, primär,
  7 Sätze", "Gesäß, sekundär", "Brust, nicht trainiert". Building 13 formatted strings per
  render would be work in `body`.
- **Untrained regions are exposed too**, with the "nicht trainiert" label but no action and
  no `.isButton` trait: dimming and inertness are visual affordances and must not cost the
  map its information. Trained regions carry `.isButton`, plus `.isSelected` while selected.
- The pills and the reset control are ordinary `Button`s; each pill borrows the same
  per-region label so VoiceOver does not read its set count as a stray number.
- The card is no longer one lumped element. The card title carries the overview as its
  accessibility value ("Primär: Quadrizeps 7 Sätze… Sekundär: Gesäß, Unterer Rücken"), so a
  VoiceOver user hears the summary first and can then swipe into the individual regions.

Set counts are formatted with `history.detail.muscle_map.a11y.region_sets` (`"%1$@ %2$d
Sätze"`) and `history.detail.muscle_map.sets_count` (`"%d Sätze"`), unpluralised — the same
shape as the app's existing `routine.sets_count`. There is no `.stringsdict` in this project;
adding one for these strings alone was not worth it.

## Performance

Parsing path strings is expensive and there are ~40 shapes per figure, so parsing happens
**once**, in the `static let` storage of `MuscleMapGeometry` (lazily initialized on first
access), and never inside a view `body`, a computed property `body` reads, or a per-shape
helper — the regression class documented in `docs/history-performance.md`.

At render time the only per-shape work is `Path.applying(_:)` inside `Shape.path(in:)`,
which is what any `Shape` does during layout. `MuscleFigureView.figure` is an O(1) switch
over two static values, not a build step.

The figures are individual `Shape` views in a `ZStack` rather than a single `Canvas`. A
`Canvas` would draw faster, but per-belly hit-testing and per-belly dimming come for free
with real views and would have to be hand-rolled against a `Canvas`. The shape count (~55 per
figure including mirrors) is small enough that this is not a rendering concern.

Selection is view state and touches nothing precomputed: the aggregation ran once in
`WorkoutDetailView`, and the region outlines the accessibility proxies use are built with the
rest of the geometry in `MuscleMapGeometry`'s static storage. Selecting a region re-runs only
the card's `body`, whose per-region work is dictionary lookups.

## Verification

The figure was rasterized off-target to confirm proportions and mirroring: the geometry
files compile standalone against macOS SwiftUI, so a scratch `ImageRenderer` host can draw
both figures to a PNG without running the app. Useful when changing path data, since Xcode
previews cannot be driven from the command line.

The card was verified in the simulator against seeded history (`-UI_TESTING
-UI_TEST_EPHEMERAL_STORE`): a leg session lit quadriceps, hamstrings and calves solid with
glutes and lower back in the softer tint; a push session lit chest, shoulders and triceps; and
a pull session's pill row wrapped over three lines (Trapez 4 · Rücken 4 · Unterer Rücken 4 ·
Schultern 3 · Bizeps 3, then muted Unterarme · Gesäß · Beinbeuger).

The interaction was driven the same way: tapping a belly, its mirrored counterpart, its pill,
the selected belly again, the reset control, and an untrained belly, each confirmed against a
screenshot. Two things make that repeatable from the command line:

- **Coordinates.** Synthetic clicks go through `System Events`, and the Simulator window's
  own bounds are *not* the device screen — mapping through them is off by tens of pixels and
  silently hits neighbouring muscles. The device content is exposed as `group 1` of the
  simulator window; read its `position` and map screenshot pixels as
  `screen = origin + pixel / 3` (3× device scale). **Address the window by name**
  (`first window whose name contains "iOS 26.1"`) rather than `window 1` — with two simulators
  open, `window 1` is whichever one is frontmost and every click silently lands on the wrong
  device. Raise the target window (`perform action "AXRaise"`) before clicking or the click is
  swallowed.
- **The accessibility tree is readable from the same place.** Recursing through `UI elements`
  prints every element's role and label, which is how the per-region VoiceOver labels were
  verified: trained regions appear as `AXButton ~ "Quadrizeps, primär, 7 Sätze"` (or
  "… 7 Sätze geplant" on a routine), untrained ones as `AXGenericElement ~ "Brust, nicht
  trainiert"` / `"Brust, nicht geplant"`, and no unlabelled path shapes appear at all. Note that
  `entire contents` returns **nothing** on this Simulator build — it must be walked level by
  level, and the region proxies sit deeper than 20 levels down, so a shallow walk finds only the
  pills.
- **`System Events` clicks take over the physical mouse pointer** for as long as the run lasts.
  Scripting a long click-through makes the machine unusable meanwhile — script the shortest path
  that answers the question, and say so before starting one.

The AI-Coach opt-in cover does not appear on this simulator (Apple Intelligence is
unavailable there), so seeded history is reachable directly after launch. The **onboarding flow
now runs on a fresh ephemeral store** and has to be skipped ("Überspringen", top right) before
either tab is reachable.

### The routine card (routine-muscle-map ticket 02)

Verified on the seeded push routine (`-UI_TESTING -UI_TEST_EPHEMERAL_STORE`, iPhone 17 Pro,
iOS 26.1):

- The card renders between the schedule card and the exercise list, titled "Geplante
  Muskelgruppen", with Brust 10 · Schultern 7 · Trizeps 3 — matching the routine's planned sets
  by hand (bench 4 + incline 3 + flyes 3 chest; press 4 + raises 3 shoulders; pushdowns 3
  triceps, with the presses' triceps work secondary and therefore uncounted).
- The screen opens at its title, so the workout-detail scroll-anchor symptom does **not** occur
  here and no `.defaultScrollAnchor(.top)` was added.
- Tapping a deltoid selected Schultern; the chip read "Schultern · 7 SÄTZE GEPLANT ·
  Zurücksetzen" over "Schulterdrücken · Seitheben". Tapping the same belly again restored the
  pill row.
- The accessibility tree spoke the planned phrasing throughout: `AXButton ~ "Brust, primär, 10
  Sätze geplant"` for the lit regions and `AXGenericElement ~ "Quadrizeps, nicht geplant"` for
  the idle ones.
- **Live editing:** adding Beinpresse (3 × 10) grew the map by Quadrizeps 3 (primary) and Gesäß
  (secondary) and wrapped the pill row onto a second line; deleting one of its sets moved the
  pill to Quadrizeps 2; deleting the exercise in sorting mode dropped both regions again. The
  `Routine.updatedAt` trigger therefore covers the add-exercise, remove-set and remove-exercise
  paths in practice, not just on paper.
- Sorting mode hides the card (its rows replace the whole list).

The remaining shapes were confirmed **on device** by the user (2026-09-04): the leg routine, the
pull routine's wrapping pill row, superset-edit mode hiding the card, an empty routine hiding it,
and the workout-detail card unchanged after the refactor. Device testing also turned up the
superset-edit scroll regression described above.

One case is **not reachable through the UI at all**: a routine built only from `General`-tagged
exercises. The create-exercise flow requires at least one muscle group, so `General` can only
arrive from the seed catalogue's fallback or from legacy/imported data. The behaviour is covered
by `MuscleMapCardModelTests` (an empty load map yields `hasTraining == false` under either
reading) and by the aggregator's `General`-only tests, and the empty-routine case exercises the
same `hasTraining` guard on screen.

## Related

The two screens this card lives on are documented in
[History Redesign](./history-redesign.md) (workout detail) and
[Routines & Exercises Redesign](./routines-exercises-redesign.md) (routine detail).
