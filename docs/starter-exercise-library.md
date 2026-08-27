# Starter Exercise Library (built-in default exercises)

`seed.exercise.assisted_pull_up` is classified as a counterweight-assistance exercise. The seed
metadata is reconciled idempotently at launch so existing seeded copies and their linked workout
history gain the correct interpretation without matching localized display names.

**Targets:** iOS only (no watch changes — exercises reach the watch only flattened inside routines via the existing sync path; no widget changes).

## What it does

The app seeds a built-in catalog of **96 common gym exercises** (Big-6 compounds + the standard machine/cable/dumbbell/barbell/bodyweight staples, grouped by body area) into the normal exercise library — for new users on first launch AND as a backfill for existing users' libraries. Catalog rows whose name matches an exercise the user already created (case-, diacritic-, and whitespace-insensitive exact match) are skipped; near-miss names ("Bench Press" vs. "Barbell Bench Press") deliberately coexist — accepted product decision. Seeded exercises behave exactly like user-created ones — editable, deletable, usable in routines (Strong/Hevy model of one flat library).

Decision record (research 2026-07-11): **local bundle, no backend.** A backend (Supabase etc.) for a ~100-row, rarely-changing catalog adds an offline-empty-first-launch failure mode, privacy-label disclosure, and ops cost for zero benefit; every comparable app ships its library locally. Content structure derived from the public-domain [yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db); German names hand-written (wger, the only open German dataset, is CC-BY-SA share-alike). ExerciseDB/RapidAPI rejected (license forbids redistribution). Text-only, no images. Escalation path if remote updates are ever needed: static versioned JSON on a CDN with the bundle as fallback — still no backend.

## Architecture / components

| Piece | File |
|---|---|
| `Exercise.seedKey` property | `GymStreak/Domain/Models/Models.swift` |
| `EquipmentType` + `cable`, `bodyweight` cases | `GymStreak/Domain/Models/EquipmentType.swift` |
| Catalog (96 `SeedExercise` rows, `currentVersion`) | `GymStreak/Data/Seeding/SeedExerciseCatalog.swift` |
| Seeder (dedup + version-gated seed + stranded-library recovery) | `GymStreak/Data/Seeding/DefaultContentSeeder.swift` |
| Version-flag seam (`SeedCatalogVersionStore`, `UbiquitousSeedCatalogVersionStore`) | `GymStreak/Data/Seeding/DefaultContentSeeder.swift` |
| Wiring | `App/AppDependencies.swift` (constructs seeder with `cloudSyncStatus`), `App/GymStreakApp.swift` (`.onAppear` runs the seeder, `.task` runs the recovery — both non-`-UI_TESTING`) |
| Tests | `GymStreakTests/DefaultContentSeederRecoveryTests.swift` |
| Localized names | `Resources/en.lproj/Localizable.strings` + `de.lproj` (`seed.exercise.*`, `equipment.cable`, `equipment.bodyweight`) |
| iCloud KV entitlement | `GymStreak/GymStreak.entitlements` (`com.apple.developer.ubiquity-kvstore-identifier`) |

### How seeding works

- Every catalog row has a stable `seedKey` (`"seed.exercise.<name>"`) that is **both** the cross-device identity of the exercise and its `Localizable.strings` key. `Exercise.seedKey` is empty for user-created exercises — `!seedKey.isEmpty` is the built-in marker.
- `DefaultContentSeeder.run()` executes at every launch (except UI-testing runs, which use `TestDataSeeder` instead):
  1. **Dedup pass (every launch):** groups exercises by non-empty `seedKey`; duplicates are collapsed into a deterministic survivor (sorted by `createdAt`, then `id.uuidString` — deterministic so concurrent devices keep the SAME record and never delete both copies). Routine references (`RoutineExercise.exercise`, `RoutineExerciseAlternative.exercise`) are re-pointed to the survivor before deletion.
  2. **Seed pass (version-gated):** runs only when the stored catalog version < `SeedExerciseCatalog.currentVersion`, and inserts only rows with `introducedInVersion > lastSeededVersion` whose `seedKey` isn't present, so **deleted seeds are never resurrected**. Rows whose localized name normalizes (case/diacritic/whitespace-folded) to an existing exercise's name are skipped — existing users get the catalog backfilled without lookalikes of exercises they created themselves. Version history: **v1 = unreleased interim policy** (seed only empty libraries; some dev devices stamped it) — **v2 = first shipped catalog** (all 96 rows carry `introducedInVersion: 2` so v1-stamped devices get backfilled).
  3. Version flag lives in `NSUbiquitousKeyValueStore` (propagates across the user's devices) with a `UserDefaults` mirror for no-iCloud accounts; reads take the max of both. Both halves go through `SeedCatalogVersionStore` so tests can drive them — the real KV store is a single process-wide instance whose contents outlive the app, so a test that wrote it would stamp the developer's simulator permanently.

### Stranded-library recovery (`recoverStrandedLibraryIfNeeded()`)

The flag and the seeded rows live in **different stores** (iCloud KV vs. CloudKit) and are not written transactionally, so a device can end up carrying "already seeded v2" over a store that holds nothing at all. `run()` then refuses to seed for the lifetime of the install and the library stays empty forever, with no way out from inside the app. Reproduced 2026-08-13 on a simulator: `cloud=2 local=0`, store had 0 exercises, and CoreData SQL logging showed the seeder's fetch with zero `INSERT INTO ZEXERCISE`.

How it happens: the KV record lives outside the app container and survives deleting the app (and, on a simulator, resetting its data), while the SwiftData store does not. In production the same shape appears whenever the flag arrives but the data doesn't — mirroring blocked or never set up, the CloudKit schema not deployed to production, or the user purging the app's data from iCloud.

The recovery runs once per launch from `GymStreakApp`'s `.task` and re-seeds only when both hold:

- **The store is completely empty** — no exercises, no routines, no history. Deliberately stricter than "no seeded exercises": a user who deleted the built-ins but kept their own content made a choice, and the append-only rule ("deleted seeds are never resurrected") still governs that case. The cost is that a partially-populated stranded store is not recovered; erasing/reinstalling is the way back for those.
- **CloudKit has proved it cannot explain the emptiness** — see the gate below. Waiting for that signal is what keeps the recovery off a new device of an existing user, which starts empty and fills in from CloudKit moments later; seeding into that window would upload 96 rows only for the next dedup pass to delete them.

#### The gate (fixed 2026-08-26)

The two failure modes are **asymmetric**, and that is what decides the design:

| Failure | Consequence | Self-healing? |
| --- | --- | --- |
| Seeded too eagerly | Duplicate catalog, uploaded, then collapsed deterministically by the next launch's `deduplicate()` pass (imported originals win on `createdAt`). Visible in the UI and pushed to the watch until that next launch. | Yes |
| Seeded too conservatively | Empty library forever, with no way out from inside the app. | **No** |

So the gate biases towards seeding, but never before mirroring has had a real chance:

| Status | Decision |
| --- | --- |
| `.off` / `.failing` | Seed at once — nothing will ever arrive (signed out, the local-only store fallback, an export CloudKit keeps rejecting). |
| `.syncing` | Never seed, however long it takes. A mirroring event is genuinely in flight; this is the new device of an existing user, mid-import. Outranks both timers below. |
| `.upToDate` / `.waiting` | Seed once **either** `hasCompletedImportThisSession` is true **or** the settle window has elapsed — then wait out the import-burst grace and re-read the store before committing. |

`CloudSyncStatus.hasCompletedImportThisSession` was added for this (`CloudKitSyncStatusMonitor` sets it on the first `.import` event with `endDate != nil && succeeded`). It is the real signal and is deliberately **never persisted**: a flag restored from `UserDefaults` would say "arrived" about a session that is over, which is precisely the trap `lastSuccessfulSync` falls into. Two timers back it up:

- **`settleWindow` (45 s, injectable)** — how long the recovery waits for CloudKit to report *anything at all* before it stops waiting for proof. Covers the device where no event ever arrives.
- **`importBurstGrace` (3 s, injectable)** — waited out after the import flag fires, before acting on it, because import events arrive in bursts. After the grace the recovery re-reads live state and store emptiness rather than trusting the event that woke it; a follow-up batch that opened meanwhile (`.syncing`) sends it back to waiting.

**The offline case is handled, not omitted.** `makeState()` returns `.waiting` whenever `NWPathMonitor` reports no network, and offline never quiesces, so waiting for quiescence would strand an offline device for the session. `.waiting` is therefore treated exactly like `.upToDate`: recovered on the settle window. That is the asymmetry argument applied literally — the user gets a usable library now, and a later import merges through the same dedup pass.

The whole cost of both timers is one launch's delay on a device that is about to be re-seeded anyway; every later launch is handled by `run()` and waits for nothing.

#### Two gates that look right and are not (both tried, both reverted)

- **`lastSuccessfulSync != nil`** (shipped 2026-08-13, defect found 2026-08-18, fixed 2026-08-26). It cannot mean "this session's transfer finished": `CloudKitSyncStatusMonitor` restores it from `UserDefaults.standard` in `init`, so it describes some past session of this *install*. It was wrong in **both** directions — it never fired on a device that had never completed a transfer (the exact dead end the recovery exists to escape) and it passed mid-import on a device whose defaults survived a store rebuild.
- **Bare `state == .upToDate`**, matching `RoutinePlanLinkRepair`. Reverted 2026-08-26. `makeState()` returns `.upToDate` whenever no mirroring event is in flight, and `statusUpdates()` yields the current status synchronously on subscribe — so at cold launch, with no events opened yet, the *first* status of every session is `.upToDate`. Since the recovery's trigger is an empty store, it would seed all 96 rows on loop iteration one, straight into an existing user's import window; the `guard isStoreEmpty` at the top of the loop cannot save it because there is no second iteration. **`RoutinePlanLinkRepair` is not a precedent**: it tolerates an optimistic `.upToDate` only because it *no-ops* on an empty store (`guard !schedules.isEmpty`), whereas this recovery's action is *conditioned* on emptiness — the same gate means the opposite thing here.
- Also rejected: a **fixed settle delay alone**, with no real signal behind it. It closes the iteration-one hole, but it never becomes more certain no matter how long it waits. It survives only as the backstop.

#### What is documented fact and what is community measurement

Researched 2026-08-26 via the `ios-api-researcher` agent, because the timer values depend on it:

- **Fact (Apple docs).** `NSPersistentCloudKitContainer.Event` shape: `type`, `endDate`, `succeeded`, `error`; `endDate != nil` means finished. Apple's own WWDC22 test helper uses `endDate != nil` as the completion gate.
- **Fact (Apple staff forum reply, [thread 744709](https://developer.apple.com/forums/thread/744709)).** A successful `.import` event means the device is "current" with what is in iCloud. This is what makes `hasCompletedImportThisSession` a real signal rather than a heuristic.
- **Community consensus, not Apple-documented.** `.import` events **burst** — several consecutive events within a few seconds ([crunchybagel](https://crunchybagel.com/nspersistentcloudkitcontainer/)); debouncing a few seconds is common practice. This is why `importBurstGrace` exists.
- **Community measurement, not Apple-published.** Mirroring does not *begin* until roughly **20–30 s after launch**, and a large dataset can take 1–2 minutes to surface ([fatbobman](https://fatbobman.com/en/posts/coredatawithcloudkit-4/)). This is why `settleWindow` is 45 s and not 10 s: a window inside that start latency is the reverted `.upToDate` bug on a delay — it expires while a perfectly healthy importing device has simply not posted its first event yet.
- **Genuinely undocumented.** Whether an `.import` event fires and succeeds at all when the private database holds no records of the app's types, and whether an early batch can complete successfully while data-bearing batches are still pending. Both are why the design never relies on the flag alone: the settle window covers the first, the burst grace plus the post-grace store re-read cover the second.
- **Undocumented by Apple, confirmed by our own measurement.** Offline, CloudKit opens a mirroring event and never ends it (`state=syncing hasNetwork=false inFlight=1`), which is why `makeState()` lets `!hasNetwork` outrank `eventsInFlight`.

**Accepted residual risk.** If an import event ever completes having applied zero records while more are pending beyond the burst grace, the recovery seeds and the catalog is duplicated for one session. That is the self-healing side of the asymmetry and is accepted deliberately.

#### Main-actor cost of the recovery

Small but real, and worth knowing before this loop grows. `recoverStrandedLibraryIfNeeded()` runs
from a launch `.task`, and its first statement reads `storedCatalogVersion`, which calls
`NSUbiquitousKeyValueStore.default.synchronize()` **synchronously on the main actor before the
first `await`** — `.task` does not save you from that (CLAUDE.md concurrency rule 7). Then
`isStoreEmpty` runs three `fetchCount`s per status event rather than once. Both are bounded and
cheap today: the loop only stays alive while the store is empty, so on a normal device it ends
after one or two events. If this ever gains per-event work beyond a count, move it off the main
actor first.

#### Unverified in production (2026-08-26)

Whether `hasCompletedImportThisSession` actually flips on a real device is the one link with no
automated coverage — the unit tests drive a stubbed status provider, and whether an `.import`
event fires and succeeds against a private database holding no records of the app's types is
undocumented (see above). **The failure mode is graceful:** if it never flips, the settle window
recovers the device anyway, just more slowly, so the gate is strictly better than the old one in
every case rather than conditionally better. To check it, run on a device signed into iCloud and
watch the Xcode console for the `#if DEBUG` line in `CloudKitSyncStatusMonitor+Logging.swift`:
`☁️ [CloudKitSyncStatusMonitor] event type=import ended=true succeeded=true`.

#### Test shape (load-bearing)

`GymStreakTests/DefaultContentSeederRecoveryTests.swift`. A "must not seed" assertion drives `StubCloudSyncStatus.finish()` and asserts on the recovery's **return value**; a "seeds only after waiting" assertion asserts an elapsed-time **lower bound**. Neither `Task.yield()` nor a bare count check proves anything — both are equally satisfied by a recovery that is merely still suspended, and two tests written that way during the reverted attempt passed against the broken gate and the fixed one alike. All five tests added with the fix were verified to fail against the old gate before being accepted (2026-08-26: 5 failed, the 4 pre-existing tests still passed).

After a successful recovery the seeder posts `.cloudKitDataDidChange`, which is what makes the already-loaded view models refetch and carries the catalog to the watch via `ExerciseCatalogSyncCoordinator` — `run()` needs neither, because it commits before any view model reads the store.

### Why this design (CloudKit constraints)

- The version flag is an optimisation, not the correctness mechanism, and it can lie about a given store — hence the recovery above. Treat it as "some device of this user has seeded v2", never as "this store holds the catalog".
- **CloudKit-backed SwiftData cannot enforce uniqueness** — `@Attribute(.unique)` is silently unenforced when `cloudKitDatabase != .none` (Apple Forums 772007). Two devices seeding independently WILL both upload the catalog. The seedKey dedup pass is the actual correctness mechanism; the KV-store version flag and the name-collision skip just make duplicates rare in the first place.
- Residual accepted race: a fresh device of an existing iCloud user can seed before the KV flag or CloudKit data arrives → duplicates exist briefly and are cleaned deterministically on the next launch.
- **Localization decision:** the localized name is resolved **once at seed time** (device language) into the mutable `Exercise.name`; `seedKey` stays as stable identity. Switching the phone language later does not re-localize names. The display-time alternative (store key, resolve in views) was deliberately rejected — it would touch every view reading `.name`, the AI coach's `ExerciseNameResolver`, and watch sync.

## Catalog maintenance rules

- **Append-only:** never remove or rename a `seedKey`. New exercises: bump `SeedExerciseCatalog.currentVersion`, add rows with `introducedInVersion` = the new version, add `seed.exercise.*` strings to **both** `.strings` files.
- Muscle groups must exactly match `MuscleGroups.allKeys` (case-sensitive, first entry = primary); avoid `"General"`.
- Don't "fix" a seeded exercise's name by editing the catalog row's strings — users may have synced/edited it; a strings-file change only affects future seeds.

## Release checklist impact

- `Exercise.seedKey` is a **SwiftData model change → the CloudKit schema must be manually deployed in CloudKit Console before this ships** (see memory note: sync silently fails in TestFlight/prod otherwise).
- New entitlement (iCloud key-value store) — automatic signing regenerates profiles; App ID already has iCloud capability.

## Dead ends / do-not-retry

- Separate local-only `ModelConfiguration` for seed data — impossible: SwiftData force-unifies related models into one store and `Exercise` has relationships into the synced graph (Apple Forums 738961/743863).
- Bundled pre-built read-only `.store` — incompatible with CloudKit-synced schemas.
- `@Attribute(.unique)` for dedup — silently unenforced under CloudKit.
- A first-launch `UserDefaults` flag alone — fails on second device/reinstall; must be paired with the seedKey dedup pass.
- Per-launch dedup without a deterministic survivor sort — dangerous: two devices could each keep a different copy and delete the other's, losing both.

## Deliberate omissions / Phase 2

- **Starter routines** — shipped, in reduced form: one built-in full-body example routine for users with no routines of their own, seeded from these catalog rows. `Routine` got the same `seedKey`/versioning treatment as `Exercise`, with one difference that matters — the version flag is the *correctness* mechanism there rather than an optimisation, because an empty routine list gives the seeder nothing to check a `seedKey` against. See `docs/example-starter-routine.md`. The wider set (upper/lower, PPL) remains deferred as a more opinionated product call.
- No exercise images/instructions — text-only catalog keeps app size unchanged; media would go through ODR/lazy loading if ever added.
- No "built-in" badge or read-only treatment in the UI — seeded and custom exercises are intentionally indistinguishable to the user.
