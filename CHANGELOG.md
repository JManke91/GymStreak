# Changelog

All notable changes to GymStreak are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.3] - 2026-07-10

### Added

- Redesigned Routines tab: a new "Up Next" hero card highlights the routine you haven't trained in the longest, and routine cards now show muscle groups, set totals and an estimated duration.
- Duplicate a routine from its menu (or by long-pressing a routine in the list).
- Redesigned Exercises tab: search, muscle-group and equipment filters, exercises grouped by muscle group, and a per-exercise "used in N routines" count.
- Redesigned exercise detail screen with a clearer info card and a "Used In" list showing where each exercise appears.
- Redesigned new/edit exercise sheet with a live preview of the exercise as it will appear in your library.
- Plan each routine on a schedule — either a rolling cadence (every N days) or fixed weekdays — from a new "Schedule" section on the routine screen. When planning on an interval you can pick the date the cadence starts from.
- Routine cards and the "Up Next" card now show when a routine is next due (and highlight overdue ones).
- Set a rep-range goal ("Rep goal") for alternative exercises too, not just the main exercise, including the per-set progress badge, carrying over when you swap to that alternative during a workout.
- Tap the "Alternatives" chip on an exercise to open a quick list of its alternatives and jump straight to one.
- Experimental: an on-device AI chat for questions about your training — next workout, PRs, weekly stats. Turn it on in AI Coach settings → Experimental.

### Improved

- Your weekly workout goal in the Trainings tab is now calculated from your planned routines instead of a fixed number, so it adapts to how many sessions actually fall in the current week. The week strip now marks planned days too.
- Alternative exercises are now easier to manage: they appear as a section right inside the expanded exercise, edit in place, and no longer take over the whole card or trap you in a separate mode.
- Smoother, more natural expand/collapse animations for exercise and set cards on the routine screen.
- An exercise and its alternatives now show as pills at the top of the expanded card, and the card shows only the one you tap.
- The Coach analysis on a past workout now leads with the real story (new personal record, or how many exercises improved), and each exercise line states the concrete change vs. last session. It also recognizes cut-short sessions and skipped exercises.
- The Coach recap (Rückblick) has been reworked: the headline now leads with your strongest strength gain instead of total volume, trends are stated without contradictions, training consistency is part of the analysis, and stagnation gets one concrete recommendation.
- The main exercise and its alternatives now use one identical layout in the expanded routine card, and you can add sets inline for the main exercise too.
- The experimental AI coach chat now remembers your conversation across app restarts — "New chat" still starts fresh.

### Fixed

- Opening a workout with a PR badge from history now shows exactly which record you set, with the exact set that achieved it highlighted. This also fixes the per-exercise PR badge, which previously never appeared on the workout detail screen.
- You can now swipe back from a recorded workout to History using the standard iOS gesture.

## [1.1.2] - 2026-07-03

### Added

- AI Coach Period Recap: tap the new "COACH · RÜCKBLICK" card in the Trainings tab to open a full-screen AI-generated monthly (or weekly/yearly) recap with streaming narrative, trend analysis, correlation callout, and stat strip.
- Period range switching: tap the chip strip at the top of the recap screen to switch between This Week, Last Week, This Month, Last Month, Last 3 Months, and This Year.
- Proactive monthly prompt: on the first open after a month boundary, a large card prompts you to view the previous month's recap — dismiss with "Später" or open with "Jetzt ansehen".
- Cache indicator: when a recap was previously generated it loads instantly with an "Aus Cache" label and a "Neu generieren" link to refresh.
- AI Coach (iOS 26+ / Apple Intelligence): post-workout recap on the save screen, monthly recap from the History tab, Ask-the-Coach analysis on exercise charts, and new workout detail analysis. Generated on-device — data never leaves the device.
- Workout detail AI Coach: tap "Ask the Coach" on any past workout to get an AI analysis comparing it against your previous session of the same routine — highlights progress, stagnation, and PRs.
- Apple Watch routine overview: the exercise list now shows planned sets inline (e.g. "3 × 10 @ 80 kg"), so you can review your plan before starting without entering the workout.
- Recover missing Watch workouts: if a workout is still missing, the History tab shows an "Add to history" button that rebuilds it from Apple Health and your routine.
- Edit past workouts: open any workout in History and tap the edit (pencil) button to correct reps, weight, completion or rest time, and add or delete sets. On save you can optionally push the corrected values back to the routine template — which then updates on both iPhone and Apple Watch for your next workout.
- Apple Watch Ultra Action Button: during a running workout, press the Action Button to complete the current set and jump to the next one — no screen tap needed. During a rest period the press skips the rest. Setup: watch Settings → Action Button → Workout → select GymStreak.
- Double Tap to complete sets: on Apple Watch Series 9/10 and Ultra 2/3, the Double Tap gesture (tap thumb and index finger twice) now completes the current set during a workout.
- Alternative exercises: define backup exercises for any routine exercise (e.g. Dumbbell Press for Bench Press) and swap to one mid-workout on iPhone or Apple Watch when the equipment is busy — the swap is only offered before the first completed set.
- Alternatives everywhere you add exercises: you can now pick alternatives directly while adding an exercise to a routine or creating a new routine (new "Alternative Exercises" section below the sets), not just afterwards from the routine — and exercises without alternatives now show a subtle "Add Alternative" hint on their routine row.
- Set reps and weight per alternative: right after picking an alternative, its sets expand inline on the same page so you can define its own reps, weight and rest time — no extra screen. Alternatives take over the main exercise's sets and reps, the weight starts empty. Changing a value shows an "apply to all sets" banner, and you can tap any alternative later to adjust it.
- Alternatives visible in the routine: expanding an exercise now lists its alternatives below the sets — tap one to edit it directly, without going through the ⋯ menu.
- Swap on Apple Watch made visible: during a workout the set screen now shows a "Swap" button whenever an exercise has alternatives and no set is completed yet — and exercises with alternatives are marked in the workout's exercise list (swipe or long-press still works too).

### Improved

- Watch readability: larger, clearer labels for the rest timer and workout metrics — the "Rest" and total-time labels, heart rate (BPM) and calories (kCal) are now easier to read at a glance during a workout.
- Clearer workout comparison: the "Ask the Coach" analysis on a past workout now shows a scannable breakdown — a one-line summary plus per-exercise rows with up/down indicators for progress, decline, or stagnation — instead of a long text block.
- Smoother Coach loading: tapping "Ask the Coach" now responds instantly with a loading card that fills in as the analysis is generated, instead of nothing happening for a few seconds.
- Clearer exercise swapping during a workout: the circle-arrows icon on iPhone is now a labeled "Swap" button, and choosing an alternative opens a compact list showing each option's muscle group and its own sets and reps (e.g. "Chest · 3×10"). Once a set is completed, the button turns into a lock that explains swapping becomes available again if you un-complete the set — and after a swap, tapping the "Swapped from" note takes you straight back to revert.

### Fixed

- Watch workout sync reliability: fixed a bug where a workout recorded on the Watch could be saved to Apple Health but never appear in the app, leaving a "waiting for sync" message that re-opening the Watch couldn't clear. The Watch now keeps each workout until the iPhone confirms it saved.
- Watch sync accuracy: fixed a false "workouts pending sync" warning that could appear right after a Watch-only workout while the data was still on its way to the iPhone — and if you recovered such a workout too early, the exact reps and weights from the Watch now replace the rebuilt estimate once they arrive instead of being lost.
- iCloud sync repaired: a bug introduced with the alternative-exercises feature silently disabled iCloud sync at app start (all data stayed local-only). Routines and workout history now sync across devices again.
- Clearer delete confirmation: deleting an exercise that isn't used in any routine no longer shows an empty "used in the following routines:" message — it now shows a simple confirmation instead.
