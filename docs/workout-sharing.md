# Workout Sharing

Share a just-finished workout as a story-sized image: a 1080 × 1920 card with the muscle map, the
new personal records and the headline stats, plus a line of text that carries the App Store link.
It is acquisition lever #5 (`docs/acquisition-strategy.md` §4.5): every posted card is an ad seen
by the user's friends.

**Status:** sharing from the **workout completion screen** shipped (2026-10-19,
`.scratch/share-screen/` ticket 02). Sharing from a History entry (ticket 03) and the conditioning
card (ticket 04) are not built yet.

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
3. **System share sheet** (`UIActivityViewController`) with the rendered PNG and the text
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
| `Presentation/ViewModels/Share/WorkoutShareViewModel.swift` | Presentation | Reads the session, fetches the PR bar, owns the layers, renders the image, holds the share text |
| `Presentation/Views/Share/WorkoutShareCardModel.swift` | Presentation | `WorkoutShareSource` (values from the session), `WorkoutShareLayers`, and `WorkoutShareCardModel.make`, which localizes, formats and lays out everything the card shows |
| `Presentation/Views/Share/WorkoutShareCalloutLayout.swift` | Presentation | Port of the design's callout layout: stage geometry, anchors per region, column assignment, collision push and mean-displacement shift |
| `Presentation/Views/Share/WorkoutShareCardView.swift` | Presentation | The 1080 × 1920 card; reads only `WorkoutShareCardModel` |
| `Presentation/Views/Share/WorkoutSharePreviewSheet.swift` | Presentation | Preview sheet, `WorkoutShareCardThumbnail` (the card scaled to a width), and the `UIActivityViewController` bridge |
| `Presentation/Views/Share/WorkoutShareEntryRow.swift` | Presentation | The completion screen's row |
| `Domain/Interfaces/PersonalBestsProviding.swift` | Domain | Read boundary: best estimated 1RM per exercise before a date |
| `Domain/Services/PersonalRecordService.swift` | Domain | Gained `sessionBests(of:)`, `records(from:priorBests:)`, `records(in:priorBests:)` and `personalBests(sessions:)`; `computePRs` is now built on them, with unchanged behaviour |
| `Data/History/SwiftDataHistorySnapshotStore.swift` | Data | `SwiftDataHistorySnapshotProvider` conforms to `PersonalBestsProviding` (`@concurrent`), same instance and model actor as History |
| `Presentation/Views/Settings/SupportLinks.swift` | Presentation | `appStoreCampaignLink(campaign:)`, `appStoreProviderToken`, `Campaign.shareSummary`, and `AppBrand.wordmark` |
| `App/AppDependencies.swift` | App | `personalBests` and `makeWorkoutShareViewModel()` |

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

- **Link:** built only by `SupportLinks.appStoreCampaignLink(campaign:)`, next to `appStoreAppID`.
  With a provider token it is
  `https://apps.apple.com/app/apple-store/id6756426105?pt=<token>&ct=share-summary&mt=8`.
  **The token isn't known yet** (`// TODO(share-screen)` on `appStoreProviderToken`). Without it,
  App Store Connect can't attribute a `ct`, so the builder returns the plain
  `https://apps.apple.com/app/id6756426105` instead of inventing one. To turn attribution on,
  get the token from App Store Connect → Analytics → Campaigns (Kampagnen) → campaign link
  generator and set the constant. No other change is needed.
- **Wordmark:** `AppBrand.wordmark` ("GymStreak") is the single swappable element on the card and
  in the share text, so the rename decision (lever #15) changes one line.

## Photos permission

"Save Image" in the share sheet writes to the photo library and **crashes without
`NSPhotoLibraryAddUsageDescription`**. The app target sets it as an `INFOPLIST_KEY_` build setting
(both configurations) and translates it in `en`/`de` `InfoPlist.strings`.

## Design provenance

The approved design is the Design canvas **"GymStreak Share Card"**,
https://claude.ai/artifact/CRKQswTkEGUFgaMpKPJTpi, approved by the user on 2026-10-19 at version 16
(`.scratch/share-screen/issues/01-design-share-card.md`, "Approved design"). Files used here:
`Main.dc.html` (strength card, states `prs` / `noPr` / `short`, layers), `MuscleFigure.dc.html`
(geometry ported 1:1 from `MuscleMapGeometry.swift`, so the app's `MuscleFigureView` is reused
as is), `SharePreview.dc.html` and `EntrySave.dc.html`. The callout anchors and the label layout
algorithm in `WorkoutShareCalloutLayout` are a direct port of `Main.dc.html`'s `ANCHOR` table and
`renderVals()`.

The conditioning card (`ConditioningCard.dc.html`) and the History and conditioning entry points
belong to tickets 03 and 04. Ticket 04 must know that `ConditioningRecord` stores **no heart-rate
data**: read it from the linked HealthKit workout, or use the design's no-HR state.

## Verification

- Unit tests: `WorkoutShareCardModelTests` covers records, the empty-PR state, the two-row cap,
  pounds conversion, the Weights/Muscles/Stats/Exercises layers, the one-exercise line, and that
  callouts split into the right columns without overlapping.
  `PersonalRecordServiceTests.unsavedSessionIsCheckedAgainstPriorBests` covers the pre-save PR path.
- Visual check against the design: the four states (`prs`, `noPr`, `short`, minimal) and the
  entry row were rendered with `ImageRenderer` from a throwaway test, then compared with the
  design's artboards.
- Device check by the user on 2026-10-19 (German locale): an Instagram story fits, with the date,
  title and footer clear of Instagram's controls. WhatsApp received the image plus the text line
  with the unattributed link, and Save Image saved it to Photos.
