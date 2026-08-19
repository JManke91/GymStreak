# Workout Planning & Dynamic Weekly Goal

## What it is
Users can **plan** each routine onto a schedule. The weekly goal shown in the **Verlauf** (History → Trainings) tab is then **derived from those plans** — it counts how many planned sessions actually fall inside the current Mon–Sun week, instead of the old hardcoded magic number `4`.

Because the number of planned sessions in a given week depends on the schedule, the goal is **dynamic**: an "every 3 days" routine might land twice one week and once the next.

Target: **iOS app only** (`GymStreak`). The watch is untouched — schedules are not part of the watch-sync DTO.

## Decisions (confirmed with the user)
- **Hybrid schedule model** — each routine is planned *either* by a rolling cadence (**every N days**) *or* on fixed **weekdays** (e.g. Mon/Wed/Fri). A routine can also be **unplanned**.
- **Goal only for v1** — planning drives the weekly goal + "next due" ordering. **Reminders/notifications are intentionally deferred to phase 2** (research already done, see below).
- **Cadence rolls from the last workout** (see "Rolling semantics").
- **Unplanned → goal 0** — when nothing is planned, the WeekHero shows a "no plan yet" state inviting the user to plan, rather than a fake target.

## Weekly goal + day-strip semantics
Everything the user sees follows the **live** plan (so the day-strip markers always agree with the "next due" shown on cards). A day is marked only when it is genuinely **completed** (checkmark) or genuinely **upcoming** (dashed outline) — **today is never marked unless a session is actually due today.**

For an `everyNDays` routine the week's goal = **sessions already trained this week + sessions still upcoming this week** (from the live cadence). Concretely:
- `completedThisWeek` = this routine's completed sessions inside the Mon–Sun week.
- `upcoming` = `WorkoutPlanningService.upcomingCadenceDates(...)` filtered to `[today, week.end)` — the same forward walk used by the sheet preview and consistent with `nextDue`.
- `goal += completedThisWeek + upcoming.count`; only `upcoming` days are added to `plannedDates` (completed days already render as checks; past un-trained cadence days are neither counted nor marked — this is what removed the "today wrongly highlighted" bug).

This keeps the denominator **stable in normal use** (completing an upcoming session moves it from dash→check and pushes the next occurrence out of the week, so the total is unchanged) while never mislabelling today. It only grows under genuine over-training (doing a routine more often than its cadence), which correctly reads as "ahead of plan".

- **"Next due" is live.** The card/hero "next due" chip uses the *live* last completion + N (via `cadenceAnchor`), updating the instant a workout finishes.
- **Weekday schedules** are stable: goal = the selected weekdays in the week; every selected weekday is marked (past ones read as "missed", future/today as upcoming).

> Earlier design note (superseded): the goal denominator was previously a fixed cadence grid anchored on the *last completion before the week started*. That grid could mark days (incl. today) that the live plan had already moved past, so it was replaced by the completed-plus-upcoming model above.

### Reference date ("start fresh")
`RoutineSchedule.startDate` is a **user-editable reference date** (default: today), edited from a date picker in the planning sheet (interval mode). It is a **floor**:

- Completions **before** the reference date are ignored when anchoring the cadence — so a user whose last workout is way back can pick a fresh reference date and the schedule restarts from there.
- With no completion on/after the reference date, the **reference date itself is the first planned session** (`countsAsSession`).
- As soon as a workout lands **on or after** the reference date, the cadence **rolls off that completion** again (default behaviour). The reference date then goes dormant.

The single source of truth is `WorkoutPlanningService.cadenceAnchor(startDate:lastCompleted:)`, used by `nextDue`, the sheet preview, and `plannedWeek` — all three go through `upcomingCadenceDates(...)`, so the reference-date floor is applied uniformly.

Weekly goal = **Σ over active-planned routines** of their weekly contribution (weekday plans: selected weekdays in the week; cadence plans: `completedThisWeek + upcoming`, per the model above). No planned routines → goal 0.

## Architecture

### New files
```
GymStreak/Domain/Models/RoutineSchedule.swift                 @Model + RoutineScheduleType enum; owns the `routine` to-one
GymStreak/Data/Sync/RoutinePlanLinkRepair.swift                One-shot repair re-exporting plans CloudKit received unlinked
GymStreak/Domain/Services/WorkoutPlanningService.swift        Pure occurrence math: plannedWeek(), nextDue(), isoWeekday()
GymStreak/Presentation/Views/Routines/SchedulePlanningView.swift  ScheduleFormatter + RoutineScheduleCard + SchedulePlanningSheet
docs/workout-planning.md
```

### Data model (`RoutineSchedule`)
Optional **to-many** relationship off `Routine` (`schedules: [RoutineSchedule]?`, cascade delete) holding **at most one** element, with the inverse on `RoutineSchedule.routine`. Plans are read through the computed `Routine.schedule`, which picks the oldest `createdAt`, then the smallest `id`, so every device shows the same plan if two ever exist — and where the repair produced the duplicate the two rows are byte-identical, so the *outcome* is stable even when the comparator itself ties; they are written through `RoutinesViewModel.setSchedule`, which links via the child's `routine` property. All fields optional/defaulted → **CloudKit-safe, no migration**.

This was originally a one-to-one (`schedule: RoutineSchedule?`) and had to be remodelled — CloudKit does not mirror to-one ↔ to-one relationships. See "iCloud sync: why the plan is a to-many" below; do not "simplify" it back.
- `typeRaw` (`everyNDays` | `weekdays`), `intervalDays`, `weekdaysMask` (bitmask, bit `w-1` = ISO weekday `w`, 1 = Mon … 7 = Sun), `startDate`, `isActive`.
- Registered in the `Schema` in `GymStreakApp.swift` (and the `ContentView` preview container).

### Domain service (`WorkoutPlanningService`, `@MainActor` pure enum)
- `plannedWeek(routines:completedSessions:referenceDate:) -> PlannedWeek` → `{ goal, plannedDates, week }`.
- `nextDue(for:lastCompleted:referenceDate:) -> Date?` (overdue = past date).
- Reuses `HistoryStatsService.isoGermanCalendar()` + `weekInterval()` so planning and history never disagree on week bounds.
- `isoWeekday(from:calendar:)` converts Gregorian `.weekday` (1 = Sun) to ISO (1 = Mon), since `firstWeekday` does **not** change the `.weekday` component value.
- Cadence occurrence generation fast-forwards `k` (`gapDays / N`) before the bounded walk, so a far-past anchor doesn't cause a long loop.

### Presentation wiring
- `HistoryStatsService.weekStats` now takes `goal: Int` (the old `weeklyGoal`/`defaultWeeklyGoal` = 4 statics were **removed**). `WeekDayStatus` gained `isPlanned`; `weekDayStatuses` takes `plannedDates`.
- `HistoryView` adds `@Query private var routines` and passes them to `TrainingsTabView`, which computes `WorkoutPlanningService.plannedWeek(...)` and feeds `goal` + `plannedDates` into the WeekHero.
- `WeekHeroView`: dynamic "X von Y" headline; **zero-goal state** (dashed ring + `calendar.badge.plus` + "Plane deine Woche"); day-strip cells now render three states — completed (filled ✓), planned-not-done (dashed tint outline; past+missed dimmed), rest (neutral).
- `RoutinesViewModel`: `setSchedule(...)` / `removeSchedule(...)`, `nextDueDate(for:)`, and `upNextRoutine` now prefers the **soonest-due planned** routine (overdue sorts first), falling back to least-recently-trained when nothing is planned.
- `RoutineCardView`: shows a next-due pill when planned (else the "last trained" label).
- `RoutineDetailView`: a **"Zeitplan" card** (`RoutineScheduleCard`) below the title block → opens `SchedulePlanningSheet` (segmented Intervall/Wochentage, interval stepper or weekday chips, live "next 3 sessions" preview, remove-plan button).

### Repository
`RoutineRepository` gained `insert(_:RoutineSchedule)` / `delete(_:RoutineSchedule)` (implemented in `SwiftDataRoutineRepository`). Presentation never touches `ModelContext` — schedule CRUD goes through the ViewModel → repository.

## Watch surface (Up Next on the watch routine list)
The watch has **no plan/schedule data and no workout history** — it cannot compute `upNextRoutine` itself. Instead, the ordering is encoded in the sync payload:
- `RoutinesViewModel.syncRoutinesToWatch()` (iOS) moves `upNextRoutine` to index 0 before calling `watchSync.syncRoutines(...)`; the rest keep their `updatedAt`-desc order. No `WatchRoutine` model change was needed — the contract is purely "first routine in the payload = up next".
- `RoutineListView` (watch) renders the first stored routine in an "Up Next" section: the routine row (navigates to detail as before) plus a tinted quick-start button (`textOnTint` on tint-gradient `listRowBackground`) that presents `ActiveWorkoutView` directly, skipping the detail screen. Remaining routines render under "All Routines".
- Freshness: the order is a snapshot from the last sync (`updateApplicationContext` — coalesced, latest wins). iOS re-syncs on every `fetchRoutines()` (incl. after a watch workout is ingested and on `.watchAppBecameAvailable`), so the hero updates whenever the iOS app runs. An old cached payload simply shows the previous hero — acceptable.

## Pro gating (P9) — the weekday split is Pro, the cadence is free

Since the monetization work, the **fixed-weekday** plan shape is a Pro capability while the rolling
`everyNDays` cadence stays free. Full rationale and the presentation decisions live in
`docs/pro-subscription.md` §5f; what matters for planning itself:

- **`WorkoutPlanningService` is entitlement-unaware and must stay that way.** It computes
  occurrences for whatever schedule it is handed. A weekday plan built while subscribed keeps
  driving the weekly goal, the day-strip markers and the up-next ordering after a lapse — that
  guarantee is structural, not a check somebody remembered to write.
- The gate is `ScheduleGatingPolicy.isScheduleTypeLocked(_:isPro:isGatingEnabled:)`, consulted only
  by `RoutinesViewModel` — at `requestWeekdaySchedule()` (the sheet's mode picker and weekday chips)
  and again inside `setSchedule(...)`, which now returns `Bool` and refuses **before** mutating, so
  a refused edit leaves an existing plan intact.
- Moving a weekday plan back to the cadence is allowed, and `removeSchedule(...)` is never gated.
- A refused tap dismisses `SchedulePlanningSheet`, because the paywall is hosted at the app root and
  SwiftUI only presents it once the inner sheet is gone (§5f).
- Everything above is inert while `ProGating.isEnabled` is `false`, which is how the app ships until
  the launch release.
- **Constraint on the phase-2 reminders below:** notification scheduling must not consult the
  entitlement either. A lapsed user's existing weekday reminders have to keep firing.

## iCloud sync: why the plan is a to-many (root cause, 2026-08-18)

**Symptom.** A plan set on one device never appeared on another — and, the variant that actually bit the user, **plans vanished after reinstalling the app**. A reinstall rebuilds the local store from CloudKit, and because the exported records carried no routine reference, every plan came back attached to nothing: present in the store, invisible in the UI. That makes the bug reachable with a single device, which is why it read as "the plan is not persisted in iCloud" while routines, exercises and workout history all synced normally.

**What it was not.** Two plausible explanations were measured and disproved before the real one was found, so neither needs re-testing:

1. *A missing CloudKit record type.* `RoutineSchedule` was added 2026-07-07, after a Production deploy recorded as holding only nine record types, so the record type was assumed never to have been deployed. Exporting both environments with `cktool export-schema` on 2026-08-17 disproved it: Production holds all ten `CD_` types, `CD_RoutineSchedule` complete, `CD_Routine.CD_schedule` present, and Development byte-identical with no field-level drift. See `docs/cloudkit-schema-automation.md`.
2. *A broken write path.* `RoutinesViewModel.setSchedule` sets both sides of the relationship, inserts explicitly through the repository, and saves on the app's CloudKit-backed `mainContext`. No second writer, no schedule deletion outside `removeSchedule`, and no orphan-cleanup touching schedules exists anywhere in the target.

**Actual root cause.** Querying the live private database (`cktool query-records`, zone `com.apple.coredata.cloudkit.zone`) showed the plan records arriving intact but **unlinked**: all four `CD_RoutineSchedule` records carried `CD_typeRaw`, `CD_intervalDays`, `CD_isActive`, `CD_startDate`, `CD_createdAt` and `CD_id`, and **not one carried `CD_routine`**; all four `CD_Routine` records lacked `CD_schedule` entirely (CloudKit omits nil fields). Two controls proved relationship mirroring works in the same container: `CD_RoutineExercise` records carry populated `CD_routine` *and* `CD_exercise`, and `CD_WorkoutSession` records carry a populated `CD_routine`. Both controls are **to-many ↔ to-one**; `Routine.schedule` was the model's **only to-one ↔ to-one**. So the receiving device imported every schedule as an orphan with `routine == nil`, and since the UI reads plans exclusively through `routine.schedule`, every routine rendered as unplanned.

This contradicts Apple's own documentation, which states one-to-one relationships mirror by "storing foreign keys in both related records" ([Reading CloudKit Records for Core Data](https://developer.apple.com/documentation/CoreData/reading-cloudkit-records-for-core-data)) and does not list the cardinality as a restriction ([Creating a Core Data Model for CloudKit](https://developer.apple.com/documentation/CoreData/creating-a-core-data-model-for-cloudkit)). Treat it as an undocumented export gap in that rarer code path — a genuine one-to-one needs two independent record writes with no single atomic unit covering both foreign keys, and Apple separately warns that CloudKit may not save relationship changes atomically. **Ruled out as causes** by the control evidence: the `deleteRule: .cascade` (delete rules are local Core Data enforcement and are not encoded in the CKRecord schema at all — forums thread 708603) and which side declares `@Relationship(inverse:)` (the identical annotation pattern works for `RoutineExercise.routine`).

**The fix.** `Routine` now owns `schedules: [RoutineSchedule]?` — the same to-many ↔ to-one shape as the nine other relationships in this model, all of which demonstrably mirror — with `Routine.schedule` reduced to a computed accessor so read sites did not change. The link is established by setting the child's `routine`, which is the property that actually mirrors.

*Why not just fix the annotations:* neither lever (cascade rule, inverse side) is implicated by the evidence, so it would likely have changed nothing, and it would have left the feature on the least-travelled mirroring path with no way to confirm a fix beyond re-testing empirically.

*Why the parent side, and why this is migration-safe:* the app has **no `VersionedSchema`/`SchemaMigrationPlan`**, so it relies on SwiftData lightweight migration and only purely additive or storage-preserving changes are safe. A one-to-one is stored on both sides locally — verified in the simulator store, `ZROUTINE.ZSCHEDULE` and `ZROUTINESCHEDULE.ZROUTINE` both exist — and `setSchedule` has always set both. Dropping the parent column therefore loses nothing: the child's `ZROUTINE` column becomes the sole storage and the parent's to-many derives from it, so existing local plans survive. Renaming the parent to-one *into* a to-many would instead have been a semantic transformation lightweight migration cannot infer, requiring a custom migration stage.

**Repairing already-synced records (`RoutinePlanLinkRepair`).** Remodelling fixes plans created or edited from now on but not records already in CloudKit: mirroring exports from persistent history, so an object nobody touches is never re-uploaded, and **no Apple API forces a bulk re-export** (confirmed — the closest documented precedent is the dedup pattern in "Sharing Core Data objects between iCloud users", which is structurally the same delete-old/keep-new shape but is not a sanctioned force-re-export technique). The repair deletes each existing schedule row and inserts an identical replacement (same `id`, `createdAt`, `isActive` and settings) linked to its routine, which registers a create transaction, exports a correct record, and tombstones the broken one. It runs at most once per device behind a `UserDefaults` version flag set only after the save commits, so a failed save retries next launch instead of being skipped.

It **waits for the sync status to reach `.upToDate`** before touching anything (`CloudSyncStatusProviding.statusUpdates()`), because deleting a row while the importer is mid-flight could race the importer's merge on the same context or delete a record being materialized. Hence it runs from a `.task`, not `onAppear`. With iCloud off it does nothing and leaves the flag clear, so a later launch with iCloud available still repairs; a session that never quiesces likewise retries next launch.

**Neither available signal proves an import finished, so the gate is a mitigation rather than a guarantee.** Two traps, both discovered the hard way:

- `lastSuccessfulSync` is the obvious choice and it is wrong: `CloudKitSyncStatusMonitor` restores `lastSuccessfulExport`/`lastSuccessfulImport` from `UserDefaults` in its initialiser, so on any device that has ever synced the timestamp is already non-nil at launch, before this session has transferred anything. `RoutinePlanLinkRepairGatingTests.syncingWithAPriorSuccessDoesNotRepair` pins that the state, not the timestamp, decides.
- `.upToDate` is better but still **optimistic at cold launch**: the monitor seeds `currentStatus` from those restored values in `init`, so the first `.upToDate` can arrive before the session has imported anything. Observed exactly that on 2026-08-18 — after a delete-and-reinstall the pass ran immediately, found an empty store, and correctly deferred to the next launch.

A signal that genuinely proves quiescence would mean observing `NSPersistentCloudKitContainer.eventChangedNotification` for an `.import` event with `endDate != nil && succeeded` *in this session*; this app's sync-status abstraction cannot express that, and building it was judged not worth it for a one-shot repair whose failure mode is "retry next launch". Note `DefaultContentSeeder.recoverStrandedLibraryIfNeeded()` still gates on the weaker `lastSuccessfulSync`; that is pre-existing and untouched here, but it has the same flaw.

*Dead end — retrying within the session.* Having seen the pass defer on a fresh install, it was tempting to keep consuming the status stream and repair as soon as rows appeared. Reverted: `runIfNeeded()` then never returns for a user who has no plans, leaving a task suspended for the whole session, and it broke the guarantee the empty-store test relies on. The next-launch retry is sufficient — this is one-time cleanup, not a critical path.

It also **defers entirely if anything else has unsaved work on the shared `mainContext`** (`guard !modelContext.hasChanges`, the same guard and reason as `SwiftDataMainContextRoutineCacheRefresher`). Without it, this pass's `save()` could commit another component's staged changes and its `rollback()` could discard them — not hypothetical, since `DefaultContentSeeder.seedStrandedLibrary()` returns on save failure without rolling back, leaving its inserts pending on that context.

*Dead end — deleting orphaned schedules (implemented, then removed).* Schedules that import with `routine == nil` are invisible and unrecoverable, so cleaning them up looked free. It is a **data-loss bug**: a local delete is exported and removes the record for every other device that imports it (CloudKit's documented tombstone mechanism, `recordWithIDWasDeletedBlock`, is what mirroring is built on). The device that still holds the plan linked locally depends on that same shared record — an updated device deleting "its" orphan would destroy the plan on a device that has not updated yet, which is the only good copy. It is also redundant: when the device that owns the link runs its own repair, its delete of the stale record retires the orphan everywhere. **Orphans are therefore skipped, never deleted.**

*Dead end — automatically collapsing duplicate plans.* Two devices that both run the repair before syncing can leave two rows on one routine (CloudKit cannot enforce uniqueness, and each device's insert gets its own record name while carrying the same `id`). A per-launch "collapse duplicates" pass would be worse than the problem: because the replacement copies `id` **and** `createdAt` verbatim, duplicates are exact ties, so `Routine.schedule`'s comparator falls back to array order — two devices could pick *different* winners and each delete the other's, losing the plan entirely. Duplicates are instead left to self-heal: `setSchedule` collapses losers and `removeSchedule` deletes the whole set, so the user's next edit resolves it, and until then both rows are byte-identical so the UI is correct either way. Note this is convergence, not exclusivity — the repair itself deletes *every* row for a routine, including one another updated device just inserted and exported, so two deciders can exist cross-device. It still converges (each insert gets its own record name and mirroring re-exports from persistent history) and the worst case stays duplication rather than loss; what a *scheduled automatic* collapse would add is two deciders acting on a tie with no user intent behind either.

*Known unknown.* Whether a delete and its paired insert in one `save()` export atomically is undocumented, and Apple's own model-design guidance ("all relationships must be optional, as CloudKit may not save relationship changes atomically due to operation size limitations") says not to rely on it. An Apple forum thread on structurally the same dedup-with-relationships question sits unanswered by DTS. The reasoned worst case is duplication rather than loss, which is why the accessor tolerates duplicates.

**No CloudKit schema deploy is needed.** A to-many stores nothing on the parent, so the change writes no new field: `CD_RoutineSchedule.CD_routine` already exists in Production and is simply populated now, while `CD_Routine.CD_schedule` stops being written and stays in the schema harmlessly (CloudKit schemas are additive and fields cannot be removed). Confirm with an export after the first real run.

**Duplicate handling is load-bearing, not cosmetic.** Because a to-many makes a second row structurally reachable, every write path must treat the set rather than the winner. `removeSchedule` deletes **all** rows — deleting only the one `Routine.schedule` surfaces would promote the loser and the "removed" plan would reappear in the card, the weekly goal and the next-due ordering — and `setSchedule` collapses losers while editing so none survives. `RoutinePlanDuplicateTests` pins both behaviours.

**Verification status.**

*Measured.* Build succeeds; full iOS suite passes (797 tests, 0 failures), including `RoutinePlanLinkRepairTests`, `RoutinePlanDuplicateTests` and `RoutinePlanLinkRepairGatingTests`. The **lightweight migration was measured, not argued** (2026-08-18): a plan row was injected into the simulator's pre-change store — old schema, `ZROUTINE.ZSCHEDULE` present and populated — then the new build was installed over it. The app launched normally, `ZROUTINE.ZSCHEDULE` was dropped, `ZROUTINESCHEDULE.ZROUTINE` kept its foreign key, and the plan survived with its UUID, interval and start date intact. This mattered because a rejected migration would throw at `ModelContainer` creation, and the local-only fallback in `GymStreakApp` re-uses the identical schema — so the second attempt would fail too and the app would hit `fatalError` at launch. The repair proved itself in the same run: the row's `Z_PK` went 1 → 2, i.e. deleted and re-inserted with its values preserved, and a second launch left it at 2 with the `UserDefaults` flag at 1, so it is genuinely one-shot.

*Confirmed against live CloudKit (2026-08-18).* A Debug build on a real iCloud-signed-in iPhone wrote a plan, and `cktool query-records` against the Development private database shows the new `CD_RoutineSchedule` records carrying a **populated `CD_routine`** (e.g. `00DAE846… → routine A4280A60…`, `intervalDays = 3`), while every record written before the fix still shows the field absent. The relationship mirrors. In the same pass the Development and Production schema exports came back byte-identical and Development unchanged from the pre-fix export, so **the no-deploy expectation held** — nothing needs deploying in the Console.

*Not exercised in the wild: the repair pass.* On that phone it correctly found nothing to do, and `CD_createdAt` is how to tell — the repair copies `createdAt` verbatim, so a re-exported record shows an old creation date with a recent server timestamp, whereas both new records carried today's date and were therefore fresh `setSchedule` writes. The phone's routines appeared unplanned, i.e. it only ever imported the pre-fix plans as orphans and holds none of them linked, so `plannedRoutines` was empty. The repair remains covered by unit tests and by the simulator migration run (`Z_PK` 1 → 2), but has not yet re-exported a real record.

**Consequence for pre-fix plans — they were unrecoverable here.** A plan that reached CloudKit unlinked can only be repaired from a device that still holds it linked locally, because the record itself does not say which routine it belonged to. On this account the only device had been reinstalled, so every pre-fix plan was already an orphan before the fix shipped and nothing could relink them; the plans were re-created by hand. Deleting the orphans is deliberately not attempted by *code* (see the dead end above), but once it is established that no device holds the link — as here — removing them manually is safe. The four stale records (2026-07-07 and 2026-08-10) were deleted on 2026-08-19 with `cktool delete-record` from both environments, after confirming that no `CD_Routine` record in either carried a `CD_schedule` value. Development now holds only the two live linked plans; Production holds none, since the only schedules that ever reached it were the broken ones.

## Edge cases
- **Never-trained cadence routine**: anchors on the reference date (default today); its `reference + k·N` grid is counted, `k = 0` included.
- **Stale history + fresh reference date**: an old completion before the chosen reference date is ignored; the plan restarts from the reference date until the next workout.
- **Completed today**: `nextDue` / preview show `today + N` (not today again). **Never trained / reference = today**: first session is today.
- **Overdue**: `nextDue` returns a past date; the chip reads "Überfällig", and it sorts first for the up-next hero. The sheet **preview is forward-looking** (shows upcoming dates from today), so it can diverge from the chip for overdue plans — intentional (chip = status, preview = plan).
- **Deleting a routine** cascade-deletes its schedule.
- **Weekday schedule with no days selected**: not savable (Save disabled); contributes 0.

## Deferred to phase 2 — Reminders (research captured, NOT built)
Local notifications when a planned routine is due. Findings (via `ios-api-researcher`, Apple `UserNotifications` docs):
- **Weekday schedules** → one repeating `UNCalendarNotificationTrigger(dateMatching: {weekday,hour,minute}, repeats: true)` per selected weekday. Stable id `routine.<id>.weekday.<w>`.
- **"Every N days"** is **not** expressible as a calendar recurrence (`DateComponents` only matches calendar-aligned fields). Use a **rolling window of one-shot** `UNCalendarNotificationTrigger(..., repeats: false)`, ids `routine.<id>.occurrence.<isoDate>`, refreshed on app foreground; stay under the **64 pending-notification** cap by budgeting a look-ahead window per routine.
- **Authorization**: just-in-time `requestAuthorization(options:)` when the user first enables a reminder; check `getNotificationSettings` before scheduling; avoid `.provisional` (silent delivery defeats a reminder).
- **Editing/removing a plan**: `removePendingNotificationRequests(withIdentifiers:)` scoped to that routine's id namespace, then reschedule (re-adding same id replaces).
- **EventKit/`EKRecurrenceRule`**: not appropriate — it needs Calendar permission and writes user-visible calendar events. Plain `Calendar`/`DateComponents` math is correct here.
- Architecture: add a routine-specific `Domain/Interfaces/WorkoutReminderScheduling` protocol and implementation alongside the existing `Data/Notifications/UserNotificationRestTimerScheduler`, wired in `AppDependencies`. The existing rest-timer gateway is deliberately not reused because planned-routine reminders need per-routine identifier namespaces and rolling-window rescheduling.
