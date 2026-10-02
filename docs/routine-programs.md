# Routine Programs

Ready-made, researched training programs that a user adds from a **Program library**. Adding one
creates **ordinary routines**: they are startable, editable and deletable, and they reach the watch
like any other routine. There is no program model in the store.

**Status (2026-10-02):** ticket 02 shipped **Beginner Full Body**, end to end: library → detail →
add sheet → routines + optional cadence plan. Ticket 03 completed the detail screen (timeline,
alternative hint, "How to train it", "Based on", repeated CTA with an add / restore / added state).
Still to come: the Routines-tab shelf and empty state (04), grouping installed routines per program
(05), Push/Pull/Legs (06), the ballistic seeds (07) and Fighter Strength (08). Tickets:
`.scratch/routine-programs/issues/`.

**Inputs:** content is in `docs/research/routine-programs-hypertrophy.md` §3 (the source of truth for
the exact tables, signed off 2026-09-27). The delivery model is
`docs/research/routine-programs-delivery-model.md`, the tier verdict
`.scratch/routine-programs/wayfinder/04-grilling-monetization-verdict.md`, and the design the
[Routine Programs Design](https://claude.ai/artifact/3ruyyATKwk7WX4EKmAi62D) canvas (artboards 2–4
are built; artboard 3's rule and source copy is the en source of truth).

## What the user sees (iOS)

1. **Entry point (temporary).** A "Programs" row under the dashed "New routine" tile on the
   Routines tab, plus a secondary "Programs" button in the zero-routine empty state. Ticket 04
   replaces both with the Programs shelf.
2. **Library** (`ProgramLibraryView`, pushed): the intro, then one card per program with eyebrow,
   name, short pitch, three stat tiles and "Based on …". A fully installed program shows
   "✓ Added". The footer ("All programs are free…") appears only for users the routine cap applies to.
3. **Detail** (`ProgramDetailView`, pushed), in the design's order:
   - **Hero**: eyebrow, name, pitch, three stat tiles and the CTA.
   - **"Scheduled by recovery time"**: the program's explanation line, a 7 × 2 grid of the next
     14 days starting today (short weekday, the routine's letter on its days, today outlined) and
     a legend ("A = Full Body A · B = Full Body B · outlined = today"). The legend falls back to a
     column when it does not fit on one line (German, large text).
   - **The routines**: "N exercises · M sets" and one row per exercise: sets × rep range, plus
     "Alternatives: …", "Superset with …", or else the slot's one-line role ("Vertical pull").
   - **Alternative hint** (only for programs that set `alternativeHintKey`).
   - **"How to train it"**: numbered rules. Full Body: effort 1–3 RIR, start weight, top of range →
     smallest step (2.5 kg lower / 1.25–2.5 kg upper), stuck twice → −10 %, after ~12 weeks → PPL.
   - **"Based on"**: each source with its one-line role.
   - **The CTA again.** Both CTAs share one state: nothing installed → "Add program"; some routines
     deleted → "Restore N routine(s)" (opens the same sheet, which lists only the missing ones —
     the gap-fill install); everything installed → "✓ Added".
   Sections a program doesn't use (no hint, no rules, no sources) are omitted.
4. **Add sheet** (`ProgramInstallSheet`): lists **the routines that would be added** (the missing
   ones only), a "Plan by recovery time" toggle that is **on by default**, the first-workout
   picker (Today / Tomorrow / Pick a day), a per-routine preview ("Full Body A — Today, then
   every 4 days") and the CTA "Add N routines". Under the CTA, "Free · doesn't use your routine
   slots" appears for capped users only. Pro users and Founders never see it.
5. On success the sheet closes and the navigation pops to the Routines list, where the new
   routines already appear.

## Beginner Full Body content

Two routines, `seed.program.full_body.a` / `.b` ("Full Body A/B", "Ganzkörper A/B"). Every set starts
at the bottom of its rep range with 0 kg. Alternatives copy the primary's set scheme and rep range.

| A | Sets × reps | Rest | | B | Sets × reps | Rest |
|---|---|---|---|---|---|---|
| Barbell back squat (alt: leg press, goblet squat) | 3 × 8–12 | 180 s | | Romanian deadlift | 3 × 8–12 | 180 s |
| Barbell bench press (alt: machine chest press, DB bench) | 3 × 8–12 | 150 s | | Overhead press (alt: machine shoulder press, seated DB press) | 3 × 8–12 | 150 s |
| Lat pulldown | 3 × 8–12 | 120 s | | Seated cable row | 3 × 8–12 | 120 s |
| Lying leg curl | 2 × 10–15 | 90 s | | Leg press | 3 × 10–15 | 120 s |
| DB lateral raise ⟷ superset | 2 × 12–20 | 60 s | | Incline DB bench press | 2 × 8–12 | 120 s |
| Tricep pushdown ⟷ superset | 2 × 10–15 | 60 s | | Dumbbell curl | 2 × 10–15 | 60 s |

Cadence: each routine every **4** days, B first due **2 days after** A. That gives a strict
A-rest-B-rest alternation.

## Architecture

```
Presentation  ProgramLibraryViewModel (@Observable @MainActor)
              ProgramLibraryViewModel+Summaries (static display-model builders)
              Views/Programs/{ProgramLibraryView, ProgramDetailView, ProgramDetailSections, ProgramInstallSheet,
                              ProgramComponents, ProgramsEntryRow (temporary, deleted by ticket 04)}
              RoutinesView: entry row + navigationDestination(isPresented:)
      │  RoutineProgramInstalling (Domain protocol)
Domain        Models/RoutineProgram.swift          value types (program → routines → exercise slots)
              Services/RoutineProgramCatalog.swift  the static content
              Services/RoutineProgramSchedule.swift first-due dates + detail timeline (pure, isolation-agnostic)
              Interfaces/RoutineProgramInstalling.swift
      ▲
Data          Seeding/RoutineProgramInstaller.swift conforms; the only place touching ModelContext
              Seeding/SeedRoutineBuilder.swift      shared with ExampleRoutineSeeder
App           AppDependencies.routineProgramInstaller + lazy programLibrary (one instance, like
              conditioningProgram — a Routines-tab re-init must not rebuild it or refetch)
```

- **The catalog lives in Domain, not `Data/Seeding`** as the delivery memo first suggested. The
  library and detail screens have to display it, and Presentation may not reference Data types.
  The precedent is `Domain/Services/ConditioningProgramContent.swift`. Copy is keyed by program id
  (`routine_programs.<id>.name|level|pitch|pitch_short|sources|stat.*`), and routine names are keyed
  by their `seedKey`, the same convention seeded exercises use.
- **Display models are built once.** The catalog is static, so `ProgramLibraryViewModel` builds every
  `ProgramSummary` (stats, routine meta, exercise rows and notes, legend, rules, sources) in `init`
  (`ProgramLibraryViewModel+Summaries.swift`). The views only read them. The two date-dependent
  lists live in `@State`: the sheet's preview lines (recomputed on `onAppear` and on change of the
  start choice) and the detail's timeline (fetched on `onAppear`). The day and weekday formatters
  are `static let`.
- **Program copy is catalog data.** `RoutineProgram` carries `alternativeHintKey`,
  `guidanceRuleKeys` (stems of `routine_programs.<id>.rule.<stem>.title|detail`) and `sourceKeys`
  (`routine_programs.<id>.source.<stem>.name|role`); a slot carries an optional `noteKey`
  (`routine_programs.note.*`, shared across programs); the timeline explanation is
  `routine_programs.<id>.schedule_detail` and a routine's timeline letter is `<seedKey>.short`.
  A new program (06, 08) therefore only adds catalog entries and strings — no view changes.
- **The timeline is derived, not drawn.** `RoutineProgramSchedule.timeline(for:from:dayCount:calendar:)`
  marks day *i* with the routine whose `(i − offset) % cadenceDays == 0`, offsets relative to the
  earliest routine (the same convention as `firstDueDates`). It shows the program as if started
  today; it does not read the user's real schedules.
- **One function feeds both the preview and the written plan.** That function is
  `RoutineProgramSchedule.firstDueDates`. The sheet's preview and the installer both call it with
  the same "routines still to add", so the dates shown are the dates written.
- **Refresh after install.** The installer saves and posts `.cloudKitDataDidChange`.
  `RoutinesViewModel` refetches on that notice, and the refetch also syncs the watch and reconciles
  the calendar and reminders. The routines list and the watch update without a relaunch.
- **Status-bar strip.** The program screens hide the navigation bar, so nothing covers the status
  bar and scrolled content was legible under the clock. `programStatusBarBackground()`
  (`ProgramComponents.swift`) overlays a zero-height `Color.clear` whose **`background`** is the
  screen colour with `.ignoresSafeArea(edges: .top)`. Dead end: `color.frame(height: 0).ignoresSafeArea(edges: .top)`
  paints nothing, because a view with a fixed size only gets its alignment resolved when safe areas
  expand ([`ignoresSafeArea` docs](https://developer.apple.com/documentation/swiftui/view/ignoressafearea%28_%3Aedges%3A%29)).
  Not relied on: `.scrollEdgeEffectStyle(.hard, for: .top)` (iOS 26). The docs only describe it
  where pinned content overlaps scrolling content, and do not say it renders with no nav bar.
  `.safeAreaInset(edge: .top)` is for real inset content, not for painting the safe area.
- **Watch target: no changes.** Program routines are ordinary `WatchRoutine`s in the existing
  routine sync. Schedules and program membership are iOS-only by design. A program header on the
  watch would need a DTO field on both `WatchModels` copies.

## Install contract

1. **Static catalog, derived state.** "Installed" and membership come from looking up present
   `seedKey`s (`installedRoutineKeys()`), never from parsing the key format. There is **no new
   `@Model`, no new field and no CloudKit schema deploy**: `Routine.seedKey` has been in Production
   since 2026-08-27.
2. **Gap-filling only.** A routine whose `seedKey` already exists locally is never inserted. So
   re-installing restores deleted routines, leaves edited ones untouched, and never adds a second
   copy, which dedup would otherwise collapse silently.
3. **Missing exercises are re-created** from `SeedExerciseCatalog` (`SeedExercise.makeExercise()`,
   shared with `DefaultContentSeeder`), never dropped. A user exercise with the catalog row's
   normalized name is reused first: `DefaultContentSeeder` skips a seed that collides by name, and
   creating it here would put a duplicate in the library. (The example routine drops such slots
   instead. It was never requested; a program was.)
4. `updatedAt = createdAt` is pinned, as for the example routine. Localized names resolve once, at
   install time.
5. **The plan is always `everyNDays`** (interval `cadenceDays`, `startDate` = start of the first due
   day). It is **never `weekdays`**, so P9 is untouched and there is no tier branch and no
   `ScheduleGatingPolicy` call. With the toggle off, no `RoutineSchedule` is written.
   Restoring only some routines takes offsets **relative to the earliest routine being added**, so a
   restored B starts on the chosen day.
6. **All or nothing.** If resolving, inserting or saving throws, the installer calls
   `modelContext.rollback()` before rethrowing. The main context is shared, so leftover inserts
   would otherwise be persisted by the next unrelated save as a half-installed program. That is
   what makes the error copy "Your routines weren't changed" true. (No unit test drives this path:
   an in-memory store gives no clean way to make `save()` throw.)
7. **Insert-only, so it does not take the `HistoryStoreGate`.** That gate guards deletes the History
   actor might be walking underneath, and this path deletes nothing.
8. **The cap stays as it is.** Program routines carry a non-empty `seedKey`, so
   `RoutineCapPolicy.countsTowardCap` already excludes them. Duplicating one creates a plain
   `Routine(name:)`, which counts.
9. **The example seeder never deletes them.** The superseded cleanup is scoped to
   `SeedRoutineCatalog.seedKeys` (ticket 01). The dedup pass stays generic over every seed key, and
   that is what programs need.

## Lifecycle

| Event | Behaviour |
|---|---|
| Edit or rename a program routine | It stays a program routine; `seedKey` is never cleared and the routine never counts toward the cap |
| Duplicate | Creates an ordinary routine (`seedKey == ""`) that **counts** toward the cap |
| Delete one routine | Deleted; its plan cascades; history survives (denormalized). The detail shows "Add program" again, and the sheet offers only the missing routine |
| Re-install | Fills gaps only (contract 2) |
| Two devices install before they sync | Both upload. The existing dedup keeps the oldest `createdAt` (then `id`) everywhere and re-points sessions and plans onto it |
| **Device B edits its copy while A's older copy is still syncing** | Dedup keeps A's older copy, so **B's edits are lost** (sessions survive, re-pointed). This residual risk is **accepted**, the same one the example routine accepts. It is bounded to the first minutes after an offline install. Documented, not engineered against |
| Re-install on B before A's routines have imported | Gap-filling inserts; dedup then collapses onto the older (possibly edited) copy. Converges correctly |
| Launch / post-import example cleanup | Never touches program routines (contract 9) |

## Monetization

```
Monetization verdict — Routine programs (Beginner Full Body, PPL, Fighter Strength)
  Tier          Free
  Derivation    §3 Rule 1 (shortcut into the aha path); P1 counting rule extended —
                app-provided routines (seedKey ≠ "") are outside the cap
  Mechanism     none — no cap, no depth gate, no preview
  Placement     none new; existing .weekdaySchedule stays the only P9 touchpoint
  Nudge         none
  Free residue  everything: all programs, all routines, cadence plan pre-filled at install
  Founder note  converts ~nobody directly, by design; value is acquisition + D30 retention
```

Shipped as decided. The free-only lines are gated on `RoutineCapPolicy.isSubjectToCap`, so they are
hidden for Pro, for Founders, and with gating off. Strategy: `docs/monetization-strategy.md` §4.1
("Routine programs" row) and the §4.2a P1 addendum (new ceiling: 3 own + 1 example + ≤7 program).
Mechanism note: `docs/pro-subscription.md` §5c.

## Testing

- `GymStreakTests/RoutineProgramInstallerTests.swift` covers:
  - exact content: sets, reps, rest, superset, alternatives and their schemes;
  - a fresh install, and that re-installing is a no-op;
  - deleting B and re-installing restores only B and keeps A's edits;
  - a deleted seed exercise is re-created, while a same-named user exercise is reused;
  - the every-4-days plan with B starting 2 days later, no plan when the toggle is off, and never
    a weekday plan;
  - program routines stay outside the cap and survive the example seeder (`run()` and
    `cleanUpAfterImport()`);
  - every catalog key exists in `SeedExerciseCatalog`.
- `GymStreakTests/RoutineProgramScheduleTests.swift` covers the start choice → first day
  (past-day clamp), offsets relative to the earliest routine being added, Full Body's 14-day
  A · – · B · – timeline, and a synthetic program proving the timeline follows cadence and offsets.
- `GymStreakTests/ProgramLibraryViewModelTests.swift` covers the free-only note across
  free/founder/subscription/lifetime and gating off, a preview limited to missing routines, and the
  chosen day being passed only when planning, the add / restore / added CTA state, and the
  timeline starting today with only today outlined.

## Deliberate omissions (v1)

- **The design's coloured exercise thumbnails** (32 pt squares per row) are not built: the app has
  no per-exercise colour or image mapping, and the squares were placeholders in the mockup.
- **Fixed font sizes.** Like the rest of the program screens, the detail uses the design's fixed
  point sizes, so Dynamic Type does not grow them; the stat tiles and the timeline's weekday and
  routine letters additionally shrink-to-fit rather than clip. Moving the program screens to
  scaled text would be one pass over all four files.
- No "reset to original" action. If it is ever wanted, it must overwrite the existing routine in
  place, never insert a fresh copy (contract 2).
- No program-level rotation or "next routine". The every-N-days cadence plus the existing up-next
  logic cover alternation (delivery memo §5).
- Effort, deload, increments, start weights and graduation are program text only ("How to train
  it"). There is no app feature for them.
