# First-run onboarding flow

The tour a user sees once, on their first launch of the version that introduced
it, before they can reach the tab bar. It teaches what Gym Streak is by showing
real pieces of the app rather than illustrations.

> **Status.** The shell is built (ticket 01): the chrome, the step navigation,
> the persistence and the presentation seam, with the welcome slide filled in.
> Steps 2–7 are declared in `OnboardingStep` and render nothing yet; tickets
> 02–08 fill them in, and ticket 09 owns the cover-ordering tests, the
> end-to-end walkthrough and the rest of this document.

## The flow

Seven steps, declared once in `OnboardingStep` so the progress bar, the counter
and the navigation all derive their length from the same list:

| # | Step | What it shows |
| - | ---- | ------------- |
| 1 | `.welcome` | What the app is: icon tile, eyebrow, two-line title, body, three check bullets. **Built.** |
| 2 | `.routines` | A real routine exercise card — sets, reps, weight, rest, alternatives. |
| 3 | `.supersets` | Supersets in a routine. |
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
Presentation/Views/Onboarding/OnboardingWelcomeSlideView.swift   step 1
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

## Scroll position across steps

The slide's `ScrollView` content carries `.id(currentStep)`. Scroll offset
belongs to the `ScrollView`, so re-identifying it on a step change is what puts
the new slide at the top — going back as well as forward.

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
hold no literal strings. The design was written in German and the English strings
follow it in the same voice. `OnboardingFlowTests` asserts every key resolves —
a missing entry resolves to the key itself, so the test fails loudly rather than
shipping a raw key on screen.

## Deliberate omission

The design's step 7 is a **mockup** — invented prices, trial copy and plan cards.
None of it is built. Step 7 raises the app's real RevenueCat paywall instead
(ticket 08), because the price and the offer must come from the offering, never
from hard-coded strings.
