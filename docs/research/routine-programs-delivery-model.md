# Routine programs — delivery model (options memo)

**Wayfinder ticket:** `.scratch/routine-programs/wayfinder/03-research-program-delivery-model.md`
**Date:** 2026-09-27 · **Type:** codebase research, no code changes
**Inputs:** `docs/research/routine-programs-hypertrophy.md` (01), `docs/research/routine-programs-fighter-strength.md` (02)

## Recommendation (TL;DR)

1. **A program is a catalog entry, and the installed program is only its routines.** Install creates ordinary
   `Routine`s whose `seedKey` names both the program and the slot (`seed.program.<program>.<slot>`, e.g.
   `seed.program.full_body.a`). A static `SeedProgramCatalog` (Data/Seeding) maps each routine key back to its
   program. **No new `@Model`, no new field, no CloudKit schema deploy.** "Is this program installed?" and
   "which routines belong to it?" are derived from the `seedKey`s already present.
2. **Installed on demand from a catalog, never seeded at launch.** The user taps *Add program*; the install writes
   the routines (and, optionally, their schedules) through a repository. The zero-routine launch seeder is the
   wrong mechanism (see §3).
3. **Must-fix before shipping — the existing seeder would delete installed programs.**
   `ExampleRoutineSeeder.removeSupersededExampleRoutines` runs over *every* routine with a non-empty `seedKey`,
   not just the example routine. An untouched program routine installed after the user's oldest own routine
   matches its "superseded" test and is deleted on a later launch — and on a second device, where CloudKit's
   millisecond rounding makes `createdAt == updatedAt`, that delete then propagates everywhere. The cleanup must be
   scoped to `SeedRoutineCatalog` keys. The dedup pass, on the other hand, is already generic and is exactly
   what programs need (§4).
4. **No program-level rotation or "next routine" concept in v1.** Independent routines with per-routine schedules
   express Fighter Strength and PPL exactly with **weekday** plans (Pro, P9), and all three programs *approximately*
   with the free **every-N-days** cadence. Only Full Body's strict A-B-A / B-A-B over Mon/Wed/Fri can't be
   expressed exactly by any schedule — but the rolling cadence gets very close, and the existing up-next logic
   already alternates (§5). A rotation model is the only thing that would make it exact, and it costs a lot more
   than it returns.
5. **The cap is already solved.** `RoutineCapPolicy.countsTowardCap(_:)` excludes every non-empty `seedKey`,
   so program routines are outside the free cap with no code change. If ticket 04 decides they *should* count, the
   policy turns into a check on the key's prefix (§6).
6. **No watch changes.** Program routines reach the watch as ordinary `WatchRoutine`s; schedules and program
   membership are iOS-only by design (§7).

---

## 1. What the codebase already provides

| Building block | Where | What it gives programs |
|---|---|---|
| `Routine.seedKey: String = ""` | `Domain/Models/Models.swift` | A stable, CloudKit-synced identity for built-in routines; already deployed to Production (2026-08-27, `docs/example-starter-routine.md` → Verification record §1) |
| `SeedRoutineCatalog` / `SeedRoutine` / `SeedRoutineExercise` | `Data/Seeding/SeedRoutineCatalog.swift` | Data shape for built-in routines: exercise seed key, sets, reps, rep range, rest, superset group. Program content fits unchanged |
| Exercise resolution by seed key, dropping deleted exercises, collapsing a broken superset | `ExampleRoutineSeeder.seed(_:exercisesBySeedKey:)` | Reusable install logic |
| Dedup by `seedKey` with a deterministic survivor, re-pointing sessions and schedules | `ExampleRoutineSeeder.deduplicate(_:)` | Generic — it already groups **all** non-empty keys |
| `RoutineSchedule` (`everyNDays` / `weekdays`, `startDate`, `isActive`) as a to-many holding at most one | `Domain/Models/RoutineSchedule.swift` | A program's recommended week, one plan per routine |
| `ScheduleGatingPolicy.isScheduleTypeLocked` (P9) | `Domain/Services/ScheduleGatingPolicy.swift` | Weekday plans are Pro, the cadence is free |
| `RoutineCapPolicy.countsTowardCap` | `Domain/Services/RoutineCapPolicy.swift` | `seedKey.isEmpty` — seeded content is excluded |
| `upNextRoutine` | `RoutinesViewModel` | Soonest-due planned routine; otherwise least-recently trained |
| KVS-mirrored enrollment with tombstones | `Data/Preferences/ConditioningProgramStore.swift` (`docs/fight-conditioning.md` ticket 04) | The precedent for *per-user program state* if it is ever needed, without a CloudKit deploy |

## 2. Representing a program — options

| | A. `seedKey` namespace + static catalog **(recommended)** | B. New `programKey` field on `Routine` | C. New `@Model Program` / `ProgramEnrollment` |
|---|---|---|---|
| Schema change / CloudKit deploy | None | Yes — new field, Production deploy (`docs/cloudkit-schema-automation.md`) | Yes — new record type plus a relationship; relationships have already failed to mirror once (`docs/workout-planning.md` → "why the plan is a to-many") |
| Cross-device dedup | Existing pass, unchanged | Existing pass (still on `seedKey`) | A second dedup for the `Program` rows themselves (`@Attribute(.unique)` is not enforced under CloudKit) |
| Cap exclusion | Already true | Already true | Already true |
| Can carry per-user program state (start date, week, variant) | No — add a KVS value later if needed (option A+) | No | Yes |
| Group a routine the user *made* into a program | No | Possible | Possible |
| Cost | Lowest | Low, plus a deploy | High |

**Why A.** Nothing the three first-release programs need is per-user *state*. 01 settled on no scheduled
deloads and 02 on text-only phases and taper (map, "Decisions so far"), so a program is fully described by static
catalog content plus the routines it created. "Installed", "partially installed" (the user deleted one routine)
and "which card groups under which program header" can all be derived by looking up the present `seedKey`s in
`SeedProgramCatalog`. **Use a catalog lookup, not string parsing** — the key format then stays an implementation
detail, and the example routine's `seed.routine.*` key can never be mistaken for a program.

**A+ (only if a later decision asks for it).** If multi-week progression ("week 3 of 12", a start date,
phase-aware copy) moves out of the fog on the map, add an enrollment value in `UserDefaults` mirrored to iCloud
KVS, copying `ConditioningProgramStore`: last write wins by `updatedAt`, plus a tombstone on leaving. Still no
CloudKit deploy. The conditioning doc gives the reasoning for choosing this over a `@Model`: one small value per
user, and no two-device insert race to reconcile.

**Why not C.** Every guarantee C would add (a program row, membership links) is either derivable (A) or
per-user state (A+), and C pays for it with an irreversible Production schema change, a new relationship
(this codebase's worst CloudKit trap), and a second dedup.

## 3. Installation — on demand, not seeded

The example routine's seeder cannot be reused as the trigger:

- It seeds **only into a store holding zero routines**. Programs are chosen by users who usually already have
  routines.
- Its **version flag is the correctness mechanism** against resurrection
  (`docs/example-starter-routine.md` → "Two mechanisms"). An explicit user install has no resurrection problem to
  solve: the user asked for it, so it never needs a flag.
- The doc already records that a second built-in routine "means rethinking that gate, not appending a row"
  (Dead ends → no per-row `introducedInVersion`).

**Install contract (recommended):**

1. Install inserts the program's routines and resolves exercises by seed key, exactly as `seed(_:…)` does.
   Pin `updatedAt = createdAt`, for consistency with the example routine. This is harmless once the cleanup is
   scoped (§4).
2. **Never insert a routine whose `seedKey` already exists locally.** Re-installing a program only **fills gaps**
   (routines the user deleted). It never adds a "fresh copy" next to an edited one, because the dedup pass would
   then silently collapse the two (§4). If "reset to original" is wanted, it's a separate, explicit action that
   overwrites the existing routine's content in place.
3. **Missing exercises.** The example seeder quietly drops a slot whose seed exercise the user deleted. That's
   fine for an unrequested example, but it's the wrong default for a program the user chose on purpose. Two
   options: (a) re-create the missing seed exercise from `SeedExerciseCatalog`, or (b) install without the slot
   and tell the user. Recommend (a): the user asked for this exact program, so a missing exercise is a gap to
   fill, not a deleted choice to respect. Fighter Strength's four new ballistic seeds (02) reach existing users
   through `DefaultContentSeeder`'s `introducedInVersion` path before any install needs them.
4. Install goes through a repository and the composition root (Hard rules 1 and 5). It is a Data-layer service
   beside `ExampleRoutineSeeder`, sharing the resolution code instead of copying it.
5. Post `.cloudKitDataDidChange` (or refresh `RoutinesViewModel` directly), so the list and the watch update.
6. Localized names are resolved once at install time (device language), as for the example routine.

## 4. Lifecycle — re-install, edit, delete, multiple devices

| Event | Behaviour under option A | Notes |
|---|---|---|
| **Edit / rename** a program routine | Stays a program routine; `seedKey` is never cleared | Same decision as the example routine (`docs/pro-subscription.md` §5c): clearing on edit charges the user for engaging |
| **Duplicate** | `duplicateRoutine` creates a plain `Routine(name:)` with no `seedKey` → an ordinary routine that counts toward the cap | Verified in `RoutinesViewModel.duplicateRoutine` |
| **Delete one routine** | Deleted; the schedule cascades; history survives (denormalized) | The catalog then shows the program as partially installed; re-install fills the gap |
| **Delete the whole program** | A UI action that deletes the program's routines | No program row to clean up |
| **Two devices install before syncing** | Both upload; the existing dedup keeps the same survivor everywhere (oldest `createdAt`, then `id`) and moves sessions and schedules onto it | Already generic over all seed keys (`deduplicate` groups `seedKey != ""`) |
| **Device B edits its copy while A's older copy is still syncing** | Dedup keeps A's older copy; B's **edits are lost** (sessions survive, re-pointed) | The same residual risk the example routine already accepts; bounded to the first minutes after an offline install. Document it, don't engineer against it |
| **Re-install on B before A's routines have imported** | Gap-filling sees no local copies and inserts; dedup then collapses onto the older (possibly edited) copy | Converges correctly. The fresh copy loses, which is what the user wants |
| **Launch cleanup (`removeSupersededExampleRoutines`)** | ⚠️ **Currently deletes untouched program routines** | See below — must be scoped |

**The cleanup trap, in detail.** The cleanup deletes any seeded routine for which
`oldestUserRoutine.createdAt < routine.createdAt && routine.updatedAt == routine.createdAt && no sessions`
holds. A program installed today by a user who has older routines of their own matches all three conditions until
the first workout or edit. On the installing device, `Routine.init`'s two `Date()` calls usually differ by
nanoseconds, which saves it by accident. On any **other** device the imported timestamps are rounded to
milliseconds and compare equal, so that device deletes the routine and the delete **propagates back**. Fix:
restrict the cleanup to keys in `SeedRoutineCatalog.entries` (one predicate or filter), and add a test:
"an untouched program routine installed after user routines survives the seeder". This goes in the first
implementation ticket, because without it the feature loses data.

## 5. Schedules — what the free cadence and P9 can express

The installed routines can each get a `RoutineSchedule`. Checked against `WorkoutPlanningService.nextDue` /
`cadenceAnchor` (the rolling cadence re-anchors on each routine's own last completion):

| Program (01/02 intent) | **Free** — `everyNDays` | **Pro** — `weekdays` (P9) |
|---|---|---|
| **Full Body A/B**, 3×/wk non-consecutive, A-B-A then B-A-B | A and B every **4** days, B's `startDate` 2 days after A → strict alternation every other day (3.5/wk). If the user actually trains Mon/Wed/Fri, the rolling anchors re-settle into A-B-A / B-A-B on their own. The cost is an "overdue" marker on the skipped weekend day | A = Mon/Fri, B = Wed → A trained 2×, B 1× every week (**unequal**, as 01 noted). Weekday masks have no week parity, so the exact pattern is **not expressible** |
| **PPL 6-day**, P/Pl/L/P/Pl/L/rest | Each routine every **3** days, start dates offset by 0/1/2 → a continuous rotation with no built-in rest day (7/wk). A rest day just shifts the rotation by one day | Push Mon/Thu, Pull Tue/Fri, Legs Wed/Sat — **exact** |
| **Fighter Strength**, 2×/wk, ≥48 h apart (Mon/Thu) | A and B every **7** days, starting Mon and Thu. Faithful while the user keeps the days; because each routine drifts independently, a late A can land next to B and break the 48 h rule | A = Mon, B = Thu — **exact** |

**Conclusion.** No program *needs* weekday plans in order to work, but two of the three are only exact with them.
That is a real tension with P9, and it belongs to ticket 04. The options there are: ship cadence plans for
everyone; install weekday plans for everyone as a program-scoped exception to P9; or offer weekday plans as the
Pro upgrade. > **Decided by ticket 04 (2026-09-27):** install suggests the every-N-days cadence for **every tier**. Recovery
> runs on time, not weekdays, so the cadence is the intended model and not a fallback. Install never writes a
> `weekdays` plan; weekday plans stay a Pro option in the schedule sheet. The options below are kept for the record.

**An installer that writes a `weekdays` schedule directly bypasses `ScheduleGatingPolicy`**, so
whatever 04 decides must be applied deliberately at install time, not left to happen by accident.
The example routine's rule — "no schedule the user never chose" — suggests installing the schedule as a
**suggested, pre-filled plan the user confirms**, not a silent write. Leave that call to design (05).

**Rotation concept — not recommended for v1.** The only schedule that can't be expressed is Full Body's exact
A-B-A / B-A-B. A program-level "next routine" would touch `upNextRoutine`, the weekly-goal maths
(`plannedWeek`), calendar sync and the watch's "first routine = up next" contract all at once. Two existing
behaviours already cover the need: the rolling cadence above, and the unplanned fallback in `upNextRoutine`
(least-recently-trained first), which alternates A → B → A and cycles P → Pull → L without any change. The
catch is that it's global across every routine the user has, not program-scoped. Revisit only if device testing
shows the cadence approximation confuses users.

## 6. Telling program routines apart for the cap

> **Decided by ticket 04 (2026-09-27):** program routines do **not** count toward the cap. That is today's
> behaviour, so no code change is needed. The catalog-lookup variant below was not chosen.

- **Today:** `countsTowardCap` returns `routine.seedKey.isEmpty`, so every installed program routine is already
  outside the cap and the nudge counts, with no code change.
- **Exposure is bounded.** The first release has 3 programs → 7 routines at most (2 + 3 + 2). Duplicates are
  impossible (dedup plus gap-filling install), and a duplicated program routine counts. A free user who installs
  everything holds 3 own + 7 program + 1 example routines, and editing lets them reshape the program ones freely.
  That's a monetization question for ticket 04, not a technical one.
- **If 04 decides program routines should count** (all of them, or beyond the first program), the policy
  becomes a catalog lookup — e.g. `countsTowardCap = seedKey.isEmpty || SeedProgramCatalog.contains(seedKey)` —
  still pure, still one rule, with `RoutineCapTests` extended. No model change either way.

## 7. Watch sync impact

None required. `RoutinesViewModel.syncRoutinesToWatch()` sends every routine as a `WatchRoutine`
(id, name, exercises); program routines are indistinguishable from any other, which matches how the example
routine ships. Schedules are not part of the watch DTO (`docs/workout-planning.md`), so the only schedule effect
on the watch is the up-next ordering, which already goes through the payload order. Program membership on the
watch (e.g. a group header) would need a DTO field on **both** targets' copies of `WatchModels` plus watch tests.
Not recommended for v1. No watch test run needed for option A.

## 8. Facts later tickets depend on

- **No CloudKit schema deploy** is needed for option A (`seedKey` has been in Production since 2026-08-27).
- **First implementation ticket must scope `removeSupersededExampleRoutines`** to example-routine keys, with a
  regression test.
- **Seed-key predicates must use `== ""` / `!= ""`**, never `.isEmpty` (it's always false inside `#Predicate`).
- **The install must not bypass P9** unless ticket 04 explicitly decides a program exception.
- **Relationship to the example routine:** because the example seeder only seeds into a store holding zero
  routines, installing a program first (e.g. from onboarding) means the example routine never appears. That's
  probably desirable, and it's an input for the "Relationship to the built-in example routine" fog.
- Per-user program state (start date, current week) → KVS value (A+), only if a later decision needs it.

## Sources (codebase)

`GymStreak/Domain/Models/Models.swift` (`Routine`), `Domain/Models/RoutineSchedule.swift`,
`Domain/Services/RoutineCapPolicy.swift`, `Domain/Services/ScheduleGatingPolicy.swift`,
`Domain/Services/WorkoutPlanningService.swift` (`nextDue`, `cadenceAnchor`, `upcomingCadenceDates`),
`Data/Seeding/ExampleRoutineSeeder.swift` (`runLocked`, `deduplicate`, `removeSupersededExampleRoutines`),
`Data/Seeding/SeedRoutineCatalog.swift`, `Presentation/ViewModels/RoutinesViewModel.swift` (`upNextRoutine`,
`duplicateRoutine`, `syncRoutinesToWatch`), `Data/Sync/WatchModels.swift` (`WatchRoutine`);
docs `example-starter-routine.md`, `workout-planning.md`, `fight-conditioning.md` (ticket 04 persistence),
`pro-subscription.md` §5c/§5f.
