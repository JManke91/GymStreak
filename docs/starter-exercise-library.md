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
| Seeder (dedup + version-gated seed) | `GymStreak/Data/Seeding/DefaultContentSeeder.swift` |
| Wiring | `App/AppDependencies.swift` (constructs seeder), `App/GymStreakApp.swift` (`.onAppear`, non-`-UI_TESTING` path) |
| Localized names | `Resources/en.lproj/Localizable.strings` + `de.lproj` (`seed.exercise.*`, `equipment.cable`, `equipment.bodyweight`) |
| iCloud KV entitlement | `GymStreak/GymStreak.entitlements` (`com.apple.developer.ubiquity-kvstore-identifier`) |

### How seeding works

- Every catalog row has a stable `seedKey` (`"seed.exercise.<name>"`) that is **both** the cross-device identity of the exercise and its `Localizable.strings` key. `Exercise.seedKey` is empty for user-created exercises — `!seedKey.isEmpty` is the built-in marker.
- `DefaultContentSeeder.run()` executes at every launch (except UI-testing runs, which use `TestDataSeeder` instead):
  1. **Dedup pass (every launch):** groups exercises by non-empty `seedKey`; duplicates are collapsed into a deterministic survivor (sorted by `createdAt`, then `id.uuidString` — deterministic so concurrent devices keep the SAME record and never delete both copies). Routine references (`RoutineExercise.exercise`, `RoutineExerciseAlternative.exercise`) are re-pointed to the survivor before deletion.
  2. **Seed pass (version-gated):** runs only when the stored catalog version < `SeedExerciseCatalog.currentVersion`, and inserts only rows with `introducedInVersion > lastSeededVersion` whose `seedKey` isn't present, so **deleted seeds are never resurrected**. Rows whose localized name normalizes (case/diacritic/whitespace-folded) to an existing exercise's name are skipped — existing users get the catalog backfilled without lookalikes of exercises they created themselves. Version history: **v1 = unreleased interim policy** (seed only empty libraries; some dev devices stamped it) — **v2 = first shipped catalog** (all 96 rows carry `introducedInVersion: 2` so v1-stamped devices get backfilled).
  3. Version flag lives in `NSUbiquitousKeyValueStore` (propagates across the user's devices) with a `UserDefaults` mirror for no-iCloud accounts; reads take the max of both.

### Why this design (CloudKit constraints)

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

- **Starter routines** (3-day full body, upper/lower, PPL built from seeded exercises) deliberately deferred — needs the same seedKey/versioning treatment on `Routine` and is a more opinionated product call.
- No exercise images/instructions — text-only catalog keeps app size unchanged; media would go through ODR/lazy loading if ever added.
- No "built-in" badge or read-only treatment in the UI — seeded and custom exercises are intentionally indistinguishable to the user.
