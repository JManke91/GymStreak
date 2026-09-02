# Calendar Sync — planned workouts in Apple Calendar

**Status:** slice 1 of 4 shipped — opt-in and calendar ownership. No workout
events are written yet (ticket 02), nothing is revised or refreshed (03), and
weekday series are not modelled (04).

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
| Data | `Data/Preferences/CalendarSyncPreference.swift` | `@Observable @MainActor final class`, `static let shared`, write-through `didSet` into `UserDefaults`, `init(defaults:)` injectable. Shaped exactly like `WeightUnitPreference`. |
| Presentation | `Presentation/ViewModels/CalendarSyncSettingsViewModel.swift` | The toggle's state machine: request → create → persist, with the failure vocabulary the section renders. |
| Presentation | `Presentation/Views/Settings/Components/CalendarSyncSettingsSectionView.swift` | The Settings section, composed into `SettingsRootView` after `UnitsSettingsSectionView`. |
| App | `App/AppDependencies.swift` | Wires `calendarSyncPreference` and `workoutCalendarSync` (Hard rule 5). |

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

## 10. Out of scope for this slice

Event writing (ticket 02), drift detection and refresh (03), weekday series (04),
and `EventKitUI` entirely.
