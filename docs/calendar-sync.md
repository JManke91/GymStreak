# Calendar Sync — planned workouts in Apple Calendar

**Status:** slices 1–3 of 4 shipped and **device-verified** — opt-in and calendar
ownership (§1–§10), cadence plans mirrored as all-day events (§11), and the mirror
following the plan as it moves (§12: drift, window top-up, and both ways the user
can take the feature away; walked on device 2026-09-03, §12i). Weekday plans are
not modelled as a recurrence yet (ticket 04) — they contribute no events at all
until then.

**Target:** iOS only. **The watch is untouched** — it holds no schedule or plan
data at all (`docs/workout-planning.md` § "Watch surface"), so there is nothing
to mirror there and no `WatchRoutine` DTO change.

**Monetization: Free.** §3 Rule 4 (it exports the user's own data) plus the §4.1
row "Apple Health sync + iCloud sync — platform integrations tied to the privacy
promise". No cap, no `PaywallPlacement`, no nudge; the free residue is the entire
capability. §7: the audience is existing planners, all founder-granted, so a gate
would convert close to nobody.

---

## 1. What slice 1 delivers

A single toggle in Settings — "Sync to Apple Calendar" — that owns the whole
feature:

- Enabling it asks for Calendar access and, on grant, creates a **dedicated
  calendar the app owns**, titled "Gym Streak" and tinted with
  `DesignSystem.Colors.tint`. It appears in Calendar.app alongside the user's own
  calendars.
- Disabling it removes that calendar again, taking every event the app ever wrote
  with it.
- Denied, restricted or "Add Only" access leaves the toggle **off** and shows a
  tappable row that opens this app's page in Settings.

The permission handshake and the container are exactly the part that has to be
proven on a real device before any event logic is worth writing, which is why
they ship alone.

### Decisions carried from planning

- **One global toggle, not per-routine.** It mirrors every active plan.
  Per-routine opt-in would need a new persisted flag on `RoutineSchedule` —
  additive and CloudKit-safe, but real schema surface — plus UI in the planning
  sheet. Ticket 02's reconciler is to be built so a per-routine filter could be
  added later without reworking it.
- **The toggle lives in Settings, not the planning sheet**, because it carries a
  system permission and applies to every routine at once — the same reasoning
  that puts Apple Health there.
- **No `EventKitUI`.** `EKEventEditViewController` and `EKCalendarChooser` have
  no role here: the app owns its calendar outright, so there is nothing for the
  user to pick.

---

## 2. Full Calendar access is required — do not re-litigate this

`requestWriteOnlyAccessToEvents()` looks like the tasteful, minimal ask and it is
a **non-starter**. Apple's own words ([Accessing the Event
Store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)):

> When an app has write-only calendar access, requests for calendar lists return
> a single virtual calendar, and queries for existing events return no results.
> New events created by the app are saved to a calendar selected by the user.

Two consequences, both fatal:

1. **A write-only app can never find, update or delete the events it wrote** —
   not via `event(withIdentifier:)`, not via `events(matching:)`, not even by
   having persisted the identifier itself. Ticket 03 exists entirely to revise
   previously written events. Corroborated by [forum thread
   731448](https://developer.apple.com/forums/thread/731448).
2. **A write-only app cannot own a calendar** — it cannot enumerate a real
   `EKSource` to assign one to, because the calendar list collapses to a single
   virtual entry.

So: `requestFullAccessToEvents()`, and the usage description earns it by saying
that the app needs to *revise* what it wrote, not merely add to it.

This is also why `CalendarAccessStatus` folds EventKit's `.writeOnly` into
`.denied`. `.writeOnly` **is reachable** — iOS 17+ offers "Add Only" in
Settings → Privacy & Security → Calendars — and it cannot carry the feature, so
it gets the same "grant Full Access" remedy as a flat refusal. This is why
`enable()` re-checks `accessStatus == .fullAccess` after
`requestFullAccessToEvents()` returns `true`: the `Bool` comes back `true` for a
pre-existing write-only grant.

Sources: [Accessing Calendar using EventKit and
EventKitUI](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui).

---

## 3. The Info.plist key, and a known localization gap

`NSCalendarsFullAccessUsageDescription`. The write-only key and the legacy
`NSCalendarsUsageDescription` are both unnecessary at this project's iOS 26.1+
deployment target.

It is declared as a **build setting**, following the HealthKit precedent:
`project.pbxproj` carries `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription`
on the iOS app target's Debug *and* Release configurations, next to
`INFOPLIST_KEY_NSHealthShareUsageDescription`. `GymStreak/Info.plist` holds only
`CFBundleURLTypes`, `UIBackgroundModes` and `WKAppBundleIdentifier`, and nothing
was added to it. The watch target's configurations were not touched.

### The prompt is localized (fixed after device testing)

The first device run showed the **English** text on a German phone: an
`INFOPLIST_KEY_*` build setting is a single literal, not a localized value, so
the prompt fell back to it. `GymStreak/Resources/{en,de}.lproj/InfoPlist.strings`
now carry `NSCalendarsFullAccessUsageDescription`, and the system picks the right
one at prompt time.

How the two halves divide: the **key** must exist in the built `Info.plist` —
that is still the `INFOPLIST_KEY_…` build setting, and removing it would break
the prompt entirely — while `InfoPlist.strings` supplies only the **text**. Both
are required. `knownRegions` already listed `en`, `Base` and `de`, and the
target's synchronized root group picks the files up with no `project.pbxproj`
entry, exactly as `Localizable.strings` is picked up.

This is not a workaround — it is what Apple's own engineers prescribe. DTS, on
exactly this combination ([forum
726709](https://developer.apple.com/forums/thread/726709)): *"You should set a
description in the build settings, as you would for the Info.plist file
previously, and then continue to localize it by adding the `InfoPlist.strings`
file."* The base `Info.plist` value is **required** as the fallback for
unsupported languages, so the build setting must stay.

`Base.lproj` is **not** needed. Per
[QA1828](https://developer.apple.com/library/archive/qa/qa1828/_index.html), iOS
walks the user's preferred-language list, matches `de-DE` → `de.lproj`, and only
consults `CFBundleDevelopmentRegion` when nothing matches — so `de` wins before
the development region is ever read. `Base` sitting in `knownRegions` with no
folder on disk is inert.

### Proof it works — and the Xcode trap that hid it for a whole afternoon

Verified at three levels, because the first two were not enough:

1. **Bundle layout** — `find GymStreak.app -name InfoPlist.strings` returns
   exactly two hits, both at the bundle root, with no nested `Resources/`
   directory (the synchronized root group flattens correctly).
2. **In-process resolution** — on a German simulator,
   `Bundle.main.preferredLocalizations` is `["de"]` and
   `localizedInfoDictionary["NSCalendarsFullAccessUsageDescription"]` returns the
   German string.
3. **The system alert itself** — which is what actually matters, because *iOS*
   presents the dialog and the resolution site is undocumented. A UI test reading
   `springboard.alerts.firstMatch.staticTexts` got the alert's own label back:
   "Gym Streak trägt deine geplanten Workouts in einen Kalender ein…". Confirmed
   German on iOS 26.1 (German only) and 26.5 (`de-DE` + `en-DE`).

> ### The trap: Xcode silently omitted the new file from the bundle
>
> After the fix, the prompt was **still English** — on the device *and* in
> Xcode's own simulator builds. The cause was not the configuration, the OS
> version, the device language list, or a stale install. It was the build:
>
> **Xcode's incremental build did not copy the newly added
> `InfoPlist.strings` into the already-existing `.lproj` folders of the built
> product.** In Xcode's DerivedData, `GymStreak.app/de.lproj/` contained only
> `Localizable.strings`, and the directory's own mtime was a week stale — while a
> `xcodebuild` run against a *fresh* DerivedData path, from the same source tree
> and the same `project.pbxproj`, produced a bundle containing both files.
>
> So iOS was behaving correctly the entire time: the installed app genuinely had
> no German usage description, and the system fell back to the `Info.plist`
> literal, which is English.
>
> **Fix: Product → Clean Build Folder (⇧⌘K), then rebuild.** If it still does not
> appear, close and reopen the project — a `PBXFileSystemSynchronizedRootGroup`
> can hold a stale snapshot of files created outside Xcode.
>
> **Diagnose it in one command** rather than by inspecting the prompt, since a
> missing localization and a working one are indistinguishable when the fallback
> text is the English original:
>
> ```
> find <DerivedData>/Build/Products/Debug-iphoneos/GymStreak.app -name InfoPlist.strings
> ```
>
> Two hits (`en.lproj`, `de.lproj`) means the bundle is correct. No hits means the
> build is the problem and installing it proves nothing.
>
> **The general lesson:** when a resource added to a synchronized group does not
> take effect, check the built product before doubting the configuration. Three
> wrong hypotheses were burned here — TCC caching the purpose string, English
> remaining in the preferred-language list, and an iOS 26.6 regression — all of
> which survived because nobody had looked inside the `.app` Xcode actually
> produced.

Two OS-side precedents worth knowing before assuming a future localization
failure is your own bug: `NSAlarmKitUsageDescription` was simply not localizable
when iOS 26.0 shipped and was fixed in 26.1 beta 2
([802749](https://developer.apple.com/forums/thread/802749)), and
`NSUserNotificationsUsageDescription` localizes for some locales but not others
([787095](https://developer.apple.com/forums/thread/787095)). Nothing of the kind
is reported for the calendar keys — and in this instance the OS was innocent.

> **Still open, deliberately.** The **HealthKit** prompts remain English-only for
> German users — the same defect, pre-dating this work. Now that
> `InfoPlist.strings` exists in both lproj folders it is a two-line fix per
> language, but it changes user-visible copy in another feature and was not part
> of this ticket, so it is left for a change that can verify it on its own.

---

## 4. Which calendar, on which source

`EventKitWorkoutCalendarSync.ensureAppCalendarExists()` does:
`EKCalendar(for: .event, eventStore:)` → set `title`, `cgColor`, `source` →
`try eventStore.saveCalendar(calendar, commit: true)`, then persists
`calendar.calendarIdentifier` under `calendar_sync.calendar_identifier`.
Rehydration is `eventStore.calendar(withIdentifier:)`.

**Source selection decides whether the calendar syncs across the user's
devices**, and Apple prescribes nothing, so the rule is stated explicitly in
`preferredSource()`:

1. `eventStore.defaultCalendarForNewEvents?.source` — whatever the user already
   trusts their own events to.
2. Otherwise the source whose `sourceType == .calDAV` and whose title contains
   "iCloud". **This is what makes the calendar appear on the user's iPad and
   Mac.**
3. Otherwise a `.local` source — device-only. Correct behaviour when no iCloud
   account is signed in; the calendar simply does not travel.

Nothing available at all throws `WorkoutCalendarSyncError.noWritableSource`,
which the Settings section reports as its own failure rather than as a permission
problem.

### This is CalDAV, **not** the app's CloudKit container

The calendar syncs through the user's CalDAV account, entirely outside
`iCloud.com.jmanke.gymstreak`. Nothing in `docs/cloudkit-schema-automation.md` is
implicated and **no schema deploy is involved** — do not go looking for one.

### 4a. App deletion, and the duplicate guard

**The calendar outlives the app, and nothing can change that.** iOS runs no code
at uninstall — Apple DTS: *"Apple has no recommendations for determining when
users uninstall apps… no services, API, or code samples available"*
([116445](https://developer.apple.com/forums/thread/116445)).
`applicationWillTerminate(_:)` is not a substitute: it fires only if the app is
running when the user swipes it away. And the calendar is not in the app's
container — it is a server-side record in the user's CalDAV account, so the
container wipe cannot reach it. This is the same contract as HealthKit workouts,
Contacts and Photos: deleting an app removes its *access*, not the user's data.
So a user who deletes the app without switching sync off keeps the calendar, and
the **section footer says so**, naming the Calendar.app path that removes it.

**What deletion does break is the app's handle.** `calendarIdentifier` lives in
`UserDefaults`, which iOS wipes — so a reinstall found nothing to reuse and
created a second "Gym Streak" calendar, then a third. `ensureAppCalendarExists()`
therefore runs an **adoption pass before creating**: it looks for a calendar on
the source it would have used, with the exact localized title, that is writable,
and adopts it. The rule itself is `WorkoutCalendarAdoption` — pure, EventKit-free
and unit-tested, because the gateway around it owns an `EKEventStore` and cannot
be.

**Why not carry the identifier across installs in iCloud KVS?** It was tried on
paper and it is worse than the bug. `calendarIdentifier` is **device-local**: the
same iCloud calendar has a *different* identifier on the user's iPhone, iPad and
Mac, and Apple notes *"a full sync with the calendar may invalidate this
identifier"*
([docs](https://developer.apple.com/documentation/eventkit/ekcalendar/calendaridentifier)).
Syncing it through `NSUbiquitousKeyValueStore` would resolve to `nil` on every
other device and manufacture **one duplicate per device**. There is no stable
external identifier for a calendar either — `calendarItemExternalIdentifier`
exists only on `EKCalendarItem`, never on `EKCalendar`. Matching on facts that
*are* stable is the only option available.

**Title and writability are required; the source is only a preference.** A user
may legitimately own a calendar called "Gym Streak", and adopting it would mean
deleting it when they later switch sync off — so the title must match exactly and
the calendar must be one the app could actually manage.

The source deliberately is **not** a requirement, and this was corrected after
review. `preferredSource()` resolves through `defaultCalendarForNewEvents`, which
the user can change at any time in Settings → Calendar → Default Calendar. Had
the source been required, moving it between the install that created the calendar
and the reinstall that tries to adopt it would miss the match and create a second
"Gym Streak" calendar — the exact bug the pass exists to stop. A match on the
expected source is therefore *preferred*, and a match on another account is still
accepted.

On more than one match the rule adopts the lowest identifier rather than
prompting: the remaining candidates are indistinguishable by any fact EventKit
exposes, so there is no useful question to ask, and creating yet another calendar
is what this prevents. The ownership risk is not increased by the count — adopting
a same-named user calendar is equally possible when it is the only match.

`EKCalendar.source` is `null_unspecified` in the SDK header ("nil for new
calendars until you set it") and so imports as `EKSource!`. The gateway projects
it with `?? ""` rather than force-unwrapping: this is a system boundary inside
`enable()`, and a nil there would crash the toggle instead of failing it.

**Known residuals, accepted:**

- Calendars orphaned by the *earlier* build are not swept up. Adoption takes one
  and `disable()` removes only that one, so a user who already accumulated
  duplicates keeps them and must delete the extras in Calendar.app. The guard is
  forward-looking by design — a sweep would mean deleting calendars the app can
  no longer prove it created.
- `calendar_sync.calendar.title` is currently "Gym Streak" in **both** `en` and
  `de`, so a language change between installs is harmless today. **That stops
  being true the moment anyone localizes that value differently** — the
  exact-title match would silently miss and create a duplicate. If the title is
  ever translated, this rule must match against every localization of it.

**Considered and not done:** a *sentinel event* written into the calendar at
creation (an all-day event in the past carrying a `gymstreak://` URL) would prove
ownership beyond doubt, survive reinstall and sync across devices. It is the
right escalation if title collisions ever turn out to matter; it was left out
because it costs a visible junk event in the user's calendar for a risk that has
not materialised. Its absence would have to be treated as inconclusive rather
than disqualifying, so it does not remove the confirmation question — it only
sharpens it.

**Also considered: not owning a calendar at all.** Writing planned workouts as
events into a calendar the user picks (`EKCalendarChooser`) is Apple's preferred
direction post-iOS-17 and leaves nothing structural to clean up. It was not taken
because the app owning its calendar is a decided part of this feature — but if
orphaned calendars ever become a real support burden, this is the alternative,
and it would reshape tickets 02–04.

### When the persisted identifier no longer resolves

The user deleted the calendar in Calendar.app, or removed the account.
`calendar(withIdentifier:)` returns `nil` and the old identifier is gone for good
— no API resurrects it. On enable, an unresolvable identifier is treated as
"create a new one", so the toggle succeeds rather than failing. Detecting that
deletion *while* sync is enabled is ticket 03's job, not this slice's.

`disable()` forgets the identifier **only once the calendar is actually gone** —
either removed successfully, or found to no longer resolve *while the app still
has full access* (the user deleted it in Calendar.app).

This is the correction of a bug device testing found. The first implementation
cleared the identifier **first**, reasoning that the app should stop claiming a
calendar it might not be able to see. That orphans the calendar on every path
where the removal cannot happen: with access revoked or downgraded to "Add
Only", `calendar(withIdentifier:)` answers `nil`, so the app dropped its only
handle while the calendar lived on — and the next enable built a second one
beside it. On the test device, toggling off and on across an access change left
**three** "Gym Streak" calendars, and switching off then removed only the newest.

So when access is missing, `disable()` now throws `.accessDenied` and **keeps**
the identifier. That is what makes the state recoverable: once the user restores
access, `enable()` adopts the very same calendar instead of stacking another one.
Pinned by `disableWithoutAccessKeepsTheIdentifier` and
`reEnableAfterRevokeDoesNotDuplicate`.

No ledger of every calendar the app ever created is kept, and none is needed:
after this fix there is no path that produces an untracked calendar. It only ever
removes the calendar whose identifier it recorded when it created it — a calendar
the app does not own is unreachable from that path.

---

## 5. Swift 6 concurrency — the answers, so nobody re-derives them

- **`EKEventStore` is not `Sendable`.** Its documented conformances are
  `CVarArg`, `CustomDebugStringConvertible`, `CustomStringConvertible`,
  `Equatable`, `Hashable`, `NSObjectProtocol` — no `Sendable`. It is confined to
  `@MainActor` per rule 2 of `docs/swift6-concurrency.md`. Writes here are a
  handful of events per plan change, so main-actor execution is not the
  `@ModelActor`-shaped problem History had.
- **That is a choice, not a constraint — do not read it as "off-main is
  impossible".** Not being `Sendable` only stops the store *crossing* an isolation
  boundary; it says nothing about a plain (non-`@MainActor`) `actor` **owning** one
  outright and exposing only `Sendable` request/response values. Nothing crosses,
  the actor's executor runs the blocking query off the main thread, and no
  `@concurrent`, `nonisolated(unsafe)` or undocumented behaviour is involved — it
  is what SE-0306 actors are for, and it is literally Apple's own advice for
  `events(matching:)`: *"This method is synchronous. For asynchronous behavior, run
  the method on another thread."* This is the documented escalation path if the
  pass ever needs to genuinely leave the main thread; it is not taken now because
  the measured cost does not call for it (§12g).
- **The `async throws -> Bool` variant is used:**
  `try await eventStore.requestFullAccessToEvents()`.
- **Rule 4's runtime-trap hazard does not apply to these APIs**, and that is
  worth stating because it is the project's most expensive past bug (TestFlight
  1.1.10). EventKit *does* annotate: both completion overloads are
  `completion: @escaping @Sendable (Bool, (any Error)?) -> Void`. Unlike
  WatchConnectivity there is no annotation gap to guard against. The completion
  fires on an arbitrary queue, so the `async` variant is simply the better call.
- `saveCalendar(_:commit:)`, `removeCalendar(_:commit:)`, `save(_:span:commit:)`,
  `remove(_:span:commit:)` and `commit()` are all **synchronous `throws`** — no
  closures at all. That is why `WorkoutCalendarSyncing.disable()` is
  non-`async`.
- **Prefer `events(matching:)` over `enumerateEvents(matching:using:)`** in later
  slices. The `Sendable` annotation status of `EKEventSearchCallback` could not be
  confirmed from primary sources; `events(matching:)` returns an array and
  sidesteps the question. Queries here are small and calendar-scoped.
- **The `EKEventStore` is built lazily, not at launch.** The gateway is
  constructed in `AppDependencies.init()` — i.e. inside `GymStreakApp.init()` —
  for every user, including the majority who never switch calendar sync on.
  `EKEventStore()` opens a connection to the Calendar store and Apple documents
  it as relatively expensive, so an eagerly-evaluated default argument would put
  that on the main thread of every cold launch to serve a feature most launches
  never touch. The init parameter is therefore an
  `@autoclosure @escaping () -> EKEventStore` held behind a `private lazy var`
  — still an injection point for tests, but not evaluated until something
  actually needs the store. `accessStatus` reads the **static**
  `EKEventStore.authorizationStatus(for:)` and `disable()` returns on the
  persisted identifier first, so neither forces the store into existence. `lazy`
  needs no synchronisation because the class is `@MainActor`-confined.
- **Only the app's own error vocabulary leaves `Data/`.**
  `requestFullAccessToEvents()` is wrapped in `do`/`catch` and rethrown as
  `WorkoutCalendarSyncError.accessDenied`. Unwrapped, a raw `EKError` would
  cross the Domain seam, land in `CalendarSyncSettingsViewModel.failure(for:)`'s
  `default:` branch and be shown to the user as "Apple Calendar refused the
  change. Please try again." for what is really a permission problem. A
  *refusal* comes back as `false`, never as a throw, so a throw here is an
  access problem and the Settings remedy is the right one.
- `.EKEventStoreChanged` is **posted on the main actor** and carries no per-change
  detail. Whether it fires for the app's own commits is undocumented — do not
  build a loop that depends on it either way (ticket 03).

---

## 6. Architecture

Dependency direction is the project's usual `Presentation → Domain ← Data`.

| Layer | File | Role |
| --- | --- | --- |
| Domain | `Domain/Interfaces/WorkoutCalendarSyncing.swift` | `@MainActor protocol` + `CalendarAccessStatus` + `WorkoutCalendarSyncError`. **Does not import EventKit** — authorization crosses the seam as the app's own enum. |
| Domain | `Domain/Interfaces/CalendarSyncPreferenceProviding.swift` | The opt-in flag's surface, sibling of `WeightUnitPreferenceProviding`. |
| Data | `Data/Calendar/EventKitWorkoutCalendarSync.swift` | The **only** file in the target that imports EventKit and the only owner of an `EKEventStore`. |
| Data | `Data/Calendar/WorkoutCalendarAdoption.swift` | The duplicate guard's matching rule — pure and EventKit-free, so it can be tested (§4a). |
| Domain | `Domain/Services/PlannedWorkoutCalendarReconciler.swift` | The mirror's policy: the marker, the window, and the create/delete diff. Foundation only (§11). |
| Domain | `Domain/Services/PlannedWorkoutOccurrenceBuilder.swift` | Turns routines + history into the occurrences the calendar should hold, through `WorkoutPlanningService` (§11). |
| Domain | `Domain/Interfaces/PlannedWorkoutCalendarMirroring.swift` | The one call every trigger site makes: `reconcile(revalidatingCalendar:)`, with a `reconcile()` default (§12d). Never throws. |
| Data | `Data/Calendar/PlannedWorkoutCalendarMirror.swift` | The coordinator: opt-in gate → repositories → builder → short-circuit → gateway, with failures logged and swallowed and both take-it-away cases handled (§12d, §12e). |
| Data | `Data/Calendar/EventKitWorkoutCalendarSync+Mirror.swift` | The gateway's event-writing half — read back, diff, batched commit. Split out to keep both files inside the size guidance. |
| Data | `Data/Preferences/CalendarSyncPreference.swift` | `@Observable @MainActor final class`, `static let shared`, write-through `didSet` into `UserDefaults`, `init(defaults:)` injectable. Shaped exactly like `WeightUnitPreference`. |
| Presentation | `Presentation/ViewModels/CalendarSyncSettingsViewModel.swift` | The toggle's state machine: request → create → persist, with the failure vocabulary the section renders. |
| Presentation | `Presentation/Views/Settings/Components/CalendarSyncSettingsSectionView.swift` | The Settings section, composed into `SettingsRootView` after `UnitsSettingsSectionView`. |
| App | `App/AppDependencies.swift` | Wires `calendarSyncPreference`, `workoutCalendarSync` and `plannedWorkoutCalendarMirror` (Hard rule 5). |

### Two pieces of persisted state, deliberately separate

- `calendar_sync.enabled` — the user's **intent**, owned by
  `CalendarSyncPreference`.
- `calendar_sync.calendar_identifier` — the app's **calendar**, owned by
  `EventKitWorkoutCalendarSync` and never read by Presentation.

Keeping them apart is what lets the toggle stay honest: the flag is only ever
written `true` *after* access is granted and the calendar exists, so a denied
prompt leaves the toggle off rather than claiming a sync that cannot happen.

### Two notes on the implementation

- **`@AppStorage` is not used**, because there is none anywhere in this
  codebase. The preference follows `WeightUnitPreference` instead.
- **The calendar's colour is a literal in `Data/`.** `Data/` must not import
  `Presentation/`, so `EventKitWorkoutCalendarSync.calendarColor` restates
  `DesignSystem.Colors.tint` (0, 255, 133) with a comment. Keep the two in step
  by hand — this is the one place a design token leaves the app, since
  Calendar.app paints the calendar with it.

### The calendar's title is localized

Key `calendar_sync.calendar.title`, which reads **"Gym Streak"** in both `en` and
`de` — the two-word user-facing brand used throughout the app's copy, not the
one-word bundle name.

---

## 7. Localization

`GymStreak/Resources/en.lproj/Localizable.strings` and
`de.lproj/Localizable.strings`, kept in lockstep, under the `calendar_sync.*`
prefix (existing planning keys live under `schedule.*`). Dot-notation keys plus
the `.localized` extension — **not** `String(localized:)` and not
`LocalizedStringKey`; the iOS target does not use `.xcstrings` (only the watch
does).

Keys: `section.title`, `section.footer`, `row.title`, `row.subtitle`,
`calendar.title`, `denied.title`, `denied.subtitle`, `failed.title`,
`failed.no_source.subtitle`, `failed.write.subtitle`.

The denied copy says **what to do** — "Tap here, then Calendars → Full Access" —
and the row itself opens `UIApplication.openSettingsURLString`, because telling
the user a permission is missing without taking them where they can grant it is a
dead end.

---

## 8. Tests

`GymStreakTests/CalendarSyncOptInTests.swift` — Swift Testing,
`@Suite(.serialized) @MainActor`, no model container needed (nothing here touches
SwiftData). Each test gets its own throwaway `UserDefaults` suite, so nothing
writes into the device's real defaults and no test can see another's flag.

**The real `EKEventStore` is never exercised** — `GymStreakTests/Support/
FakeWorkoutCalendarSync.swift` stands in, mirroring
`MockHealthKitWorkoutServicing`. The protocol seam is what makes that possible.

Covered: off by default; the flag survives a relaunch in both directions; a grant
persists the flag and leaves a calendar owned; a second enable creates no second
calendar; denied/restricted leaves the toggle off with the `.accessDenied`
remedy and does not retry on its own; `noWritableSource` and a write failure are
distinct, non-permission failures; disabling removes the calendar; a *failed*
removal still honours the user's intent to switch off; a retry clears the
previous failure.

`GymStreakTests/WorkoutCalendarAdoptionTests.swift` covers the duplicate guard
directly, since the rule was extracted precisely to be testable: adoption after a
reinstall, all three match conditions independently and together, exact-title
matching, and determinism when several orphans match.

`bundle exec fastlane test_unit_ios` (run here as `xcodebuild … -scheme
GymStreakTests test`) is green — 1072 tests in 120 suites. The **watch suite is
not required**: no watch code is touched.

---

## 9. Device verification — walked 2026-09-02 (iOS 26.1)

**Result: all five paths pass after two fixes.** Paths 1–3 passed first time.
Paths 4 and 5 failed and produced the orphaned-calendar bug corrected in §4;
the prompt's language failed and produced the localization fix in §3. Both are
re-verified by a green suite (1062 tests) and a bundle-level check of
`de.lproj/InfoPlist.strings`, but **the four paths below should be re-walked on
device** after those changes, since the failures were only observable there.

> **One-time cleanup on any device that ran the buggy build:** the orphaned
> "Gym Streak" calendars it left behind are untracked by definition, so the app
> cannot remove them. Delete them by hand in Calendar.app. No shipping build
> ever had this behaviour.

### Why device testing was mandatory

Multiple iOS-17-era forum reports describe the authorization APIs behaving
unreliably ([742809](https://developer.apple.com/forums/thread/742809),
[738398](https://developer.apple.com/forums/thread/738398),
[742371](https://developer.apple.com/forums/thread/742371),
[764567](https://developer.apple.com/forums/thread/764567)); current status on
26.1 could not be confirmed from primary sources. **Simulator agreement is not
enough.** The five paths, with what the first run found:

1. **Grant** — one prompt; a green "Gym Streak" calendar appears in Calendar.app
   on the iCloud source, and on a second signed-in device. **Passed** — which
   also proves the `INFOPLIST_KEY_…` build setting landed, since a missing usage
   description hard-crashes this call. The prompt's *text*, however, was English
   on a German device → §3.
2. **Deny** — toggle stays off, denied row appears, tapping it opens the app's
   Settings page, flipping again does not re-prompt. **Passed.**
3. **Revoke in Settings**, including "Add Only", which must behave as denied.
   **Passed** as far as the toggle goes — but this is the path that silently
   orphaned the calendar, which only showed up in 4 and 5.
4. **Delete the calendar in Calendar.app**, then re-enable — a new calendar is
   created rather than the toggle failing. **Failed:** a new calendar was created
   on *every* enable, leaving three "Gym Streak" entries → §4.
5. **Switch off with the calendar present** — it disappears and no other calendar
   changes. **Failed:** only the newest was removed; the orphans stayed. Same
   root cause as 4 → §4.

---

## 9a. Architecture review

`architecture-reviewer` returned **PASS WITH WARNINGS** — no CRITICAL findings.
Both warnings were **fixed rather than merely acknowledged**, and are the two
bullets added to §5: the launch-time `EKEventStore` allocation, and the
unwrapped EventKit error escaping the protocol's documented `throws` contract.
The reviewer independently confirmed the layer claims (no EventKit in `Domain/`,
the single `EKEventStore` in `Data/Calendar/`, both gateways reachable only
through `AppDependencies`, no `.shared` in the ViewModel, no business logic or
formatter/aggregation in the view body).

Two advisory notes worth carrying forward:

- `accessStatus` and `appCalendarIdentifier` have no *production* reader outside
  `enable()`'s own guard in this slice — they exist for tickets 02/03. Re-check
  there that they earn their place rather than lingering as protocol surface.
- An `INFOPLIST_KEY_*` Xcode does not recognise is **silently dropped**, and a
  missing usage description **hard-crashes** the first
  `requestFullAccessToEvents()` call. §9 path 1 is what proves the key landed —
  walk it rather than assuming it.

## 10. Out of scope for slice 1

Event writing (ticket 02, now shipped — §11), drift detection and refresh (03),
weekday series (04), and `EventKitUI` entirely.

---

## 11. Slice 2 — cadence plans appear in the calendar

With sync on, a routine planned on a rolling cadence ("every 5 days") puts its
next occurrences into the app-owned calendar as **all-day events**: "Push" becomes
"Push Workout" on each planned day. Editing the interval or the reference date
updates the calendar immediately, clearing the plan removes that routine's events,
and a routine with no plan — or a paused one — contributes nothing.

This is the free tier's whole capability, and deliberately so: `everyNDays` is the
only plan shape a free user has, because fixed weekdays are already Pro (P9 in
`docs/workout-planning.md`). The depth gate therefore sits upstream in the
schedule itself; **calendar sync adds no gate of its own** and nothing here reads
an entitlement.

### 11a. Why a rolling window of one-shot events, and not `EKRecurrenceRule`

`EKRecurrenceRule(recurrenceWithFrequency: .daily, interval: N, end: nil)`
expresses "every N days" perfectly, and it is still the **wrong model for this
plan shape** — for a reason that lives in this app's semantics, not in EventKit.

A cadence plan is not a fixed grid.
`WorkoutPlanningService.cadenceAnchor(startDate:lastCompleted:calendar:)`
re-derives the anchor from **the last completed session**, with
`RoutineSchedule.startDate` acting only as a floor. The entire series therefore
moves forward every time the user finishes a workout — which, for a routine
trained on its cadence, is *every session*. A recurring event would have to be
destroyed and recreated after almost every workout: the same churn as one-shots,
plus an infinite tail of occurrences the app cannot justify, because they depend
on completions that have not happened yet.

A bounded forward window is also what the app already believes about itself.
Every existing surface reads the plan through
`WorkoutPlanningService.upcomingCadenceDates(...)` — a `count`-bounded walk used
by `plannedWeek` and by the planning sheet's live "next sessions" preview. The
calendar mirror calls the very same helper, so what the user sees in Calendar.app
is exactly what the app tells itself, and no further. A unit test asserts that
equality directly rather than trusting it.

**Weekday plans are genuinely different and do get a recurrence rule** — that is
ticket 04, and the split falls exactly on the `RoutineScheduleType` boundary.
Until then a weekday plan mirrors nothing at all, which is a visible gap for a Pro
user with a fixed split.

### 11b. Identity lives in the event, not in local bookkeeping

Every written event carries a marker in `EKEvent.url`:

```
gymstreak://routine/<routine-uuid>/occurrence/<yyyy-MM-dd>
```

and reconciliation reads it **back out of the calendar**. There is no persisted
map of events, and `eventIdentifier` is not used as a durable key anywhere —
Apple: *"if you change the calendar of an event, this ID will likely change. It is
currently also possible for the ID to change due to a sync operation."*

Because the app owns its calendar exclusively, the calendar *is* the state. That
means nothing local can drift out of sync, and behaviour stays correct after a
reinstall, or on a second device syncing the same CalDAV calendar. The marker goes
in `url` rather than `notes` so the notes field stays the user's own; the app
already declares `CFBundleURLTypes` for the scheme.

Two details that are easy to get wrong:

- **The day is rendered from `Calendar` components, not a `DateFormatter`.** A
  formatter caches its time zone at construction, and the main-thread rules
  require hoisting it to a `static let` — which together would mean a marker that
  silently shifts by a day for a user who travels.
- **An event whose `url` does not parse as a marker is never touched.** The user
  can add their own events to the app's calendar in Calendar.app, and deleting
  them would be destroying user data. Unparseable means "not ours", full stop.

### 11c. The window, and why the past is never touched

One pass owns whole days from **today** to the later of the furthest planned
occurrence and a floor of `minimumWindowDays = 400`.

- **Starting at today** leaves past events alone. They are a record of what the
  user planned, and re-diffing them would quietly rewrite the user's calendar
  history on every plan change.
- **The 400-day floor** is a cleanup reach, not a lookahead: the planning sheet
  caps the cadence at 30 days and the mirror writes 8 occurrences per routine, so
  a plan anchored today reaches ~240 days out. The floor is what lets a
  *shortened* or *cleared* long cadence still find the events it left behind.
- **The query range is a day wider on each side than the window**, and the pass
  filters back down to the window itself. Apple documents that
  `predicateForEvents(withStart:end:calendars:)` evaluates its range in the
  default time zone and caps it at four years, but says **nothing** about boundary
  inclusivity — and it is an *overlap* query, not a containment one. Widening and
  filtering ourselves removes the dependency on the undocumented edge at no cost.

**Horizon: the next 8 occurrences per planned routine.** Far enough ahead that the
calendar looks planned rather than sparse, short enough that a window left stale by
an app nobody has opened in weeks is not embarrassing — and for the common 3-to-5
day cadences, roughly a month of lookahead. Keeping it topped up is ticket 03.

### 11d. Event shape: all-day, no alarm

- `isAllDay = true`, `startDate` = the occurrence day, `endDate` = **the same
  day**. A plan carries a date and no time of day, and inventing one would assert
  something the app never captured; an all-day event also does not block the
  user's day or attract travel-time suggestions.
- `timeZone = nil`. That is Apple's documented meaning of a *floating* event — one
  not tied to a time zone — and the SDK header explicitly calls all-day events
  floating. Pinning `TimeZone.current` would enter undocumented territory.
- **No `EKAlarm`.** An alarm would quietly deliver the deferred planned-workout
  reminder (`docs/workout-planning.md` § "Deferred to phase 2") through a
  different mechanism than that design chose. It stays an **open option**, to be
  taken as a product decision on its own — not slipped in here.
- The title comes from `calendar_sync.event.title_format` (`"%@ Workout"` in both
  `en` and `de`), so a routine named "Push" reads "Push Workout".

### 11e. Writes, batching and failure

Every `save`/`remove` passes `commit: false` and one trailing
`eventStore.commit()` sends the batch, so a plan change costs the user's calendar
a single round-trip rather than one per event.

On any throw the pass calls `eventStore.reset()` and gives up. That is Apple's
documented recovery, not tidiness: *"If a batch operation fails, subsequent
commits will fail until the event store is manually reset using the reset
method."* `reset()` invalidates **every object ever fetched from the store**,
which is safe here only because each pass re-fetches the calendar by identifier
and holds no `EKEvent` across passes.

`EKError.calendarReadOnly` needs no special case — it lands in the same handler,
along with `.invalidCalendar` (the user deleted the calendar between passes),
`.eventStoreNotAuthorized` (access revoked mid-session) and the rest. **The plan
is the source of truth and the calendar is a projection of it**, so
`PlannedWorkoutCalendarMirror` logs the failure and swallows it: a failed mirror
must never block a plan edit or lose the user's schedule change. A test pins that
a plan saves correctly while the gateway is throwing.

### 11f. Triggers in this slice

`RoutinesViewModel.setSchedule(...)` and `removeSchedule(from:)` are the **only**
write paths for a schedule anywhere in the target — confirmed by repo-wide grep —
so they are the only hooks, plus the Settings toggle, which reconciles right after
it flips the flag so switching sync on fills the calendar immediately instead of
waiting for the next plan edit. **The flag is written before the mirror runs**,
because the mirror reads it as its own gate.

No timer, no `.EKEventStoreChanged` observer, no completion hook in *this* slice:
drift and window refresh were deferred to slice 3, which added the completion and
foreground triggers (§12b) and kept the `.EKEventStoreChanged` decision (§12c).

### 11g. EventKit research — where Apple's docs are silent

Captured so nobody re-derives it (via `ios-api-researcher`, against the iOS 26 SDK
headers and developer.apple.com):

| Question | Answer |
| --- | --- |
| `endDate` semantics for an all-day event | **Undocumented.** EventKit's `endDate` is *inclusive* of the last all-day day — unlike RFC 5545's exclusive `DTEND` — so the next day would render a two-day event. Empirical; verified on device (§11i). Equal start/end does not trip `EKErrorDatesInverted`, which fires only when end precedes start. |
| `url` durability / CalDAV round-trip | **Undocumented.** Writable since iOS 5, no discussion text at all. CalDAV stores RFC 5545's `URL` property verbatim, so it very likely survives — but cross-device round-trip is unverified. |
| Predicate boundary inclusivity | **Undocumented** — it is an overlap query. The range *is* documented as evaluated in the default time zone and capped at four years. Hence the widen-and-filter in §11c. |
| All-day with a non-nil `timeZone` | **Undocumented.** Hence `nil`. |
| Concurrency | `save`, `remove`, `commit`, `reset`, `events(matching:)` and `predicateForEvents` are all synchronous and closure-free — the project's rule-4 `@Sendable` trap does not apply. Nothing in EventKit is `NS_SWIFT_SENDABLE`. Main-actor confinement is the *simplest* fit for this call volume, **not the only option** — see below. |
| `events(matching:)` on the main thread | Apple suggests running it off-thread, which a non-`Sendable` store makes impossible. Mitigated by a bounded window and a single-calendar scope. |
| `objectBelongsToDifferentStore` | A **trap**: passing an event from another store *raises an Objective-C exception*, uncatchable in Swift. Hold one long-lived store — which this app does — and never let a foreign `EKEvent` reach `save`. |
| Uncommitted changes | Invisible to `events(matching:)`: *"Only committed events are included in the results."* So a pass must read first, then batch-write, and can never re-query mid-batch to see its own pending work. |

### 11h. Tests

Three new suites, Swift Testing, `@Suite(.serialized) @MainActor`, **35 tests, and
no `EKEventStore` is ever constructed** — the pure `Domain/` seam plus
`FakeWorkoutCalendarSync` is what buys that:

- `PlannedWorkoutCalendarReconcilerTests` — the marker (format, round-trip,
  case-insensitive UUID, seven flavours of foreign or malformed URL), the window
  (starts today, reaches the furthest occurrence, falls back to the floor, query
  range wider than the window), and the diff (create-only, no-op, delete-only,
  mixed, two independent routines, unmarked events untouched, duplicates
  collapsed).
- `PlannedWorkoutCalendarMirrorTests` — what actually reaches the gateway: the
  cadence batch equals `upcomingCadenceDates` exactly; unplanned, paused and
  weekday routines contribute nothing; two routines both mirror with unique
  markers; the opt-in gates the whole pass; a throwing gateway leaves the plan
  saved; and all three trigger sites fire.
- `WorkoutPlanningServiceTests` — first *direct* coverage of `cadenceAnchor`,
  `upcomingCadenceDates` and `nextDue`, which the calendar now makes a second
  consumer of. Reference-date floor, re-anchoring completion, ignored stale
  completion, the far-past `gapDays / N` fast-forward, an overdue plan, the
  clamped interval.

Full iOS suite green: **1107 tests in 123 suites**. The watch suite is not
required — no watch code is touched.

### 11i. Device verification — walked 2026-09-03, passed

Verified on a physical device by the user. The checklist walked: a cadence plan's
entries appear in the "Gym Streak" calendar on exactly the days the planning sheet
previews; they render **all-day with no alarm**; editing the interval and editing
the reference date both move the series with no leftovers or duplicates; re-saving
an unchanged plan changes nothing in Calendar.app; removing a plan removes only
that routine's entries; unplanned, paused and weekday routines write nothing; an
event added by hand into the app's calendar survives a reconcile; switching sync
off takes the calendar and its entries away.

**The undocumented inclusive `endDate` (§11g) is confirmed**: entries render as one
day, not two. Had it been exclusive, every event would have spanned two days — so
`endDate = startDate` is correct for a single-day all-day event, and this is now
observed behaviour rather than an assumption.

**No hitch was reported on the Save tap**, but no latency measurement was taken
here. Slice 3 measured the same pass on the routines-list path instead — see
§12g, which closes warning 2 in §11k for everything except the EventKit
round-trip on a real CalDAV store (§12i step 6).

### 11j. Follow-ups (recorded, not fixed)

- ~~**Deleting a routine does not reconcile.**~~ **Resolved in slice 3**: the hook
  moved to `fetchRoutines()`, which `deleteRoutine(_:)` ends in (§12b).
- **Events beyond the window are unreachable after the plan that made them is
  cleared.** A cadence anchored far in the future can write occurrences past the
  400-day floor; clearing it leaves nothing desired, so the window falls back to
  the floor and those events stay. Switching sync off removes the whole calendar
  regardless.
- **Weekday plans mirror nothing** until ticket 04 — a visible gap for a Pro user
  on a fixed split.
- **The forward weekday scan is triplicated** (`WorkoutPlanningService` twice,
  `SchedulePlanningSheet` once). Real, untouched here — this feature does not need
  it, and a bug fix does not carry surrounding cleanup.

### 11k. Architecture review

`architecture-reviewer`: **PASS WITH WARNINGS**, no CRITICAL findings.

- **Warning 1 — file size.** `EventKitWorkoutCalendarSync.swift` had grown to 365
  lines. **Fixed:** `mirror(occurrences:)` and `makeEvent(for:in:)` moved to
  `EventKitWorkoutCalendarSync+Mirror.swift` (262 + 138 lines), following the
  `WatchTemplateTransactionService+…` precedent. `eventStore` is `internal` rather
  than `private` purely because `private` is file-scoped; nothing outside the type
  reads it and the `EKEventStore` still never leaves `Data/Calendar/`.
- **Warning 2 — the pass is synchronous on the main actor on the Save tap.**
  Acknowledged, not fixed in slice 2. **Measured in slice 3** (§12g): with sync
  on and 40 planned routines the routines list shows no regression, and the pass
  now runs in its own `Task` off the fetch's critical path (§12f). The EventKit
  round-trip against a real CalDAV store — which a simulator cannot represent —
  was walked on device on 2026-09-03 with no hitch observed (§12i step 6). **This
  warning is closed**, with the caveat that step 6 is an observation, not a trace.
- Advisory taken: the delete path now guards its index rather than force-indexing,
  so a future drift between the reconciler's handles and the array they index
  fails a delete instead of trapping.

The reviewer independently confirmed the layer placement of all four new types,
that no `isPro` reaches the path, that `eventIdentifier` is never read or
persisted, that the predicate is scoped to the app-owned calendar, that the
concurrency rules are untouched (no closure literal reaches an Apple API here — the
rule-4 `@Sendable` trap does not apply to EventKit's synchronous write API), and
that **no `@Model` changed, so no CloudKit schema deploy is implicated**.

It also flagged, independently, the two functional gaps already recorded in §11j —
plus one cheap way to close the second: the reference-date `DatePicker` in
`SchedulePlanningSheet` is unbounded, and bounding it to about a year out would put
every occurrence inside the cleanup window by construction.

---

## 12. Slice 3 — the mirror follows the plan

The calendar keeps telling the truth as the plan moves underneath it. The user
misses Tuesday's Push and trains on Thursday instead: the cadence re-anchors on
that completion and the calendar's future occurrences shift with it — from a
workout finished on the iPhone, on the watch, or on another device. The rolling
window tops itself up so it never runs dry. And when the user takes the calendar
or the permission away behind the app's back, the app notices and says so instead
of failing silently.

### 12a. The anchor is computed, never stored — which is what makes this cheap

There is **no "roll the plan forward" write** anywhere in the codebase, and none
was added. `RoutineSchedule` stores only `startDate` (a floor the user picks) and
the plan's shape. "Trained two days late → the plan moves" is a *pure
recomputation*:

- `WorkoutPlanningService.cadenceAnchor(startDate:lastCompleted:calendar:)`
  re-derives the anchor from the last completed session on every call.
- `lastCompleted` comes from
  `WorkoutSessionRepository.lastCompletedStartDates(forRoutineIds:)` — a
  per-routine `LIMIT 1` query over sessions with `endTime != nil`.

So this slice adds **no new state and no new anchor logic.** It only re-runs
slice 2's reconciler at the right moments and lets the existing diff do its work.
A test pins that the plan's `startDate` is unchanged after a drift.

**A payoff worth naming:** because slice 2 mirrors cadence plans as one-shot
events (§11a), an anchor shift is just "different desired dates" — delete the
stale ones, create the new ones. The app never edits into an existing recurring
series, so the one thing the API research could **not** verify from primary
sources — how `EKSpan.futureEvents` behaves when occurrences in range have already
been detached by the user editing them in Calendar.app — never arises for cadence
plans. Do not reintroduce it by "optimising" this into a recurring-series edit.

> **If a future change makes the anchor stored rather than computed, this
> section's assumptions have to be revisited.** Everything below rests on
> `desired` being a pure function of (plans, history, today).

### 12b. One hook covers watch ingest, iCloud and every plan change

Reconciliation is hooked to `RoutinesViewModel`'s two refresh paths —
`fetchRoutines()` and `refreshRoutinesWithoutWatchSync()` — *after*
`lastPerformedByRoutine` has been rebuilt. That single point covers every path
that can move an anchor:

| Path | How it reaches a refresh | Immediate? |
| --- | --- | --- |
| Workout finished on the watch | `WatchWorkoutIngestionService.ingest(_:)` materialises the session and posts `.workoutHistoryDidChange` | yes |
| Watch template transaction | `WatchTemplateTransactionService` posts `.workoutHistoryDidChange` | yes |
| A completion synced from another device | `.cloudKitDataDidChange` → `fetchRoutines()` | yes |
| Plan edited or cleared | `setSchedule(...)` / `removeSchedule(from:)` end in `fetchRoutines()` | yes |
| Routine deleted | `deleteRoutine(_:)` ends in `fetchRoutines()` | yes |
| **Workout finished on this iPhone** | nothing is posted — see below | on next Routines appearance or foreground |
| The routines list opened | `RoutinesView.onAppear` | — |
| The app becomes active | `scenePhase` (§12d) | — |

**The iPhone-local completion is the one path that is not immediate, and the
planning note was wrong about it.** The ticket's table asserted that
`WorkoutViewModel.completeWorkout(updateTemplate:notes:)` posts
`.workoutHistoryDidChange`; it does not. The only post in that type is inside
`recoverOrphanedWorkouts()`, and `.cloudKitDataDidChange` comes from
`NSPersistentStoreRemoteChange`, which does not fire for a local save. So after
finishing a workout on the iPhone the calendar re-anchors on the next
`RoutinesView.onAppear` or the next activation — both of which happen within
seconds of leaving the summary, so the calendar is correct at every point the user
can actually look at it, but it is not instantaneous. Making it so is recorded as
a follow-up (§12j) rather than done here, because it means posting from the app's
hottest path, where the notification also re-enters `WorkoutViewModel`'s own
observer and the workout-recovery engine.

Slice 2 made the reconciler idempotent, so the extra invocations this produces
are no-ops.

**One observer had to be added, because the planning assumption was wrong.**
The breakdown assumed `RoutinesViewModel` already observed
`.workoutHistoryDidChange`; a repo-wide grep showed it did not — the routines list
picked completions up only on its next `onAppear`. So `observeWorkoutHistoryChanges()`
was added, and it routes to `refreshRoutinesWithoutWatchSync()` rather than
`fetchRoutines()`: no routine *template* changed, so pushing a fresh generation at
the watch after every workout would be churn — and after a watch template
transaction it would emit a snapshot competing with the authoritative one that
transaction already staged (`docs/watch-sync.md`, ticket 05). It is one observer
covering two posting sites, not one per path. It also fixes a real staleness bug
that predates calendar sync: for a watch-ingested workout, a card's "last trained"
line, its next-due date and the hero's ordering now update as soon as it lands
instead of waiting for the tab to be re-entered.

**A hop is mandatory in these blocks, not conventional.** The first version of the
coalescing called the main-actor method *directly* from the notification block,
reasoning that `queue: .main` pins it to the main thread. `OperationQueue.main` does
guarantee that at runtime — but `addObserver(forName:object:queue:using:)` takes a
**`@Sendable`** block, so under SE-0461 the closure is inferred *nonisolated*
regardless of being written inside a `@MainActor` class, and the direct call
compiles with `warning: call to main actor-isolated instance method '…' in a
synchronous nonisolated context`. A warning, not an error — it builds and the tests
pass, so it is a silent regression against the project's zero-warning invariant.
Reverted to the hop. The full finding, including why this API is the *opposite* of
the rule-4 `@Sendable` hazard, is recorded in `docs/swift6-concurrency.md` §4.

**Bursts are coalesced.** Both posting sites fan out per item rather than per
batch — `WatchWorkoutIngestionService` posts once per inbox entry while the
coordinator drains the queue, and a template transaction posts
`.workoutHistoryDidChange` and then `.routineTemplateDidChangeLocally` for the
same commit. Uncoalesced, a drain of K workouts cost K × (`fetchAll()` + one
bounded session fetch per routine + a card rebuild), a product that scales with
the user's library — the shape of the hang in `docs/history-performance.md`.
`scheduleRefreshWithoutWatchSync()` collapses it, **through the hop rather than
around it**: each observer keeps the file's `queue: .main` + `Task { @MainActor
in … }` pattern, so nothing reads main-actor state from a notification block. The
burst's hops are all enqueued while it is being posted, and the refresh the first
of them schedules is created from inside that hop — so it lands behind the rest
(SE-0431 ordering, the same guarantee watch sync relies on) and every later
notification finds the slot taken. Nothing is dropped: the refresh re-reads the
store, so it sees the newest completion of the burst. No timer and no window —
the collapse is exactly one main-actor turn wide. `CloudSyncObserver`'s
time-based window exists for the different problem of *remote* changes arriving
over seconds.

**Window top-up and out-of-band discovery need one more trigger,** because
neither requires a completion: the app becoming active. `GymStreakApp`'s existing
`scenePhase == .active` branch calls
`plannedWorkoutCalendarMirror.reconcile(revalidatingCalendar: true)` — inside a
`Task`, for the reason in §12f, and more pointedly than anywhere else: this is
the one trigger that always reaches `events(matching:)`, so running it inline
would put a blocking CalDAV query on the activation turn, in front of the first
frame the user sees on returning to the app.

### 12c. `.EKEventStoreChanged` drives nothing

`.EKEventStoreChanged` is posted on the main actor and carries no detail about
what changed. **Whether it fires for the app's own commits is undocumented** and
could not be confirmed from primary sources, so an observer that reconciled on it
would risk a write → notification → write loop.

Decision: **check calendar state at reconcile time** — deterministic, cheap, and
already happening on the triggers above. No `.EKEventStoreChanged` observer exists
anywhere in the target, not even for display: the Settings row refreshes on
`.onAppear` and on `scenePhase == .active`, which covers the only moments it is on
screen (a revocation happens in Settings.app, so the user is necessarily away and
coming back). If one is ever added for display, it must never initiate a write.

### 12d. The short-circuit, and the one pass that deliberately steps over it

The hook fires after every routines refresh, and a pass ends in
`events(matching:)` against a CalDAV-backed store that Apple suggests not
querying on the main thread at all (§11g). So `PlannedWorkoutCalendarMirror`
remembers what the last **successful** pass wrote — the occurrences and the
calendar identifier — and returns before touching EventKit when neither has moved.

- **Exact, not hashed.** A handful of occurrences per routine is small enough to
  keep verbatim, and a hash collision here would mean a calendar that silently
  stops updating. `PlannedWorkoutOccurrence` is `Equatable`, so the comparison is
  free to write.
- **The calendar identifier is part of it**, so a recreated calendar — same plans,
  empty calendar — is never mistaken for a no-op.
- **In-memory only, for this launch.** A fresh launch always reconciles once,
  which is the cheapest way to recover from anything that happened while the app
  was not running. It is also cleared whenever the opt-in is off, whenever a pass
  fails, and when the calendar is found to be gone.

**`reconcile(revalidatingCalendar: true)` steps over it on purpose.** This is the
one design point that is easy to get wrong, and the first implementation did get
it wrong: neither take-it-away case moves the app's desired state by a single
byte, so a pass that trusted the cache could *never* discover them. A unit test
that deleted the calendar and then reconciled saw nothing happen. Hence the
parameter: the plumbing triggers pass `false` (and are short-circuited), while the
once-per-activation trigger passes `true` and accepts one query for the
revalidation. The protocol carries a `reconcile()` extension defaulting to
`false`, so no existing call site had to change.

This is the honest reading of the acceptance criterion "an unchanged desired state
performs no EventKit query at all": it holds for the frequently-fired hook, which
is what the criterion protects, and is traded away exactly once per foreground for
the only thing that can detect an out-of-band change.

### 12e. When the user takes it away

Two out-of-band cases, both discovered at reconcile time. **Neither loses or
alters the user's plan** — the plan is the source of truth and the calendar is a
projection of it.

**1. The owned calendar is gone.** `calendar(withIdentifier:)` returns `nil` (the
user deleted it in Calendar.app, or removed the account). The gateway now throws
`WorkoutCalendarSyncError.calendarMissing` rather than returning silently, because
a pass is the only place the app can find out — nothing notifies it.

Deleting a calendar is a deliberate act, so it is **treated as an opt-out**: the
mirror calls `disable()` (which drops the now-stale identifier, and is what stops
the next enable from stacking a second calendar beside a dead handle) and writes
`isCalendarSyncEnabled = false`. The Settings toggle then reads off, which *is*
the honest state. Re-enabling creates a fresh calendar and fills a full window.

*Alternative considered and rejected:* silently recreating the calendar. It fights
the user and would make the calendar impossible to get rid of without also finding
the toggle.

**2. Access was revoked in Settings.** `authorizationStatus(for: .event)` is no
longer `.fullAccess`, so the gateway's existing guard throws `.accessDenied`. The
mirror stops writing and logs at `info` — a user decision is not an error — and
**leaves the intent flag on**, so restoring access resumes the mirror by itself
with no second trip to the toggle. Nothing re-prompts;
`requestFullAccessToEvents()` would not present anything anyway once the user has
decided.

The Settings row reflects it: `CalendarSyncSettingsViewModel.refreshStatus()`
shows the existing `calendar_sync.denied.*` row — which already carries the path
back ("Tap here, then Calendars → Full Access") — whenever sync is on and access
is not. It clears only that failure, never a `.writeFailed` the user's own toggle
tap produced. **No new localized strings were needed for either case.**

### 12f. Off the routines-list critical path

`reconcileCalendar()` wraps the pass in a `Task` rather than calling it inline, so
it runs in its own main-actor turn after the fetch and the first frame (main-thread
rules 3 and 7). It is never called from a view body or an `onAppear`. **Every
trigger does this**, the scene-phase one included (§12b) — a `Task` created from
the main actor stays on it, so this defers the work rather than moving it off, and
deferral is the whole point: the list's first frame goes first.

The pass re-reads routines and last-completed dates rather than taking them from
the refresh that triggered it. That is a deliberate duplicate: the mirror is also
driven by the Settings toggle and by `scenePhase`, neither of which has a routines
list to hand, and a `reconcile(routines:lastCompleted:)` surface would push that
glue back out into every call site. The cost is one `fetchAll()` plus one bounded
`LIMIT 1` query per routine — the same shape the list itself pays.

**Known escape hatch, if measurement ever says main-actor is wrong:** the store
cannot simply *hop* off the main actor, because it is not `Sendable` and so cannot
cross an isolation boundary — but a plain `actor` owning the store and the gateway,
exposing only `Sendable` values, runs the blocking query off the main thread and is
an ordinary supported pattern (§5). Not done pre-emptively: this is the same
failure mode as the 630 ms History hang (`docs/history-performance.md`), so it is
measured rather than assumed, and §12g says the measurement does not call for it.

### 12g. Measurement

Method and probe from `docs/history-performance.md` §5: the in-app
`MainThreadStallProbe`, read out of the UI test's result bundle. Click path:
launch with a 40-routine library → **Routines → History → Routines** → read the
probe (re-entering resets it on `onAppear`, so the figure is `fetchRoutines()`
plus the first frame, not the seeding).

`RoutinesResponsivenessUITests.testRoutinesListWithCalendarSyncEnabled` adds the
sync-on case: the same 40 routines, **all planned** (`-UI_TEST_PLAN_ROUTINES`
gives each a 2–8 day cadence), with the opt-in flipped through `NSArgumentDomain`
(`-calendar_sync.enabled YES`) rather than through the toggle — so no production
code knows it is under test and no permission prompt appears.

Max main-run-loop delay on opening Routines, iPhone 17 Pro simulator (iOS 26.5),
four/three runs each:

| Build | Samples (ms) | Max |
| --- | --- | --- |
| Before this slice, sync off | 1, 35, 7, 1 | 35 |
| After, sync off | 9, 25, 8, 9, 5 | 25 |
| After, sync **on**, 40 planned routines | 24, 13, 36, 31 | 36 |

(The last sample in each "after" row is a confirming run taken after the
architecture review's fixes — the deferred scene-phase pass and the burst
coalescing in §12b.)

Scrolling was unchanged (before 32–50 ms, after 31–47 ms). Every figure is far
under the test's 250 ms / 150 ms thresholds and inside the others' spread — the
run-to-run variance (1 → 35 ms on the *unmodified* build) is larger than any
difference between the columns. **No regression.**

**What this does and does not cover.** It measures everything the mirror pays on
every pass and everything that scales with the user's library: the routine fetch,
40 `lastCompletedStartDates` lookups, 40 cadence walks and the digest comparison.
It does **not** measure the EventKit round-trip, which a simulator cannot
represent — there is no CalDAV-backed store behind it, and `events(matching:)`
against a local store with a few dozen events is not the cost that matters. That
half belongs to device verification (§12i), exactly as §11i's `endDate` behaviour
did — walked on 2026-09-03 with no hitch observed, which is an observation rather
than a number; see §12i for what that does and does not establish.

### 12h. Tests

One new suite, `PlannedWorkoutCalendarDriftTests` — Swift Testing,
`@Suite(.serialized) @MainActor`, in-memory container, **no `EKEventStore` is
constructed**:

- **Drift.** Due 3 days ago on a 7-day cadence, trained 2 days late → the whole
  series re-anchors (+6, +13, …), the stale +4 is gone, and `schedule.startDate`
  is untouched. The same case straight through the pure reconciler, asserting the
  create/delete actions. And the same again driven by `.workoutHistoryDidChange`,
  which is the notification the watch's ingestion posts — no separate code path
  and no watch file touched.
- **Top-up.** Four completions across a month: a full horizon every time, no
  duplicates, nothing in the past, and consecutive days exactly one interval
  apart. Plus: the window starts today, so yesterday is outside it.
- **The short-circuit.** Three ordinary passes cost one gateway call; a changed
  plan gets through; a recreated calendar is refilled, not skipped; and a
  revalidating pass reaches the calendar with nothing changed.
- **Take-it-away.** A deleted calendar switches sync off, drops the stale handle
  and leaves the plan intact; further passes write nothing and do not fail
  repeatedly; re-enabling produces a fresh calendar and a full window. Revoked
  access stops the writes, keeps the intent flag and the plan, and never calls
  `enable()`; restoring access resumes on the next pass; and the Settings row
  shows the denied row with the way back, then clears it.

`FakeWorkoutCalendarSync` now models the real gateway's own guards — access first,
then the calendar, with `isCalendarMissing` standing in for a calendar the user
deleted. A fake that recorded regardless would have let all of the above pass
untested. The existing `PlannedWorkoutCalendarMirrorTests` harness was updated to
start from the state the app is actually in when sync is on (full access, a
calendar owned), and its trigger tests now `await` a yield, because the pass is
deliberately deferred off the fetch's critical path.

Full iOS suite green: **1179 tests, 0 failures.** The watch suite is **not**
required — no watch file is touched, confirmed by `git status`.

### 12i. Device verification — walked 2026-09-03, passed

Verified on a physical device by the user; all six steps passed. The checklist, in
the shape of §11i:

1. With sync on and an overdue cadence plan, finishing the workout **late** moves
   the calendar's future entries onto the new cadence and takes the stale ones
   away. **Passed** — this is the Things note's "due Tuesday, trained Thursday"
   case, and it is now observed behaviour rather than a unit-test inference.
2. The same for a workout finished **on the watch** and ingested with the iPhone
   app foregrounded on another tab. **Passed** — confirming the ingest path needs
   no code of its own.
3. Past entries untouched throughout. **Passed.**
4. Deleting the "Gym Streak" calendar in Calendar.app and returning to the app:
   the Settings toggle reads **off**, no calendar is recreated, nothing crashes;
   re-enabling produces a fresh calendar with a full window. **Passed** — so the
   revalidating foreground pass (§12d) does discover a deletion against a real
   CalDAV store, which is the case the short-circuit originally hid.
5. Revoking Calendar access in Settings: the Settings row shows "Calendar access
   needed" with the tappable path, no prompt loops, the plan is unchanged, and
   restoring access resumes the mirror on its own. **Passed.**
6. Opening Routines with sync on and several planned routines on a device signed
   into iCloud. **No hitch observed.**

**What step 6 does and does not establish.** It is an observation, not a
measurement — no Instruments trace was taken, because nothing was felt to chase.
So the EventKit round-trip against a real CalDAV store is *not disproved* as a
cost; it is simply below the threshold of noticeable at this library size. If a
future slice adds work to the same pass — ticket 04's recurrence writes, say —
re-walk this step and take a trace rather than assuming it still holds. The
escalation path if it ever does not is in §12f.

### 12j. Follow-ups

- **Resolved from §11j:** deleting a routine now reconciles — `deleteRoutine(_:)`
  ends in `fetchRoutines()`, which is a hook.
- **Still open from §11j:** events written beyond the 400-day window are
  unreachable once the plan that made them is cleared; weekday plans mirror
  nothing until ticket 04; the forward weekday scan is triplicated.
- **A workout finished on this iPhone does not refresh immediately** (§12b). The
  calendar is still correct on the next Routines appearance or foreground, so
  this is a latency gap and not a wrong calendar. Closing it is one line — post
  `.workoutHistoryDidChange` at the end of
  `WorkoutViewModel.completeWorkout(updateTemplate:notes:)` — but that
  notification also re-enters that type's own observer (which has already run
  `refreshHistory()` inline) and drives `WorkoutRecovery.reconcile()`, so it is a
  change to the workout-completion path that wants verifying on its own terms,
  not inside a calendar-sync slice.
- **`RoutinesViewModel` is 1171 lines**, ~4× the 300-line guidance, and this
  slice added ~60 more. Pre-existing; when it is next touched substantially, the
  four `observe…()` methods and their tokens are the natural extraction.
- **The revalidating pass is once per activation, not throttled.** An app the user
  foregrounds repeatedly in a minute pays one bounded, calendar-scoped query each
  time. Acceptable at this size; if it ever is not, throttle by wall-clock in the
  mirror rather than by moving the trigger.
