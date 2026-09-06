# Rating prompt — the app asking for an App Store review

The app asks for an App Store rating **once, automatically, after the user's fifth completed
workout**. Nothing in the UI mentions it, nothing is gated on it, and no screen of ours is involved:
the alert belongs to the system.

This is lever #1 of `docs/acquisition-strategy.md` (§3, §4.1) — the cheapest item on that page and
the one with the most direct effect on App Store search ranking. Success is measured as the **rating
count in App Store Connect**, never in the app: the API reports nothing back (§4 below).

The manual "Rate app" row in Settings (`SupportLinks.writeReview`) is unchanged and still serves the
user who *wants* to write a review — see `docs/settings-tab.md` §5.1, which covers why that row must
never be wired to `requestReview()`.

---

## 1. What fires, and when

| | |
|---|---|
| **Trigger** | The 5th completed workout (`ReviewPromptCoordinator.workoutCount`) |
| **Counted with** | `LifetimeTrainingTotalsProviding.fetchCompletedWorkoutCount()` — the query §8 placement B already uses |
| **Frequency** | Once, ever, per device |
| **Suppressed by** | An active workout session; §8 placement B still being owed |
| **Where it is invoked** | `ContentView` (the app root) and nowhere else |
| **Localized strings** | None — the alert is Apple's and the system localizes it |

The full path, on the completion of a workout:

```
WorkoutViewModel.completeWorkout(updateTemplate:notes:)
  └─ Task {
       await proactivePaywalls?.workoutDidComplete()      // §8 A/B decides first
       await reviewPrompt?.workoutDidComplete()           // then, and only then, this
     }

ReviewPromptCoordinator.workoutDidComplete()
  ├─ already due, or already asked?      → stop
  ├─ a workout is running (Rule 3)?      → stop, nothing recorded
  ├─ is §8 placement B still owed?       → stop, nothing recorded
  ├─ fetchCompletedWorkoutCount() < 5?   → stop
  └─ isRequestDue = true

ContentView.reviewPromptHost(reviewPrompt)      → ReviewPromptHost
  └─ onChange(isRequestDue) → Task { sleep 2s; coordinator.reviewWasRequested(); requestReview() }
```

**Suppressed is deferred, never consumed.** Nothing is written unless the ask actually goes out, so a
completion that hits a rule simply re-attempts at the next one. `isRequestDue` is in-memory only for
the same reason — an ask decided but never made (the app was killed) is still owed.

---

## 2. Architecture

Four pieces, each mirroring an existing one:

| File | Layer | Modelled on |
|---|---|---|
| `Domain/Interfaces/ReviewPromptTracking.swift` | Domain | `FounderCelebrationTracking` |
| `Data/System/ReviewPromptStore.swift` | Data | `FounderCelebrationStore` |
| `Presentation/ViewModels/ReviewPromptCoordinator.swift` | Presentation | `FounderCelebrationCoordinator`, `ProactivePaywallCoordinator` |
| `Presentation/Views/Components/ReviewPromptHost.swift` | Presentation | `ContentView`'s paywall host |

Wired once in `App/AppDependencies.swift`. **iOS target only** — the watch and the widget are not
touched, and cannot be: `RequestReviewAction` / `SKStoreReviewController` has no watchOS counterpart.

### Why the decision is not in the View

`@Environment(\.requestReview)` is readable only from a `View`, and Hard rule 3 keeps business logic
out of Views. The split is the same one the paywall already uses: a `@MainActor` type decides
*whether* to ask and records that it asked; the View reads the decision, invokes the action, and
reports back. `ReviewPromptHost` contains one `onChange`, one delay and two calls — no rule.

### Storage: device-local, and deliberately so

`ReviewPromptStore` is plain `UserDefaults.standard` with the flag cached in memory at `init`,
matching `FounderCelebrationStore` and `ProactivePaywallTriggerStore`.

- **Not the App Group suite** — neither the widget nor the watch can show a review alert, so nothing
  outside the app has a reason to read it.
- **Not mirrored to iCloud KVS** — Apple's own throttle is **per device**, so the fact this record
  guards is a per-device fact. Mirroring it would make our bookkeeping disagree with the system's: a
  second device would believe it had already asked when, as far as StoreKit is concerned, it never
  has, and the ask would be lost on that device forever. The worst case of *not* mirroring is one
  extra ask on a new device — which is exactly what Apple's throttle absorbs.

Key: `review.prompt.requested`.

---

## 3. The two decisions that shape the trigger

### 3a. The threshold is 5, and it must stay strictly above 3

`ProactivePaywallTrigger.valueMomentWorkoutCount` is **3**, and
`ProactivePaywallCoordinator.workoutDidComplete()` arms §8 placement B at exactly `count >= 3`.
`docs/monetization-strategy.md` §3 Rule 3 and `docs/acquisition-strategy.md` §4.1 both forbid a
rating prompt beside a paywall — it poisons both. Keeping the thresholds apart makes the ordinary
case impossible **by construction**, with no runtime arbitration.

The invariant is written on both constants and pinned by
`ReviewPromptTests.reviewPromptThresholdClearsTheValueMoment`. Retuning either without the other
fails the suite. Five rather than four is a judgement — by the fifth session the habit is real
enough that the answer to "how are you finding this?" is worth having. The only part that is not
retunable is *strictly above three*.

**Threshold separation alone is not quite enough**, which is why there is a second guard. Placement B
is *deferred*, not dropped, when it cannot be shown (its figures failed to load, a cover was in the
way), so "the user is past 3" does not mean "B has fired". `ReviewPromptCoordinator` therefore also
refuses while `PaywallPresenting.isEligible(.valueMoment)` is true — i.e. while B could still be
raised at all. That covers the same-completion collision, the deferral, and the failed-read case in
one condition, and it costs nothing: the ask waits one more workout.

That guard reads `isEligible(_:)`, which `PaywallPresenting` documents as existing precisely for a
caller that must know the answer *before* asking. It does **not** read `pendingPlacement`, which the
same protocol reserves for the three paywall hosts.

**Accepted limitation: the deferral is unbounded.** `isEligible(.valueMoment)` goes false when the
paywall's *offer* reaches the screen (`didPresent`), not when its sheet does — deliberately, so a
sheet that ended in "couldn't be loaded" does not spend a one-shot. A free user whose offering never
resolves therefore keeps B armed, and the rating prompt waits indefinitely rather than "one more
workout". This is left as-is on purpose: the scenario is a user being shown a *failing* paywall on
every single workout completion, which is a far larger problem than a missing rating ask, and
bounding the wait would mean either a second magic number or new persisted state to serve a case
that only exists while the app is already broken. If it ever needs fixing, fix the offering
resolution, not this guard.

`ReviewPromptTests.placementBCompletionAsksForNoRating` proves the no-collision property against the
**real** `PaywallPresenter`, `ProactivePaywallTriggerStore` and `ProactivePaywallCoordinator`, driven
in the order `completeWorkout` drives them — because that ordering *is* the mechanism.

### 3b. A personal record was rejected as the trigger — there is no seam

`docs/acquisition-strategy.md` §4.1 originally suggested "after a personal record, or after the 3rd
completed workout". The PR half is not implementable at this cost:

- No ViewModel or view on the post-workout path learns "you just set a PR". `SaveWorkoutView`
  computes volume deltas, not records.
- The only post-workout PR detection is `private func detectNewPRs(session:modelContext:)` in
  `Data/AICoach/PostWorkoutRecapAggregator.swift:169` — a hand-rolled Epley reimplementation that
  does **not** call `PersonalRecordService`, and whose output is consumed only as AI prompt text.

Building that seam is larger than this whole feature. If a PR trigger is ever wanted, the work is to
route post-workout PR detection through `PersonalRecordService` and surface it on the completion
path — not to reach into the recap aggregator.

### 3c. The off-by-one, resolved deliberately

`WorkoutViewModel.pauseForCompletion()` stamps `session.endTime = Date()` when the user taps "Finish
Workout" — **before** the save screen is even on screen — and `CompletedSessionFetch.completedCount`
counts every session with an `endTime`. So by the time `workoutDidComplete()` runs, the count
**already includes the session that just ended**.

`count >= workoutCount` therefore means *"this is the 5th workout"*, not *"5 happened before this
one"*. That is the reading `docs/acquisition-strategy.md` §4.1 asks for and the same one placement
B's `count >= 3` already has. The reasoning is repeated in a comment at the decision site, because
getting it backwards would be invisible and permanent — the record is one-way.

`>=` rather than `==`: a user who installs the update with a long history behind them is asked on
their next completed workout rather than skipped forever.

---

## 4. `RequestReviewAction` — API findings

Researched via the `ios-api-researcher` agent (Context7 `/websites/developer_apple_storekit` plus
live Apple Developer Forums threads), 2026-09-06. Do not re-derive these.

**API surface.** `@Environment(\.requestReview)` is current and recommended on iOS 26 — not
deprecated, not superseded. (`SKStoreReviewController.requestReview(in:)` is deprecated iOS 14–18;
`AppStore.requestReview(in:)` is the non-SwiftUI replacement.) Declaration:

```swift
@MainActor struct RequestReviewAction: Sendable {
    @MainActor func callAsFunction()
}
```

Synchronous, non-throwing, returns `Void` — there is no `await` at the call site and no result. It is
`Sendable` and `@MainActor`, so it can be passed as data but must be *invoked* on the main actor.
Read it fresh from a `View`; `EnvironmentValues` is only meaningfully populated inside the SwiftUI
environment graph, so there is no supported way to hold it as a long-lived stored property outside
one.

**When it may be called.** Apple: never in response to a button tap or other user action, never
immediately on launch, and *"at the end of a sequence of events that they successfully complete"* —
which is exactly the post-workout moment. Apple's own sample wraps the call in a `Task` with a
**2-second `Task.sleep`** before it, "to avoid interrupting the person using the app". This app uses
that same 2 seconds, for a second reason as well: the ask is decided while the save sheet — and,
under it, the active-workout cover — are still unwinding.

**The silent-drop failure mode.** Forum thread 739656 reproduces `requestReview()` doing nothing at
all when called from a view reached via `NavigationLink`, while the identical call from the root view
works. No Apple root-cause statement exists, but the action is tied to the scene of the view that
reads it, and a call made from a transient presentation context can be dropped with no error and no
feedback. For a once-ever ask, that would spend the only chance on an alert nobody saw — hence
`ReviewPromptHost` is attached to the app root and to nothing else.

**Throttling and eligibility.**

- Never rated on this device: the system shows the prompt at most **3 times per rolling 365 days**.
- Already rated on this device: shown again only if the app version is new **and** more than 365 days
  have passed.
- **Debug builds run from Xcode always display the prompt**, throttle ignored — simulator and device
  alike. This is Apple's test facility.
- **TestFlight builds: the call is a complete no-op.** Nothing is ever shown.
- App Store builds: the rules above apply.
- The user can disable review requests device-wide in Settings, invisibly to the app.
- **No return value, no callback, no way to learn whether the alert appeared.** This is why
  `recordReviewRequested()` is written on the ask and not on a rating: "we asked" is the only fact
  available, and retrying because no rating arrived would pester a user who already rated.

**Testing.** The `.storekit` configuration file and its scheme setting are for in-app purchase
testing only and have nothing to do with this API. There is no documented reset for the production
throttle. Practically:

- Validate the **decision** with `ReviewPromptTests` — the threshold is injectable
  (`ReviewPromptCoordinator.init(workoutCount:)`), so it does not need five real workouts.
- Validate the **alert itself** only in a Debug build run from Xcode, where the system throttle is
  bypassed. The app's own once-ever flag is not bypassed, and there is deliberately no debug reset
  for it (no debug surface fits, and an unwired one would be dead code): re-reaching the ask means
  deleting the app from the simulator, which clears `UserDefaults.standard`.

**Known OS bugs (none app-fixable — they are system alert-rendering issues).**

- **iOS 26.1** — the alert's "Not Now" button was unresponsive unless the user first tapped a star
  (Forum 807408). Confirmed fixed in **iOS 26.2**. The app's deployment target is 26.1+, so users on
  the initial 26.1 release can hit it.
- **iPadOS 26.4 beta 2/3** — the call fires but no sheet appears (Forum 818088, FB22157147). Beta
  only at time of research.
- **iOS 26.5 beta** — the always-show-in-development behaviour that §"Testing" relies on reportedly
  broke (Forum 821981). Beta only; re-check when 26.5 ships.

**Sources.**
[RequestReviewAction](https://developer.apple.com/documentation/storekit/requestreviewaction) ·
[callAsFunction()](https://developer.apple.com/documentation/storekit/requestreviewaction/callasfunction%28%29) ·
[EnvironmentValues.requestReview](https://developer.apple.com/documentation/swiftui/environmentvalues/requestreview) ·
[Requesting App Store reviews](https://developer.apple.com/documentation/storekit/requesting-app-store-reviews) ·
[SKStoreReviewController.requestReview(in:)](https://developer.apple.com/documentation/storekit/skstorereviewcontroller/requestreview%28in%3A%29) ·
[AppStore.requestReview(in:)](https://developer.apple.com/documentation/storekit/appstore/requestreview%28in%3A%29-1q8qs) ·
[Forum 739656](https://developer.apple.com/forums/thread/739656) ·
[Forum 807408](https://developer.apple.com/forums/thread/807408) ·
[Forum 818088](https://developer.apple.com/forums/thread/818088) ·
[Forum 821981](https://developer.apple.com/forums/thread/821981).

There is no WWDC session on this API — it arrived quietly alongside the other SwiftUI environment
actions in iOS 16, and the documentation article above is the authoritative source.

---

## 5. Deliberate omissions

- **No pre-qualifying step.** No "do you like the app?" gate, no filtering by predicted sentiment.
  `docs/settings-tab.md` §5.1 records this as an App Review rejection risk and as explicitly
  discouraged by Apple.
- **No second trigger.** One threshold, one ask. A PR trigger is discussed in §3b; a "share your
  streak" or milestone trigger would need the same collision analysis §3a did.
- **No TestFlight release note.** The prompt is not a capability the user can invoke, and announcing
  it would be both odd and self-defeating.
- **No new localized strings.** Deliberate — the alert is the system's.
- **No in-app measurement.** There is nothing to measure: see §4. Read the rating count in App Store
  Connect.

---

## 6. Monetization

```
Monetization verdict — in-app rating prompt
  Tier          Free
  Derivation    §3 Rule 1 (sits on the aha path: workout logged → number goes up);
                §3 Rule 3 (never in an active workout, on the watch, or beside a paywall)
  Mechanism     none — no countable unit, no shallow version, nothing to withhold
  Placement     n/a — no PaywallPlacement case, no new gated strings
  Nudge         none
  Free residue  the entire feature
  Founder note  irrelevant — this is a ranking input, not a conversion surface
```

Re-checked at delivery: what shipped is free, ungated, invisible in UI copy, and suppressed inside a
workout and beside a paywall. No drift from the planning verdict.

---

## 7. Tests

`GymStreakTests/ReviewPromptTests.swift`, following the `ProactivePaywallTests` harness convention —
a throwaway `UserDefaults(suiteName:)` per test, the real stores and presenter, a stubbed totals
provider.

| Test | Asserts |
|---|---|
| `reviewPromptThresholdClearsTheValueMoment` | 5 > 3 — the invariant of §3a |
| `belowThresholdAsksNothing` | 4 workouts asks nothing, records nothing |
| `thresholdWorkoutAsks` | The 5th workout asks (the §3c off-by-one) |
| `laterWorkoutStillAsks` | 40 workouts still asks — `>=`, not `==` |
| `asksOnce` | Once, ever |
| `recordSurvivesRelaunch` | A second coordinator over the same defaults asks nothing |
| `reportingWithoutADueRequestRecordsNothing` | A stray host report spends nothing |
| `activeWorkoutSuppressesTheAskWithoutConsumingIt` | Rule 3 defers rather than consumes |
| `placementBCompletionAsksForNoRating` | No collision, against the real paywall stack |
| `ratingArrivesAfterPlacementBIsSpent` | The deferral resolves once B is spent |
| `killSwitchOffStillAsks` | With gating off the ask is not blocked forever |
