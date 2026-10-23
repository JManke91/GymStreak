# Watch: Digital Crown adjusts weight and reps

**Target:** watchOS only (`GymStreakWatch Watch App`). The iOS target is untouched —
set values reach the phone through the normal completed-workout sync.
**Source:** Things "Gym Streak" → "Adjust weights using digital crown"; local tickets in
`.scratch/watch-crown-weight-adjust/` (01 = tap-to-arm stepping, 02 = Crown glyph affordance
+ VoiceOver, 03 = "Tap first" on a locked turn, 04 = draining relock border + tap-to-lock).
**Tier:** Free — monetization §3 Rule 3 (inside an active workout, on the watch). No cap,
placement or nudge.

## Behaviour

In the in-workout set editor (`FullScreenSetEditorView`), **tapping the weight or reps
card focuses it (as before) and unlocks the Digital Crown for it.** The ± buttons work on
the focused card without any tap — unlocking is only for the Crown. While unlocked:

- each Crown detent steps the focused value by one unit of what the user is reading —
  1 kg or 1 lb for weight, 1 for reps — with a click (our own `.click` per applied change;
  the system detent haptic is off, see "Holding the Crown while locked");
- weight is **not snapped**: a 60 kg set read in pounds steps 132.3 → 133.3 lb, exactly
  like the ± buttons (`docs/weight-unit-preference.md` §9a);
- values clamp to 0…999 kg (canonical) and 0…100 reps. Clicks continue at a bound —
  accepted (the click is played per detent change, before the clamp);
- the card's Crown + lock glyph is green and open (see "Discoverability" below).

The Crown **re-locks** automatically:

| Trigger | Where |
|---|---|
| 3 s without Crown input (± taps do not hold it open; a re-tap on a card restarts the 3 s) | `SetValueCrownInput.scheduleRelock` |
| Set completion toggled | `FullScreenSetEditorView.toggleSetCompletion` |
| A rest starts or ends | `.onChange(of: viewModel.isResting)` |
| Ownership lost for any reason — the pill's ± stepper opens, a minimized rest expands to the large timer, mutation is suspended | `.onChange(of: ownsCrown)` |
| Set or exercise changes (chevrons, superset hop, list) | `.onChange(of: currentSetIndex / currentExerciseIndex)` |
| The editor disappears | `.onDisappear` |

While locked, the editor still holds the Crown (to show "Tap first"), but a turn **changes
nothing, shows no indicator and plays no click** — the detent handler only applies steps
while `isActive`, the binding is continuous, and the system haptic is off from installation
(see "Holding the Crown while locked"). The ± buttons stay live at all times. When the Crown
cannot be unlocked (`canUnlockCrown == false`: rest timer holds it, workout frozen or input
suspended), tapping a card still focuses it but does not unlock the Crown, and the glyph
disappears.

## Discoverability (2026-10-23)

The first version (tap unlocks, a green open-lock glyph appears *after* the tap) passed
manual testing but failed as UX: weight is pre-focused and ± already edit it, so nobody has
a reason to tap the card; the only signal came after the tap; and a Crown turned first was a
dead input, so users concluded the Crown does nothing here. The fix keeps "never by
accident" and adds no hurdle to ±:

**1. Persistent state glyph — Crown + lock.** The focused card always shows a
`digitalcrown.arrow.clockwise` + `lock.fill` pair at the end of its unit line, muted while
locked. A tap turns the pair green and the lock **morphs open** (`lock.open.fill`,
`.contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))`) with one `.bounce`;
the 3 s relock morphs it shut again. Under Reduce Motion the symbol simply swaps
(`.identity`) and does not bounce. The Crown glyph says *what* is locked — a lock alone would
read as "this value cannot be edited", which the live ± contradicts. Hidden on the
unfocused card and whenever the Crown cannot be unlocked (rest timer owns it, workout
frozen). The unlock haptic is the tap's existing `.click`; relock is silent.

*Placement root cause:* corner overlays (top- and bottom-trailing) were tried in an
`ImageRenderer` probe and collide on a 40 mm card with a wide value ("132,3") or the German
unit ("Wdh."). Inline in the unit `HStack` cannot collide; it only widens the centred unit
line, never the card's height.

**2. "Tap first" on a locked turn.** The editor holds the Crown while locked (focusable
whenever no rest-timer candidate owns it), so a locked turn is observable. It changes
nothing; once the rotation reaches 2 detents the focused card's unit line cross-fades to a
green **"🔒 Tap first"** / **"🔒 Antippen"** whose lock wiggles once as it appears (not under
Reduce Motion). It stays up while the turning goes on and fades 1.5 s after the last locked
detent. It shows on **every** locked turn — no once-per-set, no retirement — so the user
always learns what to do at the moment they try. A tap hides it. The hint carries its own
lock because it covers the unit line, and with it the card's lock glyph. German is
"Antippen" (not "Erst antippen"): the wiggling lock already says *unlock*, and the shorter
word leaves room for the glyph on a 40 mm card.

**3. The relock is visible — draining border.** While unlocked, the card's green border
becomes a countdown: a dim track with a bright stroke that drains linearly from full to
empty over the 3 s relock delay (`TimelineView(.animation)` against
`crownRelockDeadline`, redrawing only while unlocked). Every Crown detent refills it, because
every detent restarts the delay; when it empties the lock morphs shut. The modifier reports
each (re)start with `onRelockScheduled(deadline)`, so the timer and the border have one
source. It stays on under Reduce Motion: it is information confined to the card's edge, not
movement. Options weighed: a filling lock icon (≈ 8 pt, unreadable mid-set), a draining
card background (fights the value text).

**4. Tap again to lock.** A tap on the card that is already unlocked locks it at once, so
the lock glyph toggles both ways; a tap on the other card moves the unlocked Crown there.

**VoiceOver** does not depend on unlocking at all: each card exposes
`accessibilityAdjustableAction` (swipe up/down, the ± write path) with the hint "Swipe up or
down to adjust". Unlocking is not announced — a VoiceOver user has no reason to unlock.

### Holding the Crown while locked — what made it silent

A first attempt at holding the Crown while locked (with a "Tap first" limited to once per
set and retired after 3 uses) **failed the physical-watch test, 2026-10-23**: a locked turn
showed the **system Crown scroll indicator** and played **detent haptics**
(`isHapticFeedbackEnabled` flipped to `false` at runtime did not take — it is evidently read
when the modifier is installed); focus requested in `onAppear` on the pushed editor did not
take, so the Crown only responded after the first tap; and a missed hint was gone for good.
An intermediate round therefore made the locked editor non-focusable and showed a
"Tap = Crown" hint for 2 s on opening — rejected by the user (a hint at the start is not
when the user needs it).

The current version holds the Crown while locked again, with three changes (research:
ios-api-researcher, 2026-10-23):

- **`isContinuous: true`** — the only reported way to suppress the indicator (forum
  [707381](https://developer.apple.com/forums/thread/707381), watchOS 9 era; a later comment
  says it can still flash ~1 s when focus arrives). The counter now wraps at ±10 000;
  `WatchSetValueStepping.detents(from:to:wrappingAt:)` reads a wrap as the short way round.
- **`isHapticFeedbackEnabled: false` from installation**; the unlocked detent click is our own
  `WKInterfaceDevice.current().play(.click)` per applied change. A locked turn is silent.
- **Focus on appear:** `.defaultFocus($isCrownFocused, true)` plus a 400 ms delayed
  `isCrownFocused = true` in `.task` (past the push transition), and re-assertion on
  `scenePhase == .active`.

All three are **undocumented** behaviour, so this was run as a device spike — **passed on
a physical Apple Watch, 2026-10-23**: no indicator and no clicks on a locked turn (before
the first tap and after a relock), the first turn is caught. Should a future watchOS break
it, fall back to the non-focusable locked editor (`.focusable(isActive)`, system haptics on)
and keep the draining border and toggle.

## Architecture

| Piece | File | Role |
|---|---|---|
| `WatchSetValueStepping` | `Models/WatchSetValueStepping.swift` | Pure stepping rule: `weight(_:steppedBy:in:)`, `reps(_:steppedBy:)`, `detents(from:to:wrappingAt:)`. **The one stepping rule** — the ± buttons were moved onto it too, so there is no second rule to drift. |
| `setValueCrownInput(...)` modifier | `Views/SetValueCrownInput.swift` | Owns the Crown binding, focus (`isListening`), the 3 s relock task (`SetValueCrown.relockDelay`, reported via `onRelockScheduled`), the unlocked detent click, the commit-once-per-rotation flag and the locked-rotation detent count. Knows nothing about sets. |
| `FullScreenSetEditorView` | `Views/FullScreenSetEditorView.swift` | Owns `isCrownUnlocked`, the relock deadline and the locked-turn hint, derives `canUnlockCrown`/`ownsCrown`, the tap toggle, wires the relock triggers, maps detents to a set via `stepped(_:field:by:)`. |
| `CompactValueEditor.crownState` / `crownRelockDeadline` / `showsCrownHint` / `onAdjust` | `Views/CompactValueEditor.swift` | The Crown + lock glyph (unavailable / locked / unlocked) with its Magic Replace morph, the draining relock border, the "🔒 Tap first" hint, VoiceOver adjust. |
| `adjustSetValue` / `commitSetValueAdjustment` | `ViewModels/WatchWorkoutViewModel.swift` | The Crown write path. |

### Crown ownership

The editor joins the single-owner model in `docs/watch-rest-timer-ui.md` ("Crown
ownership"). Holding and editing are separate:

```swift
canUnlockCrown = !isCoveredByRestTimer && !isRestPillStepperOpen && viewModel.canMutateWorkout  // focusable, glyph shown
ownsCrown      = isCrownUnlocked && canUnlockCrown                                             // detents edit
```

`isCoveredByRestTimer` is the `.largeTimer` owner and `isRestPillStepperOpen` is the
`.pillStepper` owner, both already published as environment values by
`ActiveWorkoutView` — so the editor can never be focusable alongside either. Holding the
Crown while locked is harmless: the editor is a fixed screen pushed over the exercise list,
nothing underneath could scroll. Because a rest start, and any loss of `ownsCrown`, also
clear `isCrownUnlocked`, a hand-back returns the Crown *held* but never *unlocked*; only a
fresh tap unlocks it.

*Root cause recorded:* the first version re-locked on `isRestPillStepperOpen` only. The
architecture review caught that expanding a minimized pill to the large timer removed
ownership without re-locking, so minimizing again silently handed the Crown back. Re-locking
on the derived `ownsCrown` closes every such path at once.

### Write path: silent, checkpointed once per rotation

`updateSet` (the ± path) plays `.success` and writes the recovery checkpoint on every call.
Per detent that would double the system detent click and write the checkpoint 5–10×/s — the
same reasons `updateRestTime` is silent (rest-timer rule 2 and 7). So the Crown writes via
`adjustSetValue` (mutation only, gated on `canMutateWorkout`) and the modifier calls
`commitSetValueAdjustment()` (→ `persistActiveCheckpoint`) once: on `onIdle`, when the
Crown is taken away mid-rotation (`isActive` → false), and on disappear. Both VM methods
share `replaceSet`, so the mutation itself is one code path.

### The detent counter

There is no delta API on the Crown. The modifier binds a scratch `Double` counter
(`detent:`, stride 1, range ±10 000, `isContinuous: true`) and applies `new − old` from
`onChange(of:)` — this is what keeps the weight unsnapped (the value-binding overload with
`by:` snaps to a grid). The counter is never re-centered; being continuous (to hide the
system indicator) it **wraps** at ±10 000, and `detents(from:to:wrappingAt:)` reads a jump
wider than the bound as the short way round. The wrap period is taken as 2 × 10 000 while
the range has 20 001 positions, so a wrap may be off by one detent — at most one step,
once per ~10 000 detents; accepted. A fast spin can deliver several detents in one change;
the stepping functions clamp the multi-step result.

### Focus

`.focusable(isListening)` precedes `.digitalCrownRotation` and sits on the same view as
`.focused($isCrownFocused)` (with `.focusEffectDisabled()` between — the focusable view is
the whole editor, a system focus ring around it would be noise). Focus is requested by
`.defaultFocus`, again 400 ms after appearing, on `scenePhase == .active`, and **one tick
after** `isListening`
changes (`Task { @MainActor in … }`) and mirrored on every change — forum reports say
focus set in the same update that makes a view focusable does not take, and that crown
focus does not reliably move across pushed views without an explicit toggle. The modifier
is applied to the editor's content `VStack`, the same pattern `RestTimerLargeView` uses with
its own buttons inside.

## Research findings (ios-api-researcher, 2026-10-10)

- API: `digitalCrownRotation(detent:from:through:by:sensitivity:isContinuous:isHapticFeedbackEnabled:onChange:onIdle:)`
  (watchOS 9+). The binding only changes by whole strides; `isHapticFeedbackEnabled`
  gives the system detent click. Generic over `BinaryFloatingPoint` — no `Int` overload.
- No delta API: `DigitalCrownEvent` has only `offset` and `velocity` → scratch counter.
- The value-binding `by:` overload snaps to a grid → wrong model for unrounded weights; not used.
- `sensitivity: .medium`, passed explicitly (Apple's pages disagree on the default). Tune on device.
- Detent haptics keep clicking at the clamped bounds — accepted.
- `digitalCrownAccessory` is not an input API and has a forum-reported bug together with
  `digitalCrownRotation` (forum 761954) — not used.
- Whether revoking focusability while focused hands the Crown back cleanly is
  **undocumented** → device check.
- No documented system mechanism requires deliberate Crown engagement or suppresses the
  Crown on wrist-down / Always-On; Water Lock is user-initiated and unusable as a gate.
- Sources: Apple docs for
  [`digitalCrownRotation(detent:…)`](https://developer.apple.com/documentation/swiftui/view/digitalcrownrotation(detent:from:through:by:sensitivity:iscontinuous:ishapticfeedbackenabled:onchange:onidle:)-17066),
  [`DigitalCrownEvent`](https://developer.apple.com/documentation/swiftui/digitalcrownevent),
  [`digitalCrownAccessory(_:)`](https://developer.apple.com/documentation/swiftui/view/digitalcrownaccessory(_:));
  forums [761954](https://developer.apple.com/forums/thread/761954),
  [683806](https://developer.apple.com/forums/thread/683806),
  [767044](https://developer.apple.com/forums/thread/767044),
  [115562](https://developer.apple.com/forums/thread/115562).

Follow-up research (ios-api-researcher, 2026-10-23, discoverability rounds):

- `focusEffectDisabled(_:)` "controls whether this view can display focus effects, such as a
  default focus ring" (compiles on watchOS 26).
- No documented API hides the Crown indicator or observes the Crown silently; the
  `isContinuous: true` workaround and the haptics/focus measures are in "Holding the Crown
  while locked". `isHapticFeedbackEnabled` changes at runtime did not take on device.
- Programmatic Crown focus on a pushed view on appear is undocumented (`defaultFocus`,
  `prefersDefaultFocus`, delays); the device showed a plain one-tick request not taking.
- No Crown + lock SF Symbol exists → `digitalcrown.arrow.clockwise` + `lock.fill` /
  `lock.open.fill`. Magic Replace (`.replace.magic(fallback:)`) is watchOS 11+ and animates
  lock ↔ lock.open (shared base shape); the watch target is watchOS 26.
- `accessibilityAdjustableAction` is triggered by VoiceOver swipe up/down on watch; the Crown
  does not drive it.

## Discarded approaches

- **Dedicated lock/unlock button** — an extra tap per set mid-lift, and a forgotten unlock
  leaves the Crown live. Tapping a card already selects it, so tap-to-unlock arms for free
  and stays deliberate (a sleeve brush cannot arm it).
- **Always-live Crown with tuned sensitivity** — reduces accidental changes, never
  eliminates them.
- **Value-binding `by:` overload** — snaps to the display grid, destroying off-grid weights.
- **Routing Crown detents through `updateSet`** — doubles the detent haptic and checkpoints
  per detent; see "Write path".
- **A lock glyph that appears only after the tap** (ticket 01's indicator) — feedback, never an
  affordance. Replaced by the always-visible Crown + lock pair.
- **Crown glyph alone, muted/green** (first discoverability round) — on device the user asked
  for a clearer locked/unlocked state; the lock carries it, the Crown names what is locked.
- **"Tap = Crown" for 2 s on opening** — shown when the user does not need it; replaced by
  the hint on a locked turn.
- **"Tap first" once per set, retired after 3 uses** — a missed hint was lost for good.
- **A filling lock icon / draining background as the relock countdown** — see
  "Discoverability" 3.
- **A one-time coach screen** ("Tap a value, then turn the Crown") — dismissed unread
  mid-lift and teaches away from the moment of need; the just-in-time hint teaches exactly
  when the user tries.
- **Arming on the first ± tap** — invisible again, and arms the Crown after an action that
  did not ask for it.
- **Crown glyph as a corner overlay** — collides on 40 mm; see "Discoverability".

## Known follow-ups

- `FullScreenSetEditorView.swift` is ~450 lines (364 before this feature; limit 300). The Crown
  state needs the view's `@State`, so extract the parts that do not: `topTrailingAccessory` →
  an elapsed-time accessory view, `steppersCluster`/`stepperButton`/`metricsCluster` → a
  value-cluster view (architecture review, 2026-10-23).
- If input is suspended mid-rotation, `commitSetValueAdjustment()` skips the checkpoint
  (`canMutateWorkout` guard), so up to one rotation lives only in memory until the next
  mutation — the same trade-off as `updateRestTime`; a crash in that window loses it.

## Deliberately not built

- **No VoiceOver announcement of arming/disarming** (ticket 02 originally had one) —
  VoiceOver users adjust by swipe and have no reason to arm; an announcement on every tap and
  on the silent 3 s disarm would be noise. Restore with
  `AccessibilityNotification.Announcement(...).post()` in `selectCard` / `lockCrown`.

## Verification

- `GymStreakWatchTests/WatchSetValueSteppingTests.swift`: detent deltas (single, multi,
  rounding noise), kg stepping, lb non-snapping and round trip, multi-step = repeated
  single steps, weight and reps bounds.
- Build: watch app + `GymStreakWatchTests` and iOS app + `GymStreakTests` compile with no
  new first-party warnings (2026-10-21).
- Unit suites green 2026-10-23: watch 163 tests / 16 suites, iOS 1775 tests / 188 suites + 4 XCTest
  (ticket 01); after the discoverability rounds watch 164 tests / 16 suites (iOS untouched),
  incl. `wrappedCounter` for the continuous detent counter.
- Card states rendered with a throwaway `ImageRenderer` probe at 40 mm width with the 46 mm
  font (worst case) in German — locked / unlocked with the border at 73 % and 27 % /
  "🔒 Antippen" on both cards — no collisions.
- **Physical watch, 2026-10-23: all checks below passed.** XCUITest cannot rotate the
  Crown, so the Crown behaviour itself is a **physical-watch check**: a locked turn on first opening (before any tap) shows "🔒 Antippen" with **no
  scroll indicator and no clicks**; unlock with the lock morph and our own detent clicks;
  the border drains and refills per detent and the lock closes when it empties; tap again
  locks; Crown after a set/exercise swap and after returning from rest; no focus ring.
