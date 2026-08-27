# Example Starter Routine (built-in example routine)

**Targets:** iOS only. No watch changes and no widget changes — the seeded routine reaches the watch
through the existing `RoutinesViewModel` → `WatchConnectivityManager.syncRoutines` path as an
ordinary routine.

## What it does

A user who opens the Routines tab with **no routines of their own** finds one ready-made routine
waiting instead of `ContentUnavailableView` + "Add routine". Opening it shows, at a glance, what a
well-built routine looks like in this app: rep-range goals, one superset, and rest timers that
differ per exercise. There is no onboarding anywhere else in the app, so this routine *is* the
onboarding — rep ranges, supersets and per-set rest are otherwise invisible until the user happens
to build a routine that uses them.

The routine is deliberately **indistinguishable from a user-created one**: no badge, no read-only
treatment, no special-casing anywhere in the UI. It can be started, edited, duplicated, planned and
deleted like any other routine, and once deleted it never comes back — not on the next launch, not
after an app update, not on a new device.

This is the Phase 2 item `docs/starter-exercise-library.md` deferred under "Deliberate omissions →
Starter routines", and it required the prerequisite named there: `Routine` now carries the same
`seedKey` + versioning treatment `Exercise` already had.

## The routine

One full-body session, chosen so each of the three otherwise-undiscoverable features shows up at
least once and every referenced exercise already exists in `SeedExerciseCatalog`.

| # | Exercise (seed key) | Sets | Reps | Rep range | Rest |
|---|---|---|---|---|---|
| 1 | `barbell_back_squat` | 3 | 8 | 8–12 | 150 s |
| 2 | `barbell_bench_press` | 3 | 8 | 8–12 | 120 s |
| 3 | `lat_pulldown` | 3 | 10 | 10–12 | 90 s |
| 4 | `dumbbell_curl` — superset, position 0 | 3 | 10 | 10–15 | 60 s |
| 5 | `tricep_pushdown` — superset, position 1 | 3 | 10 | 10–15 | 60 s |
| 6 | `plank` | 3 | 1 | — | 60 s |

Content decisions, all deliberate:

- **Weights are `0.0`.** The user's own loads are unknowable and a fake starting number would poison
  their first progress chart.
- **Starting reps are the lower bound of the rep range**, so the routine begins at the bottom of its
  own goal and progressive overload has somewhere to go.
- **The plank carries 1 rep per set and no rep range.** The app has no time-based sets, and the
  honest reading of a rep count for a hold is one hold per set.
- **No `RoutineSchedule`.** A plan the user never chose would start driving weekly goals and
  planning nudges on day one.

## Who gets it

**Any store holding zero routines** — new installs, and existing users who never built one. A user
who already has at least one routine is never touched, and the version is stamped for them so the
question is never asked again.

This is deliberately *looser* than the exercise catalog's stranded-library recovery (which demands a
completely empty store: no exercises, no routines, no history) and deliberately *tighter* than a
blanket backfill.

### The one case "zero routines" gets wrong, and why it is cleaned up rather than gated

On the **first launch of a new device belonging to an existing user**, the routine list is empty
because mirroring has not started — community measurement puts that 20–30 s after launch — and
`NSUbiquitousKeyValueStore.synchronize()` only flushes to disk; it does not wait for the version
flag to download. So the seeder can quite legitimately see "no routines, never seeded" about a user
who has ten routines and deleted the example one months ago, and then upload it to every device
they own.

The dedup pass cannot undo this: the spurious routine carries a `seedKey` and the user's real
routines do not, so they never group together. Two ways out were considered:

- **Gate the seed on a CloudKit signal**, the way `recoverStrandedLibraryIfNeeded()` does.
  **Rejected.** The cost balance is inverted here. There, a first launch spent waiting cost nothing;
  here, a first-launch user would sit in front of the empty state for the length of the settle
  window — which is the exact thing this feature exists to remove. No wait is acceptable on the
  onboarding path.
- **Clean up afterwards** (`removeSupersededExampleRoutines`). **Chosen.** The signal is
  unambiguous and arrives on the next launch: a routine the user created *before* the example
  routine was seeded can only have come from a store that was not actually empty. The seeder then
  deletes the example routine — but only an **untouched** copy, never trained and never edited, so
  a user who started using it in the meantime keeps it. Keeps the fast path fast and makes the rare
  wrong seed self-healing, which is the property `docs/starter-exercise-library.md` argues matters.

One residual false positive remains, and the dedup-first ordering does **not** eliminate it: a
device that has imported the user's older routines but not yet the `WorkoutSession` proving they
trained the example routine still reads it as untouched and deletes it — and that delete
propagates. The blast radius is bounded because history is denormalized: the session survives with
its `routineName` intact and only its `routine` link lost.

One case the cleanup deliberately cannot catch: an existing user with **zero** routines of their
own. There is no older user routine to compare against, so a copy seeded mid-import is
indistinguishable from a legitimate one and stays. The effect is benign — they get the example
routine they would have got anyway — except for the user who had deleted it on another device, who
gets it back once.

"Untouched" is `updatedAt == createdAt` plus no `WorkoutSession` referencing it. `Routine.init`
stamps those two fields with separate `Date()` calls that differ by microseconds, so the seeder
pins them equal at seed time to make the test meaningful.

## Architecture / components

| Piece | File |
|---|---|
| `Routine.seedKey` property | `GymStreak/Domain/Models/Models.swift` |
| Catalog (`SeedRoutine`, `SeedRoutineExercise`, `currentVersion`) | `GymStreak/Data/Seeding/SeedRoutineCatalog.swift` |
| Seeder (cleanup + dedup + version-gated seed + exercise resolution) | `GymStreak/Data/Seeding/ExampleRoutineSeeder.swift` |
| Version-flag seam (shared with the exercise catalog) | `GymStreak/Data/Seeding/SeedCatalogVersionStore.swift` |
| Wiring | `App/AppDependencies.swift` (constructs it), `App/GymStreakApp.swift` (`.onAppear`, right after `defaultContentSeeder.run()`) |
| Tests | `GymStreakTests/ExampleRoutineSeederTests.swift` |
| Localized name | `Resources/en.lproj/Localizable.strings` + `de.lproj` (`seed.routine.full_body_starter`) |

### How seeding works

`ExampleRoutineSeeder.run()` executes at every launch (except UI-testing runs, which use
`TestDataSeeder`), immediately after `DefaultContentSeeder.run()` has committed the exercise
library it resolves against:

1. **Dedup pass (every launch).** Routines are grouped by non-empty `seedKey`; duplicates collapse
   into a deterministic survivor (sorted by `createdAt`, then `id.uuidString` — the same convention
   `DefaultContentSeeder` uses for exercises, so concurrent devices keep the **same** record and
   never delete both copies). Before a loser is deleted, its `WorkoutSession`s and any
   `RoutineSchedule` the user attached are re-pointed at the survivor; its own `RoutineExercise`s
   and `ExerciseSet`s go with it via the cascade rule, so nothing is left dangling.
2. **Cleanup pass.** Removes an untouched example routine that a *new device of an existing user*
   seeded into a store CloudKit had not filled yet — see "The one case 'zero routines' gets wrong"
   above.
3. **Seed pass (version-gated).** Runs only when the stored routine version <
   `SeedRoutineCatalog.currentVersion`, and only into a store holding zero routines.
4. **Exercise resolution.** Each slot points at a `SeedExerciseCatalog` row by `seedKey` and is
   resolved against the live library. A slot whose exercise the user deleted is **dropped, never
   resurrected**, and the remaining slots are renumbered contiguously.
5. **Announcement.** When a routine was actually inserted, removed, or collapsed, the seeder posts
   `.cloudKitDataDidChange`. This is load-bearing rather than defensive: `RoutinesView` is the
   **first tab**, so its `@StateObject` view model is constructed — and has already fetched an empty
   routine list — during the first render pass, *before* `ContentView`'s `.onAppear` runs the
   seeder. Without the notification a first-launch user would meet the empty state and only find the
   routine after relaunching — and a routine the cleanup pass removed would linger on screen after
   it stopped existing. It also carries either change to the watch, since `fetchRoutines()`
   ends in `syncRoutinesToWatch()`. (`DefaultContentSeeder.run()` needs no such post because the
   exercise library is not the first tab.) A launch that seeds nothing stays silent.
6. **Version stamping.** The flag lives in `NSUbiquitousKeyValueStore` under `seedRoutineVersion`
   (so a second device inherits it) with a `UserDefaults` mirror for accounts without iCloud; reads
   take the max of both. It is stamped when the routine is seeded **and** when the store already
   holds routines — but deliberately *not* when the seed was deferred for a thin library.

### Why dedup runs before cleanup

The two passes both delete seeded routines, and the order is load-bearing in both directions.

**Dedup must go first**, because its survivor choice is *deterministic* — sorted by `createdAt`,
then `id.uuidString`, so every device keeps the same record. The cleanup's question ("was this
trained or edited?") is answered from local state that two mid-sync devices can legitimately
disagree about. Running it first would let two devices keep different copies and delete each
other's — the one dedup failure mode `docs/starter-exercise-library.md` calls out as unrecoverable.

That puts the cleanup **downstream of dedup re-pointing a loser's `WorkoutSession`s onto the
survivor**, so it depends on that reassignment being visible through the inverse array. If it were
not, the cleanup would read an untouched routine and delete a trained one, orphaning the very
history dedup had just rescued (`Routine.workoutSessions` has no delete rule, so those sessions
would survive with `routine == nil`). It *is* visible — SwiftData maintains both sides in memory —
and `keepsATrainedExampleRoutineWhenTheTrainingLandedOnTheOtherCopy` pins it. That test is the one
to look at if this order is ever changed.

The alternative (cleanup first) was implemented, tested, and reverted: it keeps the trained copy
rather than the deterministic one, which is locally nicer and globally unsafe.

### Two mechanisms, two different questions

This mirrors the exercise catalog's shape but the weights are different, and confusing the two is
the way to break it:

| | Exercise catalog | Example routine |
|---|---|---|
| "Never resurrect" is enforced by | the per-`seedKey` presence check | **the version flag** |
| The version flag is | an optimisation | **the correctness mechanism** |
| Duplicate prevention across devices is | the dedup pass | the dedup pass (unchanged) |

The reason: the exercise seeder can ask "is a row with this `seedKey` already here?", but the
routine seeder's trigger is an *empty* routine list — there is nothing left to check against once
the user deletes the routine. Without a stamped version flag it would re-seed on the very next
launch. That also means a second device inherits the flag through iCloud KV and does not seed,
which is what keeps duplicates rare in the first place; the dedup pass handles the race where two
devices seed before either flag propagates.

### Deferring instead of stamping

If fewer than `minimumResolvedExercises` (4 of 6) slots resolve, the routine is **not seeded and
the version is not stamped** — the seeder simply tries again on a later launch. Two reasons:

- A two-exercise stump is a worse first impression than the empty state it replaces.
- The library can be genuinely absent *this launch* and present the next: a store rescued by
  `DefaultContentSeeder.recoverStrandedLibraryIfNeeded()` gets its exercises seconds **after**
  `ExampleRoutineSeeder` already ran and found nothing. Deferring is what makes that device get the
  routine on its following launch instead of never. Stamping there would be permanent.

A superset group left with fewer than two resolvable members collapses to standalone exercises — a
one-member superset is just an exercise with a confusing badge.

### CloudKit constraints (the traps inherited unchanged)

- **`@Attribute(.unique)` is silently unenforced** when `cloudKitDatabase != .none` (Apple Forums
  772007). Two devices seeding before they sync **will** both upload the routine. The `seedKey`
  dedup pass with a deterministic survivor is the actual correctness mechanism; the version flag
  only makes the race rare.
- **The version flag can lie about a given store.** It lives in iCloud KV while the routine lives in
  CloudKit, and the two are not written transactionally. Treat it as "some device of this user has
  seeded the example routine", never as "this store holds it". Unlike the exercise catalog there is
  no recovery path for a stranded routine flag, and that is deliberate: the failure mode is one
  missing example routine, not an unusable app, and re-seeding it would be indistinguishable from
  resurrecting a routine the user deleted on another device.
- **New model field is optional/defaulted** (`var seedKey: String = ""`), and no new relationship
  was added — the CloudKit-safety rules for a schema change are satisfied. `Routine` was already in
  `GymStreakSchema.modelTypes`, so no registration change was needed.

### Localization

The routine name is resolved **once at seed time** (device language) into the mutable
`Routine.name`; `seedKey` stays the stable identity. This matches the exercise-catalog decision, and
carries the same consequence: switching the phone language later does not re-localize the name.
`seed.routine.full_body_starter` → "Full Body Starter" (en) / "Ganzkörper-Starter" (de). The name has
to read as an example without a badge, since seeded content is deliberately indistinguishable from
user content in the UI.

## Monetization

**Free**, and structurally so. `docs/monetization-strategy.md` §3 Rule 1 — the routine sits directly
on the aha path (build a routine → train it → see it logged → see the number go up) and exists to
shorten it. Gating the one thing a brand-new user is handed would be the exact inverse of the free
tier's job. It is also, by construction, the user's only routine at the moment it appears, so no cap
could bind on it.

**It is outside the free routine cap, permanently.** `RoutineCapPolicy.countsTowardCap(_:)` counts
only routines with an empty `seedKey`, and `RoutinesViewModel` feeds the cap and the §8 D nudge from
`countableRoutineCount` (recomputed in `rebuildCardModels()`, so no `filter` ever runs in a `body`).
A free user with the example routine present still creates three routines of their own, and the
nudge first appears when they save their *second* — the counts they are shown are theirs, not ours.
Without this, shipping the example routine would have quietly turned "3 free routines" into 2 and
moved the paywall one routine earlier for every new free user (`docs/monetization-strategy.md` §10:
free-user retention and the rating outrank revenue).

The exclusion survives editing and renaming — `seedKey` is never cleared. Clearing it on first edit,
so an adopted example starts counting, was considered and rejected: it charges the user for engaging
with the very thing the routine is teaching, and it makes the cap depend on invisible edit history.
Deleting the example changes nothing about the allowance (it never took a slot), and *duplicating*
it yields an ordinary user routine that counts like any other. See `docs/pro-subscription.md` §5c.

**A free user who keeps the example therefore holds four usable routines, and that is accepted.**
The +1 is bounded and non-farmable — one seeded routine per iCloud account, never restored after
deletion, never multiplied by duplication — and every way of closing it is worse than paying it.
`docs/monetization-strategy.md` §4.2a carries the full reasoning. The nudge copy says "2 of 3
**free** routines used" so that it does not contradict the header subline, which counts all four.

## Testing

`GymStreakTests/ExampleRoutineSeederTests.swift` (18 tests, iOS suite). The iCloud KV half of the
version flag is injected through `SeedCatalogVersionStore` — the real
`NSUbiquitousKeyValueStore` is a single process-wide instance whose contents outlive the app, so a
test that wrote it would stamp the developer's simulator permanently.

Covered: seeds into an empty-routine store with the exact set/rep/rest/superset shape and no
schedule; skips a populated store; never resurrects after deletion; does not seed on a second device
that inherited the flag; collapses duplicates to a deterministic survivor with nothing dangling and
history/plan preserved; drops slots whose exercise was deleted and renumbers; collapses a superset
that lost a partner; defers rather than stamping on a thin library and seeds on the retry; names the
routine from the strings table rather than a literal; deletes a superseded example routine once
CloudKit proves the store was not empty, while keeping one the user created routines *after*, and
keeping one they trained or edited; keeps a trained routine whose training landed on the copy dedup
discarded; announces seeds, removals and collapses to the already-loaded list.

The cap exclusion is covered in `GymStreakTests/RoutineCapTests.swift`: the example routine leaves
all three free slots intact, the nudge counts only the user's own routines, editing/renaming and
deleting it change nothing, a duplicate of it counts, a lapsed Pro user above the cap with a seeded
routine in the store is unaffected, and the counting rule itself is asserted at the policy boundary
without a container.

No watch test run was required — no watch code was touched, and the watch never compiles the
SwiftData `Routine` model (it persists through `RoutineStore` in App Group UserDefaults).

## Release checklist impact

- `Routine.seedKey` is a **SwiftData model change → the CloudKit schema must be deployed
  Development → Production in the CloudKit Console before this ships.**
  The *Development* half needed no special run: Development's just-in-time schema creation
  materialized the field during an ordinary Debug run (observed 2026-08-27 —
  `xcrun cktool export-schema` showed Development ahead of Production by exactly `CD_seedKey` and
  `CD_seedKey_ckAsset`, with 10 record types either side). The reason first recorded here — that
  `seedKey` is a non-optional `String` defaulting to `""`, so *every* synced `Routine` record carries
  it — is **wrong as stated**: a later record query found `CD_seedKey` on none of the eleven live
  `Routine` records in either environment. See "Verification record" §3 for what the evidence does and
  does not settle. `-INITIALIZE_CLOUDKIT_SCHEMA` is for the
  case this one is not: a field that is `nil` or absent on every real record, which JIT never sees.
  Production has no JIT, so the Console deploy stays mandatory either way. The app's `ModelContainer`
  falls back to local-only storage *silently* on a mismatched schema, so a green build and a green
  test suite prove nothing here. See `docs/cloudkit-schema-automation.md`.
  **The deploy happened on 2026-08-27 and was confirmed by export** — see "Verification record" §1
  below, which also carries the commands to re-establish it and the cross-device protocol §4 that a
  deployed record type deliberately does not cover.

## Verification record

Two independent things have to be true before this ships, and they are checked in completely
different ways: the **record type** must exist in the Production CloudKit schema, and the **records**
must behave correctly on more than one device. A deployed type never proves the second — that lesson
is written up in `docs/cloudkit-schema-automation.md` → "Verified Production state", where a deployed
`CD_RoutineSchedule` coexisted with a relationship CloudKit was silently not mirroring.

### 1. `CD_Routine.CD_seedKey` is deployed to Production — verified 2026-08-27

By content, not by the deploy dialog:

```sh
xcrun cktool export-schema --team-id 45VTMQ88RW \
  --container-id iCloud.com.jmanke.gymstreak \
  --environment production --output-file schema-production.ckdb
xcrun cktool export-schema --team-id 45VTMQ88RW \
  --container-id iCloud.com.jmanke.gymstreak \
  --environment development --output-file schema-development.ckdb
diff schema-development.ckdb schema-production.ckdb
grep -c 'RECORD TYPE CD_' schema-production.ckdb
```

- `diff` is **empty** — Development is fully deployed, nothing pending.
- **10** `CD_` record types in Production, one per `GymStreakSchema.modelTypes` entry.
- The Production `CD_Routine` block carries `CD_seedKey STRING QUERYABLE SEARCHABLE SORTABLE` and its
  `CD_seedKey_ckAsset ASSET` companion (the normal oversized-String companion, see
  `docs/cloudkit-schema-automation.md` → "Expected side effects").

This needs only the saved **management** token and no build, device or iCloud account. Re-running it
is the cheapest way to re-establish the fact later, so prefer it over trusting this paragraph.

### 2. The store is CloudKit-backed after the schema change — verified 2026-08-27 (simulator)

The failure this guards against is `ModelContainer(cloudKitDatabase: .private(…))` throwing on a
CloudKit-illegal model and `GymStreakApp.store` taking the **silent** local-only fallback. That check
is local — it validates the model's CloudKit legality, not the deployed schema — so it is observable
without an iCloud account, which is what makes it a simulator job.

Debug build, iPhone 17 Pro simulator (iOS 26.5), booted, **not** signed into iCloud:

- `xcrun simctl launch --console-pty` printed the monitor's state line and **no**
  `CloudKit store unavailable, running local-only:` line — that error is emitted by
  `CloudKitSyncStatusMonitor.logStoreFallback` on exactly this fallback, so its absence is the
  observation, not an inference from silence.
- The live store (`…/Containers/Shared/AppGroup/<id>/Library/Application Support/default.store`, the
  App Group one — **not** the per-app `Containers/Data/Application/<id>` copy, which is a stale
  pre-App-Group leftover and will happily answer a `sqlite3` query with an old schema and zero rows)
  holds **18 `ANSCK*` mirroring tables**, which only `NSPersistentCloudKitContainer` creates.
- `ZROUTINE` carries the migrated `ZSEEDKEY VARCHAR` column, so SwiftData's lightweight migration ran.
- The store holds **exactly one** routine — `Full Body Starter`, `seedKey =
  seed.routine.full_body_starter` — with the shape this document specifies: order 0–5, rep ranges
  8–12 / 8–12 / 10–12 / 10–15 / 10–15 / none, the curl+pushdown superset sharing a `ZSUPERSETID` at
  positions 0 and 1, rest 150/120/90/60/60/60 s, 3 sets each, every weight `0.0`, and **no**
  `RoutineSchedule`.

What this run does **not** show: the Settings sync row read `off` with
`account=CKAccountStatus(rawValue: 3)` (`.noAccount`), because a bare simulator has no iCloud account.
"Sync reports on" is a device observation and belongs to §4.

### 3. Live records on the developer's own account — read 2026-08-27

With a **user** token minted, `cktool query-records` reads what the server actually holds:

```sh
xcrun cktool query-records --team-id 45VTMQ88RW \
  --container-id iCloud.com.jmanke.gymstreak \
  --environment development --database-type private \
  --zone-name com.apple.coredata.cloudkit.zone \
  --record-type CD_Routine --filters "CD_createdAt >= 2020-01-01"
```

(Filtering on `CD_seedKey` directly is possible, but the empty-string literal is awkward to type
correctly and a mistyped filter matches **nothing** instead of erroring — an always-true `CD_createdAt`
predicate sidesteps that. The zone is deliberately not `_defaultZone`, and an unfiltered query fails
on `recordName`; both return empty results that are not evidence of absence.)

Three things came back, and the third is the one that matters:

1. **Both environments are alive and distinguishable.** Development holds 6 `CD_Routine` records,
   Production 5 — the same five (`Push`, `Pull`, `Beine`, `Test Routine`, `Archivtest`, identical
   `recordName`s) plus a Development-only `New Test`. That is exactly the "environment follows the
   build" split, observed rather than assumed, and it confirms the query is reaching the right zone,
   database and account.
2. **No record carries `CD_seedKey` in either environment** — the field name appears zero times across
   all eleven records, including `New Test`. Not empty: **absent**. `CD_schedule` is absent on the same
   records too, so this is CloudKit's ordinary "unset fields are omitted from the record" behaviour.
   **This corrects the reasoning recorded under "Release checklist impact"**, which said the
   Development schema materialized `CD_seedKey` because "every synced `Routine` record carries it".
   The records disprove that as stated. The field *is* in both schemas (§1), so something wrote it
   once — most plausibly the example routine during ticket 01's on-device run, since schemas are
   additive and deleting the record does not remove the field. The evidence cannot yet separate
   "empty strings are omitted" from "these records predate the change and were never re-exported",
   because every routine here was created before 2026-08-26. **The discriminator:** create a new
   user routine on a current build and re-query — if `CD_seedKey` is still absent, empty strings are
   omitted, and the deployed field is load-bearing only for seeded routines.
3. **There is no example routine on this account, and there never will be.** Zero records with
   `seedKey = seed.routine.full_body_starter`, in either environment — correctly, because the account
   holds five routines and `ExampleRoutineSeeder` only seeds into a store holding **zero**.

Point 3 looked at the time like it ruled the account out for §4 — no device signed into it can ever
*seed*, so a naive two-device run would show zero example routines on both, which is indistinguishable
on screen from a working dedup pass. That conclusion was too quick. The seeding does not have to come
from the account: a simulator with **no** iCloud account seeds locally, and signing it in afterwards
uploads that copy. §4 was run that way, on this one Apple ID, and it produced a real duplicate to
converge. The constraint is genuine — an account holding routines never seeds — but it bounds *where
the copies come from*, not whether the protocol can run.


#### The seeded routine's record, read live (2026-08-27)

The simulator holding a correctly seeded `Full Body Starter` was signed into the developer's Apple ID
so its record would export, and the app relaunched. `CKAccountStatus(rawValue: 1)` (`.available`), the
Settings row reached `upToDate`, and mirroring logged successful export events. The Development query
then returned 7 `CD_Routine` records — the account's six plus the seeded one:

```
2026-08-26T13:38:31.942Z  Full Body Starter   CD_seedKey = 'seed.routine.full_body_starter'
```

**`CD_seedKey` exports, with the right value.** That was the one genuinely load-bearing unknown: the
dedup pass groups by non-empty `seedKey`, so had the field not reached the server, a second device
would import the example routine with an empty key, the two would never group, and the user would keep
two copies permanently — the exact failure this ticket exists to catch, and one that is invisible from
the UI.

It also settles the §3 ambiguity in the other direction: `Beine` now reads `CD_seedKey = ''` —
**present and empty**, not omitted. So empty strings do materialize; the records lacking the field are
simply pre-change ones that were never re-exported. The "empty strings are omitted" reading is wrong.

This run also closed §1's remaining half properly: the Settings row was observed reading **on**, with a
real account, on a store carrying the post-`seedKey` schema.

#### A sharp edge found here: the "untouched" test is exact `Date` equality

On the relaunch after the account's six routines imported, `removeSupersededExampleRoutines` **did not
fire**, although this is precisely the "new device of an existing user" case it exists for. The reason
is not the logic:

```
ZCREATEDAT = 809444311.941977000
ZUPDATEDAT = 809444311.941978000   → 954 ns apart
```

`isSuperseded` requires `routine.updatedAt == routine.createdAt`, so a sub-microsecond gap disables the
cleanup for that routine permanently and silently. **The current code is correct** — it pins the two in
`seedIfNeeded`, all 18 `ExampleRoutineSeederTests` pass, and a fresh seed by today's build into a real
SQLite store measured a drift of exactly `0.000000000`. The drifting record was seeded on 2026-08-26 by
a build predating that pin, so no released build can produce one. (Verified on a throwaway simulator,
since every existing simulator has `seedRoutineVersion = 1` stamped and will never seed again. A newly
`simctl create`d device signed into **no** iCloud account *is* unstamped and does seed — that is how
this was measured. The stamp only follows the account, so a fresh device signed in **before** its first
launch inherits it and will not seed.)

Two things are worth keeping from it:

- **The equality test is fragile by construction.** Any future code path that touches `updatedAt` by a
  nanosecond — a migration, a normalisation pass, a well-meant `updatedAt = Date()` in a save helper —
  silently disables the cleanup for that routine, with no failing test and nothing visible in the UI. A
  tolerance-based comparison would be the robust form. Left as-is deliberately: the current code is
  correct and this is not worth a change now, but it is the first thing to suspect if the cleanup ever
  stops firing.
- **CloudKit erases the drift, and the asymmetry favours the design.** Both timestamps exported as
  `2026-08-26T13:38:31.942Z` — millisecond precision. So a device that *imports* the routine sees the two
  values equal even when the device that *seeded* it does not, and the cleanup can therefore give
  different answers on the two devices. Since the cleanup is meant to run on the importing device, this
  works in favour of the intended behaviour rather than against it — but it does mean the seeding device
  is the one place the test can silently fail closed.

### 4. Cross-device behaviour — verified 2026-08-27, on one Apple ID

A second Apple ID turned out to be unnecessary. The race the dedup pass exists for was staged instead
by exploiting the fact that **a simulator with no iCloud account is functionally an offline device**:

- **Device A** — iPhone 17 Pro simulator, holding the `Full Body Starter` seeded 2026-08-26
  (`8973d3f1-…`), signed into the developer's Apple ID.
- **Device B** — a simulator created for the run, launched **before** signing in, so it seeded its own
  independent copy: `Ganzkörper-Starter` (`e1a6d2bf-…`, German because that simulator's locale is de).
  Signing in afterwards uploaded it alongside A's.

That reproduces "two devices seeding before they sync" exactly, without needing airplane mode — which
simulators cannot do anyway, since they share the host's network. Both Debug builds, so both in
**Development**.

The survivor was predictable before the run, which is what makes the result a test rather than an
observation: dedup sorts by `createdAt`, then `id.uuidString`, so A's 2026-08-26 copy had to win on
both devices. The name difference made the survivor unmistakable.

**What happened, in order:**

| Step | Observed |
|---|---|
| B signs in and exports | Server holds **2** `seed.routine.full_body_starter` records — the duplicate CloudKit cannot prevent |
| B relaunches (dedup runs) | B keeps `Full Body Starter`, deletes its own `Ganzkörper-Starter` |
| A relaunches | A keeps `Full Body Starter` — **the same record**, not one each |
| Server settles | Back to **1** record, stable across three polls over 60 s |
| Survivor's contents on B | All six exercises in order, rep ranges 8–12/8–12/10–12/10–15/10–15/none, rest 150/120/90/60/60/60 s, 3 sets each. **Zero dangling `RoutineExercise` rows**. The superset is real, not merely present: curl and pushdown share **one** `ZSUPERSETID` at positions 0 and 1, and the routine holds exactly **one** distinct superset id — checked because "both rows have a superset id" would also be true of two broken one-member supersets |
| Delete on B (through the UI) | Server drops to **0** |
| A relaunches | A's copy is gone too |
| Both relaunch again | Still 0 on both devices and on the server — the version flag prevents re-seeding |

All four acceptance criteria hold: exactly one copy on a second device, deterministic convergence from
a real race with the survivor's contents intact, deletion propagating, and no resurrection afterwards.

**Two things that cost time and are worth knowing next time:**

- **`simctl` devices get shut down out from under you.** Opening the Simulator app shut down Device A,
  which had been booted headlessly. `simctl launch` against a shut-down device fails with
  `Unable to lookup in current state: Shutdown`, and if the failure is not read, polling the store shows
  a frozen value that looks exactly like "the delete never arrived". Check
  `xcrun simctl list devices booted` before believing a negative sync result.
- **Deletions need the receiving app actually running.** Simulators do not reliably get CloudKit pushes,
  so the import happens on launch. A device that is merely booted, with the app suspended, will sit on
  stale data indefinitely.

## Traps found while building this

- **`String.isEmpty` inside a SwiftData `#Predicate` is always false.** It compiles, it runs, it
  throws nothing — it just gives the wrong answer. Measured 2026-08-26 against an in-memory store
  holding exactly one routine whose `seedKey` was `""`: `#Predicate { $0.seedKey.isEmpty }` fetched
  **0** rows and `#Predicate { !$0.seedKey.isEmpty }` fetched **1**. Both predicates are therefore
  constants, not tests. That made `removeSupersededExampleRoutines` silently never fire, and made
  the "seeded routines" fetch quietly return user routines too — with a green build and a green
  suite everywhere else. **Use `== ""` / `!= ""` in every seed-key predicate.**
  `removesAnExampleRoutineThatCloudKitLaterProvedWasNotWanted` is what caught it; the rest of the
  repo was checked and uses `.isEmpty` only *outside* predicate closures, so nothing else is
  affected.
- **`RoutinesView` is the first tab**, so its view model reads the routine list *during the first
  render pass*, before any `.onAppear`. Any launch-time write to routines has to announce itself —
  see step 4 above.
- **Fetch shape matters on this screen.** `run()` counts routines rather than materializing them,
  and only ever fetches the seeded ones (a predicate, not the whole list). The Routines tab is the
  screen this app has already had to rescue from a main-thread hang once
  (`docs/history-performance.md`).

## Dead ends / deliberate omissions

- **No per-row `introducedInVersion`** on `SeedRoutine`, unlike `SeedExercise`. Seeding is gated on
  the store holding *zero* routines, so a second catalog entry added later could never reach a user
  who kept the first one — the append-only version-scoped insertion would be dead code. Adding a
  second built-in routine means rethinking that gate, not appending a row.
- **No stranded-routine recovery**, mirroring `recoverStrandedLibraryIfNeeded()`. See the CloudKit
  section above: an empty routine list is exactly what a user who deleted the routine looks like, so
  a recovery could not tell the two apart, and the cost of getting it wrong (resurrecting a deleted
  routine on every device) outweighs one missing example.
- **The seeder does not re-run after the stranded-library recovery** within the same session. It is
  an `.onAppear` one-shot; the deferred-not-stamped rule already makes the following launch pick it
  up, and threading it into the recovery's async path would mean a second `.cloudKitDataDidChange`
  post for a case that resolves itself.
