# Workout history import (Strong and Hevy CSV)

**Status:** Strong shipped 2026-10-03 (`.scratch/positioning-usp/issues/01`). Hevy built
2026-10-10 (`.scratch/positioning-usp/issues/02`) as a second format on the same pipeline (§2b, §7),
and device-verified with a real export on 2026-10-17.
**Strategy:** `docs/acquisition-strategy.md` lever **#16**; research in
`docs/research/positioning-usp-2026-10.md` §3.2.

---

## 1. What it does

A user who exported their data from Strong or Hevy opens **Settings → Import → Import from Strong**
(or **Import from Hevy**), picks the CSV with the system document picker, and sees a preview:

- a **period** to import. Presets are Everything / Last month / Last 3 months / Last year, with
  From and To date pickers for a custom range (§3b). Every count below is for the selected period;
- the number of workouts;
- how many were already imported earlier (these are skipped);
- how many distinct exercise names match the library, how many will be created as custom
  exercises, and the list of those new names;
- how many cardio sets are left out, and (Hevy) how many warm-up sets;
- a **kg / lb** choice for the file's weights (Strong only: Hevy's header names the unit);
- when there are unmatched names, a toggle **"Add new exercises to your library"** (on by
  default). See §3a.

**Import** writes the workouts and shows a progress bar, then a summary: workouts imported, already
in history (skipped), custom exercises created, cardio sets skipped. **Cancel** at any point before
Import writes nothing. Imported workouts show up in History, the Fortschritt charts, PRs and every
other consumer of history exactly like workouts logged in the app, because they are ordinary
`WorkoutSession`s.

**Platform:** iOS only. The watch is not involved. It never reads history, and new custom
exercises reach it through the normal exercise-catalog sync (`requestCatalogSync()` after an import
that created any).

**Monetization: Free.** §3 Rule 4: it is the user's own logged data. No cap, no placement, no
Pro badge. A cap would defeat the feature's only purpose, which is removing the switching cost.
Re-checked at completion: what shipped is entirely ungated. Recorded in
`docs/monetization-strategy.md` §4.1.

---

## 2. Strong's format

One row per set. The classic header is

```
Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,RPE
```

Newer exports add `Workout #`, `Notes` and `Workout Notes`, and suffix units onto columns
(`Weight (kg)` / `Weight (lbs)`, `Duration (sec)`, `Distance (meters)`). The parser
(`StrongCSVParser`) therefore looks columns up **by header name** first.

**Strong localizes the header into the app language** but keeps the classic column order. A
German export starts
`Datum,Workout-Name,Dauer,Name der Übung,Reihenfolge festlegen,Gewicht,Wiederh.,Entfernung,Sekunden,Notizen,Workout-Notizen,RPE`.
A header without the English `Date` column therefore falls back to the **classic order** (Date,
Workout Name, Duration, Exercise Name, Set Order, Weight, Reps, Distance, Seconds, [Notes, Workout
Notes,] RPE). The fallback is accepted only when the header has 10–12 columns **and** the first data row has a Strong timestamp
in the date slot and numbers in the weight and reps slots. Any language therefore parses without an
alias table, and a reordered English export is not silently read by position.

> **Root cause, 2026-10-10:** the first real export tested (German, 135 workouts) was rejected as
> "not a Strong export", because v1 matched English header names only. The same file exposed two more
> v1 bugs that no synthetic fixture had: durations written `43min` / `1h 5min` parsed as 0 (only `m`
> was understood), and rest-timer rows labelled `Ruhezeit` were counted as cardio, because only the
> English `Rest Timer` was recognised. The regression test `localizedHeader` uses rows copied
> verbatim from that file. **Lesson:** never assume an export format from documentation or memory.
> Profile a real file first.


| Column | Required | Handling |
|---|---|---|
| `Date` | ✓ | `yyyy-MM-dd HH:mm[:ss]`, wall-clock time in the device's time zone (Strong writes local time with no zone). |
| `Workout Name` | ✓ | → `WorkoutSession.routineName`. |
| `Exercise Name` | ✓ | Matched to the library (§3). |
| `Set Order` | ✓ | Only used to skip rest-timer rows: a value that is neither a number nor a single letter (`Rest Timer`, `Ruhezeit`, … in any language). Set order in history is file order. Letter-marked sets (`W`/`D`/`F`, warm-up/drop/failure) import as ordinary sets. |
| `Weight…` | ✓ | Decimal comma accepted. The header's `(kg)`/`(lbs)` suffix, when present, **preselects** the unit picker. The user still decides. Negative values (assisted exercises in some exports) are stored as their absolute value. |
| `Reps` | ✓ | Rounded to an integer. |
| `Duration…` | – | `1h 5min`, `43min`, `45m`, `30s` (unit read by its first letter h/m/s), or plain seconds → `endTime = startTime + duration`. Missing or unparseable → `endTime == startTime`. The session still counts as completed. |
| `Distance…`, `Seconds` | – | Only used to recognise cardio rows. |
| `Workout Notes` | – | First non-empty value → `WorkoutSession.notes`. |
| `RPE`, `Notes` | – | Ignored. History has no field for them, and this feature adds no schema change. |

**CSV dialect** (`CSVTableReader`, format-agnostic): RFC 4180 quoting (embedded delimiters, line
breaks and `""` escapes), UTF-8 BOM stripped, `\n` or `\r\n`. The delimiter is `;` when the header
has more semicolons than commas (European-locale exports, whose decimals then use commas), else `,`.
It tokenizes UTF-8 bytes rather than `Character`s, because grapheme iteration over a multi-megabyte
file is slow and every structural character is ASCII.

**Validation boundary:** the header. Without the six required columns the file is "not a Strong
export". A data row that cannot be parsed (bad date, non-numeric weight/reps, missing exercise name,
too few fields) fails the **whole** file with its line number. Both happen before anything is
written. A file whose rows are all cardio or empty is "no strength sets to import".

---

## 2b. Hevy's format

`workout_data.csv`, from Hevy → Settings → Export & Import Data. One row per set:

```
"title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe"
"Morning workout","22 Dec 2025, 08:00","22 Dec 2025, 08:37","","Leg Press (Machine)",,"",1,"normal",90,12,,0,7.5
```

Accounts set to pounds export `weight_lbs` and `distance_miles` in the same positions. The parser
(`HevyCSVParser`) looks columns up by header name. It needs `title`, `start_time`,
`exercise_title`, `weight_kg`/`weight_lbs` and `reps`; anything else missing only disables what
that column feeds. Without those columns the file is "not a Hevy export". A bad row fails the whole
file with its line number, as for Strong. The source is chosen by the entry point and never
auto-detected, because each needs its own export instructions. A Strong file in the Hevy flow (or
the reverse) is therefore rejected.

| Column | Handling |
|---|---|
| `title`, `start_time` | Workout identity and name. Rows group into workouts by `(start, title)`, as Strong does. |
| `start_time`, `end_time` | `22 Dec 2025, 08:00`. The day is not always zero-padded, there are no seconds, and the time is wall-clock in the device's zone. Months are read by their first three letters, English or German (`Okt.`, `Mai`, `Dez`), because a localized export is unconfirmed. An ISO `yyyy-MM-dd HH:mm[:ss]` is also accepted. Duration is `end − start`, or 0 when the end is missing. |
| `weight_kg` / `weight_lbs` | **The header states the unit.** `isWeightUnitCertain` is set, so the preview hides the unit picker and imports in that unit. Empty means bodyweight (0). |
| `reps` | Rounded. Empty is 0. |
| `superset_id` | Empty means no superset. Blocks of one workout sharing a value become one superset (§3). |
| `set_type` | `warmup` (or numeric `2`) is **skipped and counted**. `normal`, `dropset` and `failure` import as ordinary completed sets. |
| `description` | The workout notes. |
| `exercise_notes` | Repeats on every set row. Appended **once per block** to the workout notes as `Exercise: note`, one per line, because history has no per-exercise notes and this feature adds no schema change. |
| `distance_*`, `duration_seconds` | Only used to recognise cardio rows (weight and reps 0, distance or duration > 0): skipped and counted, as for Strong. A timed hold such as a plank therefore counts as cardio. |
| `set_index`, `rpe` | Ignored. Set order in history is file order. |

**Research (2026-10-10).** No real Hevy export was available, so the format was taken from
published files and documentation and is pinned by `HevyCSVParserTests`:
[a sample export (kg)](https://github.com/matanabudy/workout-data-sync/blob/main/examples/hevy_export_sample.csv),
[a lbs row](https://blog.ayjc.net/posts/migrate-strong-hevy-app/),
[Taper: Hevy export columns, set types, superset numbering](https://thetaperapp.com/articles/how-to-export-hevy-data/),
[Gript: unit follows the account setting](https://griptapp.com/help/export-workouts-from-hevy).
Taper's claim that weights are always in `weight_lbs` contradicts the kg sample, so the header
decides. **Unconfirmed:** localized headers or month names, decimal commas, and the numbering of
`superset_id` (it is keyed per workout, so its numbering does not matter). The Strong lesson in §2
applies: profile the first real Hevy file before trusting this table.

---

## 3. Mapping rules (`HistoryImportMatching`)

- **Workouts** are grouped by `(start second, normalized workout name)`. Within a workout,
  consecutive rows of one exercise form one `WorkoutExercise`. The same exercise appearing again
  later becomes a second block, as it was trained.
- **Each workout becomes one `WorkoutSession`** with `routine == nil`, every set `isCompleted =
  true` and `planned == actual` reps and weight. `restTime` is the model default of 60 s (the file
  has none), `completedAt` is the workout's start (the file has no per-set time), and
  `healthKitWorkoutId` and `bodyWeightKg` are nil.
- **Exercise names** match the library **case- and whitespace-insensitively**: lowercased, trimmed,
  inner whitespace collapsed. No fuzzy matching, so Strong's `Bench Press (Barbell)` does not match
  a library `Bench Press`. That is deliberate: guessing would silently merge charts. When CloudKit
  has left two library exercises with one name, the oldest `createdAt` wins, then the smallest id.
  This is the same pick `DefaultContentSeeder` makes.
  - **Matched** (in both toggle positions): the history row takes the library exercise's id, name, muscle groups and load
    behaviour, so its charts and PRs continue.
  - **Unmatched, toggle on (default):** a custom exercise is created as a user-created one would be (`seedKey` empty,
    muscle group `General`). Equipment and load behaviour come from Strong's suffix: `(Barbell)`,
    `(Dumbbell)` default, `(Machine)`/`(Smith Machine)`, `(Cable)`, `(Bodyweight)`/`(Weighted)`
    → bodyweight, and `(Assisted)` → bodyweight with counterweight assistance. The user can edit
    any of them afterwards. **Toggle off:** see §3a.
- **Supersets (Hevy):** `ImportedExercise.supersetGroup` carries the file's `superset_id`. The
  store gives each group of one workout a fresh `supersetId` and numbers its blocks
  `supersetOrder` 0, 1, … in file order, the same fields a recorded superset writes, so
  `WorkoutSession.exercisesGroupedBySupersets` groups them. Groups are scoped per workout: the same
  id in two workouts makes two supersets. Consecutive rows form one block only while both the name
  and the superset group stay the same.
  **Display gap (open, ticket `08`):** the History detail (`WorkoutDetailView.exercisesSection`)
  lists exercises flat by `order` and shows no superset grouping, for recorded workouts as well as
  imported ones. The ticket assumed it did. The data is written correctly, so a grouped display
  added there picks imported supersets up with no import change.
- **Units:** the stored value is `WeightUnit.kilograms(fromDisplay:)` of the file value in the
  chosen unit. Kilograms stay canonical (`docs/weight-unit-preference.md` §2).
- **Cardio rows** (weight 0 and reps 0, with distance or seconds > 0) are skipped and counted.
  Rows with nothing at all are dropped silently. A workout left with no strength set is not
  imported.

### 3a. History-only import (the library toggle)

Added 2026-10-10 at the user's request. The first real export had 21 of 23 names unmatched, all
Strong spellings like `Bench Press (Barbell)`, and creating them all would crowd the library with
near-duplicates. With the toggle **off**:

- **Matched names still link to the library** exactly as before. The toggle governs only *new*
  exercises.
- **Unmatched names are written as name-only rows**: `exerciseId == nil`, the Strong spelling as
  `exerciseName`, muscle group `General`, and the load behaviour from the suffix. No `Exercise` is
  created, and the summary reports 0.

**What a name-only row does in the app:**
- **Shows fully in History:** list, detail, volume, streaks, muscle map (`General`). PR badges are
  keyed by `stableKey`, which falls back to the lowercased name, so PRs work *among the imported
  rows*. That is only true while no library exercise of that name exists; see the next point.
- **Not in Fortschritt or the exercise charts yet.** `FortschrittAggregator` builds rows only for
  *live* library exercises, and a row resolving to none is dropped by design (that is what keeps
  deleted exercises out).
- **Links up later, automatically, and permanently.** When the user **creates or renames** an
  exercise and its name is unique in the library, `ExercisesViewModel.linkNameOnlyHistory` writes
  that exercise's id onto every finished-workout row of the same name, through the existing
  `LegacyHistoryAttributing` write path. The match is case-insensitive. It then posts
  `.historySourceDataDidChange`. If two library exercises share the name, nothing is written, and
  the existing attribution banner lets the user pick. Pinned by
  `HistoryImportStoreTests.creatingExerciseLinksNameOnlyRows`.
  - **Why the link must be written, not just read by name.** Charts (`FortschrittAggregator`,
    `ExerciseProgressAggregator`) and previous performance already resolve a nil-id row by name.
    But `PersonalRecordService`, `PostWorkoutRecapAggregator` and `WorkoutAnalysisAggregator` key
    by `WorkoutExercise.stableKey` (`exerciseId ?? name`) and have no name fallback. Unlinked
    imported rows would sit under the name key, and new workouts under the UUID key. The first
    new workout would then be a "PR" against an imported history it cannot see, while the chart
    shows that history as heavier. The architecture review found this on 2026-10-10. Writing the
    link makes every consumer see one history.
  - **Side effect, accepted:** genuine pre-`exerciseId` legacy rows of that name are linked too.
    Charts were already showing them under that exercise by name, so this only makes permanent
    what was displayed. It also keeps the rows attached if a second same-named exercise appears
    later, where the name fallback would have withheld them.
  - **A later import with the toggle on** links the same way. `prepareWrite` writes each created
    exercise's id onto the existing name-only rows of that name, in the same save as the exercise.
    A created name is unique by construction. Pinned by `laterCreatingImportLinksNameOnlyRows`.
  - **Renames link too, and do not unlink.** `updateExercise` re-runs the link on every save.
    Renaming an exercise to the name of orphaned rows attaches them permanently, and renaming it
    back does not detach them, whereas a pure by-name lookup would follow the current name. This
    is accepted: the user named the exercise after those workouts.
  - **Matching difference:** the import matches whitespace-collapsed names, while linking compares
    plain lowercased names. A Strong name with irregular inner spacing therefore imports matched
    but is not auto-linked later.
  - Seeded exercises added by a future catalog version do not run this hook. Their rows stay
    chart-visible by name, but the PR split above applies until the user renames or recreates the
    exercise.

**Why nil and not a placeholder id:** an id that resolves to nothing would be dropped from
Fortschritt forever. A nil id is the one state the app already knows how to link later.

**Why the default is on:** charts are the payoff the import exists for (the aha path's "see the
number go up"). Off is the explicit choice of a user who would rather keep the library clean.

**Known edges:**
- A re-import with the toggle on cannot "upgrade" an earlier history-only import, because those
  workouts are skipped as duplicates. Adding the exercise by hand is the way, as above.
- A name-only row keeps its suffix-derived load behaviour. `(Assisted)` means counterweight, and a
  hand-made exercise of that name must match it, or Fortschritt drops the rows as a different
  measure.

### 3b. Period filter

Added 2026-10-10 at the user's request ("users might want to only import last month").

- **Selection is in whole days**, From's start through the end of To, in the device calendar. A
  workout belongs to the period by its **start time**. Cardio skips carry their workout's start
  time (`ParsedHistoryFile.skippedCardioSetStartTimes`), so they are counted per period too.
- **Presets count back from the file's newest workout, not from today**
  (`HistoryImportPeriod.dayRange`), clamped to the first workout. The first real export ended
  eight months before it was imported, so "Last month" from today would have selected nothing.
  For a user switching right now the two are the same. The menu shows "Custom" when the pickers
  match no preset.
- **The counts update live without another store round trip.** The off-main preview returns lookups
  instead of numbers: `alreadyImportedKeys` (the file's dedupe keys already in history) and
  `libraryMatchedNames`. `HistoryImportPreview.summary(in:)` then counts any period: workouts,
  duplicates, matched names, new names and cardio skips. The view model recomputes it when the
  pickers change (`refreshSelection`), never in a view body. It is an O(sets) pass over value
  types, cheap even for thousands of workouts.
- **Picker bounds come from the view model** (`fromBounds`/`toBounds`, clamped into the file's span
  and against each other). A `ClosedRange` with inverted bounds traps, so the view never builds one
  from the freely settable `rangeStart`/`rangeEnd` (architecture review, 2026-10-10). `apply(_:)`
  writes both ends and then summarises once.
- **Import takes `file.restricted(to:)`**, so only the selected workouts reach the store, and the
  new-exercise list (and whether exercises are created) covers only those.
- **Import is disabled when nothing would be written**: `importableWorkoutCount == 0`, meaning the
  period is empty or every workout in it is already in history. A notice says which case it is.
- **Exercise counts cover only the workouts that will be written.** The store resolves and creates
  exercises for *pending* workouts only, so `summary(in:)` counts names over those. Found on device
  on 2026-10-10: a period holding one already-imported workout still offered Import and listed seven
  "new" exercises that an import would never have created.
- **Importing more later is safe.** Importing an older period after a newer one, or the whole
  file afterwards, adds only what is missing, by the usual dedupe rule.

### Dedupe: idempotent by construction

A workout is skipped when history already holds a session with the **same start second and the same
normalized name** (`dedupeKey`). Re-importing the same file, or a newer export that overlaps an
older one, adds nothing twice. The lookup is a store fetch bounded to the file's date range, never a
whole-history scan. Workouts are deduplicated **before** exercises are resolved, so a fully
duplicate re-import also creates no exercises.

A consequence of the rule: renaming an imported workout in the app and re-importing the file imports
that workout again. This is accepted, because no stable Strong id exists in the export and the
workout name is part of the ticket's dedupe rule.

---

## 4. Architecture

```
Presentation  HistoryImportView ── HistoryImportViewModel (@Observable @MainActor)
                    │                      │  any HistoryImporting
Domain        HistoryImport (value types) · HistoryImporting (protocol)
              CSVTableReader · StrongCSVParser · HevyCSVParser · HistoryImportMatching   (pure, isolation-agnostic)
Data          SwiftDataHistoryImportProvider (@concurrent) → SwiftDataHistoryImportStore (@ModelActor)
App           AppDependencies.historyImporter, makeHistoryImportViewModel(source:)
```

- **Off the main actor.** Both provider methods are `@concurrent`. Without it, SE-0461 runs the file
  read, the parse and the inserts on the calling `@MainActor` view model's actor
  (`docs/swift6-concurrency.md` §1). Pinned by
  `SwiftDataHistorySnapshotStoreTests.largeHistoryImportKeepsMainActorResponsive`: 2,000
  workouts × 5 exercises × 4 sets are read, parsed, previewed and written through `any
  HistoryImporting`, with the main-actor heartbeat staying under 100 ms.
- **Its own model actor**, constructed by `Task.detached` exactly like
  `SwiftDataLegacyHistoryAttributionProvider`, so its `save()`s never land on the context History
  reads through.
- **`HistoryStoreGate`:** every store call runs inside `gate.withAccess`, the shared app gate,
  because the store reads `WorkoutSession` rows (dedupe), and a completed-session delete landing in
  between would trap (`docs/history-delete-race.md`). Writes go in **chunks of 100 workouts, one
  `save()` and one gate hold each**, so a History rebuild or a delete can interleave with a
  multi-year import instead of waiting behind all of it. Progress is reported per chunk.
- **Stateless actor:** `prepareWrite` returns the resolved exercise map
  (`HistoryImportResolvedExercise`, `Sendable`) and every `insert` chunk receives it by value. An
  earlier draft cached the map on the actor between gate holds, and the architecture review rejected
  that: a second import interleaving between chunks would have replaced the first import's mapping,
  and exercise blocks would have been silently dropped. An unresolved name now throws `.writeFailed`.
  A failed `save()` rolls back the context, so a half-written chunk never stays pending for the next
  dedupe fetch.
- **One pipeline, two formats:** `prepareImport(from:source:)` picks the parser by
  `HistoryImportSource`. Both produce `ParsedHistoryFile`, and everything after parsing (preview,
  period filter, matching, dedupe, chunked writes) is shared. The view model carries the source,
  fixed by the entry point (`makeHistoryImportViewModel(source:)`), and the view picks the few
  strings that name the app (title, intro, two errors). Strong keeps its original `history_import.*`
  keys, and Hevy's live under `history_import.hevy.*`.
- **Security-scoped URL:** `prepareImport(from:source:)` starts and stops access itself, around the
  read, on the background executor. The URL is `Sendable`, and the scope belongs to the process, not
  a thread.
- **Refresh:** after an import that wrote anything, the view model posts `.workoutHistoryDidChange`
  and `.historySourceDataDidChange`, which History, routines and Fortschritt already observe. If it
  created exercises, it also calls `requestCatalogSync()` so the watch learns them.
- **Reusable entry point:** `HistoryImportView(viewModel: dependencies.makeHistoryImportViewModel(source:))`
  is a self-contained sheet with its own `NavigationStack` and file importer. Settings presents it
  today (one row per source, `.sheet(item:)` on the chosen `HistoryImportSource`), and ticket 06's first-run link presents the same thing.
- **No schema change.** Only existing models and fields are written, so no CloudKit production
  deploy is needed.

### Failure behaviour

Parsing and preview write nothing. If a save fails part-way through an import, the chunks already
saved stay. The error screen says so, and because the import is idempotent, importing the file again
adds only the rest. Exercises are created and saved before the first workout chunk, so a failure
after that point can leave a created exercise with no history. This is harmless, and the user can
delete it.

---

## 5. UI

`Presentation/Views/HistoryImport/`. Phases: **intro** (how to export from Strong or Hevy, then "Choose CSV
File") → **reading** → **preview** (period card, counts, unit, library toggle, Import) → **importing** (determinate progress, cancel and swipe-dismiss
disabled) → **finished** (summary, Done) or **failed** (message, "Choose Another File"). Counts are
label/value rows, so no string needs plural rules. The new-exercise list sits in a `LazyVStack`,
because it is as long as the user's Strong library. `.fileImporter` sits on the sheet's stable root
and allows `[.commaSeparatedText, .plainText]`. `.plainText` is cheap insurance for a provider that
tags a `.csv` with a generic text type. Strings: `history_import.*` and `settings.section.import*`
in en and de.

---

## 6. Deliberate omissions

- **No Apple Health writes.** These are past sessions, and Strong may already have written them to
  Health, so writing would create duplicates there. `healthKitWorkoutId` stays nil, and no
  HealthKit call exists on this path.
- **Cardio rows are not imported.** History has no distance or duration-per-set fields, and adding
  them would be a schema change with a CloudKit production deploy. They are counted in the preview
  and summary.
- **RPE and Strong's per-set notes are dropped.** History has no field for them. Hevy's
  per-exercise notes survive inside the workout notes (§2b).
- **Warm-up sets (Hevy) are not imported.** They would inflate volume and set counts. They are
  counted in the preview and summary. Strong's `W`-marked sets still import as ordinary sets,
  unchanged from ticket 01.
- **No fuzzy exercise matching.** See §3.
- **No cancel during the write.** Once Import is tapped it runs to the end. Stopping between
  chunks would leave the same "partially imported, re-import to finish" state as a failure, with no
  benefit.

---

## 7. Adding another format

Hevy went in this way (ticket 02). Write a pure parser that produces `ParsedHistoryFile` and add a
`HistoryImportSource` case. Then add a branch in `SwiftDataHistoryImportProvider.prepareImport`, the
app-naming strings, and a Settings row. `CSVTableReader` and the shared `[safe:]` row subscript live
in `CSVTableReader.swift`. Nothing after parsing changes.

---

## 8. Research

- `fileImporter(isPresented:allowedContentTypes:onCompletion:)`: the returned URL needs
  `startAccessingSecurityScopedResource()` / `stop…` around the read. Only call stop if start returned
  true. Reading from a background task while access is held is fine.
  [Apple docs](https://developer.apple.com/documentation/swiftui/view/fileimporter%28ispresented%3Aallowedcontenttypes%3Aallowsmultipleselection%3Aoncompletion%3A%29),
  [forum: security scope on iCloud Drive](https://developer.apple.com/forums/thread/741560).
- `.commaSeparatedText` conforms to `.delimitedText` → `.plainText`. Allowing `.plainText` also
  accepts CSVs that a provider tags generically.
  [Forum: CSV loading](https://developer.apple.com/forums/thread/767714).
- Known fileImporter issue (iOS 18.x, real devices): the picker occasionally won't select a file or
  call back. The fallback, if it ever reproduces, is a `UIDocumentPickerViewController(forOpeningContentTypes:asCopy: true)`
  representable.
  [Forum](https://developer.apple.com/forums/thread/775056). Attach only one fileImporter to a
  stable view.

---

## 9. Verification record

- **A real German-language Strong export** (2026-10-10, 2,270 rows) parsed through the shipping
  parser: 135 workouts, 2,248 sets, 22 rest-timer rows ignored, 0 durations unread, 23 distinct
  exercise names.
- `StrongCSVParserTests` (15, including the localized-header regression and its negative case): grouping, quoted fields with commas/quotes/line breaks, semicolon +
  decimal-comma exports, empty RPE, cardio and rest-timer rows, the newer header variant, foreign
  header rejection, a malformed row's line number, durations, name normalization, oldest-duplicate
  library pick, dedupe key, unit conversion and equipment traits.
- `HistoryImportStoreTests` (4), against an in-memory store: an end-to-end import (preview writes
  nothing, matched vs. created exercise ids, completed sets, routine-less session, end time, no
  HealthKit id), re-import creates zero workouts and zero exercises, pounds stored as kilograms, and
  a foreign file writes nothing.
- `largeHistoryImportKeepsMainActorResponsive`: 2,000 workouts, main actor under 100 ms.
- **Hevy (2026-10-10):** `HevyCSVParserTests` (9): grouping and duration, header-unit detection
  (kg and lbs), superset grouping, set types (warm-up skipped, drop and failure kept, cardio
  skipped), warm-ups per period, notes mapping, date formats, rejection of a Strong file, and a
  malformed row's line. `HevyHistoryImportStoreTests` (4): superset fields in history and
  `exercisesGroupedBySupersets`, per-workout superset scoping, re-import idempotency with lbs → kg,
  and a Strong file in the Hevy flow writing nothing. All Strong suites pass unchanged (regression).
  **On device, 2026-10-17:** the user ran the hand-off checklist with a real Hevy export (accepted
  with no unit picker, workouts in History, chart and records, re-import adds nothing) and reported
  it working.
- **On device, 2026-10-10** (iPhone, German UI, the user's real German-language Strong export, 135
  workouts from 2024-04-14 to 2026-02-12), confirmed by the user:
  - The file is accepted after the localized-header fix. Before that fix it was rejected as
    "not a Strong export" (§2 root cause).
  - Imported workouts appear in History with the right sets, duration and volume, and with PR
    badges and "Erste Session" markers. One example is "Push", Thu 12 Feb: 22 sets, 55 min,
    5.3 t, Bench Press (Barbell) 90 kg × 4.
  - The library toggle works in both positions.
  - Period presets work. "Letzte 3 Monate" selects 12.11.2025–12.02.2026, which is 5 workouts, 1 of
    them already imported, and 6 new exercises. A custom single-day period updates the counts live.
  - Re-importing a period whose only workout is already in history shows "all already imported",
    counts 0 new exercises and disables Import (§3b).
- **Not exercised on device:** a pound export imported as lb and then shown in kg. The user's file
  is kilograms. The user accepted the unit test `poundsAreConverted` as sufficient (2026-10-10). A non-Strong CSV
  on device is also unverified: the rejection is unit-tested, and the first, pre-fix attempt
  showed the error screen.
