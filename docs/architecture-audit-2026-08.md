# Architecture & Scaling Audit — August 2026

> **Status (2026-08-14): live worklist, no longer findings-only.** Produced
> 2026-08-13 by four independent parallel reviews (concurrency/scaling, structural
> debt, DI/observation seams, iOS↔watchOS code sharing) run after the Swift 6
> language-mode migration (`docs/swift6-concurrency.md`) completed. **No code was
> changed by the audit itself**; the `> DONE` blocks in §3 were added afterwards by
> the changes that closed each item, and each links to its feature write-up.
>
> **What is open:** P1.1–P1.5 are done. **P1.6 is the only open P1**; all of §4's
> P2 is open; §5's P3 is deliberately unscheduled. Start at
> [§7 Sequencing](#7-sequencing) — and when you close an item, put its leftovers
> into a numbered entry there, not only into its own DONE block. P1.6 spent a day
> invisible because it was recorded as prose inside P1.2.
>
> This exists because a rules-conformance review is **not** the same question as
> "is this architecturally sound and does it scale?". The first passed; this
> document answers the second.

---

## 1. Verdict

**Shape: sound.** The MainActor-centric model with a single actor is the right
posture for this app, and this is now argued rather than assumed. The recommendation
is explicitly *not* "add more actors" — it is that `SwiftDataHistorySnapshotStore` is
a **template to reuse narrowly** in the few places doing History-shaped work.
`docs/swift6-concurrency.md` §1's finding that module-wide default-MainActor breaks
`Domain/`'s isolation-agnosticism is sound and should not be revisited.

**Scaling: not verified, and demonstrably broken in specific places.** History got
the off-main treatment; nothing else did. Two paths are arguably worse than History
was before its fix — one has *no* async boundary at all, and one is designed to hop
*onto* the main actor from a background caller.

**None of the findings below are defects introduced by the Swift 6 migration.** They
are pre-existing hazards the migration's tooling and this audit made visible.

### Cross-corroboration (the strongest signal here)

`Presentation/Views/Charts/ExerciseProgressChartView.swift` + its ViewModel were
independently flagged **P1 by two different reviews on different grounds** — the
concurrency review for an unbounded synchronous main-actor fetch, the structural
review for calling a repository directly from the View. When two lenses converge on
one file, that is the place to start.

---

## 2. Resolving a disagreement between reviews

The code-sharing research and the structural review reached **opposite conclusions**
on the 19–20 duplicated iOS/watch files. Both are correct, because they answered
different questions:

| Review | Question it answered | Conclusion |
|---|---|---|
| Code-sharing research | *What is the supported mechanism?* | A **local Swift package** is the only documented option that works for watchOS. Multi-destination framework targets have never supported watchOS; sharing one synchronized folder across two targets is undocumented and, per our own `project.pbxproj`, fragile. Duplication is nowhere sanctioned by Apple. |
| Structural review | *Is the duplication actually costing us?* | It diffed **all 20 pairs**: 6 byte-identical, 9 differing only in the Xcode header comment, 1 cosmetic reformat, 2 self-documented platform additions, 1 with deliberate two-sided extensions, 1 not a duplicate at all (sender vs. receiver implementations sharing a name). **Exactly one real undocumented drift** in ~4,600 duplicated lines. |

**Resolution: do not migrate to a shared package now.** The convention is holding —
one one-line drift is not evidence of failure. If it is ever done, SPM is the correct
mechanism and `.defaultIsolation(MainActor.self, .when(platforms: [.watchOS]))`
cleanly expresses our asymmetric isolation (needs `swift-tools-version: 6.2`).
**Revisit only if** a second real drift appears, or the test-coverage argument (P1.1)
is not satisfied more cheaply.

> **Update 2026-08-13:** it *was* satisfied more cheaply. P1.1 landed as a watch
> unit-test target with twin suites asserting the watch copies directly, so the
> duplication is now drift-detected without extracting a package. This
> strengthens the hold — a second real drift is now the only trigger left.

Two corrections worth recording from that research:
- `#if canImport(SwiftData)` **cannot** keep SwiftData off the watch — SwiftData *is*
  available on watchOS. "Never SwiftData on the watch" is a design rule with no
  compiler enforcement; it stays a review invariant.
- Known Apple bug **FB7724987**: code coverage is not gathered for local package
  targets under selective Test Plans. Relevant if we ever extract.

---

## 3. P1 — act on these

### P1.1 Stand up a watch unit-test target *before* any watch structural work
> **DONE 2026-08-13** — `GymStreakWatchTests` (hosted watchOS unit-test bundle,
> Swift Testing, own shared scheme) plus 28 seed tests over the watch copies of
> `ProgressiveOverloadService`, `WatchWorkoutStructuralReducer` and
> `WatchWorkoutInteractionPolicy`. Full write-up, build settings, isolation rule
> and one discarded approach in **`docs/watch-unit-tests.md`**. P2.9 is unblocked.

The watch target has **zero unit tests**. `GymStreakWatchUITests` is fastlane
screenshot generation, not assertions; `project.pbxproj` defines exactly one unit-test
target (`GymStreakTests`, iOS-only). Pure-logic watch files are tested only via their
iOS twins — `ProgressiveOverloadService.swift:1-24`'s own header says so. The
1682-line `WatchWorkoutViewModel` (+898 lines of extensions) has none.
*Highest-leverage finding in the audit.* Additive, ~1–2 days, unblocks **P2.9**
(corrected 2026-08-13: the original text said "P2.4/P2.5", but those are the
iOS-side AI-coach ViewModel coverage and `AppDependencies` items — a watch test
target does not touch either. §4's P2.9 row is the one that says "gated on
P1.1", and it is the watch work this actually unblocks).

### P1.2 Progress charts: unbounded synchronous fetch on the main actor
> **DONE 2026-08-13** — the aggregation moved to `Domain/Services/ExerciseProgressAggregator.swift`
> and now runs inside `SwiftDataHistorySnapshotStore` behind a fourth `@concurrent`
> provider method, `fetchExerciseProgress`. `ExerciseProgressViewModel.load()` is `async`
> behind a generation counter and drives the screen from `.task(id:)`;
> `ExerciseProgressChartView` lost its repository, its progress service and
> `loadRecentSessions`. `ExerciseProgressProviding` shrank to `compareWithPrevious`.
>
> **The magnitude claim is now measured, not inferred** (closing §6's caveat for this
> item): `largeExerciseProgressBuildKeepsMainActorResponsive` — added to the existing
> `SwiftDataHistorySnapshotStoreTests` suite as §6 recommended — records a **307 ms**
> main-actor stall at 240 sessions × 5 exercises × 4 sets when `@concurrent` is removed
> from the new method, and stays inside the 100 ms budget with it. Full write-up,
> including why the fetch stays unbounded on purpose and why the actor is shared, in
> **`docs/progress-charts.md`**. `docs/swift6-concurrency.md` §1 gained the shared-actor
> reentrancy invariant and a `#Predicate` rule that came out of the same research.
>
> **Not addressed, and not part of this finding → now tracked as [P1.6](#p16-exerciseprogressservicecomparewithprevious--unbounded-main-actor-fetch-per-exercise):**
> `ExerciseProgressService.compareWithPrevious`
> (SaveWorkoutView / WorkoutDetailView / WorkoutAnalysisAggregator) still runs on the main
> actor and issues one unbounded fetch *per exercise* via `previousPerformance`. It takes a
> caller-supplied main-context `WorkoutSession`, so it needs a different fix. Worth a P1 of
> its own. (It sat here as prose for a day, invisible to §7 — hence the "anything still only
> in a DONE block?" check now at the end of that section.)

*Flagged by two reviews.* Independently verified:
- `Domain/Models/ExerciseProgressModels.swift:64-65` — `ChartTimeframe.all.startDate`
  is `Date.distantPast`. Unbounded.
- `Data/Progress/ExerciseProgressService.swift:35-43` — `FetchDescriptor` sets **no**
  `relationshipKeyPathsForPrefetching`, then walks `session.workoutExercisesList` per
  session → N+1 relationship faults. (Prefetching exists in only 4 places in the
  codebase, 3 of them inside the History actor.)
- `Presentation/ViewModels/ExerciseProgressViewModel.swift:35-42` — `loadData()` is
  **fully synchronous, no `await` in the chain**, called from `init` and from every
  range-pill / exercise switch. `isLoading = true; …; isLoading = false` can never be
  observed because nothing yields.
- `Presentation/Views/Charts/ExerciseProgressChartView.swift:503-534` —
  `loadRecentSessions()` calls `workoutSessionRepository.fetchCompleted()` **directly
  from the View**, a second unbounded scan, violating Hard rules 1 and 3.

**Not gated behind any opt-in — every user, every chart open.** Same shape that
measured 600 ms in History.

*Fix:* add the progress reads to `HistorySnapshotProviding` /
`SwiftDataHistorySnapshotStore` (which already has a prefetch-correct
`fetchCompletedSessions()`), `@concurrent` on the concrete provider methods; make the
ViewModel `async`; move `loadRecentSessions` out of the View. Medium cost, a port of
an existing pattern rather than new design.

### P1.3 AI-coach chat facts hop *onto* the main actor to do unbounded work
> **DONE 2026-08-13** — the boundary is inverted. `ChatFactProviding` lost `@MainActor`
> and `AnyObject`; its three methods are `async`. `ChatFactProvider` (struct, `@concurrent`
> on each method) forwards into a new `@ModelActor ChatFactStore` built inside
> `Task.detached` — the `SwiftDataHistorySnapshotProvider` pattern, ported. Fact-line
> building moved to `Domain/Services/AICoach/ChatFactBuilder`, and `ExerciseNameResolver`
> moved there with it, losing the `@MainActor` it never needed. Full write-up in
> **`docs/ai-coach-chat-feasibility.md`** (delta 6).
>
> **Measured, per §6's instruction:** `chatFactLookupKeepsMainActorResponsive` joined
> `SwiftDataHistorySnapshotStoreTests` — the shared tripwire suite, as §6 recommended,
> rather than a new file — and records a **319 ms** main-actor stall at 240 sessions ×
> 5 exercises × 4 sets when `@concurrent` is removed from one method, staying inside the
> 100 ms budget with it. The build was green either way. This is the third such
> measurement (600 ms History, 307 ms progress charts, 319 ms here) and the first on a
> *second* model actor.
>
> **Three judgements where the finding's prescription was not followed** (each argued in
> code comments or `docs/swift6-concurrency.md`):
> 1. **`nextWorkoutFacts` did not stay on `@MainActor`.** The finding calls it "small
>    bounded"; it is not. It fetches every completed session and faults `session.routine`
>    per session per active routine. It moved off-main with the other two — just with a
>    lean fetch that prefetches `\.routine` and never touches the set graph.
> 2. **A second `@ModelActor`, not the History one.** Reusing it would have put English
>    fact lines in the History read boundary and serialised mid-stream tool calls behind
>    ~300 ms snapshot builds.
> 3. **The tools were not annotated.** Apple declares the `Tool.call` *requirement*
>    `@concurrent`; guaranteeing off-main once at the boundary that owns the cost makes
>    the tools' own isolation irrelevant, and is more robust than annotating every caller.
>
> Two corrections fell out of the research, both applied: the shared prefetch-correct
> fetch is now `Data/Persistence/CompletedSessionFetch` (both actors call it, so the
> undocumented identity-map bet is written down once), and a **retracted claim still
> asserted in `SwiftDataHistorySnapshotStore`'s comment** — that `@concurrent` on a
> protocol requirement was measured not to work — was removed; it had already been
> retracted in `docs/swift6-concurrency.md` §1 and it misled this round's research.

`Domain/Interfaces/AICoach/ChatFactProviding.swift:16-19` is `@MainActor` and its doc
comment states the intent explicitly — a tool whose `call(arguments:)` runs off the
main actor holds it and `await`s to hop *back*. `Data/AICoach/Chat/ChatFactService.swift:100-159`
then does an unbounded fetch (no prefetch) and a nested scan over every session ×
exercise × set with no early exit. Fires live, mid-conversation, possibly several
times per turn, while the chat is streaming — the worst possible moment.
*Fix:* keep the small bounded `nextWorkoutFacts()` on `@MainActor`; move the PR/history
facts to an `async` actor-backed boundary. The caller is *already* async and off-main,
so this is a **net simplification** — deleting a hop, not adding one.

### P1.4 Real wire-schema drift between the duplicated `WatchModels.swift`
> **DONE 2026-08-13** — the watch copy is now `var loadBehaviorRaw: String? = nil`,
> byte-identical to iOS. Full write-up in **`docs/watch-sync.md`** ("Wire schema
> evolution rule"). Three things the finding did not have, all now established:
>
> 1. **The mechanism is verified, not assumed.** On this project's toolchain
>    (Swift 6.3.2): a non-optional property with a default value throws
>    `DecodingError.keyNotFound` on an absent key — the default is *never* a
>    decode-time fallback — while `Optional` properties are synthesized as
>    `decodeIfPresent`. Independently confirmed against the compiler's
>    `DerivedConformanceCodable.cpp`. Widening is wire-neutral: a non-nil optional
>    is still encoded, so iOS keeps receiving the key.
> 2. **The finding understated the blast radius, and the fix direction depends on
>    it.** "Benign today because the watch is always the sender" is incomplete —
>    the watch also *decodes* `CompletedWatchWorkout` from its own App-Group state
>    file, where `WatchSyncStateFile` decodes as a whole: one undecodable entry
>    quarantines the file as `.corrupt` and starts the outgoing queue empty
>    (`WatchSyncStateStore.swift:117-135`), and an undecodable legacy blob strands
>    its workouts permanently. So the watch had to widen; tightening iOS instead
>    would have thrown away the receiver's tolerance for pre-2026-07-12 payloads.
>    Apple does not document whether the `transferUserInfo` queue survives an app
>    update, so an old-schema payload reaching a new build cannot be ruled out.
> 3. **It is now drift-detected.** `WatchModelsWireCompatibilityTests` in *both*
>    test targets decodes a v1-only payload and asserts every later addition
>    arrives as `nil`, so the next non-optional wire field fails on the side that
>    added it. Verified to bite by reintroducing the drift: `keyNotFound: Key
>    'loadBehaviorRaw' … Path: exercises[0]`. This closes the last gap a wire
>    field could slip through — the twin *behavioural* suites from P1.1 cannot see
>    a schema drift, because a field non-optional in one copy compiles on both.
>
> Origin, for the record: `7812427` (2026-07-12) added the field to both copies in
> one commit, optional on iOS and non-optional on the watch.

The one genuine undocumented divergence in ~4,600 duplicated lines, found
independently by two reviews and verified here:
- `GymStreak/Data/Sync/WatchModels.swift:260` — `var loadBehaviorRaw: String? = nil`
- `GymStreakWatch Watch App/Models/WatchModels.swift:354` — `var loadBehaviorRaw: String = "resistance"`

Same `Codable` struct (`CompletedWatchExercise`), different optionality; the other
three `loadBehaviorRaw` sites in each file *do* match, and every other divergence
between the pairs carries an explanatory comment. **Failure mode:** benign today only
because the watch is always the sender — if iOS ever sends the field absent, the
watch's non-optional declaration **fails to decode**. One-line fix; make it a
deliberate standalone change, not folded into a sweep.

### P1.5 Extract Live Activity + routine-template-sync from `WorkoutViewModel`
> **DONE 2026-08-13** — `WorkoutViewModel` went 2,195 → 1,887 lines and no longer
> imports ActivityKit. Live Activity now sits behind
> `Domain/Interfaces/RestTimerLiveActivityPresenting` +
> `Data/LiveActivity/ActivityKitRestTimerPresenter`; the template writeback is
> `Domain/Services/RoutineTemplateSyncService`. Full write-ups in
> **`docs/rest-timer-notifications.md`** (Live Activity section + ActivityKit
> findings) and `docs/architecture.md`'s layer table. Green: app build with zero
> warnings, `test_unit_ios` and `test_unit_watch` both passing.
>
> **Four things the finding did not have:**
> 1. **The presenter is identity-keyed, not instance-scoped.** The finding said
>    "mirror `RestTimerReminderScheduling`", and that pattern's *point* turned out
>    to be identity: `AppDependencies` owns one presenter shared by both
>    `WorkoutViewModel`s, so `endActivity(id:)` mirrors `cancelReminder(id:)` and
>    cannot end the other instance's countdown. `startActivity(id:content:)` is
>    idempotent per id, which removed the ViewModel's `if currentRestActivity == nil`
>    check from the restore path.
> 2. **A latent bug the extraction exposed, fixed inside the new gateway.**
>    Relaunching mid-rest produced **two** Live Activities: the previous process's
>    countdown was still on the Lock Screen and `restoreTimerState()` requested a
>    second one. The presenter now sweeps leftovers before presenting a restored
>    countdown — gated on "this process has never presented", so the deliberate
>    3-second "Rest Complete" state between two timers in one session is not cut
>    short. This is the one **behavior change** in P1.5; it has a TestFlight note.
> 3. **The old error handling was dead code, and our own concurrency doc was
>    wrong.** Read out of the iOS 26.5 SDK's `ActivityKit.swiftinterface`:
>    `ActivityAuthorizationError` is a typed 12-case enum, and the replaced code
>    string-matched `error.localizedDescription` against `"unsupportedTarget"`,
>    `"activitiesDisabled"` and `"activityLimitExceeded"` — two of which are not
>    cases at all, and `localizedDescription` never yields a case name, so no
>    branch could ever be taken. Separately, `Activity.end(_:dismissalPolicy:)`
>    carries **no** attribute; it is *not* `@concurrent` as
>    `docs/swift6-concurrency.md` §8 claimed. That section is corrected, and the
>    real reason for `@preconcurrency import` (non-`Sendable` `Activity` crossing
>    at the `await`) is now *verified by removing it and reading the error*, not
>    asserted.
> 4. **`RestTimerAttributes` moved out of `Domain/`.** It imports ActivityKit and
>    was the only thing keeping `Domain/` coupled to it; it now lives in
>    `Data/LiveActivity/` next to its only app-target consumer. Both it and the
>    widget's copy gained the "keep these declarations identical" header they
>    lacked — a drift there breaks the Live Activity at runtime with no compile
>    error, the same failure shape as P1.4.
>
> **Architecture review: PASS WITH WARNINGS**, no CRITICAL findings. Its one
> warning — the two user-facing Live Activity strings ("Rest Complete! 💪" and the
> "Workout" title fallback) were hardcoded English, carried over verbatim from the
> old code — was fixed rather than acknowledged: both now go through
> `live_activity.rest_timer.*` keys in en/de, localized in the app process before
> crossing into `ContentState`.
>
> **On the finding's "unusually well covered already" for template sync:** true for
> the `reconcileExerciseMembership: true` half only. `saveEditedWorkout` — the
> `false` half, including the entire legacy-fallback matching branch — had **zero**
> tests; nothing in the repo called it. `RoutineTemplateSyncServiceTests` now covers
> that path directly (writeback, no membership changes, legacy id/name fallback,
> mixed history disabling the fallback, set-count reconciliation, and that the
> service does not save), and `EditWorkoutSessionCommitTests` covers the
> ViewModel's own commit half (draft reconciliation, planned-vs-actual writeback,
> `didUpdateTemplate`, the watch notification, `historyVersion`).
>
> **A latent bug the extraction exposed, now fixed and pinned:** the template
> writeback owned the only `save()` on the `updateTemplate == true` branch, and it
> returns early for a session with no routine — so ticking "update routine" on a
> routine-less workout silently **discarded the user's set edits**. The save is now
> unconditional. `editsToARoutinelessWorkoutSurviveEvenWhenTemplateUpdateIsRequested`
> was verified to fail against the old control flow before being kept.
>
> **Unrelated defect found while validating the localization fix, also fixed:**
> `Localizable.strings` defined `history.empty.title` / `.description` **twice** in
> both en and de with different wording. In a `.strings` file the last definition
> wins (verified with `plutil -convert json`), so the earlier pair was dead; it was
> deleted and the resolved values are unchanged in both languages.
>
> **Deliberately not done → now tracked as P2.11:** the near-verbatim SwiftData mechanics shared with
> `WatchTemplateTransactionService+Structural` (`appendRoutineExercise` ↔
> `appendAddition`, the removal loop, `normalizeOrder`). The *value-writeback*
> bodies must stay separate — the watch writes only sets that deviate from plan
> while iOS writes every completed set, and only iOS reconciles set count — so
> merging them would silently change one platform's behavior. The extractable part
> is mechanics-only and is P2-sized at best.

The two cleanest, safest extractions from the 2195-line file, because everything else
is *already* behind injected gateways:
- **Live Activity** (`WorkoutViewModel.swift:368-464`) is the only system integration
  not behind a protocol. Mirror the existing
  `RestTimerReminderScheduling` → `UserNotificationRestTimerScheduler` pattern. ~100
  lines. **No test coverage today — write contract tests before moving.**
- **Routine-template sync** (`:1789-2103`, ~240–320 lines) is pure business logic on
  `@Model` arrays with no `Task`/`Timer`/observer/ActivityKit in the block → belongs
  in `Domain/Services/`, precedent: `SupersetOrderingService`. Unusually well covered
  already (3 dedicated tests + 9 adjacent overload tests), so extract-method rather
  than rewrite.

### P1.6 `ExerciseProgressService.compareWithPrevious` — unbounded main-actor fetch *per exercise*
**The only open P1. Added 2026-08-14** — it is not a new discovery: P1.2 surfaced it while
fixing the charts and explicitly called it "worth a P1 of its own", but recorded it as prose
inside a block marked DONE, where nothing scheduling work would ever look. Promoted here so
§7 stops reading as "all P1 complete".

- `Data/Progress/ExerciseProgressService.swift:32` `previousPerformance(…)` builds a
  `FetchDescriptor<WorkoutSession>` with **no** `relationshipKeyPathsForPrefetching`, and
  `compareWithPrevious(workout:)` (`:116`) calls it **once per exercise** in the session.
- Callers: `SaveWorkoutView`, `WorkoutDetailView` (both on appear) and
  `WorkoutAnalysisAggregator`. **Not gated behind any opt-in** for the first two — this
  runs every time a workout is finished or a past workout is opened.
- Same shape that measured ~600 ms in History, 307 ms in the progress charts and 319 ms in
  the chat facts.

**Why it is not a port of the existing pattern** — read `docs/progress-charts.md`
("Still on the main actor, deliberately out of scope") before starting. Unlike the three
boundaries already moved, this one takes a **caller-supplied main-context `WorkoutSession`**,
so it cannot cross an actor boundary unchanged: an `@ModelActor` cannot accept a
main-context `@Model` argument. It needs a different call shape — pass the session's `id`
and re-fetch inside the actor, or return a value-type comparison keyed by
`WorkoutExercise.id` — which is design work, not a mechanical port. That is why P1.2 left
it rather than folding it in.

*Per §6, and per what P1.2/P1.3 actually did:* add the tripwire case to the existing
`SwiftDataHistorySnapshotStoreTests` suite **before** the fix, and verify it fails without
the `@concurrent` annotation. Do not start a fresh test file.

---

## 4. P2 — worth doing, not urgent

| # | Finding | Evidence |
|---|---|---|
| P2.1 | Four AI-coach aggregators run synchronously on the main actor with no prefetching; two hand-roll PR detection in near-verbatim duplicate instead of using `PersonalRecordService.computePRs` | `PeriodRecapAggregator`, `ExerciseDeepDiveAggregator`, `WorkoutAnalysisAggregator`, `PostWorkoutRecapAggregator`. `ExerciseDeepDiveAggregator.lastCompletedSetTimestamp` fires from a `.task` on every chart appearance, not a user action. Gated behind AI opt-in — the only reason this is P2. |
| P2.2 | `RoutinesViewModel` registers 4 notification observers with **no `deinit`**; `ExercisesViewModel` 1, also none | Inconsistent with the `isolated deinit` convention introduced in the Swift 6 migration. Harmless while both are app-lifetime with `[weak self]`; a hazard the day either becomes per-navigation. ~15 min each. |
| P2.3 | `CloudSyncObserver.syncVersion` is written on every remote-change event and **read by nobody** (0 external references) | Its `ObservableObject`/`@Published`/singleton machinery exists only to force eager `init()`. Sibling `CloudKitSyncStatusMonitor` already does the same job correctly as an injected non-singleton. |
| P2.4 | Zero test coverage for all five `@Observable` AI-coach ViewModels — including `PeriodRecapViewModel`, which `architecture.md` §8 names as *the canonical reference* for the modern pattern | Not an `@Observable` testability problem; coverage simply hasn't caught up with the pattern shift. |
| P2.5 | `AppDependencies.init` has grown launch *orchestration*, not just wiring (`:141-156`) | Extract an `AppLaunchCoordinator`. **The ordering at `:151-156` is load-bearing for watch-sync correctness** — careful diff review, not a mechanical move. |
| P2.6 | `WorkoutViewModelTests` silently resolves `AICoachCache.shared`, doing real `FileManager` I/O in the test host | Pass an explicit no-op double. Test-only change. **Widened 2026-08-14 (P1.5):** it is now three suites, not one — `EditWorkoutSessionCommitTests` and `RoutineTemplateSyncServiceTests` construct `WorkoutViewModel` too. It is also the reason `saveEditedWorkout`'s two `AICoachCache` invalidations are the one part of that method left untested; the double this item asks for is what unblocks them. |
| P2.7 | Three mechanical rendering nits in `ExerciseProgressChartView`: ~~per-row `DateFormatter`/`RelativeDateTimeFormatter` construction~~ (**fixed 2026-08-13** with P1.2 — hoisted to `static let` on `SessionCardView`, which that change re-typed anyway), `Dictionary(grouping:)` read by `body` in `ExerciseSwitcherMenu`, `.map/.min/.max` read by `body` in `ProgressChartContent` | Literal named-forbidden patterns from `docs/history-performance.md`, but bounded to ≤8 rows — low severity, cheap to fix while splitting the file. The remaining `Dictionary(grouping:)` is over the user-scaled `availableExercises`, so it is the least bounded of the three. |
| P2.8 | `WorkoutDetailView:188,194,200` re-walks the workout-exercise graph three times instead of reading `Aggregates` once | The `Aggregates` struct exists specifically to avoid this. ~5 lines. |
| P2.9 | Watch: extract the Combine metric-projection pipeline (3 of 5 `.sink`s are display glue) then the rest-timer/Crown state machine | **Both gated on P1.1.** There is a live `// FIXME` next to the metrics code — pin behaviour with tests first. The Crown path deliberately avoids re-rendering per detent; a naive extraction would reintroduce that cost. |
| P2.10 | Process: stop growing `WorkoutViewModel` in place | `git log` shows +118/+66/+8 lines added in the legacy style (`a22d306`, `70d1193`, `f5f0d8f`) rather than as new `@Observable` collaborators. The "legacy stays `ObservableObject`" rule is being read too literally. **2026-08-14:** P1.5 took it 2,195 → 1,887 by extraction, so the trend is reversed but the file is still far over the 200–300 guideline. The next candidate is the ~230-line "Progressive overload from history" block, which is already pure logic over `@Model` arrays. |
| P2.11 | Near-verbatim SwiftData mechanics duplicated between `RoutineTemplateSyncService` and `WatchTemplateTransactionService+Structural` | **Added 2026-08-14 (P1.5).** Three overlapping sites: `appendRoutineExercise` ↔ `appendAddition` (the same 5-step insert-slot → link-exercise → link-routine → contains-guard-append → insert-child-sets dance), the slot-removal loop, and `normalizeOrder`. **Only the mechanics are shareable.** The value-writeback bodies must stay separate and merging them would silently change one platform's behavior: the watch writes only sets whose actual values deviate from planned (`WatchTemplateTransactionService+Validation`, `WatchRoutineTemplateFold`), iOS writes every completed set; and only iOS reconciles set *count* (the watch expresses cardinality through the structural add/remove channel and rejects an unknown set id outright). Low value, real risk if scoped wrong. |

---

## 5. P3 — explicit holds (do not schedule)

These are judgements that the current design is **right**, not omissions:

- **`WatchWorkoutViewModel` observation (36 `@Published`, a live timer, 15 observing
  views).** The worst observe-narrowly violation in the codebase — and the last five
  commits are all in that exact file. Restructuring now would be reckless. Revisit as
  a dedicated, Instruments-measured `@Observable` migration once the rest-timer work
  settles.
- **`WatchSyncStateStore.swift` (942/942, byte-identical).** The single atomic
  App-Group owner of outgoing sync state, routine authority and optimistic anchors,
  with documented ordering invariants ("durable enqueue BEFORE HealthKit
  finalization… the reverse had a loss window that stranded workouts"). **The textbook
  case where the refactor is more dangerous than the debt.**
- **`HistoryView` binding the full `WorkoutViewModel`.** Real but dormant, protected
  by `AppDependencies` creating two separate instances. Prefer a narrow projection
  protocol over a 2195-line migration.
- **`ActiveWorkoutView` (980) and `RoutineDetailView` (761).** Read in full against
  every rendering rule: `ForEach` correctly inside `LazyVStack`, rows take precomputed
  value structs not `@Model`s, no `ModelContext`, and their one aggregation each
  carries a justifying comment. Size here is breadth of UI states, not entanglement.
  **Do not split for size alone.**
- **`@Model` computed properties.** The one expensive aggregate was already fixed
  *within* the pattern (single-traversal `Aggregates`). Recommend naming that as the
  required convention for future non-trivial computed properties.
- **The `@Observable` migration deferral** — still correct. The one place it matters
  was measured and found *not* to be the History hang's cause. No shipping bug drives
  it.
- **The outer/inner view-split DI pattern.** Not boilerplate awaiting a better
  mechanism: `@Environment`/`EnvironmentKey` would **not** help, since environment
  values are equally unreadable inside a plain `init()`. Used only where needed.
- **`HapticManager.shared` (83 call sites).** Verified 100 % in Views, 0 in
  ViewModels — the documented tolerance is being honoured exactly.
- **`CoachChatService`, `CoachScreenContext`, watch `AppStateProvider`,
  `WatchWorkoutRecoveryCoordinator`, both `WatchConnectivityManager`s.** All genuine
  process-wide identity: `AppIntent.perform()` and `WKApplicationDelegate` callbacks
  execute outside the SwiftUI environment, and WCSession delegate identity must be the
  launch-time instance. **Hold.**
- **No-DTO and no-UseCase decisions.** Hold, except one narrow revisit: the
  routine-template-sync block has grown past "ViewModel → repository call" into real
  multi-step orchestration → P1.5.

---

## 6. Measured vs. inferred — read this before acting

Everything in §3–§4 was verified by **reading code**: call chains, fetch descriptors,
`git log`, and direct diffs of the duplicated pairs. **None of the P1/P2 magnitude
claims were measured at scale.**

They are well-grounded inference — the same shape (unbounded fetch + no prefetch +
full graph traversal on the main actor) that *did* measure ~600 ms in History. But
History needed a 240-session heartbeat test to prove, and the honest sequence here is
therefore **tripwire test first, then fix**.

Recommendation: generalise `HistoryMainThreadStallProbe` /
`largeSnapshotBuildKeepsMainActorResponsive` into one reusable harness and add a case
per boundary, rather than writing four separate one-off tests — a single growing suite
is far more likely to actually be run.

One structural limit worth stating plainly: the `@concurrent` off-main guarantee
**cannot be enforced by the type system.** SE-0461 does not propagate `@concurrent`
through protocol requirements to witnesses, so the guarantee rests on a code comment,
one regression test, and reviewer discipline. That is inherent to the language today,
not sloppiness — which is exactly why any new boundary added for P1.2/P1.3 must join
the same shared tripwire suite.

---

## 7. Sequencing

1. ~~**P1.1** (watch test target)~~ — **done 2026-08-13**, see `docs/watch-unit-tests.md`.
2. ~~**P1.4** (wire drift)~~ — **done 2026-08-13**, deliberately and on its own,
   see `docs/watch-sync.md` ("Wire schema evolution rule"). It grew one twin test
   suite per target beyond the one-line fix, because nothing else can detect a
   re-drift of a *schema* (as opposed to behavioural) field.
3. ~~**P1.2**~~ and ~~**P1.3**~~ — both **done 2026-08-13**, see `docs/progress-charts.md`
   and `docs/ai-coach-chat-feasibility.md`. The reusable tripwire harness §6 asked for is
   now real: `SwiftDataHistorySnapshotStoreTests` holds a case per boundary across two
   model actors, and its header says so. Add to it; do not start a fresh test file.
4. ~~**P1.5**~~ — **done 2026-08-13**, see `docs/rest-timer-notifications.md`. The
   "template-sync leans on existing tests" half of that plan was only half right:
   the historical-edit path had no coverage at all and grew its own suite.
5. **P1.6** (`compareWithPrevious`) — **open, and the next thing to do.** Added to §3 on
   2026-08-14; it was surfaced by P1.2 but only recorded inside that item's DONE block,
   so this list previously read as "every P1 is finished". It is not a port of the three
   boundaries already moved — the caller-supplied main-context `WorkoutSession` means the
   call shape has to change first. Tripwire case into
   `SwiftDataHistorySnapshotStoreTests` before the fix.
6. **P2** — independent cleanup, no particular order; P2.9 gated on P1.1. P2.11 was added
   by P1.5 and is the lowest-value item in the table — read its risk note before starting.
7. **P3** — do not schedule.

### Anything still only in a DONE block?

Audited 2026-08-14, because that is exactly how P1.6 went missing. Every "not addressed" /
"deliberately not done" note inside a completed item now has a numbered home:
`compareWithPrevious` → **P1.6**; the shared SwiftData mechanics → **P2.11**; the
`saveEditedWorkout` AI-cache invalidations → folded into **P2.6**, which already owns the
missing `AICoachCaching` double. The `Activity.activities`-at-launch uncertainty stays in
`docs/rest-timer-notifications.md` on purpose — it is a documented unknown with a known
remedy, not scheduled work. **When a future item closes, put its leftovers here, not only
in its own write-up.**

The mandatory `architecture-reviewer` gate did not apply to this audit (no code
changed). It applies to every item that lands from it — P1.2, P1.3, P1.4 and P1.5
each went through it, and P1.6 must too.
