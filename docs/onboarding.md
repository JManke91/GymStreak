# First-run onboarding flow

The tour a user sees once, on their first launch of the version that introduced
it, before they can reach the tab bar. It teaches what Gym Streak is by showing
real pieces of the app rather than illustrations.

> **Status.** Complete and shipped. The shell and the feature-slide scaffold came
> from tickets 01 and 03; steps 2–6 from tickets 04–07; step 7, the Pro offer,
> from ticket 08; the cover ordering, its tests and the end-to-end walkthrough
> from ticket 09 (see "Verification" at the end).

## The flow

Seven steps, declared once in `OnboardingStep` so the progress bar, the counter
and the navigation all derive their length from the same list:

| # | Step | What it shows |
| - | ---- | ------------- |
| 1 | `.welcome` | What the app is: icon tile, eyebrow, two-line title, body, three check bullets. **Built.** |
| 2 | `.routines` | A real routine exercise card — sets, reps, weight, rest, alternatives. **Built.** |
| 3 | `.supersets` | Two collapsed cards joined by the real superset connector. **Built.** |
| 4 | `.progressiveOverload` | A finished exercise and the weight prompt it raises. **Built.** |
| 5 | `.history` | A recorded session: its header, the four stat tiles and one exercise block with its record and per-set deltas. **Built.** |
| 6 | `.aiCoach` | The on-device coach, as a teaser: one answer, one question, and what the free tier gets. **Built.** |
| 7 | `.offer` | The real RevenueCat paywall on the `onboarding` placement. **Built** — and **absent** for anyone it would show nothing to. |

The seventh step is the only conditional one. `OnboardingStep.allCases` is what
the tour *can* contain; `OnboardingFlowViewModel.steps` is what a given run
contains, and it drops `.offer` whenever the paywall seam would refuse it. So a
Pro user's tour is six steps, with six progress segments and a counter that says
so — never seven with a final segment that leads nowhere.

Every step is skippable. "Skip" and finishing the last step are the same exit:
both end the flow and both record it.

## Architecture

```
Domain/Interfaces/OnboardingCompletionTracking.swift   the durable "seen it" record
Data/Preferences/OnboardingCompletionStore.swift       UserDefaults.standard behind it
Presentation/ViewModels/Onboarding/OnboardingStep.swift          the step list + per-step CTA key
Presentation/ViewModels/Onboarding/OnboardingFlowViewModel.swift presented? which step?
Presentation/ViewModels/Onboarding/FirstRunCoverOrder.swift      which first-run cover wins
Presentation/Views/Onboarding/OnboardingCoverView.swift          the chrome
Presentation/Views/Onboarding/OnboardingCheckBullet.swift        the shared bullet
Presentation/Views/Onboarding/OnboardingWelcomeSlideView.swift   step 1
Presentation/Views/Onboarding/OnboardingPlate.swift              the preview panel
Presentation/Views/Onboarding/OnboardingInertPreview.swift       the inert-mount seam
Presentation/Views/Onboarding/OnboardingFeatureSlideView.swift   the steps 2–6 layout
Presentation/Views/Onboarding/OnboardingChromePill.swift         the tour's own caption pill
Presentation/Views/Onboarding/OnboardingRoutinesSlideView.swift   step 2
Presentation/Views/Onboarding/OnboardingSupersetsSlideView.swift step 3
Presentation/Views/Onboarding/OnboardingProgressiveOverloadSlideView.swift step 4
Presentation/Views/Onboarding/OnboardingHistorySlideView.swift   step 5
Presentation/Views/Onboarding/OnboardingAICoachSlideView.swift   step 6
Presentation/Views/Onboarding/OnboardingSampleRoutine.swift      steps 2 and 3's sample values
Presentation/Views/Onboarding/OnboardingSampleWorkout.swift      step 4's sample values
Presentation/Views/Onboarding/OnboardingSampleHistory.swift      step 5's sample values
Presentation/Views/Onboarding/OnboardingSampleCoach.swift        step 6's sample values
App/AppDependencies.swift                              constructs the view model
App/ContentView.swift                                  hosts the three first-run covers
```

Step 7 adds no file. It is a case of `PaywallPlacement` (`onboarding`), a query
on the paywall seam (`PaywallPresenting.isEligible(_:)`), and a sheet inside
`OnboardingCoverView` — see "Step 7 — the offer" below.

The view model is app-lifetime and held concretely by the composition root,
mirroring `FounderCelebrationCoordinator`: the app root binds a
`.fullScreenCover` straight to its `@Observable` `isPresenting`, and both the
cover's content and that binding must be built from the *same* instance so a
dismissal is recorded exactly once. Slides hold no dependencies — the cover
navigates, the slides only render.

`isPresenting` is seeded at composition time rather than in a launch task, so the
very first frame of the app root already knows the tour is due. There is nothing
asynchronous to wait for: the answer is one `UserDefaults` read.

## Who sees it, and why the flag is device-local

**Everyone, once — existing users updating into this version included.** The flow
is deliberately *not* conditioned on whether the install already has routines or
history: a returning user meeting the tour once is a small cost, and the
condition that would avoid it would also hide the tour from a new user who
happened to be restored from a backup.

The record is a plain `UserDefaults.standard` key (`onboarding.flowCompleted`),
matching `FounderCelebrationStore`:

- **Not iCloud KVS.** A KVS flag survives app deletion — the trap the
  starter-catalog seeding flags already fell into (`seedCatalogVersion` and
  friends make a reinstall skip seeding forever). A reinstalling user staring at
  a tab bar with no idea what the app is would be the same bug with a worse
  outcome. Being toured twice on a second device is the cheaper mistake.
- **Not the App Group suite.** Neither the watch app nor the widget shows
  onboarding.

The flag is cached in memory and seeded at init, because `UserDefaults` is not
observable and the view model is read while the app root is being composed.

## Cover ordering

Three things want the whole screen on a first launch. The order is **onboarding →
Founder thank-you → AI Coach opt-in**, and it is decided in one place:
`FirstRunCoverOrder.topmost(isOnboarding:isCelebratingFounder:shouldShowCoachOptIn:)`
returns the first cover that is due, or `nil` for the tab bar. `ContentView`
reads the three conditions in `body` — which is also what registers it as an
observer of all three — and each of the three `.fullScreenCover`s binds to
`firstRunCover == <its own case>`.

**A single `FirstRunCover?` is why "exactly one cover" is structurally true.**
The earlier shape was three hand-written suppression clauses
(`isCelebratingFounder && !isOnboarding`, `shouldShowOptIn && !isCelebratingFounder
&& !isOnboarding`), which is an invariant that holds only as long as three
expressions agree with each other, and which cannot be asked anything without a
running SwiftUI hierarchy. `FirstRunCoverOrderTests` now walks all eight
combinations of the three conditions.

Three things about this are load-bearing and easy to break:

- **The tour must never raise itself again.** `isPresenting` is seeded once and
  only ever goes true → false. If it could rise while the Founder cover is on
  screen, SwiftUI would tear that cover down, the binding's write-back would run,
  and the once-ever thank-you would be spent on a screen nobody read.
  `OnboardingFlowTests.onboardingNeverReRaisesItself` pins it.
- **The hand-off happens inside one SwiftUI transaction** — the tour's dismissal
  and the un-suppression of the next cover land in the same state update, and
  SwiftUI can drop a presentation raised while another is being dismissed.
  `FounderCelebrationCoordinator.presentIfDue()` guards on its own
  `isPresenting`, which is already `true` while suppressed, so a dropped
  presentation would *not* be retried. **Verified 2026-09-04** on the simulator
  with `-PRO_GATING_ON -FOUNDER_SIMULATE_PRECUTOFF`: skipping the tour raises the
  Founder thank-you by itself, immediately after. The presentation is not
  dropped, so no runloop deferral is needed — but the behaviour rests on
  SwiftUI's presentation handling rather than on anything this code controls,
  which is why ticket 09 pins it with a test.

- **Suppression is not consumption.** None of the three spends its record when it
  fails to present: `FounderCelebrationCoordinator` writes only on dismissal
  (`presentIfDue()` may therefore be called while the tour is up — it raises its
  own flag, and the ordering keeps the screen off), the tour's flag is written
  only when the tour ends, and the opt-in has no record to spend at all, because
  it re-reads `AICoachAvailability`/`AICoachPreferences` on every render. The
  order is recomputed from live conditions each time, so a cover that became due
  behind another one becomes topmost the moment the one above it goes away.
  `founderScreenIsNotSpentWhileSuppressed`, `optInEligibleDuringTheTourIsNotLost`
  and `theThreeCoversArriveInOrder` pin all three cases — the last of which is
  the one that matters most, since Apple Intelligence availability resolves
  asynchronously after launch and therefore usually *does* turn true while the
  tour is still on screen.

**A sheet is not a cover, and that is the fourth rule.** The app root also hosts
the paywall — as a `.sheet` — and a sheet raised while a full-screen cover is up
never reaches the screen at all. Step 7 raises a paywall from *inside* the tour,
so the tour hosts its own, and `ContentView`'s root paywall host is suppressed
while `onboarding.isPresenting` for the same reason it is suppressed under the
coach-chat cover. See "Step 7 — the offer" for why hosting it there beats
dismissing the tour first.

## Design fidelity

The screens follow the Claude Design project "Gym Streak"
(`0d4ac3f4-2c40-43cc-b80e-84bd411c334a`), file `Onboarding.html` with
`gs-onboarding.jsx` behind it — read them with the DesignSync tool
(`method: "get_file"`). Conventions the shell established, which the remaining
slides inherit:

- **Welcome is centred, feature slides start at the top.** `OnboardingStep`'s
  `isContentCentred` carries the difference; feature slides lead with a
  fixed-height preview plate, so they flow from the top.
- **Bullets are a tinted chip, not a solid disc** — tint at 14% with a 34% border
  and a thin checkmark, label at footnote size in `textSecondary`. Three filled
  accent discs stacked in a column out-shout the headline.
- **The Back control is a chip**, dimmed as a whole to 25% when disabled rather
  than recoloured.
- **The icon tile is a wash, not a button** — tint at 14% with a 36% border and
  an *outlined* glyph.

Two places where the shipped screen deliberately does *not* copy the design's
pixel values, because the design is a fixed-size web mock and the app is not:

- **The bullet chip scales with its label** (`@ScaledMetric(relativeTo: .footnote)`,
  the pattern `FounderCelebrationView` uses). A fixed 18pt disc would sit beside
  text 2.5× that size at AX5. The metric is **snapshotted into a local `let` in
  `body`** before the `alignmentGuide` closure reads it: SwiftUI declares that
  closure `@Sendable` *and* `nonisolated` and calls it off the view's actor, so
  reading the `@MainActor` property inside it captures `self` across the boundary —
  the isolation class that crashed TestFlight 1.1.10. Full write-up in
  `docs/swift6-concurrency.md` §4a.
- **The Back control's hit target is 44pt**, with the 30pt chip drawn inside it.
  The design's 30pt square is a visual size, not a hit box, and this is the
  flow's only way back.

**The shipped component is authoritative, and inert means no side effects.** Both rules, and how
the scaffold enforces the second one, are in "The feature-slide scaffold" below. The specific
mismatch to remember: the design's Progressive-Overload prompt does not exist in the app at all —
the shipped bar is orange, names the target rep count rather than a next weight, and offers
"Erhöhen" and a dismiss X. Step 4 was built around the shipped bar and its copy written to it; see
"Step 4 — Progressive Overload" below.

Two deliberate departures from the design file:

- Its welcome body says "Vier kurze Schritte" while its own flow has seven. The
  shipped copy avoids the count.
- Its background carries a radial tint glow off the top-right corner. **Still not
  built.** Ticket 03 was the place to establish it and deliberately did not: on
  the shipped screen the plate's own 45 %-black drop shadow already separates the
  preview from the background, and a tint glow behind a dark panel that starts
  24 pt from the top edge is invisible under it. It would only read on the
  welcome poster, which is the one slide the design does *not* put it on
  differently. Restoring it is a `RadialGradient` overlay on
  `OnboardingCoverView`'s background, ignoring safe areas, at `tint` 9 %.

## The feature-slide scaffold (steps 2–6)

Every feature slide is the same three things stacked: a fixed-height **plate**
holding a real piece of the app, then the copy, then the bullets. Ticket 03 built
that scaffold together with the first slide that uses it, so steps 3–6 add an
entry and a preview view rather than a screen.

```
OnboardingFeatureSlideContent   what the slide says, as localization keys
OnboardingFeatureSlideView      plate + eyebrow (+ Pro badge) + title + body + bullets
OnboardingPlate                 the panel: breadcrumb, fixed height, bottom fade
OnboardingChromePill            a caption the tour adds, that no app screen has
View.onboardingInertPreview()   how a production component is mounted inside it
```

A slide is declared as a `static let` on `OnboardingFeatureSlideContent` — see
`.routines` in `OnboardingRoutinesSlideView.swift` — and rendered by handing that
entry plus a preview view to `OnboardingFeatureSlideView`. Nothing in the content
struct is a literal string; it carries keys, and the layout resolves them. The
only per-slide layout knobs are `plateHeight`, `plateFadesOutBottom` and
`plateContentInset`.

**`plateContentInset` is a truncation escape hatch, not a styling choice.** The
plate is about 50 pt narrower than the screen it pictures — the slide's 24 pt
margins on each side plus the panel's own 12 pt inset — so a production row that
fits in the app can cross into truncation here. Step 4's workout set row is that
case: at the default inset it rendered "6 W… × … kg", ellipsising the two numbers
the slide exists to show. It takes 4 pt instead, which still reads as a panel with
something laid on it. The breadcrumb keeps the full inset either way, so the
panels stay aligned with each other.

### The plate, and why its height is a constant

The panel never sizes to its content. Both the fixed height and the dissolving
bottom edge say the same thing — *the real screen continues below this* — and a
hard crop would instead read as "this is all there is". The height is chosen per
slide so the fade lands **inside** the content: at 376 pt the Routines slide
fades through its "Add set" button, which is exactly the point where the real
card carries on into its alternatives.

The plate also clamps its subtree to `dynamicTypeSize(.large)`. A panel with a
hard height cannot honour AX5, and blowing up a picture of a screen is not what
the reader needs anyway: the copy *below* the plate scales normally, and the
cover's `ScrollView` carries the overflow. Verified on the simulator at AX1 and
AX5 — the body and both bullets wrap and scroll into view intact, nothing clips.

### The breadcrumb is the point

"Routinen › Oberkörper A" above the preview is what turns a screenshot into a
direction. A slide that only shows the feature teaches what the app can do; one
that also says where it lives teaches the user to find it after the tour ends.

### Inert means no side effects, not just no taps

`View.onboardingInertPreview(describing:)` is the **one** way a production
component is mounted in a plate, and `OnboardingFeatureSlideView` applies it to
every slide's preview so no slide has to remember. It does three things:

- **`allowsHitTesting(false)`**, not `disabled(true)`. `disabled` changes how some
  controls draw, and the plate's whole job is to look like the shipped screen.
  Hit testing off blocks taps, drags and focus alike, so no sample value can be
  edited and no tap haptic can fire. It also lets the cover's `ScrollView` take a
  drag that starts on the plate — confirmed on device-scale simulator.
- **`\.isOnboardingPreview` in the environment**, for the side effects a dead
  pointer does not stop. `ProgressiveOverloadBanner` fires a success haptic in
  `onAppear` — nobody tapped, so hit testing is no defence — and it now reads
  this flag and skips it. That is the pattern for every future case: the
  component guards its own on-appear work; the flag defaults to `false`, so a
  component that never learns about it behaves exactly as it does today.
- **One accessibility element**, labelled with the breadcrumb through
  `onboarding.preview.accessibility`. An expanded routine card is ~20 VoiceOver
  stops of steppers and remove buttons that lead nowhere; the copy below the
  plate is what carries the meaning.

### The shipped component is authoritative

Where the design file and the shipped component disagree, the component wins and
the slide's copy adapts. Otherwise onboarding advertises a screen the user will
never find, and the app owns two of everything. A slide that cannot be built from
production components is a finding to raise, not a licence to redraw one — the
design's Verlauf and Coach previews are re-implementations and its
Progressive-Overload prompt does not exist in the app at all.

## Step 2 — Routines

The plate shows one expanded routine exercise card, drawn by four production
views: `ExerciseHeaderView`, `ExerciseParameterChips`, `RoutineSetsEditor` and,
through the editor, `RoutineSetStepperRow`. The sample values live in
`OnboardingSampleRoutine`.

**Three findings this slide raised, recorded so they are not rediscovered:**

1. **The expanded card's chassis was not a component — it is now.** The 14 pt
   padding, the fill, the hairline border and the 20 pt corner lived inline in
   `RoutineDetailView.normalExerciseCard`, and ticket 03's slide reproduced that
   five-line chain by hand. Ticket 04 would have made that a third copy, so it
   extracted `View.routineExerciseCardChassis(color:)` into
   `RoutineDetailComponents.swift` instead; the browsing card and both tour
   previews now call it. `color` is the superset group's colour (`nil` for a
   non-member), which is the only thing that ever varied between the sites.
   Superset *edit* mode keeps its own chassis — its background and border are a
   selection state, not this panel.
2. **The ALTERNATIVEN block cannot be reused.** `RoutineAlternativesSection`
   takes a `RoutineExercise` `@Model` *and* the screen's view model, so the tour
   — which has neither — cannot mount it. It sits below the fade anyway, and the
   slide teaches alternatives through the header's avatar stack instead, which is
   real production rendering. Ticket 02 value-typed the header and the
   workout-detail block; this section was not in its scope.
3. **The header's overflow menu is deliberately omitted.** Passing no
   `onSupersetAction` / `onEditAlternatives` makes `ExerciseHeaderView` draw no
   menu — both what an inert preview wants (a `Menu` is a control that can still
   present) and 30 pt of width the exercise name gets to keep, which matters for
   the longer German exercise names.

**The sample values are copy, not data.** `OnboardingSampleRoutine` is written
next to the slide for the same reason its headline is written in
`Localizable.strings`. Nothing there is inserted, seeded or synced, and the plate
is not interactive, so there is no path from those numbers into the user's
library. Two details are load-bearing:

- **The exercise is named by its seed key** (`seed.exercise.lat_pulldown`,
  `seed.exercise.pull_up` for the alternative), not by a literal, so the tour
  cannot advertise an exercise under a different name than the library the user
  lands in uses. Their muscle groups and equipment *are* restated locally,
  because `Presentation` does not reach into `Data/Seeding` — and
  `OnboardingFlowTests.sampleRoutineAvatarsMatchTheCatalog` compares that copy
  against `SeedExerciseCatalog` from the test target, which may cross the layer.
  Without it the avatar's colour and glyph would drift silently the day a
  catalog row changes.
- **The three sets are identical** (3 × 10 reps at 55 kg). That is what makes the
  header read "3 × 10 Wdh. · 55 kg" instead of the mixed-scheme fallback
  "3 Sätze · max 55 kg", which teaches nothing about reps.
  `OnboardingFlowTests.sampleRoutineReadsAsOneScheme` pins it.

Weights are canonical kilograms, so the plate renders in the user's own unit —
the cover inherits `\.weightUnit` from `ContentView`.

`OnboardingSampleSet` is a small reference type conforming to
`AlternativeEditableSet`. That protocol is a class protocol with settable
properties, because on the real screen the rows write straight back to the
`@Model` they came from. The carrier exists so the *production* set editor can be
reused verbatim rather than the slide drawing its own set list; it is built once
into `@State`, never shared, and never written to.

## Step 3 — Supersets

The slide reuses step 2's breadcrumb key (`onboarding.routines.breadcrumb`,
"Routines › Upper Body A") rather than declaring its own: both slides show the
same sample routine, and a tour that named two different places for one screen
would be sending the user somewhere that does not exist. One accepted cost: the
plate's single accessibility label is derived from the breadcrumb, so VoiceOver
announces the same "Preview of the app screen Routines › Upper Body A" on steps
2 and 3. The copy below each plate carries the difference; an optional
`previewAccessibilityKey` on `OnboardingFeatureSlideContent` is the fix if that
ever stops being enough.

The plate shows one whole superset of that routine: two **collapsed**
member cards inside the production `SupersetGroupContainer`, which draws the
connector, its two end dots and the unlink control at the seam between the cards.
Nothing about that line is redrawn here — the container positions all three from
anchors the member headers publish, so the tour shows the shipped geometry and
cannot drift from it. `onUnlink` is an empty closure; the plate is mounted with
hit testing off, so it can never be called.

A member card is `ExerciseHeaderView` (with `supersetPosition`, `supersetTotal`,
`supersetColor` and `isSupersetMember`), the disclosure chevron, and
`ExerciseParameterChips` — the chip strip the real card shows whether or not it
is expanded. The chips are indented by `ExerciseHeaderView.connectorLaneWidth`,
exactly as `normalExerciseCard` indents everything below its header: the header
reserves that lane for the connector, and content that does not clear it has the
group's line drawn straight through it. Both cards share one rest time (1 m 30 s),
which is what the slide's body claims and how the real screen resolves a group's
rest.

**The design's "SUPERSATZ · OHNE PAUSE" pill does not exist in the app** and was
not built. The caption above the group is production's own name for it —
`superset.label` → "Superset A" — and the pill *around* that text is declared as
what it is: `OnboardingChromePill` — a declared component, documented as tour
chrome, which step 4 reuses for its "Automatic" marker. The distinction is the
point of ticket 03's rule 1. A still image of two linked cards does not say what
the link is called, so the tour may caption it — but only with a word the user
will meet again in the app.

The letter is `OnboardingSampleRoutine.supersetLetter`, and its colour comes from
`SupersetLabelProvider.color(for:)`, the same mapping the Routines screen uses.
"A" is not an arbitrary constant: the label provider gives a routine's first
superset the first letter, and the slide shows a first-time user's first group.
`OnboardingFlowTests.theFirstSupersetOfARoutineIsLabelledA` pins that against the
provider rather than against itself.

**Two sample choices are load-bearing:**

- **Both members carry a rep range.** Without one `ExerciseParameterChips` draws
  its ghost "set a goal" chip — an empty affordance, in a picture where nothing
  can be tapped.
- **Both exercise names are short ones.** The plate is narrower than the real
  screen by the slide's own margins and `ExerciseHeaderView` clips a name to one
  line, so the design's pairing ("Fliegende (Kurzhantel)" + "Bizeps-Curls
  (Kurzhantel)", i.e. `dumbbell_fly` + `dumbbell_curl`) ellipsised in German
  while reading fine in the app — teaching the user that the app truncates names.
  `pec_deck` ("Butterfly") + `hammer_curl` ("Hammercurls") do not. They are still
  a real superset pairing: two exercises that share no muscle, which is when
  grouping them is worth doing.

The plate is 330 pt with **no bottom fade**: the group ends inside it. That is
the one slide where fading would lie — "the superset continues below" is exactly
what the reader must not conclude. The height is therefore a measured fit (two
97 pt cards, the 28 pt seam, the caption and the panel's padding) with about 9 pt
of slack, not a round number.

## Step 4 — Progressive Overload

The payoff slide: the app asks for more weight by itself. The plate shows one
exercise of a running workout with all three sets logged at the top of its rep
goal, and, directly under it, the prompt that state produces.

Both pieces are production views. The card is `WorkoutExerciseCardView` with
`WorkoutSetRowView` inside it; the prompt is `WorkoutOverloadPromptBar` itself,
which draws `ProgressiveOverloadBanner`. The bar sits *below* the card because
that is where the workout screen puts it — a bottom safe-area inset under the
scrolling exercise list, not something inside the card (`WorkoutOverloadPromptBar`
carries the note on why it had to leave the card in the first place). Sample
values live in `OnboardingSampleWorkout`, on the same terms as
`OnboardingSampleRoutine`: copy, never data.

**The design file is wrong on this slide, and the shipped component won.** The
design draws a green gradient card with a "Ziel erreicht" eyebrow, the line
"Alle Sätze am oberen Ende. Nächstes Mal 92,5 kg?" and two buttons. None of that
exists in the app. What ships is an uppercase eyebrow naming the *exercise*
("FOR DEADLIFT") over an **orange** `.ultraThinMaterial` bar at radius 8 whose
message is `rep_range.all_sets_maxed` — it names the **target rep count and never
a weight** — with an "Increase" capsule and a dismiss X. So the slide was built
around the shipped bar and **its copy was written to match**: the body says the
app tells you when the weight should go up and deliberately names no next weight,
because the reader will not find one on that bar.
`OnboardingFlowTests.overloadPromptSuggestsWithoutNamingAWeight` asserts that no
slide string contains the sample weight. Redesigning the production banner is its
own ticket against a live workout surface, not a side effect of the tour.

**Four sample choices are load-bearing:**

- **Every set is at `targetRepMax`.** That is the condition
  `OverloadPromptPolicy` actually requires, so the plate is not showing a prompt
  the app would not have raised. Pinned by
  `sampleWorkoutSetsAreAllAtTheRepCeiling`, which also checks the rows read as
  in-range (`isOutsideRepRange` would draw the orange off-goal dot instead).
- **No swap button** (`canSwap` and `isSwapLocked` both false). This is
  production behaviour, not a simplification: a swap is only offered while the
  slot has alternatives *and* no set is logged yet, so a card with three
  completed sets that still showed one would be a card the app cannot produce.
  It also hands the name and the "3/3 · 4–6" meta line the width the plate
  cannot otherwise spare. The exercise menu stays — `WorkoutExerciseCardView`
  always draws it, and unlike step 2's header there is no way to pass it away.
- **No completion times** (`completedAt: nil`). The row shows the time a set was
  checked off at its right-hand end, and it is what pushed the reps and the
  weight into an ellipsis at plate width. `completedAt` is optional in
  production — a set ingested from the Watch can arrive without one — so a
  completed row with no time is a row the app itself draws. Together with
  `plateContentInset: 4` this fits from a 375 pt phone upwards; **verified on
  the simulator** at 402 pt (iPhone 17, German and English) and 375 pt
  (iPhone SE 3rd gen), and **on device on 2026-09-05** in both units.
- **A short exercise name in both languages** — `seed.exercise.deadlift`,
  "Deadlift" / "Kreuzheben". Same constraint step 3 ran into, and worse here:
  a long single German word cannot wrap, so it truncates. 90 kg × 6 in a 4–6
  goal is a believable moment to add weight, and the rest is a heavy compound's
  2 m 30 s — rendered by the card's own chip, so it reads in the app's format
  ("2m 30s") rather than in a number this slide chose.

**The plate is 500 pt with no bottom fade.** The prompt is the point of the
slide and the real screen pins it to the bottom edge, so it has to be whole — a
fade over the one thing the reader is here for is the crop that costs the point.
Like step 3, the height is therefore a measured sum rather than a round number:
the card (header, rest chip, three 62 pt set rows, the dashed "Add set" button
and its 14 pt padding), the 10 pt gap, the prompt bar, and the panel's own
breadcrumb and padding. Change `WorkoutSetRowView`'s `minHeight` or the card's
padding and the prompt loses its bottom edge with no fade to admit it.

**The "Automatic" pill is `OnboardingChromePill`,** the same tour chrome step 3
captions its superset with, in the tour's own accent rather than the banner's
orange — so it reads as the slide talking *about* the prompt rather than as a
control inside it. It marks the thing a still picture cannot show: nobody asked
for that bar, it appeared. It is pinned to the prompt's top-right corner with a
vertical offset only; with the content inset down to 4 pt, a horizontal overhang
would put it against the panel's rounded corner.

**Nothing in the plate fires or reacts.** Every closure is empty and the plate
mounts its content with hit testing off, so neither "Increase" nor the dismiss X
can be reached. The side effect a dead pointer does not stop is
`ProgressiveOverloadBanner`'s success haptic in `onAppear`, and it is suppressed
by `\.isOnboardingPreview` — the environment flag ticket 03 introduced for
exactly this component (see "Inert means no side effects" above).

## Step 5 — History

What the training just logged looks like afterwards. The plate shows the top of a
workout-detail screen: `WorkoutSessionHeaderView`, `WorkoutStatGrid` and one
`WorkoutDetailExerciseBlock` with its `PRRecordStrip`, its `ExerciseComparisonStrip`
and its per-set delta chips. All three are production views — the first two are the
ones ticket 02 extracted out of `WorkoutDetailView` for exactly this — and none of
them does anything on appear, so the slide needs no guard beyond the plate's inert
mount. Sample values live in `OnboardingSampleHistory`, on the same terms as the
other slides: copy, never data.

**It is the session the tour just built.** Steps 2 and 3 assemble "Upper Body A"
(lat pulldown, plus a pec-deck/hammer-curl superset); this is one session of it,
a couple of days ago. The routine name is read from step 2's own key, the chip's
`WorkoutType` is *derived* from that name by `WorkoutType.classify` exactly as the
app derives it, and the four stat tiles count the same routine's sets and volume —
so a reader who followed the tour sees their own three screens close a loop rather
than three unrelated mock-ups.

**Every delta is derived, never typed.** `OnboardingSampleHistory` declares two
lists — this session's four sets and last week's three — and everything else is
computed from them by the production code the History screen runs:
`ExerciseComparisonBuilder` pairs the sets (which is what makes the fourth one read
"New": the builder leaves a set the previous session did not have without a
counterpart), `SetDeltaChip.Delta` turns each pair into a chip, `ExerciseComparisonStrip`
derives the top-weight and volume figures, and `ExerciseLoadMetrics.estimatedOneRepMax`
produces both Epley numbers in the PR strip. A hand-written "+2.5 kg" is a number
that can disagree with the sets printed beside it; there is none here.
`historySampleDeltasAgreeWithTheSets` and `historySamplePRIsAnActualRecord` pin it.

**The four sets are chosen to show all four states a delta chip has** — gain,
unchanged, loss, and new — while keeping both summary figures positive:

| set | this session | last session | chip |
| --- | --- | --- | --- |
| 1 | 57.5 kg × 11 | 55 kg × 11 | `+2.5 kg` — and the PR |
| 2 | 55 kg × 10 | 55 kg × 10 | `=` |
| 3 | 55 kg × 9 | 55 kg × 10 | `−1 rep` |
| 4 | 55 kg × 8 | — | `New` |

That combination is not free. **A lost rep costs about 55 kg of volume and a
2.5 kg increase over 11 reps only returns 27**, so a three-set version of this
block with a rep loss in it has *falling* volume — the design file's own Verlauf
preview does, at −3 %. The fourth set is what buys an honest "+24 %" without
inventing a weight jump nobody makes. Reps declining 11 → 10 → 9 → 8 is what
fatigue looks like, which is what makes the third set's loss read as real rather
than arranged.

**Dates are relative, not calendar dates.** The session is two days ago and its
predecessor a week before that, formatted through `WorkoutDetailView`'s own
`"EEE d. MMM"` template (and the strip's `"d. MMM"`). A fixed "19 Apr" reads as
stale the moment the year turns and prints a weekday that is wrong in most years.
That is also why the breadcrumb says "History › Last workout" rather than the
design's "Verlauf › Training vom 19. Apr" — a date in the breadcrumb would have to
agree with the header, and only one of the two can be a literal.

**The Pro badge is on the eyebrow, and the copy is written so it cannot mislead.**
This is the tour's first badged slide, and the honesty problem is real: **the
screen in the plate is free in every entitlement state.** Rule 4 and §5d are
explicit — "every workout, session and set stays readable in the History tab", and
the shipped P2 gate narrows the *exercise progress chart* (estimated 1RM and total
volume as metrics, 1Y and All as windows), not the session detail. The design's
copy ("Die vollen Auswertungen sind Teil von Pro") sits directly under a picture of
a free screen and would have advertised a gate that does not exist. The shipped
body therefore names both halves: the history stays readable for free, and Pro adds
the long-term curves per exercise. Bullet 1 ends "— free" and bullet 2 "with Pro",
which is also §8 C: a badge has to name the capability it unlocks.

**Two findings about `WorkoutStatTile` at plate width**, both raised rather than
fixed, because the shipped component is authoritative (see the rule above):

1. **The intensity label does not fit four-across on a narrow phone.** German
   "INTENSITÄT" wants ~64 pt at 10 pt semibold and a quarter of the plate leaves
   ~55, so the tile either breaks the word mid-way or ellipsises it depending on
   the vertical room left. The slide works around it *locally* — `.lineLimit(1)`
   and `.minimumScaleFactor(0.75)` applied to the grid, which reach the labels
   through the environment and leave the component untouched. **The same word is
   tight on the real screen too**: at 402 pt the shipped tile has ~64 pt for it,
   which is the width it needs, and a 375 pt phone would have ~57. If it is ever
   seen truncated in the app, the fix belongs in `WorkoutStatTile` — a
   `minimumScaleFactor` on its label — not here.
2. **A four-cell set grid wraps a rep-delta chip in German.** "−1 Wdh." needs more
   than a quarter of the plate at 390 pt, so it takes two lines there (it fits at
   402 pt, and "−1 reps" fits at both). This is what the shipped block draws at
   that width; `plateHeight` is measured against that taller case so nothing is
   ever cropped, and the chip is left alone.

Two more things the plate does **not** show, deliberately: the "Exercises" section
heading above the blocks, and the muscle-map card and remaining two exercises of
the session. The plate is a slice of a screen, and those are the parts that teach
nothing at a third of their real width. The header keeps a 4 pt inset of its own,
which is the difference between the real screen's 20 pt header margin and the 16 pt
its sections below use — so the rhythm inside the panel is the screen's.

**`plateContentInset: 4`, like step 4** and for the same reason: the stat row and
the set grid are the two densest rows the app draws, and at the default 12 pt both
broke on a 390 pt phone.

## Step 6 — AI Coach

A teaser, deliberately: the tour shows what the coach sounds like and where it
lives, and the Apple Intelligence opt-in stays its own screen, right after the
tour (ticket 09 orders the covers). The plate holds one coach answer about the
routine the tour has been building, the follow-up question that answer invites,
and one line saying what the free tier gets.

Two of the three pieces are production views mounted verbatim — the answer is
`AISurface` (its gradient edge, `AISparkleView`, the "Coach" eyebrow and
`AIPrivacyFooter` all its own), and the question is `MessageBubble` in its
`.user` shape, which is why it is an accent bubble with black text rather than
the design's white-on-grey one. The third is tour chrome, and is discussed
below. Sample values live in `OnboardingSampleCoach`, on the same terms as the
other slides: copy, never data.

**Nothing on this slide asks the coach anything.** No ViewModel is built, no
`CoachChatService` is touched and no availability is queried, so the slide
renders identically on a device that cannot run Apple Intelligence — which is
most of the installed base and all of the simulator fleet. The two on-appear side
effects in the subtree are `AISurface`'s shimmer and `AISparkleView`'s pulse, and
both already guard on flags this slide does not set (`isStreaming`, `pulse`), so
neither needs the `\.isOnboardingPreview` escape hatch step 4's banner does.

**The breadcrumb is not the design's.** The design says "Verlauf › Coach", and
the coach is not in the History tab: `CoachBarView` is the TabView's **bottom
accessory** (the iOS 26 `tabViewBottomAccessory` mini-player pattern), so it
floats above the tab bar on every tab and zoom-morphs into `CoachChatView`. A
breadcrumb naming a place the reader would then fail to find is worse than no
breadcrumb, so it says "Anywhere › Ask your coach" / "Überall › Frag deinen
Coach" — the second half being the bar's own title (`ai_coach.chat.bar.title`),
which is the label the reader is going to be looking at.

**"BETA" is the tour's own marker, and the app does not use the word.** The
design puts it on the surface's header row and in the eyebrow, and the shipped
`AISurface` has no slot for it — its header is sparkle, label, optional streaming
indicator, optional regenerate button. Adding one for the tour's benefit would be
adding production surface to a live component to hold a word production never
says, so the marker is `OnboardingChromePill` instead, pinned to the surface's
top-right corner exactly as step 4 pins "Automatic" to its prompt. It is drawn in
`textSecondary` rather than the tour's accent, because opposite an accent "COACH"
eyebrow an accent pill reads as a second eyebrow. `OnboardingChromePill`'s
`systemImage` became optional for it: there is no icon for "this feature is
young", and a glyph would make a status read as a control.

**This is a finding, not a decision the slide is entitled to make.** Nowhere in
the app is the AI Coach labelled a beta — not the chat, not the settings screen,
not the App Store copy. Either the app should adopt the label or the tour should
drop it; a word that appears only during onboarding is the mirror image of the
rule ticket 03 set for the superset caption ("only a word the user will meet
again in the app"). It is built as specified and flagged here rather than
silently dropped.

**The allowance strip is scaffold chrome, and both shipped candidates were tried
first.** `PeriodRecapAllowanceCard` is the recap's *gate*: a headline,
recap-specific copy and a primary button that spends a generation and fires a
haptic — an affordance nobody can tap has no business in a plate. `OnyxCapNudge`
is closer, and is what the real Coach Chat screen shows above its input field,
but it draws a consumption meter, and the tour has no consumption to report: an
empty meter beside this sentence would state a count nobody has spent. So the
strip states the *offer* instead — the Pro badge, and one line naming what free
gets and what Pro adds, which is the §8 C obligation the badge above the copy
creates.

**The free-messages figure is read from `ProFeatureCaps`, never typed.** §4 calls
the taster caps a one-line retune, and a slide carrying its own copy of the number
starts lying the day that line changes. It resolves in
`OnboardingSampleCoach.allowanceLine` rather than in the view so
`coachAllowanceLineFollowsTheCap` can assert on the finished sentence — both that
today's cap is in it, and that the sentence is a *format* rather than a literal
that happens to agree.

**The answer talks about the tour's own routine, and every number in it is
checkable.** Steps 2 and 3 build "Upper Body A"; step 5 shows its lat pulldown
gaining 2.5 kg and 24 % volume. So the answer credits *that* exercise with the
growth and names the pec deck — the first member of step 3's superset — as the one
that has not moved, at **the weight step 3's card actually plans for it (37.5 kg)**.
`coachSampleStagnatesAtTheRoutinesWeight` compares the two, and the weight goes
through `WeightFormatting`, so the plate prints it in the reader's own unit rather
than in a number the slide chose. The one figure that is pure copy is the "+18 %"
— nothing on screen contradicts it, and no production code can derive it.

**The accented figure comes from the translation, not from the layout.**
`onboarding.coach.sample.answer` wraps the figure in `**…**` and the slide colours
whatever run the parse marks — the two lines `ProgressiveOverloadCard.accentedText`
already uses. Which figure carries a sentence is a translation decision, and a
slide that coloured "the third word" would be wrong in the other language.
`coachAnswerMarksOneAccentedFigure` pins that exactly one run is marked and that
the parse consumed the markers, because a dropped marker ships raw asterisks and
a build cannot see it. The parse is hoisted out of `body` and keyed by
`WeightUnit` (rendering rule 2): it is a per-render allocation otherwise, and the
sentence it parses depends on the reader's unit.

**The plate is 376 pt with no bottom fade.** The allowance strip is the last thing
in it and the only line on the slide that names the offer — fading it would crop
exactly the sentence the Pro badge is promising to explain. The height is
therefore a measured sum with about 9 pt of slack, taken against the *German*
rendering, where the answer, the privacy footer and the strip each wrap one line
further than in English. **Verified 2026-09-05** by rendering the whole slide with
`ImageRenderer` at 402 pt and 375 pt in both languages: nothing crops, and English
leaves about 30 pt of panel below the strip.

## Step 7 — the offer

The tour ends by offering Pro once, through the app's own paywall seam. Nothing
about the offer is drawn here: the placement is `PaywallPlacement.onboarding`,
the presenter decides whether it may be raised, and `ProPaywallView` renders
whatever offering the RevenueCat dashboard serves for it. Purchase, restore and
dismissal behave exactly as they do from every other placement, because they are
the same view.

**The design's step 7 is a mockup and is not built** — see "Deliberate omission".

### Where the paywall is hosted, and why it is not the app root

A sheet raised while a full-screen cover is up **never reaches the screen**. That
is the trap this codebase already paid for once (see "Cover ordering"), and step
7 sits squarely in it: the tour *is* a full-screen cover, and the app root's
paywall host is a sheet on the view underneath it.

Two ways out, and the shipped one is the second:

- **Dismiss the tour first, then let the root host take the request.** Rejected.
  It puts the cover's dismissal and the sheet's presentation in one SwiftUI
  transaction, which is the case SwiftUI is documented to drop — and a dropped
  presentation here is not a lost animation but a placement left pending, which
  would then surface later, out of nowhere, on whatever screen the user had
  reached.
- **Host the paywall inside the tour's own cover**, the way the coach-chat cover
  hosts its own for `.coachChat`. Shipped. `OnboardingCoverView` owns a
  `.sheet(item:)` filtered to `.onboarding`; `ContentView`'s root host is
  suppressed while the tour is up, exactly as it is under the chat cover. Any
  *other* placement that fires during the tour stays pending and is picked up by
  the root host once the tour ends — the same deferral the chat cover produces.

Verified on the simulator on 2026-09-05: the real paywall does appear over the
tour's cover, with its close, purchase and restore controls, on a fresh install
with gating on.

### The step is absent, not empty, when nothing would be shown

`OnboardingFlowViewModel.steps` filters `.offer` out whenever
`PaywallPresenting.isEligible(.onboarding)` is `false` — a Pro user, a Founder,
a run with `-PRO_GATING_OFF`, or a tour re-entered after the placement already
fired. The progress bar, the step counter, Back and the CTA all size themselves
from that list, so those users get a six-step tour whose last slide is the coach
teaser and whose CTA says "Start training" (`OnboardingStep.finishCTAKey`) rather
than "Next". Verified on the simulator with `-FOUNDER_SIMULATE_PRECUTOFF`:
"SCHRITT 1 VON 6", six segments.

`isEligible(_:)` is a new query on `PaywallPresenting`, added for this one caller
and deliberately narrower than `present(_:)`: it answers the **standing** rules
(the kill switch, the entitlement, §8's once-ever record) and not Rule 3 or "a
paywall is already on screen", which are conditions of the moment. A `true`
answer is not a promise, so `advance()` checks `pendingPlacement` after asking
and ends the tour if nothing was raised. That is what catches the real race: the
entitlement resolves asynchronously after launch, so a Founder can be `free` on
the welcome slide and Pro by the coach slide. `steps` is computed on every read
rather than fixed at init for exactly that reason — and because reading it in a
view body is what lets SwiftUI observe the change and redraw the bar.

### Whatever the user does, the tour is over

Every exit from the paywall — the close button, a completed purchase, a
successful restore — ends in `ProPaywallView` calling `dismiss()`, which clears
the sheet binding and calls `offerWasDismissed()`. That clears the placement and
records the tour complete. There is no path where the user answers the offer and
is then asked again.

The once-ever record is the placement's own, written by `didPresent(_:)` when an
*offer* reaches the screen — not when the sheet does. So a tour whose offering
could not be resolved (offline; §5j's retry state) has not spent the placement,
and the user can still meet it later at placement A.

The offer step draws no chrome of its own. `OnboardingCoverView` swaps the whole
header/slide/footer stack for the plain background on `.offer`: the paywall owns
the screen there, and a progress bar over a dead CTA that the user cannot reach
would be worse than a black ground for the length of one presentation animation.

## Scroll position across steps

The slide's `ScrollView` content carries `.id(currentStep)`. Scroll offset
belongs to the `ScrollView`, so re-identifying it on a step change is what puts
the new slide at the top — going back as well as forward. The design does the
same thing imperatively (`scrollTop = 0` on index change).

The `ScrollView` sits inside a `GeometryReader` and its content is given a
`minHeight` of one viewport. That is what lets the welcome poster sit centred
while a slide that outgrows the screen still scrolls: the content box is never
shorter than the visible area, and never capped.

## Monetization

```
Monetization verdict — First-run onboarding flow
  Tier          Free (the tour) + one new paywall placement (step 7)
  Derivation    §3 Rule 1 — the tour IS the aha path
  Mechanism     no cap, no lock on the tour; step 7 = the existing RevenueCat paywall
  Placement     PaywallPlacement.onboarding — NEW (one-shot), needs a dashboard
                Placement + paywall.headline.onboarding en+de
  Nudge         none (slides 5 & 6 carry the existing Pro badge only)
  Free residue  all six value slides, skippable at any step; "later" exits to the full free app
  Founder note  §7 — Founders are entitled, so the presenter suppresses step 7 for them
```

Step 5 is the first slide to carry the `OnyxProBadge`, and it gates nothing — the
screen it previews is free in every entitlement state. What its copy sells is the
shipped P2 chart gate (long-term curves, estimated 1RM, total volume); see
"Step 5 — History" above for why the design's copy could not be used as written.

**Step 6 is the second badged slide, and it gates nothing either.** The badge and
the allowance strip both advertise the shipped **P3 taster** — the coach's free
tier is `ProFeatureCaps.freeCoachChatMessagesPerMonth` messages a calendar month,
metered by `MeteredAISurface.coachChat`, with `PaywallPlacement.coachChat` raised
only once that runs out. So the slide names an existing cap rather than creating
one: no new cap constant, no new placement, no new headline key. Re-checked
against the shipped mechanism on 2026-09-05, after the slide was built:

```
Monetization verdict — Onboarding step 6 (AI Coach teaser)
  Tier          Free
  Derivation    §3 Rule 1 — the tour is the aha path; the slide sells, it never gates
  Mechanism     none new; it *describes* the shipped P3 monthly taster
  Placement     none new — the coach's own PaywallPlacement.coachChat is untouched
  Nudge         none (OnyxCapNudge belongs on the real screen, where a count exists)
  Free residue  the whole slide, and the coach's own monthly free messages after it
  Founder note  §7 — Founders are entitled, so the strip's second half is already
                true for them; the slide neither promises nor withholds anything
```

The six value slides contain no gate at all. Step 7 is the one placement the
feature adds, and it shipped on 2026-09-05 exactly as the verdict above scoped
it — re-checked against what was built:

```
Monetization verdict — Onboarding step 7 (the offer), as shipped
  Tier          Pro offer (the tour around it stays free)
  Derivation    §8 A′ — soft, dismissible in one tap, once ever
  Mechanism     the dashboard-authored RevenueCat paywall; no cap, no lock
  Placement     PaywallPlacement.onboarding (new, one-shot),
                paywall.headline.onboarding en+de
  Nudge         none
  Free residue  the whole app — dismissing lands the user in the full free app,
                and the six value slides are shown either way
  Founder note  §7 — a Founder is entitled, so the step is absent, not dismissed:
                the tour is six steps long for them
```

`docs/monetization-strategy.md` §4/§8 and `docs/pro-subscription.md` §5a carry it
too, with the §10 guardrail and the one-line rollback: **drop `.offer` from
`OnboardingStep`**, leaving the six value slides and the `onboarding` placement
unraised. The guardrail worth watching is that a first session can now contain
two soft paywalls — this one and A, which fires when the user creates their first
routine — measured against free-user D30 retention and the App Store rating at
their pre-tour baseline.

## Localization

All copy lives in `en.lproj`/`de.lproj` under the `onboarding.` prefix; the views
hold no literal strings. The deliberate borrows: the exercise names on steps 2–6
use `seed.exercise.*` keys so the tour and the library agree, step 3's group
caption uses `superset.label` so the tour calls a superset what the app calls it,
steps 5 and 6 take their routine name from step 2's own
`onboarding.routines.sample.routine_name` rather than restating it, and step 6's
surface eyebrow is `ai_coach.chat.title` — the app's own name for the screen —
rather than `AISurface`'s hard-coded English default, with its breadcrumb ending
in the coach bar's own `ai_coach.chat.bar.title`. Everything step 4's plate says beyond its breadcrumb comes from the
production components themselves (`workout.exercise.*`, `rest_timer.rest_short`,
`rep_range.*`), which is what makes it a preview rather than a picture of one —
`overloadSlideStringsAreLocalized` covers those keys too. The design was written in German and the English strings
follow it in the same voice. `OnboardingFlowTests` asserts every key resolves —
a missing entry resolves to the key itself, so the test fails loudly rather than
shipping a raw key on screen.

## Deliberate omission

The design's step 7 is a **mockup** — invented prices (4,99 € / 29,99 € / 79,99 €),
trial copy and hand-rolled plan cards. **None of it is built, and none of those
strings exist in the app.** Step 7 raises the app's real RevenueCat paywall
instead, because the price, the packages and the trial must come from the
offering the dashboard serves, never from hard-coded strings — a mocked price is
a wrong price the moment pricing changes or the storefront differs, and App
Review has already rejected this app once over a purchase path it could not
follow (`appstore-rejection-1.1.9.md`).

**The production progressive-overload banner was not redesigned.** The design
file draws a nicer card than the app's shipped orange bar, and the tempting move
was to build the design's version and use it on both surfaces. Rejected when the
slides were scoped (2026-09-04): the shipped component is authoritative for a
tour that claims to show the real app, and changing a control that lives inside
an active workout is its own ticket against a live workout surface — not a side
effect of an onboarding feature. Step 4's copy was written to the shipped bar
instead.

## Known follow-ups (found by review, deliberately not applied)

The ticket-09 `architecture-reviewer` pass over the accumulated feature diff
returned **PASS WITH WARNINGS**, no CRITICAL findings. Four things it flagged are
recorded here rather than fixed, because each is bounded by literal sample data
and none of them scales with anything a user can create:

- **Three slides derive their display values inside `body`.**
  `OnboardingRoutinesSlideView` builds its card (two maps over three literal sets
  plus `SetSummaryFormatting.text`, which calls `RoutineMetricsService`),
  `OnboardingSupersetsSlideView` does the same for two members, and
  `OnboardingHistorySlideView` reads `OnboardingSampleHistory.workoutType` — a
  computed `static var` that re-runs `WorkoutType.classify` (a `lowercased()` and
  up to 18 `contains`) on every render — plus two strings that do not depend on
  the weight unit at all. Rendering rule 3 says no aggregation in `body`, and
  strictly these are aggregation; the input is three literal sets, so the cost is
  constant and invisible. **The fix, when it is worth doing, already exists in
  this folder**: a `@MainActor private static let [WeightUnit: …]` cache built
  from `WeightUnit.allCases`, exactly as `OnboardingAICoachSlideView` does for
  its parsed answers. The unit-independent values (`workoutType`, the duration
  and intensity strings) simply become `static let`.
- **`ContentView` is 304 lines**, just over the 300-line convention — 249 before
  the tour. The natural extraction is the three first-run covers into one
  `firstRunCovers(…)` `ViewModifier`. The ordering refactor moved logic *out* of
  the file rather than in, so this is acknowledged rather than owed.

Five more were raised by the earlier tickets' reviews and left unapplied because
they land in **production** files this feature only read from, two of which
carried another agent's in-flight work at the time:

- `WorkoutDetailView.exercisesSection` sorts `workoutExercisesList` inside `body`
  (rendering rule 3) and puts its `ForEach` in a plain `VStack` inside a
  `ScrollView` (rendering rule 1). Fix: hoist the sorted array into `@State`
  beside `prDetails`/`comparisons` and make the container lazy. This one is a
  real rule violation on a screen that *does* scale with user data — the most
  worthwhile of the five.
- `WorkoutDetailExerciseBlock.swift` is 440 lines. Splitting `SetDeltaChip` out is
  the obvious cut the next time the file is opened.
- **The expanded routine card's chassis is not a component** — padding 14 /
  white 3.5 % fill / hairline border / 20 pt corner live inline in
  `RoutineDetailView.normalExerciseCard`, and `OnboardingRoutinesSlideView`
  reproduces that five-line chain. That duplication is step 2's one drift risk.
  Extracting it was out of scope (`RoutineDetailView` is 829 lines).
- **"INTENSITÄT" is tight in `WorkoutStatTile`** at a quarter of the width. The
  history slide works around it locally with `.lineLimit(1)` +
  `.minimumScaleFactor(0.75)` through the environment; if the word is ever seen
  truncated on the real screen, the fix belongs in the component.
- `"\(Int(duration / 60))m"` is copied from `WorkoutDetailView.statsGrid`,
  hardcoded "m" included, because `WorkoutStatGrid` takes pre-formatted strings by
  design. Fix: a `static func durationText(_:)` beside the component, applied at
  both call sites.

## Verification

**Unit tests.** `OnboardingFlowTests` (the flow's life, the step navigation and
every localization key), `OnboardingOfferStepTests` (step 7's presence, its
paywall hand-off and its three exits) and `FirstRunCoverOrderTests` (the cover
ordering, above). Both suites — iOS and watch — pass via
`bundle exec fastlane test_unit`; the watch target is untouched by this feature
and stays green.

**Walked end to end on the simulator (iPhone 17 Pro, iOS 26.5, 2026-09-06),** on
a freshly installed container each time:

| What was walked | Result |
| --------------- | ------ |
| Fresh install, first launch | The tour, on step 1 of 7, before the tab bar |
| Steps 1 → 7 via the CTA | Every slide renders; the counter and the progress bar track it |
| Back from step 6 | 6 → 5 → 4, each slide re-entered at the top of its scroll |
| Step 7 | The real RevenueCat paywall, inside the tour's own cover |
| Dismissing the paywall | The tour ends, and the AI Coach opt-in arrives **by itself**, immediately |
| Relaunch afterwards | Straight to the tabs — no tour |
| Fresh install, "Überspringen" on step 3 | The tour ends, the opt-in arrives by itself; a relaunch does not bring the tour back |
| Fresh install with `-PRO_GATING_ON -FOUNDER_SIMULATE_PRECUTOFF` | **Six** steps, not seven — the offer step is absent for a Founder, and the progress bar has six segments |
| …then "Überspringen" | The Founder thank-you arrives by itself; dismissing *it* raises the coach opt-in |

The last two rows are the ordering rule end to end, live: three covers, one at a
time, each appearing on its own once the one above it goes away — including the
coach opt-in, whose Apple Intelligence availability had resolved while the tour
was still on screen.

Two things worth knowing for the next walkthrough. Slides 4 and 5 are **taller
than the viewport** on a 6.3" screen, so their body copy is cut off at the
bottom of the scroll area at rest; that is the intended overflow (see "Scroll
position across steps" — the slide scrolls, the CTA is pinned below it rather
than over it), not a clipped layout. And the CLI walkthrough is driven by
`osascript` clicks mapped through the simulator window: the device screen sits
at the window origin **+27, +80** at scale 3.0 on this machine, the window frame
alone misses, and the target window must be matched **by name** — another
agent's simulator is frequently window 1 and silently eats every click.
