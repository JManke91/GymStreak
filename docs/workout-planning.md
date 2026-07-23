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
GymStreak/Domain/Models/RoutineSchedule.swift                 @Model + RoutineScheduleType enum; Routine.schedule relationship
GymStreak/Domain/Services/WorkoutPlanningService.swift        Pure occurrence math: plannedWeek(), nextDue(), isoWeekday()
GymStreak/Presentation/Views/Routines/SchedulePlanningView.swift  ScheduleFormatter + RoutineScheduleCard + SchedulePlanningSheet
docs/workout-planning.md
```

### Data model (`RoutineSchedule`)
One-to-one, optional relationship off `Routine` (`schedule: RoutineSchedule?`, cascade delete). All fields optional/defaulted → **CloudKit-safe, no migration**.
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
