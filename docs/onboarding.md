# First-run onboarding flow

The tour a user sees once, on their first launch of the version that introduced
it, before they can reach the tab bar. It teaches what Gym Streak is by showing
real pieces of the app rather than illustrations.

> **Status.** The shell is built (ticket 01) and the feature-slide scaffold with
> it (ticket 03): the chrome, the step navigation, the persistence and the
> presentation seam, plus the preview plate, the inert-mount seam and the shared
> feature-slide layout — with steps 1, 2 and 3 filled in. Steps 4–7 are declared
> in `OnboardingStep` and render nothing yet; tickets 05–08 fill them in on the
> scaffold, and ticket 09 owns the cover-ordering tests, the end-to-end
> walkthrough and the rest of this document.

## The flow

Seven steps, declared once in `OnboardingStep` so the progress bar, the counter
and the navigation all derive their length from the same list:

| # | Step | What it shows |
| - | ---- | ------------- |
| 1 | `.welcome` | What the app is: icon tile, eyebrow, two-line title, body, three check bullets. **Built.** |
| 2 | `.routines` | A real routine exercise card — sets, reps, weight, rest, alternatives. **Built.** |
| 3 | `.supersets` | Two collapsed cards joined by the real superset connector. **Built.** |
| 4 | `.progressiveOverload` | The automatic weight suggestion. |
| 5 | `.history` | Logged workouts and the numbers going up. |
| 6 | `.aiCoach` | The on-device coach, as a teaser (the opt-in stays its own screen, after the tour). |
| 7 | `.offer` | The real RevenueCat paywall on a new `onboarding` placement. |

Every step is skippable. "Skip" and finishing the last step are the same exit:
both end the flow and both record it.

## Architecture

```
Domain/Interfaces/OnboardingCompletionTracking.swift   the durable "seen it" record
Data/Preferences/OnboardingCompletionStore.swift       UserDefaults.standard behind it
Presentation/ViewModels/Onboarding/OnboardingStep.swift          the step list + per-step CTA key
Presentation/ViewModels/Onboarding/OnboardingFlowViewModel.swift presented? which step?
Presentation/Views/Onboarding/OnboardingCoverView.swift          the chrome
Presentation/Views/Onboarding/OnboardingCheckBullet.swift        the shared bullet
Presentation/Views/Onboarding/OnboardingWelcomeSlideView.swift   step 1
Presentation/Views/Onboarding/OnboardingPlate.swift              the preview panel
Presentation/Views/Onboarding/OnboardingInertPreview.swift       the inert-mount seam
Presentation/Views/Onboarding/OnboardingFeatureSlideView.swift   the steps 2–6 layout
Presentation/Views/Onboarding/OnboardingRoutinesSlideView.swift   step 2
Presentation/Views/Onboarding/OnboardingSupersetsSlideView.swift step 3
Presentation/Views/Onboarding/OnboardingSampleRoutine.swift      steps 2 and 3's sample values
App/AppDependencies.swift                              constructs the view model
App/ContentView.swift                                  hosts the fullScreenCover
```

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
Founder thank-you → AI Coach opt-in**, enforced at the host in `ContentView`:
the Founder binding and the opt-in binding are both suppressed while
`onboarding.isPresenting`, and the Founder binding also suppresses the opt-in as
it did before.

Two things about this are load-bearing and easy to break:

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

Nothing is lost by being suppressed, because none of the three spends its record
when it fails to present: `FounderCelebrationCoordinator` only writes on
dismissal, and the opt-in re-evaluates its own condition. Each one appears on its
own once the cover above it goes away. Ticket 09 pins this with tests — including
the case that matters most, the coach opt-in becoming eligible asynchronously
while the tour is still on screen.

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
  text 2.5× that size at AX5.
- **The Back control's hit target is 44pt**, with the 30pt chip drawn inside it.
  The design's 30pt square is a visual size, not a hit box, and this is the
  flow's only way back.

**The shipped component is authoritative, and inert means no side effects.** Both rules, and how
the scaffold enforces the second one, are in "The feature-slide scaffold" below. The specific
mismatch to remember: the design's Progressive-Overload prompt does not exist in the app at all —
the shipped bar is orange, names the target rep count rather than a next weight, and offers
"Erhöhen" and a dismiss X.

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
View.onboardingInertPreview()   how a production component is mounted inside it
```

A slide is declared as a `static let` on `OnboardingFeatureSlideContent` — see
`.routines` in `OnboardingRoutinesSlideView.swift` — and rendered by handing that
entry plus a preview view to `OnboardingFeatureSlideView`. Nothing in the content
struct is a literal string; it carries keys, and the layout resolves them. The
only per-slide layout knobs are `plateHeight` and `plateFadesOutBottom`.

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
what it is: `OnboardingChromePill`, private to the slide, documented as tour
chrome. The distinction is the point of ticket 03's rule 1. A still image of two
linked cards does not say what the link is called, so the tour may caption it —
but only with a word the user will meet again in the app.

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

The shell as built contains no gate at all. Ticket 08 adds the placement, and
ticket 09 records it in `docs/monetization-strategy.md` §4 and
`docs/pro-subscription.md` together with the §10 guardrail and the one-line
rollback (drop step 7, leaving the six value slides).

## Localization

All copy lives in `en.lproj`/`de.lproj` under the `onboarding.` prefix; the views
hold no literal strings. Two deliberate borrows: the exercise names on steps 2
and 3 use `seed.exercise.*` keys so the tour and the library agree, and step 3's
group caption uses `superset.label` so the tour calls a superset what the app
calls it. The design was written in German and the English strings
follow it in the same voice. `OnboardingFlowTests` asserts every key resolves —
a missing entry resolves to the key itself, so the test fails loudly rather than
shipping a raw key on screen.

## Deliberate omission

The design's step 7 is a **mockup** — invented prices, trial copy and plan cards.
None of it is built. Step 7 raises the app's real RevenueCat paywall instead
(ticket 08), because the price and the offer must come from the offering, never
from hard-coded strings.
