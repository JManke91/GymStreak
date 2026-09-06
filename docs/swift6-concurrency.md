# Swift 6 Concurrency

> Status: **the whole project compiles in Swift 6 language mode** (`SWIFT_VERSION = 6.0`)
> with `SWIFT_APPROACHABLE_CONCURRENCY` on, zero warnings from first-party sources across
> all six targets in both Debug and Release, and all unit tests passing — 728 iOS + 34
> watch (verified 2026-08-23; previously 458 on 2026-08-12). One warning does come out of
> the build and is expected: a RevenueCat deprecation with no non-SPI replacement, recorded
> in §9c. Anything beyond it is a regression.
>
> ⚠️ **A green build is not proof of correct isolation.** §4a records a `@MainActor`
> closure that compiled without a single warning and trapped on every launch of
> TestFlight build 1.1.10 (1001). Read it before handing any closure to an Apple API.
>
> This document is the reference for how concurrency is expressed in GymStreak,
> which build settings are deliberate, and which mistakes are already paid for.
> Read it before changing isolation, adding a singleton, or touching a build setting.

---

## 1. Build settings (deliberate, do not "normalize")

Set at **project level** unless noted, so new targets inherit them:

| Setting | Value | Scope |
|---|---|---|
| `SWIFT_VERSION` | `6.0` | **Project level** — all six targets |
| `SWIFT_APPROACHABLE_CONCURRENCY` | `YES` | **Project level** — all six targets |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` | **Watch app only** |
| `SWIFT_STRICT_CONCURRENCY` | unset | Redundant under language mode 6 (which implies `complete`) |

### ⚠️ SE-0461 can silently move the History aggregation back onto the main actor

This is the single most important finding in this document. **It is fixed in code, not
by avoiding a build setting** — but the failure mode is invisible (the build stays
green), so understand it before touching this boundary.

`SWIFT_APPROACHABLE_CONCURRENCY = YES` enables **SE-0461 (`nonisolated(nonsending)`
by default)**, which changes a `nonisolated async` function to run **on the caller's
actor** instead of hopping off it. The History read boundary
(`HistorySnapshotProviding` → `SwiftDataHistorySnapshotProvider` →
`SwiftDataHistorySnapshotStore`) exists precisely to keep unbounded fetches,
relationship faulting and whole-history aggregation **off** the main actor. With the
setting on and no `@concurrent`, calling `fetchTrainingSnapshot` from a `@MainActor`
ViewModel ran that entire aggregation **on the main actor**, reproducing the hang in
`docs/history-performance.md`.

**The fix: `@concurrent` on the concrete `SwiftDataHistorySnapshotProvider`
methods** (three at migration time; seven today — audit P1.2 added
`fetchExerciseProgress`, P1.6 `fetchPreviousPerformances`, and Pro ticket 11 both
`fetchLifetimeTotals` — the widest of them, no date window at all — and
`fetchCompletedWorkoutCount`, which is annotated even though it is only a
`fetchCount`, because it still enters the model actor). That restores the
unconditional "always leave the caller's actor" contract, so the guarantee is a
property of the code and survives any build-setting change.

Measured with `GymStreakTests/SwiftDataHistorySnapshotStoreTests`:

| Configuration | `heartbeat.maximumDelay` | Verdict |
|---|---|---|
| Swift 5, approachable OFF (pre-migration) | within the 100 ms budget | ✔ |
| Swift 6, approachable ON, **no `@concurrent`** | **~600 ms** (0.597 / 0.611 / 0.616 s) | ✘ |
| Swift 6, approachable ON, **`@concurrent` on the provider** | within budget | ✔ **shipped** |

Re-measured independently on 2026-08-13 when `fetchExerciseProgress` joined the same
boundary (`largeExerciseProgressBuildKeepsMainActorResponsive`, 240 sessions × 5
exercises × 4 sets): **307 ms** stall without `@concurrent` on that one method, within
budget with it. Measured a third time the same day on a **different model actor** —
audit P1.3's `ChatFactProvider` → `ChatFactStore`
(`chatFactLookupKeepsMainActorResponsive`, same 240-session fixture): **319 ms** without
`@concurrent` on `exercisePRFacts`, within budget with it.

Measured a fourth time on 2026-08-28 when the AI-coach exercise deep-dive joined the
History provider (ticket 02, `exerciseDeepDiveAggregationKeepsMainActorResponsive`, same
240-session fixture plus a live library entry): **311 ms** without `@concurrent` on
`fetchDeepDiveAggregate`, within budget with it. Build green either way, again — and
this one had been running on the main actor in shipped code, reached from a `Task { }`
created on a `@MainActor` ViewModel, which is exactly the call shape SE-0461 leaves on
the caller's actor.

Four independent boundaries, two different actors, same failure, same fix — treat
`@concurrent` on a new method at any such boundary as mandatory, not advisory, and prove
it by deleting the annotation once and watching the test go red before you ship.

**Two variants that did NOT fix it, with an important caveat about why:**

1. `@concurrent` on the `HistorySnapshotProviding` *protocol requirements* — measured
   616 ms.
2. Removing the actor's own `HistorySnapshotProviding` conformance — measured 599 ms.

⚠️ **Neither measurement supports a general claim**, and an earlier version of this
document wrongly asserted one ("`@concurrent` on the requirement does not work — the
witness stays caller-isolated"). Both numbers were taken while the test called the
**concrete** provider directly, so the protocol annotation could not have influenced
that call path at all — 616 ms is simply the cost of an unannotated concrete method.
(Flagged by architecture review 2026-08-12; claim retracted.)

**What the specifications actually say** (researched 2026-08-13):

- **SE-0461 does not discuss protocol requirements, witnesses, or existentials at all** —
  an exhaustive search of the proposal finds zero occurrences of "witness" or
  "existential". So there is **no documented rule** about whether a requirement's
  `@concurrent` spelling propagates to, or must be matched by, its witness. Record that
  as *not documented*, not as *does not work*.
- SE-0461 does establish that `@concurrent` **implies `nonisolated`**, cannot apply to
  synchronous functions, and that the nonsending/concurrent distinction is an **ABI-level
  calling-convention difference** ("the caller's actor must be passed as a parameter").
- **SE-0338** (quoted) explains the underlying mechanism: non-actor-isolated async
  functions "never formally run on any actor's executor… they will switch to a generic,
  non-actor executor when it's called." The actor-switch is emitted in the **callee**,
  not at the call site — which is consistent with the witness's own annotation governing
  execution regardless of concrete-vs-existential dispatch. *(Inference from SE-0338, not
  a statement about `@concurrent` + existentials; treat the mechanism as unconfirmed.)*

**What is empirically verified in this repo:** `@concurrent` on the concrete methods
keeps the work off the main actor **including through existential dispatch** — the
regression test types the provider as `any HistorySnapshotProviding`, matching how
`HistoryViewModel` calls it. Cancellation also still propagates across the hop
(`cancellingTheCallerPropagatesThroughTheConcurrentHop`).

Any new type conforming to `HistorySnapshotProviding` that does real work must carry
`@concurrent` on its own methods. The actor deliberately no longer conforms, so it
cannot be injected as an unannotated conformer. The same rule and the same warning
comment are carried by `LifetimeTrainingTotalsProviding` (ticket 11) and
`ExerciseDeepDiveFactProviding` (ticket 02) — narrow read boundaries conformed to by the
*same* provider struct, so there is still one `@ModelActor` and one `ModelContext`, and
`lifetimeTotalsKeepMainActorResponsive` / `exerciseDeepDiveAggregationKeepsMainActorResponsive`
type it as the existential exactly like the cases above them. Three protocols on one
provider is the pattern, not an accident: a new question about history gets its own
narrow boundary and the existing actor, never a new actor.
`largeSnapshotBuildKeepsMainActorResponsive` is the acceptance criterion — a green
build cannot catch this.

### Why `@concurrent` is belt-and-braces, not redundant

It would be tempting to argue the `@ModelActor` hop alone should suffice. It does not,
and the reason is worth recording: **Apple does not document that the executor
`@ModelActor` synthesises guarantees off-main execution.** The best available secondary
source ([Massicotte, *ModelActor is Just Weird*](https://www.massicotte.org/model-actor/))
observes a `@ModelActor`-isolated method satisfying `MainActor.preconditionIsolated()`
— i.e. running on the model actor *and* the main actor simultaneously — and states
plainly "as far as I can tell, this is not documented". The same source describes
`@ModelActor` construction as sensitive to *where* it is created, which is exactly why
`SwiftDataHistorySnapshotProvider` builds the store inside `Task.detached`.

So the off-main guarantee rests on two independent, deliberate mechanisms — the
`Task.detached` construction and the `@concurrent` entry points — precisely because
neither SwiftData's executor behaviour nor construction affinity is contractual.

### One actor per feature, and when to add a second (audit P1.3)

Apple documents neither "one actor per feature" nor "one shared actor" as guidance
(researched 2026-08-13; the `@ModelActor` macro is explicitly designed to be
instantiated against a shared `ModelContainer`, so several actors on one container is
the intended pattern, not a misuse). The choice is ours, so record the reasoning:

`HistorySnapshotProviding` declines to give the exercise-detail chart its own actor,
because that would mean "a second `ModelContext` warming the same rows" for **one
screen's** data. `ChatFactStore` does take a second actor, for reasons that do not
apply there:

- the two boundaries return different *kinds* of thing (display snapshots vs. English
  fact lines for an on-device model) and belong to different features;
- chat tool calls fire mid-stream, and a shared actor would serialise them behind a
  ~300 ms whole-history snapshot build;
- the AI coach is opt-in and hardware-gated, so most users should never pay for its
  context at all.

The accepted cost is a second read-only `ModelContext` registering the same rows while
the chat screen lives. Neither context caches across calls — every method refetches —
so the documented cross-context staleness of SwiftData (a context does not see another
context's saves without a refetch; community-confirmed, not Apple-documented) cannot
bite either of them. **Neither actor writes**, which is the property that makes two
contexts on one container uninteresting here; a second *writing* context would be a
different question entirely.

### One shared `@ModelActor` is safe only while every method is `await`-free inside

`SwiftDataHistorySnapshotStore` now serves four screens, so two calls can be in flight
at once (History reloading while the pushed exercise chart loads). That is safe, and the
reason is precise rather than incidental: **Swift actors are reentrant only at suspension
points.** The language guide states that code between potential suspension points "runs
sequentially, without the possibility of interruption from other concurrent code", and the
runtime holds the actor's lock for the whole synchronous run, releasing it only at a real
`await`. Every method on the store is `async` but contains **no internal `await`** — all
SwiftData fetches are synchronous — so each runs to completion before the next is dequeued.

Adding an `await` inside one of those methods would open a genuine interleaving window on
a single non-`Sendable` `ModelContext`. If a future read needs to await something, hoist
that work to the caller or give it its own actor. Apple documents neither "one actor per
feature" nor "one shared actor" as guidance (researched 2026-08-13) — the choice is ours,
and this invariant is what makes the shared one defensible.

### Getting a `@Model`'s identity into a model actor: send values, not an id to re-fetch

Researched 2026-08-14 for audit P1.6, which had to move a read that takes a
caller-supplied main-context `WorkoutSession`. An `@ModelActor` cannot accept a `@Model`
from another context, so the obvious port is "pass the `id`, re-fetch inside". **That is
only sound when the object is provably saved**, and three separate gaps say so:

| Question | Status |
|---|---|
| Does a second `ModelContext` see the main context's **unsaved** changes? | **Undocumented.** Apple DTS reproduced inconsistent behaviour across OS versions on forum thread 763487 and explicitly declined to state the expected one. |
| When does `mainContext` autosave fire? | Default `autosaveEnabled == true` for `mainContext` (and `false` for any context you construct, including the one `@ModelActor` synthesizes) **is** documented. The *timing* is not — "key lifecycle events", with no bound. |
| Is `PersistentIdentifier` the safe handle instead? | It is the documented, `Sendable`, purpose-built one — but `PersistentIdentifier.isTemporary` is `true` until the origin context saves, and Apple documents that temporary ids "should not be persisted or used to create durable maps to a model". Same precondition, stated from the other side. |

So the rule is about the *precondition*, not the mechanism: if the object is definitely
saved (History reads over completed workouts), `PersistentIdentifier` is the better-supported
handle than our own `id: UUID` + `#Predicate`. If it might not be — anything reading a
workout the user is still in, e.g. the save sheet — **send `Sendable` values describing
what you need instead** (`PreviousPerformanceLookup` is the worked example) and keep the
bounded read of the live object on the caller's side.

What makes this worth a rule rather than a judgement call is the failure mode: a re-fetch
that finds nothing returns *empty*, not an error. In P1.6's case that would have rendered
as "New exercise" on every row — a confident false statement about the user's history,
with a green build and no warning.

One related correction while here: prefetching cannot follow a key path *through* a to-many
relationship (`\.workoutExercises.sets`) — that is a **Swift `KeyPath` limitation, not a
SwiftData one**, since key-path composition needs each segment to resolve to a single
value. `CompletedSessionFetch`'s two-step warm-up is the workaround, and its reliance on
the context's identity map stays an inference from Core Data's documented uniquing, not a
SwiftData guarantee. Note also that Apple DTS has confirmed (forum thread 772608,
FB16858906) that `relationshipKeyPathsForPrefetching` **still triggers a fetch on attribute
access in some cases** — treat it as a strong optimization, not a guarantee.

### `#Predicate`: keep optional-chained relationship comparisons out of it

Also researched 2026-08-13, while considering date-bounding the exercise-chart fetch.
Apple publishes **no enumerated list of supported `#Predicate` expression shapes**;
`SwiftDataError.unsupportedPredicate` exists but only covers the cases SwiftData detects.
Community investigation reports that a single optional-chain hop with equality (which we
already ship: `exercise.workoutSession?.endTime != nil`) works, while **multi-hop chains
and `??` feeding a comparison operator can compile and then return silently wrong
results** rather than throwing. That failure mode is worse than a crash, so the rule is:
keep in-store predicates to the simple proven shape and do richer filtering in Swift
**inside the model actor**, where it is still off the main thread. `fetchExerciseProgress`
does exactly that with its `startDate` window.

A second opinion arrived with the P1.3 research (2026-08-13) recommending we rewrite
`exercise.workoutSession?.endTime != nil` into an `if let` form. **Declined**, and the
reason is recorded so it is not re-proposed: the source it rests on describes the
*multi-hop / `??`-into-comparison* shapes as the risky ones and reports the
single-hop-with-equality shape we ship as working. Rewriting a shipped, heartbeat-tested
fetch on a speculative reading is the larger risk. The rule below is unchanged: keep
in-store predicates to this one proven shape and filter further in Swift.

Related: `relationshipKeyPathsForPrefetching` is documented only for the fetch it is
attached to. The cross-fetch trick — warm `WorkoutExercise` with
`[\.sets, \.workoutSession]`, then fetch `WorkoutSession` — relies on `ModelContext`'s
identity map, which Apple does not document. It is an empirical bet covered by the
heartbeat tests, so new code must **reuse the helper** rather than invent a second fetch
ordering that makes the same undocumented bet independently. Since P1.3 gave the AI-coach
actor the same need, that helper is `Data/Persistence/CompletedSessionFetch`
(`withFullGraph` for the two-step warm-up above, `withRoutine` for callers that only date
sessions against a routine and must not fault the set graph). Both model actors call it;
the bet is written down once.

### ⚠️ `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` stays watch-only

SE-0466 lets a module default every otherwise-nonisolated declaration to
`@MainActor`. It fits the **watch** target well: no SwiftData, no Domain layer,
almost entirely UI and view models, with a small enumerable set of genuinely
background types (see §3).

It does **not** fit the iOS app target, and this was measured too. Enabling it
there made the entire `Domain/` layer implicitly main-actor-isolated:

- the pure `Domain/Services/` namespaces (`PersonalRecordService`,
  `HistorySnapshotBuilder`, `FortschrittAggregator`, …) became `@MainActor`, so the
  `@ModelActor` History store could no longer call them from its own executor;
- the SwiftData `@Model` classes became `@MainActor`, so even after marking the
  services `nonisolated` the services could not read model properties
  (`isCounterweightAssistance`, `order`, `supersetId`, …) — 16 errors and climbing.

`Domain/` is isolation-agnostic by design (Clean Architecture: it depends on
nothing, including an actor). A module default of `MainActor` actively misdescribes
it, and pushing through would have required annotating the whole layer `nonisolated`
just to restore the status quo. The iOS target keeps `nonisolated` as its default
and annotates the ~62 types that genuinely are main-actor (already the established
convention: every ViewModel carries `@MainActor` explicitly).

---

## 2. Singleton patterns

Every shared service is `@MainActor final class X { static let shared = X() }`.
Under strict concurrency this is not merely a style choice — a `static let` of a
**non-`Sendable`** type is global shared mutable state and a hard error. Global-actor
isolation makes the class implicitly `Sendable`, which fixes it.

Converted during this migration:

| Type | Was | Now | Why |
|---|---|---|---|
| `HapticManager` (`Presentation/DesignSystem.swift`) | bare `class`, no isolation | `@MainActor final class` | every member drives main-actor-only UIKit feedback generators; all ~83 call sites are already in SwiftUI bodies/actions, so this costs no hops |
| `AICoachAvailability` | `@Observable final class` | `+ @MainActor` | mutable state read directly by SwiftUI; also let `refresh()` drop its `await MainActor.run { … }` wrapper |
| `AICoachPreferences` | `@Observable final class` | `+ @MainActor` | same |

Making those two `@MainActor` required their Domain protocols
(`AICoachAvailabilityProviding`, `AICoachPreferencesProviding`) to become
`@MainActor` as well — under **SE-0470** a global-actor-isolated type satisfying a
nonisolated protocol requirement is a conformance-isolation error. The rest of the
AI-coach protocol surface was already `@MainActor`, so this made it uniform.

### Default arguments and `.shared` — the gotcha is NOT what the docs used to say

`docs/architecture.md` previously claimed `= Foo.shared` default arguments on a
`@MainActor` singleton are a permanent Swift 6 error requiring a `nil`-default
workaround. **That is wrong.** Verified directly against the compiler:

```
swiftc -swift-version 5  →  warning: main actor-isolated static property 'shared'
                            can not be referenced from a nonisolated context
swiftc -swift-version 6  →  (no diagnostic)
```

**SE-0411 (isolated default value expressions)** makes it legal: a default argument
of a `@MainActor`-isolated function may reference that actor's state. The Swift 5
warning is an artifact of the pre-SE-0411 rule, and it disappears in language mode 6
(where the upcoming feature is on by default).

`CoachChatViewModel` was still converted to the `nil`-default + resolve-in-init-body
form — but for **consistency** with its four sibling AI-coach ViewModels
(`PeriodRecapViewModel`, `ExerciseDeepDiveViewModel`, `PostWorkoutRecapViewModel`,
`WorkoutAnalysisViewModel`), which already use it, not because it is required. Either
form compiles. Prefer the sibling pattern for new AI-coach ViewModels.

---

## 3. `nonisolated` on a type — a *checked* opt-out

Under the watch target's default-MainActor isolation, four stateless helper types
were silently made `@MainActor`, which made them unreachable from the `nonisolated`
`WCSessionDelegate` callbacks that legitimately need them. All four are now
`nonisolated`:

| Type | Location (both targets where duplicated) | Contents |
|---|---|---|
| `WatchSyncDiagnostics` | `Data/Sync/`, `Watch/Managers/` | one `Logger` (`Sendable`) + pure static log/hash helpers |
| `WatchWorkoutWire` | `Data/Sync/`, `Watch/Models/` | immutable `String` wire keys + pure predicates |
| `WatchExerciseCatalogSync` | `Data/Sync/`, `Watch/Models/` | immutable metadata/context keys |
| `ExerciseCatalogInbox` | `Watch/Managers/ExerciseCatalogStore.swift` | `appGroupID` + synchronous `FileManager` move |

**`nonisolated` is the right tool here, and it is not warning-suppression:**

- **SE-0449** (Swift 6.1) exists specifically to allow `nonisolated` on a *type*
  declaration to opt out of global-actor inference. Before it you had to annotate
  every member; the type-level form is the purpose-built spelling for a namespace
  where every member needs it.
- **It stays checked.** Verified with the compiler: adding `static var counter = 0`
  or a non-`Sendable` stored static to a `nonisolated enum` is *still* a hard error
  under Swift 6 (`#MutableGlobalVariable`). `nonisolated` removes the inherited
  isolation, not the data-race checking. This is categorically different from
  `nonisolated(unsafe)` and `@unchecked Sendable`, which *do* disable checking.
- For these types the `@MainActor` was the **false** statement — they hold no
  isolated state, and the module default merely lost information the code already
  documented in its comments.

`ExerciseCatalogInbox` is the decisive case: `WCSessionFile`'s temporary file is
deleted the moment `session(_:didReceive:)` returns, and `WCSessionFile` is not
`Sendable`. Moving that work into the `Task { @MainActor in }` hop would be a **bug**,
not a tidier alternative.

---

## 4. The WatchConnectivity delegate boundary (inbound)

Callbacks WatchConnectivity delivers *to* us. For the closures we hand *to* it, see §4a
— a separate hazard with a separate fix.

`WCSessionDelegate` callbacks arrive on a **background queue**. The established
pattern — keep it — is: `@MainActor final class` manager, each delegate requirement
individually `nonisolated`, hopping via `Task { @MainActor in … }`.

`Task { @MainActor in }` (not `DispatchQueue.main.async`, not
`MainActor.assumeIsolated`) is deliberate: SE-0431 guarantees that tasks targeting an
actor are **enqueued in creation order**, so callback order is preserved — which the
watch sync protocol depends on. `MainActor.assumeIsolated` would *trap* here, because
these callbacks genuinely are not on the main thread.

**The `@MainActor in` is load-bearing, not decoration — a bare `Task { … }` does not get
that guarantee.** SE-0431 scopes creation-order enqueue to closures with an *explicit*
isolation marker (a global-actor attribute or an explicit `isolated` capture) and
deliberately **excludes** closures that are merely *implicitly* isolated by their context,
so that bare `Task {}` does not become a scheduling bottleneck. Inside an already-`@MainActor`
type, `Task { await self.foo() }` therefore still runs on the main actor but with
**unspecified enqueue order**. It compiles, it looks identical, and it silently loses
ordering. It was written that way for one review cycle in
`AppDependencies.onWorkoutInboxUpdated` while making the watch drain gate-aware.

Be precise about what that would actually have cost, though — the first write-up of this
overstated it. Payload-vs-payload ingestion order was never at risk: the drain iterates
`WatchWorkoutInboxStore.entries()`, which sorts by arrival-timestamp filename, so whichever
task wins the gate drains everything oldest-first and the loser finds an empty inbox. Inbox
order is a property of the **store**, not of task scheduling. What genuinely depends on task
order is one drain kind preceding another — `routineAuthorityDidChange` (receipt recovery)
before a plain `drainInbox` — and even that converges, since it re-drains after
`recoverReadyReceipts()`. So: spell the isolation explicitly on any `Task` whose ordering
matters, because it is free and strictly stronger — but do not audit the codebase for bare
`Task {}` on the premise that each one is a live ordering bug.
([SE-0431](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0431-isolated-any-functions.md))

`assumeIsolated` is not banned, though — it is correct when the callback is *documented
or configured* to arrive on the main thread. `CloudKitSyncStatusMonitor` uses it
legitimately for a `NotificationCenter` observer registered with `queue: .main`.

#### NotificationCenter is the *opposite* of the rule-4 hazard — and a hop is mandatory

`addObserver(forName:object:queue:using:)` takes
`using block: @escaping @Sendable (Notification) -> Void`. **The block parameter is
`@Sendable`**, unlike WatchConnectivity's completion handlers, which annotate nothing.
That inverts everything about it:

- Under [SE-0461], a closure literal whose *contextual type* is `@Sendable` is inferred
  **nonisolated**, even written inside a `@MainActor` class. So there is no silent
  main-actor inference, no compiler-inserted `assumeIsolated`, and **the SE-0423 runtime
  trap that crashed TestFlight 1.1.10 cannot occur here.** The annotation gap that makes
  §4a dangerous is exactly what is absent.
- The flip side: because the block is nonisolated, **some hop is mandatory** —
  `Task { @MainActor in … }` or `MainActor.assumeIsolated`. A bare synchronous call to a
  `@MainActor` method from inside the block is *not* merely a style choice.

Measured on this project's toolchain, so nobody has to re-derive it: a bare call compiles
with **`warning: call to main actor-isolated instance method '…' in a synchronous
nonisolated context`** — a warning, not an error, under
`SWIFT_APPROACHABLE_CONCURRENCY`. That makes it a **zero-warning-invariant regression that
still builds and still passes tests**, which is precisely how it slips in. It was written
and then reverted once during calendar sync ticket 03 (`docs/calendar-sync.md` §12b); a
build log grepped only for `error:` will not catch it.

#### SwiftUI's `alignmentGuide` closure is genuinely off-actor

Found while building the onboarding welcome slide (2026-09-04, `docs/onboarding.md`).
`CheckBullet` read an `@ScaledMetric` property from inside an `alignmentGuide` closure and
the build warned:

> main actor-isolated property 'baselineInset' can not be referenced from a Sendable closure

**Not a spurious diagnostic.** `SwiftUICore.swiftinterface` (iOS 26.5) declares it

```swift
@preconcurrency @inlinable nonisolated public func alignmentGuide(
    _ g: VerticalAlignment,
    computeValue: @escaping @Sendable (ViewDimensions) -> CGFloat
) -> some View
```

`@Sendable` **and** `nonisolated`: SwiftUI calls it during layout, off the view's actor, so
reading a `@MainActor`-isolated stored property there captures `self` across the boundary —
the outbound half of rule 4, and the class of defect that crashed TestFlight 1.1.10.

**Fix: snapshot the metric into a local `let` in `body`**, on the main actor, so the closure
captures a plain `CGFloat` and nothing else — the *Sendable boundary projection* rung of the
escape-hatch ranking. `@preconcurrency import`, `nonisolated(unsafe)` and
`MainActor.assumeIsolated` would each have hidden the capture instead of removing it. The
repo's other `alignmentGuide` call sites (`FullScreenSetEditorView`, `WorkoutTopProgressView`,
and the note in `WorkoutRestTimerOverlay`) read only `ViewDimensions`, capture nothing, and
were already correct.

### Nothing non-`Sendable` may cross the hop

Two categories had to be fixed, both by extracting at the boundary:

**1. `WCSession` itself** (a non-`Sendable` class). Read the flags synchronously in
the nonisolated callback and send only the values:

```swift
nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    let isReachable = session.isReachable          // read here…
    Task { @MainActor in
        self.isReachable = isReachable             // …send only the Bool
    }
}
```

Same for `isPaired` / `isWatchAppInstalled` — immutable `Bool` snapshots of the moment
the callback fired.

**⚠️ The session's *mutable* snapshot state is the exception: do NOT hoist it.**
`receivedApplicationContext` and `outstandingFileTransfers` are read **inside** the hop
from the manager's stored `self.session` (the same `WCSession.default` singleton the
callback receives), so they are sampled when used. Hoisting them was tried and
reverted: it opened a window between callback and hop in which a catalogue transfer
started in that gap would be missing from `cleanUpOrphanedStagingFiles(keeping:)` and
its staging file deleted mid-flight. The rule is *"extract the immutable values, read
the mutable ones on the far side"*.

The activation callback's **load-bearing ordering** is unchanged either way: challenge
update before inbox drain, then orphan cleanup, then `sessionDidBecomeReady()`.

**2. The `[String: Any]` plist payloads** (`Any` is not `Sendable`). These cross via
`WatchWirePayload`, a documented `@unchecked Sendable` box in `WatchWirePayload.swift`
(one copy per target):

```swift
nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    let boxed = WatchWirePayload(message)
    Task { @MainActor in
        self.handleIncomingPayload(boxed.payload, source: "message")
    }
}
```

**Why a box and not a re-typed `Sendable` value** (deliberate, do not "fix"):
re-encoding each plist value into a closed `Sendable` enum would risk silently
dropping or widening a value the sync protocol depends on — the routine authority
already encodes `UInt64` generations as decimal strings precisely because plists are
lossy here. Boxing keeps the received payload byte-identical and leaves all ~7
existing parsers (`TemplateAckRecord.from(payload:)`,
`RoutineSnapshotHeader.parse(context:)`, `WatchRoutineSync`, the catalogue challenge
readers, …) untouched. That matters on a sync path with a documented incident history.

The `@unchecked` rests on a stated invariant, not optimism: WatchConnectivity builds a
fresh dictionary per delivery, hands it over, and neither retains nor mutates it; the
values are immutable property-list types. This mirrors the pre-existing
`HealthKitWorkoutObserver.CompletionBox`, which boxes HealthKit's non-`Sendable`
completion handler for the same reason.

`WatchWirePayload` is also `nonisolated` — it is constructed inside nonisolated
callbacks, and the watch target's default isolation would otherwise make even its
initializer main-actor-isolated.

---

## 4a. Outbound completion handlers — the direction that shipped a crash

§4 covers callbacks WatchConnectivity delivers **to** us. This covers the closures we
hand **to** it, which is a separate hazard with a separate fix — and the one that
actually crashed a TestFlight build.

### The incident

GymStreak **1.1.10 (1001)** crashed a few seconds after every launch on iOS 26.6.
Crash report `GymStreak-2026-08-23-120321.ips`:

```
EXC_BREAKPOINT (SIGTRAP)   faulting thread 2 — NSOperationQueue (QOS: UTILITY)

_dispatch_assert_queue_fail
dispatch_assert_queue
_swift_task_checkIsolatedSwift
swift_task_isCurrentExecutorWithFlagsImpl
GymStreak                                    ← our errorHandler closure
GymStreak                                    ← block→closure thunk
-[WCSession _onqueue_notifyOfMessageError:messageID:withErrorHandler:]_block_invoke
-[NSBlockOperation main]
```

Not a nil unwrap. An **actor-isolation precondition failure**: a `@MainActor`-isolated
closure invoked on WatchConnectivity's private operation queue. (`EXC_BREAKPOINT` plus
`swift_task_isCurrentExecutor*` / `dispatch_assert_queue` in the stack is the
signature. How the report was pulled off the device in the first place:
`docs/crash-report-retrieval.md`.)

### Why it happens, and why nothing warned

**`WatchConnectivity` is entirely un-annotated for concurrency.** `WCSession.h` in the
iOS 26 SDK contains **zero** `NS_SWIFT_SENDABLE` and **zero** `NS_SWIFT_UI_ACTOR`, and
`WatchConnectivity.apinotes` adds none. So `sendMessage`'s handler imports as a plain,
non-`Sendable` `((any Error) -> Void)?`.

Then two rules combine:

1. **[SE-0461] closure isolation inference** (restating [SE-0306]): *if the contextual
   type of the closure is neither `@Sendable` nor `sending`, the closure inherits the
   enclosing context's isolation.* Our closures are literals inside a
   `@MainActor final class`, so they are inferred `@MainActor`.
2. **[SE-0423] dynamic actor isolation enforcement**: passing a synchronous
   actor-isolated function value to an API that erases isolation and has not adopted
   strict concurrency is **deliberately not diagnosed**. The compiler instead wraps the
   body as `MainActor.assumeIsolated { … }`. Off the main actor that is a fatal
   precondition, implemented for `MainActor` as `dispatch_assert_queue(main)`
   ([SE-0424]).

So it compiles with zero warnings in Swift 6 mode *by design* — SE-0423 exists
precisely to trade a source break for a runtime check. **There is no build setting,
`-strict-concurrency` level, or upcoming feature that turns this back into a warning.**

It shipped because `errorHandler` is a failure-only path: nothing in development ever
sends a message to an unreachable watch and waits for the timeout.

### The rule

> **Every closure literal handed to a WatchConnectivity API must be marked
> `@Sendable`.** Then hop with `Task { @MainActor in … }` for anything touching
> main-actor state, extracting `Sendable` values *before* the hop as in §4.

```swift
// @Sendable is load-bearing, not decoration.
session?.sendMessage(payload, replyHandler: nil) { @Sendable [weak self] error in
    WatchSyncDiagnostics.notice("… \(error.localizedDescription)")   // extract BEFORE the hop
    Task { @MainActor in
        self?.workoutQueueDrainRequester.messageSendFailed()
    }
}
```

`@Sendable` is not merely a capture-checking attribute: SE-0461's second rule makes a
`@Sendable` closure **inferred `nonisolated`**, so no isolation is inferred, no
`assumeIsolated` wrapper is emitted, and no check exists to fail. ([SE-0434] is
one-directional — isolation implies `@Sendable`, not the reverse — so writing it
explicitly does not pull isolation back in.)

The three fixed sites (2026-08-23): `WatchConnectivityManager.sendAck` and
`.sendWorkoutQueueDrainMessage` (iOS), `.sendWorkoutMessage` (watch). `sendMessage` is
the only WCSession API the app calls that takes a block at all — `transferUserInfo`,
`transferFile`, `updateApplicationContext` and `activate` are block-free, so the
framework surface is fully covered.

### Three traps around the fix

**⚠️ `@Sendable` is NOT sufficient if the closure is `async`.** With
`SWIFT_APPROACHABLE_CONCURRENCY` on (§1), a `@Sendable` *async* closure becomes
`nonisolated(nonsending)` and inherits the **caller's** isolation at runtime — putting
you straight back on WatchConnectivity's queue with main-actor expectations, or worse.
All three handlers here are synchronous, which is why the fix holds. If one is ever
made `async`, it needs `@concurrent` — the same SE-0461 trap as rule 1 in §1.

**⚠️ `nonisolated` on a closure literal does not exist.** [SE-0449] allows
`nonisolated` on declarations, extensions and types — not on closures. The "closure
isolation control" pitch that would add it was never accepted and is not in Swift 6.2.
`@Sendable` is the only spelling available.

**⚠️ `@preconcurrency import WatchConnectivity` does NOT fix this.** It downgrades
`Sendable`-conformance diagnostics; it does not change closure isolation inference. The
SE-0423 check is inserted *because* the module is under-annotated, so the trap would
survive the import while checking elsewhere got weaker. (Contrast §8, where the
ActivityKit import addresses a real non-`Sendable` value crossing an `await`.) And
**never** add `-disable-dynamic-actor-isolation`: it converts this crash into a silent
main-actor data race.

### Proving the fix — do not assume, check the mangling

Unit tests cannot catch this: the handler is a failure-only path, and the check is
fatal only when it actually runs. Two cheap ways to *verify* an isolation fix:

**1. Look for `Yb` in the emitted symbol.** `Yb` is Swift's mangling for `@Sendable`.
A closure without it inherited the enclosing isolation and carries the precondition:

```bash
nm "$(...)/GymStreak.app/GymStreak.debug.dylib" | grep sendWorkoutQueueDrainMessage
# ...ys5Error_pYbcfU_   ✅ @Sendable — no check emitted
# ...ys5Error_pcfU_     ❌ isolated  — will trap off-main
```

**2. A/B the two shapes at `-O`** and diff the emitted calls. This is how the fix was
confirmed on 2026-08-23 — same file, both shapes, real `WCSession`:

```bash
xcrun -sdk iphonesimulator swiftc -swift-version 6 -O \
  -target arm64-apple-ios26.1-simulator -emit-assembly repro.swift -o repro.s
grep -E "isCurrentExecutor|checkIsolated|reportUnexpectedExecutor" repro.s
```

The un-annotated closure emits `swift_task_isCurrentExecutor` +
`swift_task_reportUnexpectedExecutor`; the `@Sendable` one emits neither. **Both
compile with zero warnings**, which is the whole point.

⚠️ **Two traps when doing this.** Use a **real imported ObjC API** — a hand-written
Swift stub with a non-`Sendable` closure parameter does *not* reproduce it, because
SE-0423's check only appears at the boundary with non-strict-concurrency code. And do
not test on a **Debug** build: Xcode enables `-enable-actor-data-race-checks` there,
which puts `reportUnexpectedExecutor` at the head of *every* main-actor function and
drowns the signal.

### How to prevent a recurrence

The attribute is invisible and easy to drop. Two stronger options, neither adopted yet —
weigh them if a fourth call site ever appears. **The full decision, the rejected
alternatives (including restructuring the adapter) and the triggers to reopen it are
recorded in [ADR 0002](adr/0002-guard-watchconnectivity-outbound-closures-with-rules.md).**

1. **A typed seam**, which makes the compiler reject a main-actor literal at every call
   site instead of relying on the attribute being remembered:
   ```swift
   nonisolated extension WCSession {
       func sendMessage(_ message: [String: Any], onError: @escaping @Sendable (any Error) -> Void)
   }
   ```
2. **Pass a `nonisolated static func` reference** instead of a literal — its function
   type is non-isolated by declaration, so it cannot silently regress, and the body
   becomes directly testable by calling it from `Task.detached { }`.

Verified against the iOS 26 SDK headers on 2026-08-23. Sibling frameworks are **not**
affected: HealthKit annotates its handlers `NS_SWIFT_SENDABLE`
(`HKObserverQuery.h:32`, `HKSampleQuery.h:57`) — which is exactly why
`HealthKitWorkoutObserver` needed its `CompletionBox` — and so does `NSTimer.h:38`.
WatchConnectivity is the outlier.

[SE-0306]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md
[SE-0423]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0423-dynamic-actor-isolation.md
[SE-0424]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0424-custom-isolation-checking-for-serialexecutor.md
[SE-0434]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0434-global-actor-isolated-types-usability.md
[SE-0449]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0449-nonisolated-for-global-actor-cutoff.md
[SE-0461]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md

---

## 5. `isolated deinit` for main-actor teardown

A nonisolated `deinit` may not touch non-`Sendable` stored properties. Three classes
tear down `Timer`s and `NSObjectProtocol` observer tokens, so all three now use
**`isolated deinit`** (SE-0371), which runs the deinit on the class's own actor:

- `Presentation/ViewModels/WorkoutViewModel.swift` — 2 timers + 4 observer tokens
- `Data/Sync/CloudSyncObserver.swift` — 1 observer token
- `Data/Sync/CloudKitSyncStatusMonitor.swift` — observer array + `NWPathMonitor`

`CloudKitSyncStatusMonitor` previously used a "copy the values into locals first"
trick with a comment claiming it kept deinit off the main actor. **That did not
satisfy the checker** — reading the stored property *is* the cross-actor access — so
the trick was removed rather than preserved.

---

## 6. Boundary value types instead of crossing framework objects

`NSPersistentCloudKitContainer.Event` is a non-`Sendable` class delivered to a
nonisolated notification handler. It is now projected into `SyncEventSummary`
(`Data/Sync/CloudKitSyncStatusMonitor.swift`), a `Sendable` struct built **at the
boundary**, carrying `identifier`, `type`, `endDate`, `succeeded`, an
`errorDescription` and a precomputed `isAccountProblem`. That last field is why the
non-`Sendable` `CKError` no longer needs to travel at all — the classification that
used to be `isAccountProblem(_:)` happens during extraction.

Prefer this shape (extract a `Sendable` projection at the boundary) over boxing,
whenever the consumer only needs a handful of values. Boxing is for the case in §4
where preserving the payload exactly is the point.

---

## 7. XCTest and isolation

`XCTestCase.setUpWithError()` / `tearDownWithError()` are **`nonisolated`** in XCTest.
An override must match its superclass's isolation, so overriding the throwing
*synchronous* variants **strips the class's `@MainActor`** — after which every
`XCUIApplication` touch is a cross-actor access. The `async` variants inherit the
class isolation correctly:

```swift
@MainActor
final class SomeUITests: XCTestCase {
    override func setUp() async throws { … }      // ✔ inherits @MainActor
    override func tearDown() async throws { … }   // ✔
    // override func setUpWithError() throws { }  // ✘ nonisolated, strips @MainActor
}
```

Converted: `GymStreakUITests.swift`, `HistoryResponsivenessUITests.swift`,
`WorkoutDeletionUITests.swift`, `GymStreakWatchUITests.swift`.

Also: `waitForExpectations(timeout:handler:)` takes a **nonisolated** completion
closure, so reading a main-actor `XCUIElement` property inside it (for a failure
message) is a cross-actor access. Use `await fulfillment(of:timeout:)` instead and
assert afterwards on the test's own actor — see
`SettingsTabUITests.testICloudRowReportsOffWithoutICloudAccount`.

---

## 8. `@preconcurrency import` for under-annotated Apple modules

`Data/LiveActivity/ActivityKitRestTimerPresenter.swift` uses
`@preconcurrency import ActivityKit`, and is the only file in the app target that
imports ActivityKit at all.

**Correction (2026-08-13, audit P1.5):** this section previously said the import
lived in `WorkoutViewModel` and that `Activity.end(_:dismissalPolicy:)` "is a
`@concurrent` async method". Both were wrong, and the second was never true.
Read out of the iOS 26.5 SDK's `ActivityKit.swiftinterface`:

```swift
public class Activity<Attributes> : Swift.Identifiable where … {   // not Sendable, no isolation
  public static func request(attributes:content:pushType:) throws -> Activity<Attributes>
  public static var activities: [Activity<Attributes>] { get }
  public func end(_ content: ActivityContent<…>?, dismissalPolicy: ActivityUIDismissalPolicy = .default) async
}
```

`end` carries **no** attribute at all — it is a plain `nonisolated async` method.
The real reason the import is needed is simpler: `Activity` is a non-`Sendable`
class, ActivityKit's module is built `-swift-version 5` without SE-0461, so
`await activity.end(…)` still leaves the main actor and the activity crosses an
isolation boundary. **Verified by removing the attribute:** the build fails with
`error: sending 'self.activity' risks causing data races` at that `await`.

`ActivityContent<State>` *is* conditionally `Sendable` (`where State: Sendable`),
so only the `Activity` instance itself is the problem. `ActivityAuthorizationInfo`
is likewise a non-`Sendable` `final class`, but it is created and read locally and
never crosses.

**Remove the import once ActivityKit ships concurrency annotations** — re-verify by
deleting `@preconcurrency` and building, rather than by reading release notes.

---

## 9. Non-concurrency fixes made in the same pass

The migration also cleared 16 stale-API/deprecation warnings:

- **`AICoachService`** — FoundationModels moved on: `prewarm()` is synchronous, and
  `streamResponse(…)` **no longer throws**. Errors now surface when the returned
  stream is *iterated*. The creation-time `do`/`catch` + `mapError` had become
  unreachable dead code and was removed; the four consuming ViewModels already call
  `AICoachTelemetry.recordError` in their `for try await` catch blocks (chat streams
  through `CoachChatService`, not `AICoachService.stream()`), which is where
  the error actually arrives. Two new `GenerationError` cases
  (`.concurrentRequests`, `.refusal`) had also made the switch non-exhaustive.
  *Deliberate omission:* per-`GenerationError`-case logging was dropped with that dead
  code; if wanted, it belongs at the iteration sites (see git history for the old
  `mapError`).
- **`Text` `+` operator** (deprecated iOS/watchOS 26) → **`AttributedString`** with
  per-run attributes, in `StreamingTextView` and `WorkoutTopProgressView.setCounter`.
  *Discarded approach:* Apple's suggested replacement `Text("\(a)\(b)")` is a
  `LocalizedStringKey`, so it mints catalog entries — it created an untranslated
  `"%@, Set %lld of %lld"` key that **regressed the German VoiceOver label**, plus a junk
  `"%@%@%@"` key, and on the streaming path it would run a localization lookup per
  snapshot (~30 Hz). `AttributedString` carries the styling with no key and no lookup.
  For the accessibility label, `Text(verbatim:)` + `String(localized: "Set \(x) of \(y)")`
  reuses the existing translated key. **Note:** when setting an explicit run `font`, keep
  `.monospacedDigit()` if the call site applied it — an explicit run font overrides it
  (this bit the current-set digit in `setCounter`).
- **`onChange(of:perform:)`** (deprecated watchOS 10) → two-/zero-parameter closures
  in `RestTimerLargeView`, `RestTimerMinimizedPill`.
- **Unused `if let` bindings** → `!= nil` in `HealthKitWorkoutManager` (×2) and
  `GymStreakWidgetsLiveActivity`.
- **`WatchTemplateTransactionService.MergePlan.empty`** — was a `static let` on a type
  holding SwiftData `@Model` references (so never `Sendable`); now a computed
  `static var`, which owns no global at all.
- **`GymStreakIntents`** — `static var title` → `static let` (a mutable static is
  global shared mutable state; `AppIntent.title` is a get-only requirement).

---

## 9a. `Task { }` inherits isolation — it defers, it does not offload

Quoted from the Swift migration guide (`DataRaceSafety.md`): **"a newly-created task will
inherit the isolation of its enclosing scope unless an explicit global actor is
written."** So inside a `@MainActor` type:

```swift
Task { … }                 // runs on the MainActor, one turn later — NOT off-main
Task { @MyActor in … }     // runs on MyActor
```

This matters at `AICoachService.prewarm()`, whose `Task { }` was previously commented as
if it kept work off the caller's turn. It does not; the comment is corrected. SE-0461's
mechanism for genuinely leaving the actor is a **`@concurrent` function declaration**
(as used by `SwiftDataHistorySnapshotProvider`), not an unstructured `Task`.
`Task.detached` also leaves, but severs cancellation and priority — prefer `@concurrent`
unless you specifically want detachment (the History store's *construction* is a
deliberate `Task.detached`).

## 9b. Explicitly unverified — do not turn these into claims

Recorded so nobody re-derives a confident answer from nothing (researched 2026-08-13):

| Question | Status |
|---|---|
| Does `@concurrent` on a *protocol requirement* propagate to / constrain the witness? | **Not documented.** SE-0461 never mentions witnesses or existentials. |
| Is a witness required to match the requirement's `nonisolated(nonsending)`/`@concurrent` spelling, or is a thunk synthesised? | **Not documented.** |
| Is `Task { @concurrent in … }` valid syntax? | **Unverified** — not used anywhere here. |
| Is `LanguageModelSession` `Sendable`; are `init()` / `prewarm(promptPrefix:)` safe off the main actor; must the session be retained for `prewarm()` to take effect? | **Not documented / unretrievable.** Hence `prewarm()` was left on the main actor. |
| Does `@ModelActor`'s synthesised executor guarantee off-main execution? Is construction-site affinity contractual? | **Not documented by Apple**; secondary evidence says no (see §1). |
| Does `FoundationModels.Tool.call(arguments:)` run off the main actor? | The **requirement** is declared `@concurrent` in the iOS 26 SDK (documented, researched 2026-08-13). Whether that governs our *unannotated* witnesses is the same undocumented witness question as above — so `ChatFactProvider` does not depend on it and carries its own `@concurrent`. Apple's own `FindContacts` sample leaves `call` unannotated. |

## 9c. The one warning the build does emit

The zero-warning invariant is about *our* code. As of 2026-08-26 exactly one warning
survives a clean build, and it is not fixable from here:

```
GymStreak/Presentation/Views/Pro/ProPaywallView.swift:203:21: warning: 'paywallComponents'
is deprecated: Use hasPaywall to check whether the Offering has a paywall.
```

`paywallPayloadState(of:)` logs three states — `present`, `declared-but-absent`, `none` —
and the middle one only exists because RevenueCat can serve a paywall *marker* without the
components payload (remote config resolves components from `/v1/config`, so a launch that
could not reach that endpoint keeps the marker and loses the payload). Telling that apart
from a real payload is the entire point of the function: in Release those two are the
difference between the authored paywall and a blank-looking default template.

The SDK's suggested replacement cannot express it. `Offering`'s public, non-deprecated
surface is only `paywall` and `hasPaywall`, and `hasPaywall` is `true` for both states.
The property that *does* draw the line — `hasPrunedPaywallComponents` — lives in an
extension marked `@_spi(Internal)` (`Sources/Purchasing/Offering.swift`), as does
`internalPaywallComponents`. Reading either needs `@_spi(Internal) import RevenueCat`,
which would be the project's first SPI import and would break on SDK upgrades without
warning.

So the options are: keep one deprecation warning, take on an SPI import, or collapse the
diagnostic to two states. **Keeping the warning is the deliberate choice** — the log label
is worth more than the clean build line, and the alternatives are each worse. Swift has no
per-expression deprecation suppression, and the wrap-in-a-deprecated-helper trick only
moves the warning to the helper's call site.

Revisit when RevenueCat promotes `hasPrunedPaywallComponents` out of `@_spi`.

## 9d. Actor isolation does not isolate a SwiftData *store*

`@ModelActor` gives a context its own executor. It does **not** give it its own view of the store.
Another context can delete a row this one has already fetched, and the next property read on that
object is an uncatchable `fatalError` from `SwiftData/BackingData.swift` — not a thrown error, not a
notification. SwiftData has no equivalent of Core Data's
`setQueryGenerationFrom(NSQueryGenerationToken.current)` and no
`automaticallyMergesChangesFromParent`; `isDeleted` reports only deletes staged in the object's own
context, and `relationshipKeyPathsForPrefetching` removes queries, not the invalidation window.
Apple DTS confirms there is no API-level fix ([forums/thread/800316](https://developer.apple.com/forums/thread/800316)).

This shipped as a crash: see `docs/history-delete-race.md`. The remedy is app-level mutual
exclusion — `HistoryStoreGate` (`Domain/Services/`). Rule for new code: **a background walk of a
SwiftData graph must be serialized against every context that can delete rows in it.**

One subtlety worth preserving — both of the gate's entry points are `nonisolated` on purpose. An
isolated method that `await`s the body would let a second caller in through actor reentrancy,
defeating the exclusion; being `nonisolated` (SE-0461 `nonisolated(nonsending)`) also means the body
runs on the caller's executor, so it does not disturb the `@concurrent` off-main guarantee of §1.

**Take the right entry point.** `withAccess` takes an `async` closure and is for the three
`@ModelActor` reader providers, whose bodies must `await` their actor. Every **writer** —
ViewModels, seeders, the watch ingestion coordinator — uses `withExclusiveAccess`, which takes a
*synchronous* closure. The gate is not reentrant, so suspending inside a gated write deadlocks the
app permanently with no crash, no log and no test able to catch it; the synchronous closure makes
that a compile error. The two are separate names rather than overloads because a sync closure
converts freely to `() async throws -> T`, so as overloads the `async` one would be silently
selected the moment an `await` appeared and the deadlock would still compile. See
`docs/history-delete-race.md`.

## 10. Rules for new code

1. **New ViewModels**: `@Observable @MainActor final class`.
2. **New shared service**: `@MainActor final class X { static let shared = X() }`,
   behind a `@MainActor` Domain protocol, wired in `AppDependencies`.
3. **Pure logic in `Domain/Services/`**: keep it isolation-free. Do not add
   `@MainActor` to it — the actor-owned History store calls into it off-main.
4. **New Apple delegate conformance**: `@MainActor` class, each delegate method
   `nonisolated`, hop with `Task { @MainActor in … }`, and **extract `Sendable` values
   before the hop**. Never capture the framework object itself.
5. **Handing a closure literal to an Apple API whose block is not `NS_SWIFT_SENDABLE`?**
   Mark it `@Sendable` (§4a). Inside a `@MainActor` type it is otherwise inferred
   main-actor-isolated, compiles clean, and **traps at runtime** when the framework
   calls it off-main. Check the header before assuming; WatchConnectivity annotates
   nothing, HealthKit and Foundation annotate properly.
6. **Reaching for an escape hatch?** Rank: `nonisolated` (checked — always prefer) →
   `Sendable` boundary projection → `@preconcurrency import` (Apple's gap) →
   `@unchecked Sendable` box (only with a written invariant) → `nonisolated(unsafe)`
   (avoid). The first two are not escape hatches at all; the last two must be
   justified in a comment.
7. **An `async` boundary that must do its work off the caller's actor needs
   `@concurrent` on the concrete method** — `nonisolated async` alone does not
   guarantee it under SE-0461 (§1). Run
   `largeSnapshotBuildKeepsMainActorResponsive` after touching such a boundary, and
   add a case to `SwiftDataHistorySnapshotStoreTests` for each **new** boundary rather
   than writing a one-off test elsewhere.
8. **A new method on `SwiftDataHistorySnapshotStore` must contain no internal `await`**
   (§1). The shared-actor safety argument rests entirely on that.
9. **Moving a read that takes a caller-supplied `@Model` off the main actor?** Do not
   pass its id and re-fetch unless the object is provably saved (§1). Send `Sendable`
   values and keep the bounded live-object read on the caller — a re-fetch miss is
   silent, not an error.
10. **Do not** "normalize" the build settings table in §1 — each deviation is measured.

## Sources

- SE-0411 isolated default value expressions · SE-0412 strict concurrency for global
  variables · SE-0423 dynamic actor isolation enforcement (§4a) · SE-0424 custom
  isolation checking for `SerialExecutor` (§4a) · SE-0431 task enqueue ordering ·
  SE-0434 usability of global-actor-isolated types · SE-0449 `nonisolated` on type
  declarations · SE-0461 `nonisolated(nonsending)` by default / `@concurrent` ·
  SE-0466 control default actor isolation · SE-0470 global-actor isolated conformances
  · SE-0371 isolated synchronous deinit
- [Swift Migration Guide](https://www.swift.org/migration/documentation/migrationguide/)
- `os.Logger` is `Sendable` (Apple DTS, forums thread 747816); `FileManager.default`
  is documented thread-safe for the non-delegate operations used here.
- Related in-repo docs: `docs/history-performance.md`, `docs/architecture.md`,
  `docs/watch-sync.md`, `docs/ai-coach.md`, `docs/crash-report-retrieval.md`.
