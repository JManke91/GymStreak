# Settings Tab

Dedicated fourth tab ("Einstellungen" / "Settings") that collects app settings in an
iOS-style grouped-inset list. It ships with a **Data** section (live iCloud sync status),
an **AI Coach** section and a **Support** section; every further setting reuses the
section/row blueprint documented here.

**Targets:** iOS only. The watch app has no settings surface and is untouched by this feature.

---

## 1. What the feature does

- Adds a fourth tab with a gear icon after "Verlauf"/"History" (`ContentView`).
- Its root screen (`SettingsRootView`) shows the screen title followed by grouped sections:
  uppercase section header → rounded card holding the rows → optional footnote below the card.
- **Gym Streak Pro** section (first, above Data): states the user's plan — Founder, Pro
  (subscription or lifetime) or Free — and where it came from. **It renders nothing while the
  gating kill switch is off**, which is every build today, so the shipping Settings screen is
  unchanged. Below the status row it offers **Manage subscription**, which opens RevenueCat's
  Customer Center (restore, manage, change plan, cancel, refund) — everyone but a Founder gets it,
  since a Founder has no purchase to manage. There is still no *purchase* affordance here; the
  paywall is reached from a gate, never from Settings. Documented in `docs/pro-subscription.md`
  §5i and §5j; this file does not repeat its rules.
- **Data** section: a single iCloud row that reports at a glance whether the user's data is
  safe — state-tinted icon tile, "Last: \<timestamp\>" subtitle and a status dot (or spinner)
  with a short label. Footnote: "Your training data syncs automatically via iCloud …".
- **AI Coach** section: its row pushes the **existing** `AICoachSettingsView` unchanged.
- **Support** section: "App bewerten" / "Rate app" deep-links to the App Store's
  write-a-review composer, and "Support kontaktieren" / "Contact support" hands a prefilled
  support mail to the user's default mail app (§5).
- **Debug** and **Debug — Store** sections (`#if DEBUG`, never in a shipping build): a picker
  that overrides the reported Pro entitlement, and the RevenueCat Test Store products with Buy
  and Restore actions. Their strings are deliberately unlocalized — developer-facing only.
  Documented in `docs/pro-subscription.md` §6; this file does not repeat their behaviour.
- The gear button that used to sit in the History header was removed together with its
  navigation destination — the AI Coach settings are now reachable from the Settings tab and
  from the coach chat toolbar (`CoachChatView`), not from History.

## 2. Files

| File | Role |
| --- | --- |
| `Presentation/Views/Settings/SettingsRootView.swift` | Tab root: `NavigationStack` + `ScrollView`, screen title, sections, `SettingsDestination` enum and its `navigationDestination` |
| `Presentation/Views/Settings/Components/SettingsSectionView.swift` | Grouped section: header, card, footnote |
| `Presentation/Views/Settings/Components/SettingsRowView.swift` | Shared row shape |
| `Presentation/Views/Settings/Components/SettingsActionRowView.swift` | Tappable row: the row shape wrapped in a plain-styled `Button` |
| `Presentation/Views/Settings/SupportLinks.swift` | App Store Apple ID, the write-a-review URL, the support mail address |
| `Presentation/Views/Settings/LegalLinks.swift` | Terms of Use (Apple's standard EULA) and privacy policy URLs — an App Review requirement, see §5a |
| `Domain/Services/SupportMailComposer.swift` | Builds the support `mailto:` URL from a `DeviceDiagnostics` value |
| `Domain/Interfaces/DeviceDiagnosticsProviding.swift` | `DeviceDiagnostics` + the provider protocol |
| `Data/System/SystemDeviceDiagnosticsProvider.swift` | Reads bundle/OS/hardware metadata (`Bundle`, `ProcessInfo`, `sysctlbyname`) |
| `Presentation/Views/Settings/Components/SubscriptionSettingsSectionView.swift` | Pro plan section: renders the summary, or nothing while gating is off |
| `Presentation/ViewModels/Pro/SubscriptionStatusSummary.swift` | Entitlement → plan + copy keys; the kill-switch visibility rule |
| `Presentation/Views/Pro/CustomerCenterSettingsRow.swift` | The Manage-subscription row and its `CustomerCenterView` presentation |
| `Presentation/Views/Settings/Components/ICloudSyncRowView.swift` | iCloud row: subscribes to the status stream, maps state → icon/tint/label |
| `Domain/Interfaces/CloudSyncStatusProviding.swift` | `CloudSyncState`, `CloudSyncStatus`, the provider protocol |
| `Data/Sync/CloudKitSyncStatusMonitor.swift` | The status source (CloudKit account status + mirroring events + network path) |
| `App/AppDependencies.swift` | Owns the monitor (`cloudSyncStatus: CloudSyncStatusProviding`) and the diagnostics provider (`deviceDiagnostics: any DeviceDiagnosticsProviding`) |
| `GymStreakTests/SupportMailComposerTests.swift` | URL-builder contract: recipient, subject, body layout, percent-encoding |
| `GymStreakTests/SystemDeviceDiagnosticsProviderTests.swift` | Metadata gateway: bundle fields, OS version shape, and the simulator model-identifier trap |
| `App/GymStreakApp.swift` | `Store` struct: container **plus** whether it is CloudKit-backed |
| `App/ContentView.swift` | Tab wiring (`SettingsRootView` + `tab.settings` label) |
| `Presentation/Views/History/Components/HistoryHeaderView.swift` | Gear button removed |
| `Presentation/Views/History/HistoryView.swift` | `AICoachSettingsDestination` + its `navigationDestination` removed |
| `GymStreakUITests/SettingsTabUITests.swift` | Regression tests: AI Coach push, iCloud "off" state, Support row presence, support-mail fallback alert |

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

**Two row wrappers.** `SettingsRowView` is only the shape; what makes it interactive is
decided by its wrapper, and there are exactly two:

- **Navigation row** — `NavigationLink(value: SettingsDestination.…) { SettingsRowView(…) }`
  with `.buttonStyle(.plain)`. Used by the AI Coach row.
- **Action row** — `SettingsActionRowView(…, action:)`, which wraps the same shape in a
  `Button` with `.buttonStyle(.plain)`. It mirrors `SettingsRowView`'s parameters
  (`icon`, `iconTint`, `title`, `subtitle`, `showsChevron`, `isLast`) and defaults
  `showsChevron` to `true`, so an action row is visually indistinguishable from a
  navigation row. It exists so that rows which *do* something rather than push a
  destination don't each re-implement the button and press handling. Used by the Support
  section.

A row that is neither (the iCloud status row) is placed in the card directly, with no
wrapper, no chevron and no tap target.

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

Precedence: `off` → **no network** → `syncing` → queued changes → `upToDate`.

**Why "no network" outranks `syncing`, and not the other way round** (device-measured bug,
2026-08-12). CloudKit opens a mirroring event and then simply *never ends it* while the device
is offline — there is no failure callback, the event just stays in flight for the whole outage.
The original order tested `eventsInFlight` first, so that stalled event masked the offline
state and pinned the row at "Lädt …" until connectivity returned: the log read
`state=waiting hasNetwork=false inFlight=0` for one instant and then
`state=syncing hasNetwork=false inFlight=1` for the rest of the outage. A transfer that cannot
reach the network is queued, not progressing, so `!hasNetwork` is now checked before
`eventsInFlight`. Note this is a genuinely different case from a *failed* export, which is what
`hasQueuedChanges` covers — offline produces no event failure at all.

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
  `NSPersistentCloudKitContainer` instance. **Confirmed on a real device signed into iCloud
  (2026-08-12): the events do arrive for this app's SwiftData container**, and the row tracks
  them. We rely on the notification and accept that it is an undocumented implementation
  detail — see the fallback below, which is now a contingency rather than a live option.
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

**Fallback if the events ever stop arriving** (the risk flagged in ticket 02, now retired —
the events were seen on device, so this is only insurance against a future OS regression):
swap signal 2
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

## 5. Support section

Two action rows: "App bewerten" / "Rate app" (`star.bubble`, §5.1) and "Support kontaktieren" /
"Contact support" (`envelope`, §5.2), both in the app tint. Footnote: "Bewertungen helfen
anderen, Gym Streak zu entdecken." Strings: `settings.section.support*`,
`settings.support.rate.row.*`, `settings.support.contact.*`.

### 5.1 Rate app

**The link.** `https://apps.apple.com/app/id<appStoreAppID>?action=write-review`, opened with
the SwiftUI `@Environment(\.openURL)` action. The Apple ID (`6756426105`, from App Store
Connect → App Information → General) lives in exactly one place,
`SupportLinks.appStoreAppID`, and the composed URL in `SupportLinks.writeReview` — nothing
interpolates the ID at a call site. Because it is a universal link, on device it opens the
App Store app straight on the review sheet instead of bouncing through Safari.

**Why not the in-app rating prompt** (research, 2026-08-14 — decided, do not re-litigate).
The obvious ask is an in-app rating "without leaving the app", and that is not permissible:
`requestReview()` / `SKStoreReviewController.requestReview(in:)` is the only in-app review
prompt, and Apple's documentation states outright that *"Because this method may not present
an alert, don't call `requestReview()` or `requestReview(in:)` in response to a button tap or
other user action."* It is additionally capped at three prompts per 365 days, never fires
again for a user who already rated on that device, and exposes no API to detect whether the
alert appeared — a settings button wired to it would silently do nothing for a large share of
users. Apple's own documented alternative for exactly this case is a persistent settings link
to the App Store product page, which is what this row is. **No `requestReview()` /
`SKStoreReviewController` call exists anywhere in the app**, and none should be added here.

Also deliberately absent: any gating of the row on a rating threshold or a pre-qualifying
"do you like the app?" step. Filtering who gets shown the review link is an App Review
rejection risk and is explicitly discouraged by Apple.

Sources:
[`requestReview()`](https://developer.apple.com/documentation/storekit/requestreviewaction),
[`SKStoreReviewController`](https://developer.apple.com/documentation/storekit/skstorereviewcontroller),
[Human Interface Guidelines — Ratings and reviews](https://developer.apple.com/design/human-interface-guidelines/ratings-and-reviews).

**Verification limit:** the App Store app does not exist on the iOS simulator, so the deep
link itself can only be confirmed on a device. The row's presence, label, icon and tap target
are simulator-verifiable.

### 5.2 Contact support

Tapping the row opens the user's **default** mail app on a new message to
`SupportLinks.supportEmail` (`julian.manke@googlemail.com`) with the subject prefilled and a
short diagnostic block already in the body, so a bug report does not need a follow-up asking
"which iOS version, which device". **Nothing is transmitted by the app** — the user reads the
message and sends it themselves.

**Handoff, not an in-app compose sheet.** The URL is a `mailto:` opened with the SwiftUI
`@Environment(\.openURL)` action. `MFMailComposeViewController` was considered and **rejected**
(2026-08-14, decided — do not re-litigate): it needs a `UIViewControllerRepresentable` wrapper
plus a `nonisolated` delegate with a `@MainActor` hop (extra Swift 6 concurrency surface for no
user-visible gain), needs a `canSendMail()` guard, always uses Apple Mail regardless of which
mail app the user actually set as default, and does not exist on watchOS. The `mailto:` route is
pure SwiftUI, respects Gmail/Outlook/Spark/… as the default client, and stays reusable if a
support row is ever wanted on the watch.

**The URL is built with `URLComponents` + `URLQueryItem`, never string interpolation**
(`SupportMailComposer.mailtoURL(recipient:subject:intro:diagnostics:)`). RFC 6068 requires the
`subject` and `body` values to be percent-encoded and the body contains newlines, so a
hand-built string would corrupt or truncate it. Verified behaviour of Foundation's `queryItems`
setter: it escapes newlines (`%0A`), `&`, `=` and `#` inside values, and leaves `+`, `?` and `/`
raw — nothing in the block contains those, so no extra encoding pass is needed.
`SupportMailComposerTests` pins this by decoding the finished URL back through
`URLComponents(url:)`, which is what a mail client does.

**Body layout** — two blank lines (so the user's cursor starts above the block), the localized
intro line, then one `Label: value` per field. The field labels stay English and untranslated:
they are triage keys, not prose. Only the intro line is localized, which is what makes the
payload transparent before sending.

```
<blank>
<blank>
Sent along to help with troubleshooting:
App: 1.4.0 (128)
iOS: 26.5
Device: iPhone17,1
Locale: de_DE
```

**The four fields and the API each one needs** (`SystemDeviceDiagnosticsProvider`):

| Field | Source | Note |
| --- | --- | --- |
| App version + build | `Bundle.main` `CFBundleShortVersionString` / `CFBundleVersion` | falls back to `unknown`, never an empty line |
| iOS version | `ProcessInfo.processInfo.operatingSystemVersion` | the structured type, preferred over the free-form `UIDevice.current.systemVersion`; patch omitted when `0` |
| Device model | `sysctlbyname("hw.machine")` → `iPhone17,1` | **`UIDevice.current.model` is unusable** — it returns only the generic `"iPhone"`. On the **simulator** `hw.machine` reports the *host Mac's* architecture (`arm64`), so `ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]` is read first — it carries the simulated device's real identifier |
| Locale | `Locale.current.identifier` | e.g. `de_DE` |

**Never auto-include** (privacy exclusion list — this is a hard boundary, not a default):
HealthKit data of any kind, workout/routine/exercise content, the user's name or mail address,
iCloud or Sign-in-with-Apple identifiers, device UDID or serial, location. None of it helps
triage, and shipping health data out of the app outside its stated purpose is an App Review
guideline 5.1.1 risk. `SupportMailComposerTests.bodyCarriesNoUserData` asserts the body is
exactly the intro plus four lines, so an added field fails a test rather than shipping quietly.
Because the payload is user-initiated, user-visible and never leaves the device under app
control, it triggers **no App Store privacy-label disclosure**.

**Fallback when no mail client exists.** `openURL`'s completion reports whether *any* app
accepted the URL — `accepted == true` only means a mail client opened, never that a mail was
sent. On `false` (no mail app configured: the default state on a fresh simulator, and real for
users who deleted Mail) the row raises an alert that names the support address and offers
"Adresse kopieren" / "Copy address" (`UIPasteboard.general.string`), so the row is never a dead
tap. The same alert covers the — practically impossible — case of the composer returning `nil`.

**Verification split:** the simulator ships no mail client, so it is the natural place to prove
the *fallback* (`SettingsTabUITests.testContactSupportRowFallsBackToCopyableAddress`); the
*primary* path needs a device run, done and confirmed on 2026-08-14 (§8).

## 5a. Legal section

Two action rows below Support: "Nutzungsbedingungen (EULA)" / "Terms of Use (EULA)" (`doc.text`)
and "Datenschutzerklärung" / "Privacy Policy" (`hand.raised`), both opening a URL with
`@Environment(\.openURL)` through `SettingsRootView.open(_:)`. Strings: `settings.section.legal*`,
`settings.legal.terms.row.*`, `settings.legal.privacy.row.*`. URLs: `LegalLinks`.

**This section is a submission requirement, not a design choice.** App Store guideline 3.1.2(c)
requires an app offering auto-renewing subscriptions to carry a functional link to both documents
*inside the app*. Version 1.1.9 shipped with neither and was rejected for it on 2026-08-18. The full
reasoning — including why the same two links also live in the RevenueCat paywall footer, and why the
Terms of Use is Apple's standard EULA rather than a custom document — is in
`docs/pro-subscription.md` §5k.

**Shown to everyone**, unconditionally: unlike `SubscriptionSettingsSectionView` it is not gated on
the entitlement or on the kill switch, because a build with gating off still ships the products.

## 6. Adding another setting

1. Add the strings to `en.lproj`/`de.lproj` (`settings.*`).
2. Add a `SettingsSectionView { … }`, or another row inside an existing section, and set
   `isLast: true` on the final row of each card.
3. Pick the wrapper (§3): a row that **pushes a screen** additionally needs a `case` on
   `SettingsDestination` in `SettingsRootView.swift`, handled in the `navigationDestination`
   switch, and is wrapped in a `NavigationLink(value:)` + `.buttonStyle(.plain)`. A row that
   **runs code** uses `SettingsActionRowView(…, action:)` instead and needs no destination
   case.

Nothing else in the root screen has to change — layout, background and scroll behaviour are
section-agnostic.

## 7. Behaviour notes

- The root deliberately uses `.toolbar(.hidden, for: .navigationBar)`: pushed destinations
  (like `AICoachSettingsView`) keep their own navigation chrome and back button.
- Navigation is value-based (`NavigationLink(value:)` + `navigationDestination(for:)`),
  matching the other tabs.
- The floating coach bar (`tabViewBottomAccessory`) and `tabBarMinimizeBehavior(.onScrollDown)`
  are applied to the `TabView` in `ContentView`, so they apply to this tab automatically;
  verified on the simulator (coach bar visible over the settings root).
- A trailing `Color.clear.frame(height: 100)` keeps the last section clear of the floating
  tab bar and coach accessory.

## 8. Verification record

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

**Support section (2026-08-14):**

- `xcodebuild … -scheme GymStreak -destination 'iPhone 17' build` → succeeded.
- Both pre-existing `SettingsTabUITests` cases re-run after the section was added → passed,
  so the new section did not disturb the existing rows.
- `SettingsTabUITests.testSupportSectionShowsRateAppRow` → passed: the row exists, is
  hittable and carries the localized title.
- ⏳ **Open, device-only:** tapping "App bewerten" landing on the App Store review composer.
  The App Store app is absent from the simulator, so `openURL` has nothing to hand the
  universal link to there.
- Architecture review (`architecture-reviewer` on the diff): **PASS**, no critical or warning
  findings — the change stays inside `Presentation/`, crosses no layer and touches no
  isolation or rendering rule.

**Contact support row (2026-08-14):**

- `xcodebuild … -scheme GymStreak -destination 'iPhone 17' build` → succeeded.
- `SupportMailComposerTests` (5 tests) → passed: recipient, subject, the exact body layout,
  `%0A`-encoded newlines that survive decoding, an `&` in subject/intro that does not terminate
  the value, and the "no extra field" privacy assertion.
- `SystemDeviceDiagnosticsProviderTests` (4 tests) → passed in the app host: the bundle fields
  are real, the OS version's major component matches `ProcessInfo`, and `deviceModel` resolves
  to the *simulated* device rather than `arm64` — the automated guard for the `hw.machine` trap.
- Full iOS unit suite (`-scheme GymStreakTests`) → passed, so the new `AppDependencies` member
  disturbed nothing. The watch suite was not run: no watch code is touched.
- All four `SettingsTabUITests` → passed, including the new
  `testContactSupportRowFallsBackToCopyableAddress`: on the simulator no app accepts the
  `mailto:` URL, the alert appears carrying `julian.manke@googlemail.com`, and its copy button
  is hittable.
- ✅ **Device run (2026-08-14) — the part the simulator cannot cover:** tapping the row opens the
  default mail app on the prefilled message, and the four diagnostic values are correct for real
  hardware (`hw.machine` returns the real model identifier; the simulator's environment-variable
  branch is not taken there).
- Architecture review (`architecture-reviewer` on the diff): **PASS WITH WARNINGS**, no critical
  findings. Confirmed clean: dependency direction (`Sendable` value type + gateway protocol in
  `Domain/Interfaces/`, a Foundation-only pure builder in `Domain/Services/`, the system reads
  isolated in `Data/System/`, the concrete type wired once in `AppDependencies` with Presentation
  seeing only `any DeviceDiagnosticsProviding`), concurrency surface, rendering rules
  (`deviceDiagnostics.current` runs in the tap handler, never in `body`) and EN/DE parity.
  **The one warning, acknowledged and deliberately not acted on:** `contactSupport()` in
  `SettingsRootView` performs ViewModel-shaped orchestration (read provider → call the Domain
  builder → drive the fallback state). It is tolerable because the computation is fully delegated
  to a pure Domain service, no service is constructed in the view, and the settings root is a
  deliberately stateless screen (§4.4). **Trigger for revisiting:** when a third support action
  lands, extract an `@Observable @MainActor SettingsSupportViewModel` (`makeSupportMailURL()` +
  `isShowingMailFallback`) rather than adding a fourth branch to the view.

**Device run (2026-08-12), iPhone signed into iCloud — the part the simulator cannot cover:**

- ✅ The SwiftData-created container **does** emit `eventChangedNotification`; the row reports
  the real sync status, and the `syncing` → `upToDate` transition is observable. The
  `.NSPersistentStoreRemoteChange` fallback in §4.3 is therefore not needed, and ticket 03 may
  build its "Letzte Aktivität" upload/download split on the event stream.
- ✅ **`waiting` verified on device, after the run that exposed the precedence bug** (§4.2).
  Before the fix, the offline log went `path status=unsatisfied …` → `state=waiting
  hasNetwork=false`, then an import event opened and never ended, flipping the row to a
  permanent "Lädt …". Restoring the network produced `requiresConnection` → `satisfied`
  (cellular first, then Wi-Fi), the pending import ended `succeeded=true`, and the row returned
  to `upToDate` **without a relaunch**. After the fix, the offline state holds for the whole
  outage: amber tile with the slashed-cloud glyph, amber dot, "Wartet", and the subtitle still
  showing the last *real* sync ("Zuletzt: Heute, 15:30") rather than blanking — confirmed by
  screenshot. **All four states are now confirmed on real hardware.**

  **How to test it — "Airplane Mode" alone does not work** (it cost three runs before this was
  understood). Airplane Mode drops *cellular only*: `interfaces` goes from
  `["wifi", "wifi", "cellular"]` to `["wifi", "wifi"]`, `path status` stays `satisfied`, and
  exports keep succeeding, because iOS keeps Wi-Fi connected inside Airplane Mode once it has
  been re-enabled there. Turn Wi-Fi off in *Settings → Wi-Fi* (not Control Centre, which only
  disconnects until the next day) **and** Airplane Mode on; `interfaces=[]` with
  `status=unsatisfied` is what proves the device is genuinely offline. Note the trap: **if
  Xcode is attached over Wi-Fi, disabling Wi-Fi kills the console you are reading it in** —
  connect the device by cable first, or skip the console and just read the row in the UI.

**DEBUG instrumentation** (kept, it is what made the above diagnosable): `publish()` logs the
complete input vector — `☁️ [CloudKitSyncStatusMonitor] state= hasNetwork= inFlight= queued=
account=` — and the `NWPathMonitor` handler logs `path status= satisfied= expensive=
constrained= interfaces=`. Because `.waiting` has exactly two entry conditions
(`!hasNetwork`, `hasQueuedChanges`), those two lines are enough to attribute any wrong state
to its signal. Note that `hasQueuedChanges` is only ever set by a **failed `.export`** event;
a failed `.setup` or `.import` leaves it false by design.

**Dead end worth remembering:** synthetic `osascript` clicks in the *upper* area of the
simulator window did not register on this screen (they do register mid-screen and on the tab
bar), which first looked like a broken `NavigationLink`. It is a driver limitation, not an app
bug — confirm interactions of this kind with an XCUITest instead of synthetic clicks.

## 9. Known follow-ups (found, deliberately not applied)

Carried over from the implementation tickets so they are not lost with them. None is a defect;
each is a threshold to act on rather than work to schedule now.

- **`SupportLinks` lives under `Presentation/Views/Settings/`** although it holds constants, not
  a view. Flagged twice by the architecture reviewer (tickets 01 and 02) as advisory only — it
  is presentation config for this feature area. Move it out of `Views/` if that folder's
  view-only shape starts to matter.
- **`SettingsActionRowView`'s parameter list is a hand-maintained mirror of `SettingsRowView`'s**
  and will drift if the latter gains a parameter. Acceptable at two mirrored rows; revisit if
  `SettingsRowView` grows.
- **`contactSupport()` in `SettingsRootView` does ViewModel-shaped orchestration.** Acknowledged
  in §8; extract an `@Observable @MainActor SettingsSupportViewModel` when a third support
  action lands.
- **The "App bewerten" deep link was never confirmed on a device** — only the row itself. The
  App Store app is absent from the simulator, and the feature was closed out (2026-08-14) with
  this gap known.

## 10. Deliberate omissions

- The design reference's **iCloud detail screen** (`ICloudDetail`: status hero, "Letzte
  Aktivität" upload/download rows, account row, "Jetzt synchronisieren") is **not** implemented
  and **not planned** — dropped as a product decision on 2026-08-14 (its ticket 03 was closed
  as won't-implement). The status the root row already shows was judged sufficient; a whole
  screen behind it would mostly restate it. The row on the root therefore deliberately carries
  **no chevron and no tap target**; the design shows both only because it pushes that screen.
  To restore it, the sync-status source in `Data/` already exposes everything the hero and the
  upload/download rows would need (state, last successful export date, last successful import
  date, account status) — the work is the screen itself plus a `SettingsDestination` case.
  Three parts of the design are **not** restorable and should not be attempted:
  - a **device list** — CloudKit exposes no such API;
  - the **iCloud account email** — user identity discovery was removed in iOS 17, so the
    account row can only report signed in / not signed in / restricted;
  - a **"Jetzt synchronisieren" button** — `NSPersistentCloudKitContainer` offers no public
    manual sync trigger, and a button that only appears to act is worse than none.
- The row does not show *what* is syncing (the design's "2 neue Trainings werden übertragen"):
  `NSPersistentCloudKitContainer.Event` carries no item count.
- The AI Coach row shows a static subtitle; it does not reflect whether the coach is currently
  enabled.
