# Delete a Recorded Workout

## What it is
A visible way to delete a recorded workout, and — when the workout also exists in Apple Health — a per-deletion choice of whether Health should be cleaned up too.

There are three entry points, all of which raise the **same** confirmation:

1. The workout detail screen's ellipsis **Menu** (also holds Edit Workout).
2. **Swiping a history card to the left** in the Trainings list, which reveals a destructive delete action.
3. The pre-existing **long-press context menu** on a history card.

The workout detail screen's trailing toolbar item is an ellipsis **Menu** holding **Edit Workout** and a destructive **Delete**; the previously standalone pencil button is folded into that menu. Delete raises a destructive confirmation alert:

- **Workout with an Apple Health counterpart** → two destructive choices, *Delete in GymStreak Only* and *Delete in GymStreak and Apple Health*, plus Cancel.
- **Workout without one** (`healthKitWorkoutId == nil`) → a single *Delete* plus Cancel. The Apple Health option is not offered, because there would be nothing for it to remove.

Confirming pops the detail screen and removes the session from history.

Target: **iOS app only** (`GymStreak`). No changes to the watch target.

Related: [History (Verlauf) Redesign](./history-redesign.md), [Edit a Past Workout](./edit-past-workout.md), [Watch Workout Recovery](./watch-workout-recovery.md).

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

### Swipe a history card to delete
Dragging a card in the Trainings **list** to the left slides it aside and reveals a red trash action; tapping that action raises the shared confirmation above. Scope is deliberately the month-grouped list only — **calendar mode keeps the detail-screen route**, because it shows a single card for the selected day where a swipe adds little.

**`.swipeActions` and `.onDelete` are not usable here, and this is not worth re-attempting.** Both require a `List` or `Form`. The history list is a `ScrollView` → `VStack` of custom cards grouped under month dividers, and it sits inside `HistoryView`'s own outer `ScrollView`, so a `List` cannot be nested into it either. The two `.swipeActions` occurrences elsewhere in the codebase (`CreateRoutineView`, the watch's `ExerciseListView`) are inside a `List`/`Form` and are not transferable.

**Converting the history screen to a `List` was considered and rejected** — it would mean reworking the month section headers, card insets, spacer views, the WeekHero block and the segmented header of a recently redesigned screen, a large regression risk for no user-visible gain.

So the affordance is hand-rolled in `SwipeToDeleteContainer`, which wraps each card:

```swift
content                                        // a plain card — never a Button/NavigationLink
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { select() }          // VoiceOver double tap
    .accessibilityAction(named: Text("action.delete".localized)) { … }
    .background(DesignSystem.Colors.background, in: RoundedRectangle(cornerRadius: 20, …))
    .onTapGesture { handleTap() }              // open card → dismiss only; else select
    .focusable()                               // Full Keyboard Access
    .onKeyPress(.return) { select(); return .handled }
    .onKeyPress(.space)  { select(); return .handled }
    .simultaneousGesture(dragGesture)          // 15pt minimum, horizontal-dominant only
    .offset(x: offset)
    .background(alignment: .trailing) { deleteAction }
    .clipShape(RoundedRectangle(cornerRadius: 20, …))
```

Six details in that composition are load-bearing:

- **The row must not be a `Button` or `NavigationLink`.** This was shipped wrong once and is the single most important note in this section. The first implementation wrapped the existing `NavigationLink(value: session.id)`, on the reasoning that a 15pt `minimumDistance` means a stationary tap is never claimed by the drag — which is true, but irrelevant. **A SwiftUI button activates on touch-up anywhere inside its bounds**, mirroring UIKit's `.touchUpInside`; it tolerates arbitrary finger movement in between. A swipe therefore *is* a valid activation, and `.simultaneousGesture` is documented to let both the drag and the view's own gestures recognize without cancelling each other — so every swipe both revealed the action and pushed the detail screen, making the delete unreachable. The fix is to remove the button entirely: the card is a plain view, the container owns the tap through `.onTapGesture` and reports it via `onSelect`, and `HistoryView` pushes by appending to a `NavigationPath`. That path must stay type-erased (`NavigationPath`, not `[UUID]`) because the same stack also pushes `ExerciseWithHistory` and `PeriodRecapDestination` values from other links. **Do not "simplify" the row back to a `NavigationLink`** — `GymStreakUITests/SwipeToDeleteUITests.swift` fails if you do.

  Binding that path had two knock-on consequences, both handled. The AI Coach settings screen was pushed with `.navigationDestination(isPresented:)`, which is **not represented in the path**; leaving the two views of one stack able to disagree invites spurious pops and double pushes, so it was converted to a value-based destination (`AICoachSettingsDestination`) like every other destination on this stack. And a programmatic push can fire twice where a `NavigationLink` could not, so `pushWorkout(_:)` guards on `path.isEmpty` — cards are only tappable at the root.
- **`.simultaneousGesture`, never `.gesture` or `.highPriorityGesture`.** The latter two starve the enclosing scroll view's pan recognizer — a documented iOS 18 failure mode where the ScrollView stops scrolling entirely. Simultaneous recognition lets both run. `onChanged` additionally bails out unless `abs(translation.width) > abs(translation.height)`, so a vertical scroll can't make a row catch. Unlike a button, a `TapGesture` fails once the finger moves, which is why the tap and the drag can now coexist on the same row.
- **The opaque backdrop.** `WorkoutCardView`'s own background is `Color.white.opacity(0.035)`; without an opaque layer beneath it the red action would show through the resting card. The backdrop uses the screen's own background colour, so the card looks unchanged.
- **The revealed action is a `.background` applied *outside* the `.offset`.** `.offset` is layout-neutral, so the background is sized from the card (and therefore fills its full height) and stays put while the card slides. Putting the action in a `ZStack` instead does **not** work: inside a `ScrollView` the height proposal is nil, so a `frame(maxHeight: .infinity)` sibling collapses to its own ideal height and leaves gaps above and below the red strip.
- **`AccessibilityActionKind.delete` is macOS-only** — it compiles nowhere on iOS. The VoiceOver path uses `.accessibilityAction(named:)`, which surfaces in the standard Actions rotor. The red button is `.accessibilityHidden(!isOpen)`: an element once revealed, invisible to VoiceOver while it sits behind a closed card.
- **The row's button semantics are rebuilt by hand.** Dropping the `NavigationLink` also dropped what it gave for free, so the container restores it: `.accessibilityElement(children: .combine)` makes the card one element instead of a pile of loose labels, `.accessibilityAddTraits(.isButton)` restores the trait, a default `.accessibilityAction` handles VoiceOver's double-tap activation (`.onTapGesture` alone is not an accessibility action), and `.focusable()` + `.onKeyPress(.return)` restore Full Keyboard Access, which a plain view with only the `.isButton` trait does not get.

**Only one card is open at a time.** The open card and the id of the card being dragged live in one `HistorySwipeState` struct owned by `HistoryView` (the view that owns the scroll view) and passed down as a `Binding`. Opening a card closes any other, and — matching a `List` row — **a tap while any card is open only dismisses it**, so a swipe left open never leads to an accidental push. Switching list/calendar mode, switching Trainings/Fortschritt, or scrolling also closes it. The in-flight drag is tracked by card id (`draggingCardId`) rather than as a `Bool`, so a second finger on another card cannot end the first card's drag and strand it mid-offset. Scroll-driven closing reads `contentOffset.y` via `.onScrollGeometryChange` and is **suppressed while a card is being dragged** — otherwise the few points of vertical drift in a slightly diagonal swipe would close the very card being opened.

The pre-existing long-press `.contextMenu` stays on the card inside the container. A row carrying both a swipe action and a context menu is normal on iOS; the two gestures are naturally exclusive (one needs displacement, the other needs stillness). If they ever do interfere, the fix is to move `.contextMenu` up onto the container rather than the wrapped card.

### Ordering: local delete first, HealthKit best-effort
`WorkoutViewModel.deleteWorkout(_:alsoFromHealthKit:)` captures `session.healthKitWorkoutId` *before* deleting (the `@Model` instance is invalid afterwards), performs the local delete synchronously, and only then fires a detached `Task` for HealthKit:

```
deleteWorkout(session)                       // SwiftData is the source of truth
  ↓ workoutSessionRepository.delete → save → fetchWorkoutHistory
guard alsoFromHealthKit, let healthKitWorkoutId
  ↓
Task { try await healthKitManager.deleteWorkout(externalUUID:) }
```

The local delete is never gated on, blocked by, or rolled back for HealthKit. A HealthKit failure only sets `@Published var healthKitDeleteFailed`, which `HistoryView` renders as `HealthDeleteFailureBanner` — a non-blocking inline notice with a dismiss button, not a modal. Apple's HIG has no explicit rule for this case; treating it as information rather than an error the user must acknowledge is a deliberate product call, justified by the fact that nothing is left for the user to decide (the local delete already succeeded; the only consequence is a leftover entry they can remove in the Health app).

### Finding and deleting the HealthKit workout
`HealthKitWorkoutManager.deleteWorkout(externalUUID:)` (behind `HealthKitWorkoutServicing`):

```swift
let predicate = HKQuery.predicateForObjects(
    withMetadataKey: HKMetadataKeyExternalUUID,
    allowedValues: [externalUUID.uuidString]
)
let descriptor = HKSampleQueryDescriptor(
    predicates: [.workout(predicate)], sortDescriptors: [], limit: 1
)
let matches = try await descriptor.result(for: healthStore)
guard let workout = matches.first else { return false }   // already gone
try await healthStore.delete(workout)
return true
```

The `Bool` return distinguishes "deleted" from "nothing matched". **Nothing matched is a success, not an error** — see the research notes below.

### Cascade deletion of children (local)
No child objects are hand-deleted. `WorkoutSession.workoutExercises` and `WorkoutExercise.sets` both declare `.cascade` delete rules, so exercises and sets are removed with the session. Deleting them manually would be redundant and risks double-delete.

### List and calendar refresh
`deleteWorkout(_:)` republishes `viewModel.workoutHistory`. `HistoryView` observes `onChange(of: viewModel.workoutHistory.count)` and re-runs `refresh()`, so both list mode and calendar mode drop the workout without a manual pull-to-refresh. `HistoryView`'s `navigationDestination(for: UUID.self)` resolves the session by id from that same array, so a stale push cannot resurrect a deleted session.

### Watch-originated workouts do not reappear as recovery offers
Neither the local delete nor the HealthKit delete leaves a stale recovery-ledger entry, and this required **no code change**. `WorkoutRecoveryCoordinator` protects against a re-offer three times over:

- **Ledger state is terminal.** Once the session was committed, `applyStateTransition` moved the ledger entry from `.provisional` to `.resolvedByHistory` (or `.placeholderSaved` for a recovered placeholder). `WorkoutRecoveryReconciler.decide` returns `.resolve` for those states before it looks at anything else.
- **Ingest receipts outlive history.** `reconcileLedger` treats `receipts.receipt(forHealthKitWorkoutId:) != nil` as proof of prior ingestion — the comment in that file states the intent explicitly: *"A receipt proves prior ingestion even if the user deleted history."*
- **The HealthKit deletion is itself absorbed by the ledger.** The next anchored-query drain reports the removed object in `deletedObjectUUIDs`; `WorkoutRecoveryLedgerStore.applyDeleted(objectUUID:now:)` maps it back to its candidate and tombstones the entry once it loses its last HealthKit object. A tombstoned candidate is never offered for recovery.

## Architecture

### Files modified
- `GymStreak/Domain/Interfaces/HealthKitWorkoutServicing.swift` — added `deleteWorkout(externalUUID:) async throws -> Bool` to the existing gateway protocol.
- `GymStreak/Data/HealthKit/HealthKitWorkoutManager.swift` — implemented that method against the real `HKHealthStore`; added `HealthKitError.deleteFailed`.
- `GymStreak/Presentation/ViewModels/WorkoutViewModel.swift` — added `deleteWorkout(_:alsoFromHealthKit:)`, the `healthKitDeleteFailed` published flag, and `dismissHealthKitDeleteNotice()`.
- `GymStreak/Presentation/Views/History/WorkoutDetailView.swift` — `@Environment(\.dismiss)`, `showingDeleteConfirmation` state, the toolbar `Menu`, the shared confirmation, and the private `deleteWorkout(alsoFromHealthKit:)` helper.
- `GymStreak/Presentation/Views/History/HistoryView.swift` — its long-press delete alert replaced by the shared confirmation; renders the failure banner; owns `HistorySwipeState` and closes an open swipe card on scroll; fires the success haptic on a confirmed delete so the list paths match the detail screen; owns the `NavigationPath` the list cards push onto.
- `GymStreak/Presentation/Views/History/TrainingsTabView.swift` — list cards wrapped in `SwipeToDeleteContainer` as plain (non-`NavigationLink`) cards; takes the `HistorySwipeState` binding and an `onSelectWorkout` closure, and clears the open card when switching display mode.
- `GymStreak/Resources/{en,de}.lproj/Localizable.strings` — new keys (table below).
- `GymStreakTests/Support/MockHealthKitWorkoutServicing.swift` — the hand-written double gained the new method with a recording array, an injectable error, and an injectable "already gone" result.

### Files added
- `GymStreak/Presentation/Views/History/Components/DeleteWorkoutConfirmation.swift` — the shared `ViewModifier` + `View` extension hosting the confirmation.
- `GymStreak/Presentation/Views/History/Components/HealthDeleteFailureBanner.swift` — the non-blocking failure notice.
- `GymStreak/Presentation/Views/History/Components/SwipeToDeleteContainer.swift` — the hand-rolled swipe row plus the `HistorySwipeState` struct that coordinates it.
- `GymStreakUITests/SwipeToDeleteUITests.swift` — gesture regression coverage (see Tests).

### Files unchanged on purpose
- `WorkoutSessionRepository` and its protocol — the local delete path already existed end to end.
- `App/AppDependencies.swift` — **no new dependency wiring.** The delete capability was added to a protocol the ViewModel is already injected with.
- No SwiftData field and no migration were introduced. The workout is located by the `healthKitWorkoutId` we already store; persisting `HKWorkout.uuid` instead would have needed an additive `@Model` field (and therefore a CloudKit schema deploy) for no benefit.
- `TrainingsTabView`'s long-press `.contextMenu` delete — kept. It costs nothing and preserves existing muscle memory; the problem was that it was the *only* way in, not that it exists.
- `WorkoutDetailView.loadHealthKitKcal()` still constructs its own `HKHealthStore()` inline to read calories — a pre-existing layer violation, deliberately worked *around* rather than expanded. The new delete goes through the gateway protocol. Fixing the older read is a separate cleanup.

### Layer compliance
Dependency direction holds: the new capability is declared in `Domain/Interfaces/`, implemented in `Data/HealthKit/`, and consumed by `Presentation/` through the injected protocol. No `ModelContext`/`FetchDescriptor` in views, no `.shared` access in the ViewModel, no ad-hoc service construction, no `@Model`/schema change.

## HealthKit research findings
Confirmed against Apple documentation and Apple engineer forum replies before implementation. **Do not re-research these.**

- **Delete API:** `HKHealthStore.delete(_ object: HKObject) async throws` for a single workout. The array and `deleteObjects(of:predicate:)` variants also have async overloads, but the single-object form fits here because we resolve the workout first. Note for any future batch work: the array/predicate variants are **all-or-nothing** — if one object can't be deleted, none are.
- **Lookup strategy:** query by our own metadata (`HKMetadataKeyExternalUUID`, stamped at save time and mirrored in `WorkoutSession.healthKitWorkoutId`) using `HKQuery.predicateForObjects(withMetadataKey:allowedValues:)`. Metadata predicates work with custom keys. There is already a working metadata-lookup precedent in the watch manager and in this detail view's calorie read.
- **Query API:** `HKSampleQueryDescriptor` with async `result(for:)` and `HKSamplePredicate.workout(_:)` — iOS 15.4+, well under the iOS 26.1 floor. Apple's current concurrency-native recommendation; it removes the `withCheckedContinuation` wrapper the older code paths use.
- **Scoping to our own source is unnecessary.** `HKQuery.predicateForObjects(from:)` could be ANDed in, but HealthKit enforces the ownership rule on delete regardless of what the query matched.
- **No new authorization.** Deleting needs *share* authorization for `HKObjectType.workoutType()` and finding the sample needs *read* — the app already requests both. Read authorization is undetectable by design: `authorizationStatus(for:)` reports only sharing status, and a denied read looks identical to "no such data."
- **"Already gone" is not an error.** A zero-result query is indistinguishable from a silently denied read or a user who already deleted the workout in the Health app. All three mean the desired end state holds, so `deleteWorkout(externalUUID:)` returns `false` and the ViewModel treats it as success.
- **Ownership errors have no dedicated code.** Failures surface as `HKError.errorAuthorizationDenied`, `errorAuthorizationNotDetermined`, or `errorInvalidArgument`. They are handled generically; there is no "not your data" case to switch on.
- **Cascade behaviour.** Deleting the `HKWorkout` also removes the quantity samples its builder associated with it (active energy, distance, heart rate). Reported by an Apple engineer; *not* stated as a contract in the reference docs.
- **Activity Ring exercise minutes cannot be deleted by any app.** They are system-awarded and only the user can remove them in the Health app. This is a hard Apple limitation, which is why the confirmation copy promises removal of the *workout* and explicitly says the credited exercise minutes stay in Health.
- **GymStreak saves no `HKWorkoutRoute`,** so route cascade is moot. If routes are ever added, delete them explicitly rather than assuming cascade — undocumented either way.
- **Watch-recorded workouts.** A workout recorded by the watch app via `HKWorkoutSession`/`HKLiveWorkoutBuilder` is saved with `sourceRevision.source` carrying the **iPhone app's** bundle identifier, and the watch's store is a rolling ~7-day synced subset of the phone's — so the phone is expected to be allowed to delete it, and this is not a cross-app ownership violation. Confidence was **medium-high from an Apple engineer forum reply, not a documented contract** — **confirmed empirically on a physical iPhone + Apple Watch on 2026-07-26** (see Verification below): the phone deleted a watch-recorded workout and it vanished from the Health app.

Sources: [`delete(_:)`](https://developer.apple.com/documentation/healthkit/hkhealthstore/1614155-deleteobject) · [`predicateForObjects(withMetadataKey:allowedValues:)`](https://developer.apple.com/documentation/healthkit/hkquery/1614780-predicateforobjects) · [`HKSampleQueryDescriptor`](https://developer.apple.com/documentation/healthkit/hksamplequerydescriptor) · [`authorizationStatus(for:)`](https://developer.apple.com/documentation/healthkit/hkhealthstore/authorizationstatus(for:)) · [watch-vs-phone source, Apple engineer reply](https://developer.apple.com/forums/thread/683224) · [exercise minutes survive deletion, Apple engineer reply](https://developer.apple.com/forums/thread/681755)

## Localization

| Key | en | de |
| --- | --- | --- |
| `workout.history.delete.title` (reused) | Delete Workout? | Workout löschen? |
| `workout.history.delete.message` (reused) | Are you sure…? | Möchtest du…? |
| `workout.history.delete.message_health` | …choose whether to remove it from Apple Health too; credited exercise minutes stay in Health | …ob es auch aus Apple Health entfernt wird; gutgeschriebene Trainingsminuten bleiben in Health |
| `workout.history.delete.gymstreak_only` | Delete in GymStreak Only | Nur in GymStreak löschen |
| `workout.history.delete.with_health` | Delete in GymStreak and Apple Health | In GymStreak und Apple Health löschen |
| `history.delete.health_failed` | Deleted in GymStreak, but couldn't be removed from Apple Health… | In GymStreak gelöscht, konnte aber nicht aus Apple Health entfernt werden… |
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
- `healthKitDeleteFailureLeavesLocalDeleteCommitted` — a throwing HealthKit delete leaves the local deletion and the republished history intact and raises only the non-blocking flag.
- `alreadyAbsentHealthKitWorkoutIsNotTreatedAsFailure` — a `false` result (nothing matched) does not raise the flag.

`GymStreakUITests/SwipeToDeleteUITests.swift` covers the swipe gesture, which no unit test can observe — the behaviour under test is gesture arbitration:

- `testSwipingCardRevealsDeleteWithoutNavigating` — the regression guard. Swiping reveals the delete action **and** the detail screen's `More` menu is absent, i.e. no push happened.
- `testRevealedDeleteOpensConfirmation` — tapping the revealed action raises the shared confirmation alert.
- `testTappingCardStillNavigatesToDetail` — the gesture did not cost the plain tap.
- `testCoachSettingsStillPushesOnThePathBoundStack` — the other destination on the now path-bound stack still pushes, covering the `isPresented` → value-based conversion.

These were confirmed to **fail against the pre-fix `NavigationLink` version** (the swipe navigated, so the delete action was never revealed) and pass after it, so they genuinely detect the regression rather than merely passing.

Two setup details these tests depend on: the app must be launched with `-UI_TESTING` so `TestDataSeeder` seeds workout history, and the **AI Coach opt-in prompt covers the UI on a fresh launch and swallows taps** — it must be dismissed via its "Maybe later" / "Vielleicht später" button before the tab bar is usable. `UITestHelpers.navigateToTab` silently does nothing when that prompt is up, which is worth knowing for any future UI test in this app.

## Verification

**Automated / static**

- **Build:** `xcodebuild -scheme GymStreak -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` → BUILD SUCCEEDED (re-confirmed after the swipe affordance landed).
- **Tests:** `GymStreakTests` → TEST SUCCEEDED (283 tests in 36 suites at the time of the Apple Health slice). `GymStreakUITests/SwipeToDeleteUITests` → all 4 pass. The older `GymStreakUITests` screenshot generators fail in a bare `xcodebuild test` run — `GymStreakUITests.swift:147: Bench Press exercise should be visible`, in the routines screenshot flow. That is a pre-existing fastlane-pipeline dependency unrelated to deletion; those tests are driven by `/screenshots` with seeded data and language launch arguments. (Their root cause is likely the same AI Coach opt-in prompt documented under Tests, which `navigateToTab` cannot tap through — not investigated, since fixing the screenshot pipeline is out of scope here.)
- **Architecture review:** `architecture-reviewer` → PASS WITH WARNINGS across all three passes (Apple Health slice, swipe slice, navigation fix), no CRITICAL findings. Every warning was fixed rather than merely acknowledged: the stale doc comment on the shared confirmation, drag ownership tracked by card id instead of a shared `Bool`, the `isPresented` destination on a path-bound stack, the missing keyboard focusability, the open card surviving a Trainings/Fortschritt switch, and the List-style "a tap while a card is open only dismisses it" rule.

**Manual testing of the local-delete slice — passed** (confirmed 2026-07-26): dismiss-then-delete ordering with a rich workout (no crash, no blank flash), calendar mode, list mode, cancel path, the pre-existing long-press context menu, Edit still reachable inside the ellipsis menu, and a watch-originated workout that did not resurface as a pending-sync offer after backgrounding and reopening the app.

**Device validation of the Apple Health delete — PASSED** (physical iPhone + Apple Watch, 2026-07-26). The one assumption that could not be settled in the simulator was whether the phone may delete a **watch-recorded** HealthKit workout (see the research note above). Observed on device:

1. A workout recorded on the watch and synced to the phone was deleted from the phone with *Delete in GymStreak and Apple Health*.
2. **It disappeared from the Health app.** The phone *is* allowed to delete a watch-recorded workout — the forum-sourced expectation holds in practice, no failure banner appeared. This settles the open research question: watch-recorded workouts carry the iPhone app's bundle identifier as their source, so deleting them from the phone is not a cross-app ownership violation.
3. **Credited exercise minutes remained** on the Activity rings, exactly as predicted — the app cannot remove them and the confirmation copy is correct to say so.
4. Backgrounding and reopening GymStreak left the **pending-sync banner quiet** — no stale recovery-ledger entry, the deleted workout was not re-offered.
5. The two-option alert plus cancel rendered correctly in **both English and German**.

No product fallback is needed: the Apple Health option stays available for watch-recorded workouts.

**Swipe-to-delete — PASSED on a physical iPhone** (2026-07-26), after one failed round.

The first implementation wrapped the existing `NavigationLink`, and device testing immediately showed every swipe pushing the detail screen instead of leaving the delete action reachable (see the `NavigationLink` note above for why). After the rework — plain card, container-owned tap, programmatic `NavigationPath` push — the gesture was confirmed working on device.

That failure is why `SwipeToDeleteUITests` exists. All four pass; the three *gesture* tests (reveal-without-navigating, revealed-delete-opens-confirmation, tap-still-navigates) were additionally verified to fail against the buggy version, so they genuinely detect the regression. The fourth covers the path-bound stack's other destination. The lesson worth carrying forward: **a hand-rolled gesture on a scroll-view row cannot be signed off from a build succeeding** — the simulator and the compiler both accepted the broken version.

## Edge cases and decisions
- **Undo:** none. The confirmation copy states the action cannot be undone, matching the pre-existing context-menu delete.
- **A workout whose HealthKit save failed or was denied** has `healthKitWorkoutId == nil`. That is normal, never blocks deletion, and suppresses the Apple Health option rather than offering a no-op.
- **Exercise minutes:** deliberately called out in the confirmation copy rather than silently omitted, because the app cannot remove them and a promise of complete erasure would be false.
- **Detail screen size:** `WorkoutDetailView` is ~484 lines, over the repo's 200–300 line guideline; `WorkoutViewModel` is ~1990. Neither is materially worsened here, and no refactor was undertaken. The next structural touch of the detail view should extract the toolbar/confirmation and the section builders (`statsGrid`, `coachSection`, `exercisesSection`).
- **AI Coach analysis cache:** `AICoachCache` stores workout analyses on disk keyed by `workout.id`. Deleting a session does **not** purge its entry; the orphaned entry is unreachable (a new session gets a new UUID) and only costs a little disk. Purging it is a candidate cleanup, not a correctness issue.
- **Swipe-to-delete** reuses `.deleteWorkoutConfirmation(...)` unchanged — which is why the confirmation was extracted into a shared modifier rather than duplicated instead of being built twice.
- **Gesture risk and the product fallback.** Apple Developer Forum thread [794212](https://developer.apple.com/forums/thread/794212) reports `simultaneousGesture(DragGesture())` on rows inside a `ScrollView` behaving unreliably on iOS 26 betas (jittery or hijacked vertical scrolling). The reported repro used a rotated scroll view, which does not apply here, and the design deliberately avoids the known trigger (`highPriorityGesture`). The simulator UI tests show the swipe and the tap arbitrating correctly, but they exercise synthesised gestures — how it feels under a real finger is still a device question. **If the gesture ever proves to fight the scroll view in practice, the agreed fallback is a small visible ellipsis button on each card reusing the detail screen's menu shape** — not a fiddlier gesture.
- **Deliberately not built: full-swipe-to-delete.** Dragging all the way across does not delete; the card clamps just past the action width. A destructive action that fires from an over-drag with no confirmation is the wrong default when the confirmation is the whole point of the feature.
