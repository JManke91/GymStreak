# Settings Tab

Dedicated fourth tab ("Einstellungen" / "Settings") that collects app settings in an
iOS-style grouped-inset list. It ships with a **Data** section (live iCloud sync status)
and an **AI Coach** section; every further setting reuses the section/row blueprint
documented here.

**Targets:** iOS only. The watch app has no settings surface and is untouched by this feature.

---

## 1. What the feature does

- Adds a fourth tab with a gear icon after "Verlauf"/"History" (`ContentView`).
- Its root screen (`SettingsRootView`) shows the screen title followed by grouped sections:
  uppercase section header → rounded card holding the rows → optional footnote below the card.
- **Data** section: a single iCloud row that reports at a glance whether the user's data is
  safe — state-tinted icon tile, "Last: \<timestamp\>" subtitle and a status dot (or spinner)
  with a short label. Footnote: "Your training data syncs automatically via iCloud …".
- **AI Coach** section: its row pushes the **existing** `AICoachSettingsView` unchanged.
- The gear button that used to sit in the History header was removed together with its
  navigation destination — the AI Coach settings are now reachable from the Settings tab and
  from the coach chat toolbar (`CoachChatView`), not from History.

## 2. Files

| File | Role |
| --- | --- |
| `Presentation/Views/Settings/SettingsRootView.swift` | Tab root: `NavigationStack` + `ScrollView`, screen title, sections, `SettingsDestination` enum and its `navigationDestination` |
| `Presentation/Views/Settings/Components/SettingsSectionView.swift` | Grouped section: header, card, footnote |
| `Presentation/Views/Settings/Components/SettingsRowView.swift` | Shared row shape |
| `Presentation/Views/Settings/Components/ICloudSyncRowView.swift` | iCloud row: subscribes to the status stream, maps state → icon/tint/label |
| `Domain/Interfaces/CloudSyncStatusProviding.swift` | `CloudSyncState`, `CloudSyncStatus`, the provider protocol |
| `Data/Sync/CloudKitSyncStatusMonitor.swift` | The status source (CloudKit account status + mirroring events + network path) |
| `App/AppDependencies.swift` | Owns the monitor, exposes it as `cloudSyncStatus: CloudSyncStatusProviding` |
| `App/GymStreakApp.swift` | `Store` struct: container **plus** whether it is CloudKit-backed |
| `App/ContentView.swift` | Tab wiring (`SettingsRootView` + `tab.settings` label) |
| `Presentation/Views/History/Components/HistoryHeaderView.swift` | Gear button removed |
| `Presentation/Views/History/HistoryView.swift` | `AICoachSettingsDestination` + its `navigationDestination` removed |
| `GymStreakUITests/SettingsTabUITests.swift` | Regression test: tab → row → AI Coach settings pushes |

Architecture: the screen itself is stateless `Presentation/` work (`AICoachSettingsView` owns
its own state). The only dependency is the sync-status source, which lives in `Data/` behind
the `CloudSyncStatusProviding` Domain protocol and is wired in `AppDependencies` — no
CloudKit, Core Data or Network type appears in `Presentation/`.

## 3. The row/section blueprint

Derived from the Claude Design reference (project `0d4ac3f4-2c40-43cc-b80e-84bd411c334a`,
`gs-einstellungen.jsx` → `SSection` / `SRow`; screen 01 of `Einstellungen Redesign.html`).

**`SettingsSectionView(header:footer:content:)`**
- Header: 11 pt semibold, uppercased, tracking 0.7, white 40 %, 6 pt leading inset.
- Card: `VStack(spacing: 0)`, white 3.5 % fill, white 6 % 1 pt border, 20 pt continuous radius.
- Footer: 11.5 pt, white 40 %, 8 pt horizontal inset, 9 pt below the card.
- Outer: 16 pt horizontal padding, 22 pt bottom padding. Header and footer are optional.

**`SettingsRowView`** — one shape for every setting:
- optional tinted icon tile (34×34, 10 pt radius, tint at 16 % fill / 28 % border),
- title (15.5 pt semibold) with optional subtitle (12 pt, white 45 %),
- optional right-hand `value` string (14 pt, monospaced digits) and/or a generic `trailing`
  view (toggle, status element),
- optional chevron,
- hairline separator at the bottom unless `isLast`, inset to 60 pt when an icon tile is
  present (16 pt otherwise) so it lines up with the text column.

Two initializers: the generic one takes `@ViewBuilder trailing:`, and a convenience overload
(`Trailing == EmptyView`) covers rows without a trailing element. Both carry defaults for
every optional parameter — without explicit defaults the memberwise init would force all
call sites to pass every argument.

Decorative overlays (the card border, the row separator) are marked
`.allowsHitTesting(false)` so they never compete with the row's tap target.

## 4. iCloud sync status

### 4.1 The four states

| State | Colour (design `toneColor`) | Icon | Label EN/DE | Subtitle |
| --- | --- | --- | --- | --- |
| `.upToDate` | accent green (`DesignSystem.Colors.tint`) | `checkmark.icloud` | Up to date / Aktuell | `Last: <timestamp>` |
| `.syncing` | blue `#5AB4FF` | `icloud` + spinner instead of the dot | Syncing… / Lädt … | `Last: <timestamp>` |
| `.waiting` | amber `#FFC53D` | `icloud.slash` | Waiting / Wartet | `Last: <timestamp>` |
| `.off` | red `#FF6B6B` | `exclamationmark.triangle` | Off / Aus | Not synced / Nicht synchronisiert |

The timestamp uses a `static let DateFormatter` with `doesRelativeDateFormatting = true`
(→ "Today at 14:32" / "Heute, 14:32"), hoisted out of `body` per the main-thread rules.

### 4.2 How the status is derived

`CloudKitSyncStatusMonitor` (Data layer, `@MainActor`) combines three signals and pushes the
result through `AsyncStream`; there is no polling and no timer anywhere in the feature:

1. **Account status** — `CKContainer(identifier:).accountStatus()`, re-queried whenever
   `.CKAccountChanged` fires (CloudKit does not put the new status in the notification's
   `userInfo`, so a re-query is mandatory). Anything other than `.available` ⇒ `.off`.
2. **Mirroring events** — `NSPersistentCloudKitContainer.eventChangedNotification`, read via
   `NSPersistentCloudKitContainer.eventNotificationUserInfoKey`. An event whose `endDate` is
   `nil` has started but not finished ⇒ `.syncing` (tracked as a `Set<UUID>` of
   `event.identifier`, so overlapping import/export events don't cancel each other out). A
   finished event carries `succeeded` and `error`:
   - succeeded `.export`/`.import` → its `endDate` becomes the persisted last-success stamp,
     and a successful export clears the "queued" flag;
   - a failed `.export` → sets the "queued changes" flag ⇒ `.waiting`;
   - additionally, a failure carrying a `CKError` of `.notAuthenticated`,
     `.managedAccountRestricted` or `.permissionFailure` triggers a fresh
     `accountStatus()` query, which may then move the row to `.off`. The query is
     deliberate: writing a synthetic "signed out" straight into the state would pin the
     row to `.off` for the rest of the session after a transient permission failure,
     because nothing but `.CKAccountChanged` or a relaunch would ever clear it.
3. **Network path** — `NWPathMonitor`. `path.status != .satisfied` ⇒ `.waiting` on its own,
   because a user who pulls the network expects the row to say so even when nothing happens
   to be queued. When the path comes back, the state recomputes immediately, and CloudKit's
   own retry produces a fresh successful export event ⇒ back to `.upToDate` without a restart.

Precedence: `off` → `syncing` → `waiting` → `upToDate`.

**The local-only fallback counts as `.off`.** `GymStreakApp` silently falls back to a
`cloudKitDatabase: .none` store when the CloudKit container cannot be built (and UI-test runs
use an ephemeral store). That fact used to be invisible, so the app's store construction now
returns a `GymStreakApp.Store` (container **plus** `isCloudKitEnabled`), which
`AppDependencies` forwards to the monitor. With it `false`, the monitor reports `.off`
permanently and registers no observers at all — otherwise the row would show a stale
"up to date" for a store that never syncs.

**Cold launch.** The last successful export and import dates are persisted in `UserDefaults`
(`cloudSync.lastSuccessfulExport` / `…Import`; the row shows the newer of the two), so the
subtitle is correct on the first frame after launch instead of blank until the session's first
event happens to arrive. The account status is unknown for the first few milliseconds and is
deliberately treated as *available* during that window — the alternative flashes a red "Off"
row on every launch.

### 4.3 API findings (research, 2026-08-12)

- **There is no first-class SwiftData sync-status API**, in iOS 26 or earlier. WWDC25's
  SwiftData session covers inheritance/migration and *persistent history* fetches — unrelated
  to CloudKit transfer status. Going through the Core Data layer underneath is the only option.
- **`eventChangedNotification` for a SwiftData-created container**: the events *are* observed
  in practice on current iOS (multiple independent 2025/26 write-ups with working code, e.g.
  [AzamSharp, "SwiftData iCloud Sync Status"](https://azamsharp.com/2026/03/16/swiftdata-icloud-sync-status.html),
  [crunchybagel](https://crunchybagel.com/nspersistentcloudkitcontainer/)), but Apple never
  documents it for SwiftData: a DTS reply in
  [forum thread 756775](https://developer.apple.com/forums/thread/756775) points at
  `.NSPersistentStoreRemoteChange` instead, because SwiftData does not hand out its
  `NSPersistentCloudKitContainer` instance. We rely on the notification and accept that it is
  an implementation detail — see the fallback below.
- **Observation must stay closure-based.** `Notification` and
  `NSPersistentCloudKitContainer.Event` are not `Sendable`; the `notifications(named:)` async
  sequence would carry a non-`Sendable` `Notification` across an `await`. `addObserver(forName:
  object:queue: .main)` plus `MainActor.assumeIsolated` keeps everything on the main thread
  and in event order. `object:` must be `nil` — there is no container instance to filter on;
  with multiple stores you would filter on `event.storeIdentifier` instead.
- **`CKAccountStatus`** has five cases (`.available`, `.noAccount`, `.restricted`,
  `.couldNotDetermine`, `.temporarilyUnavailable`); only `.available` is treated as on.
- **Distinguishing "waiting" from "up to date" has no single Apple signal.** The composite
  used here (event error inspection + `NWPathMonitor`) is the community-standard approach.
- Sources: [`NSPersistentCloudKitContainer.eventChangedNotification`](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/eventchangednotification),
  [`Event`](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/event),
  [`CKAccountStatus`](https://developer.apple.com/documentation/cloudkit/ckaccountstatus),
  [`ModelConfiguration.CloudKitDatabase`](https://developer.apple.com/documentation/swiftdata/modelconfiguration/cloudkitdatabase-swift.struct).

**Fallback if the events ever stop arriving** (the risk flagged in ticket 02): swap signal 2
for `.NSPersistentStoreRemoteChange` — the notification DTS endorses, already observed by
`CloudSyncObserver` — and keep signals 1 and 3. That still supports all four states
(`.syncing` = a debounce window after a remote change), but loses the `succeeded`/`error`
granularity and therefore the clean upload/download split that ticket 03's "Letzte Aktivität"
section wants. The DEBUG `print` in `CloudKitSyncStatusMonitor.handle(event:)` (prefix
`☁️ [CloudKitSyncStatusMonitor]`) is what proves which world we are in — it logs every event
with its type, end state and error.

### 4.4 Discarded approaches

- **A ViewModel for the row.** The row needs one value and no commands; a `@State` +
  `.task { for await … }` pair inside `ICloudSyncRowView` keeps the subscription scoped to the
  row, so a status change never re-renders the settings root. A ViewModel would have added a
  layer without adding behaviour.
- **Making the monitor `@Observable` and observing it from the view.** `@Observable` does not
  propagate through an existential protocol, and Presentation may only see the protocol — the
  `AsyncStream` is what makes push-based updates possible across that boundary.
- **Deriving the status from `CloudSyncObserver`** (the existing `.NSPersistentStoreRemoteChange`
  listener). It only proves "something changed", never "everything is uploaded", so
  `.upToDate` vs `.waiting` would have been guesswork. Kept as the documented fallback only.
- **Exposing separate export/import timestamps in `CloudSyncStatus`.** Both are persisted, but
  the Domain type carries only the aggregate `lastSuccessfulSync` this ticket needs; ticket 03
  widens it when it actually shows the two rows.

## 5. Adding another setting

1. Add the strings to `en.lproj`/`de.lproj` (`settings.*`).
2. Add a `case` to `SettingsDestination` in `SettingsRootView.swift` and handle it in the
   `navigationDestination` switch.
3. Add a `SettingsSectionView { … }` (or another `SettingsRowView` inside an existing
   section) with a `NavigationLink(value:)` wrapping the row and `.buttonStyle(.plain)`.
   Set `isLast: true` on the final row of each card.

Nothing else in the root screen has to change — layout, background and scroll behaviour are
section-agnostic.

## 6. Behaviour notes

- The root deliberately uses `.toolbar(.hidden, for: .navigationBar)`: pushed destinations
  (like `AICoachSettingsView`) keep their own navigation chrome and back button.
- Navigation is value-based (`NavigationLink(value:)` + `navigationDestination(for:)`),
  matching the other tabs.
- The floating coach bar (`tabViewBottomAccessory`) and `tabBarMinimizeBehavior(.onScrollDown)`
  are applied to the `TabView` in `ContentView`, so they apply to this tab automatically;
  verified on the simulator (coach bar visible over the settings root).
- A trailing `Color.clear.frame(height: 100)` keeps the last section clear of the floating
  tab bar and coach accessory.

## 7. Verification record

- `xcodebuild … -scheme GymStreak build` → succeeded.
- `SettingsTabUITests.testSettingsRowPushesAICoachSettings` → passed (tab appears, row pushes
  `AICoachSettingsView`).
- `SettingsTabUITests.testICloudRowReportsOffWithoutICloudAccount` → passed: on a simulator
  without an iCloud account the row reads "Aus" / "Nicht synchronisiert" instead of a stale
  "Aktuell". This is also the automated regression for the local-only-store case.
- Simulator walkthrough (iPhone 17, iOS 26.5): tab renders as designed, History header looks
  right without its gear, coach bar visible on the settings tab. Screenshot of the Data
  section in the `off` state confirms the design (red tile with warning triangle, red dot,
  "Aus", footnote below the card).

**Still open — needs a device (cannot be done from the simulator):** confirming that the
SwiftData-created container really emits `eventChangedNotification`, and with it the
`syncing` / `waiting` / `upToDate` states. Run a Debug build on a device signed into iCloud,
watch the console for `☁️ [CloudKitSyncStatusMonitor]` lines while saving a workout, then
toggle Airplane Mode (row must go amber "Wartet") and back (row must return to green
"Aktuell" without relaunching). If no such line ever appears, take the
`.NSPersistentStoreRemoteChange` fallback in §4.3 — and tell ticket 03 before it builds the
"Letzte Aktivität" section on the upload/download split.

**Dead end worth remembering:** synthetic `osascript` clicks in the *upper* area of the
simulator window did not register on this screen (they do register mid-screen and on the tab
bar), which first looked like a broken `NavigationLink`. It is a driver limitation, not an app
bug — confirm interactions of this kind with an XCUITest instead of synthetic clicks.

## 8. Deliberate omissions

- The design reference's **iCloud detail screen** (`ICloudDetail`: status hero, "Letzte
  Aktivität" upload/download rows, account row, "Jetzt synchronisieren") is **not** implemented
  — it belongs to ticket 03. The row on the root therefore carries **no chevron and no tap
  target** yet; the design shows both because it pushes that screen.
- The row does not show *what* is syncing (the design's "2 neue Trainings werden übertragen"):
  `NSPersistentCloudKitContainer.Event` carries no item count.
- The AI Coach row shows a static subtitle; it does not reflect whether the coach is currently
  enabled.
