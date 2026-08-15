# Swift 6 Concurrency

> Status: **the whole project compiles in Swift 6 language mode** (`SWIFT_VERSION = 6.0`)
> with `SWIFT_APPROACHABLE_CONCURRENCY` on, zero warnings across all six targets in both
> Debug and Release, and all 458 unit tests passing (verified 2026-08-12).
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

Three independent boundaries, two different actors, same failure, same fix — treat
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
comment are carried by `LifetimeTrainingTotalsProviding` (ticket 11) — a second, narrow
read boundary conformed to by the *same* provider struct, so there is still one
`@ModelActor` and one `ModelContext`, and `lifetimeTotalsKeepMainActorResponsive` types
it as the existential exactly like the four cases above it.
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

## 4. The WatchConnectivity delegate boundary

`WCSessionDelegate` callbacks arrive on a **background queue**. The established
pattern — keep it — is: `@MainActor final class` manager, each delegate requirement
individually `nonisolated`, hopping via `Task { @MainActor in … }`.

`Task { @MainActor in }` (not `DispatchQueue.main.async`, not
`MainActor.assumeIsolated`) is deliberate: SE-0431 guarantees that tasks targeting an
actor are **enqueued in creation order**, so callback order is preserved — which the
watch sync protocol depends on. `MainActor.assumeIsolated` would *trap* here, because
these callbacks genuinely are not on the main thread.

`assumeIsolated` is not banned, though — it is correct when the callback is *documented
or configured* to arrive on the main thread. `CloudKitSyncStatusMonitor` uses it
legitimately for a `NotificationCenter` observer registered with `queue: .main`.

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

## 10. Rules for new code

1. **New ViewModels**: `@Observable @MainActor final class`.
2. **New shared service**: `@MainActor final class X { static let shared = X() }`,
   behind a `@MainActor` Domain protocol, wired in `AppDependencies`.
3. **Pure logic in `Domain/Services/`**: keep it isolation-free. Do not add
   `@MainActor` to it — the actor-owned History store calls into it off-main.
4. **New Apple delegate conformance**: `@MainActor` class, each delegate method
   `nonisolated`, hop with `Task { @MainActor in … }`, and **extract `Sendable` values
   before the hop**. Never capture the framework object itself.
5. **Reaching for an escape hatch?** Rank: `nonisolated` (checked — always prefer) →
   `Sendable` boundary projection → `@preconcurrency import` (Apple's gap) →
   `@unchecked Sendable` box (only with a written invariant) → `nonisolated(unsafe)`
   (avoid). The first two are not escape hatches at all; the last two must be
   justified in a comment.
6. **An `async` boundary that must do its work off the caller's actor needs
   `@concurrent` on the concrete method** — `nonisolated async` alone does not
   guarantee it under SE-0461 (§1). Run
   `largeSnapshotBuildKeepsMainActorResponsive` after touching such a boundary, and
   add a case to `SwiftDataHistorySnapshotStoreTests` for each **new** boundary rather
   than writing a one-off test elsewhere.
7. **A new method on `SwiftDataHistorySnapshotStore` must contain no internal `await`**
   (§1). The shared-actor safety argument rests entirely on that.
8. **Moving a read that takes a caller-supplied `@Model` off the main actor?** Do not
   pass its id and re-fetch unless the object is provably saved (§1). Send `Sendable`
   values and keep the bounded live-object read on the caller — a re-fetch miss is
   silent, not an error.
9. **Do not** "normalize" the build settings table in §1 — each deviation is measured.

## Sources

- SE-0411 isolated default value expressions · SE-0412 strict concurrency for global
  variables · SE-0431 task enqueue ordering · SE-0449 `nonisolated` on type
  declarations · SE-0461 `nonisolated(nonsending)` by default / `@concurrent` ·
  SE-0466 control default actor isolation · SE-0470 global-actor isolated conformances
  · SE-0371 isolated synchronous deinit
- [Swift Migration Guide](https://www.swift.org/migration/documentation/migrationguide/)
- `os.Logger` is `Sendable` (Apple DTS, forums thread 747816); `FileManager.default`
  is documented thread-safe for the non-delegate operations used here.
- Related in-repo docs: `docs/history-performance.md`, `docs/architecture.md`,
  `docs/watch-sync.md`, `docs/ai-coach.md`.
