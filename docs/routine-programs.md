# Routine Programs

Ready-made, researched training programs that a user adds from a **Program library**. Adding one
creates **ordinary routines**: they are startable, editable and deletable, and they reach the watch
like any other routine. There is no program model in the store.

**Status (2026-10-02):** ticket 02 shipped **Beginner Full Body**, end to end: library → detail →
add sheet → routines + optional cadence plan. Ticket 03 completed the detail screen (timeline,
alternative hint, "How to train it", "Based on", repeated CTA with an add / restore / added state).
Ticket 04 (done 2026-10-02) replaced the temporary entry row with the Programs shelf and rebuilt the zero-routine empty
state around programs. Ticket 05 (done 2026-10-03) groups installed routines per program on the Routines tab. Ticket 06 (done 2026-10-03) added **Push / Pull / Legs**, the first 3-routine program, and linked Full Body's graduation rule to it. Ticket 07 seeded the five ballistic exercises (catalog v3) and ticket 08 (2026-10-03) added **Fighter Strength**, the last catalog program, with its fight-training guidance, the "Fight camp" phases and a link to fight conditioning. **The feature is complete (user-confirmed 2026-10-03).** Tickets and the wayfinder research are archived in
`.scratch/_done/routine-programs/`.

**Inputs:** content is in `docs/research/routine-programs-hypertrophy.md` §3 (Full Body) and §4 (PPL)
and `docs/research/routine-programs-fighter-strength.md` §3–§5 (Fighter Strength), the source of
truth for the exact tables, signed off 2026-09-27. The delivery model is
`docs/research/routine-programs-delivery-model.md`, the tier verdict
`.scratch/_done/routine-programs/wayfinder/04-grilling-monetization-verdict.md`, and the design the
[Routine Programs Design](https://claude.ai/artifact/3ruyyATKwk7WX4EKmAi62D) canvas (all seven
artboards are built; artboard 3's and artboard 7's rule and source copy is the en source of truth).

## What the user sees (iOS)

1. **Programs shelf** (`ProgramShelf`, artboard 1) on the Routines tab, below the dashed "New
   routine" tile and above the conditioning card: the "PROGRAMS" label, "Ready-made plans, built
   from the research" and "See all" (→ library). A horizontal row holds one 248 pt card per
   catalog program: level eyebrow and routine count, name, a short shelf pitch, a 7-day pattern
   (the routine's letter on its days) and a cadence line. Tapping a card pushes that program's
   detail; its back link then reads "Routines". A program with **any** of its routines in the list
   shows "✓ ADDED" in the eyebrow's place (artboard 5). It reverts only once all of them are
   deleted; with some deleted, the detail offers the restore.
   **Empty state** (`ProgramsEmptyStateView`, artboard 6), shown with zero routines: the title,
   "Start with a program", one line, one row per program (monogram, name, "Beginner · 2 routines
   · 3–4× a week") and a bottom-pinned, outlined "Build your own routine" that goes through
   `RoutinesViewModel.requestAddRoutine()` like every other create affordance. The header buttons
   are not shown there, as in the design. The example routine is unchanged, so a fresh install
   usually sees the list with the shelf rather than this state.
2. **Library** (`ProgramLibraryView`, pushed): the intro, then one card per program with eyebrow,
   name, short pitch, three stat tiles and "Based on …". A fully installed program shows
   "✓ Added". The footer ("All programs are free…") appears only for users the routine cap applies to.
3. **Detail** (`ProgramDetailView`, pushed), in the design's order:
   - **Hero**: eyebrow, name, pitch, three stat tiles and the CTA.
   - **"Scheduled by recovery time"**: the program's explanation line, a 7 × 2 grid of the next
     14 days starting today (short weekday, the routine's letter on its days, today outlined) and
     a legend ("A = Full Body A · B = Full Body B · outlined = today"). The legend falls back to a
     column when it does not fit on one line (German, large text).
   - **The routines**: "N exercises · M sets" and one row per exercise: sets × rep range ("3 × 3"
     for a slot without a rep goal), plus "Alternatives: …" — prefixed with the slot's role when it
     has one ("Main lift · Alternatives: Front Squat") — or "Superset with …", or else the role alone
     ("Vertical pull").
   - **Alternative hint** (only for programs that set `alternativeHintKey`).
   - **"How to train it"**: numbered rules. Full Body: effort 1–3 RIR, start weight, top of range →
     smallest step (2.5 kg lower / 1.25–2.5 kg upper), stuck twice → −10 %, after ~12 weeks → PPL.
     That last rule carries a **"See Push / Pull / Legs"** link that pushes the PPL detail (back
     link "Beginner Full Body"; installing from there pops to the Routines list like any detail).
     PPL: the same effort, start-weight and progression rules, and stuck **three** sessions → −10 %
     (Metallicadpa's reset). Fighter Strength titles the section **"Around your fight training"**
     (artboard 7): 1 lift first, **! not before hard sparring** (the "!" chip in
     `DesignSystem.Colors.warning`; warnings take no number), 2 every rep fast, 3 strength lifts at
     1–3 RIR.
   - **"Fight camp"** (Fighter Strength only, artboard 7): one intro line, then weeks 1–4 Strength
     (as written, also the off-season default), 5–8 Maintain, 9–11 Power, 12 Taper (last heavy
     session 5+ days out). Text only — the routines never change by week.
   - **"Pairs with Fight conditioning"** (Fighter Strength only): a row that presents
     `ConditioningLibraryView` full screen, the same screen as the Routines-tab boxing button.
   - **"Based on"**: each source with its one-line role.
   - **The CTA again.** Both CTAs share one state: nothing installed → "Add program"; some routines
     deleted → "Restore N routine(s)" (opens the same sheet, which lists only the missing ones —
     the gap-fill install); everything installed → "✓ Added".
   Sections a program doesn't use (no hint, no rules, no camp phases, no pairing, no sources) are
   omitted.
4. **Add sheet** (`ProgramInstallSheet`): lists **the routines that would be added** (the missing
   ones only), a "Plan by recovery time" toggle that is **on by default**, the first-workout
   picker (Today / Tomorrow / Pick a day), a per-routine preview ("Full Body A — Today, then
   every 4 days") and the CTA "Add N routines". Under the CTA, "Free · doesn't use your routine
   slots" appears for capped users only. Pro users and Founders never see it.
5. On success the sheet closes and the navigation pops to the Routines list, where the new
   routines already appear.
6. **Grouped list** (artboard 5). Below the "Up next" hero, each installed program's routines sit
   under a section labelled with the program's name, with a **"Program guide"** link to its detail
   (back link "Routines"). The user's own routines, the example routine and any duplicate follow
   under **"Your routines"**. That label stays "All routines" while no program routine exists. When
   "Up next" picks a program routine, its eyebrow shows the program name on the trailing side;
   the due pill is unchanged. Context menus (duplicate, delete) work as before.

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

## Push / Pull / Legs content

Three routines, `seed.program.ppl.push` / `.pull` / `.legs` ("Push", "Pull", "Legs"; de "Push",
"Pull", "Beine"; timeline letters Pu / Pl / Le, de Pu / Pl / Be, as in the design's shelf).
Metallicadpa's exercises, main lifts converted to 6–10 double progression, bench always the first
push lift, row the first pull lift (hypertrophy doc §4), run as the rotating 5-day split.

| Push | Sets × reps | Rest | | Pull | Sets × reps | Rest | | Legs | Sets × reps | Rest |
|---|---|---|---|---|---|---|---|---|---|---|
| Barbell bench press | 4 × 6–10 | 180 | | **Deadlift** | 2 × 4–6 | 180 | | Barbell back squat | 3 × 6–10 | 180 |
| Overhead press | 3 × 8–12 | 150 | | Barbell row | 3 × 6–10 | 150 | | Romanian deadlift | 3 × 8–12 | 150 |
| Incline DB bench press | 3 × 8–12 | 120 | | Lat pulldown (alt: pull-up, assisted pull-up) | 3 × 8–12 | 120 | | Leg press | 3 × 8–12 | 120 |
| Tricep pushdown ⟷ superset 1 | 3 × 8–12 | 60 | | Seated cable row | 3 × 8–12 | 120 | | Lying leg curl | 3 × 8–12 | 90 |
| DB lateral raise ⟷ superset 1 | 3 × 15–20 | 60 | | Face pull | 5 × 15–20 | 60 | | Standing calf raise | 5 × 8–12 | 60 |
| Overhead tricep extension ⟷ superset 2 | 3 × 8–12 | 60 | | Hammer curl | 4 × 8–12 | 60 | | Cable crunch (optional) | 3 × 10–15 | 60 |
| Cable lateral raise ⟷ superset 2 | 3 × 15–20 | 60 | | Dumbbell curl | 4 × 8–12 | 60 | | | | |

The lat pulldown alternatives are the doc's "Sub: pull_up, assisted_pull_up". The doc's "seated leg
curl equally valid" is commentary, not an alternative. The cable crunch is a normal slot; its
"optional" lives in the detail note ("Optional · abs").

Cadence: each routine every **5** days, offsets **0 / 1 / 3** → Push · Pull · rest · Legs · rest,
repeated (~4 sessions a week, "~4×"; each muscle 3× per 2 weeks). A late session moves the plan like
any every-N-days schedule.

**Why 5 days, not the 6-day source layout (decided 2026-10-03).** The ticket shipped first as each
routine every 3 days, offsets 0/1/2 — Metallicadpa's 6-day PPL with the weekly rest day left to
program text. On screen that meant a 14-day timeline without a single rest day, and the next routine
went overdue after every rest. The product owner chose the rotating 5-day split instead: the rest days
are in the plan, and with volume equated frequency barely matters for hypertrophy (Schoenfeld, Grgic &
Krieger 2019). Accepted cost: the same tables give ~30 % fewer weekly sets per muscle than the 6-day
version, and frequency is below the ≥2×/week floor. Considered and not taken: every 4 days
(Push · Pull · Legs · rest, ~1.75×/week). Sources and the amended content are in the hypertrophy doc §4.
The design canvas (artboards 1, 2 and 6) was updated to the 5-day copy on 2026-10-03. **Session length** (library and detail tile "~50 min") is the app's own
estimate (`RoutineMetricsService.estimatedDurationMinutes`: 40 s per set, the rest between sets,
60 s per exercise) applied to the tables: Push 48, Pull 49, Legs 43 min. The design's "~65 min" was
a placeholder. (Full Body's "~50 min" is the design's figure and stays; the same formula gives it
35 / 39 min.)

## Fighter Strength content

Two routines, `seed.program.fighter.a` / `.b` ("Squat & Press", "Hinge & Pull"; de "Kniebeuge &
Drücken", "Hüftbeuge & Ziehen"; letters A / B). Fighter doc §3 as amended at sign-off: main lifts
3–5, `deadlift` instead of the trap bar, jump shrug default with hang power clean as its
alternative, no neck work. Lifting only — it schedules no conditioning.

| A — Squat & Press | Sets × reps | Rest | | B — Hinge & Pull | Sets × reps | Rest |
|---|---|---|---|---|---|---|
| Box jump · *no goal* | 3 × 3 | 90 | | Jump shrug (alt: hang power clean) · *no goal* | 4 × 3 | 150 |
| Barbell back squat (alt: front squat) | 4 × 3–5 | 180 | | Deadlift | 3 × 3–5 | 180 |
| Barbell bench press (alt: DB bench) ⟷ superset | 4 × 3–5 | 180 | | Overhead press (alt: seated DB press) | 3 × 4–6 | 150 |
| Medicine-ball chest pass ⟷ superset · *no goal* | 4 × 3 | 180 | | Pendlay row (alt: barbell row) | 3 × 5–6 | 150 |
| Pull-up, weighted (alt: lat pulldown) | 3 × 4–6 | 150 | | Rotational med-ball throw · *no goal* | 3 × 3 | 90 |
| Bulgarian split squat (per leg) | 2 × 6–8 | 120 | | Hanging leg raise (alt: cable crunch) | 3 × 8–12 | 90 |
| Ab wheel rollout | 3 × 6–10 | 90 | | | | |

- **No rep goal** = `RoutineProgramExercise(…, fixedReps: 3, …)`: `repMin/repMax` are nil, so the
  installed slot (and its alternatives) get `targetRepMin/Max = nil` and
  `ProgressiveOverloadService` never qualifies them for a weight increase — power lifts, jumps and
  throws progress by speed, height or distance, not reps (fighter doc §5). Sets start at 3 reps.
- "Weighted", "per leg" and "per side" live in the slot notes (the app has no added-load or
  per-side field, fighter doc §6).
- The bench / chest-pass pair is the contrast superset of Kostikiadis et al.: one heavy set, then
  three explosive throws, 180 s rest on both.

Cadence: each routine every **7** days, B **3** days after A (A · – · – · B · – · – · –), with the
program text "at least 48 hours between A and B — if one slips, push the other back". Weekday pairs
(Mon/Thu) are not used: install never writes a weekday plan (P9). **Session length** "~60 min" is
the design's figure; the app's estimate formula hand-applied to the tables gives roughly 62 min for
A and 48 for B. Library level "Combat sports", monogram "FS", shelf cadence "2 sessions a week".

## Architecture

```
Presentation  ProgramLibraryViewModel (@Observable @MainActor)
              ProgramLibraryViewModel+Summaries (static display-model builders)
              ProgramLibraryViewModel+Shelf (ShelfCard / PatternDay builders)
              Views/Programs/{ProgramLibraryView, ProgramDetailView, ProgramDetailSections, ProgramInstallSheet,
                              ProgramComponents, ProgramShelf, ProgramsEmptyStateView}
              RoutinesView: shelf + empty state; navigationDestination(isPresented:) → library,
                            navigationDestination(item: shelfProgramId) → detail
      │  RoutineProgramInstalling (Domain protocol)
Domain        Models/RoutineProgram.swift          value types (program → routines → exercise slots)
              Services/RoutineProgramCatalog.swift  the static content (+Fighter.swift: Fighter Strength)
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
  `guidanceRuleKeys` (stems of `routine_programs.<id>.rule.<stem>.title|detail`), `sourceKeys`
  (`routine_programs.<id>.source.<stem>.name|role`), `ruleLinks` (rule stem → program id; the rule
  gets a `routine_programs.detail.rule_link` "See %@" link, rendered by `ProgramGuidanceCard`, whose
  destination closure `ProgramDetailView` fills with a nested detail) and `showsLengthStat` (the
  detail's third tile is the program length `stat.length|length_label` instead of the session
  length `stat.duration` — true for Full Body only); a slot carries an optional `noteKey`
  (`routine_programs.note.*`, shared across programs); the timeline explanation is
  `routine_programs.<id>.schedule_detail` and a routine's timeline letter is `<seedKey>.short`.
  A new program therefore only adds catalog entries and strings — no view changes (PPL, ticket 06,
  needed only the two catalog fields above). Fighter Strength (ticket 08) added four optional
  program fields — `guidanceTitleKey` (the section heading, default "How to train it"),
  `warningRuleKeys` (rules drawn as "!" in the warning colour), `phaseKeys`
  (`routine_programs.<id>.phase.<stem>.weeks|title|detail` plus `.phases_intro`, rendered by
  `ProgramCampCard`) and `pairsWithConditioning` (`ProgramConditioningPairingRow`, which
  `ProgramDetailView` answers with a `fullScreenCover` of `ConditioningLibraryView`, reading
  `AppDependencies` from the environment like the Routines tab does) — and a slot initializer
  without a rep range (`fixedReps:`, `startReps` + nil `repMin/repMax`).
- **The timeline is derived, not drawn.** `RoutineProgramSchedule.timeline(for:from:dayCount:calendar:)`
  marks day *i* with the routine whose `(i − offset) % cadenceDays == 0`, offsets relative to the
  earliest routine (the same convention as `firstDueDates`). It shows the program as if started
  today; it does not read the user's real schedules.
- **One function feeds both the preview and the written plan.** That function is
  `RoutineProgramSchedule.firstDueDates`. The sheet's preview and the installer both call it with
  the same "routines still to add", so the dates shown are the dates written.
- **The shelf is display models too.** `ShelfCard` (level, name, shelf pitch, routine count, the
  7-day pattern, cadence line, the empty state's monogram and meta line) is built once per catalog
  program in `init`; the pattern is `RoutineProgramSchedule.timeline` over 7 days from a fixed
  reference date, since it does not depend on today. Only `isAdded` moves: `refresh()` sets it from
  `installedRoutineKeys()`. The shelf copy is catalog-keyed like the rest
  (`routine_programs.<id>.pitch_shelf|cadence|mark`), so a new program needs strings only.
- **"Added" follows the Routines list.** `RoutinesView` calls `programLibrary.refresh()` from
  `.onReceive(viewModel.$routines)`, so every refetch (install, delete, CloudKit import) also
  re-derives the shelf state. It costs one `seedKey != ""` fetch per refetch, outside `body`.
- **Grouping on the Routines tab.** `RoutinesViewModel.rebuildCardModels()` publishes
  `cardGroups: [RoutineCardGroup]` and `heroProgramName`, built by
  `RoutinesViewModel.makeCardGroups(routines:heroId:makeCard:)` (`RoutinesViewModel+Groups.swift`).
  Membership is `RoutineProgramCatalog.program(forRoutineSeedKey:)`, a static dictionary over the
  catalog. That is a lookup, never a parse of the key format. Program sections come in catalog
  order, then the own section. The hero is excluded from every group, and a group left empty is
  dropped, so a program whose only remaining routine is the hero shows no section. The label switch to
  "Your routines" counts the hero, though. `RoutinesView` renders `ForEach(cardGroups)` → header +
  `ForEach(group.cards)` inside the existing `LazyVStack`, so the rows stay lazy, value-struct and
  `.equatable()`. `RoutineCardView.programName` is part of its `==`. Titles are localized in the
  view model; the view only uppercases them.
- **Refresh after install.** The installer saves and posts `.cloudKitDataDidChange`.
  `RoutinesViewModel` refetches on that notice, and the refetch also syncs the watch and reconciles
  the calendar and reminders. The routines list and the watch update without a relaunch.
- **Status-bar strip.** The program screens and the Routines tab hide the navigation bar, so
  nothing covers the status bar and scrolled content was legible under the clock (on the Routines
  tab it became visible once the shelf made the list long enough to scroll). On 2026-10-03 the same overlap
  showed on a routine's detail, so the strip now sits on **every** screen that hides the navigation bar
  (the four tab roots, routine / exercise / chart / period-recap details and the program screens) —
  a new screen that hides the bar should add it too. `statusBarBackground()`
  (`Presentation/Views/DesignSystem/StatusBarBackground.swift`) overlays a zero-height `Color.clear` whose **`background`** is the
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
- `GymStreakTests/PushPullLegsProgramTests.swift` covers the 3-routine program: every catalog
  program references only seed exercises; the exact PPL content (deadlift-first Pull at 2 × 4–6 /
  180 s, the row at 3 × 6–10, the optional crunch); Push's two supersets; the every-5-days plan at
  offsets 0/1/3; a restore of Pull + Legs that starts Pull on the chosen day and Legs two days
  later while leaving Push's plan alone; the 14-day Pu · Pl · – · Le · – timeline and shelf pattern; PPL's detail
  showing the session length; and Full Body's single rule link pointing at `ppl`.
- `GymStreakTests/FighterStrengthProgramTests.swift` covers the exact A/B tables (sets, start reps,
  rep goal or none, rest, alternatives), the bench / chest-pass superset, that every power, jump and
  throw slot (and alternative) has no rep goal and never qualifies for a weight increase even with
  every set completed far past 3 reps (a squat at the top of its range as the control), the
  every-7-days plan with B three days after A, the 14-day timeline matching the shelf pattern, and
  the detail models (the section title, "1 · ! · 2 · 3" numbering, the four camp phases, the
  pairing flag, "3 × 3" schemes) while Full Body keeps its plain "How to train it".
- **Known flake (not fixed):** `ExampleRoutineSeederTests.collapsesTwoSeededCopiesIntoTheOlderOne`
  counts global `.cloudKitDataDidChange` posts (`object: nil`). Every program install in a parallel
  suite posts the same notification, so it can read 2 instead of 1. It failed once on 2026-10-03 and
  passed alone and on a full re-run. Fix, if it recurs: scope the observer to the seeder's own posts
  (e.g. an `object`) or serialize the program suites with it.
- `GymStreakTests/RoutineProgramScheduleTests.swift` covers the start choice → first day
  (past-day clamp), offsets relative to the earliest routine being added, Full Body's 14-day
  A · – · B · – timeline, and a synthetic program proving the timeline follows cadence and offsets.
- `GymStreakTests/RoutineCardGroupTests.swift` covers the grouping through a real `RoutinesViewModel`:
  program routines go into their program's section, while own, example and duplicated routines go
  into "Your routines". A partly installed program still gets its section, a program hero names its
  program and leaves the rest of the program in the section, and with no program there is the single
  "All routines" section.
- `GymStreakTests/ProgramLibraryViewModelTests.swift` covers the free-only note across
  free/founder/subscription/lifetime and gating off, the shelf's "Added" state (set on install, kept
  while one routine remains, cleared once none does), Full Body's A · – · B · – · A · – · B shelf
  pattern, a preview limited to missing routines, and the
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
- **Fighter Strength's camp phases are text only.** The routines are the weeks 1–4 version; the app
  does not swap set counts by camp week and does not know a fight date. A real phase layer (possibly
  following the conditioning program's week) is a follow-up, not v1 (fighter doc §9, sign-off (3)).
- **No sparring-day awareness.** "Not before hard sparring" is a rule on the detail screen; the plan
  does not move around sparring days and does not read the conditioning add-on's "I spar hard" flag.
- **Accepted edge cases (ticket 03 review):** `RoutineProgramSchedule.timeline` would trap on
  `cadenceDays == 0` (no catalog program has it), and the detail's timeline goes stale if the screen
  stays open past midnight (it is fetched on appear).
- **Follow-ups parked in Things (Gym Streak, Someday), from the content sign-off:** "Upper/Lower
  routine program" (planned next), "Stall detection: suggest −10 % after repeated misses" (today
  the −10 % rules are text), and "Fighter Strength phases as a program layer" (needs its own
  Monetization Gate). Other goals (5×5, powerbuilding) are out of scope for now.
- Dropped at content sign-off, not built: neck work (weak evidence), the trap-bar deadlift, the
  landmine press, the loaded jump squat and the Pallof press (fighter doc §8).
