# Changelog

All notable changes to GymStreak are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.8] - 2026-08-14

### Added

- Apple Watch: turn the Digital Crown during a rest to change the rest duration in 5-second steps; the new duration applies to the rest of that exercise.
- Apple Watch: after adjusting a rest with the Crown, a short "This rest / All sets" prompt lets you keep the change for the running rest only.
- Apple Watch: long-press the small rest pill to adjust the rest right there — it grows into a -15 / +15 stepper (the Crown still works too) and shrinks back after 3 seconds. Note: long-pressing the pill no longer skips the rest; tap it to open the timer and use Skip.
- Apple Watch: a rest duration you changed during a workout can now be saved into the routine — finish with "Save & Update Template" and the new rest time applies to that exercise on your iPhone too; choose "Save (Don't Update)" to keep it for this workout only.
- Apple Watch: the rest screen now says so — "Turn = duration" appears above the countdown for the first 2 seconds of every rest, so the Digital Crown adjustment is no longer a hidden gesture.
- New "Settings" tab: the app now has a fourth tab with a gear icon where all app settings live. It starts with the AI Coach settings, which used to sit behind the gear icon in the History tab.
- Settings: the new "Data" section shows your iCloud sync status at a glance — up to date, syncing, waiting for network, or off — with the time of the last successful sync.
- Settings: a new "Support" section with a "Rate app" row that takes you straight to the App Store review page for Gym Streak.
- Settings: a new "Contact support" row opens your mail app on a prepared message to support, with app version, iOS version, device model and language already filled in. No workout or health data is ever included, and nothing is sent until you send it yourself.

### Improved

- Progress charts: opening an exercise chart, switching the time range (1W/1M/3M/1Y/All) or picking another exercise no longer freezes the app while the data is gathered. The chart loads in the background and shows a spinner while it works — most noticeable if you have a long workout history.
- AI Coach chat: the app no longer stutters while the coach looks up your data mid-answer. Questions about your next workout, a personal record or your history are now gathered in the background, so scrolling and typing stay smooth while the reply streams in — most noticeable if you have a long workout history.
- Finishing a workout and opening a past workout no longer freeze while the "vs. last time" comparison is put together. The lookup now runs in the background — most noticeable if you have a long workout history.
- During a workout, the "increase weight?" suggestion no longer disappears the moment you tick off the last set. It now sits above the rest bar, names the exercise it belongs to, and stays there until you increase the weight or dismiss it.

### Fixed

- Apple Watch: fixed the workout and rest-timer screens being cut off on the smallest watches (40 mm, e.g. Apple Watch SE) — the Complete button, the set chevrons and the Skip button now stay fully on screen.
- Rest timer: reopening the app while a rest is still running no longer leaves two countdowns on the Lock Screen — the old one is cleared and only the live one remains.
- Exercise library: fixed the built-in exercises staying missing on a device that once recorded them as installed but has an empty library (for example after a reinstall while iCloud data was unavailable). The app now restores the roughly 100 default exercises once it is sure iCloud has nothing left to deliver — libraries you have already set up are never touched.
- Fixed the per-exercise comparison on the save screen when a routine trains the same exercise twice (for example heavy first, high-rep later): the two entries could share one row instead of showing separately.
- AI Coach intro screen: the feature descriptions were cut off mid-sentence on the welcome screen (most visible in German). The text is now shown in full, and the screen scrolls if it does not fit.

## [1.1.7] - 2026-08-10

### Added

- Tapping a reps or kg value opens a keypad with quick steps (+/- 2.5 and 5 kg), the planned value for reference, and an option to apply the change to all following sets. The set list no longer jumps around while you edit.
- Each set has a new menu with Duplicate set and Delete set.
- If a routine change you accepted on your watch can never be applied, the watch now tells you: a notice appears on the routine list with the reason, and stays until you dismiss it. Changes that are simply still on their way to your iPhone stay silent, as before.
- Breaking up a superset is now as quick as creating one: a scissors button sits on the connecting line between two linked exercises. Tap it to split the group at that point — a pair is dissolved, a longer superset splits into two, and an exercise left on its own becomes a normal exercise again.
- The rest timer now offers presets and fine steps instead of a slider, and you can set a rep goal (e.g. 8-12) while adding the exercise instead of afterwards. Exercises added during a running workout can get a rep goal too.

### Improved

- The active workout screen has been redesigned. Only the exercise you are currently on is expanded; every other exercise collapses to a compact row you can tap to open.
- Checking off a set and editing its values are now separate targets: the left column of a set row logs the set, the reps and kg chips open an editor. No more mistaps.
- Progress in the header now shows one segment per set, grouped by exercise, so you can see where you are in the workout at a glance.
- Rest no longer takes over the screen. A rest bar sits above the workout buttons with +30s and Continue; tap it if you want the large timer.
- Exercises in a superset now always sit next to each other in the routine. Linking exercises that are far apart pulls them together at the position of the first one, and existing routines are tidied up the next time you open them.
- In sorting mode a superset now moves as one block: it is shown as a single grouped row, dragging it takes all its exercises along, and nothing can be dropped between them.
- In a routine, a superset now connects its exercises with one continuous line in the group colour, running from the first dot to the last across the gaps between cards. The line stays connected when you expand or collapse a card.
- The "Link superset" control between two exercises now carries a label and a much larger tap area, so it is easier to see and to hit.
- The screen for adding an exercise to a routine has been redesigned. It opens with the exercise itself — avatar, muscle group and equipment — and a live summary of sets, volume and rest that updates as you configure.
- Sets are now edited right in the list with the same steppers as the routine screen, and you can still tap any number to type an exact value. Starting from scratch, three quick schemes (3x8, 3x10, 4x12) get you set up in one tap.
- Adding is now one clear button at the bottom that names the routine you are adding to.
- A watch workout and the routine update it requests are now sent to the iPhone as two separate items, so a routine update that cannot be confirmed can never hold back the workout itself.

### Fixed

- Fixed a bug where a workout finished on the Apple Watch with "Save & update template" could stay stuck on the watch and never appear on the iPhone, even though it was saved to Apple Health. Affected workouts are sent automatically the next time you open the app.
- A weight increase after hitting your rep goal now only applies to your next workout. The sets you just completed keep the values you actually lifted, on both iPhone and Apple Watch.

## [1.1.6] - 2026-07-30

### Added

- You can now delete a recorded workout directly from its detail screen via the new "..." menu in the top right.
- When you delete a workout that was also saved to Apple Health, you can now choose whether to remove it from Health as well. Exercise minutes already credited to your Activity rings stay in Health — only you can remove those in the Health app.
- Opening a recorded workout now shows a muscle map at the top: a front and back body diagram with the muscles that workout trained highlighted — solid green for the main movers, a lighter green for supporting ones. Below the diagram the trained muscles are listed by name, with the set count for each main muscle.
- The muscle map is now interactive: tap a highlighted muscle on either body — or its name in the list below — to see how many sets it got and which exercises trained it. The other muscles dim while one is selected; tap it again or "Reset" to go back. Untrained muscles are not tappable. With VoiceOver, every muscle on the diagram is announced by name and state.
- On Apple Watch, finishing all sets of an exercise at the top of its rep range now offers a weight increase right there in the workout. One tap applies the default +2.5 kg to every set, "Change" lets you dial in any step with the Digital Crown — in 0.25 kg increments, with the common plate steps one tap away — and "Later" keeps the suggestion for the workout summary. The increase applies to your routine for the next workout — the sets you just recorded stay exactly as you performed them.
- The Watch workout summary now offers the weight increase directly: every exercise finished at the top of its rep range gets an "Increase weight" button in the recap, so a suggestion you tapped "Later" on is not lost. It uses the same picker and applies from your next workout.

### Improved

- The History tab now opens noticeably faster and responds to taps right away, even with a long workout history. Scrolling the Trainings list, switching between Progress and Trainings, and the calendar view should all feel smoother.
- Watch weight increases work without your iPhone nearby: the change is saved on the Watch and syncs to the iPhone as soon as it is reachable. If you changed the same exercise on the iPhone in the meantime, the iPhone version wins and the Watch updates itself.
- Swapping to an alternative exercise on the Watch now uses that alternative's own rep range, so the weight-increase suggestion matches the exercise you actually performed.
- Weight increases now also offer a smaller +0.5 kg step, on both iPhone and Watch, and the +1.25 kg option no longer displays as "1.2 kg".
- The weight-increase prompt on the Watch is now a proper full-screen card instead of a panel floating over the workout, so the buttons underneath can no longer be hit by mistake.
- The routine detail screen has been redesigned. Sets are now edited directly in the card — every set row has minus/plus buttons for reps and weight, and you can still tap a number to type an exact value. There is no more tapping a set open first.
- Rest time and rep goal are now chips on every exercise card. Tap "Pause" or the rep goal to adjust it right there, whether the card is open or closed — presets, a fine stepper, and switching the rest timer off entirely.
- Alternative exercises are now a list inside the exercise card instead of a separate switcher. Tap an alternative to edit its own sets, rest and rep goal in place. On the closed card the alternatives show as small overlapping icons next to the exercise name.
- The "Edit" button is now "Sort": it shows a compact list for dragging exercises into order and removing them. Removing an exercise no longer asks for confirmation — an "Undo" toast appears instead for a few seconds.
- Each exercise card now summarises its sets as e.g. "4 x 8 reps - 100 kg" instead of just the set count.
- The exercise "..." menu no longer offers "Edit Sets". Sets are already fully editable in the opened exercise card, and that entry only replaced those controls with a weaker list. Note this also removes reordering the sets within an exercise.

### Fixed

- On assisted (counterweight) exercises, the Watch confirmation now correctly says the assistance was reduced instead of claiming the weight went up.
- Fixed: in the routine's "Sort" mode, dragging an exercise to a new position left it greyed out and made the whole list undraggable until you left the screen. Reordering now uses the system list reorder and works repeatedly.
- Applying from the summary never alters the workout you just finished — your recorded sets stay exactly as performed, no second workout is created, and iPhone History no longer re-offers an increase you already made. Increases applied during the workout show as done instead of being offered again. On pyramid/drop sets the Watch now says all sets were adjusted rather than showing one misleading weight.

## [1.1.5] - 2026-07-25

### Added

- The workout completion screen now lets you act on achieved rep goals: exercises that hit the top of their rep range show an "Increase Weight" card — pick an increment and your routine is updated for next time, with an Undo option.
- You can now apply a weight increase after the fact: opening a past workout that maxed a rep range shows the "Increase Weight" card, and applying updates your routine for next time (your saved workout history stays unchanged).
- Exercises added during a workout can now be configured with the exact number of sets, reps, weight, and rest time before they join the session.
- Exercises added or removed during a workout can now be saved back to the routine for future workouts when "Update Routine Template" is enabled.
- Apple Watch: add or remove exercises during an active workout, with set, rep, weight, and rest configuration before adding.
- Apple Watch: exercises you add or remove during a workout now also update your routine for future workouts when you choose "Save & Update Template" — additions keep their sets, reps, weight, and rest, and any routine changes you made on iPhone in the meantime are preserved.
- Apple Watch: completing your last set now finishes the workout automatically and shows the summary — no need to go back and press Finish.
- Apple Watch: if you changed any sets during the workout, auto-finishing still asks whether to update your routine template before saving.
- Apple Watch: if the Watch app is closed or relaunched during a workout, it now recovers the in-progress workout — reconnecting the live Health session and restoring your exercises, sets, and progress — so you can carry on without losing anything or creating a duplicate.
- Apple Watch workouts that never reached your iPhone (e.g. the app was reinstalled or unpaired) are now detected more reliably in the background and offered for recovery on the History screen; recovery stays optional, only adds to history, and is automatically replaced by the full workout if it later arrives.

### Improved

- The full rest timer now opens as a full-screen view layered over your workout (instead of a bottom sheet); minimize it to the compact banner at the top and tap that banner to reopen it.
- The rest timer now morphs smoothly between its large and compact states: minimizing shrinks the countdown ring and time into the top banner, and tapping the banner grows them back — no more hard cut between the two.
- Rest-timer notifications are requested only when needed, stay aligned with the actual countdown, and show a warning when alerts are unavailable.
- Apple Watch: the active-workout screen now shows which exercise you are on ("Exercise 2 / 5") above a neutral progress bar, with the exercise name and a "Set 1/3" counter right above the values — green is now reserved for the current set only.
- Apple Watch: the +/- buttons now move to sit above whichever value (weight or reps) you're editing, swapping sides with the heart-rate/calorie readout.
- Apple Watch: on your final set the complete button now reads "Finish Workout" so you know the tap will end the workout.
- Apple Watch: the workout Complete button is now a clean, larger checkmark (no text label), and the set controls and spacing were refined so everything stays comfortably inside the screen edges.
- Apple Watch: the total workout time moved out of the top bar (where it overlapped the clock) into the workout screen next to the exercise counter, larger and easier to read; the rest-timer countdown now appears in that same spot while you rest.
- Apple Watch: the minimized rest timer is now a single small pill in the same top-right spot on every workout screen — exercise list, metrics, controls and the set editor — so it no longer appears twice or pushes your workout content down.
- Apple Watch: the rest timer now morphs between its two states — minimizing shrinks the full-screen countdown into the small pill in the top-right corner, and tapping the pill grows it back, with the countdown running throughout.
- Apple Watch: workouts you finish on the watch now reach your iPhone history far more reliably — a completed workout is saved durably before it's sent and retried until confirmed, including when the iPhone was powered off or out of range.
- Apple Watch: closing an in-progress workout now asks whether to save or discard, and always stops the underlying Health workout so it can't keep running in the background or block starting a new one.
- Apple Watch: "Save & Update Template" now updates the routine immediately on both iPhone and an already-open Watch app, keeps rapid updates in order, and no longer leaves already-saved workouts falsely listed as waiting to sync.
- Apple Watch Ultra: pressing the Action Button during a rest timer now stops that timer, completes the next set, and starts the following rest timer in one press.
- Apple Watch: multiple offline workouts saved with "Save & Update Template" now continue syncing to iPhone history without reopening the Watch app.

### Fixed

- Fixed workout progress comparisons when the same exercise appears multiple times or shares its name with another equipment variant.
- Applying a weight-increase suggestion from the routine editor on assisted exercises (e.g. assisted pull-ups) now reduces the assistance weight as shown, instead of increasing it.
- Weight-increase suggestions now also work for swapped (alternative) exercises — the mid-workout "Increase" button responds again, and applying updates the alternative's own sets in your routine.
- Apple Watch: fixed a freeze when finishing your last set (including via the Action Button) — the workout summary now appears immediately instead of waiting on the Health save.
- Apple Watch Ultra: fixed the Action Button failing with "Complete Set failed" — pressing it now completes the set instantly, even from the watch face.
- Apple Watch: fixed workout syncing getting stuck after restarting the iPhone; normal reachable sync and offline recovery now coexist safely.
- Apple Watch: fixed a brief flash of an empty "no exercises" screen when discarding a workout or closing the summary — the screen now slides away cleanly.
- Apple Watch: the workout set navigation arrows are no longer clipped by the screen corners on Apple Watch Ultra — the bottom row now stays inside the safe area.

## [1.1.4] - 2026-07-12

### Added

- The AI coach chat is no longer experimental — meet your always-available coach: a floating "Ask your coach" bar above the tab bar opens the chat from anywhere in the app with a fluid zoom animation. On an exercise's progress screen, it suggests questions about that exercise. It can be turned off in the AI Coach settings like any other coach feature.
- Apple Watch: the routine list now shows your next workout at the top — the next planned workout if you set up a schedule, otherwise the routine you haven't trained the longest — with a quick-start button to jump straight in.
- The Apple Watch app is now fully available in German (routine list, live workout, rest timer, workout summary, and rest notifications).
- The app now comes with a built-in library of around 100 common exercises (barbell, dumbbell, machine, cable, and bodyweight). They are added to your existing library too — exercises you already created yourself are detected and not duplicated.

### Improved

- The experimental AI coach chat is more reliable: rare "Something went wrong" bubbles are now retried automatically, and the coach is stricter about answering only from your actual data (no more invented clock times or streak lengths).
- Creating a new routine now uses the same modern exercise picker as editing an existing routine — with search, "already added" markers, inline set configuration, alternatives, and creating a new exercise on the spot.
- The exercise picker for routines now has the same muscle-group filter pills as the exercise library — tap a muscle group (or combine it with search) to narrow the list, in both the new-routine and edit-routine flows.
- Apple Watch: set navigation and progress are now clearly separated from the Complete/Undo action, so you can browse sets without mistaking Next for completion.
- Apple Watch: eligible exercise rows now have a visible Swap button, while the set editor keeps total elapsed/rest time visible and uncluttered.
- Apple Watch: the workout screen has a new look — a glass-style Complete button that fills up with your set progress, round set-navigation buttons beside it, shared +/− buttons with live heart rate and calories next to the weight/reps cards, a brief green "Done" celebration when an exercise is finished, and a calmer elapsed-time chip at the top.

### Fixed

- Assisted exercises now track progress correctly: reducing machine assistance counts as improvement, and you can record your body weight for a more accurate effective-load calculation.
- The "How the Coach works" and "About Apple Intelligence" rows in the AI Coach settings now respond to taps anywhere on the row, not just on the text.
- The keyboard in the exercise search can now be dismissed with a "Done" button directly above the keyboard (also next to the search field, or by dragging the list) — previously only the return key would close it.
- Swiping in from the left edge now goes back on a routine's detail screen, same as everywhere else in the app — previously only the back button worked.
- Choosing "update routine" after a workout now also saves your new weights and reps when you swapped an exercise for one of its alternatives — previously the alternative's values in the routine stayed unchanged (on Apple Watch workouts and iPhone workouts alike).

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
