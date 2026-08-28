# Weight unit preference (kg / lb)

**Status:** tickets 01 and 02 of 05 shipped — the unit type, the preference store, the
Settings picker, the formatting seam, the active-workout surfaces (01), and the whole of
routine building/editing plus the progressive-overload increment grid (02). Tickets 03–05
route the remaining surfaces (history/charts/PRs/volume, watch parity, AI coach) through
the seam built here.

**Source:** Things to-do "Weight Conversion" (`4HHdQyQQe88T9iMReWTmdc`), reported as a
customer complaint that the app is unusable in pounds.
Slices: `.scratch/weight-unit-preference/issues/`.

---

## 1. What it does

A user opens Settings → Units → Weight unit, picks Pounds, and every weight on the
active-workout screen reads in lb — the set rows, the collapsed exercise row, the keypad
sheet, the assistance and body-weight fields — with the +/− controls stepping in
pound-sized increments. Switching back to Kilograms restores exactly the numbers that
were there before, because nothing was rewritten in the database.

The same holds while building a routine: the set editor, the create-routine flow, the
alternative-exercise editors, the routine cards and sorting rows, and the
progressive-overload sheet all read and accept pounds, and the sheet offers real pound
plate steps rather than converted kilogram ones.

**Monetization: Free.** §3 Rule 1 (aha path), Rule 3 (in-workout), Rule 4 (the user's own
logged data). No cap, no placement, no nudge — the whole feature is the free residue.
Re-checked at completion: what shipped is entirely free, matching the planning verdict.

---

## 2. Storage decision — kilograms stay canonical

**Kilograms remain the stored unit everywhere.** `weight`, `plannedWeight`,
`actualWeight`, `bodyWeightKg` and every wire DTO keep their current meaning. Pounds exist
only between the store and the user's eyes. Consequences:

- no SwiftData migration, no CloudKit schema change, no watch wire-format break;
- volume aggregation, Epley 1RM, PR comparison and every chart keep working on one unit;
- two rules that the code enforces rather than trusts:
  1. **always convert from the canonical kilograms**, never from a previously converted
     display value — chained kg→lb→kg hops accumulate IEEE-754 error;
  2. **never persist a converted number** — only `WeightUnit.kilograms(fromDisplay:)`'s
     result goes back into the store.

### Rejected: store the value the user typed plus the unit they typed it in

Volume aggregation, 1RM, PR comparison and every chart would then need per-set conversion
anyway, and history becomes unreadable the moment a user switches units mid-programme
(a chart mixing 90 and 198 as bare numbers). Not revisited.

---

## 3. API research

### `Measurement<UnitMass>.converted(to:)` — chosen

Conversion goes through `Measurement<UnitMass>`; the string is built by
`FloatingPointFormatStyle<Double>` plus a unit word out of `Localizable.strings`.

**Finding that contradicted the plan: Foundation's `UnitMass.pounds` does not use the
exact avoirdupois pound.** Its `UnitConverterLinear` coefficient is **`0.453592`**, not
`0.45359237` — measured, not assumed (`Measurement(value: 100, unit: UnitMass.pounds)
.converted(to: .kilograms).value == 45.3592` exactly). That is a 8·10⁻⁷ relative
difference: 0.0002 lb at 100 kg, three orders of magnitude below the single decimal place
pounds are displayed with, so it is invisible in the UI and irrelevant to storage — the
kg→lb→kg round trip is exact to ~10⁻¹⁶ regardless, because it divides and multiplies by
the *same* coefficient. `WeightUnitTests.poundsUseFoundationsCoefficient` asserts the
coefficient directly, so an SDK that tightens it shows up as a test failure rather than as
a silent shift in everyone's logged pounds.

### `MeasurementFormatter` — rejected

A mutable `NSObject` that is not `Sendable`, so a `static let` of it does not compile in
this Swift 6 build — the same wall the repo already hit with `DateFormatter`
(`Domain/Models/ExerciseUsage.swift`). Hoisting is mandatory under the
no-formatter-in-`body` rule, so a formatter that cannot be hoisted cannot be used.

### `Measurement.formatted(.measurement(...))` for the unit word — rejected

Its `usage:` parameter defaults to `.general`, which **re-derives the unit from the
locale** and would silently contradict the value just converted. `usage: .personWeight` is
worse: CLDR can render `en_GB` person weights in **stone**. `usage: .asProvided` does
suppress that, but then one is paying for `Dimension`/`UnitConverter` generality to produce
one of two words already owned in `Localizable.strings`.

This is not hypothetical for this codebase: locale-driven formatting is what put "+2.5 kg"
next to "→ 137.8 lb" on the same watch screen
(`GymStreakWatch Watch App/Views/ProgressiveOverloadPickerViews.swift`).

---

## 4. Architecture

```
Domain/Models/WeightUnit.swift                    the unit, conversion, precision,
                                                  increments, ceiling, locale default
Domain/Interfaces/WeightUnitPreferenceProviding   @MainActor protocol, get/set
Data/Preferences/WeightUnitPreference.swift       @Observable @MainActor, UserDefaults
App/AppDependencies.swift                         wired as `weightUnitPreference`
App/ContentView.swift                             publishes \.weightUnit into the env
Presentation/Helpers/WeightUnitEnvironment.swift  the @Entry environment value
Presentation/Helpers/WeightFormatting.swift       the one formatting seam
Presentation/Helpers/WeightDisplayMirror.swift    the kg ↔ display field invariant
Presentation/Views/Workout/SetValueKeypad.swift   the digit pad, split off the sheet
Presentation/Views/Settings/Components/UnitsSettingsSectionView.swift
```

`WeightUnit` lives in `Domain/` and imports only Foundation — no SwiftUI, no localization.
The unit *words* are Presentation's business, which is why they live in
`WeightFormatting` and not on the enum.

### Two delivery paths, on purpose

- **ViewModels** take `WeightUnitPreferenceProviding` by **init injection** from
  `AppDependencies` — never `WeightUnitPreference.shared` (Hard rule 2). Ticket 03's
  `ExerciseProgressViewModel` is the first one that needs it.
- **Views** read `@Environment(\.weightUnit)`. Around 40 view call sites render a weight
  across tickets 02–04; prop-drilling the unit through every row initializer is the wrong
  trade, and the value is one `WeightUnit` that changes at most once in a session.

Reactivity: `ContentView.body` reads
`dependencies.weightUnitPreference.weightUnit`. The store is `@Observable`, so that read is
what registers the observer — the Settings picker writes the property, `ContentView` is
invalidated, the environment value is republished, and every weight on screen re-renders.
No notification, no publisher.

### Default and precision

Seeded once, from `Locale.current.measurementSystem`: **`.us` → pounds, everything else
including `.uk` → kilograms**. `.uk` is deliberately *not* treated as imperial — UK gyms use
kg regardless of what CLDR says about road signs. `measurementSystem` is what makes the
distinction possible at all; the coarser `usesMetricSystem` reports `false` for both `.us`
and `.uk` and could not tell them apart. The seed is written back inside `init`, so from the
second launch on there is a stored value and the locale is never consulted again: a trip
abroad or a system-region change must not move the unit.

Display precision is per unit: kg keeps `.fractionLength(0...2)` (0.25 kg increments need
two digits), lb uses `.fractionLength(0...1)`. `.grouping(.never)` on both — at 999 kg a
grouping separator would read as a decimal point. A whole number renders "65", never "65.0".

---

## 5. The formatting seam

Three parallel weight formatters existed, none unit-aware. That drift is the reason "kg"
ended up baked into ~20 localized *values*, which is why this could not be a pure code
change. They are now one:

| Before | After |
| --- | --- |
| `WeightFormatting` — `FloatingPointFormatStyle` + `"set.weight_compact"` | **the seam**, now unit-aware |
| `WorkoutValueFormatting.weight` — hand-rolled decimal-separator swap | **deleted**; call sites use the seam. A pass-through forwarder was rejected: one name per job |
| `SetSummaryFormatting` — delegated to the first | still delegates, now passing a unit |

`WorkoutValueFormatting` keeps `clock(_:)` only.

The seam's shape splits by what the caller holds, because mixing the two is how a value
gets converted twice:

- `number(_ kilograms:in:)` / `label(_:in:)` / `spokenLabel(_:in:)` take **canonical
  kilograms** and convert.
- `displayNumber(_ display:in:)` / `displayLabel(_:in:)` take a value **already in the
  unit** — a stepper delta, a figure the user just typed — and do not convert, by design.
- `incrementLabel(_ display:in:)` renders a *step* rather than a weight, and deliberately
  ignores the unit's own display precision (see §9).
- `estimateLabel(_ kilograms:in:)` renders a **derived** weight — an Epley 1RM, a PR
  roll-up — rounded to whole display units. `label`'s precision belongs to a weight the
  user *entered*; a computed estimate has arbitrary decimals and would print "137,35 kg" of
  false confidence where the old `%.0f kg` printed "137 kg". It rounds *after* converting,
  so the pound figure comes from the stored kilograms and not from a rounded kilogram one.
- `volume(_ kilograms:in:)` / `volumeParts(_:in:)` render a **tonnage** and own the rollup
  decision (§10). The `Parts` form exists for the chart headline, which styles the number
  and the unit word differently and must not ask twice whether the rollup happened.
- `labelled(_ number:in:)` pairs any preformatted number — a single value, or a range such
  as "40–45" — with the unit word. The one place that pairing is expressed.
- `inputStyle(for:)` hands a `TextField` the same hoisted `static let` style, so no field
  builds its own.
- `unitWord` / `spokenUnitWord` / `unitName` are the only readers of the unit-word keys.

`ProFeatureCaps`-style constants for the grid live on `WeightUnit`: `fractionDigits`,
`fineIncrement`, `coarseIncrement`, `maximumKilograms`, `maximumDisplay`.

### Ticket-02/03 surfaces are pinned, not converted

Every call site outside this ticket's surface list passes `.kilograms` **explicitly**, with
a one-line comment naming the ticket that owns it. Grep `in: .kilograms` and
`unitWord(.kilograms)` for the remaining work. The alternative — a defaulted `unit:`
parameter — was rejected: a silent default on a seam whose entire purpose is to stop unit
drift is the bug this design exists to prevent. Pinned surfaces stay internally consistent
(kilogram numbers next to a kilogram word) instead of half-converted.

Tickets 02 and 03 cleared every pin. **Nothing in `GymStreak/Presentation/` is pinned to
`.kilograms` any more** and no view builds its own `"kg"` string — grep `%gkg`, `%g kg`,
`in: .kilograms` and `unitWord(.kilograms)` to confirm. The two remaining `"… kg"` literals
in `Presentation/` are both inside `#Preview` blocks (`OnyxListRow`, `OnyxProLockOverlay`)
and are sample copy, not user-facing. Tickets 04 (watch) and 05 (coach prompts) own what is
left, and neither goes through this seam.

`EditWorkoutSessionView` (history editing, nominally ticket 03) *is* converted: it shares
`WeightInput`, so its number converts whether or not its ticket has run, and leaving its
label in kg would have been the inconsistency.

**Views read `\.weightUnit`; ViewModels take the protocol.** `WorkoutViewModel` gained
`weightUnitPreference: WeightUnitPreferenceProviding?` by init injection (nil-defaulted,
like `recovery`/`activeWorkout`/`proactivePaywalls`, so unit-test instances read the
canonical kilograms). It needs the unit only for the swap picker's scheme summary — the
call site that forced the Domain fix in §9.

---

## 6. Input: the snapping rule and the ceiling

**Snapping happens in display space, then converts.** `round(value / increment) *
increment` runs on the *displayed* number, so a pounds user gets a 0.5 lb grid rather than
a grid of kilogram boundaries. Increments are per unit:

| | fine stepper | keypad quick-step (±1×, ±2×) |
| --- | --- | --- |
| kg | 0.25 | 2.5 → ±2.5 / ±5 |
| lb | 0.5 | 5 → ±5 / ±10 |

**Accepted consequence, by design:** a set entered in kg and then *edited* in lb mode
re-grids to the lb grid — 100 kg becomes 220.5 lb, i.e. 100.017 kg. That is correct; it is
the user's chosen grid. It must only happen on an actual edit, **never on a mere unit
switch**, which is what the mirror guard below enforces.

**Confirmed on device and deliberately kept (2026-08-27):** the same rule makes the `+`
button read as less than a full step the *first* time it is pressed on a kilogram-seeded
weight. 50 kg displays as 110.2 lb; `+` adds 5 → 115.2312, which snaps to the 0.5 lb grid
→ **115.0**, so the press looks like +4.8. Every press after that is exactly +5 (115 → 120
→ 125), because the value is now on the grid. The product call: a pounds user should end up
on numbers they can load on a bar, so the first press tidying the number is the feature, not
the bug. The rejected alternative — skipping the snap for stepper presses — keeps the
arithmetic exact but leaves every derived weight on 115.2 / 120.2 / 125.2 forever.

**The ceiling is a kilogram magnitude.** `WeightUnit.maximumKilograms = 999`; the
display-space bound is *derived* from it (`maximumDisplay`, 2202.4 lb) rather than a second
literal raised to 2200 in one place and forgotten in the others. `clampedKilograms(fromDisplay:)`
is the single clamp.

### The display mirror — `WeightDisplayMirror`

`WeightInput` and `OnyxWeightStepper` each keep a canonical-kilograms `@Binding` and a
display-space `@State`, and both attach `.weightDisplayMirror(kilograms:displayValue:onUpdate:)`.
The invariant lives in that one `ViewModifier` rather than in each field — an earlier draft
inlined the same four handlers into both, and two copies of a subtle rule drift.

The mirror is **one-directional**: `displayValue` is re-derived from the kilograms on
appear, on an external write, and on a unit switch. `commit(_:)` opens with

```swift
guard newValue != weightUnit.converting(fromKilograms: kilograms) else { return }
```

which is the line that makes "toggle to lb and back to kg and nothing changed" true. A
re-derived mirror carries exactly the canonical value, so it is recognised as not-an-edit
and skipped — without that guard, switching units would snap the derived value to the new
grid and write the re-gridded kilograms straight back to the store. `commit` then snaps in
display space, clamps in kilogram space, re-derives the field (so it never shows a number
the store does not hold), and stores + reports canonical kilograms.

Two details that are easy to get wrong:

- **The write-back is gated on the current canonical value, not on a remembered one.** An
  earlier draft kept a `lastReportedKilograms` and compared against that. Because history
  is not the current value, an edit that snapped back onto the previously reported figure
  after an external write would have been dropped silently, leaving the field showing a
  number the store did not hold — the exact inversion of the invariant. `guard stored !=
  kilograms` has no such hole and needs no state; `commit`'s opening guard already
  terminates the echo.
- **Re-deriving compares the rendered strings, not the magnitudes.** `mirror` assigns only
  when `WeightFormatting.displayNumber` would produce different text, because rewriting a
  `TextField` over a difference nobody can see moves the cursor mid-typing.

  The round trip is *mostly* exact — 225 lb returns bit-for-bit — but not always. Measured
  over the whole 0.5 lb grid up to the 999 kg ceiling, **337 of 4406 values come back
  inexact, worst case 2.3e-13** (at 1134.5 lb); the 0.25 kg grid is comparable at 310 of
  3997. So the dust is real, just rarer than assumed.

  A numeric tolerance of half the last displayed digit was tried first and is **wrong**, on
  two counts. Its justification — "half an increment is the smallest real correction, so a
  half-digit threshold masks nothing" — inverts the fact: half an increment is the *largest*
  snap. Typing `37.502` kg snaps by 0.002 and `100.02` lb by 0.02, both under the
  corresponding 0.005/0.05 threshold, so small genuine corrections were masked. And because
  rounding is a step function, a difference far *inside* any tolerance can still cross a
  rendering boundary: of 200,001 two-decimal pound values, **814 round-trip to a different
  one-decimal string** despite differing by ~1e-13. A magnitude tolerance cannot express
  "would the user see this"; the string comparison is that question, exactly.

  `WeightUnit` was also the wrong home for the judgement — what a field renders is a
  Presentation concern — which is why the discarded `rendersDifferently` no longer exists.

`SetValueKeypadSheet` works entirely in display space — base value, digits, quick steps —
and crosses back to kilograms only in `onSave`.

---

## 7. Localization restructure

The pattern, now binding for every weight string: **the unit word lives in exactly two
keys per form, and every compound format string takes a preformatted weight via `%@`.**

Added (`// MARK: - Units`, before `// MARK: - Workout Set`, identical order in both files):

| key | en | de |
| --- | --- | --- |
| `unit.weight.kg` | kg | kg |
| `unit.weight.lb` | lb | lb |
| `unit.weight.kg.spoken` | kilograms | Kilogramm |
| `unit.weight.lb.spoken` | pounds | Pfund |

The `.spoken` forms exist for VoiceOver — `accessibility.set.label` used to spell out
"kilograms" inline, and a screen reader saying "kay gee" is the alternative. They double as
the Settings picker's labels via `WeightFormatting.unitName`, which applies
`localizedCapitalized` rather than introducing a third pair of keys.

Restructured:

| key | before | after |
| --- | --- | --- |
| `set.weight_compact` | `%@ kg` | `%1$@ %2$@` |
| `set.weight_label` | `Weight (kg)` | `Weight (%@)` |
| `set.planned_detail` | `%d reps × %.2f kg` | `%1$d reps × %2$@` |
| `exercise.assistance.value` | `Assistance: %@ kg` | `Assistance: %@` |
| `exercise.body_weight.input` | `Body weight (kg)` | `Body weight (%@)` |
| `accessibility.set.label` | `Set %d: %d reps, %.2f kilograms` | `Set %1$d: %2$d reps, %3$@` |
| `exercise.detail.set_scheme` | `%d × %d reps · %.1f kg` | `%d × %d reps · %@` |
| `rep_range.current_state` | `Current: %@kg × %d reps (%d sets)` | `Current: %@ × %d reps (%d sets)` |
| `rep_range.new_state` | `New: %@kg × %d reps (all sets)` | `New: %@ × %d reps (all sets)` |
| `rep_range.routine_updated` | `Routine updated: %@kg × %d reps next time` | `Routine updated: %@ × %d reps next time` |
| `configure_exercise.set_detail` | `%d reps • %.1f kg` | `%d reps • %@` |
| `routine_exercise_detail.set_detail` | `%d reps • %.1f kg` | `%d reps • %@` |
| `routine_exercise_detail.weight_label` | `Weight (kg):` | `Weight (%@):` |

Added by ticket 02, both replacing English-only string building in
`PendingRoutineExercise`:

| key | en | de |
| --- | --- | --- |
| `set.reps_range` | `%1$d–%2$d reps` | `%1$d–%2$d Wdh.` |
| `set.weight_range` | `%1$@–%2$@` | `%1$@–%2$@` |

`set.weight_range` carries no unit word: the pair is handed to
`WeightFormatting.labelled`, so a range reads "40–45 kg", not "40 kg–45 kg".

Added by ticket 03 — the rollup words (§10) and the volume delta's missing a11y phrase
(§11):

| key | en | de |
| --- | --- | --- |
| `unit.volume.t` | t | t |
| `unit.volume.thousand` | k | k |
| `history.detail.bw.spoken` | bodyweight | Körpergewicht |
| `history.detail.a11y.delta_up_percent` | up %d percent from last time | plus %d Prozent im Vergleich zur letzten Sitzung |
| `history.detail.a11y.delta_down_percent` | down %d percent from last time | minus %d Prozent im Vergleich zur letzten Sitzung |

Restructured by ticket 03:

| key | before | after |
| --- | --- | --- |
| `history.detail.a11y.delta_up_weight` | `up %@ kilograms from last time` | `up %@ from last time` |
| `history.detail.a11y.delta_down_weight` | `down %@ kilograms from last time` | `down %@ from last time` |
| `paywall.value_moment.figures` | `… %@ sets and %@ kg of volume.` | `… %@ sets and %@ of volume.` |
| `history.detail.bw` (de only) | `KG` | `Körper` |

The two `delta_*_weight` keys are the only ones in the app that had **spelled the unit out**
in the value rather than abbreviating it, which is why they are restructured rather than
merely re-fed: they now take a preformatted *spoken* weight from
`WeightFormatting.spokenLabel`.

Deleted: `set.weight` (`%.2f kg`, dead — no Swift call site); `set.weight_unit` (`kg`, now
redundant with `unit.weight.kg`; its two remaining readers call
`WeightFormatting.unitWord(.kilograms)` until their own ticket converts them); and
`exercise.assistance.input` (`Assistance (kg)`, also dead in both targets — restructuring it
would have left a `%@` nobody fills, which is the trap `set.weight` was deleted to avoid).
Ticket 02 can add it back when an assistance input field actually exists. Its two
`WeightFormatting.unitWord(.kilograms)` stand-ins are gone as of ticket 03: nothing in
`Presentation/` is pinned to kilograms any more.

`.scratch/i18n-foundation/issues/03-migrate-ios-to-string-catalog.md` plans to move these
872 keys into a `Localizable.xcstrings`. The keys above apply unchanged to the catalog.

---

## 8. Surfaces converted

### Ticket 01 — active workout

`WorkoutSetRowView`, `WorkoutExerciseCollapsedRow`, `SetValueKeypadSheet`, the shared
`WeightInput` and `OnyxWeightStepper`, `EditSetView`, `ActiveWorkoutView`'s body-weight
card, and (forced by the shared field) `EditWorkoutSessionView`.

`OnyxWeightStepper` currently has **no production call sites** — only its own `#Preview`.
It was converted rather than deleted because the ticket names it as a surface; if a future
pass wants it gone, nothing references it. Since it shares `WeightDisplayMirror` with
`WeightInput`, keeping it costs no duplicated logic.

`SetValueKeypadSheet` also shed its digit pad into `SetValueKeypad` — the sheet had grown
past the 300-line convention, and "edit one set value" and "type digits into a buffer" are
two jobs. The locale decimal separator now lives on `SetValueKeypad`, which the sheet reads
when it parses the buffer.

### Ticket 02 — routine building and editing

| surface | what changed |
| --- | --- |
| `RoutineSetsEditor` / `RoutineSetStepperRow` | the primary inline set editor. Per-unit step (2.5 kg / 5 lb), display-space field, kg-space ceiling, spoken a11y unit |
| `RoutineExerciseDetailView` | set detail line, weight label, and the bare `TextField` |
| `ConfigureExerciseView` (create-routine flow) | set detail line and the bare `TextField` |
| `ConfigureExerciseSetsView` | the summary strip's planned volume |
| `PendingRoutineExercise.setSummary(in:)` | was a computed property building `"…kg"` with a local `NumberFormatter` |
| `PendingAlternativesSection`, `RoutineAlternativesSection` | alternative set summaries via `SetSummaryFormatting` |
| `RoutineExerciseCardDisplay` | routine card + sorting row summaries (`init(_:in:)`) |
| `ExerciseDetailView` | the "used in routine" scheme line |
| `WeightIncreaseSheet`, `ProgressiveOverloadCard`, `WorkoutOverloadPromptBar` | the whole progressive-overload chain (§9) |

**The two bare `TextField`s are gone.** `RoutineExerciseDetailView` and
`ConfigureExerciseView` each held a `TextField(value:format:)` straight over the stored
kilograms — no unit, no increment, no snapping. Both now use one shared
`WeightValueField`, which wraps `WeightDisplayMirror`. Its mirror state is **private to
each instance** on purpose: sharing one display value across the rows of a collapsible
editor is exactly how a collapsing row's still-live `onChange` handlers write the newly
expanded row's number into the old set (the animation race already documented for these
two screens).

**Deleted, not hoisted:** `PendingRoutineExercise`'s local `NumberFormatter` and
`ProgressiveOverloadCard.formattedWeight` (`String(format: "%g kg", …)`). Neither had a
reason to exist beside the seam.

`PendingRoutineExercise.setSummary` also shed its English-only `"\(setCount) set(s)"` /
`"\(min)-\(max) reps"` string building — the ticket left this optional; it was fixed
rather than left, since the method was being rewritten anyway and the localized keys for
both halves already existed or were one line away.

`RoutineSetsEditor.swift` crossed the 300-line convention once its row learned to convert,
so `RoutineSetStepperRow` moved into its own file — "one set row" and "the set list plus its
apply-to-all banner" are two jobs. Same treatment `SetValueKeypadSheet` got in ticket 01.

**One Swift 6 trap worth remembering:** `Binding(get:set:)`'s setter is `@Sendable`, so
handing it a stored non-`Sendable` closure property (`set: onWeightChange`) warns —
"converting non-Sendable function value to '@isolated(any) @Sendable (Double) -> Void'". A
closure *literal* (`set: { onWeightChange($0) }`) is main-actor-isolated under SE-0461 and
compiles clean. The warning only surfaced once the file was actually recompiled, which an
incremental build had been skipping: **force recompilation of every touched file before
claiming zero warnings.**

**Two dead views were converted rather than deleted**, following ticket 01's precedent with
`OnyxWeightStepper`: the whole of `RoutineExerciseDetailView` (no navigation destination
references it anywhere) and `SetRowView` inside it (no call sites at all). The ticket names
both as surfaces; nothing references them if a later pass wants them gone. `SetRowView`
still carries unlocalized English (`"Set \(id.prefix(8))"`, `"reps"`, `"rest"`) — out of
scope here, and moot while it is unreachable.

### Ticket 03 — history, charts, PRs and volume

The read-only half, and the largest single block of duplicated formatting the app had.

| surface | what changed |
| --- | --- |
| `WorkoutCardView`, `WeekHeroView`, `WorkoutDetailView`, `HistoryCalendarView`, `TrainingsTabView` | eight duplicate volume formatters collapsed into `WeightFormatting.volume` (§10) |
| `PeriodRecapView`, `CoachEntryCard`, `ProactivePeriodPromptCard` | the same, for the coach recap cards' volume figures |
| `PRRecordStrip` | local `formatKg` deleted; the PR set takes `label`, the two Epley figures take `estimateLabel` |
| `WorkoutDetailExerciseBlock` | the per-set grid, the comparison strip, and the delta chip's accessibility phrasing (§11) |
| `RecentUsageCardView` | the best-set line and the per-set chips, whose unit word was a literal `Text("kg")` |
| `ExerciseProgressChartView` / `ExerciseProgressViewModel` | the plotted series, the y-axis domain, the headline, the tap annotation and all three stat-card PR figures |
| `ProPaywallView` | the value-moment figure (§10, the one deliberate exception to the rollup) |
| `MetricInfoPopover` | **no change needed** — all three `chart.metric.*.description` values were already unit-neutral in both languages. The ticket expected an Epley rewrite; the copy says "the maximum weight you could lift once … (weight × (1 + reps ÷ 30))", and the Epley formula is linear, so it holds in pounds unchanged. Verified rather than assumed. |

**`WorkoutCardView` takes the unit as a value, not from the environment.** It is
`Equatable` so SwiftUI can skip unchanged rows, and an `@Environment` property would both
break the synthesized `==` and leave it blind to a unit change — the row would keep its old
number under a new unit word. Its two list parents read `\.weightUnit` once and pass it
down. This is the shape rendering rule 4 asks for anyway: a row takes values.

**The chart's series and its y-scale convert together, in the ViewModel.** `ChartSeries`
(`Presentation/Helpers/ChartSeries.swift`) holds the points in *display* space together with
the y-domain derived from those same converted numbers. It sits in `Presentation/` rather
than beside `ExerciseProgressData`: putting a kilograms→pounds conversion in `Domain/Models/`
would be the same leak that removing `ProgressMetric.unit` was meant to close, and the
review of this slice caught the first draft doing exactly that. `ProgressChartContent` no longer receives `ExerciseProgressData` at all, only the
series and the metric's *name*. Two defects made this necessary rather than tidy:

- converting the marks without converting `chartYScale(domain:)` would draw a pound line
  against a kilogram scale — clipped, and silently;
- `yDomain` used to be a computed property read **from inside the `ForEach` that drew the
  points** (`AreaMark`'s `yStart`), so it mapped over the whole series once per point.
  Adding a `Measurement` conversion in there would have multiplied an already O(n²) read.

The canonical `ExerciseProgressDataPoint` travels inside each `ChartSeries.Point`, so a tap
hands the **unconverted** point back and the annotation is formatted from kilograms like
every other weight in the app.

`chartSeries` is rebuilt after a load, from `selectedMetric`'s `didSet`, and on
`.onChange(of: weightUnit)`. Each of the three earns its place:

- **the unit change** is not part of `loadKey`, so a trip to Settings and back would
  otherwise leave the plotted line in the old unit under a relabelled axis. Nothing is
  refetched — only the conversion is redone.
- **`didSet` rather than `updateMetric(_:)`** keeps the cache correct for *any* writer,
  including the title tests that deliberately force selections the picker would refuse, and
  a future `$selectedMetric` picker binding. `private(set)` was the alternative and is
  worse: it makes access control carry an invariant that a one-line `didSet` states
  directly.
- **the rebuild also re-derives `selectedDataPoint`.** The tap annotation's figure is a
  *string*, formatted once at selection time, so without this a tapped point keeps reading
  "100 kg" over a converted line — the same mismatch one property further out. It is
  re-derived from the canonical point, never from the rendered string.

`ProgressMetric.unit: String` returned the literal `"kg"`, which made `Domain/` the layer
that decided the user's unit. It is `ProgressMetric.quantity: ProgressQuantity`
(`.weight` / `.volume`) now, and Presentation resolves the word — the same discipline
ticket 02 applied to `RoutineMetricsService`. The two cases are both masses; they differ in
*magnitude*, which is exactly what decides whether the display rolls up.

`formatCompactValue`'s `1.2k` / `3.5M` thresholds were suspected of being kilogram-scaled.
They are not — they are magnitude-based, so 27 563 lb compacts to "27.6k" exactly as
12 500 kg compacts to "12.5k". What did have to change is *who* it formats for. Its `unit:`
suffix parameter is **deleted**: its one remaining caller is the chart's unit-less y-axis,
and a unit word coming out of `Domain/` is the decision that removing `ProgressMetric.unit`
took out of it.

The tap annotation no longer routes a single load through it either. Compaction is right for
a tonnage and wrong for one load, and the ≥1000 branch — unreachable behind the 999 kg
ceiling — becomes reachable above ~454 kg once converted: a 500 kg sled set would have
annotated "1.1k lb" while the headline read "1102.3 lb" for the same point. A `.weight`
annotation takes `WeightFormatting.label` now, so it agrees with the headline by
construction. Found in review, not on screen.

**`ExerciseProgressViewModel` takes `WeightUnitPreferenceProviding` by init injection**
(nil-defaulted, like `WorkoutViewModel`'s), per Hard rule 2 — it formats weights, so it may
not reach for `.shared`. The chart view's outer wrapper passes
`dependencies.weightUnitPreference` through; a test instance injects nothing and reads the
canonical kilograms.

**All volume, Epley-1RM and PR math still runs in kilograms.** `Models.swift`,
`ExerciseLoadMetrics`, `HistoryStatsService`, `LifetimeTotalsAggregator` and
`ExerciseProgressModels`' aggregation are untouched, and
`LifetimeTrainingTotals.volumeKilograms` keeps its name because it is accurate. The set
delta is the one place worth stating explicitly: the **difference** of two canonical
kilogram values is converted, never a difference of two converted numbers.

---

## 9. Progressive overload: a parallel pound grid, and the Domain-layer leak

### The pound increments are real plate steps, not converted kilograms

`ProgressiveOverloadIncrement` used to be one kilogram grid: presets `[0.5, 1.25, 2.5, 5]`,
default 2.5, free selection `0.25…50` by 0.25. Converting those numbers to pounds gives
**1.1 / 2.76 / 5.51 / 11.02 lb** — nonsense on a plate rack. A pounds user gets a parallel
grid of the steps their gym actually stocks:

| | presets | default | free selection |
| --- | --- | --- | --- |
| kg | 0.5, 1.25, 2.5, 5 | 2.5 | 0.25 … 50, stride 0.25 |
| lb | 1.25, 2.5, 5, 10 | 5 | 0.25 … 100, stride 0.25 |

The grid is **selected by unit, never converted**, and both grids live in one
`grid(for:)` switch so a change to one is read against the other. The stride stays 0.25 in
both units because that is what keeps the 1.25 micro-plate exactly on the grid — at a 0.5
stride `normalized(1.25)` would snap to 1.5 and the picker could never highlight the
preset. `normalized(_:in:)` is unit-aware for the same reason. A test asserts the two
grids do **not** coincide with the converted kilogram list.

**1.25 renders as "1.25" in pounds too.** Pound *weights* keep one fraction digit (§4), so
the pound weight style would round a 1.25 lb step to "1.3" — the same class of bug as
`%.2g` rendering it "1.2". The seam therefore formats a step by what it is rather than by
its unit: `WeightFormatting.incrementLabel` uses its own `fractionLength(0...2)` style.

**The conversion happens exactly once**, in `WeightIncreaseSheet`'s apply button:
`onApply(weightUnit.kilograms(fromDisplay: increment))`. Everything below that line —
`ProgressiveOverloadService`, `RoutinesViewModel.applyProgressiveOverload`,
`WorkoutViewModel.applyProgressiveOverload(…)` and
`applyProgressiveOverloadFromHistory(…)` — keeps taking canonical kilograms and needed no
change. The sheet computes every number it *shows* in display space instead, so the
arithmetic the user reads adds up exactly ("198.4 + 5 = 203.4") rather than drifting
through a conversion.

`selectedIncrement` became `Double?`: the default is per-unit, so it cannot be resolved at
initialization, before the environment exists. Nil means "the current unit's default".

**Watch drift, deliberate and time-boxed — with a user-visible consequence.** The watch
keeps its own copy of `ProgressiveOverloadService.swift`, still carrying the kilogram-only
`ProgressiveOverloadIncrement` (flat `options`/`default`/`minimum`/`maximum`/`step` and
`normalized(_:)`). Until ticket 04 ships, **a pounds user gets kilogram plate steps on the
watch** — the picker offers 0.5/1.25/2.5/5, and they are kilograms whatever the phone says.
The two test suites therefore assert *different contracts for the same type name*
(`GymStreakTests/ProgressiveOverloadServiceTests.swift` vs
`GymStreakWatchTests/ProgressiveOverloadServiceTests.swift:140-163`), which is precisely the
copy-drift trap CLAUDE.md warns about — recorded here so ticket 04 closes it deliberately
rather than discovering it. Both copies' doc comments say so too.

### The Domain-layer leak

`RoutineMetricsService.setSchemeSummary` appended `" · \(String(format: "%gkg", weight))"`
— the Domain layer emitting a localized unit word, and a kilogram one at that, two lines
below its own comment saying "formatting strings are provided by the caller so the Domain
layer stays localization-free".

The fix moves the formatting **out**, matching how `uniformSetScheme` already hands back
raw values: the method now takes `formattingWeight: (Double) -> String`. Its one caller,
`WorkoutViewModel.setScheme`, passes `WeightFormatting.label(_:in:)` with the injected
unit.

Rejected: passing a `WeightUnit` into the service and formatting there. That relocates the
violation instead of fixing it — Domain would still be reaching for `Localizable.strings`.

---

## 10. The tonnage rollup

Eight near-identical helpers each decided this on their own — "over 1000 → `%.1ft`, else
`%.0fkg`" — in `WorkoutCardView`, `WeekHeroView`, `WorkoutDetailView`,
`HistoryCalendarView`, `TrainingsTabView`, `PeriodRecapView`, `CoachEntryCard` and
`ProactivePeriodPromptCard`. One had already drifted to `%.0ft`. They were folded into
`WeightFormatting.volume` **before** anything was converted, so the rounding decision was
made once instead of eight times.

**The decision.** Kilograms roll up to the metric tonne at 1 000 kg, as before. Pounds roll
up at 1 000 *displayed* pounds onto a magnitude prefix over the real unit:

Real output, 400 kg and 12 500 kg of volume (English locale):

| | below the rollup | at or above 1 000 |
| --- | --- | --- |
| kg | `400 kg` | `12.5 t` — the unit *word* changes |
| lb | `882 lb` | `27.6k lb` — the *number* takes a prefix, the word stays "lb" |

The rolled figure always carries exactly one decimal, so 1 000 kg reads `1.0 t` and a
lifetime 250 000 kg reads `250.0 t`. That is the pre-consolidation `%.1ft` behaviour kept
deliberately: varying the precision by magnitude is a decision nobody asked for.

**The prefix goes on the number, not into the unit word.** `unit.volume.klb = "k lb"` was
the first shape, and the shared `set.weight_compact` (`"%1$@ %2$@"`) rendered it
"27,6 k lb" with an orphaned "k". So pounds keep `unit.weight.lb` and the rolled number
carries `unit.volume.thousand` ("k") — which is also how `formatCompactValue` already
writes the chart axis.

The threshold is applied **after** conversion, so each unit rolls at 1 000 of its own
numbers and the two paths keep the same shape and the same digit count. A consequence to
expect: 500 kg is below the threshold as kilograms and above it as pounds, so the same
session reads `500 kg` or `1,1k lb`. That is correct — the rollup is a property of the
number on screen.

**Why not the alternatives.** Pounds have no natural rollup unit, which is the whole
problem:

- **Short tons (2 000 lb, "tn")** — rejected. The abbreviation sits one letter from the
  tonne, US lifters do not talk in short tons, and German has no sensible word for it, so
  the German build would have carried an English abbreviation for an American unit.
- **Metric tonnes for a pounds user ("0,5 t")** — rejected. It mixes measurement systems on
  the user's own numbers, which is exactly the confusion this feature exists to remove.
- **No rollup at all** — rejected. A lifetime figure runs to seven digits; the history
  cards and the week hero render volume in a small metric tile beside two other numbers.

`k` is a magnitude prefix, not a unit from another system, so it cannot be misread as
metric. It is also already the app's vocabulary: `formatCompactValue` labels the chart axis
`1.2k` / `3.5M`.

**Consequences accepted.** Below the threshold the figure now carries the unit word with a
space (`847 kg`, from the shared `set.weight_compact`) where the old helpers wrote
`847kg`. And `TrainingsTabView`'s month summary gains a decimal — it was the one site using
`%.0ft` — which is the convergence the consolidation is for.

**One deliberate exception.** `ProPaywallView`'s value-moment figure does *not* go through
`volume`. It is §8 B endowed progress inside a sentence ("You've logged 12 workouts, 148
sets and 24 300 kg of volume"), where the large grouped number is the point; a rolled-up
"24,3 t" would shrink the very figure the placement exists to show. It keeps its hoisted
`NumberFormatter` and only attaches the unit word through `WeightFormatting.labelled`, so
the *unit* is still resolved in one place.

---

## 11. The accessibility substring landmine

`SetDeltaChip.Delta` carried only a formatted label — `.gain("+2,5 kg")` — and recovered
everything else from that string:

```swift
case .gain(let s):
    return s.contains("kg")                       // weight, or reps?
        ? …delta_up_weight, numericPart(of: s)     // strips "kg" back out
        : …delta_up_reps,   numericInt(of: s)
```

Two bugs, both build-green and test-green:

1. **In pounds the label reads `+11 lb`**, `contains("kg")` is false, and VoiceOver
   describes a weight increase as a rep increase. Nothing crashes, nothing warns, and no
   sighted check catches it.
2. **A volume delta's label is a percentage** (`+15%`). It never contained "kg" either, so
   it already took the rep branch, and `Int("15%")` returned nil → `0`. VoiceOver has been
   reading a 15% volume gain as *"up 0 reps from last time"*.

**Fix: the kind is passed, not parsed.** `Delta.Quantity` is
`.weight(spoken:)` / `.reps(Int)` / `.percentage(Int)`, decided at construction where the
type is actually known. `.weight` carries the spoken form of its own figure
("2,5 kilograms"), so the phrase never has to reconstruct a number from a display string.
`numericPart(of:)` and `numericInt(of:)` are deleted. Two new keys —
`history.detail.a11y.delta_up_percent` / `_down_percent` — give the volume delta the phrase
it never had, and the unit word moved out of `delta_up_weight` / `_down_weight` (which
spelled "kilograms" into the value) and into `unit.weight.*.spoken`.

**Adding `"lb"` to the substring check was rejected explicitly.** It keeps a display string
as the source of truth for a semantic decision, leaves the percentage case broken, and
breaks again the next time a unit or a delta kind is added.

The per-set cell got the same treatment one level up: the visible chip reads
`WeightFormatting.label` ("60 kg") while the accessibility value reads
`WeightFormatting.spokenLabel` ("60 kilograms"). A screen reader saying "kay gee" is why
the spoken keys exist.

**The bodyweight marker was a unit collision too.** `history.detail.bw` renders in the same
cell as every converted weight, and its German value was `"KG"` — *Körpergewicht*, and
indistinguishable from kilograms. Pre-existing, but this feature is what made it actively
wrong: a pounds user saw `KG` sitting beside `49,6 lb`. It is `"Körper"` now (`"BW"` in
English, which never collided), and it gained the spoken form every other abbreviation on
this screen has — `history.detail.bw.spoken`, so VoiceOver says "Körpergewicht" rather than
spelling the abbreviation out.

---

## 12. Tests

`GymStreakTests/WeightUnitTests.swift` (Swift Testing, `@MainActor`):

- kg↔lb round trip **from the canonical kilograms**, across 0…999 kg
- Foundation's pound coefficient asserted directly (see §3)
- locale default mapping, including the `.uk` → kg product call, plus an assertion that
  `.uk` and `.us` are distinguishable at all
- per-unit precision rendering: no trailing `.0`, per-unit fraction digits, no grouping
- grid snapping in display space, and that a pound grid is *not* a kilogram grid
- the ceiling enforced in kilogram space, and the display bound derived from it
- the preference store: first-launch seeding, write-through, never re-seeded on a later
  launch in a different locale, and an unrecognised stored value falling back

The store's `init(defaults:locale:)` is injectable specifically so the "never re-seeded"
rule can be tested against a throwaway suite rather than the device's real defaults.

plus round-trip dust rendering identically while a real correction does not.

`GymStreakTests/ProgressiveOverloadServiceTests.swift` (ticket 02):

- `normalized(_:in:)` clamps and snaps in **both** units
- every preset of every unit lands exactly on that unit's stride, and each unit's default
  is one of its own presets
- the pound presets are not the converted kilogram list — the test that would have caught
  "just convert the numbers"
- a 1.25 step still renders both decimals in pounds, where the weight style would round it

`GymStreakTests/RoutineMetricsServiceTests.swift` (ticket 02): `setSchemeSummary` renders
its weight through the caller's closure and emits no unit word of its own, and never calls
the formatter for a bodyweight or pyramid scheme.

`WeightUnitTests.swift`, added by ticket 03 for the volume formatter (§10):

- a tonnage below the rollup carries the plain unit word and no decimals
- kilograms roll up to the tonne, and **exactly** at 1 000 (999 does not)
- a rolled pound figure keeps `unit.weight.lb` and is **not** the tonne word — the assertion
  that would catch "just show tonnes to everyone" — while the prefix rides on the number
- the threshold is applied in *display* space: 500 kg rolls as pounds and not as kilograms,
  which deciding before conversion could not produce
- a tonnage is converted, so the two units differ by their **numbers** and not only by
  their unit words
- `volume` contains exactly the `volumeParts` it was built from, across both units and both
  sides of the threshold — the number and the word cannot disagree about the rollup
- `estimateLabel` rounds to whole display units where `label` does not, and rounds *after*
  converting

`GymStreakTests/ChartSeriesAxisTests.swift` (ticket 03) guards the axis rule: a narrow
domain above 1000 yields distinct labels in both the pounds and the kilograms case, a wide
one still compacts, and a domain under the threshold renders exactly as before.
`WeightUnitTests` gained the matching pair for the shared rollup — two related volumes carry
the same unit word under one decision, and the same two carry *different* ones when each
decides for itself, which pins why the overload exists.

`GymStreakTests/SetDeltaAccessibilityTests.swift` (ticket 03) guards §11, which no build and
no sighted check can catch:

- a pounds weight delta is spoken in *pounds* and never mentions kilograms
- a weight delta's phrase differs from a rep delta's — **this equality is the old defect**,
  since `label.contains("kg")` was false for "+11 lb" and chose the rep phrasing
- a volume delta is described as a percentage, not as "up 0 reps"
- the visible label carries the chosen unit and its converted magnitude
- a negligible change is neutral in both units

`ExerciseProgressStatCardTests`'s two `personalRecordString` expectations moved from the
literal `"90.0 kg"` to `WeightFormatting.label(90, in: .kilograms)`: the seam drops a
trailing zero and takes its unit word from `unit.weight.*`. Asserting through the seam
rather than re-hardcoding the new literal keeps the test about the *stat card* instead of
about the formatter, which has tests of its own.

**Not unit-tested:** the mirror in §6 is view state, so "toggle units and nothing changed"
rests on `commit`'s opening guard plus the on-device check, not on a test. That covers the
routine set editor too, which now goes through the same modifier.

**Verification (ticket 03):** the iOS app, the widgets extension and the watch app all built
clean with zero first-party warnings, and `GymStreakTests` ran **961 Swift Testing tests in
107 suites** with only the known `CloudSyncObserverCoalescingTests` flake — confirmed
pre-existing by stashing this ticket's changes and reproducing the same failure on the
unmodified tree. The four suites this slice touches (`WeightUnitTests`,
`SetDeltaAccessibilityTests`, `ExerciseProgressStatCardTests`,
`ExerciseProgressMetricTitleTests`) pass 43/43 in isolation. The watch suite was not run — no
watch code was touched.

The formatter's real output was read off a throwaway probe rather than inferred: `0 kg`,
`400 kg`, `847 kg`, `999 kg`, `1.0 t`, `12.5 t`, `250.0 t`; `882 lb`, `1.1k lb`, `27.6k lb`,
`551.2k lb`; `estimateLabel(137.35)` → `137 kg` / `303 lb`; a 5 kg gain in pounds →
`+11 lb` / *"up 11 pounds from last time"*; a 15% volume gain → *"up 15 percent from last
time"*.

**On device (2026-08-27, German locale, both units).** The chart in pounds
(`44,1 lb` headline with the number and word in separate type styles, `REKORD` agreeing, a
unit-less `30…45` axis, the line inside its padded domain), the tap annotation
(`52,9 lb` — unit *and* decimal), the volume metric in kilograms (`340 kg`, axis `280…340`,
no lb figure surviving under a kg label), and the workout-detail set grid in kilograms
(`30 kg`, `21,5 kg`, `Top ↑ +1 kg`, `Volumen ↓ −6%`) all render correctly.

**Two defects the pass caught, both fixed:**

- **The chart's PR stat card disagreed with its own headline.** `REKORD 53 lb` sat directly
  above `GESCH. 1RM 52,9 lb`. `estimateLabel` had been applied to the `.estimated1RM` stat
  card on the reasoning that it *is* an estimate — but that card's prior format was
  `%.1f kg`, not `%.0f`, and unlike the history PR banner it has a visual neighbour to agree
  with. Whole-unit rounding is the banner's alone. `.maxWeight` and `.volume` were already
  consistent, which is what made the diagnosis unambiguous.
- **The set cell could wrap.** The shared `set.weight_compact` adds a space, so `21,5kg`
  became `21,5 kg` in a box whose width is the screen divided by the set count, up to six. At
  six sets that box is ~47pt inside its padding and the string measures more, so it would
  have wrapped and made one grid row taller than its neighbours. Already over budget before
  the space, so not a regression — but this ticket lengthened the string, so the cell carries
  `.lineLimit(1).minimumScaleFactor(0.8)` now.

A second pass closed both remaining gaps. The **`k lb` rollup** is confirmed on Shoulder
Press — `504 kg` in kilograms, `1,1k lb` in pounds, i.e. the same session rolling in one unit
and not the other, which is the display-space threshold visible on screen — and on Inclined
Flying (`1,1 t` / `2,4k lb`). The **six-set grid** is confirmed in both units: six
`22,5 kg` / `49,6 lb` cells on one line at uniform height, PR banner reading
`Neuer Rekord: 49,6 lb × 11` over `gesch. 1RM 68 lb`, and the workout volume tile rolling to
`1,2 t` / `2,6k lb`.

It also found two more defects, both fixed:

- **Two related volumes in different units.** `REKORD 1,1 t` directly above
  `GESAMTVOLUMEN 960 kg` — a 1080 kg window record and a 960 kg latest value, each deciding
  its own rollup. They are adjacent so they can be compared, and in different units they
  cannot be. The decision is now taken **once per screen from the window's largest volume**
  (by definition the record, so it also covers the headline and the annotation) and passed
  through `volumeParts(_:in:rolledUp:)`. The old code never hit this: neither figure rolled,
  both were plain `%.0f kg`.
- **A y-axis printing one label on every gridline** — four rows of `1,1k` in pounds,
  `1,1k / 1,1k / 1k / 950` in kilograms. `formatCompactValue` resolves to 100 units once it
  compacts, so a narrower domain collapses. Pre-existing, and routine once pounds multiply
  every volume by 2.2. `ChartSeries` now decides from its own domain span whether compaction
  survives and falls back to plain integers when it does not.

The device screen-reader pass was waived by the user; `SetDeltaAccessibilityTests` is the
standing evidence for §11.

**All four fixes re-confirmed on device (2026-08-28):** `REKORD 1,1 t` over a `1,0 t`
headline (one unit, not two); the axis reading `1100 / 1050 / 1000 / 950` where it printed
`1,1k` twice; `REKORD 52,9 lb` over a `52,9 lb` headline (matching precision, was `53 lb`);
and `Körper` in the bodyweight cells beside `49,6 lb`, where nothing about it can be read as
a unit any more.

**A consequence of the shared rollup, accepted:** a sub-threshold value forced to roll up
with its record loses precision — 960 kg renders `1,0 t` rather than `960 kg`. One decimal of
tonnes carries ±50 kg of rounding whatever the value, and the alternative was two adjacent
figures in different units, which is what this fixed. The y-axis beside it is unrolled and
gives the exact magnitude.


**Verification (ticket 02):** re-run after the review fixes and after the
`RoutineSetStepperRow` extraction, not before them. iOS app, widgets extension and watch
app build clean with zero first-party warnings, every changed file force-recompiled;
`GymStreakTests` runs 917 Swift Testing tests plus 4 XCTest tests, all green.

`CloudSyncObserverCoalescingTests` flaked in two intermediate runs of this work. It was
**not** caused by it: with the changes stashed, the same suite fails the same way on an
unmodified HEAD under the full run, and passes in isolation on both. It is timing-sensitive
around the sync-coalescing window. Recorded here so the next person does not re-diagnose it.

The watch suite was not run: no watch code was touched (ticket 04 owns watch parity).

**On device (2026-08-27, German locale, Pounds):** all seven checks passed — the set editor
and its 5 lb steps, the kg→lb→kg round trip leaving stored weights untouched, the
create-routine flow and its pending summary, the collapsible editor's row-switch isolation,
the overload sheet's pound presets, the planned volume (600 lb), and the swap picker's
`"Lats · 3×8 · 93,7 lb"` — the Domain-leak fix rendering in the user's unit.

**Read test results per test, not from `xcodebuild -quiet`'s summary.** During this work a
`-quiet` run printed a "Failing tests:" list naming only an unrelated flaky suite while
`WeightUnitTests.poundsUseFoundationsCoefficient` was in fact red — the assertion compared a
pound value against a kilogram-derived expectation and was wrong by the conversion factor
itself. Grep the per-test `✔`/`✘` lines (or `Test run with N tests`) instead.
