# Weight unit preference (kg / lb)

**Status:** ticket 01 of 05 shipped — the unit type, the preference store, the Settings
picker, the formatting seam and the active-workout surfaces. Tickets 02–05 route the
remaining surfaces (routine building, history/charts/PRs/volume, watch parity, AI coach)
through the seam built here.

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
- `displayNumber(_ display:in:)` takes a value **already in the unit** — a stepper delta,
  a figure the user just typed — and does not convert, by design.
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

Pinned today: `SetSummaryFormatting` (one file-local constant covering the three routine
card/alternative call sites), `RoutineSetsEditor` (unit word + spoken a11y label),
`ConfigureExerciseView`, `WeightIncreaseSheet`, `ConfigureExerciseSetsView` (volume).

`EditWorkoutSessionView` (history editing, nominally ticket 03) *is* converted: it shares
`WeightInput`, so its number converts whether or not its ticket has run, and leaving its
label in kg would have been the inconsistency.

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

Deleted: `set.weight` (`%.2f kg`, dead — no Swift call site); `set.weight_unit` (`kg`, now
redundant with `unit.weight.kg`; its two remaining readers call
`WeightFormatting.unitWord(.kilograms)` until their own ticket converts them); and
`exercise.assistance.input` (`Assistance (kg)`, also dead in both targets — restructuring it
would have left a `%@` nobody fills, which is the trap `set.weight` was deleted to avoid).
Ticket 02 can add it back when an assistance input field actually exists.

`.scratch/i18n-foundation/issues/03-migrate-ios-to-string-catalog.md` plans to move these
872 keys into a `Localizable.xcstrings`. The keys above apply unchanged to the catalog.

---

## 8. Surfaces converted in this ticket

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

---

## 9. Tests

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

**Not unit-tested:** the mirror in §6 is view state, so "toggle units and nothing changed"
rests on `commit`'s opening guard plus the on-device check, not on a test.

**Verification:** iOS app, widgets extension and watch app build clean (only the
pre-existing RevenueCat `paywallComponents` deprecation and asset trait-set warnings);
`GymStreakTests` runs 938 tests in 104 suites, all passing. The watch suite was not run —
no watch code was touched (ticket 04 owns watch parity).

**Read test results per test, not from `xcodebuild -quiet`'s summary.** During this work a
`-quiet` run printed a "Failing tests:" list naming only an unrelated flaky suite while
`WeightUnitTests.poundsUseFoundationsCoefficient` was in fact red — the assertion compared a
pound value against a kilogram-derived expectation and was wrong by the conversion factor
itself. Grep the per-test `✔`/`✘` lines (or `Test run with N tests`) instead.
