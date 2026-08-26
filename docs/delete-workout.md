# Delete a Recorded Workout

## What it is
A visible way to delete a recorded workout, and — when the workout also exists in Apple Health — a per-deletion choice of whether Health should be cleaned up too.

There are two entry points, both of which raise the **same** confirmation:

1. The workout detail screen's ellipsis **Menu** (also holds Edit Workout).
2. The **long-press context menu** on a history card.

The workout detail screen's trailing toolbar item is an ellipsis **Menu** holding **Edit Workout** and a destructive **Delete**; the previously standalone pencil button is folded into that menu. Delete raises a destructive confirmation alert:

- **Workout with an Apple Health counterpart** → two destructive choices, *Delete in GymStreak Only* and *Delete in GymStreak and Apple Health*, plus Cancel.
- **Workout without one** (`healthKitWorkoutId == nil`) → a single *Delete* plus Cancel. The Apple Health option is not offered, because there would be nothing for it to remove.

Confirming pops the detail screen and removes the session from history.

Target: **iOS app only** (`GymStreak`). No changes to the watch target.

Related: [History (Verlauf) Redesign](./history-redesign.md), [Edit a Past Workout](./edit-past-workout.md), [Watch Workout Recovery](./watch-workout-recovery.md), [Saving an iPhone Workout to Apple Health](./healthkit-ios-workout-save.md).

> **The Apple Health choice is only as good as `healthKitWorkoutId`.** Until 2026-08-24,
> iPhone-recorded workouts were written to Health *without* the app's metadata, so they carried no
> external UUID and this confirmation correctly — but confusingly — showed a single *Delete*, while
> watch-recorded workouts offered both options. That was a defect in the **save** path, not here;
> root cause and fix in [healthkit-ios-workout-save.md](./healthkit-ios-workout-save.md). Workouts
> the phone recorded before that fix stay un-correlatable and are still single-*Delete*.

## Why it exists
Before this feature, the only way to delete a recorded workout was a hidden long-press `.contextMenu` on a history card in `TrainingsTabView`'s list mode. Calendar mode had **no** delete path at all, and neither did the detail screen. Because both list mode and the calendar's selected-day card push the same `WorkoutDetailView`, adding the affordance there closes both gaps with one control.

The Apple Health half exists because a delete that leaves the workout visible in the Health app is only half a delete — but a delete that *silently* removes Health data would be worse. Hence an explicit per-deletion choice rather than a global setting.

## How it works

### The confirmation
1. `WorkoutDetailView`'s trailing `ToolbarItem` is a `Menu` (`ellipsis` glyph, accessibility label `history.detail.more`) with:
   - **Edit** → sets `showingEdit`, which presents the existing `EditWorkoutSessionView` sheet (unchanged behavior).
   - **Delete** (`role: .destructive`) → sets `showingDeleteConfirmation`.
2. Both delete entry points (the detail-screen menu and the history card's long-press context menu) attach the **same** shared modifier, `.deleteWorkoutConfirmation(isPresented:hasHealthKitWorkout:onDelete:onCancel:)`, so the copy and the choice are identical wherever the user starts. `onDelete` receives a single `alsoFromHealthKit: Bool`.
3. Confirming from the detail screen **dismisses first, then deletes**:
   ```swift
   dismiss()
   viewModel.deleteWorkout(workout, alsoFromHealthKit: alsoFromHealthKit)
   HapticManager.shared.success()
   ```

**Why an `.alert` and not a `.confirmationDialog`.** An action sheet is the more conventional iOS container for a multi-option destructive choice, but on iOS 26 a `confirmationDialog` anchors to the view its modifier is attached to — attaching one to a large ancestor makes it mis-anchor as a floating popover. Both call sites here *are* large ancestors (the detail screen's root `ZStack`, the history screen's `NavigationStack` content), and neither has a natural small anchor for the context-menu path. `PendingSyncBannerView` documents the same trap and works around it by hosting its dialog on a button. An alert has no anchor, so it is used instead.

### History-card deletion and navigation
Trainings list cards are native `NavigationLink(value: card.id)` rows. Long-pressing a card opens a destructive context-menu shortcut; activating it raises the shared confirmation. The row also exposes the same named delete action to accessibility. Calendar mode uses the visible delete route in `WorkoutDetailView`.

The native link is a deliberate performance and accessibility boundary. It provides navigation, focus, keyboard and VoiceOver semantics without rebuilding those behaviors on every row. The `UUID` navigation value stays lightweight; `HistoryView` resolves the corresponding `WorkoutSession` only at the navigation or deletion boundary.

#### Removed custom swipe interaction (2026-07-26)
Release 1.1.5 used native links and scrolled smoothly. Commit `0ffd13c` added a hand-rolled `SwipeToDeleteContainer` to every card with a simultaneous horizontal `DragGesture`, focus handlers, manual accessibility actions, offsets, clipping and background layers. Users then reported intermittent 0.3–1 second periods where the list ignored input.

An identical 60-session main-run-loop probe against isolated commits measured:

| Build | Open History | Fortschritt → Trainings | Fast scroll |
| --- | ---: | ---: | ---: |
| Released 1.1.5 (`bfb8441`) | 342 ms | 179 ms | 41 ms |
| Post-release (`0ffd13c`) with custom wrapper | 388 ms | 205 ms | 298 ms |
| Same post-release commit, only wrapper reverted | 335 ms | 184 ms | 45 ms |

Removing only the wrapper restored fast scrolling from 298 ms to 45 ms, essentially the 1.1.5 result. `SwipeToDeleteContainer`, `HistorySwipeState`, the scroll-geometry observer and programmatic list-row taps were therefore removed rather than tuned.

On the shipping iOS 18.5–26 range, SwiftUI's native `.swipeActions` contract still requires a `List`. Converting the complete History screen—header, banners, coach cards, calendar, month dividers and cards—to one `List` is a separate screen-level redesign and was rejected for this release-critical fix. Arbitrary scroll-container swipe actions arrive with [`swipeActionsContainer()`](https://developer.apple.com/documentation/swiftui/view/swipeactionscontainer/) in iOS 27/Xcode 27; adopting that beta API now would still require the current fallback. Until the deployment target permits that API, deletion remains discoverable through the visible detail-screen menu, with the card context menu as a shortcut.

### Ordering: local delete first, HealthKit best-effort
`WorkoutViewModel.deleteWorkout(_:alsoFromHealthKit:)` captures `session.healthKitWorkoutId` *before* deleting (the `@Model` instance is invalid afterwards), performs the local delete synchronously, and only then fires a detached `Task` for HealthKit:

```
deleteWorkout(session)                       // SwiftData is the source of truth
  ↓ workoutSessionRepository.delete → save → fetchWorkoutHistory
guard alsoFromHealthKit, let healthKitWorkoutId
  ↓
Task { try await healthKitManager.deleteWorkout(externalUUID:) }
```

The local delete is never gated on, blocked by, or rolled back for HealthKit. A HealthKit failure only sets `@Published var healthKitDeleteFailure: HealthKitDeleteFailure?`, which `HistoryView` renders as `HealthDeleteFailureBanner` — a non-blocking inline notice with a dismiss button, not a modal. The enum has two cases and they exist purely because the user's remedy differs: `.accessDenied` (Apple Health will not let the app write workouts — grant it in Health, or delete there) and `.failed` (anything else — the workout is still in Health, remove it manually). Apple's HIG has no explicit rule for this case; treating it as information rather than an error the user must acknowledge is a deliberate product call, justified by the fact that nothing is left for the user to decide (the local delete already succeeded; the only consequence is a leftover entry they can remove in the Health app).

### Authorization, then deleting the HealthKit workout
`HealthKitWorkoutManager.deleteWorkout(externalUUID:)` (behind `HealthKitWorkoutServicing`) does three things in order:

```swift
let workoutType = HKObjectType.workoutType()

// 1. Re-ask when this install has never been asked. Requesting types the user
//    already decided does not re-prompt; a cancelled sheet throws, and the
//    guard below turns that into the actionable error.
if healthStore.authorizationStatus(for: workoutType) == .notDetermined {
    try? await healthStore.requestAuthorization(toShare: [workoutType], read: [workoutType])
    checkAuthorizationStatus()
}

// 2. Deletion is governed by *current* share authorization.
guard healthStore.authorizationStatus(for: workoutType) == .sharingAuthorized else {
    throw HealthKitError.healthAccessDenied
}

// 3. Match on our own metadata and delete in one call — no read query involved.
let deletedCount = try await healthStore.deleteObjects(
    of: workoutType,
    predicate: HKQuery.predicateForObjects(
        withMetadataKey: HKMetadataKeyExternalUUID,
        allowedValues: [externalUUID.uuidString]
    )
)
return deletedCount > 0
```

`HKError`s are then classified rather than flattened: `errorAuthorizationNotDetermined` and
`errorAuthorizationDenied` become `HealthKitError.healthAccessDenied` (a permission with a user
remedy), everything else stays `deleteFailed`.

The `Bool` return distinguishes "deleted" from "nothing matched". **Nothing matched is a success,
not an error** — the user already removed it in the Health app, or it was never there.

#### Why authorization is re-requested here (the reinstall bug, fixed 2026-08-26)
**Deletability is a function of *current* share authorization, not of a stored ownership token.**
Apple: *"Your app can delete only those objects that it has previously saved to the HealthKit store.
If the user revokes sharing permission, you can no longer delete the object."* Ownership itself is
keyed on the **bundle identifier** and survives a reinstall — there is no install identifier
anywhere in the HealthKit model, and `HKSourceRevision` is descriptive provenance, not an
access-control key.

The authorization, however, does **not** survive a reinstall, while
`WorkoutSession.healthKitWorkoutId` does — it comes straight back over CloudKit. So a freshly
reinstalled app holds a perfectly valid external UUID for a workout it is momentarily not allowed
to touch.

That produced the reported bug: delete the app → reinstall → let iCloud re-sync → the workout is
back in history and, because its `healthKitWorkoutId` is non-nil, the confirmation correctly offers
*Delete in GymStreak and Apple Health* → choosing it always failed. The app requests HealthKit
authorization in exactly one place, `WorkoutViewModel.prepareHealthKitAuthorization()` at **workout
start**, so a user who reinstalled and went straight to History had never been asked in that
install. The old delete path checked nothing, ran its lookup query with authorization
`.notDetermined`, and flattened the resulting throw into the generic `deleteFailed` banner.

Two changes fix it, and the second one matters independently:

- **Ask in place.** Scoped to the workout type, so the sheet raised while the user is deleting
  something asks for the one thing the deletion needs rather than dragging active energy and heart
  rate into it. The remaining types are still asked for at workout start.
- **`deleteObjects(of:predicate:)` instead of lookup-then-`delete(_:)`.** It removes the *read*
  authorization dependency from the path entirely and returns a deleted count, so zero is an
  unambiguous "already gone" rather than the "gone, or the read was blocked" ambiguity a lookup
  query leaves behind.

A corroborating symptom of the same root cause, deliberately left alone: after a reinstall
`WorkoutDetailView.loadHealthKitKcal()` runs the same metadata lookup and swallows its error, so
those synced workouts show no Apple Health calories until authorization is granted. It repairs
itself once the user grants access anywhere.

### Cascade deletion of children (local)
No child objects are hand-deleted. `WorkoutSession.workoutExercises` and `WorkoutExercise.sets` both declare `.cascade` delete rules, so exercises and sets are removed with the session. Deleting them manually would be redundant and risks double-delete.

### List and calendar refresh
`deleteWorkout(_:)` deletes through `WorkoutSessionRepository`, saves, then increments
`WorkoutViewModel.historyVersion`. `HistoryView` includes that version in its `.task(id:)`
token, so the actor-owned `HistorySnapshotProviding` pipeline reloads list and calendar values
once without a manual pull-to-refresh. Navigation and deletion carry only the workout `UUID`;
the concrete `WorkoutSession` is resolved through the repository at the boundary, so a stale
row value cannot resurrect a deleted session.

### Watch-originated workouts do not reappear as recovery offers
Neither the local delete nor the HealthKit delete leaves a stale recovery-ledger entry, and this required **no code change**. `WorkoutRecoveryCoordinator` protects against a re-offer three times over:

- **Ledger state is terminal.** Once the session was committed, `applyStateTransition` moved the ledger entry from `.provisional` to `.resolvedByHistory` (or `.placeholderSaved` for a recovered placeholder). `WorkoutRecoveryReconciler.decide` returns `.resolve` for those states before it looks at anything else.
- **Ingest receipts outlive history.** `reconcileLedger` treats `receipts.receipt(forHealthKitWorkoutId:) != nil` as proof of prior ingestion — the comment in that file states the intent explicitly: *"A receipt proves prior ingestion even if the user deleted history."*
- **The HealthKit deletion is itself absorbed by the ledger.** The next anchored-query drain reports the removed object in `deletedObjectUUIDs`; `WorkoutRecoveryLedgerStore.applyDeleted(objectUUID:now:)` maps it back to its candidate and tombstones the entry once it loses its last HealthKit object. A tombstoned candidate is never offered for recovery.

## Architecture

### Files modified
- `GymStreak/Domain/Interfaces/HealthKitWorkoutServicing.swift` — added `deleteWorkout(externalUUID:) async throws -> Bool` to the existing gateway protocol. **2026-08-26:** now also declares the `HealthKitError` enum (moved here from `HealthKitWorkoutManager.swift`, with the new `healthAccessDenied` case) so `Presentation/` can classify a failure without reaching into `Data/`.
- `GymStreak/Data/HealthKit/HealthKitWorkoutManager.swift` — implemented that method against the real `HKHealthStore`. **2026-08-26:** re-requests share authorization when `.notDetermined`, guards on `.sharingAuthorized`, deletes via `deleteObjects(of:predicate:)` instead of lookup-then-`delete(_:)`, and classifies `HKError` codes instead of flattening every throw into `deleteFailed`.
- `GymStreak/Presentation/ViewModels/WorkoutViewModel.swift` — added `deleteWorkout(_:alsoFromHealthKit:)`, the failure flag, and `dismissHealthKitDeleteNotice()`. **2026-08-26:** the flag became `@Published var healthKitDeleteFailure: HealthKitDeleteFailure?` and the catch tells an access denial apart from a genuine failure.
- `GymStreak/Presentation/Views/History/WorkoutDetailView.swift` — `@Environment(\.dismiss)`, `showingDeleteConfirmation` state, the toolbar `Menu`, the shared confirmation, and the private `deleteWorkout(alsoFromHealthKit:)` helper.
- `GymStreak/Presentation/Views/History/HistoryView.swift` — its long-press delete alert was replaced by the shared confirmation; it renders the failure banner and resolves lightweight row ids at the deletion boundary.
- `GymStreak/Presentation/Views/History/TrainingsTabView.swift` — native `NavigationLink` rows with context-menu and accessibility delete actions.
- `GymStreak/Resources/{en,de}.lproj/Localizable.strings` — new keys (table below).
- `GymStreakTests/Support/MockHealthKitWorkoutServicing.swift` — the hand-written double gained the new method with a recording array, an injectable error, and an injectable "already gone" result.

### Files added
- `GymStreak/Presentation/Views/History/Components/DeleteWorkoutConfirmation.swift` — the shared `ViewModifier` + `View` extension hosting the confirmation.
- `GymStreak/Presentation/Views/History/Components/HealthDeleteFailureBanner.swift` — the non-blocking failure notice, plus the `HealthKitDeleteFailure` enum that selects its copy.
- `GymStreakUITests/WorkoutDeletionUITests.swift` — context-menu deletion and navigation regression coverage.

### Files unchanged on purpose
- `WorkoutSessionRepository` and its protocol — the local delete path already existed end to end.
- `App/AppDependencies.swift` — **no new dependency wiring.** The delete capability was added to a protocol the ViewModel is already injected with.
- No SwiftData field and no migration were introduced. The workout is located by the `healthKitWorkoutId` we already store; persisting `HKWorkout.uuid` instead would have needed an additive `@Model` field (and therefore a CloudKit schema deploy) for no benefit.
- `TrainingsTabView`'s long-press `.contextMenu` delete — kept as a shortcut; the visible detail-screen menu is the discoverable route.
- `WorkoutDetailView.loadHealthKitKcal()` still constructs its own `HKHealthStore()` inline to read calories — a pre-existing layer violation, deliberately worked *around* rather than expanded. The new delete goes through the gateway protocol. Fixing the older read is a separate cleanup.

### Layer compliance
Dependency direction holds: the new capability is declared in `Domain/Interfaces/`, implemented in `Data/HealthKit/`, and consumed by `Presentation/` through the injected protocol. No `ModelContext`/`FetchDescriptor` in views, no `.shared` access in the ViewModel, no ad-hoc service construction, no `@Model`/schema change.

## HealthKit research findings
Confirmed against Apple documentation and Apple engineer forum replies before implementation. **Do not re-research these.**

- **Delete API:** `deleteObjects(of:predicate:)` — `func deleteObjects(of objectType: HKObjectType, predicate: NSPredicate) async throws -> Int`, iOS 9+, "Deletes objects saved by this application that match the provided type and predicate." One call, no read query, and the returned count makes "already gone" unambiguous. The single-object `delete(_ object: HKObject) async throws` was used until 2026-08-26; it required resolving the workout with a read query first, which is what made the path depend on read authorization. Note for any future batch work: the array/predicate variants are **all-or-nothing** — if one object can't be deleted, none are.
- **Lookup strategy:** match on our own metadata (`HKMetadataKeyExternalUUID`, stamped at save time and mirrored in `WorkoutSession.healthKitWorkoutId`) using `HKQuery.predicateForObjects(withMetadataKey:allowedValues:)`. Metadata predicates work with custom keys. There is already a working metadata precedent in the watch manager and in this detail view's calorie read.
- **Deletability is current authorization, not stored ownership.** *"Your app can delete only those objects that it has previously saved to the HealthKit store. If the user revokes sharing permission, you can no longer delete the object."* Ownership is keyed on the **bundle identifier**, which survives a delete-and-reinstall; there is no install identifier in the HealthKit model, and `HKSourceRevision` is descriptive provenance, not an access-control key. The *authorization* is what resets on reinstall — see the reinstall section above. Re-granting fully restores deletion of samples any earlier install wrote; Apple documents no prior-install caveat.
- **The documented failure codes for delete are exactly two:** `errorAuthorizationNotDetermined` when share permission was never requested, `errorAuthorizationDenied` when it was refused. `errorInvalidArgument` means a bad argument, **not** a source mismatch — there is no "not your data" case to switch on. `HKError` conforms to `_BridgedStoredNSError`, so `catch let error as HKError` and `error.code` work directly, with no `NSError` domain-string comparison.
- **Requesting authorization again is cheap and non-intrusive.** "If the user has already chosen whether to grant the application access to all of the types provided, then the completion will be called **without prompting the user**." Its success flag does **not** report whether authorization was granted, so `authorizationStatus(for:)` must be re-read afterwards.
- **`getRequestStatusForAuthorization(toShare:read:)` answers exactly one question:** would a sheet appear? It is set-wide, not per-type — `.shouldRequest` means at least one type in the combined set is still undecided. It cannot report read grant vs. deny (by design), so it is *not* used here: sharing authorization is what governs deletion, and `authorizationStatus(for:)` reports that synchronously.
- **Scoping to our own source is unnecessary.** `HKQuery.predicateForObjects(from:)` could be ANDed in, but HealthKit only ever deletes objects this app saved, whatever the predicate matched — enforced against *current* sharing authorization, which is precisely what a reinstall clears.
- **Deleting needs *share* authorization for `HKObjectType.workoutType()`, and nothing else.** Since the switch to `deleteObjects(of:predicate:)` no read is involved in this path at all, so read authorization — undetectable by design, since `authorizationStatus(for:)` reports only sharing status — cannot affect it. The app requests both types at workout start; the delete path re-requests share in place when this install has never been asked.
- **"Already gone" is not an error.** A zero deleted-count means the user already removed the workout in the Health app, or it was never there. The desired end state holds, so `deleteWorkout(externalUUID:)` returns `false` and the ViewModel treats it as success.
- **A *denied* read is not the dangerous case — an *unrequested* one is.** Apple: "If they denied permission, attempts to read data from HealthKit return only samples that your app successfully saved to the HealthKit store." So a denied read still returns *our own* workout, and a zero-result lookup really did mean "gone". What throws is authorization that was never **requested** in this install (`errorAuthorizationNotDetermined`) — documented explicitly for writes, and reported consistently on the forums for reads. This document previously claimed a zero-result query was indistinguishable from a denied read; that was more pessimistic than reality, and it obscured the undetermined case that actually caused the reinstall bug.
- **Reinstalling resets HealthKit authorization** for the same bundle ID on the same device: `authorizationStatus(for:)` returns `.notDetermined` again. Apple DTS gives delete-and-reinstall as the way to reset a stuck authorization state. One unresolved DTS thread reports iOS 18.5 landing in `.sharingDenied` instead, with no sheet shown — which is why the code guards on `== .sharingAuthorized` rather than on `!= .notDetermined`, and why the denied notice names the remedy instead of silently retrying.
- **No iOS 18/26 behavior change here.** iOS 26's HealthKit work is the Medications API and per-object read authorization; nothing touches sample ownership or reinstall semantics.
- **Cascade behaviour.** Deleting the `HKWorkout` also removes the quantity samples its builder associated with it (active energy, distance, heart rate). Reported by an Apple engineer; *not* stated as a contract in the reference docs.
- **Activity Ring exercise minutes cannot be deleted by any app.** They are system-awarded and only the user can remove them in the Health app. This is a hard Apple limitation, which is why the confirmation copy promises removal of the *workout* and explicitly says the credited exercise minutes stay in Health.
- **GymStreak saves no `HKWorkoutRoute`,** so route cascade is moot. If routes are ever added, delete them explicitly rather than assuming cascade — undocumented either way.
- **Watch-recorded workouts.** A workout recorded by the watch app via `HKWorkoutSession`/`HKLiveWorkoutBuilder` is saved with `sourceRevision.source` carrying the **iPhone app's** bundle identifier, and the watch's store is a rolling ~7-day synced subset of the phone's — so the phone is expected to be allowed to delete it, and this is not a cross-app ownership violation. Confidence was **medium-high from an Apple engineer forum reply, not a documented contract** — **confirmed empirically on a physical iPhone + Apple Watch on 2026-07-26** (see Verification below): the phone deleted a watch-recorded workout and it vanished from the Health app.

Sources: [`deleteObjects(of:predicate:withCompletion:)`](https://developer.apple.com/documentation/healthkit/hkhealthstore/deleteobjects(of:predicate:withcompletion:)) · [`delete(_:withCompletion:)`](https://developer.apple.com/documentation/healthkit/hkhealthstore/delete(_:withcompletion:)-78l1m) · [Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data) · [Protecting user privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy) · [`HKError.Code`](https://developer.apple.com/documentation/healthkit/hkerror/code) · [`HKSource`](https://developer.apple.com/documentation/healthkit/hksource) · [`getRequestStatusForAuthorization(toShare:read:completion:)`](https://developer.apple.com/documentation/healthkit/hkhealthstore/getrequeststatusforauthorization(toshare:read:completion:)) · [DTS: reinstall resets authorization / iOS 18.5 immediate denial](https://developer.apple.com/forums/thread/787407) · [`predicateForObjects(withMetadataKey:allowedValues:)`](https://developer.apple.com/documentation/healthkit/hkquery/1614780-predicateforobjects) · [`HKSampleQueryDescriptor`](https://developer.apple.com/documentation/healthkit/hksamplequerydescriptor) · [`authorizationStatus(for:)`](https://developer.apple.com/documentation/healthkit/hkhealthstore/authorizationstatus(for:)) · [watch-vs-phone source, Apple engineer reply](https://developer.apple.com/forums/thread/683224) · [exercise minutes survive deletion, Apple engineer reply](https://developer.apple.com/forums/thread/681755)

## Localization

| Key | en | de |
| --- | --- | --- |
| `workout.history.delete.title` (reused) | Delete Workout? | Workout löschen? |
| `workout.history.delete.message` (reused) | Are you sure…? | Möchtest du…? |
| `workout.history.delete.message_health` | …choose whether to remove it from Apple Health too; credited exercise minutes stay in Health | …ob es auch aus Apple Health entfernt wird; gutgeschriebene Trainingsminuten bleiben in Health |
| `workout.history.delete.gymstreak_only` | Delete in GymStreak Only | Nur in GymStreak löschen |
| `workout.history.delete.with_health` | Delete in GymStreak and Apple Health | In GymStreak und Apple Health löschen |
| `history.delete.health_failed` | Deleted in GymStreak, but couldn't be removed from Apple Health… | In GymStreak gelöscht, konnte aber nicht aus Apple Health entfernt werden… |
| `history.delete.health_access_denied` | Deleted in GymStreak. Apple Health didn't allow it to be removed there — turn on Workouts for GymStreak under Health › Profile › Apps… | In GymStreak gelöscht. Apple Health hat das Entfernen dort nicht erlaubt — aktiviere „Workouts" für GymStreak unter Health › Profil › Apps… |
| `history.detail.more` | More | Mehr |
| `action.dismiss` | Dismiss | Schließen |
| `action.delete` / `action.cancel` (reused) | Delete / Cancel | Löschen / Abbrechen |
| `edit_workout.title` (reused) | Edit Workout | Workout bearbeiten |

## Watch target
**Unchanged.** The watch has no workout-history browsing UI; deletion is an iOS-only concern. Note that a HealthKit workout deleted on the phone also disappears from the watch's HealthKit store, since the watch holds a synced subset of the phone's.

## Tests
`GymStreakTests/WorkoutViewModelTests.swift` covers the ViewModel delete path against `MockHealthKitWorkoutServicing`:

- `deletingWorkoutWithAppleHealthChoiceRemovesBothCopies` — local session gone, the external UUID forwarded to HealthKit, no failure flag.
- `deletingWorkoutGymStreakOnlyLeavesAppleHealthUntouched` — HealthKit is never called.
- `deletingWorkoutWithoutHealthKitCounterpartSkipsHealthKit` — `healthKitWorkoutId == nil` short-circuits even when Apple Health was requested.
- `healthKitDeleteFailureLeavesLocalDeleteCommitted` — a throwing HealthKit delete leaves the local deletion and the republished history intact and raises only the non-blocking flag (`.failed`).
- `alreadyAbsentHealthKitWorkoutIsNotTreatedAsFailure` — a `false` result (nothing matched) does not raise the flag.
- `healthAccessDenialIsReportedSeparatelyFromAFailedDelete` — `HealthKitError.healthAccessDenied` surfaces as `.accessDenied`, not `.failed`, so the notice can name the remedy. This is the state a reinstalled app lands in.

`GymStreakUITests/WorkoutDeletionUITests.swift` covers the supported UI routes:

- `testLongPressCardOffersDeleteWithoutNavigating` — the context-menu shortcut appears without pushing detail.
- `testContextMenuDeleteOpensConfirmation` — the shortcut raises the shared confirmation alert.
- `testTappingCardStillNavigatesToDetail` — native row navigation remains intact.
- `testCoachSettingsStillPushesOnThePathBoundStack` — the heterogeneous path's settings destination still works.

`GymStreakUITests/HistoryResponsivenessUITests.swift` seeds 60 sessions and measures delayed common-mode main-run-loop service while opening History, switching Fortschritt back to Trainings, and fast-scrolling. Its scroll threshold is 150 ms; the removed wrapper measured 298 ms and the native-link row measured 41–45 ms in the causal A/B.

Two setup details these tests depend on: the app must be launched with `-UI_TESTING` so `TestDataSeeder` seeds workout history, and the **AI Coach opt-in prompt covers the UI on a fresh launch and swallows taps** — it must be dismissed via its "Maybe later" / "Vielleicht später" button before the tab bar is usable. `UITestHelpers.navigateToTab` silently does nothing when that prompt is up, which is worth knowing for any future UI test in this app.

## Verification

**Automated / static**

- **Responsiveness regression:** five repeated 60-session runs passed after the native-link replacement.
- **Deletion/navigation UI:** all four `WorkoutDeletionUITests` passed.
- **Build, full unit suite and final architecture review:** see the latest verification record in [History performance](./history-performance.md).

**Manual testing of the local-delete slice — passed** (confirmed 2026-07-26): dismiss-then-delete ordering with a rich workout (no crash, no blank flash), calendar mode, list mode, cancel path, the pre-existing long-press context menu, Edit still reachable inside the ellipsis menu, and a watch-originated workout that did not resurface as a pending-sync offer after backgrounding and reopening the app.

**Device validation of the Apple Health delete — PASSED** (physical iPhone + Apple Watch, 2026-07-26). The one assumption that could not be settled in the simulator was whether the phone may delete a **watch-recorded** HealthKit workout (see the research note above). Observed on device:

1. A workout recorded on the watch and synced to the phone was deleted from the phone with *Delete in GymStreak and Apple Health*.
2. **It disappeared from the Health app.** The phone *is* allowed to delete a watch-recorded workout — the forum-sourced expectation holds in practice, no failure banner appeared. This settles the open research question: watch-recorded workouts carry the iPhone app's bundle identifier as their source, so deleting them from the phone is not a cross-app ownership violation.
3. **Credited exercise minutes remained** on the Activity rings, exactly as predicted — the app cannot remove them and the confirmation copy is correct to say so.
4. Backgrounding and reopening GymStreak left the **pending-sync banner quiet** — no stale recovery-ledger entry, the deleted workout was not re-offered.
5. The two-option alert plus cancel rendered correctly in **both English and German**.

No product fallback is needed: the Apple Health option stays available for watch-recorded workouts.

**Reinstall fix (2026-08-26) — automated only; device validation still open.** `xcodebuild` build succeeded with zero first-party warnings, and the full `GymStreakTests` suite passed including the new `healthAccessDenialIsReportedSeparatelyFromAFailedDelete`. The unit tests exercise the ViewModel's classification against `MockHealthKitWorkoutServicing`; they **cannot** cover the part that actually broke, because the authorization re-request and `deleteObjects(of:predicate:)` live behind the real `HKHealthStore`. The reproduction to run on a physical device is: record and finish a workout on the phone → confirm it in the Health app → delete the app → reinstall → let iCloud re-sync → open History **without starting a workout** → delete with *Delete in GymStreak and Apple Health*. Expected: the Apple Health permission sheet appears, and after granting it the workout disappears from Health with no banner. Declining should show the new access-denied notice, not the generic one.

The removed swipe gesture had previously passed functional device testing, but functional correctness did not catch its scaling cost. The lesson is stricter: a hand-rolled gesture graph attached to every lazy scroll row requires a main-run-loop performance gate, not only gesture tests and a successful build.

## Edge cases and decisions
- **Undo:** none. The confirmation copy states the action cannot be undone, matching the pre-existing context-menu delete.
- **A workout whose HealthKit save failed or was denied** has `healthKitWorkoutId == nil`. That is normal, never blocks deletion, and suppresses the Apple Health option rather than offering a no-op. Note the failure mode this hides: a workout can be *present* in Health and still have `healthKitWorkoutId == nil` if the write did not stamp `HKMetadataKeyExternalUUID` — which is exactly what happened to iPhone-recorded workouts until 2026-08-24 ([healthkit-ios-workout-save.md](./healthkit-ios-workout-save.md)). The suppressed option is then correct given what the app knows, but wrong from the user's point of view.
- **The permission sheet appears *after* the local delete.** The ordering is deliberate and unchanged: SwiftData is the source of truth, so the session is gone from history before the HealthKit `Task` runs. On a reinstalled app that means the workout vanishes and *then* Apple Health asks for permission. Gating the local delete on an authorization round-trip to make the sheet come first was rejected — it would make a local deletion fail for a HealthKit reason, which is exactly the coupling this feature avoids everywhere else.
- **Only the workout type is requested from the delete path.** Active energy and heart rate are still asked for at workout start. A three-row permission sheet raised while the user is deleting something asks for more than the action needs, and HealthKit does not re-prompt for types the user already decided.
- **Exercise minutes:** deliberately called out in the confirmation copy rather than silently omitted, because the app cannot remove them and a promise of complete erasure would be false.
- **Detail screen size:** `WorkoutDetailView` is ~484 lines, over the repo's 200–300 line guideline; `WorkoutViewModel` is ~1990. Neither is materially worsened here, and no refactor was undertaken. The next structural touch of the detail view should extract the toolbar/confirmation and the section builders (`statsGrid`, `coachSection`, `exercisesSection`).
- **AI Coach analysis cache:** `AICoachCache` stores workout analyses on disk keyed by `workout.id`. Deleting a session does **not** purge its entry; the orphaned entry is unreachable (a new session gets a new UUID) and only costs a little disk. Purging it is a candidate cleanup, not a correctness issue.
- **No custom swipe-to-delete on iOS 18–26.** Reintroducing another horizontal row gesture is explicitly rejected. Use native `List.swipeActions` only as part of a deliberate whole-screen `List` redesign, or reassess `swipeActionsContainer()` once iOS 27 is the minimum supported OS.
