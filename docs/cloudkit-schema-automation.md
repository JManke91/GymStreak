# CloudKit Schema Automation (Debug Tool)

**iOS target only** (the watch target never uses SwiftData/CloudKit).

## What it does

`CloudKitSchemaInitializer` uploads the app's **complete** SwiftData schema to the CloudKit **Development** environment in one shot — every record type and every field, including optional properties that are currently `nil` everywhere. This removes the manual dance that was previously required before a CloudKit Console "Deploy to Production": creating real in-app data (e.g. completing a workout with an assisted exercise and a body weight entered) just so a non-nil value syncs and materializes the field in the Development schema.

Deploying Development → Production in the CloudKit Console **remains a manual step** — Apple provides no supported API for it (re-confirmed 2026-08-17, see "Verifying the deployed schema headlessly" below). The release checklist is now:

1. Check whether the release changed the persisted model at all — see "Which changes produce a Console diff" below. If no `@Model` declaration and no `GymStreakSchema.modelTypes` entry changed, there is nothing to deploy and steps 2–5 are a no-op.
2. Run the app once with the `-INITIALIZE_CLOUDKIT_SCHEMA` launch argument (Debug build, device/simulator **signed into iCloud**).
3. Watch the Xcode console for `✅ [CloudKitSchemaInitializer]`.
4. CloudKit Console → deploy schema changes to Production.
5. **Verify by content, not by the deploy dialog** — `xcrun cktool export-schema` both environments and diff them (exact commands below). This is the only step that produces evidence rather than an inference.

## How to run it

- **Xcode:** Product → Scheme → Edit Scheme → Run → Arguments → add `-INITIALIZE_CLOUDKIT_SCHEMA`, run once, remove the argument again.
- **CLI:** install the Debug build on a booted, iCloud-signed-in simulator, then `xcrun simctl launch --console booted com.shotat24fps.GymStreak -INITIALIZE_CLOUDKIT_SCHEMA`. That argument is the **app bundle identifier** (`PRODUCT_BUNDLE_IDENTIFIER`), which is *not* the CloudKit container suffix: the container is `iCloud.com.jmanke.gymstreak`, the app is `com.shotat24fps.GymStreak`. (Corrected 2026-08-17 — this line previously used the container suffix as the bundle id, which `simctl` rejects.)

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
- **Development environment only — and the build type decides the environment.** A dev-signed build run from Xcode (or a Debug build on a simulator) resolves to Development; **TestFlight and App Store builds always use Production and cannot use Development** (Apple, "Testing Your CloudKit App"). Two consequences: running the TestFlight build of a release never updates the Development schema, and `initializeCloudKitSchema` can never create a record type in Production — Production rejects new types outright ("Cannot create new type … in production schema", Apple DTS, forums thread 819507). Production also has **no just-in-time schema creation**, which is what makes the manual Console deploy mandatory rather than optional. The environment can be pinned with the `com.apple.developer.icloud-container-environment` entitlement; this project does not set it and relies on the signing default.
- **Never ships:** the entire utility is `#if DEBUG`-compiled, and additionally requires the explicit launch argument, per Apple's guidance ("should not be used in production or during standard development cycles").
- `databaseScope = .public` is broken for this API (Apple forums thread 682698, "No authToken received for asset"); `.private` is required and matches the app's setup.
- `loadPersistentStores` must complete (synchronously, `shouldAddStoreAsynchronously = false`) before `initializeCloudKitSchema` is called.
- Development schema fields can only be **added**, never removed — reset the Development environment in the CloudKit Console if stale experimental types pile up.
- `NSPersistentCloudKitContainerSchemaInitializationOptions` has exactly two members: `.printSchema` (print the generated record definitions) and `.dryRun` (validate the model and build the records **without uploading**). `CloudKitSchemaInitializer` passes `options: []`; temporarily passing `[.printSchema, .dryRun]` prints the full expected schema — every record type and field — with no network write. Reach for it only to inspect what the *client* intends to upload; to learn what CloudKit actually holds, export the live schema instead (see "Verifying the deployed schema headlessly" below) — that needs no build, no iCloud-signed-in device, and no code edit.
- **Known transient failure (hit on first real-device run, 2026-07-11):** Core Data error 134060, "Failed to initialize CloudKit schema because the requests timed out (a 30s wait failed)". The 30s timeout is an internal, non-configurable limit (`NSPersistentCloudKitContainerSchemaInitializationOptions` has no timeout/retry knob); Apple forums thread 704844 reproduces it as a transient CloudKit-side hiccup. Remedy: the tool retries up to 5× per launch (community practice, not an Apple-documented guarantee — the dev schema is additive, so partial progress persists); verify the result in the CloudKit Console after a run. If it persists across many retries, test with the live app container stopped (unverified contention theory) and check general CloudKit status. Ruled out for this project: hardcoded `com.apple.developer.icloud-container-environment` entitlement (not present) and `.public` scope (we use `.private`).
- Sources: Apple "Creating a Core Data Model for CloudKit", Apple SwiftData "Syncing model data across a person's devices" (the canonical DEBUG-only bridge snippet), `NSManagedObjectModel.makeManagedObjectModel(for:mergedWith:)` docs, Apple "Testing Your CloudKit App" (environment selection), Apple DTS on forums thread 819507 (Production rejects new types; wrong-container diagnosis), fatbobman "Fixing SwiftData & Core Data Sync: initializeCloudKitSchema".
- **Our bridge deliberately diverges from Apple's snippet** (re-confirmed 2026-08-17): Apple's version points the temporary `NSPersistentStoreDescription` at the *real* store URL, which forces it to run before the app's `ModelContainer` is created. `CloudKitSchemaInitializer` uses a throwaway temp store instead, so it is independent of container-creation order and safe to run alongside the live container.

## Expected side effects (observed on first successful run, 2026-07-11)

- **Extra system fields appear in the schema** and are normal, safe, and deployable:
  - `CD_<field>_ckAsset ASSET` companions on String/BYTES fields — NSPersistentCloudKitContainer stores oversized variable-length values as CKAssets; full schema initialization materializes these upfront, whereas lazy record-driven schema creation only adds them when actually needed.
  - `CD_moveReceipt` + `CD_moveReceipt_ckAsset` on every record type — internal Core Data↔CloudKit mirroring bookkeeping.
- **Harmless log noise during the run:** the live app container logs `CloudSyncObserver: Persistent store change detected` while the temporary records are created/deleted, and the throwaway container logs error 134407 ("store was removed from the coordinator") plus BGTaskScheduler cancellation errors during teardown — that's the temp store being removed while its mirroring delegate is still winding down. A ✅ line means the upload succeeded regardless.

## Verifying the deployed schema headlessly (`cktool`, 2026-08-17)

`xcrun cktool` (bundled with Xcode) reads either environment's schema without the Console UI, which turns "the diff was empty so Production is probably fine" into an actual observation. This is the authoritative check.

```sh
xcrun cktool export-schema --team-id 45VTMQ88RW \
  --container-id iCloud.com.jmanke.gymstreak \
  --environment production --output-file schema-production.ckdb

xcrun cktool export-schema --team-id 45VTMQ88RW \
  --container-id iCloud.com.jmanke.gymstreak \
  --environment development --output-file schema-development.ckdb

diff schema-development.ckdb schema-production.ckdb   # empty ⇒ fully deployed
grep -c 'RECORD TYPE CD_' schema-production.ckdb      # must equal GymStreakSchema.modelTypes.count
```

- **Team is `45VTMQ88RW`** (`DEVELOPMENT_TEAM` of the app targets; the watch **UI-test** target's `F89C86WVJX` is not the CloudKit team). `xcrun cktool get-teams` prints it.
- **Needs a management token, not a user token.** Create it in CloudKit Console → the **Settings** section of your user account → generate a CloudKit Management Token; it is shown once. Store it with `xcrun cktool save-token --type management` (keychain by default, `--method file` writes `~/.config/cktool`). Resolution order is `--token` → `CLOUDKIT_MANAGEMENT_TOKEN` → `~/.config/cktool` → keychain, so once saved every call is headless. **The interactive prompt needs a real TTY** — running `save-token` without the token argument inside a non-interactive shell fails with "Interaction was required while running in non-interactive mode".
- Output is CloudKit Schema Language: one indented `RECORD TYPE CD_<Model> ( … );` block per model, listing every field with its type. Note that mirrored relationships appear as **`STRING`** fields holding the related record name (`CD_schedule`, `CD_routine`, …), not as `REFERENCE` — `REFERENCE` shows up only for CloudKit's own `___`-prefixed system fields. Uniform across all ten types, so it is a mirroring convention, not a defect. To-many relationships get **no** field on the parent: the edge exists solely as the child's back-reference, so `Routine.routineExercises` correctly has no `CD_routineExercises`.
- Both flags are genuinely honoured: an invalid `--environment` is rejected by argument parsing, and a wrong `--container-id` fails with `authorization-failed`, so identical exports mean identical schemas rather than a cached or ignored request.
- **`cktool` cannot deploy to Production.** `import-schema` is documented and demonstrated only against `--environment development` ("applies a file-based schema definition against the development database for testing"). Apple's "Deploying an iCloud Container's Schema" names the Console as the only migration path, and the one real-world CLI attempt on record (forums thread 777449) returned `invalid-scope`. This is the same wall as `initializeCloudKitSchema`'s "Cannot create new type … in production schema", not a way around it. No public CloudKit Web Services deploy endpoint exists either (the `POST …/management/schema` endpoint in brightdigit/MistKit#135 is reverse-engineered, not published).
- **Never run `xcrun cktool reset-schema` on this container.** It takes no `--environment` flag by design: it rewrites the *Development* schema to match Production **and deletes all Development data**, unconditionally.
- Sources: Apple ["cktool"](https://developer.apple.com/icloud/ck-tool/), ["Automating CloudKit Development"](https://developer.apple.com/icloud/cloudkit/automating/), the Xcode-bundled [`cktool(1)` man page](https://keith.github.io/xcode-man-pages/cktool.1.html), ["Deploying an iCloud Container's Schema"](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema), ["Integrating a Text-Based Schema into Your Workflow"](https://developer.apple.com/documentation/cloudkit/integrating-a-text-based-schema-into-your-workflow), WWDC21 ["Automate CloudKit tests with cktool and declarative schema"](https://developer.apple.com/videos/play/wwdc2021/10118/), and forums thread [777449](https://developer.apple.com/forums/thread/777449) (CLI production deploy → `invalid-scope`).

### Querying live records for diagnosis (2026-08-17)

Whether a *record* actually reached the server is a different question from whether its *type* is deployed, and answering it is what separates "never exported" from "exported but never imported" when a model appears not to sync. `cktool query-records` answers it, but four traps each produce an empty result that looks like proof of absence:

```sh
xcrun cktool query-records --team-id 45VTMQ88RW \
  --container-id iCloud.com.jmanke.gymstreak \
  --environment production \
  --database-type private \
  --zone-name com.apple.coredata.cloudkit.zone \
  --record-type CD_RoutineSchedule \
  --filters "CD_isActive == 1"
```

- **The zone is not the default.** `NSPersistentCloudKitContainer` mirrors everything into the custom zone **`com.apple.coredata.cloudkit.zone`**; `cktool` defaults to `_defaultZone`, which holds none of the app's data and returns zero rows without erroring. (Multiple store configurations would each get their own zone; this app has one.)
- **A `user` token is required, not the management token** used for `export-schema` — the wrong type fails with "Session has expired or is invalid. A new user token may be required." Generate it at [`icloud.developer.apple.com/dashboard/account/tokens`](https://icloud.developer.apple.com/dashboard/account/tokens), then store it with `xcrun cktool save-token --type user` (real TTY required). It is **bound to the Apple ID signed into the Console when it is minted**, and CloudKit's private database is per-user — so it must be the same Apple ID as the iCloud account on the device whose data you are looking for, not the developer account, or you query a different person's empty database. Apple documents user tokens as interactive-only ("cannot be automated") and short-lived (hours), so expect to re-mint.
- **Unfiltered queries fail.** A match-all predicate goes through the system `recordName` field, which Core Data never marks queryable — it marks its own `CD_` attributes `QUERYABLE` but has no reason to index `recordName`, because (per an Apple Frameworks engineer, forums thread 655392) `NSPersistentCloudKitContainer` never queries the private database at all. Expect `Field 'recordName' is not marked queryable`. Filtering on any already-`QUERYABLE` `CD_` field routes through that field's own index and needs no Console change.
- **Filter grammar** is `FIELD OP VALUE` with `==`, `!=`, `<`, `<=`, `>`, `>=` (plus `NEAR`, `CONTAINS_ALL_TOKENS`, `CONTAINS_ANY_TOKENS`, `LIST_CONTAINS_ANY`, `LIST_NOT_CONTAINS_ANY`). Values are typed by shape (`123` → Int64, `6.12` → Double, `2021-01-01` → Timestamp) or explicitly as `stringType:…`, `referenceType:…`. **Swift `Bool` mirrors as `INT64`**, so it is `CD_isActive == 1`, never `== true` — a type-mismatched filter matches nothing instead of erroring. For an always-true predicate use something like `CD_intervalDays >= 0`.
- **Environment follows the build, not the query.** Debug builds and simulator runs write to **Development**; only TestFlight and App Store builds write to **Production**. A plan created from Xcode lives in the Development database, so a Production query legitimately returns nothing. **Run both environments** before concluding anything, and remember that export is asynchronous and opportunistic — a record written moments ago or while offline may not have shipped yet.

An empty `records` array is trustworthy evidence of absence only once zone, token identity, environment, filter typing and sync timing are all excluded. Sources: forums threads [692797](https://developer.apple.com/forums/thread/692797) (user vs. management token), [655392](https://developer.apple.com/forums/thread/655392) (private DB needs no queryable index), [795826](https://developer.apple.com/forums/thread/795826) (debug build writes to Development), Apple ["Testing Your CloudKit App"](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitQuickStart/TestingYourApp/TestingYourApp.html), and `Filters.md` in [apple/sample-cloudkit-tooling](https://github.com/apple/sample-cloudkit-tooling/blob/main/cktool-cli/Commands/query-records.md).

## Which changes produce a Console diff (2026-08-17)

"Deploy Schema Changes" compares Development against Production and shows **nothing** when the Development schema has not changed. An empty diff is therefore the *correct* result for a release that did not touch the persisted model — it is not evidence that the tool failed.

**Schema-affecting:**

- A new `@Model` type → a new `CD_<TypeName>` record type. It must also be registered in `GymStreakSchema.modelTypes`, or neither the app's `ModelContainer` nor this initializer will ever see it.
- A new persisted property → a new `CD_<propertyName>` field.
- A new relationship → a new reference field. CloudKit requires every synced relationship to be **optional** and cannot honour `.deny` delete rules.

**Not schema-affecting — no diff, nothing to deploy:**

- `@Transient` properties (never persisted) and `#Index` declarations (local-only; CloudKit's queryable/sortable indexes are configured separately in the Console).
- Anything persisted outside SwiftData. The Pro/monetization layer shipped in 1.1.9 is the worked example: its "models" (`ProGating`, `PaywallPlacement`, `LifetimeTrainingTotals`, …) are plain value types, and its state lives in `UserDefaults` — `MonthlyAllowanceStore` in the App Group suite (mirrored to `NSUbiquitousKeyValueStore`), `FounderCelebrationStore` and `ProactivePaywallTriggerStore` in `UserDefaults.standard`. Note that iCloud key-value mirroring syncs across devices **without** any CloudKit record type, so it never produces a schema diff either. `GymStreakSchema.modelTypes` was untouched, so the Console correctly reported no diff. Before assuming a release needs a deploy, check it: `git diff <range> -- GymStreak | grep '^[+-]@Model'` and whether `GymStreakSchema.swift` itself changed.
- A rename is not a rename — CloudKit schemas are additive, so it surfaces as a new type/field beside the orphaned old one.
- `@Attribute(.unique)` cannot be enforced by CloudKit at all (concurrent sync has no atomic-delivery guarantee); avoid it on synced models.

### "No diff" checklist

1. **Confirm container and team.** Viewing a similarly-named container is the single most common cause (Apple DTS, forums thread 819507). It must be `iCloud.com.jmanke.gymstreak`, environment **Development**.
2. **Confirm the change is schema-affecting** (above).
3. **Confirm Development was actually populated.** Development creates record types just-in-time, only when a record of that type is saved *and* mirrored — a `@Model` type with zero saved records never appears at all. Bypassing exactly that is why `-INITIALIZE_CLOUDKIT_SCHEMA` exists.
4. **Confirm the upload succeeded.** A retry-exhausted failure (error 134060, above) prints `❌` and is otherwise indistinguishable from "nothing changed" — read the console, don't infer from the Console UI.
5. **Verify by content, not by the deploy dialog.** Export both environments with `cktool` and diff them (see the section above); this beats reading the Console UI. There must be one `CD_`-prefixed record type per entry in `GymStreakSchema.modelTypes` (10 as of 2026-08-17: `CD_Routine`, `CD_Exercise`, `CD_RoutineExercise`, `CD_ExerciseSet`, `CD_RoutineExerciseAlternative`, `CD_AlternativeExerciseSet`, `CD_RoutineSchedule`, `CD_WorkoutSession`, `CD_WorkoutExercise`, `CD_WorkoutSet`).
6. **"Already deployed" is the benign case.** If a previous run pushed this exact shape, no diff is correct. Reload the page if the Console hangs on "Loading Changes".

### Verified Production state (observed 2026-08-17)

Previously this section carried an open question: `RoutineSchedule` was added 2026-07-07, *after* a 2026-07-03 Production deploy recorded as holding only 9 record types, so `CD_RoutineSchedule` was suspected of never having reached Production — the leading explanation for the "routine plan is not persisted in iCloud" report. **That suspicion is wrong.** Measured directly with `cktool export-schema` against container `iCloud.com.jmanke.gymstreak`:

- **Production holds all 10 `CD_` record types** (plus CloudKit's own `Users`), `CD_RoutineSchedule` among them, with every one of its fields: `CD_id`, `CD_routine`, `CD_typeRaw` (+ `_ckAsset`), `CD_intervalDays`, `CD_weekdaysMask`, `CD_startDate`, `CD_isActive`, `CD_createdAt`.
- **`CD_Routine` carries the `CD_schedule` field**, so the `Routine.schedule` ↔ `RoutineSchedule.routine` edge is fully represented in Production.
- **Development and Production exports are byte-identical** (261 lines each, zero diff) — the Development schema is fully deployed, and no re-run of `-INITIALIZE_CLOUDKIT_SCHEMA` was needed to establish this. A regeneration would have been a no-op.
- **No field-level drift anywhere:** every persisted property of all ten `@Model` types has a matching `CD_` field, and no orphaned `CD_` field survives from a rename or removal. Absences are limited to to-many array relationships, which correctly carry no parent-side field.
- Production is in fact **newer than the 2026-07-03 deploy record** in this document: it also contains every persisted property added after the 2026-07-11 full-schema upload — `CD_bodyWeightKg`, `CD_watchTemplateOutcomeRaw`, `CD_watchTemplateTransactionID` (`WorkoutSession`), `CD_seedKey` and `CD_loadBehaviorRaw` (`Exercise`), `CD_routineExerciseId` (`WorkoutExercise`). So at least one Production deploy happened after 2026-07-03 without being recorded here. Treat the deploy history below as incomplete, and prefer an export over it.

**Consequence:** a missing Production record type was *ruled out* as the cause of the routine-plan sync report. **The real cause was found the next day and it was not a schema problem at all:** `Routine.schedule` was a to-one ↔ to-one relationship, and CloudKit did not mirror it — the plan records arrived complete but with `CD_routine` absent, so other devices imported them as orphans. Querying records, not inspecting the schema, is what settled it. Full root cause, the disproved hypotheses, and the to-many remodelling that fixed it are in `docs/workout-planning.md` → "iCloud sync: why the plan is a to-many". The lesson worth keeping: a deployed record type proves the *type* exists, never that a *reference field* is being populated — check records for that.

## Why this design (dead ends considered)

- **Separate Xcode target** (Apple's "best practice" isolation): rejected as over-build for a single-developer app — the launch-argument + `#if DEBUG` gate achieves the same safety without a second target to maintain.
- **Running on every Debug launch:** rejected — it's a network-heavy operation against real CloudKit; Apple and fatbobman both advise running it deliberately, not per-launch.
- **SwiftData-native API:** none exists as of iOS 26 — dropping down to Core Data via `makeManagedObjectModel(for:)` is Apple's documented interop path.
