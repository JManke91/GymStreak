# CloudKit Schema Automation (Debug Tool)

**iOS target only** (the watch target never uses SwiftData/CloudKit).

## What it does

`CloudKitSchemaInitializer` uploads the app's **complete** SwiftData schema to the CloudKit **Development** environment in one shot — every record type and every field, including optional properties that are currently `nil` everywhere. This removes the manual dance that was previously required before a CloudKit Console "Deploy to Production": creating real in-app data (e.g. completing a workout with an assisted exercise and a body weight entered) just so a non-nil value syncs and materializes the field in the Development schema.

Deploying Development → Production in the CloudKit Console **remains a manual step** — Apple provides no API for it. The release checklist is now:

1. Run the app once with the `-INITIALIZE_CLOUDKIT_SCHEMA` launch argument (Debug build, device/simulator **signed into iCloud**).
2. Watch the Xcode console for `✅ [CloudKitSchemaInitializer]`.
3. CloudKit Console → deploy schema changes to Production.

## How to run it

- **Xcode:** Product → Scheme → Edit Scheme → Run → Arguments → add `-INITIALIZE_CLOUDKIT_SCHEMA`, run once, remove the argument again.
- **CLI:** install the Debug build on a booted, iCloud-signed-in simulator, then `xcrun simctl launch --console booted com.jmanke.gymstreak -INITIALIZE_CLOUDKIT_SCHEMA`.

The app launches normally; the schema upload runs concurrently in the background and prints a ✅/❌ line when finished.

## How it works

- `NSManagedObjectModel.makeManagedObjectModel(for:)` (Core Data ↔ SwiftData interop, iOS 17+) converts the SwiftData `@Model` types into an `NSManagedObjectModel` — no duplicate Core Data model file.
- A throwaway `NSPersistentCloudKitContainer` is created over a **temporary store URL** (never the app's real store), with `NSPersistentHistoryTrackingKey` enabled (required by CloudKit mirroring) and `NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.jmanke.gymstreak")`, `databaseScope = .private`.
- `initializeCloudKitSchema(options: [])` creates temporary representative records for every entity (all attributes populated), uploads them to define the schema, then deletes them. The temp store is removed afterwards.
- Safe to run while the live app container syncs: it only touches record *type* definitions, not sync state or user data.

## Components

| Component | Location | Role |
|---|---|---|
| `GymStreakSchema` | `GymStreak/Domain/Models/GymStreakSchema.swift` | Single source of truth for the model-type list; used by both the app's `ModelContainer` and the initializer. **New `@Model` types must be added here.** |
| `CloudKitSchemaInitializer` | `GymStreak/Data/Sync/CloudKitSchemaInitializer.swift` | `#if DEBUG`-only utility: builds the model, loads the throwaway store, calls `initializeCloudKitSchema`, tears down. |
| Trigger | `GymStreak/App/GymStreakApp.swift` (`init`) | Checks the launch argument and runs the initializer in a detached task. |

## Constraints & research findings (2026-07-11)

- **Requires a signed-in iCloud account** — the call uploads temporary records to the real private database; there is no account-free path. A fresh simulator without iCloud login will fail with an account error.
- **Development environment only.** Production deploy stays manual in the CloudKit Console.
- **Never ships:** the entire utility is `#if DEBUG`-compiled, and additionally requires the explicit launch argument, per Apple's guidance ("should not be used in production or during standard development cycles").
- `databaseScope = .public` is broken for this API (Apple forums thread 682698, "No authToken received for asset"); `.private` is required and matches the app's setup.
- `loadPersistentStores` must complete (synchronously, `shouldAddStoreAsynchronously = false`) before `initializeCloudKitSchema` is called.
- Development schema fields can only be **added**, never removed — reset the Development environment in the CloudKit Console if stale experimental types pile up.
- Optional `.dryRun` / `.printSchema` options exist on `initializeCloudKitSchema` for local validation without upload.
- **Known transient failure (hit on first real-device run, 2026-07-11):** Core Data error 134060, "Failed to initialize CloudKit schema because the requests timed out (a 30s wait failed)". The 30s timeout is an internal, non-configurable limit (`NSPersistentCloudKitContainerSchemaInitializationOptions` has no timeout/retry knob); Apple forums thread 704844 reproduces it as a transient CloudKit-side hiccup. Remedy: the tool retries up to 5× per launch (community practice, not an Apple-documented guarantee — the dev schema is additive, so partial progress persists); verify the result in the CloudKit Console after a run. If it persists across many retries, test with the live app container stopped (unverified contention theory) and check general CloudKit status. Ruled out for this project: hardcoded `com.apple.developer.icloud-container-environment` entitlement (not present) and `.public` scope (we use `.private`).
- Sources: Apple "Creating a Core Data Model for CloudKit", `NSManagedObjectModel.makeManagedObjectModel(for:mergedWith:)` docs, fatbobman "Fixing SwiftData & Core Data Sync: initializeCloudKitSchema".

## Expected side effects (observed on first successful run, 2026-07-11)

- **Extra system fields appear in the schema** and are normal, safe, and deployable:
  - `CD_<field>_ckAsset ASSET` companions on String/BYTES fields — NSPersistentCloudKitContainer stores oversized variable-length values as CKAssets; full schema initialization materializes these upfront, whereas lazy record-driven schema creation only adds them when actually needed.
  - `CD_moveReceipt` + `CD_moveReceipt_ckAsset` on every record type — internal Core Data↔CloudKit mirroring bookkeeping.
- **Harmless log noise during the run:** the live app container logs `CloudSyncObserver: Remote change detected` while the temporary records are created/deleted, and the throwaway container logs error 134407 ("store was removed from the coordinator") plus BGTaskScheduler cancellation errors during teardown — that's the temp store being removed while its mirroring delegate is still winding down. A ✅ line means the upload succeeded regardless.

## Why this design (dead ends considered)

- **Separate Xcode target** (Apple's "best practice" isolation): rejected as over-build for a single-developer app — the launch-argument + `#if DEBUG` gate achieves the same safety without a second target to maintain.
- **Running on every Debug launch:** rejected — it's a network-heavy operation against real CloudKit; Apple and fatbobman both advise running it deliberately, not per-launch.
- **SwiftData-native API:** none exists as of iOS 26 — dropping down to Core Data via `makeManagedObjectModel(for:)` is Apple's documented interop path.
