# Workout Reminders

## What it is

The app speaks to the user about training on three occasions, all at 08:00 local time and all under
one frequency cap:

1. **Planned-session reminder** — the morning of each planned training day.
2. **Missed-session nudge** — the morning after a planned day on which nothing was logged.
3. **Dormancy nudge** — for users with **no plan**: 4 days after the last completed workout (or after
   first launch), once more a week later, then silence until they train.

Before any of that, **one in-app screen** offers the feature; its yes button is the only thing in
this feature that can raise the iOS notification permission prompt.

Target: **iOS app only** (`GymStreak`). The watch is untouched — schedules are not part of the
watch-sync DTO and watchOS shows no reminders. The widget reads none of this.

Shipped in two slices of `docs/acquisition-strategy.md` lever #13: the planned-session reminder and
the permission seam on 2026-09-09 (`.scratch/acquisition-phase-b/issues/03`), and the two nudges on
2026-09-16 (`04`) — **through the same plumbing, the same permission and the same cap**: triggers,
not a second scheduler and not a second cap.

## Why it exists

§1a of the acquisition strategy measured that 15% of installs ever launch the app twice. Before this
feature the **only** `UNUserNotificationCenter` use in the whole codebase was the rest timer: there
was no workout reminder, no scheduled-session nudge, and no streak reminder in an app called Gym
Streak. This is the only lever in the strategy that *asks* the user to come back.

**Monetization: free, and not a concession.**

```
Monetization verdict — workout and streak reminders
  Tier          Free
  Derivation    §3 Rule 1 — it is the aha path (train → log → see the number go up)
  Mechanism     n/a — nothing is gated
  Placement     none
  Nudge         none
  Free residue  the entire feature
  Founder note  gating this would convert nobody. It exists to make a free user return at all,
                and a user who does not return is not a Pro prospect.
```

Re-checked at completion of both slices: nothing shipped here reads `ProEntitlementProviding`, and
no `PaywallPlacement` was added. The scheduler is deliberately entitlement-unaware for the same
structural reason `WorkoutPlanningService` is — a lapsed subscriber's weekday plan keeps driving
reminders, exactly as it keeps driving their weekly goal (`docs/workout-planning.md`, "Pro gating").

## The permission strategy — why the pre-prompt is the feature

**A denial of the iOS notification prompt is permanent and unrecoverable in-app.** The user has to
go to Settings, and nothing the app does afterwards can re-raise it. So the app gets exactly one
ask, and where it is spent decides whether the lever works at all.

The shipped placement: **the tour ends → the app opens → one in-app screen offers "remind me to
train" → only a yes triggers the system prompt.**

- **A no costs no permission.** That is the entire point: the in-app screen can be offered again,
  the system prompt cannot. `decliningSpendsNoPermission` pins that a decline leaves the fake
  notification centre's `authorizationRequestCount` at zero and its status at `.notDetermined`.
- **It is not a paywall and must not read like one.** The onboarding tour used to end on a Pro
  offer; ticket 02 retired it precisely because a purchase request before the user has logged a set
  sits in front of the aha path. Reintroducing that *feeling* at the same moment would undo the
  same work, so the decline is a full-width control at the same reading position as the accept, not
  a dimmed word in a corner.
- **It is not inside the tour.** The tour asks for nothing and has no conditional step
  (`docs/onboarding.md`); the offer is a separate cover ordered after it.

### This overrides §4.13's original "ask after the first completed workout"

The strategy document said to ask after the first completed workout, on the reasoning that the app
should earn the request first. **That is wrong for this app's actual problem.** The population this
lever exists for is §1a's 89% who launch once — most of whom never *start* a workout, let alone
finish one. Gating the ask behind a completed workout means the retention notification never reaches
anyone who needs it. The ask has to work for a user who has completed nothing. §4.13 has been
rewritten in place to say what shipped.

### The rest timer's own prompt is untouched

`UserNotificationRestTimerScheduler` requests authorization **lazily, mid-workout**, the first time a
rest timer is scheduled. It was not moved, refactored, or consolidated into this flow — a refactor of
shipped rest-timer code does not belong in a retention ticket, and that request is load-bearing for a
feature that works today.

The interaction is handled from this side only: if the rest timer already obtained permission, the
offer screen recognises it and **is never shown** — reminders simply start working
(`anAlreadyAuthorizedUserIsNotAsked`). The narrow change is that *this* feature never triggers its
own system prompt without the in-app screen first.

### When the offer is raised

`WorkoutReminderOptInViewModel.presentIfDue()` — called from the launch task and on every foreground,
both idempotent, exactly like `FounderCelebrationCoordinator.presentIfDue()`. Five rules, all in the
view model:

| Rule | Why |
| --- | --- |
| System permission is undetermined | Already granted → nothing to ask. Already denied → an in-app screen cannot undo it, and showing one is nagging. |
| At most `maxOffers` = **2** | A decline may be revisited once and then never again. A third ask is the app not taking no for an answer. |
| Not within `reofferCooldownDays` = **14** of a decline | Long enough that the second ask lands in a different frame of mind; short enough to still be inside the window this lever measures. |
| Never inside an active workout | §3 Rule 3 — a full-screen cover is an interruption whether or not it sells anything. |
| Never during the first-run tour | Enforced by ordering, not by a condition — see below. |

**Suppressed is deferred, never consumed.** Nothing is written until the user answers, so an offer
that never reached the screen is still owed (`theOfferWaitsOutAnActiveWorkout`).

A yes records the answer *before* raising the system prompt, so a user killed mid-alert is not
offered it again; the cover stays up until the alert is answered, so the next first-run cover cannot
slide in underneath an alert the user is still reading.

### Presentation never sees the notification framework

The view model holds `WorkoutReminderPermissionRequesting` — a **Domain** protocol with exactly two
methods (`isReminderPermissionUndetermined()`, `requestReminderPermission()`) and no
`UNAuthorizationStatus` in its signature — implemented by `UserNotificationReminderPermission` in
`Data/Notifications/`.

The first draft had the view model hold `WorkoutReminderNotificationCenter` directly. That is a
**Presentation → Data** edge: the protocol lives in `Data/Notifications/` and naming the status
requires `import UserNotifications` in a ViewModel. No other protocol declared under `Data/` is
referenced from `Presentation/`, so it would have been the first such edge in the codebase, and it
was caught by the `architecture-reviewer` pass. The narrow projection keeps `Domain/Interfaces/`
Foundation-only and stops any ViewModel reaching a notification API it has no business calling.

### Cover ordering

`FirstRunCover` gained a fourth case. The order is now:

```
onboarding → founderCelebration → workoutReminders → coachOptIn
```

The offer is raised at launch even while the tour is still up; `FirstRunCoverOrder` puts the tour
first, so the offer simply becomes the topmost cover the moment the tour ends — which is the
placement this lever depends on. It sits **before** the coach opt-in because it is about the core
loop the tour has just described and reaches every device, while the coach is a peripheral feature
only some hardware can run. It sits **after** the Founder thank-you because good news belongs before
an ask, never between two of them. `FirstRunCoverOrderTests` walks all sixteen combinations.

The offer's copy was **rewritten when the nudges shipped.** Slice 1's screen promised "Only on your
planned days — no plan, no notification. Nothing else." The dormancy nudge exists precisely for users
with no plan, so that promise became false; a screen whose yes spends the user's one irreversible
answer must not be dishonest about what follows it. It now reads "Only when it helps — on your
planned days, or after a few days without training. Never right after a workout."

## The frequency cap

`Domain/Services/ReminderFrequencyPolicy.swift` — **the whole cap, in one file**, because this is the
mechanism most able to damage §10's App Store-rating guardrail, and a guardrail nobody can find in
one place is not a guardrail.

| Constant | Value | Meaning |
| --- | --- | --- |
| `maxRemindersPerDay` | 1 | At most one notification on any calendar day, across every reminder kind. |
| `maxRemindersPerRollingWindow` | 3 | At most three in any seven-day window. |
| `rollingWindowDays` | 7 | The window's length. |

Every reminder the app can send passes through `admissibleDays(from:alreadyReminded:calendar:)`.
**A new reminder kind adds a candidate, never a second cap** — the nudges were added exactly that way.

Implementation notes worth keeping:

- **Admission is tiered: planned sessions first, then missed-session nudges, then dormancy.**
  `WorkoutReminderPlanner` calls `admissibleDays` once per kind, passing the higher tiers' admitted
  days in as `alreadyReminded`. A nudge is speculative — it is withdrawn the moment the user trains —
  so it must never displace a reminder about a session the user actually planned. Consequence: a
  Monday/Wednesday/Friday user is already reminded at the limit and never receives a missed-session
  nudge (`nudgesNeverDisplacePlannedReminders`). That is intended: they are being spoken to three
  times a week already.
- **Every window containing a day is checked, not only the one ending at it.** Slice 1 checked
  backward windows only, which is sufficient while candidates arrive strictly earliest-first. Tiered
  admission breaks that: a nudge can be offered a day *earlier* than planned reminders already
  accepted, and only a forward window sees it push one of them past three
  (`capRefusesAnEarlierDayThatOverfillsALaterWindow`). The check is seven windows per candidate —
  trivial at these sizes. `capThinsADailyPlan` asserts over every window rather than over the
  answer's shape.
- **Earliest-first within a tier, not by importance.** The soonest planned session is the one a
  reminder can still change the outcome of, and a later day refused today is often admitted on a
  later pass once the days now in the window have fallen out of it.

The numbers are a starting point, meant to be retuned **downwards** on evidence and never upwards
without it.

## Which days get a reminder

`Domain/Services/WorkoutReminderPlanner.swift` — pure logic over model arrays. It builds the planned
days, asks `ReEngagementNudgePlanner` for the nudge days, gives each day **one** kind (priority:
planned session → missed session → dormancy), drops days whose 08:00 has passed, and admits the
result through the cap in tiers.

- **`reminderHour` = 8, `reminderMinute` = 0**, local time, **for every kind**. Morning, and early
  enough that the reminder is still a decision rather than a report. Shared deliberately: the
  scheduler's ledger decides "already spoken" from this one fire time. Not configurable: a preference nobody finds is
  not worth the surface, and the cap matters far more than the hour.
- **`horizonDays` = 14.** Long enough that a user who does not open the app for a fortnight is still
  reminded; short enough that a stale window cannot outlive the plan by much. It is comfortably
  inside the 64 pending requests iOS keeps per app — the cap allows at most six in this window.

### The two schedule shapes

`RoutineSchedule` has two modes and they are read through `WorkoutPlanningService`, **never around
it** — a second forward walk here is exactly how the reminder and the Verlauf day-strip would come to
disagree about which day is planned.

- **`.weekdays`** (an ISO-weekday bitmask, 1 = Monday … 7 = Sunday): the horizon is walked day by day
  and each day whose ISO weekday is selected becomes a candidate. Same rule
  `WorkoutPlanningService.plannedWeek` uses for weekday plans.
- **`.everyNDays`**: `WorkoutPlanningService.upcomingCadenceDates(…)`, which goes through
  `cadenceAnchor` — the user's `startDate` until a qualifying completion lands on or after it, after
  which the cadence rolls off that completion. **A cadence is not a fixed weekday and is never
  treated as one.** `cadencePlanAgreesWithNextDue` cross-checks the first reminder day against
  `WorkoutPlanningService.nextDue`, which is what the routine card's next-due pill shows.

### What produces no reminder

- A **paused** schedule (`isActive == false`).
- A routine with **no schedule**.
- A `.weekdays` plan with **no weekday selected** — not a plan; `nextDue` answers `nil` for it too.
- A day whose **08:00 has already passed**. It is skipped *and* costs no allowance — otherwise a user
  opening the app in the afternoon would spend the day's cap on a notification that never existed.
- Any day the cap refuses.

**One reminder per day, not per routine and not per kind.** Two routines planned on the same Tuesday
share one notification, and the copy names neither rather than picking a winner
(`twoRoutinesOnOneDayShareOneReminder`). A missed-session nudge that lands on a planned day is
dropped in favour of the planned reminder (`triggersDoNotStackOnOneDay`).

## Re-engagement nudges

`Domain/Services/ReEngagementNudgePlanner.swift` — the two "come back" triggers, as pure functions.

### Why not a streak nudge

The strategy document originally called this slice a "streak-at-risk nudge". **The app has no daily
streak.** The only streak is `HistoryStatsService.streakWeeks` — *consecutive weeks* containing a
finished workout — which has no crisp "about to lapse" moment, and inventing a daily definition would
put a different number in the notification than the Verlauf tab shows. **Do not add a daily streak,
and do not read `streakWeeks` here** — it is the Verlauf tab's read model, not a trigger.

A purely schedule-based trigger has the opposite problem: it reaches nobody in the target
population. It requires a `RoutineSchedule`, and a user who launched once has only the seeded starter
routine, which is unplanned. Hence two triggers: **the schedule drives the nudge when there is one,
and dormancy covers everyone else.**

### Missed planned session

The morning after a planned day `D` (yesterday included, so a session missed yesterday can still earn
this morning's nudge), unless **any** workout was completed on or after `D`. Any routine, not only
the planned one: a user who trained something else that day has not drifted, and a "still waiting"
message right after a workout is exactly the notification this feature must never send.

- The routine is named when `D` carried exactly one planned routine.
- A past planned day **before the schedule's `createdAt`** was never planned: a Monday plan set up on
  a Tuesday has not missed Monday (`aPlanCreatedTodayMissedNothingYesterday`).
- `.everyNDays` planned days come from `WorkoutPlanningService.upcomingCadenceDates` walked from
  yesterday, which stays on the same grid as a walk from today.

### Dormancy

For users with **no active plan** only (`WorkoutReminderPlanner.hasActivePlan`: an active schedule
that is a cadence or has at least one weekday).

| Constant | Value | Meaning |
| --- | --- | --- |
| `dormancyThresholdDays` | 4 | Days without a completed workout before the first nudge. One missed day is not a lapse. |
| `dormancySpacingDays` | 7 | Days between nudges in one lapse — at most one a rolling week. |
| `maxDormancyNudgesPerLapse` | 2 | Then silence until the user trains again. Two unanswered nudges are an answer. |

The lapse is measured from the most recent completed workout of any routine
(`WorkoutSessionRepository.lastCompletedWorkoutStartDate()`, one `LIMIT 1` query — it includes
sessions whose routine was deleted). For a user who has never completed one it is measured from
**`WorkoutReminderTracking.firstSeenAt`**, the install-date stand-in: nothing in the app recorded an
install date, so the scheduler records the moment of its own first pass, before any early return.
For a user updating from a build without it, that is the update day — which errs toward nudging
later, not at once. A lapse whose nudge days are all in the past produces nothing
(`aLongLapseGoesQuiet`): a user who stopped months ago is not sent a stream on their next launch.

**Why scheduled users never get it:** a user on a once-a-week plan is not dormant four days after
training, and the planned reminder and missed-session nudge already speak to them. It also makes the
"a user who misses a planned day and then goes dormant gets one notification, not two" rule
structural.

### Scheduled ahead, withdrawn by training

Both nudges are **speculative**. A user who has stopped opening the app never runs a refresh, so a
nudge scheduled only once the lapse is *observed* would never reach the population it exists for.
Each pass therefore schedules the nudges that would be due if nothing is logged in between, and every
completed workout ends in a refresh (`WorkoutViewModel.currentSession`'s end edge and the routine
refreshes) that re-reads `lastCompletedWorkoutStartDate()` and withdraws them
(`completingAWorkoutClearsTheMissedNudge`, `completingAWorkoutResetsDormancy`).

**Known limit:** a workout logged on the watch withdraws pending nudges only once the phone has
ingested it — `WatchWorkoutIngestionService` posts `.workoutHistoryDidChange`, `RoutinesViewModel`
refreshes on it, and that refresh re-plans the reminders. Until the transfer arrives (the phone app
has not run since), a nudge can still stand. The missed-session copy is written to read acceptably in
that case: it says the session is "still waiting" and that "training today counts just the same",
never that nothing happened.

## "Never during an active workout" — the mechanism, and why it is this one

`monetization-strategy.md` §3 Rule 3 forbids anything reaching the user inside a workout, and
`docs/rating-prompt.md` obeys the same rule. A notification is harder than a paywall: **once a
request has been handed to the system, the app cannot suppress its delivery.**

- A `UNUserNotificationCenterDelegate` was **considered and rejected.** `willPresent` is only called
  in the foreground, so it cannot cover a workout the user has backgrounded — and adding a delegate
  at all would change the *rest timer's* shipped foreground behaviour, which today relies on there
  being no delegate.
- The shipped mechanism is **withdrawal**: `WorkoutViewModel.currentSession`'s `didSet` — the single
  place that already keeps `ActiveWorkoutReporting` in step — triggers a refresh on both edges. A
  refresh taken while a workout is running cancels every pending reminder and schedules nothing; the
  refresh at the end of the workout puts back whatever is still due
  (`schedulerWithdrawsRemindersDuringAWorkout`).

A morning reminder the workout swallowed is simply gone by the time the session ends, because its
08:00 is in the past — which is the correct outcome: the user trained.

The other two prohibitions are structural. **Never on the watch:** the watch target is untouched and
watchOS has no access to schedules at all. **Never adjacent to a paywall:** nothing in this feature
raises one, and the offer screen is not routed through the paywall seam.

## Architecture

Dependency direction is the project's usual `Presentation → Domain ← Data`, wired in
`App/AppDependencies.swift`.

### New files

```
GymStreak/Domain/Interfaces/WorkoutReminderScheduling.swift        one method: refreshReminders()
GymStreak/Domain/Interfaces/WorkoutReminderTracking.swift          the offer's record + the cap's ledger
GymStreak/Domain/Interfaces/WorkoutReminderPermissionRequesting.swift  the permission, as Presentation may see it
GymStreak/Domain/Services/ReminderFrequencyPolicy.swift            the cap, in one file
GymStreak/Domain/Services/WorkoutReminderPlanner.swift             which mornings, which kind, admitted in tiers
GymStreak/Domain/Services/ReEngagementNudgePlanner.swift           missed-session and dormancy days
GymStreak/Data/Notifications/WorkoutReminderNotificationCenter.swift   protocol + UNUserNotificationCenter conformance
GymStreak/Data/Notifications/UserNotificationReminderPermission.swift  the permission gateway
GymStreak/Data/Notifications/UserNotificationWorkoutReminderScheduler.swift
GymStreak/Data/Preferences/WorkoutReminderStore.swift              UserDefaults conformer
GymStreak/Presentation/ViewModels/Reminders/WorkoutReminderOptInViewModel.swift
GymStreak/Presentation/Views/Reminders/WorkoutReminderOptInView.swift
GymStreakTests/WorkoutReminderTests.swift
GymStreakTests/ReEngagementNudgeTests.swift
GymStreakTests/ReEngagementNudgeSchedulerTests.swift
GymStreakTests/Support/FakeWorkoutReminderNotificationCenter.swift
GymStreakTests/Support/WorkoutReminderFixtures.swift
docs/workout-reminders.md
```

### Changed files

`WorkoutSessionRepository` + `SwiftDataWorkoutSessionRepository` (`lastCompletedWorkoutStartDate()`,
slice 2; the test double in `WatchWorkoutIngestionCoordinatorTests` forwards it), `FirstRunCoverOrder` (fourth cover), `ContentView` (hosts the new cover), `GymStreakApp` (launch and
foreground triggers), `AppDependencies` (wiring), `RoutinesViewModel` (refresh hook beside
`reconcileCalendar()`), `WorkoutViewModel` (withdrawal on both workout edges), `en`/`de`
`Localizable.strings`, `FirstRunCoverOrderTests`.

### The notification-centre seam

`WorkoutReminderNotificationCenter` is a **sibling** of `RestTimerNotificationCenter` in the same
folder, with the same shape — deliberately **not** a generalisation of it. Two small protocols over
one system type cost a few lines of duplication; folding them into one would mean editing shipped
rest-timer code to serve a retention feature. The method names are distinct (`addWorkoutReminder…`
vs `addRestTimer…`) for the reason the rest timer's already are: `UNUserNotificationCenter` conforms
to both, and a shared name would have one conformance satisfy the other by accident.

Authorization options are `[.alert, .sound]`, matching the rest timer exactly — no badge, because
nothing in the app renders one.

### The scheduler

`UserNotificationWorkoutReminderScheduler` is shaped like `PlannedWorkoutCalendarMirror`, and for the
same reason: several unrelated surfaces need the identical three steps — read the plans, ask a pure
Domain type what the outside world should hold, hand the answer to a gateway — and none should own
that glue.

```
record firstSeenAt if absent              ← the dormancy anchor, before every early return
cancel this feature's pending requests   ← unconditional, before every early return
guard !activeWorkout.isWorkoutActive     ← Rule 3
guard status == .authorized              ← read, never requested
read routines + lastCompletedStartDates  ← the same bounded per-routine lookup the mirror uses
  + lastCompletedWorkoutStartDate + firstSeenAt   ← what ends a lapse / clears a missed day
plan → schedule → record the ledger
```

**Every pass rebuilds the whole window** rather than editing it, so nothing can drift, and the
operation is idempotent (`schedulerRefreshIsIdempotent`). Cancellation happens *first and
unconditionally* because every early return below it is a state in which the app must be silent — a
return taken before the cancellation would leave yesterday's plan firing.

**The passes are serialized, and the reason is the cap.** Six triggers fire this method, each in its
own `Task`, and a pass suspends three times (the pending-requests read, the status read, every
`add`). Two overlapping passes would have the second's unconditional cancellation land *after* the
first had already added requests, and both would then write a ledger describing neither — which is
exactly how the §10 rating guardrail gets exceeded by one. `refreshReminders()` therefore holds an
`isRefreshing` flag: a caller arriving mid-pass books one more pass and returns rather than waiting
(it is a trigger, not a client of the result, and the pass it books re-reads the store). No trigger
is dropped, no two passes overlap, and a burst costs at most one extra pass.
`concurrentRefreshesAreSerialized` pins it.

Request identifiers are `workoutReminder.<kind>.<yyyy-MM-dd>` — `planned`, `missed` or `dormancy` —
and the planner gives every day at most one kind, so a day can never carry two requests. The day is rendered from `Calendar` components rather than a `DateFormatter`, for the
reason `PlannedWorkoutMarker` gives: a hoisted formatter caches its time zone and would silently
shift the identifier by a day for a user who travels. The trigger is a `UNCalendarNotificationTrigger`
on full date components, not a time interval, so the fire time is a wall-clock morning across time
zones and DST transitions.

A request the system refuses is logged and **not** recorded in the ledger, so a failure does not
spend the day's allowance (`schedulerDoesNotRecordAFailedRequest`).

### The ledger, and what "already reminded" means

The rolling-seven-day cap has to survive app launches, so `WorkoutReminderTracking.remindedDays` is
durable. On each refresh the scheduler keeps the ledger's **past** days (pruned to one window back)
and replaces the future with what this pass actually scheduled — the future is about to be re-planned,
and counting it would have each pass refuse the schedule it just made.

**A scheduled day whose fire time has passed is treated as delivered.** The app cannot know whether a
notification was seen (`deliveredNotifications()` is unreliable — the user can clear Notification
Centre), and for a cap whose purpose is to bound how often the app *speaks*, having spoken is the
fact that matters.

**The split is on the fire moment, not on the day** — an easy thing to get subtly wrong. A reminder
that went out at 08:00 this morning has been spoken and still constrains the rest of its rolling
window; splitting on the calendar day would drop it from the ledger the moment the user opened the
app that afternoon, and a fourth notification could then land inside seven days. The test is exactly
complementary to the planner's own "is this morning still ahead of us" filter, so no day is counted
twice and none is missed. `schedulerCountsAlreadyFiredRemindersAgainstTheCap` pins it.

One store (`WorkoutReminderStore`) conforms to the one protocol carrying both halves — the offer's
record and the ledger. They are one feature's durable state written by the same two collaborators;
splitting them would double the composition-root wiring without making either half safer. Plain
`UserDefaults.standard`, never iCloud KVS and never the App Group suite, for the reasons
`OnboardingCompletionTracking` sets out: notification authorization is a **per-device** fact, so a
mirrored record would suppress the offer on a device that has never asked.

### The trigger sites

| Trigger | Where | Why |
| --- | --- | --- |
| Launch | `GymStreakApp` `.task` | The window is dated; a day rolls over whether or not anything changed. |
| Foreground | `GymStreakApp` `.onChange(of: scenePhase)` | Same, plus the next chance for a suppressed offer or an elapsed cooldown. |
| Any plan or history change | `RoutinesViewModel.refreshReminders()`, beside `reconcileCalendar()` | Every path that can move a planned day — a workout finished here or on the watch, a completion synced from another device, a plan edited or cleared, a routine deleted — already ends in one of the two routine refreshes. Hooking there rather than once per trigger is the same trade the calendar mirror already makes. |
| Workout start / end | `WorkoutViewModel.currentSession` `didSet` | The withdrawal mechanism above. |
| Permission granted | `WorkoutReminderOptInViewModel.accept()` | So a yes makes reminders work in the same turn, not on the next launch. |

The launch task **and** the foreground trigger are both guarded by `isUITesting`. The foreground one
is not optional: a UI-test run has an empty store and an undetermined permission status, so the offer
would claim the screen on the first activation and take the fastlane screenshot lane with it — the
same failure mode already recorded for the AI Coach opt-in cover.

All of them are `Task`-deferred: a refresh awaits the notification centre and belongs off the
routines list's critical path (main-thread rules 3 and 7).

## Copy

Notifications: `notification.planned_session.*`, `notification.missed_session.*` (both with a
`.body_routine` variant taking the routine name) and `notification.dormancy.*`. Offer screen: the
`reminders.optin.*` family. All present in **en** and **de**.

| Kind | en | de |
| --- | --- | --- |
| Planned | *Training day* — "Upper Body is planned for today. Ready when you are." | *Trainingstag* — "Upper Body steht heute an. Wann immer du bereit bist." |
| Missed | *Today works too* — "Upper Body is still waiting for you. Training today counts just the same." | *Heute passt auch* — "Upper Body wartet noch auf dich. Heute zu trainieren zählt genauso." |
| Dormancy | *Up for a session?* — "A short workout counts too. Pick a routine whenever it suits you." | *Lust auf eine Einheit?* — "Auch ein kurzes Training zählt. Such dir eine Routine aus, wann es dir passt." |

The nudges arrive to someone who has already drifted, which makes them the single most likely thing
in this feature to earn a one-star review or a revocation. They were reviewed as copy against three
rules: **never name the lapse** (no "you missed", no day counts, no streak numbers), **lower the bar
rather than raise the stakes** ("training today counts just the same", "a short workout counts too"), and
**leave the decision with the user** ("whenever it suits you"). The missed-session copy also has to
read acceptably when it is wrong — a watch-only workout the phone has not seen yet — which is why it
says "still waiting" rather than anything about what did not happen.

All copy is deliberately unpressured and never guilt-based. This notification's failure mode is a one-star review or a permanent revocation,
both of which outrank the lever (§10). The offer screen states the cap as a *benefit* ("One a day at
most", "never more than three in a week — that limit is built in, not a setting"), because the honest
answer to "will this app spam me" is the thing that earns the yes.

## Deliberate omissions

- **No in-app settings toggle.** The system Settings screen already owns this switch, and a second
  one would let the app's state disagree with the system's. If a toggle is ever wanted, it belongs in
  `SettingsRootView` reading the same `WorkoutReminderNotificationCenter` status.
- **No configurable reminder hour.** See `reminderHour` above.
- **No `UNUserNotificationCenterDelegate`.** See "Never during an active workout".
- **No daily streak, and no streak nudge.** See "Why not a streak nudge" above.
- **No dormancy nudge for scheduled users.** See "Dormancy" above. If ever wanted, it would need a
  threshold relative to the plan's own rhythm, not a fixed four days.
- **No missed-session nudges beyond the cap.** Users whose planned reminders fill the week get none,
  by the tiered admission. Retune the cap downwards, never the tiers, if nudges feel like too much.

## One other feature borrows this plumbing

The post-workout conditioning add-on's "Remind me later"
(`ConditioningReminderScheduling`, `docs/fight-conditioning.md` ticket 05) uses the
`WorkoutReminderNotificationCenter` seam, the `WorkoutReminderPermissionRequesting` projection and
`reminderHour` — but is **not** a fourth reminder kind. It is a single user-requested one-shot for a
moment that exists nowhere in the user's plans, so `WorkoutReminderPlanner` would drop it on its next
rebuild, and it sits outside `ReminderFrequencyPolicy` for the reason the rest timer does: that cap
bounds what the app says **unprompted**. Its own cap is one identifier, so at most one can be pending.
The two never collide because `cancelPendingReminders()` filters on the `workoutReminder.` prefix,
which the conditioning identifier deliberately lacks — **keep that filter** if either identifier
scheme is ever changed.

It is also the **second** place allowed to raise the system permission prompt (the ticket-01
conditioning cues were the first). Both ask lazily, at a point of use the user chose; the rule this
document sets — that no *scheduling pass* may ever ask — is unchanged.

## Verification

`GymStreakTests/WorkoutReminderTests.swift` — 25 tests over the cap, the planner, the scheduler and
the permission seam. `GymStreakTests/ReEngagementNudgeTests.swift` and `ReEngagementNudgeSchedulerTests.swift` — 12 tests over the two nudges:
one nudge for a missed Tuesday, none after training that day, dormancy thresholds and spacing,
silence for recent activity and for scheduled users, one kind per day, tiered admission, the
forward-window cap check, and withdrawal by a completed workout through the real scheduler. The
notification centre is faked throughout, so no system prompt is ever raised; the harness, routines
and dates are shared from `GymStreakTests/Support/WorkoutReminderFixtures.swift`.

**On device:** slice 1 (planned reminder + permission seam) was manually tested and confirmed working
on 2026-09-16; slice 2 (both nudges) was confirmed finished and tested on 2026-09-17.

The `authorizationRequestCount == 0` assertions are the ones that carry the ticket: they are what
proves a decline, a suppressed offer, and every scheduling pass spend none of the user's one
irreversible answer.
