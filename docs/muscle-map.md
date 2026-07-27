# Muscle Map

Visualization of the muscle groups a workout trained: a schematic human body, drawn front
and back, with the trained muscle bellies lit in the app's accent color.

**Status:** tickets 01–04 of `.scratch/muscle-map/issues/` are implemented — the figure, the
aggregation, the card on the workout detail screen, and the tap-to-inspect interaction. The
map is a control, not a picture.

**Targets:** iOS only. There is no watchOS counterpart and none is planned — the watch target
is untouched by this feature.

## What the user sees

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

`MuscleLoadAggregator` produces what a real workout should light up, and
`MuscleMapCardModel.make(from:)` turns that into everything the card renders — the
`highlights` dictionary the figures take, the ordered `pills`, the per-region `details` the
chip shows, the per-region accessibility labels, and the pre-joined VoiceOver summary:

```swift
// In WorkoutDetailView.task — once, off the render path.
muscleMap = MuscleMapCardModel.make(from: MuscleLoadAggregator.aggregate(session: workout))
```

## Architecture

| File | Layer | Role |
|---|---|---|
| `Domain/Models/MuscleMapRegion.swift` | Domain | The 13 regions the figure is drawn in, `MuscleEngagement` (primary / secondary), and the muscle-group-key → region resolver |
| `Domain/Models/MuscleLoad.swift` | Domain | What one workout did to one region: engagement, completed set count, contributing exercise names |
| `Domain/Services/MuscleLoadAggregator.swift` | Domain | Turns a `WorkoutSession` into `[MuscleMapRegion: MuscleLoad]` |
| `Presentation/Views/MuscleMap/MuscleMapPathParser.swift` | Presentation | Path-string parser and `MuscleMapPathShape`, the `Shape` that maps design space into the view frame |
| `Presentation/Views/MuscleMap/MuscleMapGeometry.swift` | Presentation | The static path data, the parsed layered `MuscleMapFigure` values, and each figure's `MuscleMapRegionOutline` list (one merged path per region, for the accessibility proxies) |
| `Presentation/Views/MuscleMap/MuscleFigureView.swift` | Presentation | The view itself: drawing, per-belly hit-testing, dimming, per-region accessibility |
| `Presentation/Views/History/Components/MuscleMapCardView.swift` | Presentation | `MuscleMapCardModel` / `MuscleMapPill` / `MuscleMapDetail` (the finished values the card renders) and the card: header, legend, two captioned figures, and the pill row or detail chip |

`MuscleMapRegion` lives in `Domain/` rather than alongside the view because it is shared
vocabulary: the aggregation service of ticket 02 produces it and the figure consumes it.
Putting it in `Presentation/` would have forced a duplicate enum in `Domain/` (which cannot
depend on `Presentation/`). It imports only Foundation.

It is deliberately *not* the existing `BodyRegion` enum in `Domain/Models/MuscleGroups.swift`
— that one has three cases (upper body / core / lower body) and only drives muscle-group
badge coloring.

## Aggregation

### Where the data comes from

`WorkoutExercise.muscleGroups` is already denormalized onto every recorded exercise, so the
map reads history as it stands: **no schema change, no `@Model` property, and therefore no
CloudKit schema deploy**. The live `Exercise` library is deliberately not joined — history
must keep describing what was actually performed even after the library exercise is edited.

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
  still counts its sets somewhere instead of silently dropping them.
- **Primary wins.** A region that is secondary for one exercise and primary for another
  renders primary. The same applies within a single exercise, whose keys can collapse onto
  one region (Shoulders + Front Delts) — the region is then counted once, as primary.
- **Set counts are completed sets of the exercises the region led.** Supporting work adds no
  sets (the design shows a number for primary regions and the word "secondary" for the rest)
  but still records the exercise name.
- **An exercise with no completed sets contributes nothing at all** — no highlight, no name.
  History shows work actually performed, and a primary region reading "0 sets" would be a
  lie about a skipped exercise.
- Exercise names per region are distinct and follow the session's exercise `order`.
- A session that maps to nothing — only `General`, an empty routine, or nothing completed —
  yields an empty dictionary, which the card reads as "hide me".

### Consuming it

`aggregate(session:)` walks `workoutExercises` and `sets`, i.e. two SwiftData relationship
levels, so it is a service call rule 3 forbids in a `body`. `WorkoutDetailView` calls it from
`loadMuscleMap()` — once from `.task` when the screen opens and again from `reloadAfterEdit()`
after the session is edited — and stores the finished `MuscleMapCardModel` in `@State`. Its
output is a value type precisely so the card and the figures never touch a `@Model` per belly.

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
fill, a white 6 % hairline border, a 22 pt continuous corner radius, 14 pt padding (12 at the
bottom) and a 16 pt outer margin. Each figure is **128 pt wide**, so the pair plus the 6 pt
gap needs 262 pt — comfortably inside the 315 pt of card interior on the narrowest device the
app supports (iOS 26 requires a 375 pt-wide screen or larger), so no responsive sizing is
needed.

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

### Placement and the scroll anchor

Order on the detail screen is header → **muscle map card** → stat grid → the rest. Because the
card is inserted above the fold only once its aggregation lands (one frame after the screen
appears), the scroll view compensated by keeping the content below anchored, and the screen
opened already scrolled past the workout title. `WorkoutDetailView`'s `ScrollView` therefore
carries `.defaultScrollAnchor(.top)`. Do not remove it — the symptom returns immediately, and
it is not obvious from reading the card's code.

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
  silently hits neighbouring muscles. The device content is exposed as
  `group 1 of window 1`; read its `position` and map screenshot pixels as
  `screen = origin + pixel / 3` (3× device scale).
- **The accessibility tree is readable from the same place.** Walking `entire contents` of
  that group prints every element's role and label, which is how the per-region VoiceOver
  labels were verified: trained regions appear as `AXButton ~ "Quadrizeps, primär, 7 Sätze"`,
  untrained ones as `AXGenericElement ~ "Brust, nicht trainiert"`, and no unlabelled path
  shapes appear at all.

The AI-Coach opt-in cover does not appear on this simulator (Apple Intelligence is
unavailable there), so seeded history is reachable directly after launch.

## Related

The screen this card lives on is documented in [History Redesign](./history-redesign.md).
