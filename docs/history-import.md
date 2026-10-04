# Workout history import (Strong CSV)

**Status:** Strong shipped 2026-10-03 (`.scratch/positioning-usp/issues/01`). Hevy is ticket
`02`, still open; it extends this pipeline with a second format (§7).
**Strategy:** `docs/acquisition-strategy.md` lever **#16**; research in
`docs/research/positioning-usp-2026-10.md` §3.2.

---

## 1. What it does

A user who exported their data from Strong opens **Settings → Import → Import from Strong**,
picks the CSV with the system document picker, and sees a preview:

- the number of workouts and their period;
- how many were already imported earlier (these are skipped);
- how many distinct exercise names match the library, how many will be created as custom
  exercises, and the list of those new names;
- how many cardio sets are left out;
- a **kg / lb** choice for the file's weights.

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
(`StrongCSVParser`) therefore looks columns up **by header name, never by position**:

| Column | Required | Handling |
|---|---|---|
| `Date` | ✓ | `yyyy-MM-dd HH:mm[:ss]`, wall-clock time in the device's time zone (Strong writes local time with no zone). |
| `Workout Name` | ✓ | → `WorkoutSession.routineName`. |
| `Exercise Name` | ✓ | Matched to the library (§3). |
| `Set Order` | ✓ | Only used to skip Strong's `Rest Timer` rows. Set order in history is file order. Letter-marked sets (warm-up/drop/failure) import as ordinary sets. |
| `Weight…` | ✓ | Decimal comma accepted. The header's `(kg)`/`(lbs)` suffix, when present, **preselects** the unit picker. The user still decides. Negative values (assisted exercises in some exports) are stored as their absolute value. |
| `Reps` | ✓ | Rounded to an integer. |
| `Duration…` | – | `1h 5m`, `45m`, `30s`, or plain seconds → `endTime = startTime + duration`. Missing or unparseable → `endTime == startTime`. The session still counts as completed. |
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
  - **Matched:** the history row takes the library exercise's id, name, muscle groups and load
    behaviour, so its charts and PRs continue.
  - **Unmatched:** a custom exercise is created as a user-created one would be (`seedKey` empty,
    muscle group `General`). Equipment and load behaviour come from Strong's suffix: `(Barbell)`,
    `(Dumbbell)` default, `(Machine)`/`(Smith Machine)`, `(Cable)`, `(Bodyweight)`/`(Weighted)`
    → bodyweight, and `(Assisted)` → bodyweight with counterweight assistance. The user can edit
    any of them afterwards.
- **Units:** the stored value is `WeightUnit.kilograms(fromDisplay:)` of the file value in the
  chosen unit. Kilograms stay canonical (`docs/weight-unit-preference.md` §2).
- **Cardio rows** (weight 0 and reps 0, with distance or seconds > 0) are skipped and counted.
  Rows with nothing at all are dropped silently. A workout left with no strength set is not
  imported.

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
              CSVTableReader · StrongCSVParser · HistoryImportMatching   (pure, isolation-agnostic)
Data          SwiftDataHistoryImportProvider (@concurrent) → SwiftDataHistoryImportStore (@ModelActor)
App           AppDependencies.historyImporter, makeHistoryImportViewModel()
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
- **Security-scoped URL:** `prepareStrongImport(from:)` starts and stops access itself, around the
  read, on the background executor. The URL is `Sendable`, and the scope belongs to the process, not
  a thread.
- **Refresh:** after an import that wrote anything, the view model posts `.workoutHistoryDidChange`
  and `.historySourceDataDidChange`, which History, routines and Fortschritt already observe. If it
  created exercises, it also calls `requestCatalogSync()` so the watch learns them.
- **Reusable entry point:** `HistoryImportView(viewModel: dependencies.makeHistoryImportViewModel())`
  is a self-contained sheet with its own `NavigationStack` and file importer. Settings presents it
  today, and ticket 06's first-run link presents the same thing.
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

`Presentation/Views/HistoryImport/`. Phases: **intro** (how to export from Strong, then "Choose CSV
File") → **reading** → **preview** → **importing** (determinate progress, cancel and swipe-dismiss
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
- **RPE and per-set notes are dropped.** History has no field for them.
- **No fuzzy exercise matching.** See §3.
- **No cancel during the write.** Once Import is tapped it runs to the end. Stopping between
  chunks would leave the same "partially imported, re-import to finish" state as a failure, with no
  benefit.

---

## 7. Extending to Hevy (ticket 02)

The seam is ready: `CSVTableReader` is format-agnostic, and everything after parsing consumes
`ParsedHistoryFile`. Hevy needs a `HevyCSVParser` that produces the same value type (unit from the
`weight_kg`/`weight_lbs` header, warm-up sets skipped and counted), a `prepareHevyImport(from:)` (or a
format parameter) on `HistoryImporting`, and superset ids carried on `ImportedExercise`.

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

- `StrongCSVParserTests` (13): grouping, quoted fields with commas/quotes/line breaks, semicolon +
  decimal-comma exports, empty RPE, cardio and rest-timer rows, the newer header variant, foreign
  header rejection, a malformed row's line number, durations, name normalization, oldest-duplicate
  library pick, dedupe key, unit conversion and equipment traits.
- `HistoryImportStoreTests` (4), against an in-memory store: an end-to-end import (preview writes
  nothing, matched vs. created exercise ids, completed sets, routine-less session, end time, no
  HealthKit id), re-import creates zero workouts and zero exercises, pounds stored as kilograms, and
  a foreign file writes nothing.
- `largeHistoryImportKeepsMainActorResponsive`: 2,000 workouts, main actor under 100 ms.
- **Not yet done:** an import of a real Strong export on a device, with one exercise's chart
  checked against the CSV. See the ticket's manual steps.
