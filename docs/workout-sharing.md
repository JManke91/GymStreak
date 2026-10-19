# Workout Sharing

Share a just-finished workout as a story-sized image: a 1080 × 1920 card with the muscle map, the
new personal records and the headline stats, plus a line of text that carries the App Store link.
It is acquisition lever #5 (`docs/acquisition-strategy.md` §4.5): every posted card is an ad seen
by the user's friends.

**Status:** sharing from the **workout completion screen** (2026-10-19, `.scratch/share-screen/`
ticket 02) and from a **History workout detail** (2026-10-19, ticket 03) shipped. Sharing a
**fight-conditioning session** (ticket 04, "Sharing a conditioning session" below) was built
2026-10-19; the user confirmed the feature finished and tested the same day.

**Targets:** iOS only. The watch target is untouched and no watch counterpart is planned.

**Tier:** Free, always — `docs/monetization-strategy.md` §3 Rule 4 (the user's own data) and Rule 1.
No `OnyxProBadge` on the card or the sheet, and nothing on the card is a Pro-gated metric.

## What the user sees

1. **Completion screen** (`SaveWorkoutView`). Directly under Summary, a card-styled row: a live
   thumbnail of the share card, "Share this workout", one line on what the image contains ("Your
   muscle map, stats and 2 new PRs as a story-ready image."), and a green **Share** button. The
   row appears once the session is read, and its PR count updates when the history check returns.
   It is hidden for a workout with no completed set.
2. **Preview sheet** (`WorkoutSharePreviewSheet`). A close button, "Share workout", the live card
   at 270 × 480, five layer chips and one green **Share** button. The chips:
   - **Muscles**: the callouts. Off, the figures grow from 200 to 280 pt wide.
   - **PRs**: the Personal records section and the PR tags on the callouts.
   - **Stats**: duration, sets, and volume.
   - **Exercises**: one line naming every exercise. Off by default, but on for a one-exercise
     workout, where it reads "Back Squat · top set 140 kg × 3".
   - **Weights**: off, PRs show reps only ("5 reps"), the volume stat becomes the exercise count,
     and a one-exercise line reads "Back Squat · 5 sets". This is for people who don't want to
     post their numbers.

   Below the chips are two buttons: **Save** (secondary, dark capsule) next to the green
   **Share**. Save writes the card straight to Photos and turns into a green "Saved" ✓. It
   resets when a chip changes, because the card on screen no longer matches the saved image.
3. **History workout detail** (`WorkoutDetailView`). The same share row as the completion screen,
   directly under the muscle map, plus a share icon (`square.and.arrow.up`) in the top-right
   toolbar group, left of the `…` menu. Both appear on every recorded workout, logged or imported
   from Strong or Hevy, and are hidden when the workout has no completed set. Both open the same
   preview sheet.
4. **System share sheet** (`UIActivityViewController`) with the rendered PNG and the text
   "Tracked with GymStreak: <App Store link>". Instagram, WhatsApp, Messages and Save Image all
   work from it.

Sharing **never saves or alters the workout**. The completion screen is pre-save
(`docs/workout-summary.md`); the card is built from the in-memory session and nothing in the share
path writes to it. Cancel still discards the workout, and Save still commits it, as before.

## The card

Built from the approved design (below) exactly. Top to bottom, with 56 pt between sections inside
the Instagram-safe area (250 pt free at the top, 300 pt at the bottom):

- **Header:** date line ("SUNDAY · 18 OCT", 24 pt, tracking 3, uppercased) and the routine name at
  120 pt heavy (one line, scales down for a long name). An unnamed workout reads "Workout".
- **Stage:** the front and back `MuscleFigureView`s, with one **callout** per *primary* region:
  green dot on the muscle's outer edge, a leader line, the short region name and "N sets", plus a
  black-on-green **PR** tag when a record was set by an exercise that trains that muscle first.
  Secondary regions only get the softer fill. The callout names are the design's gym names where
  they differ from the region names: Lats, Quads, Traps (de: Latissimus, Quadrizeps, Trapez).
- **Personal records:** "2 NEW PERSONAL RECORDS", then a `#1C1C1E` card with one row per record
  (trophy in a green 14 % circle, exercise, value such as "100 kg × 5" in green).
- **Stats:** duration (min), sets (completed), and volume (whole display units, grouped, never
  rolled up to tonnes: "8,940 kg").
- **Exercise line** (when on).
- **Footer:** green dot + wordmark, and "Tracked on iPhone & Apple Watch".

Units follow the user's weight-unit preference (`WeightFormatting`, kilograms stay canonical).
The card is always rendered in dark mode and uses fixed point sizes, so Dynamic Type never
changes the image.

### Decisions the design didn't specify

- **At most two record rows.** Two rows plus the stats fill the safe area exactly; a third pushes
  the footer into the bottom margin. The section label still counts every record ("3 new personal
  records"), and every PR muscle still gets its tag.
- **Overflow behaves like the design's HTML.** When content is taller than the safe area (Muscles
  off with PRs and stats on), it runs into the bottom margin instead of shrinking the title and
  stats. The content block is `fixedSize` vertically for that reason. Without that, SwiftUI scaled
  the title down through `minimumScaleFactor`.
- **Callout order** is heaviest set count first, so when a muscle visible on both figures (such as
  shoulders or forearms) picks the emptier column, the bigger muscles pick first.
- **PR tag placement** uses the record exercise's *first* muscle group, mapped to a region. That
  is the same "primary mover" rule the muscle map uses.
- **Trophy** is the SF Symbol `trophy`, not the design's hand-drawn SVG.
- **Chips wrap left-aligned** using the app's existing `FlowLayout`. The design centres each row;
  the block as a whole is centred.
- **Chips never change width.** The ✓ is always laid out and only fades in. When it was inserted
  on toggle, the wider chip made `FlowLayout` move its neighbours between rows mid-animation
  (found on device, 2026-10-19).
- **Chips that would change nothing aren't offered** (user feedback, 2026-10-19). **PRs** is
  hidden when the workout set no record, following the design's precedent of hiding the Heart rate
  chip on the conditioning card. **Weights** is dimmed and disabled while none of the things it
  changes are visible: the stats, the record rows, or a one-exercise line with a top set. It keeps
  its setting for when they come back. Both flags (`isRecordsChipShown`, `isWeightsChipEnabled`)
  are computed in `WorkoutShareCardModel.make`, never in `body`.

## Sharing a conditioning session

The conditioning variant of the card (`ConditioningCard.dc.html`), built 2026-10-19 (ticket 04).
It is the card that carries the fighter positioning (`docs/research/positioning-usp-2026-10.md` §6
step 5). Only interval and steady-state conditioning sessions (`ConditioningRecord`) share; **mat and
sparring sessions do not** (user decision, 2026-10-19: they have no rounds to draw and would need
their own variant; follow-up, not planned).

**Entry points.** Both build a fresh `ConditioningShareViewModel` on tap, await
`prepare(recordID:)` and only then present the sheet (`.sheet(item:)`), so the sheet never opens on
an empty card and chips never appear mid-animation. Link campaign `ct=share-conditioning` for both.
- **History detail** (`ConditioningRecordDetailView`): a share icon in the top-right toolbar, left of
  the trash icon, as `EntryConditioning.dc.html` places it.
- **Runner finish screen** (`ConditioningFinishedView` in `ConditioningRunnerView`): a secondary
  "Share session" button above Done, shown once the run recorded a session (ending in the warm-up
  records nothing, so there is nothing to share). This placement is not in the design; it reuses the
  screen's existing button style. It also covers the post-workout add-on, which runs the same runner.

**The card,** top to bottom (56 pt between sections, same tokens as the strength card):
- **Header:** eyebrow "MONDAY · 20 OCT · CONDITIONING", the session title (re-localized like
  History), and a subtitle: modality · "8 × 2:00 work, 1:00 rest" (steady state: "45 min"), plus a
  short effort ("RPE 9", `share_card.conditioning.effort.*`) when no heart rate is shown. The
  design's "Week 4" is left out: `ConditioningRecord` does not store the program week.
- **Round strip:** one block per planned work interval with the rests between them, widths
  proportional to time, "4 / 6" on the right and a work/rest legend. Rounds not reached (ended early)
  are faded green, as the design's `done < rounds` case draws them.
- **Time in heart-rate zone:** Z5 → Z1 bars, each relative to the longest zone, the time as m:ss.
- **Stats:** with heart rate: duration, average, maximum (bpm). Without: duration, work, rest.
- **Footer:** as the strength card.

**No-heart-rate state** (the design's `noHr`): no zone card, the strip grows from 96 to 200 pt and
names each round (R1…Rn), the stats become duration / work / rest, and the **Heart rate** chip is
hidden. Chips: **Rounds**, **Heart rate**, **Stats** (`ConditioningShareLayers`). Heart rate off
behaves like the no-heart-rate state but keeps the chip.

### Decisions the design didn't specify

- **Five zones, % of HRmax** (user decision, 2026-10-19): Z1 from 50 %, Z2 60, Z3 70, Z4 80, Z5 90
  of the heart-rate profile's maximum (estimated or measured), **also when a resting heart rate is
  set** — not Karvonen. Time below 50 % counts as Z1, so the zones add up to the measured time.
  `HeartRateZones.sessionZoneFloors(for:)`; `nil` exactly when there is no aerobic target (no or
  invalid profile, medication switch).
- **Heart rate without a profile:** the average and maximum are still shown; only the zone card
  disappears (and the strip grows, as without heart rate).
- **Steady state:** one full-width block headed "Steady state" with no value and no legend (the
  duration stat already says it), and without heart rate only the duration stat.
- **Short sprints:** every block is at least 16 pt wide (an 8 s sprint beside 90 s of rest would
  otherwise be a hairline); a block narrower than 52 pt loses its R-label. From 20 rounds the strip
  would no longer fit at that minimum and the 8 pt gap (the round timer allows up to 30), so the gap
  tightens to 4 pt and the minimum shrinks to an even share of the width (found in review). Set breaks are drawn as
  ordinary rests, because the record stores no set-break length.
- **Rest stat** without heart rate is `rest × (completed rounds − 1)`: the rests actually taken.
- **The missed rounds' R-labels** are grey instead of black, which would be invisible on faded green.

### Where the heart rate comes from

`ConditioningRecord` stores **no heart rate** (no CloudKit schema change was made for this). The
share view model reads it from Apple Health **only when the record has a `healthKitWorkoutId`** — a
user with Health sync off opted out of Health, and the card uses its no-heart-rate state.
- `ConditioningHeartRateReading` (Domain) → `HealthKitConditioningHeartRateReader` (Data): an
  `HKSampleQueryDescriptor` for `HKQuantityType(.heartRate)` with
  `predicateForSamples(withStart: record.startTime, end: record.endTime)` and **no options**, so a
  sample overlapping either edge matches; sorted by start date. **All sources**, not only samples
  associated with the workout: an iPhone-run session with a watch on the wrist has its readings
  outside any workout. It never asks for access: heart-rate read access is part of the workout
  authorization (`HealthKitWorkoutManager`). Denied and empty look the same, both mean no heart rate.
- `ConditioningHeartRateSummarizer` (Domain, pure) folds the readings: each holds its value until
  the next reading but at most **15 s** (the watch mat-session tally's cap), clamped to the window;
  the average is time-weighted; the maximum is the highest reading. **Under 50 % of the session
  measured → no summary**, because a watch outside a workout samples every few minutes and those
  numbers would describe a few stray readings, not the session.
- In practice, heart rate appears for **watch-run sessions** (the watch workout samples about every
  5 s). An iPhone-run session usually has too little coverage, and right after the iPhone runner
  finishes the Health write may still be in flight (no `healthKitWorkoutId` yet), so the finish
  screen's card is usually the no-heart-rate one. Sharing the same session later from History picks
  up whatever Health has by then.
- **Series samples:** a sample with `count > 1` carries one summary value for its span; it is
  treated as holding that value over the span. Apple Watch writes heart rate as individual samples,
  so this matters only for third-party sources. Reading per-reading values would need
  `HKQuantitySeriesSampleQueryDescriptor` (iOS 15.4+), deliberately not used.
- Research (2026-10-19, ios-api-researcher against Apple's docs): HealthKit's async query
  descriptors take no completion closure, so no `@Sendable` handler is involved.
  [HKQuantitySeriesSampleQueryDescriptor](https://developer.apple.com/documentation/healthkit/hkquantityseriessamplequerydescriptor),
  [Running queries with Swift concurrency](https://developer.apple.com/documentation/healthkit/running-queries-with-swift-concurrency).
  The watch's ~5 s workout sampling interval and the claim that the watch writes individual samples
  are the researcher's background knowledge, not confirmed in Apple's docs.

**Tier:** Free — §3 Rule 4 (the user's own logged session). No Pro badge, even though the
conditioning program has its own gate (`ConditioningProgramGatingPolicy`).

## Sharing a past workout (History)

- **Two entry points, one card.** An inline share row (the completion screen's
  `WorkoutShareEntryRow`, reused unchanged) directly under the muscle map, plus the toolbar icon.
  Both open the same prepared model. The row exists because sharing is a free acquisition channel
  and a small toolbar icon is easy to miss (user decision, 2026-10-19).
- **Not sticky, on purpose.** A pinned bottom bar was considered and rejected. This is a long
  reading screen, the bar would cover sets and comparisons on every visit, and the tab bar's
  bottom accessory is already used for the active-workout bar. An inline row high on the page
  gets the visibility without that cost.
- **When the card is built:** in `.task`, right after `loadPRs()` (and again after an edit), by
  `prepareShareCard()`, which calls `prepare(session:weightUnit:knownRecords: prDetails)`. Those
  are History's own PR details for this workout, same rule and same shape (keyed by
  `WorkoutExercise.id`), so **no second history walk** happens. The only extra main-actor work is
  one bounded read of this session, the same `loadMuscleMap()` makes, plus building the card
  model. This screen shipped a 630 ms hang once (`docs/history-performance.md`), so a
  history-wide walk here would not be acceptable.
- **Toolbar tap before the card exists** (while the PRs still load): `presentShare()` falls back to
  a fresh model that fetches its own PRs through `PersonalBestsProviding`, off main.
- **Edits:** `reloadAfterEdit()` rebuilds the card after `loadPRs()`, so a share after
  "Edit workout" shows the edited workout. The chips reset to their defaults. An edit that removes
  every completed set clears the card, so the row disappears instead of showing the old workout.
- **Presentation:** `.sheet(item:)` on the view model itself (`sharePreview`). The first version
  used `.sheet(isPresented:)` plus a separate optional view model set in the same tap, and the
  first tap showed an **empty sheet**, because the sheet content was built from the still-nil
  value. The second tap worked because the first tap's model was still there (found on device,
  2026-10-19).
- **Visibility:** `isShareable` (any completed set) is computed in `loadExerciseGroups()` from the
  already-built exercise rows, so `body` reads no extra model property. It gates both the row and
  the icon.
- **Deletion:** `prepareShareCard()` and the button are no-ops once `isBeingDeleted` is set.
  `prepare` reads the session only before any `await`, so a delete during the PR walk can't fault
  it.
- **Link:** `ct=share-history` (`SupportLinks.Campaign.shareHistory`). The campaign is an init
  parameter of the view model, passed by each entry point through
  `AppDependencies.makeWorkoutShareViewModel(campaign:)`.

### PRs for a past workout

The card shows the PRs **as of that workout**, not today's records. No new computation was
needed: `prepare` already asks `PersonalBestsProviding.fetchPersonalBests(before: startTime,
excludingSessionID:)` for the best estimated 1RM per exercise over sessions that *started
earlier*, and `PersonalRecordService.records(from:priorBests:)` keeps the exercises that beat it.
That is the same rule `PersonalRecordService.computePRs` applies when it walks history
chronologically, so the card's records match the PR badges the History detail already shows for
that workout. A later workout that beat the record doesn't remove it from the earlier card.

Known edge: two sessions with the same `startTime` don't count each other as "earlier". Both can
show the same record. This is the same strict-`<` boundary the completion screen uses.

## Architecture

```
SaveWorkoutView ── .task ──▶ AppDependencies.makeWorkoutShareViewModel()
      │                              │
      │                     WorkoutShareViewModel (@Observable @MainActor)
      │                       ├─ prepare(session:weightUnit:)
      │                       │    reads the session once (bounded) ─▶ WorkoutShareSource (values)
      │                       │    await PersonalBestsProviding.fetchPersonalBests  (off main)
      │                       │    PersonalRecordService.records(from:priorBests:) ─▶ records
      │                       ├─ layers (didSet ─▶ WorkoutShareCardModel.make)
      │                       └─ renderImage() ─▶ ImageRenderer, scale 1, dark
      ├─ WorkoutShareEntryRow(card:subtitle:)
      └─ .sheet ─▶ WorkoutSharePreviewSheet ─▶ .sheet ─▶ ActivityShareSheet (UIActivityViewController)
```

| File | Layer | Role |
|---|---|---|
| `Presentation/ViewModels/Share/ShareCardPreviewing.swift` | Presentation | What the preview sheet needs from either card's view model, `ShareSaveState`, and the shared Save-to-Photos flow (`saveImage()`, `cardDidChange()`) and share line |
| `Presentation/ViewModels/Share/WorkoutShareViewModel.swift` | Presentation | Reads the session, fetches the PR bar, owns the layers, renders the image, holds the share text |
| `Presentation/ViewModels/Share/ConditioningShareViewModel.swift` | Presentation | Reads the conditioning record, reads its heart rate from Health, owns the layers, renders the image |
| `Presentation/Views/Share/ConditioningShareCardModel.swift` | Presentation | `ConditioningShareSource`, `ConditioningShareLayers`, and `ConditioningShareCardModel.make` (strings, block widths, zone rows, stats) |
| `Presentation/Views/Share/ConditioningShareCardView.swift` | Presentation | The conditioning card; reads only `ConditioningShareCardModel` |
| `Presentation/Views/Share/ConditioningSharePreviewSheet.swift` | Presentation | The shared sheet with the conditioning card and its chips |
| `Domain/Models/Conditioning/ConditioningHeartRate.swift` | Domain | `HeartRateReading`, `ConditioningHeartRateSummary` |
| `Domain/Services/ConditioningHeartRateSummarizer.swift` | Domain | Average, maximum and time per zone of a session window; gap cap and coverage threshold |
| `Domain/Services/HeartRateZones.swift` | Domain | Gained `sessionZoneFloors(for:)` |
| `Domain/Interfaces/ConditioningHeartRateReading.swift` · `Data/HealthKit/HealthKitConditioningHeartRateReader.swift` | Domain · Data | Heart-rate readings of a time window |
| `Presentation/Views/Share/WorkoutShareCardModel.swift` | Presentation | `WorkoutShareSource` (values from the session), `WorkoutShareLayers`, and `WorkoutShareCardModel.make`, which localizes, formats and lays out everything the card shows |
| `Presentation/Views/Share/WorkoutShareCalloutLayout.swift` | Presentation | Port of the design's callout layout: stage geometry, anchors per region, column assignment, collision push and mean-displacement shift |
| `Presentation/Views/Share/WorkoutShareCardView.swift` | Presentation | The 1080 × 1920 card; reads only `WorkoutShareCardModel` |
| `Presentation/Views/Share/WorkoutSharePreviewSheet.swift` | Presentation | `SharePreviewSheet` (the shell both cards use: header, card, chips, Save and Share, the error alert), `ShareLayerChip`, `WorkoutSharePreviewSheet` (strength card + chips), `ShareCardScaled` / `WorkoutShareCardThumbnail`, and the `UIActivityViewController` bridge |
| `Presentation/Views/Share/WorkoutShareEntryRow.swift` | Presentation | The completion screen's row |
| `Presentation/Views/History/WorkoutDetailView.swift` | Presentation | History entry points: inline share row, toolbar icon, `prepareShareCard()`, `presentShare()`, `isShareable` |
| `Domain/Interfaces/PhotoLibrarySaving.swift` | Domain | Save-to-Photos boundary and `PhotoSaveError` |
| `Data/System/PhotoLibraryImageSaver.swift` | Data | PhotoKit add-only implementation |
| `Domain/Interfaces/PersonalBestsProviding.swift` | Domain | Read boundary: best estimated 1RM per exercise before a date |
| `Domain/Services/PersonalRecordService.swift` | Domain | Gained `sessionBests(of:)`, `records(from:priorBests:)`, `records(in:priorBests:)` and `personalBests(sessions:)`; `computePRs` is now built on them, with unchanged behaviour |
| `Data/History/SwiftDataHistorySnapshotStore.swift` | Data | `SwiftDataHistorySnapshotProvider` conforms to `PersonalBestsProviding` (`@concurrent`), same instance and model actor as History |
| `Presentation/Views/Settings/SupportLinks.swift` | Presentation | `appStoreCampaignLink(campaign:)`, `appStoreProviderToken`, `Campaign.shareSummary`, and `AppBrand.wordmark` |
| `App/AppDependencies.swift` | App | `personalBests`, `makeWorkoutShareViewModel(campaign:)` and `makeConditioningShareViewModel()` |
| `Presentation/Views/Conditioning/ConditioningRecordDetailView.swift`, `ConditioningRunnerView.swift` | Presentation | Conditioning entry points: toolbar icon, finish-screen button |

**Rendering rules** (CLAUDE.md): the card view never touches a `@Model`. Every string, number,
date and position is computed in `WorkoutShareCardModel.make`, which runs on prepare, on PR arrival
and on a chip toggle, never in `body`. The `ForEach`es in the card are bounded (≤ 13 regions, ≤ 2
records, 3 stats). `ImageRenderer` runs only from the Share button.

### PRs for a workout that isn't saved yet

`PersonalRecordService.computePRs` walks *completed* history, and the History model actor can't be
trusted to see a session the main context hasn't committed. So the check is split:

1. **Before the `await`**, on the main actor: `PersonalRecordService.sessionBests(of:)` reads the
   in-memory session's best set per exercise. This is a bounded walk of one workout, the same reads
   the summary already makes.
2. **Off main:** `PersonalBestsProviding.fetchPersonalBests(before: startTime, excludingSessionID:)`
   returns the best estimated 1RM per `stableKey` over completed sessions that started earlier.
3. **After:** `PersonalRecordService.records(from:priorBests:)` compares the two. A PR has the same
   definition as History's (Epley, strictly greater than every earlier best), so the card and the
   History detail agree once the workout is saved. Like History, a user's very first workout counts
   every exercise as a record.

Nothing reads the session after the `await`, because `cancelWorkout()` can delete it while the walk
runs.

`PersonalBestsProviding` is its own protocol rather than a new `HistorySnapshotProviding`
requirement, for the reason `LifetimeTrainingTotalsProviding` gives. It also keeps the seven test
doubles of the History protocol untouched.

## Link and wordmark

- **Link:** built only by `SupportLinks.appStoreCampaignLink(campaign:)`, next to `appStoreAppID`:
  `https://apps.apple.com/app/apple-store/id6756426105?pt=122361031&ct=<campaign>&mt=8`, where the
  campaign is `share-summary` (completion screen), `share-history` (History detail) or
  `share-conditioning` (both conditioning entry points). `SupportLinksCampaignTests` pins the format.
- **Provider token** `122361031` (`SupportLinks.appStoreProviderToken`, set 2026-10-19). It belongs
  to the developer account, not the app, and comes from App Store Connect → Analyse → Akquisition →
  Kampagnen → "Kampagnen-Link erstellen" (the `pt` of any generated link). Campaign names need no
  registration: whatever `ct` arrives is listed. Without a token the builder would return the plain
  `https://apps.apple.com/app/id6756426105`, since a `ct` is not attributed without `pt`.
- **When numbers appear:** only installs through links shared from a build with the token count,
  and App Store Connect shows a campaign only once at least **5 distinct Apple Accounts** installed
  through it.
- **Wordmark:** `AppBrand.wordmark` ("GymStreak") is the single swappable element on the card and
  in the share text, so the rename decision (lever #15) changes one line.

## Photos permission and the Save button

"Save Image" in the share sheet writes to the photo library and **crashes without
`NSPhotoLibraryAddUsageDescription`**. The app target sets it as an `INFOPLIST_KEY_` build setting
(both configurations) and translates it in `en`/`de` `InfoPlist.strings`.

**Why a Save button in the preview** (added 2026-10-19 after user feedback): posting a story from
Instagram usually means saving to Photos first, and inside the share sheet "Bild sichern" sits one
screen deeper, after Share. The direct button saves a tap and makes the option visible. A saved
image carries the wordmark but **not the link**, which only travels as share-sheet text. That was
accepted, because an Instagram story drops the text either way.

**Mechanism** (researched 2026-10-19 against the iOS SDK headers `PHPhotoLibrary.h`,
`PHAssetCreationRequest.h`; Context7 has no Photos docs):
- `Domain/Interfaces/PhotoLibrarySaving.swift`: `savePNG(_ data: Data) async throws` and
  `PhotoSaveError` (`denied`, `restricted`, `failed`). It takes PNG bytes, so no UIKit or Photos
  type enters Domain.
- `Data/System/PhotoLibraryImageSaver.swift`:
  - Calls `PHPhotoLibrary.authorizationStatus(for: .addOnly)`, then
    `await PHPhotoLibrary.requestAuthorization(for: .addOnly)` while still `.notDetermined`.
    This is add-only; read access is never asked for.
  - Saves with `try await PHPhotoLibrary.shared().performChanges { @Sendable in
    PHAssetCreationRequest.forAsset().addResource(with: .photo, data:options:) }`. That keeps the
    PNG bytes as they are (no re-encode, unlike `creationRequestForAsset(from: UIImage)`).
  - `.limited` is treated as authorized (it describes read access and isn't expected for
    add-only).
- **Threading (load-bearing):** Photos runs the change block on an arbitrary serial queue, and the
  block is not `NS_SWIFT_SENDABLE`. Without `@Sendable` it would be inferred main-actor-isolated,
  and the app would trap the first time Photos ran it (`docs/swift6-concurrency.md` §4a). The
  block lives in a `nonisolated static func` and captures only `Data`.
  - Verified at runtime: a throwaway Swift Testing probe called the saver from a `@MainActor` test
    on an iOS 26 simulator, with access granted through `xcrun simctl privacy <udid> grant
    photos-add com.shotat24fps.GymStreak`. It passed with no executor trap.
  - The `ios-api-researcher` reviewed the final code: correct.
  - `ImageRenderer` + `pngData()` stay on main. The renderer must run there, and one tap-triggered
    1080 × 1920 encode costs tens of milliseconds.
- `WorkoutShareViewModel.saveImage()`:
  - `saveState` is `idle` → `saving` → `saved`.
  - A chip change resets `saved` to `idle`, but never `saving`; resetting `saving` would re-enable
    the button mid-save, a bug found in review.
  - A save that finishes after a chip change ends `idle`, not `saved`, because the card is compared
    with the one that was rendered.
- **Errors:**
  - Denied: an alert with **Open Settings** (`UIApplication.openSettingsURLString`). The app never
    re-requests, because the system silently returns `.denied`.
  - Restricted: an informational alert.
  - Failed: "try again, or use Share → Save Image".

## Design provenance

The approved design is the Design canvas **"GymStreak Share Card"**,
https://claude.ai/artifact/CRKQswTkEGUFgaMpKPJTpi, approved by the user on 2026-10-19 at version 16
(`.scratch/share-screen/issues/01-design-share-card.md`, "Approved design"). Files used here:
`Main.dc.html` (strength card, states `prs` / `noPr` / `short`, layers), `MuscleFigure.dc.html`
(geometry ported 1:1 from `MuscleMapGeometry.swift`, so the app's `MuscleFigureView` is reused
as is), `SharePreview.dc.html` and `EntrySave.dc.html`. The callout anchors and the label layout
algorithm in `WorkoutShareCalloutLayout` are a direct port of `Main.dc.html`'s `ANCHOR` table and
`renderVals()`.

**Deliberate deviations from the approved design** (user decision, 2026-10-19, after the device
check): the History detail also gets the completion screen's share row, not only the toolbar
icon of `EntryHistory.dc.html`. The preview sheet gains a secondary **Save** button beside Share,
which `SharePreview.dc.html` doesn't have. Both reuse the existing visual system, so no new design
round was run.

The conditioning card is built from `ConditioningCard.dc.html` (states `hr` / `noHr`, layers
`showRounds` / `showHeartRate` / `showStats`) and its entry point from `EntryConditioning.dc.html`;
the finish-screen button is an addition (see "Sharing a conditioning session").

## Verification

- Conditioning (ticket 04): `ConditioningHeartRateSummarizerTests` (time-weighted average, zones,
  below-Z1, the gap cap, sparse readings, window clamping, zone floors incl. resting HR and
  medication), `ConditioningShareCardModelTests` (hr / noHr states, Heart rate chip, average and
  maximum without zones, ended early, minimum block width, 30 rounds, steady state, layers) and
  `ConditioningShareViewModelTests` (Health read only with a `healthKitWorkoutId`, unknown record).
  The four states (hr, noHr ended early, 15 short sprints, steady) were rendered with
  `ImageRenderer` from a throwaway test and compared with `ConditioningCard.dc.html`.

- Unit tests: `WorkoutShareViewModelTests` covers History's `knownRecords` path (PRs used, no
  history fetch) and the Save state across chip changes, including mid-save.
  `WorkoutShareCardModelTests` covers records, the empty-PR state, the two-row cap,
  pounds conversion, the Weights/Muscles/Stats/Exercises layers, the one-exercise line, and that
  callouts split into the right columns without overlapping.
  `PersonalRecordServiceTests.unsavedSessionIsCheckedAgainstPriorBests` covers the pre-save PR path.
- Visual check against the design: the four states (`prs`, `noPr`, `short`, minimal) and the
  entry row were rendered with `ImageRenderer` from a throwaway test, then compared with the
  design's artboards.
- Device check by the user on 2026-10-19 (German locale): an Instagram story fits, with the date,
  title and footer clear of Instagram's controls. WhatsApp received the image plus the text line
  with the unattributed link, and Save Image saved it to Photos.
- Device check by the user on 2026-10-19 (ticket 03): sharing from History, the inline share row,
  the preview's Save button (permission prompt, "Saved" ✓, reset on chip change) and the denied
  alert all work.
