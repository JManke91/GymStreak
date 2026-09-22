# Fight Conditioning (add-on)

**Status (2026-09-21): tickets 01–02 shipped and device-verified — the iPhone runner (library,
preview, runner, Apple Health write) and History logging (own SwiftData record, interleaved cards,
detail, delete). Ticket 03 (personal heart-rate zones, incl. the Apple Health peak-HR suggestion) shipped and
device-verified the same day. Ticket 04 (the 12-week program — showcase, enrollment, weekly targets,
today's suggestion) shipped and was device-verified 2026-09-20. Ticket 05 (the post-workout add-on on
the iPhone workout summary) shipped and was device-verified 2026-09-21 — its `.later` branch is not
reachable before program week 5 and remains unit-tested only (see that section). Ticket 06 (the watch runner with the live heart-rate zone) shipped and was device-verified 2026-09-22; its runner was then redesigned (heart-rate gauge, swipe-away controls — see "Watch runner redesign").**
Watch → iPhone history sync (07) and the Pro gate (08) are later tickets. This file holds
the pre-implementation research (so it is not re-done) and the feature doc (iOS + watch
architecture, components, edge cases) as tickets land. Parent Things task: "Add fighting conditioning into workout routine"
(`TFUtiRbLsX4VScjcnbdZbv`, Gym Streak project).

## What it is

A periodized conditioning add-on for fighters who lift: the user keeps their strength routines and
the app guides the energy-system conditioning around them — interval sessions with work/rest
countdowns, steady-state aerobic sessions with a duration and a live heart-rate target zone.
Skill training (MMA, BJJ, Muay Thai) is explicitly out of scope; only the conditioning is modeled.

## Plan (approved 2026-09-18)

Tickets: `.scratch/fight-conditioning/issues/01–08` — iPhone runner → History logging → HR zones →
12-week program → post-workout add-on → watch runner with live HR zone → watch→iPhone sync → Pro gate.
Tier: Phase 1 and all in-session/watch/history surfaces free; program Phases 2–3 Pro (depth gate +
blurred preview, `PaywallPlacement.conditioningProgram`).

**Deliberately not planned (for now):** live HR on iPhone via AirPods Pro 3 / Bluetooth strap
(needs an iOS 26 `HKWorkoutSession` on iPhone — the watch covers HR); a Live Activity for the
interval timer; AI Coach integration; skill training (MMA/BJJ/Muay Thai) sessions.

## iOS architecture (ticket 01 — the iPhone runner)

**What the user gets.** Routines tab header → the boxing-figure button opens the Conditioning
library (full screen). Five sessions of the corrected protocol, grouped Aerobic / Lactic /
Alactic: *Aerobic base* (30/45/60 min steady, RPE 3–4), *Aerobic + bursts* (4–6 × 8 s at RPE 8,
90 s rest), *Lactic 30/120* (6–8 rounds), *Lactic 45/180* (4–6 rounds), *Alactic power* (2–3 sets ×
5 × 8 s, 90 s rest, 4 min set break, 15 min warm-up). A session opens a preview: modality chips,
a volume segment (the lowest option is the default — beginners start low), the 85–90 %
*beginner variant* toggle (alactic only), and the structure with its total time. *Start session*
opens the runner. The heart-rate button in the library toolbar re-opens the safety screen
read-only.

**The runner** shows the phase (WARM-UP / WORK / REST / SET BREAK / COOL-DOWN / STEADY; effort
phases on a tint capsule with `textOnTint`), a large countdown of the current phase, the
round/set position, the effort cue, "Next: …", a session progress bar and elapsed time. Steady
state additionally shows "elapsed of total". Pause / Resume / End (with a confirmation that says
whether anything will be saved). The screen stays awake (`isIdleTimerDisabled`) while the runner
is up. On finish: "Session complete" / "Session ended", elapsed time and the Health save outcome.

**Timing never counts down.** `ConditioningClock` (Domain) holds the start date and paused
intervals; `ConditioningTimeline` (Domain) expands a plan into phases with start offsets and maps
an elapsed time to a `ConditioningPosition`. The view model re-derives everything from
`clock.elapsed(at: now)` every 200 ms, so a locked or backgrounded phone resumes at the right
place. On returning to the foreground (`scenePhase == .active`) it calls `resynchronize()`, which
jumps to the current phase **without** replaying the cues that happened meanwhile (their
notifications already fired). If the session ended while the app was suspended, the Health
workout still ends at the timeline's end, not at wake-up.

Expansion rules (unit-tested in `ConditioningTimelineTests`): warm-up → work/rest pairs with no
trailing rest after the last work → cool-down; set-based sessions replace the last rest of each
set with a set break and have none after the last set; steady state is one `.steady` block of the
chosen minutes; the sub-maximal option only changes the work effort of sessions that support it.

**Cues.** In the foreground: a system sound + haptic at every transition (effort start vs.
recovery start differ) and a 3-2-1 lead-in tick before every effort phase that follows another
phase. For the background: when the session starts or resumes, one local notification per
upcoming phase start plus a "Session complete" one (title = phase, body = position + effort),
cancelled on pause, end and finish. The app installs no `UNUserNotificationCenterDelegate`, so a
notification firing while the app is in the foreground is not presented — no double cue.
Capped at 48 pending requests (iOS allows 64 per app, shared with the rest timer and reminders;
the longest session has ~35 transitions). Notification permission is asked on the first start;
when denied, the runner shows "cues only play while the screen is on" and keeps running. Stale
`conditioning.cue.*` requests from a killed process are swept on the next schedule — until then
they can still fire (accepted edge).

**Apple Health.** A separate `HKWorkout`, written after the fact through the same builder path as
strength (`HealthKitWorkoutManager.writeWorkout(configuration:…)`, extracted from
`saveWorkoutDirectly`). Configuration per modality (`HealthKitWorkoutManager+Conditioning.swift`):
run `.running` / outdoor, assault bike `.cycling` / indoor, rower `.rowing` / indoor, swim
`.swimming` with `swimmingLocationType = .unknown` and no lap length, sled/ropes/med ball
`.highIntensityIntervalTraining` / indoor. Metadata: brand name = session title (the same choice as the strength path, which stores
the routine name there — it is what Fitness shows as the workout's title),
`HKMetadataKeyExternalUUID`, and `GymStreakSessionKind = "conditioning"`. No energy sample — the
phone has no sensor and the strength path's flat 4.5 kcal/min estimate is meaningless for
sprints. The workout's duration is wall clock start → end, pauses included. Rules: honors the
strength path's `healthKitSyncEnabled` switch (read through `HealthSyncPreferenceReading`); ending
before the first effort phase has begun saves nothing (steady state begins immediately); Health
authorization is primed at session start. The external UUID is not stored anywhere yet — History
logging (ticket 02) will keep it.

**Recovery-ledger guard.** `HealthKitAnchoredWorkoutDrain.facts(from:)` admits every
GymStreak-authored workout carrying an external UUID into the watch-workout recovery ledger
(`docs/healthkit-ios-workout-save.md`). A conditioning workout has no strength-history
counterpart, so without a guard it would be offered in the pending-sync banner as a "missing"
workout and imported as a placeholder strength session. The drain therefore skips workouts whose
`GymStreakSessionKind` is `conditioning`. Ticket 07 (watch → iPhone sync) must revisit this if it
wants conditioning recovery.

**First-use safety screen.** Shown inside the runner cover the first time a session is started
(`ConditioningSafetyStore`, device-local `UserDefaults` flag `conditioning.safetyAcknowledged`,
same reasoning as `OnboardingCompletionStore`); the session only starts after *I understand*.
Content: physician/ACSM disclaimer, stop symptoms, beginner sprint caution + 85–90 % variant,
warm-up and bike/rower for maximal efforts, RPE (HR estimates, beta-blockers), no hard work during
a weight cut or dehydrated.

**Components.**

| Layer | File | Role |
|---|---|---|
| Domain/Models | `Conditioning/ConditioningSession.swift` | energy system, modality, effort, phase kind, volume, definition, options, plan, phase |
| Domain/Services | `ConditioningLibrary.swift` | the five sessions (corrected protocol) |
| Domain/Models | `Conditioning/ConditioningPhase.swift` | phase, phase kind, effort — split out in ticket 06, identical copy on the watch |
| Domain/Services | `ConditioningTimeline.swift`, `ConditioningTimeline+Expansion.swift` | position lookup and `ConditioningClock` (identical copy on the watch since ticket 06); phase expansion (iOS only) |
| Domain/Interfaces | `ConditioningCueDelivering.swift`, `ConditioningWorkoutSaving.swift` (+ `HealthSyncPreferenceReading`), `ConditioningSafetyAcknowledging.swift` | gateways |
| Data | `HealthKit/HealthKitWorkoutManager+Conditioning.swift`, `Notifications/ConditioningCueDeliverer.swift`, `Preferences/ConditioningSafetyStore.swift`, `Preferences/UserDefaultsHealthSyncPreference.swift` | implementations |
| Presentation | `ViewModels/Conditioning/ConditioningRunViewModel.swift` (`@Observable`), `ConditioningLibraryViewModel.swift`, `ConditioningCopy.swift` (localized vocabulary) | state + copy |
| Presentation | `Views/Conditioning/ConditioningLibraryView`, `ConditioningPreviewView`, `ConditioningRunnerView`, `ConditioningSafetyView` | screens |
| Domain/Models | `Conditioning/ConditioningRecord.swift` (`@Model`), `ConditioningCardModel` in `HistorySnapshot.swift` | ticket 02 — the history row and its display struct |
| Domain/Repositories · Data | `ConditioningRecordRepository.swift` · `SwiftDataConditioningRecordRepository.swift` | ticket 02 — persistence |
| Presentation | `ViewModels/Conditioning/ConditioningHistoryViewModel.swift`, `Views/Conditioning/ConditioningHistoryCardView.swift`, `ConditioningRecordDetailView.swift` (+ `ConditioningRecordDestination`), `Views/History/Components/HistoryDateBlock.swift` | ticket 02 — History surfaces |
| App | `AppDependencies`: `conditioningCues`, `conditioningSafety`, `conditioningRecordRepository`, `makeConditioningRunViewModel(plan:)`, `conditioningHistory` (lazy) | wiring |

Strings: `conditioning.*` in `Resources/{en,de}.lproj/Localizable.strings`.

**Tests.** `ConditioningTimelineTests` (intervals, sets with set breaks, steady state, sub-maximal,
position lookup, first-effort rule, library completeness, pause-aware clock) and
`ConditioningRunViewModelTests` (one save with the plan's modality and the timeline's end date,
nothing saved when ended in the warm-up or with Health sync off, pause/resume rescheduling,
resynchronize without cue replay, 3-2-1 lead-in). The drain filter is not unit-tested:
`HKWorkout.sourceRevision` cannot be faked.

**Monetization.** Free — Rule 3 (in-session). No Pro badge anywhere in the runner.

**Watch target.** Unchanged by ticket 01; the watch runner with live HR is ticket 06 (below).

**Device verification — PASSED (physical iPhone, 2026-09-19).** Lock-screen notifications fire at
each transition and the countdown is correct on unlock without replayed cues; the 3-2-1 lead-in
plays; pause freezes the countdown; a finished session appears in Apple Health with the modality's
activity type and the session title; ending during the warm-up saves nothing; the conditioning
workout does not appear in the recovery banner.

## iOS architecture (ticket 02 — History logging)

**What the user gets.** A finished session is recorded in GymStreak, not only in Apple Health. It
appears in the History tab's Trainings list as its own card, interleaved with the workout cards by
date: the date tile, the session title, an energy-system chip, the elapsed time, `4/6 rounds` (only
for interval sessions), an "Ended early" marker when it applies, and the modality glyph where a
workout card carries its completion ring. Tapping it pushes a detail screen (date and time, total
time, modality, energy system, rounds completed of planned, the work/rest interval, sets, the
effort target, and a line saying it is also in Apple Health). Long-press on the card, or the trash
button on the detail screen, opens the **same** delete confirmation the strength path uses
(`docs/delete-workout.md`) — "GymStreak only" vs. "GymStreak and Apple Health" when a Health
counterpart exists, one destructive button when it does not.

**`ConditioningRecord` is its own `@Model`, not a `WorkoutSession` with zero exercises.** History
cards, Fortschritt, the muscle map and `PersonalRecordService` all walk `workoutExercises → sets`,
and every one of them would have had to special-case an empty session. A separate row also carries
what conditioning actually has — rounds, work/rest intervals, effort — instead of empty strength
fields. It is denormalized like `WorkoutSession`: it copies the session's numbers rather than
pointing at a `ConditioningSessionDefinition`, so retuning or removing a session in
`ConditioningLibrary` never rewrites what the user did. `titleSnapshot` is the one value read only
as a fallback — while `sessionTypeRaw` still names a session in the library the title is
re-localized, so History follows the user's language rather than freezing the language they
trained in.

**The record id *is* the Apple Health external UUID.** `writeWorkout` gained an optional
`externalUUID:`, and `ConditioningWorkoutSaving.saveConditioningWorkout` now takes the id instead of
returning one. The record is written **first** and never depends on the Health write: with Health
sync off, Health unavailable, or a failed write, the session is still in History — only
`healthKitWorkoutId` stays `nil`, which is exactly what the delete confirmation reads to decide
whether to offer the Health option. Same threshold as ticket 01: ending before the first work
interval records nothing anywhere. `ConditioningRunnerView.onDisappear` calls `end()`, which is a
no-op once the state is `.finished`, so a completed session cannot produce a second row.

**The History merge.** `HistoryListRow` gained `.conditioning(ConditioningCardModel)`;
`HistorySnapshotBuilder.build` takes `conditioningRecords:` and, after its single session pass, runs
a second, far smaller pass (the records are flat — no relationship to fault) that buckets cards by
month. Month sections are now the **union** of both kinds, sorted explicitly, because a month can
reach the list through conditioning alone; without that its rows would appear under the previous
month's divider. Within a month the two are combined by a linear merge on `startTime` (both inputs
are already newest-first), with a same-second tie resolved in the workout's favour so `ForEach`
identity stays deterministic. Row ids are prefixed `conditioning-` so they cannot collide with
`card-`.

**Deliberately strength-only.** `weekStats`, `weekDays` (the week hero and its goal), `cardsByDay`
and `typesByMonth` ignore conditioning, and so does `HistorySnapshot.sessionCount`, which gates the
AI Coach recap cards — those analyse lifting. `MonthSectionModel` therefore carries a separate
`conditioningCount`: the list divider names both ("3 Workouts · 12.4 t · 2 conditioning", assembled
from the clauses that apply so a conditioning-only month never reads "0 Workouts · 0 kg"), while the
calendar's month header keeps summarising exactly what its day cells show. `conditioningCount` was
added to the snapshot too, so the loading spinner does not flash over a conditioning-only list.

**Calendar mode is a deliberate omission.** `cardsByDay` is `[Date: WorkoutCardModel]`; holding both
kinds would mean an enum threaded through `HistoryCalendarView`'s day cells, dots, legend and
selected-day detail. A conditioning-only day therefore shows no dot in calendar mode. To restore it:
widen `cardsByDay` to an enum (or a parallel `conditioningByDay`), teach the day cell a conditioning
dot colour, and render the conditioning card in the selected-day section.

**Delete.** `ConditioningHistoryViewModel` (`@Observable @MainActor`) owns record lookup and delete,
deliberately separate from the 2,000-line `WorkoutViewModel`: conditioning shares none of its state.
It takes `HistoryStoreGate.withExclusiveAccess` around the delete + save, because
`fetchTrainingSnapshot` now fetches `ConditioningRecord` on the model actor too and a delete landing
mid-walk is the same uncatchable trap (`docs/history-delete-race.md`). It then posts
`.historySourceDataDidChange`, which `WorkoutViewModel` translates into the `historyVersion` token
the Trainings `.task(id:)` is keyed on — no new refresh mechanism. Apple Health deletion reuses
`HealthKitWorkoutServicing.deleteWorkout(externalUUID:)` unchanged (the predicate is type-agnostic
across `HKObjectType.workoutType()`), and a failure raises the same non-blocking
`HealthKitDeleteFailure` banner; `HistoryView` shows one banner for whichever path set it.

**Navigation.** `HistoryView`'s stack already claims `UUID.self` for workout sessions, so a
conditioning row pushes `ConditioningRecordDestination(id:)` — a conditioning id sent as a bare
`UUID` would resolve to "no such workout" and render nothing.

**Rendering.** `ConditioningHistoryCardView` takes a `ConditioningCardModel`, never the `@Model`
(Performance rule 4), and is `Equatable` so SwiftUI can skip unchanged rows. The day/month tile was
extracted from `WorkoutCardView` into `HistoryDateBlock` so both card kinds share it — including its
hoisted `static` `DateFormatter`s, which are the dominant per-card cost the History work measured.

**CloudKit.** `ConditioningRecord` is registered in `GymStreakSchema.modelTypes`
(`SchemaRegistrationTests` fails otherwise) and every stored property is optional or has a default,
because the app has no migration plan. **Its record type must be deployed to the CloudKit
Production environment before this ships** — run once with `-INITIALIZE_CLOUDKIT_SCHEMA` in Debug
while signed into iCloud, deploy in the CloudKit Console, then verify with
`xcrun cktool export-schema`. Production has no just-in-time schema creation; without the deploy
every device on the release stores conditioning history locally only. See
`docs/cloudkit-schema-automation.md`.

**Tests (ticket 02).** `SwiftDataConditioningRecordRepositoryTests` (newest-first ordering, the full
denormalized round trip through the app schema, unknown-id lookup, delete, steady state);
`HistorySnapshotBuilderTests` (interleaving by date within a month, a conditioning-only month
getting its divider, no leak into the strength aggregates, caller-independent sorting, the card
carrying recorded values including the unknown-session-type fallback);
`SwiftDataHistorySnapshotStoreTests.conditioningRecordsReachTheTrainingSnapshot` (through the model
actor); `ConditioningTimelineTests` (completed vs. started work intervals, sets, steady state);
`ConditioningRunViewModelTests` (one record with the Health external UUID, nothing before the first
effort, rounds actually finished when ended early, a record even with Health sync off, a record
surviving a failed Health write, no double record from `onDisappear`, steady state, the sub-maximal
beginner variant).

**Monetization (ticket 02).** Free — §3 Rule 4: it reads and retains the user's own logged data.
Also Rule 1 (the aha path: train it → see it logged). No cap, no placement, no badge.

**CloudKit — deployed (2026-09-19).** The Development schema was diffed against Production in the
CloudKit Console before deploying. The diff was **purely additive**: one new `CD_ConditioningRecord`
record type with exactly the model's 15 stored properties (plus the framework's `CD_entityName`,
`CD_moveReceipt` and `___` fields, and the `_ckAsset` overflow field each `String` gets), and not a
single change to any existing record type. Deployed to Production the same day. Note for later
tickets: a Production deploy cannot be undone — record types and fields can never be removed and
these names are now frozen. Adding fields stays safe, so if ticket 03 (personal HR zones) or 06/07
(the watch runner) want average HR or time-in-zone on this record, that is another additive deploy,
not a problem.

**Device verification — PASSED (physical iPhone, 2026-09-19).** All nine manual steps behaved as
specified: ending during the warm-up records nothing in History (and nothing in Health); ending
after the first work interval produces one card showing the elapsed time, the rounds actually
completed and the "Ended early" marker; the card sits in date order among the strength workouts; the
detail screen shows modality, energy system, rounds, the work/rest interval and the effort; the
delete alert offers both "GymStreak only" and "GymStreak and Apple Health" when a Health counterpart
exists, and deleting with the Health option removes it from both; and with Health sync **off** the
session is still recorded in History, with a delete alert offering the single button — which is the
property that matters most here, because it is what makes GymStreak rather than Apple Health the
source of truth for conditioning history.

## iOS architecture (ticket 03 — personal heart-rate zones)

**What the user gets.** A small heart-rate profile: maximum heart rate either *estimated from age*
(HRmax = 208 − 0.7 × age, Tanaka) or *measured*, an optional resting heart rate, and an "I take
medication that affects my heart rate" switch. The editor is reachable from **Settings →
Conditioning → Heart-rate zones** and, as a sheet, from the heart-rate card of a session preview. It
shows the resulting aerobic zone live, states that the age estimate is only ± 10 bpm, explains the
Karvonen switch and the medication switch, and offers **Fill from Apple Health** (age from date of
birth, latest resting heart rate). Save is disabled while the input is invalid; the zone card lists
what is wrong.

**Where targets appear.** Only the *conversational* aerobic effort (Aerobic base, the steady
session) gets a heart-rate target:

| Preview card (`ConditioningHeartRateGuidance`) | When |
|---|---|
| `target` — "Aerobic: 112–140 bpm (60–75 % of max)" + estimate or measured note + Edit | aerobic base with a valid profile |
| `needsSetup` — "Get a personal heart-rate target" + Set up | aerobic base, no or incomplete profile |
| `rpeOnly` — "RPE only" + Edit | medication switch on |
| `maximalIntent` — "No heart-rate target … go by maximal intent" | every alactic session, whatever the profile |
| `none` — no card | lactic and aerobic-burst intervals (heart rate lags a 30 s effort too much to steer by; RPE stays the cue) |

The runner shows the range with a heart glyph and its basis under the effort cue during the steady
phase only (`ConditioningRunViewModel.heartRateTarget(for:)`, which delegates to
`HeartRateZones.target(for:profile:)`). The profile is snapshotted when the runner is created, so
editing it mid-session changes nothing until the next session. The RPE cue is always shown
alongside — heart rate never replaces it.

**The math (`Domain/Services/HeartRateZones.swift`, pure, unit-tested).** Without resting HR:
60–75 % of HRmax. With resting HR: 50–70 % of heart-rate reserve, `resting + p × (max − resting)`
(Karvonen). Rounded to whole bpm. Plausibility: age 13–100, measured max 120–230 bpm, resting
30–120 bpm, and reserve (max − resting) ≥ 40 bpm. Only the *active* max source is validated — the
inactive value is kept in the profile so switching back never loses it. With the medication switch
on nothing is required and no target is ever produced.

**Persistence.** `HeartRateProfileStore` (`Data/Preferences`, `@Observable @MainActor`) writes the
profile as JSON under `conditioning.heartRateProfile` in `UserDefaults.standard` — the same store and
reach as the user's other settings (weight unit, calendar sync, reminders): it survives relaunches,
not a reinstall, and does not travel between devices. One instance lives in `AppDependencies`, so
an open preview observes a save from the sheet immediately. Deliberately not iCloud KVS: no other
setting syncs that way, and the watch gets the computed range over WatchConnectivity (ticket 06): the
store's `onChange` refreshes the program view model, which republishes the watch offer.

**Apple Health pre-fill.** `HealthKitHeartRateProfileReader` (`Data/HealthKit`, behind the Domain
protocol `HeartRateProfileHealthReading`) requests **read-only** access to
`HKCharacteristicType(.dateOfBirth)` and `HKQuantityType(.restingHeartRate)` only when the user taps
the pre-fill row — never at launch, never with the workout authorization. Age comes from
`dateOfBirthComponents()`; resting HR from an `HKSampleQueryDescriptor` for the single newest sample
(`SortDescriptor(\.endDate, order: .reverse)`, `limit: 1`) in count/min; read access to
`HKQuantityType(.heartRate)` is requested in the same call for the peak suggestion below. A denied read and missing
data are indistinguishable in HealthKit, so both leave the field empty and the footer says "Nothing
found — check the Health app permissions or enter the values yourself". The pre-fill only fills
what it found; it never clears a value.

**The peak suggestion.** HealthKit has **no maximum-heart-rate type** — only heart-rate samples,
resting HR, walking average, HRV, recovery and VO₂ max; Apple's Workout-app zones are computed
internally and never written to Health. The pre-fill therefore also reads the highest heart-rate
sample of the last 6 months (`HeartRateZones.peakLookbackMonths`) with an
`HKStatisticsQueryDescriptor` and `.discreteMax` (HealthKit computes it; no months of samples are
fetched), dropping a value outside the plausible 120–230 bpm range as a sensor artifact. It is
**never filled in automatically**: the editor shows it as a row "Highest recorded: 192 bpm" with
*Use* (switches the source to *Measured* and fills it) and *Ignore*, and a footer warns that
everyday training rarely reaches the true maximum while a single optical spike (wrist movement
while boxing) can overshoot it. Rejected: auto-filling it as the max — a wrong max silently skews
every zone, in either direction. `NSHealthShareUsageDescription` (build setting + en/de
`InfoPlist.strings`) now also names date of birth, resting heart rate and highest recorded heart rate.

**Components (ticket 03).**

| Layer | File | Role |
|---|---|---|
| Domain/Models | `Conditioning/HeartRateProfile.swift` | `HeartRateProfile`, `HeartRateTarget`, `HeartRateHealthPrefill` |
| Domain/Services | `HeartRateZones.swift` | estimate, % HRmax, Karvonen, validation, which effort gets a target |
| Domain/Interfaces | `HeartRateProfileStoring.swift`, `HeartRateProfileHealthReading.swift` | gateways |
| Data | `Preferences/HeartRateProfileStore.swift`, `HealthKit/HealthKitHeartRateProfileReader.swift` | implementations |
| Presentation | `ViewModels/Conditioning/HeartRateProfileEditorViewModel.swift`; `ConditioningLibraryViewModel.heartRateGuidance(for:)`; `ConditioningCopy.heartRate*` | state + copy |
| Presentation | `Views/Conditioning/HeartRateProfileView.swift` (+ `HeartRateProfileSheet`), `ConditioningHeartRateCard.swift`; runner line in `ConditioningRunnerView`; Settings section in `SettingsRootView` | screens |
| App | `AppDependencies.heartRateProfileStore`, `makeHeartRateProfileEditor()`, profile snapshot in `makeConditioningRunViewModel(plan:)` | wiring |

Strings: `conditioning.hr.*`, `settings.section.conditioning*`, `settings.conditioning.hr.row.subtitle`.

**Tests (ticket 03).** `HeartRateZonesTests` (estimate, % HRmax, measured max, Karvonen, missing
values per source, seven implausible inputs, medication, only-conversational) and
`HeartRateProfilePresentationTests` (store round trip and clear, editor pre-fill fills only what was
found and refuses to save an invalid draft, the peak is only suggested — *Use* switches to a
measured max, *Ignore* leaves the draft untouched — "nothing found" state, preview guidance per session and
profile). The HealthKit reader is not unit-tested — it needs a real Health store.

**Monetization (ticket 03).** Free — §3 Rule 3: the target is in-session guidance, and the profile
exists only to feed it. No cap, no placement, no badge.

**Watch target.** Unchanged by ticket 03. Ticket 06 syncs the computed range (not the profile) to
the watch for the live zone indicator; RPE-only users get none there either.

## iOS architecture (ticket 04 — the 12-week program)

**What the user gets.** The Conditioning screen is the program — single sessions live one tap away
(see "One screen, one subject" below). Not enrolled: an invitation card → the **showcase**
("Conditioning for fighters" / "Kampfsport-Kondition"): a hero, the **week rail** (the twelve weeks
as three labelled, tappable blocks carrying the week range and the phase's short name), the three
**phase cards that expand in place**, four claims taken verbatim from the "Marketing claims" list
below (no guaranteed outcomes), a safety footnote, and *Set up my program* → an enrollment sheet
(start date ≥ today, beginner / experienced, "I spar hard at least twice a week").
Enrolled: a status card (phase label in the phase's accent, "Week 3 of 12", phase name or "Taper
week", and the same week rail — here filled up to the current week),
**Today's conditioning** (the suggested session with its volume, cautions and *Set up session*, or a
rest card saying why), **This week** (each target with dots and "1 of 2"; tapping one opens its
preview), and — when the user taps a block of that rail — the matching phase card, opened
**directly under the rail** with the user's own targets (the current phase wears a "Current" capsule,
past phases are ticked). There is no separate phase section further down: the first device test
showed that putting the explanation below "This week" broke the connection to the bar it explains. A menu offers Pause / Resume, Restart (the enrollment sheet again,
pre-filled) and Leave (confirmation; logged sessions stay in History). Before the start day the
screen shows "Starts Mon, Sep 21" and week 1's targets; after week 12, "Program complete" + Restart.
Every session still runs through the ticket 01 runner: the target opens `ConditioningPreviewView`
with `initialOptions` set to the target's volume, so the ticket 03 heart-rate card and the modality
choice are unchanged.

**One screen, one subject (revised after the first device test).** Ticket 01 built this screen as a
session library; ticket 04 first put the program on top of it, which left two competing subjects.
The library now lives behind one row at the bottom — *Single session* / *Einzelne Einheit* — pushing
`ConditioningSessionListView`. Nothing is lost: a one-off session is one tap away and still counts
toward the program week (the week's progress counts records by session type, not by how they were
started).

**Phases are one thing, shown twice — deliberately linked.** The first version had an unlabelled
three-segment bar at the top and the phase descriptions detached at the bottom, so the reader had to
connect them. Now the **week rail** (`ConditioningProgramWeekRail`) carries "Weeks 1–4 · Base" per
block and selects the matching card, and each **phase card** (`ConditioningProgramPhaseCard`) carries
its number on a connecting rail, its week range and energy system in the phase's own accent, a
teaser while collapsed, and — expanded — the detail, "what a week looks like" (the plan's own
targets) and the spacing rule that matters in that phase. The accents ramp with intensity: aerobic
`tint` green, lactic `warning` amber, alactic a local coral (`destructive` red reads as an error).
The showcase lists all three cards under the rail; the enrolled dashboard keeps the rail in its
status card and opens one card underneath on tap — collapsed by default, so the screen leads with
today's session until the user asks for the detail.
The showcase renders a *beginner's* week there: it is the conservative promise and the default the
enrollment sheet opens on. The same card, with the user's own targets, is the ticket-08 blurred
preview.

**The level choice explains itself.** Picking beginner or experienced (or flipping the sparring
switch) rewrites a summary card in place: sessions a week, then one row per phase with that phase's
emphasis at that level ("Weeks 5–8 · Build repeatable speed — 2 × 7 rounds"). It is derived from
`ConditioningProgramContent` (`sessionsPerWeek`, `emphasisTarget(of:experience:sparsHard:)`), never
written as prose, so it cannot drift from the plan the user will actually get.

**Routines tab entry.** `ConditioningProgramRoutinesCardView` sits under the create button: an
invitation with an × for users who are not enrolled (dismissal is device-local,
`conditioning.program.routinesCardDismissed`; the boxing button in the header stays), and "Week 3
of 12" for enrolled users. The invitation opens the Conditioning screen with the showcase already
pushed (`ConditioningLibraryView(opensShowcase:)`). Leaving the program brings the invitation back
only if it was never dismissed.

**The program as data (`ConditioningProgramContent`).** Phases → weekly templates → sessions from
`ConditioningLibrary`, never hard-coded in views. Beginners get the lowest volume option and fewer
sessions, experienced users the middle option:

| Weeks | Beginner | Experienced | Spars hard |
|---|---|---|---|
| 1–4 aerobic | 2 × aerobic base, 1 × bursts | 3 × aerobic base, 1 × bursts | same |
| 5–8 lactic (30/120 in 5–6, 45/180 in 7–8) | 1 × lactic, 2 × aerobic base | 2 × lactic, 1 × aerobic base | 1 × lactic, 2 × aerobic base |
| 9–11 alactic | 2 × alactic power, 1 × aerobic base | same, higher volume | same |
| 12 taper | 1 × alactic (2 sets), 1 × aerobic base (30 min) | same | same |

The protocol's "lactic optional in Phase 3 for non-sparrers" is **deliberately left out**: with two
alactic sessions it would be a third hard session and break the two-hard-a-week rule. A unit test
asserts no week, for any user, asks for more than two hard sessions.

**Week/phase derivation (`ConditioningProgramSchedule`).** Everything counts in calendar days. The
start is stored as `ConditioningProgramDay` (year/month/day), not an instant, so flying to another
time zone never moves the start; day differences go through `Calendar.dateComponents([.day])`
between local midnights, which counts a 23 h or 25 h DST day as one day. Program day = calendar days
since the start minus days inside a pause; a pause (`from ..< until`, or open `pausedSince`) freezes
the program on the day it began, and resuming picks up on that same day. `currentWeekStart` walks
back to the week's first calendar day, so a pause inside a week stays inside its range for progress
counting.

**Today's conditioning (`ConditioningProgramCoach`, pure).** Progress: an exact session match
counts first, then a session of the same energy system fills an open target (a 45/180 in a 30/120
week is still lactic work). The suggestion, in order:

1. Anything logged today → rest ("Done for today") — one conditioning session a day.
2. Every target met → rest ("This week is done").
3. Hard (lactic/alactic) targets first — the week's emphasis — unless blocked: two hard sessions
   already logged this program week → blocked (`hardSessionCap`); a lactic target within 48 h of
   the last lactic session's end → blocked (`lacticSpacing(until:)`, which can reach into the
   previous week, so the 48 h window is fetched separately from the week).
4. A heavy lower-body workout logged today → an open easy session is preferred; with none left the
   hard session is suggested with the caution "start no earlier than <end + 6 h>".
5. A user who spars hard gets a "not on a hard sparring day, or the day before one" caution on
   every hard suggestion.
6. Otherwise the open easy session; if nothing is suggestible, rest with the blocking reason.

*Heavy lower body* = at least two exercises whose muscle groups include Quadriceps or Hamstrings
(`StrengthLogEntry.isHeavyLowerBody`) — squats + RDLs count, one lunge on an upper-body day does not.
*Hard sparring counted as lactic*: the app does not know which days the user spars, so the flag
acts where it can — the lactic template drops to one session (sparring supplies the other) and the
caution above. Rejected: asking for sparring weekdays at enrollment — not in the ticket, and a fixed
weekday list goes stale.

**Data flow.** `ConditioningProgramViewModel` (`@Observable @MainActor`, one lazy instance in
`AppDependencies.conditioningProgram`, shared by the Conditioning screen and the Routines card)
computes a `ConditioningProgramDashboard` value in `refresh()`: two bounded fetches through
repositories — `ConditioningRecordRepository.fetch(since:)` (the earlier of the week start, 48 h ago
and today) and `WorkoutSessionRepository.fetchCompletedSessions(since: startOfToday)` (prefetches
`workoutExercises`; muscle groups are read in the view model, never in a view). It refreshes on
appear, when a run ends (`activeRun` back to `nil`), and when the enrollment changes on another
device. Views render the dashboard value only.

**Persistence and sync (`ConditioningProgramStore`, `Data/Preferences`).** The enrollment is JSON
in `UserDefaults` mirrored to iCloud key-value storage (`conditioning.program.enrollment`; the KVS
entitlement already exists). Chosen over a SwiftData `@Model` because it is one small value per
user: a CloudKit-synced model would need an irreversible Production schema deploy, and two devices
enrolling offline would each insert a row to reconcile. **No new record type — no CloudKit deploy
needed for this ticket.** The stored value carries `updatedAt`, and the later write wins; leaving
writes a *tombstone* (`enrollment: nil` + timestamp), so a device holding an old local copy cannot
resurrect a program the user left elsewhere. External changes arrive via
`NSUbiquitousKeyValueStore.didChangeExternallyNotification` (a `@Sendable` closure that hops with
`Task { @MainActor }`, observer removed in an `isolated deinit`).

**Components (ticket 04).**

| Layer | File | Role |
|---|---|---|
| Domain/Models | `Conditioning/ConditioningProgram.swift` | experience, calendar day, enrollment + pauses, phase, target, week |
| Domain/Services | `ConditioningProgramContent.swift`, `ConditioningProgramSchedule.swift`, `ConditioningProgramCoach.swift` | content, week/phase derivation, progress + today's suggestion |
| Domain/Interfaces · Repositories | `ConditioningProgramStoring.swift`; `fetch(since:)`, `fetchCompletedSessions(since:)` | gateways |
| Data | `Preferences/ConditioningProgramStore.swift`; the two bounded SwiftData fetches | implementations |
| Presentation | `ViewModels/Conditioning/ConditioningProgramViewModel.swift`, `ConditioningProgramCopy.swift` | state + copy |
| Presentation | `Views/Conditioning/ConditioningProgramShowcaseView` (+ `ConditioningProgramEnrollSheet`, `ConditioningExperienceSummaryCard`), `ConditioningProgramSection`, `ConditioningProgramTodayCard` (+ `ConditioningTargetProgressRow`), `ConditioningProgramPhaseCard`, `ConditioningProgramWeekRail`, `ConditioningSessionListView`; `ConditioningRoute` in `ConditioningLibraryView`; `Views/Routines/ConditioningProgramRoutinesCardView` | screens |
| App | `AppDependencies.conditioningProgramStore`, `conditioningProgram` (lazy) | wiring |

Strings: `conditioning.program.*`, `conditioning.library.single.*`. The German copy was rewritten
after the first device test ("Kampfbereite Kondition" and its subheadline did not read as natural
German): the program is **Kampfsport-Kondition**, the phases are *Grundlage aufbauen* /
*Tempohärte entwickeln* / *Explosivität schärfen*, and the English follows the same three nouns
(base / repeatable speed / explosive power). A Claude design canvas was used to settle the layout
before it was built.

**Ticket 08 hook (blurred preview).** `ConditioningProgramPhaseCard` takes a phase and the user's
own targets as values, and `ConditioningProgramDashboard.weeks` always carries all twelve weeks of
the user's plan — so the Phase 2–3 preview is these cards under `.proLocked`, not a new view.
**Ticket 05 hook.** The post-workout add-on calls the same `ConditioningProgramCoach.suggestion`
with the just-finished strength workout in `strengthToday`.

**Tests (ticket 04).** `ConditioningProgramScheduleTests` (weeks/days and completion, open pause
freezes, closed pause shifts, spring-forward and fall-back DST in Europe/Berlin, time-zone travel,
week start spanning a pause); `ConditioningProgramContentTests` (phase layout and taper, ≤ 2 hard
sessions every week for every user, sparring halves lactic, volumes valid);
`ConditioningProgramCoachTests` (progress matching, hard first, one a day, 48 h lactic spacing —
easy meanwhile / rest until / clear after 48 h —, leg day prefers easy / flags hard ≥ 6 h, the
heavy-lower-body threshold, the two-hard cap, sparring caution, week complete);
`ConditioningProgramStoreTests` (round trip through iCloud, tombstone beats an older local copy,
older cloud value never wins); `ConditioningProgramViewModelTests` (enroll → week 1 with a
suggestion, pause freezes and resume shifts, a logged session counts, leave + dismiss).

**Device verification — PASSED (physical iPhone, 2026-09-20).** The Routines card carries the
program name; the week rail opens the matching phase card directly beneath the status card and
closes it again; the showcase's three phase cards expand with their week example and spacing rule;
the enrollment sheet's level card rewrites itself between Einsteiger and Erfahren and lines up with
the form's other rows; a program session opens its preview at the program's volume (45 min for an
experienced user, not the 30 min default), and finishing one moves the week's progress to 1 von 3 and
turns today's card into "Für heute erledigt"; a session started from *Einzelne Einheit* counts the
same; pausing freezes the week and resuming returns to it without advancing; leaving brings back the
invitation card, which dismisses with its ×; re-enrolling opens with no phase expanded.

**Not verified on device, and why.** Phases 2–3, the taper and the completed state — and with them
all four spacing rules (48 h between lactic sessions, the "≥ 6 h after heavy legs" caution, the
two-hard-sessions cap, the sparring caution) — first occur in week 5, and the start date cannot be
set in the past, so reaching them means waiting five weeks. They rest on the eleven
`ConditioningProgramCoachTests` cases. Cross-device iCloud sync of the enrollment is likewise
untested: it needs a second device on the same account.

**Follow-ups found but not applied (ticket 04).**

- *Allow a start date in the past.* The picker is bounded to today (`in: startOfDay(for: Date())...`
  in `ConditioningProgramEnrollSheet`). Allowing earlier dates would support a camp already under way
  and, incidentally, make Phases 2–3 reachable for device testing. `ConditioningProgramSchedule`
  already handles it — `programDay` simply returns a larger number; only the picker bound stops it.
- *Change the level mid-program.* Einsteiger/Erfahren can only be changed by restarting, which resets
  the weeks. The enrollment is a mutable value, so a "change level" action that keeps `startDay` and
  `pauses` is small; it was left out because the ticket did not ask for it.
- *The showcase hero scrolls under the transparent toolbar*, so the back button can overlap the
  title mid-scroll. Cosmetic and consistent with the app's other full-screen covers; a scroll-edge
  background on the showcase would fix it.

**Monetization (ticket 04).** Free and ungated for now, as planned — ticket 08 adds the Phase 2–3
depth gate at `PaywallPlacement.conditioningProgram`. Recorded in `docs/monetization-strategy.md` §4.

**Watch target.** Unchanged by ticket 04 — but since ticket 06 every `refresh()` also republishes
the week's open sessions to the watch (see below).

## iOS architecture (ticket 05 — the post-workout add-on)

**What the user gets.** An enrolled user who finishes a strength workout on iPhone is offered today's
conditioning session on the **workout summary** (`SaveWorkoutView`), as one card between the
exercise-progress section and the Apple Health toggle.

| Offer | Card | Actions |
|---|---|---|
| `.startNow` — easy aerobic work | "Add conditioning?" · "Aerobic base · 45 min" · "Easy aerobic work fits right after lifting." | **Start now** |
| `.later` — lactic or alactic work | "Better later today" · the session · "This is hard work. Keep at least 6 hours from lifting — ideally another day. Earliest from 01:00." | **Remind me later** (prominent) · *Start anyway* (the explicit override) |
| `.none` | nothing renders | — |

The × in the card header dismisses it in one tap. Nothing is persisted by a dismissal: the next
workout asks again, because by then the answer may differ.

**The prompt cannot block or delay the save**, and that is structural rather than careful: the card
is a `Section` in the summary `Form`, so it is a passenger on a screen the user was already on. The
Save button is untouched. *Start now* does commit the workout — through `completeWorkout`, the very
same call Save makes, behind the same `isSaving` latch — because the two sessions have to reach
Apple Health as separate workouts.

**Two `HKWorkout`s, never overlapping.** `pauseForCompletion()` stamps `WorkoutSession.endTime` when
the user taps Finish, i.e. before this screen appears; the conditioning session's timeline starts
only after `completeWorkout` returns. The strength workout's range therefore ends strictly before the
conditioning one begins, whatever the user does on the summary screen. This is the flow the ticket-01
research demanded: `HKWorkoutSession.beginNewActivity` is hard-restricted to `.swimBikeRun`, so
strength → cardio in one session is impossible anyway.

**The decision is the ticket-04 Domain service.** `ConditioningProgramCoach.addOn(…)` is
`suggestion(…)` plus exactly **one extra rule**: *right after lifting is stricter than the same day as
lifting.* The coach's existing leg-day rule prefers easy work only when the day's lifting was heavy
lower body — correct for "today", because hard conditioning in the evening after an upper-body morning
is fine. Sharing a *session* is different: same-session concurrent training blunts explosive power
most of all (Robineau 2016, Wilson 2012), so the add-on offers an open **easy** target first whatever
the week's emphasis is, and offers a hard one for **later** rather than now. Everything else — the
48 h lactic spacing, the two-hard-a-week cap, one session a day, the sparring caution — is inherited
unchanged, which is why a rest verdict simply produces no card.

`finishedAt` is passed in rather than read from the repository: the summary appears **before** the
workout is committed, so the session the offer is about is not in the store yet. The caller appends it
to today's committed workouts, so the coach's own rules do see it.

**"Remind me later" reuses the reminders infrastructure, but not the planner.** It goes through the
same `WorkoutReminderNotificationCenter` seam and the same Domain permission projection
(`WorkoutReminderPermissionRequesting`) as `docs/workout-reminders.md`, and its fire time starts at
`WorkoutReminderPlanner.reminderHour`. It is deliberately **not** a fourth reminder kind:

- **Not in `WorkoutReminderPlanner`.** That scheduler *derives* a window of mornings from the user's
  plans and rebuilds it from scratch on every pass. This is a single, user-requested, one-shot
  reminder for a moment that exists nowhere in the plans — the first rebuild would silently drop it.
- **Not under `ReminderFrequencyPolicy`.** That cap bounds how often the app speaks **unprompted**.
  This reminder exists because the user asked for it one tap ago, the same reasoning under which the
  rest timer and the ticket-01 conditioning cues sit outside the cap. Its cap is structural instead:
  **one identifier** (`conditioning.reminder.session`), so a second request replaces the first and at
  most one can ever be pending.
- **The two features cannot delete each other's requests.**
  `UserNotificationWorkoutReminderScheduler` retires only identifiers carrying the
  `workoutReminder.` prefix, which this one deliberately does not.

**The fire time** (`ConditioningProgramCoach.reminderFireDate`) is `notBefore` — the six-hour mark —
pushed into waking hours: before 08:00 it waits for 08:00 the same day; at or after 21:00 it moves to
08:00 the next morning. Built from date components, not by adding hours, so a reminder pushed across a
DST transition still lands at 08:00 wall clock. Lifting that ends after 15:00 therefore produces a
next-morning reminder, which is the "ideally another day" the protocol actually wants.

**Permission.** The reminder asks for notification permission if it is still undetermined. That is a
deliberate exception to `docs/workout-reminders.md`'s "the offer screen is the only place": the user
has just tapped a button whose entire meaning is "send me a notification", which is the least careless
possible moment to spend the one irreversible ask — and ticket 01's cue deliverer already established
that this feature asks lazily at the point of use. When permission is absent the scheduler returns
`false` and the card says so ("Turn on notifications in Settings to be reminded") rather than
confirming a reminder that does not exist.

**Where the runner is hosted, and why it is not the summary screen.** `SaveWorkoutView` is a sheet
that dismisses itself as part of starting the session, so a runner presented from there would be torn
down with it. `ConditioningAddOnViewModel` is therefore one app-lifetime instance in
`AppDependencies`, and `ContentView` presents `ConditioningRunnerView` from it — hosted at the root
for the same reason the paywall and the first-run covers are. It is **not** part of `FirstRunCoverOrder`:
it is never raised at launch, only by a deliberate tap, by which time every first-run cover is gone.
`activeRun` is read in `body` (like `pendingPaywall`) so this view is observing it before the sheet
writes it. The cover's `onDismiss` calls `program.refresh()`, so the finished session counts toward the
week on the Conditioning screen and the Routines card.

**Deliberate simplification: `Start now` goes straight to the runner**, not through
`ConditioningPreviewView`. The volume comes from the program target and the modality from the
session's own default — which is exactly what the preview would have opened on. The cost is that the
user cannot pick run vs. bike vs. rower for this one session without going to the Conditioning screen
instead; the research note that maximal efforts prefer bike/rower is therefore not honoured on this
path. To restore the choice, route `start()` to the preview with `initialOptions: target.options`, as
the Routines-tab program card already does.

**Watch-finished strength workouts are out of scope**, as the ticket states. This add-on lives on the
iPhone summary screen only. A workout finished on the watch reaches the phone through
`transferUserInfo` and is ingested by `WatchWorkoutIngestionService` with no summary screen and often
with the phone app not even running, so there is no moment at which this prompt could be shown. The
watch target is untouched by this ticket; a conditioning add-on on the watch belongs with tickets
06/07, which build the watch runner and its sync.

**Components (ticket 05).**

| Layer | File | Role |
|---|---|---|
| Domain/Services | `ConditioningProgramCoach.swift` | `ConditioningAddOnOffer`, `addOn(…)`, `reminderFireDate(…)`, `hardAfterLifting` |
| Domain/Interfaces | `ConditioningReminderScheduling.swift` | the one pending reminder, copy passed in already localized |
| Data | `Notifications/UserNotificationConditioningReminderScheduler.swift` | over the existing `WorkoutReminderNotificationCenter` seam |
| Presentation | `ViewModels/Conditioning/ConditioningAddOnViewModel.swift` | offer, reminder, the started run; `ConditioningProgramViewModel.addOn(finishedAt:isHeavyLowerBody:)` + the extracted `coachEntries` helper; `ConditioningProgramCopy.addOn*` |
| Presentation | `Views/Conditioning/ConditioningAddOnCard.swift` (value input only), the section in `Views/Workout/SaveWorkoutView.swift` | the card |
| App | `AppDependencies.conditioningAddOn` (lazy); the runner cover in `ContentView` | wiring and hosting |

Strings: `conditioning.addon.*` in en + de.

**Tests (ticket 05).** `ConditioningAddOnTests` — the decision (easy offered now; hard offered for
later at exactly the six-hour mark; an open easy target beating the week's hard emphasis, asserted
*against* what `suggestion` returns for the same inputs, so the extra rule cannot silently disappear;
no offer on a rest verdict or after a session already logged today; a leg day still offering easy
work now), the fire time (kept when it is inside waking hours, pushed to the next morning from a
late one, waiting for 08:00 from an early one, and a spring-forward DST case), and the view model
(no offer when not enrolled; dismissal clearing the card and persisting nothing; `start()` running
the offered session at the program's volume and cancelling any pending reminder; `remindLater()`
scheduling exactly one reminder at the computed time; a refused reminder reported rather than
confirmed).

**Monetization (ticket 05).**

```
Monetization verdict — post-workout conditioning add-on
  Tier          Free
  Derivation    §3 Rule 1 (the aha path: train it → see it logged) and Rule 3 (it starts an
                in-session surface that is already free)
  Mechanism     n/a — nothing is gated
  Placement     none
  Nudge         none
  Free residue  the entire feature
  Founder note  it converts nobody by design: it is a shortcut into a free session, and gating a
                prompt whose whole job is to get the user to train again would work against §10's
                retention guardrail.
```

Re-checked at completion: nothing added here reads `ProEntitlementProviding` and no `PaywallPlacement`
was added. Ticket 08 still gates program Phases 2–3; this card shows whatever session the user's own
plan asks for, so it inherits that gate rather than needing one.

**Two things the architecture review changed** (verdict: PASS WITH WARNINGS, no critical findings):

- *The view classifies nothing.* The first cut walked `session.workoutExercises` and called
  `StrengthLogEntry.isHeavyLowerBody` inside `SaveWorkoutView` — a domain computation in a View
  (Hard rule 3) that also duplicated `ConditioningProgramViewModel`'s own helper. The classification
  now has **one definition**, `ConditioningProgramViewModel.strengthEntry(_:endTime:)`, used both for
  committed workouts and, through `ConditioningAddOnViewModel.prepare(for:)`, for the uncommitted
  one; the view passes the session and nothing else. `endTime` is a parameter precisely because the
  add-on classifies a session the summary screen has not saved yet.
- *One commit path.* `SaveWorkoutView.commitWorkout(then:)` is now the only place the workout is
  completed; the Save button and *Start now* both call it, the latter with the runner start as its
  `afterCommit`. Two copies of the guard / `isSaving` latch / dismissal order would have drifted.

**Deliberate asymmetry worth knowing.** Unlike a training reminder, the conditioning reminder is
**not** withdrawn while a workout is running. `UserNotificationWorkoutReminderScheduler` cancels its
own requests on every pass to honour §3 Rule 3; this one is user-requested, one-shot and about the
session the user is being reminded to do, so it stands. If it ever needs suppressing, the hook is
`WorkoutViewModel.currentSession`'s `didSet`, which is where the training reminders do it.

**Device verification — PASSED (physical iPhone, 2026-09-21).** In program week 1 the summary screen
offers "Aerobic base · 30 min" with the easy-work line; the × removes the card without moving
anything else on the form and without affecting Save; Save behaves normally. *Start now* commits the
workout and opens the runner, History then lists both the strength workout and the conditioning card,
and **Apple Health shows two separate workouts whose times do not overlap** — the criterion this
ticket turned on. A third workout the same day is offered nothing, which is the coach's
one-session-a-day rule reaching the summary screen correctly.

**Not verified on device, and why.** The `.later` branch — and with it the six-hour explanation, the
reminder and the *Start anyway* override — needs a lactic or alactic week, which first occurs in
week 5. That is the same reachability limit ticket 04 recorded: `ConditioningProgramEnrollSheet`
bounds the start-date picker at today (`ConditioningProgramShowcaseView.swift:179`), so reaching
week 5 means waiting four weeks. It rests on eight `ConditioningAddOnTests` cases covering the
deferral, the exact six-hour mark, the "easy beats the week's hard emphasis" rule, and the four
fire-time cases including the late-evening push to the next morning and a spring-forward DST day.
Lifting the picker bound — already a wanted ticket-04 follow-up — would make it testable immediately.

## Watch architecture (ticket 06 — the watch runner with a live heart-rate zone)

**What the user gets.** An enrolled user sees a **Conditioning** row on the watch's routine list
("Today: Aerobic base", or "3 sessions this week"). It opens this program week's open sessions —
*Today* (the coach's suggestion) and *This week* (the other open targets). A session shows its
volume, total time, the personal heart-rate range when there is one, a machine picker (the session's
own modalities, default first) and a one-line stop rule; **Start** opens the runner as a full-screen
cover. After a strength workout on the watch, the summary offers **Conditioning next** with today's
suggested session; tapping it closes the summary and starts that session as soon as the strength
workout's HealthKit session has ended.

The runner shows the phase (effort phases on a tint capsule with black text), the phase countdown,
"Round 2/6" or "Set 1/3 · Rep 4/5", the RPE cue, live heart rate — with the range and a below / in
zone / above glyph during conversational phases only — the next phase, and Pause/Resume and End
(confirmation that says whether anything will be saved). At the end: "Session complete" / "Session
ended", the time, and the Apple Health outcome.

**No synced program → nothing.** Not enrolled, paused, not started or completed publishes an empty
offer, and the watch then renders no conditioning row, no empty state and no paywall (Rule 3). The
same happens once the program week the offer was computed for is over (`validUntil`), so a watch
whose iPhone has not been opened for a week never offers stale targets.

**What travels (iOS → watch).** The iPhone does all program logic; the watch only runs phases.
`ConditioningProgramViewModel.watchOffer()` derives a Domain `ConditioningWatchOffer` from the
dashboard it just computed — the week's targets with sessions still open, today's suggestion first,
each at the program's volume with the session's default modality, plus
`HeartRateZones.target(for: definition.effort, profile:)`, which is `nil` for every effort but the
conversational one and for RPE-only users. `refresh()` publishes it through the Domain
`ConditioningWatchPublishing` interface on every call (a `defer`, so leaving and pausing publish the
empty offer too). `refresh()` now also runs on every app activation (`GymStreakApp`), because "today"
and the program week roll over by the clock, and on every heart-rate profile save (the store's new
`onChange`, wired in `AppDependencies`).

`WatchConditioningMapper` (Data) turns the offer into the wire DTO `WatchConditioningProgram`
(`Data/Sync/WatchConditioningModels.swift`, identical copy in the watch target): the session type,
energy system, modalities, volume, "today", the **already expanded phases**, and the range as two
integers. Enums travel as strings so a watch that does not know a newer value drops one session, not
the whole offer. It rides as sorted-key JSON under `conditioningProgram` in **the same application
context as the routines** — `updateApplicationContext` replaces the whole dictionary, so a context
of its own would clobber them. `RoutineSyncAuthority.updateConditioningProgram(_:push:)` follows the
weight unit's contract exactly; both now go through one `republishContextExtras`. The offer carries a
*day*, not an instant, and is compared as bytes, so the refresh on every activation costs an authority
generation only when the offer really changed. On the watch, `processApplicationContext` applies it
ahead of (and independently of) the routine authority decision, like the unit; an absent key (older
iPhone build, no refresh yet this launch) keeps the last offer.

**Root cause of the first device test (2026-09-22): no Conditioning row on the watch.** The offer is
published from `refresh()` on app activation — at launch that is *before* `WCSession` finishes
activating, so `canSyncRoutines` refused the push and the value was only recorded. Nothing re-sent it:
activation did not trigger a routine sync, and the next ordinary sync was dropped by the
identical-routine-payload suppression, so the offer never left the phone in that process. The weight
unit had the same latent gap. Fix: `RoutineSyncAuthority.hasUnsentExtras` is set whenever an extra
changes and cleared only when a context is actually handed to WatchConnectivity (`handToTransport`);
while it is set `sendOrdinary` bypasses the suppression, and `activationDidCompleteWith` posts
`.watchAppBecameAvailable` so `RoutinesViewModel` syncs — that post is what fixes the device case
(at launch no routine payload has gone out yet) and it needs a real `WCSession`, so it is verified on
device only — confirmed 2026-09-22: after the fix, "Kondition · Heute: Aerobe Basis" appeared on the
watch right after an iPhone launch. `ConditioningOfferBeforeActivationTests` covers the suppression bypass, the safety net
for when routines already went out. Architecture review of the fix: PASS.

**Swim is left out on the watch.** The mapper filters it from the modalities. A live watch session
for `.swimming` wants a location type and, for a pool, a lap length the app does not have — the
research could not confirm whether `.unknown` is accepted at session start — and a touchscreen
runner is no use in the water anyway. Swimming stays an iPhone choice. No current session has swim
as its default, so nothing disappears.

**Why the phases are expanded on the iPhone.** The ticket asked for the timeline engine duplicated
into the watch target and kept identical. The *timing* core is (`ConditioningTimeline.swift` —
position lookup, first-effort rule, completed rounds — and `ConditioningClock`, plus
`ConditioningPhase.swift`), byte for byte; the *expansion* (`init(plan:)`, `phases(for:options:)`)
moved to the iOS-only `ConditioningTimeline+Expansion.swift`, because it needs `ConditioningLibrary`
and the session definitions, which the watch would otherwise also have to duplicate. The watch never
decides a structure; it runs what the iPhone sent. `WatchConditioningTimelineTests.sharedCopiesMatch`
reads both copies of all three shared files through `#filePath` and fails the moment they differ.

**The runner (`WatchConditioningRunViewModel`, `@Observable @MainActor`).** Same principle as the
iPhone: it never counts down. A 250 ms task re-derives `position` from `ConditioningClock` (wall clock
minus pauses) on every tick. Cues come from the pure `ConditioningCueEvaluator`: the effort cue
(`.start`) or recovery cue (`.stop`) when a phase boundary is crossed, a `.click` 3-2-1 before every
effort phase that follows another, `.success` at the end. A tick more than 2 s after the previous
one is a catch-up and replays nothing — the iPhone's `resynchronize` rule. If the last phase ended
while the process was not running, the workout ends at the timeline's end, not at wake-up.

**The zone nudge (`ConditioningZoneMonitor`, pure).** Only during a conversational phase with a
synced range. Out of zone for **30 s** → `.directionUp` (below: pick it up) or `.directionDown`
(above: ease off), then at most once every **60 s** while the drift lasts; back in zone, a change of
direction or a phase without a range restarts the count. Time is session time, so a paused session
cannot nudge. Heart rate lags effort by tens of seconds, and a buzz on every sample would train the
user to ignore it.

**Apple Health (`WatchConditioningWorkoutManager`).** Its own `HKWorkoutSession` + `HKLiveWorkoutBuilder`
with the modality's activity type — run `.running`/outdoor, bike `.cycling`/indoor, rower
`.rowing`/indoor, sled/ropes/med ball `.highIntensityIntervalTraining`/indoor, the iPhone's mapping.
Deliberately **not** `WatchHealthKitManager`: that manager's finalization is bound to the durable
strength queue, which conditioning does not use (ticket 07 decides how watch sessions reach iPhone
History). Metadata on save: `HKMetadataKeyExternalUUID`, brand name = session title,
`GymStreakSessionKind = conditioning` — the key the iPhone's recovery drain already skips, so a watch
conditioning workout never shows up in the strength recovery banner. Ending before the first effort
discards the session (nothing saved), the iPhone rule. Live heart rate comes from
`workoutBuilder(_:didCollectDataOf:)`; only the rounded `Int` crosses to the main actor. Pause/resume
pause the HealthKit session too, so the saved workout's duration excludes pauses (unlike the iPhone
path, which writes wall clock after the fact). If the system ends the session from outside (another
workout started, which force-ends ours), `didFailWithError` reaches the runner through
`onSessionFailed` and the run ends there instead of ticking on without background runtime; `finish`
throws when there is no session to save, so the summary never claims "Saved to Apple Health" for
nothing.

**Strength → conditioning.** Only one workout session can run on the watch: starting a second one
force-ends the first with `errorAnotherWorkoutSessionStarted`. The summary therefore only *queues*
the session (`queueAfterWorkout`); `RoutineListView`'s strength-cover `onDismiss` starts it, and
`start` waits (up to 15 s, polling `WatchHealthKitManager.isWorkoutActive`, which turns false when
the strength session reaches `.ended`) before creating the conditioning session. Still busy → "Couldn't
start the session". The runner cover lives on `RootView`, above the `NavigationStack`, because a
session starts from a pushed detail screen and a cover cannot be raised from under the strength cover.

**Crash recovery (`docs/watch-workout-recovery.md` patterns).** `WatchConditioningCheckpoint` — the
synced session, modality, clock and external UUID — is one atomically-replaced App Group file
(`Conditioning/active-session-checkpoint.json`), written on start, pause and resume only: the clock
is wall-clock based, so nothing per tick needs saving. On relaunch `WatchWorkoutRecoveryCoordinator`
recovers the active HealthKit session once and, before the strength planner sees it, calls
`resumeConditioning`: a conditioning checkpoint **and** a recovered session whose activity type is not
`.traditionalStrengthTraining` (HealthKit restores the original configuration) → the conditioning
manager adopts it and the runner resumes where the wall clock says, with no cue replay. A checkpoint
without such a session → the checkpoint is discarded (the workout was ended or never began). A
recovered conditioning session **without** a checkpoint falls through to the strength planner's
existing orphan path, which saves it to Apple Health as a plain "GymStreak" workout — acceptable,
and it carries no external UUID, so the iPhone never offers it for recovery. The architecture review
suggested guarding strength adoption on `.traditionalStrengthTraining` instead; rejected, because an
un-adopted session is never ended and would keep running in the background, blocking the next
workout.

**Offer persistence on the watch (`WatchConditioningStore`).** The exact received bytes in an
atomically-replaced App Group file (`Conditioning/program.json`), so the row is there before the
first context of a launch; undecodable bytes are ignored and the last good offer stays. Owned by the
watch `WatchConnectivityManager` like the catalogue store; `AppState` puts it and the runner into the
environment. "Today" is shown only on the day the iPhone said it. The store publishes precomputed
`sessions` / `today` / `others` (recomputed on apply and on every app activation, since the day and
the week roll over by the clock), so no view body filters.

**Components (ticket 06).**

| Target | File | Role |
|---|---|---|
| iOS Domain | `Models/Conditioning/ConditioningWatchOffer.swift`, `Interfaces/ConditioningWatchPublishing.swift` | the offer and its gateway |
| iOS Presentation | `ConditioningProgramViewModel+WatchOffer.swift`; publish in `refresh()` | derivation |
| iOS Data | `Sync/WatchConditioningMapper.swift`, `Sync/WatchConditioningModels.swift` (shared), `WatchConnectivityManager.publishConditioningOffer`, `RoutineSyncAuthority.updateConditioningProgram` | wire + transport |
| iOS App | `AppDependencies` (`conditioningWatch`, profile `onChange` → refresh), `GymStreakApp` (refresh on activation) | wiring |
| Shared (identical) | `ConditioningPhase.swift`, `ConditioningTimeline.swift`, `WatchConditioningModels.swift` | timing engine + wire |
| watch Models | `Conditioning/ConditioningRunCues.swift` (cue evaluator, zone status, zone monitor), `WatchConditioningCheckpoint.swift` (+ store), `WatchConditioningCopy.swift` | pure logic, crash boundary, en/de copy |
| watch Managers | `WatchConditioningStore.swift`, `WatchConditioningWorkoutManager.swift`; hooks in `WatchConnectivityManager`, `WatchWorkoutRecoveryCoordinator` | sync, HealthKit, recovery |
| watch ViewModels | `WatchConditioningRunViewModel.swift` | the runner |
| watch Views | `Conditioning/ConditioningSessionListView` (+ `ConditioningEntryRow`), `ConditioningSessionDetailView`, `ConditioningRunnerView`, `ConditioningRunSummaryView`; row in `RoutineListView`, button in `WatchWorkoutSummaryView`, cover in `RootView` | screens |

Strings: 58 new English-key entries with German in the watch `Localizable.xcstrings` (session titles,
machines, phases, RPE cues, positions, runner and summary copy). The watch localizes the synced raw
values itself, so it follows its own language.

**Tests (ticket 06).** Watch: `WatchConditioningTimelineTests` (offsets and lookup, first effort and
completed rounds, the pause-aware clock's checkpoint round trip, and the three shared files identical
across targets); `WatchConditioningRunCuesTests` (3-2-1 and effort cue, recovery and finish cues, no
replay on a catch-up or while paused, zone status, 30 s sustained drift then once a minute, resets);
`WatchConditioningStoreTests` (survives a relaunch, garbage and duplicates ignored, stale week and no
program show nothing, "today" only on its day and the rest under "this week"); `WatchConditioningRunViewModelTests` (warm-up end
saves nothing and discards, an early end after the first effort saves once at that moment, pause
freezes, a recovered session replays no cue and finishes at the timeline's end, the zone only where
the iPhone put one and never for RPE-only, a sustained drift nudges). iOS:
`ConditioningWatchOfferTests` (open sessions with the suggestion first and `validUntil` at the week's
end at the program's volume, the range only for conversational sessions and never with the medication
switch, empty offer when not enrolled / paused / left, the wire mapping drops swim and is
deterministic, the offer rides the routine context, is resent only on change and survives a unit
change). Suites: watch 104/104, iOS 1472/1472.

**Monetization (ticket 06).**

```
Monetization verdict — watch conditioning runner
  Tier          Free
  Derivation    §3 Rule 3 (on the watch app and inside an active session)
  Mechanism     n/a — nothing is gated
  Placement     none
  Nudge         none
  Free residue  the entire feature
  Founder note  n/a — nothing gated
```

Re-checked at completion: no watch file reads an entitlement, no `OnyxProBadge`, no placement. When
ticket 08 gates program Phases 2–3 on the iPhone, the watch simply runs whatever the iPhone offers —
the gate belongs in `watchOffer()`'s input, never on the watch.

**Deliberate omissions.** No watch safety screen — the one-line stop rule on the detail screen
stands in; the full first-use screen is on the iPhone. No "single session" library on the watch —
only the program's open sessions, which is what the ticket asked for. No record in iPhone History yet
— that is ticket 07; until then a watch session exists only in Apple Health (and the iPhone's week
progress does not count it). The volume cannot be changed on the watch; it is the program's.

**Device verification (physical iPhone + Apple Watch, 2026-09-22).** Passed: the Kondition row
with "Heute: Aerobe Basis" after an iPhone launch (once the sync fix below was in); the personal
range under "Ziel"; the runner with countdown, phase, heart rate and zone glyph; the countdown
correct after wrist-down; pause freezing the countdown; haptics at WORK/PAUSE changes wrist-down;
the workout in Apple Health / Fitness; crash recovery (force-quit mid-session → the runner reopens at
the right point); strength → "Jetzt Kondition" opening the runner, with two separate,
non-overlapping workouts in Apple Health.

**Bug found on device: the end dialog came back on top of the summary.** Tapping *Einheit beenden*
in the "Einheit vorzeitig beenden?" dialog showed the summary briefly, then the dialog again (closable
with its ✕, which revealed the summary). Cause: the `confirmationDialog` sat on the view wrapping
every runner state, and the confirm button called `run.end()` directly. The session switched the
screen to the summary while the watchOS dialog was still animating out with its `isPresented`
binding still `true`, so the re-render presented it a second time. Fix: the dialog is attached to the
running screen only, and its button just sets `isEndConfirmed`; `.onChange(of: isConfirmingEnd)`
calls `end()` once the dialog has closed. Re-checked on device 2026-09-22: fixed.

**Architecture review: PASS WITH WARNINGS (2026-09-21), no critical findings.** Applied: `watchOffer()`
moved to its own extension file (the view model had crossed 300 lines), the store's precomputed
sessions (no filtering in `body`), `finish` throwing without a session, and `onSessionFailed`.
Acknowledged, not changed: `AppDependencies`, `RoutineSyncAuthority` and the iOS
`WatchConnectivityManager` were already over 300 lines and grew slightly; `refresh()` on every
activation is main-actor work, bounded to two small fetches plus encoding one small offer.

## Watch runner redesign (2026-09-22)

**Why.** The ticket-06 runner worked but was a scrolling list: phase, countdown, position, effort,
heart rate, range, arrow, next phase and the buttons did not fit even an Ultra 3, and the zone was
"128 · 112–140 bpm · ↑" — correct, but it made the user do the arithmetic. The redesign was drawn in
Claude design ("Watch Conditioning Runner Redesign", https://claude.ai/artifact/Chhz8TStY6r515mWYnhGcA),
approved by the user, and built as drawn.

**The layout.** Every page fits the screen without scrolling, on every size down to the 40 mm SE.

- **One gauge, two uses.** A 240° arc open at the bottom follows the watch edge
  (`ConditioningGaugeLayout`: centre at 47 % of the height, radius 43 % of the shorter side, from 150°
  over the top to 390°). Everything is laid out on that geometry and scaled by
  `width / 211 pt` (the canvas was drawn for the Ultra 3), so the SE shows the same composition.
- **Steady state = the heart-rate gauge** (`ConditioningZonePage`). The gauge spans the personal
  range ± 40 bpm (`ConditioningZoneGauge`, pure): the range is a bright green band in the middle
  third with its bounds labelled, below it the arc is tinted blue, above it orange, and the live
  heart rate is a glowing marker that moves along it (animated, no glow in Always-On). The centre
  says what to *do*, in the state's colour: "Im Ziel" ✓, "Etwas zügiger" ⌃⌃ or "Etwas ruhiger" ⌄⌄,
  with "noch 14 bpm bis zur Zone" / "12 bpm über der Zone" / "Tempo halten · 112–140" under it;
  remaining time sits in the gauge's open bottom. RPE-only users (no range) get the same page with
  the arc as session progress and "RPE 3–4 · Gesprächstempo halten" — never a target.
- **Every other phase = the countdown ring** (`ConditioningIntervalPage`): the arc empties as the
  phase runs (green for effort, grey for recovery), the phase in a pill (effort on the tint with
  black text), the countdown, the RPE cue, a row of round dots, heart rate, and the next phase. In the
  last three seconds before an effort the page turns into the lead-in: "BELASTUNG IN" and a large
  green 3-2-1, matching the haptic `.click`s.
- **Controls one swipe to the left** (`ConditioningControlsPage`), like Apple's Workout app: the
  running state is a horizontal `TabView(.page)` with the controls page first and the runner selected
  by default. Two big round buttons, Pause/Resume (amber) and End (red). Pausing jumps back to the
  runner. Moving them off the main page is also what stops an accidental End mid-sprint. The end
  confirmation stays attached to the running state with the end-after-dismissal pattern above.

The view model derives what the pages draw (`WatchConditioningRunViewModel+Display`: which page,
`leadInCount`, `phaseRemainingFraction`, `sessionFraction`, `roundProgress`); the pages take values
only. New tokens: `OnyxWatch.Colors.zoneBelow` / `zoneAbove` / `gaugeTrack`. Strings: 14 new en/de
keys ("On target" → "Im Ziel", …); five keys of the old runner were removed. Deliberate trade-off:
the runner pages use fixed sizes scaled by screen width, not Dynamic Type, so the gauge composition
never needs scrolling. Architecture review: PASS WITH WARNINGS (a missing "RPE 3–4" catalog entry and
a doubled VoiceOver label on the controls page, both fixed).

**Verified before handing over.** The pages were rendered to PNG at Ultra 3 (211 × 257 pt) and SE
40 mm (162 × 197 pt) through a throwaway `ImageRenderer` test and checked against the canvas — that
caught text without an explicit colour (black on black outside a dark environment), bound labels
colliding with the phase caption, and the lead-in cue overlapping the round dots, all fixed. Tests:
`WatchConditioningRunCuesTests.gaugePlacement` and `WatchConditioningRunViewModelTests.displayValues`.
Watch suite 106/106 (three consecutive green runs); 108/108 with the heart-rate loading state.

**Heart rate while it is loading (2026-09-22).** The first sample of a workout session takes a few
seconds, and the runner used to show "--" meanwhile. Worse, with no reading there is no zone status,
so the zone page fell back to the RPE-only copy and told a user *with* a range "RPE 3–4 ·
Gesprächstempo halten". Now `ConditioningHeartRateReading` (in `WatchConditioningRunViewModel+Display`)
has three states: **measuring** — a spinner sized to the number it stands in for (so nothing shifts
when the value arrives), a pulsing heart, "Puls wird gemessen …" and "Ziel 112–140 bpm"; **missing**
— after 30 s without a sample, counted from when delivery (re)started (a crash-recovered session
measures again rather than claiming "no heart rate" at once) (loose fit, or Health read access to heart rate denied)
a dimmed "--", "Kein Puls" and "Sitz der Uhr und Health-Zugriff prüfen", so the spinner never spins
forever; **bpm** — the gauge as designed. RPE-only users keep their copy in every state; the
interval page uses the same spinner in its footer. `ImageRenderer` cannot draw the system spinner,
so its look was checked on device — confirmed by the user 2026-09-22, together with the redesign. Tests: `WatchConditioningRunViewModelTests.heartRateReading`,
`recoveredSessionMeasuresAgain`. Architecture review: PASS WITH WARNINGS (the recovery window and a
missing VoiceOver label on "--", both fixed).

**Bug found while testing the redesign: a double finish.** `WatchConditioningRunViewModelTests`'s
recovered-session test began failing every run: the fake recorder saw **two** finishes. When the
timeline is over, two ticks — the 250 ms loop and a manual one (or `end()`'s own tick) — could both
see `position == nil` before the finish they spawned had run. The guard lived inside the async
`finish`, which reset `isFinishing` when it completed, so the second spawned finish then saved a
second Apple Health workout. On a watch that is most likely after a crash resume, whose first tick
already lies past the end. Fix: `claimFinish()` takes the one finish synchronously, before any
suspension point (in `tick()` and in `end()`, after `end()`'s own tick), and only `resetRunState()`
on the next start releases it. The test had passed before only by timing luck.

## Research findings — Apple Health / HealthKit (verified 2026-09-18)

- **Record conditioning as its own `HKWorkout`, separate from the strength workout.**
  Multi-activity sessions (`HKWorkoutSession.beginNewActivity(configuration:date:metadata:)`,
  `HKWorkoutActivity`) are hard-restricted to `.swimBikeRun`: if the original activity type is not
  `swimBikeRun` and the new type differs, the call errors. Strength → cardio is therefore not
  possible in one session. Separate workouts are also the better fit anyway: energy estimation,
  Fitness rings and Workout Effort are keyed per activity type, and the existing save/dedup flow
  assumes one app record ↔ one `HKWorkout` via `HKMetadataKeyExternalUUID`
  (`docs/healthkit-ios-workout-save.md`). Watch flow: `finishWorkout()` / `session.end()` for the
  strength session, then a new `HKWorkoutSession`.
  Sources: [beginNewActivity](https://developer.apple.com/documentation/healthkit/hkworkoutsession/beginnewactivity(configuration:date:metadata:)),
  [Dividing a HealthKit workout into activities](https://developer.apple.com/documentation/healthkit/dividing-a-healthkit-workout-into-activities).
- **Activity types per modality:** run → `.running` (`.outdoor` gives GPS route, treadmill
  `.indoor`); rower → `.rowing`; swim → `.swimming` (+ swimming location type — `.unknown` when the
  pool length is not known: `swimmingLocationType` and `lapLength` are optional, and `.pool`
  without a lap length renders oddly in Health; [HKWorkoutSwimmingLocationType](https://developer.apple.com/documentation/healthkit/hkworkoutswimminglocationtype),
  [lapLength](https://developer.apple.com/documentation/healthkit/hkworkoutconfiguration/laplength));
  an `HKWorkoutBuilder` save with zero samples is valid ([finishWorkout](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/finishworkout(completion:))); assault/air bike →
  `.cycling` indoor; sled / battle ropes / med-ball / sprint intervals → `.highIntensityIntervalTraining`;
  `.mixedCardio` only for a non-interval multi-machine circuit.
- **Profile pre-fill (ticket 03, verified 2026-09-19):** `HKHealthStore.dateOfBirthComponents()`
  (iOS 10+) throws both when read access is denied and when no birthday is set — no distinct error
  code, treat as opaque. `requestAuthorization(toShare: [], read:)` is the documented read-only
  pattern and prompts only for undecided types. Read authorization cannot be queried: denied reads
  just return empty. `NSHealthShareUsageDescription` covers characteristic and quantity reads
  alike. Resting HR: `HKSampleQueryDescriptor(predicates: [.quantitySample(type:)],
  sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)` →
  `result(for:)`, unit `.count().unitDivided(by: .minute())`. Extract plain values before crossing
  actors — Apple documents no `Sendable` conformance for `HKQuantitySample`.
  Sources: [dateOfBirthComponents()](https://developer.apple.com/documentation/healthkit/hkhealthstore/dateofbirthcomponents()),
  [requestAuthorization(toShare:read:)](https://developer.apple.com/documentation/healthkit/hkhealthstore/requestauthorization(toshare:read:)),
  [HKSampleQueryDescriptor](https://developer.apple.com/documentation/healthkit/hksamplequerydescriptor).
- **Live heart rate:** the watch is the reliable source (`HKLiveWorkoutBuilder` statistics in
  `workoutBuilder(_:didCollectDataOf:)`, already used by `WatchHealthKitManager`). iPhone-originated
  `HKWorkoutSession` exists since iOS 26 but the phone has no HR sensor — HR only with a Bluetooth
  strap or AirPods Pro 3 / Powerbeats Pro 2 ([Apple Support](https://support.apple.com/en-us/123184)).
  With no source nothing errors; the zone UI must degrade gracefully.
- **WorkoutKit (`CustomWorkout`, `IntervalBlock`, `HeartRateRangeAlert`, `openInWorkoutApp()`) —
  rejected.** It hands the session to Apple's Workout app: no in-app UI, no completion callback, the
  result only comes back as a plain `HKWorkout` that must be re-detected, breaking the externalUUID
  dedup. `WorkoutScheduler` also had reported sync breakage ([forum](https://developer.apple.com/forums/thread/767737)).
  Custom in-app timers it is. Reconsider only for "Workout-app-only" scheduling later.
- **Watch haptics for work/rest cues** fire in the background because an active `HKWorkoutSession`
  grants runtime (no `WKExtendedRuntimeSession` needed). In the 2025 forum thread about haptics not
  firing wrist-down in Always-On, Apple DTS called the restriction as-designed *for apps without* an
  active workout session — wrist-down counts as background, and a workout session is the exception
  ([forum](https://developer.apple.com/forums/thread/772780)) — verify on device. For Always-On UI
  refresh Apple documents `TimelineView` + `isLuminanceReduced` (≤ 1 Hz with an ongoing workout);
  the runner is view-model driven like the existing rest timer.
- **One workout session at a time (ticket 06, 2026-09-21).** Starting a second `HKWorkoutSession`
  while one is active force-ends the first (its delegate gets `HKError.errorAnotherWorkoutSessionStarted`);
  it is safe once the first has reached `.ended`
  ([errorAnotherWorkoutSessionStarted](https://developer.apple.com/documentation/healthkit/hkerror/code/erroranotherworkoutsessionstarted)).
  `recoverActiveWorkoutSession()` returns the session with its original `workoutConfiguration`, so
  the activity type tells strength from conditioning on relaunch. `HKLiveWorkoutBuilder.elapsedTime`
  and the saved duration exclude paused intervals. For `.swimming`, `swimmingLocationType` and
  `lapLength` are optional properties, but whether `.unknown` is accepted at session start could not
  be confirmed from the docs — swim is therefore not offered on the watch.

## Research findings — sports-science fact-check of the source protocol (2026-09-18)

The source protocol's structure (aerobic → lactic → alactic, 3 × 4-week blocks) is defensible
(residual-training-effect logic: aerobic decays slowest, alactic fastest, so alactic peaks last).
Corrections the app content must apply:

| Source claim | Verdict | Correction |
|---|---|---|
| Training all three systems at once "dilutes adaptations" | Overstated | Each block *emphasizes* one system and *maintains* the others; mixed approaches are valid ([PubMed 18212712](https://pubmed.ncbi.nlm.nih.gov/18212712/), [8WeeksOut](https://8weeksout.com/2015/06/30/the-ultimate-conditioning-guide/)) |
| Aerobic at a fixed 130–150 BPM | Needs correction | HRmax varies ±10 bpm; 150 bpm is ~86 % HRmax at 45. Individualize: 60–75 % HRmax (HRmax ≈ 208 − 0.7 × age, [Tanaka](https://www.jacc.org/doi/abs/10.1016/s0735-1097(00)01054-8)) or 50–70 % HRR (Karvonen), plus RPE 3–4 / talk test. Nasal breathing is a cue, not a rule |
| Lactic work is "highly taxing on the CNS", "clears lactate" | Wrong physiology | Fatigue is mainly peripheral/metabolic, lactate is a fuel and buffer, not the cause of fatigue ([Robergs 2004](https://journals.physiology.org/doi/full/10.1152/ajpregu.00114.2004)). The 72 h spacing is convention → "≥ 48 h apart, never the day before sparring or heavy legs" |
| 6 s sprint / 54 s rest ×10 gives "equally explosive" reps; a full minute replenishes ATP | Needs correction | It is phosphocreatine, not ATP; PCr is ~50 % back in 20–30 s but only ~85 % after 6 min ([PubMed 7714837](https://pubmed.ncbi.nlm.nih.gov/7714837/), [PMC3524088](https://pmc.ncbi.nlm.nih.gov/articles/PMC3524088/)). 6/54 ×10 is repeat-sprint / alactic *capacity* work with declining output. True power: 5–8 s, 60–120 s rest, sets of 4–5, 3–5 min between sets. Source also contradicts itself (4–8 s vs 6–10 s) → 5–8 s |
| Drop lactic work in phase 3, sparring covers it | Conditional | Only if the athlete spars hard ≥ 2×/week |
| Hard conditioning after skill training, never before sparring | Mostly accurate, incomplete for lifters | Keep ≥ 6 h (ideally 24 h) between hard conditioning and strength work; lift first on shared days; prefer bike/rower over running; explosive power is the quality most blunted by same-session concurrent training ([Robineau 2016](https://journals.lww.com/nsca-jscr/fulltext/2016/03000/specific_training_effects_of_concurrent_aerobic.10.aspx), [Wilson 2012](https://pubmed.ncbi.nlm.nih.gov/22002517/), [2022 meta-analysis](https://pubmed.ncbi.nlm.nih.gov/35476184/)) |

**Corrected default protocol**

- *Setup:* HRmax = 208 − 0.7 × age or a measured value; optional resting HR enables Karvonen; RPE
  always shown and is the only target for users on HR-affecting medication (beta-blockers).
- *Weeks 1–4, aerobic emphasis:* 2–3 × 30–60 min at 60–75 % HRmax (50–70 % HRR), RPE 3–4, talk test;
  bike, rower, swim or run. Maintenance: 1 × week 4–6 × 8 s bursts at RPE 8, 90 s rest.
- *Weeks 5–8, lactic emphasis:* 1–2 × week, ≥ 48 h apart: 30 s on / 2 min off × 6–8 or 45 s / 3 min
  × 4–6 at RPE 9 ("hard but repeatable"); keep 1–2 aerobic sessions. Beginners start at the low
  round count.
- *Weeks 9–12, alactic emphasis:* 2 × week, 5–8 s maximal, 60–120 s rest, 2–3 sets × 4–5 reps,
  3–5 min between sets — HR is not a useful target, cue maximal intent; stop a set if output drops
  ~10 %. Keep 1 aerobic session; lactic optional only for athletes not sparring hard; taper the final week.
- *Around 3–5 strength sessions a week:* easy aerobic right after lifting or on off days;
  lactic/alactic ≥ 6 h (ideally 24 h) from heavy lower-body lifting and from sparring; hard sparring
  counts as a lactic session; at most 2 truly hard conditioning sessions a week.

**Safety content the app must show** ([ACSM pre-participation](https://pubmed.ncbi.nlm.nih.gov/26473759/)):
medical disclaimer + "consult a physician" for inactive users or those with cardiovascular,
metabolic or renal disease/symptoms (all lactic/alactic work counts as vigorous); HRmax is an
estimate; HR zones invalid on beta-blockers → RPE; stop on chest pain, dizziness or unusual
breathlessness; no all-out sprints for beginners before ~4 weeks of base (offer an 85–90 % option);
thorough warm-up before sprints, prefer bike/rower for maximal efforts; no hard conditioning during
a weight cut or while dehydrated.

**Marketing claims.** Defensible: "structured, evidence-informed conditioning periodized for combat
sports", "guides intensity with your own heart-rate zones", "designed to fit around your lifting",
"consistent training improves aerobic fitness and repeat-sprint ability", and conditional promises
("follow the plan consistently and you should see measurable improvements"). **Never:** guaranteed
outcomes or numbers ("never gas out", "+X % VO₂max"), "flushes lactic acid", "zero effect on your
gains", medical/safe-for-everyone claims, or implied endorsement by named coaches.
