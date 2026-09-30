# UI-test data isolation (`-UI_TESTING` never touches iCloud)

## Rule

Any launch with `-UI_TESTING` runs on an **in-memory store with CloudKit off**
(`GymStreakApp.store`, the same branch `-UI_TEST_EPHEMERAL_STORE` takes). Fixture
data from `TestDataSeeder` must never reach the developer's — or anyone's — iCloud
account. Applies to Xcode runs, XCUITests and the fastlane screenshot lanes alike.
Launch arguments are Xcode/XCTest-only, so shipped builds (TestFlight, App Store)
never took this path and were never affected.

## The bug this prevents (found 2026-09-27)

Symptom: delete the app, run it from Xcode again, and the routines and exercises
look right until the CloudKit import finishes — then a full extra copy of every
routine and exercise appears. It gets worse with every Xcode launch.

Root cause, established from the store pulled off the device (see "How it was
diagnosed" below):

1. The shared `GymStreak.xcscheme` had `-UI_TESTING` enabled (since 2026-09-06,
   `bfdc1c4`). `GymStreakApp` then runs `TestDataSeeder.seedData` on every launch
   instead of the real seeders.
2. Before the fix, `-UI_TESTING` alone did **not** select the ephemeral store, so
   the seeder wrote into the real CloudKit-backed store. Each launch inserted a fresh
   fixture set (3 routines Drücken-/Bein-/Ziehen-Tag, 16 exercises, 5 sessions) with
   new UUIDs, and mirroring exported it to the private database.
3. The seeder's "clear existing data" step uses `ModelContext.delete(model:)` — a
   batch delete. The earlier sets vanished locally, but their deletes were never
   exported: every earlier set stayed in CloudKit.
4. After a reinstall, the local store holds only this launch's set (looks correct),
   then the import brings back every set from earlier launches. The device showed
   3 copies with creation times 22:23, 22:25 and 22:26 — one per Xcode launch.

The shared scheme also had `-INITIALIZE_CLOUDKIT_SCHEMA` enabled (since 2026-09-19,
`999a0e2`). Not the cause of the duplicates: it uses a throwaway temp store. But it
starts a second full CloudKit mirror of the private database on every launch, so it
is a one-shot tool and must be switched off again after use (see
`docs/cloudkit-schema-automation.md`).

## Fix

- `GymStreakApp.store`: `-UI_TESTING` implies the ephemeral store. `TestDataSeeder`
  clears and re-seeds on every launch anyway, so no UI test depends on persistence
  across launches.
- The shared scheme: `-UI_TESTING` and `-INITIALIZE_CLOUDKIT_SCHEMA` are disabled
  by default again. With the code guard, enabling `-UI_TESTING` is harmless (the
  data stays on the device).

## Cleaning up an account that already has leaked fixtures

The code fix stops new copies. It does not remove the copies already in CloudKit.
They live in the **Development** environment of whichever Apple ID ran Xcode builds.
Remove them by deleting the `com.apple.coredata.cloudkit.zone` zone of that account's
private database in the CloudKit Console (Development), then delete and reinstall the
app. This also deletes any real data that account holds in Development.

## How it was diagnosed

```sh
xcrun devicectl list devices
# SwiftData put the store in the App Group container, not the app container:
xcrun devicectl device info files --device <UDID> --domain-type appGroupDataContainer \
    --domain-identifier group.com.gymstreak.shared
for f in default.store default.store-wal default.store-shm; do
  xcrun devicectl device copy from --device <UDID> --domain-type appGroupDataContainer \
    --domain-identifier group.com.gymstreak.shared \
    --source "Library/Application Support/$f" --destination ./$f
done
sqlite3 default.store "select ZNAME, hex(ZID), datetime(ZCREATEDAT+978307200,'unixepoch') from ZROUTINE order by ZNAME;"
```

Distinct `ZID`s per duplicate mean new objects were created (a seeder), not one record
imported twice. Creation times one launch apart point at a per-launch writer.

**Dead end, recorded so it is not retried:** the first diagnosis blamed the
reinstall race of the real starter-content seeders (`DefaultContentSeeder` /
`ExampleRoutineSeeder`) and added a post-import dedup pass. That race is real and
the pass stays (`docs/starter-exercise-library.md` → "Post-import dedup"). But it
cannot touch these duplicates: fixture rows carry no `seedKey`, and under
`-UI_TESTING` the real seeders do not run at all.

**Side finding:** the store is in the App Group container
(`group.com.gymstreak.shared`), because SwiftData picks the app group automatically
when `groupContainer:` is not specified. `docs/cloudkit-sync-suspension.md` §1/§4
was corrected accordingly: it had assumed the app's private container.
