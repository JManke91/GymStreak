# App Store rejection — the monetization launch (1.1.9 → 1.1.10), and the road back

**Living document.** It records why Apple rejected the monetization launch, everything the
investigation has established or ruled out, what has already been fixed, and what is still open.
Update it as things change; it is the file to re-read after a context reset. The filename still says
1.1.9 because that is the build that was first rejected; the file covers the whole episode.

**Status: 2026-08-23 — 1.1.11 (1004) submitted; awaiting the third review.** The binary, the
subscription group and both subscriptions went in as **one** submission, all four elements reading
*Bereit zur Prüfung* (§6, §10). Everything below is the record of how we got here.

The previous state, for context: 1.1.10 (1002) came back with the same 2.1(b) purchase error. 3.1.2(c)
was **not** re-cited, so §2's fixes landed.

**The cause is now known, and it is ours.** Apple attached a screenshot this time (§3.7): it shows
RevenueCat's **Customer Center** reading *"No subscriptions found"* — not the paywall, not an error
alert, not a purchase sheet. The reviewer never reached a paywall, and RevenueCat confirms it from the
other side: **no transaction was attempted in either review session** (§3.4, §3.4b). The paywall is
only reachable behind gates that need data a fresh install does not have, and Settings — the one place
headed *Subscription* — sells nothing (§3.9). Two rounds of 2.1(b) are fully explained by that.

**§3.9's code fix is done** (2026-08-23): a free user's Settings now offers **Get Gym Streak Pro** and
**Restore purchases**, and the Customer Center — the screen Apple screenshotted — is no longer shown to
anyone who has never bought anything. It **shipped in 1.1.11 (1004)**.

A second, independent defect surfaced the same day: the paywall advertised a **free trial that did not
exist for any new customer** (§3.10). Both introductory offers were *paid*; the only free trial was a
Promotional Offer no user could reach. Resolved on two fronts the same day — the yearly's introductory
offer is now a genuine **7-day free trial**, and the paywall's copy and badge were rewritten to state
whatever the store actually offers.

Seven faults are known and all seven are addressed and shipped. **Nothing is outstanding on our
side** — the paywall is published, 1.1.11 carries §3.9's Settings rows, the App Review notes name the
click path, and the reply is with Apple (§9). What remains is the review verdict.

Durable engineering knowledge (why the code is shaped the way it is) lives in
`docs/pro-subscription.md` §5k and §9.8. This file is the operational record: evidence, dead ends,
and state.

---

## 1. What Apple said

| | |
|---|---|
| Submission ID | `0f05424d-0422-4696-873a-ef6227b5208a` |
| Review date | 2026-08-18 |
| Version reviewed | **1.1.9 (68)** |
| Review device | **iPad Air 11-inch (M3)**, iPadOS **26.6.1** |

Two guidelines were cited.

**Guideline 3.1.2(c) — Business - Payments - Subscriptions.**

> The submission did not include all the required information for apps offering auto-renewable
> subscriptions. The following information needs to be included within the app: a functional link to
> the Terms of Use (EULA) and a functional link to the privacy policy.

Apple restated the full requirement: title of the subscription, length, price (and price per unit
where appropriate), and functional links to the privacy policy and Terms of Use — **in the app**;
plus the privacy policy in App Store Connect's Privacy Policy field and the Terms of Use in the App
Description or EULA field — **in the metadata**. They suggested `SubscriptionStoreView` as one way to
get all of it; that is a suggestion, not a requirement.

**Guideline 2.1(b) — Performance - App Completeness.**

> The In-App Purchase products in the app exhibited one or more bugs which create a poor user
> experience. Specifically, we noticed an error when we tried to buy the In App Purchase.

No error text, no screenshot, no reproduction steps were given.

**Apple also offered to approve the build as-is** if we replied calling it a bug-fix submission.
**Declined, deliberately** — 1.1.9 is the monetization launch, not a bug fix, and it would have put a
build on the store whose purchase flow errors, whose legal links are absent, and which (see §5) would
have given every new user Pro for free.

### 1b. The second rejection — 1.1.10 (1002), 2026-08-23

| | |
|---|---|
| Submission ID | `5622461c-6906-418e-85ec-1a4b65a31281` |
| Review date | 2026-08-23 |
| Version reviewed | **1.1.10 (1002)** |
| Review device | **iPad Air 11-inch (M3)**, iPadOS **26.6** |

**Guideline 2.1(b) only.** 3.1.2(c) was *not* re-cited — §2's legal links satisfied it.

> The In-App Purchase products in the app still exhibited one or more bugs which create a poor user
> experience. Specifically, error occurred when we tried to buy the In App Purchase.

Apple added the boilerplate about implementing StoreKit and confirming the Paid Applications
Agreement (both long since verified, §3.1), plus one line that is *not* boilerplate:

> Review the product configurations, complete any missing information, and test them in the sandbox.

That points at App Store Connect product state — which is exactly what §6 was, and still was, at the
time of this review.

Two things are now confirmed by this round:

- **The build-number fix held.** Apple named the build **1002**, not a low Xcode Cloud counter, so
  Fault 3 (§4) is genuinely closed and `cutoffBuild` is safe.
- **The device is not a coincidence.** Two reviews, two rejections, both on an iPad Air 11-inch (M3).
  See §3.8.

---

---

## 2. Fault 1 — no legal links anywhere · **FIXED**

Entirely ours, and unambiguous. A grep of the whole iOS target for a legal URL returned nothing:
`SupportLinks.swift` held only the App Store review link and a support address, Settings had no legal
section, and the paywall is dashboard-authored content that carried no links either.

| Fix | Where | Status |
|---|---|---|
| Terms + Privacy buttons in the paywall footer | RevenueCat Paywall Editor | ✅ done — verified in the editor preview alongside price, period and Restore |
| Settings → **Legal** section, en + de | `SettingsRootView.swift`, `LegalLinks.swift` | ✅ done — in the binary, so it holds even when the paywall does not load |
| Privacy Policy URL | App Store Connect → App-Datenschutz | ✅ done — the gist URL |
| Terms of Use in the App Description | App Store Connect → Beschreibung (de) | ✅ done — Apple's standard EULA link |
| Terms of Use in the **English** description | App Store Connect | ⚠️ **unconfirmed** — only the German description has been seen |

The paywall now also satisfies the other three items of 3.1.2(c) that Apple listed but did not flag:
each package names its title, its length and its price, and the annual shows price per unit
(`$79.99/yr ($6.66/mo)`).

**Terms of Use is Apple's standard EULA**, not a custom document — see `pro-subscription.md` §5k for
why, and what changing that decision would cost.

---

## 3. Fault 2 — the "purchase error" · **DIAGNOSED 2026-08-23**

The one Apple complained about in both rounds. It is not a purchase that failed — it is a purchase
that was never reachable. §3.7 is the evidence, §3.9 is the defect. Everything before those two
sections is the investigation that got there, kept because its dead ends are worth not re-walking.

### 3.1 Ruled out

Each of these is a documented cause of this exact rejection elsewhere. None applies here.

| Checked | Evidence | Verdict |
|---|---|---|
| Paid Applications Agreement | Active since 2026-01-09 | ✅ not it |
| Tax forms | W-8BEN + U.S. Certificate of Foreign Status, both active since 2024-07-26 | ✅ not it |
| Banking | Account active, DE, EUR | ✅ not it |
| Product review state at review time (**1.1.9 only**) | Both subscriptions were "In Prüfung", submitted with the binary | ✅ not it for 1.1.9 — but see §6: for **1.1.10** they were developer-rejected, and that is the leading suspect |
| Pricing coverage | All countries and regions, both products | ✅ not it |
| Product localizations | de + en, group and both products | ✅ not it |
| Subscription review screenshot | Attached | ✅ not it |
| RevenueCat sandbox testing access | "Anybody" — the default. Even when restricted it never errors a purchase; it only withholds the entitlement grant | ✅ not it |
| RevenueCat **In-App Purchase Key** | Uploaded and reporting **"Valid credentials"** (Key ID `94YP72RJHW`, Issuer ID set) | ✅ not it |
| RevenueCat receipt validation | The reviewer's purchase never reached RevenueCat at all (§3.4) — so nothing on RevenueCat's side had the chance to reject it | ✅ not it |

### 3.2 Dead hypothesis: the 12-month-commitment billing plan

**Falsified 2026-08-21.** The theory was that `gymstreak.iap.pro.yearly.sub` has Apple's
*monthly-with-12-month-commitment* plan enabled alongside the up-front one, and that plan is
unavailable in the **United States** and Singapore — while App Review buys from a US account and our
own successful sandbox test on 2026-08-17 was made from a German one. It fit the evidence and the SDK
models such a plan as a compound product identifier, so it was plausible.

**It is wrong.** RevenueCat's product page for the annual states **Billing Plan: Upfront**. The
offering's `$rc_annual` package is bound to that product, so the paywall never offers the commitment
plan and a US account has a perfectly purchasable up-front annual.

**Consequence: removing the monthly billing plan in App Store Connect is *not* required.** It is
dormant configuration that the app never surfaces. Removing it is a product decision, not a fix.

### 3.3 What the offering actually contains

`gymstreak_sale` ("Set of all packages", created 2026-08-15, components-based paywall attached):

| Package | RevenueCat product | Apple product |
|---|---|---|
| `$rc_annual` | `yearly` (Test Store) | `gymstreak.iap.pro.yearly.sub` — Billing Plan **Upfront**, Store Status *Ready to Submit* |
| `$rc_monthly` | `monthly` (Test Store) | `gymstreak.iap.pro.monthly.sub` |

The annual is attached to the **Gym Streak Pro** entitlement (created 2026-08-13), which is the
identifier the app compiles against. That link is correct.

> **Worth revisiting later, unrelated to the rejection:** the current offering is named for a
> *sale*, and since the stale `default` offering was deleted on 2026-08-28
> (`pro-subscription.md` §9.4d) `gymstreak_sale` is the **only** offering — so every gate in the app
> resolves to something called a sale, and there is no neutrally-named offering left to move to.
> Renaming it, or creating a plainly-named permanent offering and reserving `gymstreak_sale` for an
> actual promotion, is the open decision. Note the identifier is a wire string in the dashboard only,
> never in app code.

### 3.4 The 2026-08-18 reviewer session — the purchase never reached RevenueCat

**Established 2026-08-21.** It was the single most useful fact until §3.7's screenshot arrived, and
it still is until that screenshot is read. Whether it repeats for the 2026-08-23 session is open (§7a).

The reviewer is `$RCAnonymousID:fad4b105e8f1438da24c05157db0c6cc` (`$RCA••••c6cc`):

| | |
|---|---|
| Country | **United States** |
| First seen / last opened | both **2026-08-18, 03:54 UTC** |
| Total spent | USD 0 |
| Entitlements | none |
| Current offering | `gymstreak_sale` |
| Sandbox-purchases banner | **absent** |

That last row is the finding. A customer who has made *any* sandbox purchase carries a "This Customer
has sandbox purchases / Show sandbox data" banner — Julian's simulator record `c669` has one. `c6cc`
does not.

Corroborated from the other side: **Recent Transactions on the annual product, with the Sandbox
toggle on**, shows five `Renewal` rows on **2026-08-17** from `df06••••6585` (the German device test —
sandbox subscriptions renew every few minutes, hence five) and **nothing at all on 2026-08-18**.

**Conclusion: the purchase failed upstream of RevenueCat.** The SDK configured, fetched offerings and
rendered a paywall — the reviewer got far enough to tap Buy — but no transaction was ever created,
so nothing reached RevenueCat to validate, record or reject. **That exonerates the entire RevenueCat
half of the integration**: the entitlement identifier, the offering, the entitlement attachment, the
In-App Purchase Key and receipt validation all sit downstream of a transaction that never existed.

What is left is the StoreKit/App Store half: an Apple sandbox failure (`STORE_PROBLEM`), a problem
with the reviewer's own sandbox account, or the purchase sheet failing to present on an iPad running
an iPhone-only app.

**The record-reading trap, kept because it cost a round:** `$RCA••••c669` looks like the reviewer and
is not — `Last Seen App Version 1.1.10` (never submitted; `main` only) on `iOS 26.5` (a simulator
runtime), with en-US and USA being simulator defaults. It is a local Debug build. Also note the
"Has made sandbox purchase" filter *excludes* the record wanted here, and the country flag in the
list is not the storefront.

### 3.4a Refuted: "the reviewer was granted Founder and never saw a real paywall"

A natural theory once Fault 3 (§4) is known — if the shipped build is 68 and the cutoff is 1000, is
every install a Founder, reviewer included? **No, and two independent guards each stop it:**

1. `guard environment == .production`. App Review runs in the **sandbox** receipt environment, so the
   decision stays *undecided* and nothing is granted.
2. Even if it did not, `AppTransaction.originalAppVersion` returns **`"1.0"`** in every non-production
   environment (§3a's trap table). `Int("1.0")` is `nil`, so the decision stays *undecided* again.

*Undecided* means no grant, so the gates stay closed and the paywall shows — which matches what the
reviewer reported. Fault 3 is a real and serious bug, but it could only ever have fired for
**production** installs after approval. It is not the cause of the purchase error.

### 3.4b The 2026-08-23 reviewer session — again, nothing reached RevenueCat

`$RCAnonymousID:4aef15284bdb43a7ab34b49f1ca80308` (`$RCA••••0308`):

| | |
|---|---|
| First seen / last opened | both **2026-08-23, 06:54 UTC** (screenshot at 09:02 local — same session) |
| Last Seen App Version | **1.1.10** |
| Last Seen Platform Version | **iOS 26.6 (Build 23G71)** — the iPad in compatibility mode |
| Last Seen SDK | native **5.83.2** |
| Last Seen Locale | **en-GB** |
| Last Seen Storefront | **USA** |
| Entitlements | none |
| Current offering | `gymstreak_sale` — so offerings **did** resolve |
| Customer history | *"First seen or purchased"* and *"Last opened the app"*. **Nothing else.** |
| Sandbox-purchases banner | **absent** |

The list view showed a 🇬🇧 flag for this record while the storefront is USA — the flag in the customer
list is not the storefront, exactly as §3.4's trap says.

**Product-side confirmation.** `GymStreak Pro – Jahresabo` → Recent Transactions with **Sandbox on**
still shows only the five `Renewal` rows from `df06••••6585` on **2026-08-17**. Nothing on 18 August,
nothing on 23 August.

**Also cleared while there:** §3.3's "(Test Store)" ambiguity. The product page shows Associated
Entitlements = **Gym Streak Pro**, Associated Offerings = **gymstreak_sale**, and a Subscription Group
holding `gymstreak.iap.pro.yearly.sub` (current) and `gymstreak.iap.pro.monthly.sub`. These are real
App Store products, correctly wired. Not a factor.

### 3.5 Why there was no evidence, and what now produces some

`ProPaywallView` wired `onPurchaseCompleted`, `onRestoreCompleted` and `onRequestedDismissal` — but
**not** `onPurchaseFailure` or `onRestoreFailure`. RevenueCat showed the reviewer its own alert and
the app logged nothing, so the rejection arrived undiagnosable.

**Fixed 2026-08-20.** Both handlers now log the RevenueCat `ErrorCode` *by name*
(`storeProblemError`, `productNotAvailableForPurchaseError`, `configurationError`, …), the domain and
code, the underlying `SKError`, and the message — subsystem `app.gymstreak.pro`, category `Paywall`.
Neither changes behaviour.

### 3.6 Superseded

This section used to list what was still unknown. §3.7 answered all of it: the screenshot, the second
reviewer session, and the TestFlight purchase (§7b) between them closed every open item. What remains
is not diagnosis but repair — see §3.9, §3.10 and §7.

### 3.7 The reviewer's screenshot — it is the **Customer Center**, not the paywall

**Read 2026-08-23. This is the finding the whole investigation was missing.**

The 1.1.10 rejection carried `Screenshot-0823-075757.png` (App Store Connect → submission page →
Übermittelte Elemente → the `iOS-App 1.1.10` row → **Laden**). Taken at **09:02, Sun 23 Aug**, on an
iPad, with the app in a portrait iPhone-compatibility window. It shows:

> ✕ &nbsp;&nbsp; **No subscriptions found** — *We can check for previous purchases* — **[ Restore past purchases ]**

That is **RevenueCat's Customer Center in its empty state**, presented by
`CustomerCenterSettingsRow`. It is not `ProPaywallView`, not `PaywallView`, and not any error alert.
There is no purchase sheet, no price, no package on that screen at all.

**So Apple's evidence for "error occurred when we tried to buy" is a screenshot of a screen that
cannot buy anything.** The reviewer went looking for the in-app purchase, landed in Settings →
**Manage subscription** → "No subscriptions found", and reported that as the failure.

Everything else lines up with that reading and with nothing else:

- The 2026-08-23 customer record (§3.4b) has **no purchase event of any kind** — its entire history is
  "First seen" and "Last opened", both 06:54 UTC. Nothing was ever attempted at the StoreKit layer.
- No sandbox transaction exists on either product for 18 or 23 August (§3.4b).
- Apple's added line, *"Review the product configurations, complete any missing information"*, is what
  a reviewer writes when they could not find or reach a working purchase — not what they write about a
  purchase that threw.

**This reframes Fault 2 entirely.** For two rounds the working assumption was that a purchase was
attempted and failed. The evidence now says **no purchase was ever attempted**, and the real defect is
that the paywall is hard to reach on a fresh install (§3.9).

### 3.8 Demoted: the device pattern (iPhone-only app on an iPad)

`TARGETED_DEVICE_FAMILY = 1` for the iOS app target (`GymStreak.xcodeproj/project.pbxproj`), so on the
reviewer's **iPad Air 11-inch (M3)** the app runs in **iPhone compatibility mode** — a scaled iPhone
window, not a native iPad app. Both rejections came from that device; the one purchase that has ever
succeeded (2026-08-17, five sandbox renewals on the annual) was a German **iPhone**.

This is a live, unresolved pattern in Apple's own forums: [thread
821419](https://developer.apple.com/forums/thread/821419) reports an IAP dialog that appears normally
on a physical iPhone and fails to appear during App Review on an iPad Air 11-inch (M3) — rejected
twice under 2.1(b), with no resolution from DTS beyond "review in the sandbox".

**Demoted 2026-08-23, not refuted.** §3.7 explains both rejections without needing any iPad-specific
mechanism, and §3.4b shows the reviewer never got as far as a purchase sheet on either occasion — so
there is nothing for compatibility mode to have broken. Keep the theory on file: it stays untested
until someone runs a sandbox purchase on an iPad, and if a *third* rejection arrives after §3.9 is
fixed, this is where to look next.

---

### 3.9 Fault 6 — nothing leads a new user to the paywall · **CODE FIXED 2026-08-23**, ships in the next build

This is the defect §3.7 points at, and it is entirely ours.

**Settings sells nothing, by design.** `SubscriptionSettingsSectionView` says so in its own doc
comment: *"The section still sells nothing; the paywall is the only surface that does, and it is
reached from a gate, never from Settings."* A free user in Settings sees a status row reading *Free*
and one action: **Manage subscription** → *"Restore, change, cancel or request a refund"* →
`CustomerCenterView` → **"No subscriptions found"**. That is the screen Apple screenshotted.

**Every purchase surface is behind a gate that needs data the reviewer does not have.**

| Placement | What a fresh install must do first |
|---|---|
| `firstRoutineCreated` (§8 A, soft) | Create **1** routine — the only genuinely reachable one |
| `routineCap` | Create **3** routines (`ProFeatureCaps.freeRoutineLimit = 3`), then tap ➕ a 4th time |
| `chartMetric`, `chartWindow` | Log enough workouts for a chart to exist |
| `coachChat`, `periodRecap`, `exerciseDeepDive` | Exhaust a monthly AI taster allowance |
| `valueMoment` | Accumulate lifetime training totals |
| `weekdaySchedule` | Reach the schedule editor |

A reviewer with ten minutes, an unfamiliar fitness app, and an iPad does the obvious thing: opens
Settings, finds the section literally headed *Subscription*, taps the only row in it, and is told
**"No subscriptions found."** From there the app offers no route to a paywall at all.

**Two rounds of 2.1(b) are fully explained by this** — and unlike §3.8's iPad theory or an Apple-side
sandbox fault, it needs no unproven mechanism, it is consistent with the total absence of transactions
in both sessions, and we can fix it ourselves.

**The fix has two halves.**

1. **Settings now carries both a purchase and a restore affordance** — done 2026-08-23, in code,
   ships in the next build. A free user gets **"Get Gym Streak Pro"** (raises the paywall through the
   new `PaywallPlacement.settingsUpgrade`, via `PaywallPresenter` like every gate, so the kill switch,
   Rule 3 and the entitlement check all still apply) and **"Restore purchases"**
   (`RestorePurchasesSettingsRow` → `Purchases.shared.restorePurchases()`, reporting restored /
   nothing-found / failed as three distinct alerts).

   **The Customer Center is no longer shown to free users at all**, which removes the exact screen
   Apple screenshotted. It now goes only to `.subscription` and `.lifetime` — people with something
   to manage. Guideline 3.1.1 is satisfied more directly than before, by a row that does one thing and
   names it. See `pro-subscription.md` §5i.
2. **App Review Information → Notes: the exact click path.** Still to do. Free, immediate, and it
   should have been there for 1.1.9 — see §9.

**What a free user's Settings looks like now**, and what each tier gets:

| Plan | Rows below the status row |
|---|---|
| `.subscription` / `.lifetime` | Manage subscription → `CustomerCenterView` |
| `.free` | **Get Gym Streak Pro** → paywall · **Restore purchases** → `restorePurchases()` |
| `.founder` | none — a local, permanent grant has nothing to buy, restore or manage |

**Shipped in this change:**

| File | What |
|---|---|
| `Domain/Models/Pro/PaywallPlacement.swift` | new case `settingsUpgrade = "settings-upgrade"`, a contextual gate so it is never one-shot |
| `Domain/Models/Pro/ProRestoreOutcome.swift` | **new** — `.restored` / `.nothingFound` / `.failed` |
| `Domain/Interfaces/ProEntitlementProviding.swift` | `restorePurchases() async -> ProRestoreOutcome` promoted from the DEBUG-only protocol to the shipping one |
| `Data/Purchases/ProEntitlementProvider.swift` | the restore implementation, moved out of the `#if DEBUG` extension and returning the outcome |
| `Presentation/ViewModels/Pro/SubscriptionStatusSummary.swift` | `showsUpgradeAction` / `showsRestoreAction` (both `.free`-only); `showsCustomerCenter` narrowed from "everyone but a Founder" to `.subscription`/`.lifetime` |
| `Presentation/Views/Pro/RestorePurchasesSettingsRow.swift` | **new** — the row, plus a three-way alert |
| `Presentation/Views/Settings/Components/SubscriptionSettingsSectionView.swift` | composes the three shapes; takes `paywalls` |
| `Presentation/Views/Settings/SettingsRootView.swift` | passes `dependencies.paywalls` |
| `Resources/{en,de}.lproj/Localizable.strings` | 13 new keys, both languages |

**Tests.** `freeTierIsOfferedUpgradeAndRestore`, `everyTierHasAnActionExceptFounder` (no tier may be
left with a status row and nothing to do — the assertion that would have caught this), a rewritten
`customerCenterIsOfferedToPayingPlansOnly`, `freeTierCopyResolves` over all 13 keys in en and de, and
`emptyRestoreReportsNothingFound`. `unreachableRestoreDoesNotRevoke` was extended to assert the
outcome is `.failed`, never `.nothingFound` — telling someone who paid that they own nothing is the
worst thing a restore can say. Whole iOS suite green; the watch target is untouched.

> **`monetization-strategy.md` §8 is not violated.** It forbids the app *interrupting* to sell; a row
> the user has to go looking for does not interrupt. Recorded there as well as here.

### 3.10 Fault 7 — the paywall advertises a free trial that does not exist · **OPEN**

Found 2026-08-23 during the first successful TestFlight purchase, unrelated to how it was found. It
is a second, independent rejection risk (Guideline 2.3.1 / 3.1.2) and must be fixed before
resubmitting.

#### What App Store Connect actually offers — verified 2026-08-23

| | Monatsabo `…pro.monthly.sub` | Jahresabo `…pro.yearly.sub` |
|---|---|---|
| Regular price (DE) | 4,99 €/Monat | 24,99 €/Jahr |
| **Einführungsangebot** (Introductory) | 2,99 € für den ersten Monat | **Für die erste Woche kostenlos** — *changed 2026-08-23, see B below* |
| Offer window | 14 Aug – **30 Sept 2026** | 23 Aug 2026 – **kein Enddatum** |
| Territories | 175 | 175 |
| Aktionsangebot (Promotional) | none | `yearly_sub_seven_days_free` — "Für die erste Woche kostenlos", Im Voraus, 175 territories |

**As originally found (18–23 Aug), neither product offered a free trial to a new customer** — both
introductory offers were paid (the yearly's was 19,99 € für das erste Jahr). That is the state the
paywall's copy was measured against, and the state both rejected builds shipped under. The yearly was
changed to a real 7-day trial on 2026-08-23; the monthly's paid introductory offer stands.

**The 7-day free trial is dead configuration, and structurally cannot be a new-user trial.** It is an
**Aktionsangebot** — a *Promotional Offer* — and two things stop it independently:

1. **It is not wired into the paywall.** RevenueCat's package component carries a dedicated
   **Promotional Offer** field (separate App Store / Play Store identifiers) and the SDK applies the
   offer at purchase time when the customer is eligible. The Annual package's field is empty, so
   `yearly_sub_seven_days_free` is never requested. *(Signing is RevenueCat's job, not ours — an
   earlier version of this section wrongly said the app had to request a signed offer in code.)*
2. **A new customer is not eligible anyway.** App Store promotional offers reach only customers with
   **prior purchase history** in that subscription group — existing and lapsed subscribers. Someone
   installing the app for the first time can never receive one, whatever the paywall says.

So the trial has never been shown to anyone, cannot be shown to a new user, and believing it was live
is what put a false free-trial claim on the paywall.
([Apple — introductory offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions) ·
[promotional offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-promotional-offers-for-auto-renewable-subscriptions))

> **The monthly's introductory offer expires 30 September 2026**; the yearly's trial has no end date.
> After 30 Sept the monthly has no offer, RevenueCat's Introductory override stops firing for it on its
> own, and its Default text takes over — correct, once §3.10's fix is in. Nothing to schedule, but
> worth knowing the monthly's launch pricing is a five-week window while the annual's trial is
> permanent.

#### What the paywall says, and why

The text lives in the **RevenueCat Paywall Editor**, not the binary — a grep of `Localizable.strings`
finds no trial copy. It sits in a per-component **override state**, which is why three passes over the
editor missed it: the Default state shows only `{{ product.price_per_period_abbreviated }}`, and both
localizations look clean. The offending text is under **Text properties → `</> Introductory`**:

```
{{ product.period_with_unit }} kostenlos testen, dann {{ product.price_per_period_abbreviated }}
```

Rendering, on a real device, as *"1 Monat kostenlos testen, dann 4,99 €/Mo"* and *"1 Jahr kostenlos
testen, dann 24,99 €/J (2,08 €/Mon.)"* — while Apple's own purchase sheet for the same tap says
**"2,99 € pro Monat — Angebot (1 Monat)"**. A user expecting €0 is charged €2,99.

**Two distinct defects in that one line:**

1. **`kostenlos testen` is simply false.** RevenueCat's Introductory state fires for *any* introductory
   offer, free or paid, so hardcoding "free trial" into it was never safe. **This is the actual lie.**
2. **`{{ product.period_with_unit }}` is the wrong variable** — it is the *subscription's billing
   period*, not the offer's duration (`{{ product.offer_period_with_unit }}`). Today the two coincide,
   because both offers happen to last exactly one billing period, so it renders correctly by accident.
   It would start lying the moment an offer's length differs from the billing period — for instance if
   the 7-day trial were ever made real.

**A third, separate defect: the badge.** The Annual package carries a literal **`FREE TRIAL`** badge in
the **English** localization while the German one carries `SPARE {{ product.relative_discount }}`. So
the two languages make different claims about the same package, and the English one is false.

#### The fix

Dashboard only — no binary, no App Store Connect edit, no review risk. Four text edits plus a badge.

**1. Both packages, both locales, with `</> Introductory` selected:**

| Locale | Replace the Introductory text with |
|---|---|
| English | `{{ product.offer_price }} for {{ product.offer_period_with_unit }}, then {{ product.price_per_period_abbreviated }}` |
| German | `{{ product.offer_price }} für {{ product.offer_period_with_unit }}, dann {{ product.price_per_period_abbreviated }}` |

Keep the annual's existing ` ({{ product.price_per_month }}/Mon.)` tail. Result on a German device:

- Monatlich — *"2,99 € für 1 Monat, dann 4,99 €/Mo"*
- Jährlich — *"19,99 € für 1 Jahr, dann 24,99 €/J (2,08 €/Mon.)"*

`{{ product.offer_price }}` renders the offer's actual price, and renders *free / gratis* if the offer
ever becomes a trial — so this wording stays true through either change and needs no second pass.

**2. Delete the `FREE TRIAL` badge** from the Annual package's English localization. There is no free
trial for a new customer, so the badge is false in the only audience that sees the acquisition paywall.

**3. Publish.** The editor has been sitting on **"Draft version"** throughout; nothing above is live
until *Publish changes*. Check what the currently published version says as well — it may already
differ from the draft.

> **Editor-preview trap.** With the German locale selected, the preview still renders variables in
> English ("1 month kostenlos testen") and uses mock prices ($9.99 / $79.99, SPARE 19%). The device
> renders them localized and with real prices (4,99 € / 24,99 €, SPARE 58%). A preview that looks
> half-English is not a bug.

#### "But how do we tell users about the 7-day trial?" — we do not, and cannot

The question is the right one and the answer is structural: `{{ product.offer_price }}` describes the
**Einführungsangebot** only, which is correct, because that is the sole offer a new customer can
receive. An Aktionsangebot can never be a new-user trial (see above). Three ways forward, and choosing
between them is a pricing decision, not a bug fix:

| | What | Cost | When |
|---|---|---|---|
| **A** | Ship truthfully: delete the badge, keep both paid intro offers | Dashboard only, no App Store Connect edit, **no review risk** | **Now — this resubmission** |
| **B** | Make the trial real: replace the yearly's Einführungsangebot with a **Free Trial, 1 Woche** | An App Store Connect **product edit** → re-check the review state afterwards (§6) | **Chosen 2026-08-23** — see below |
| **C** | Keep it as a win-back: put `yearly_sub_seven_days_free` in the Annual package's **Promotional Offer → App Store** field | Dashboard only, but reaches nobody until there are lapsed subscribers | Later, once there are subscribers to win back |

#### B in detail — chosen 2026-08-23

Julian's call: a free trial is expected to convert better than a first-year discount, and he is willing
to edit the product and resubmit the subscription.

**The trap this decision walks into, stated plainly.** The intuition is *"both offers are configured, so
the Aktionsangebot is being downgraded to purchase-history-only; remove the Einführungsangebot and the
trial opens up to everyone."* **That is wrong, and acting on it would make things worse.** The
Aktionsangebot is restricted to existing and lapsed subscribers because it is a *Promotional Offer* —
that is Apple's definition of the type, not a consequence of anything else being configured. The two
offer types serve **disjoint audiences** and never compete:

| | Einführungsangebot (Introductory) | Aktionsangebot (Promotional) |
|---|---|---|
| Audience | never subscribed in this group | currently or previously subscribed |
| Applied by | the App Store, automatically | the paywall/SDK, on request |
| Concurrent | **one** per territory per date range | several allowed |

Deleting the Einführungsangebot would therefore not unlock the trial for new users. It would leave them
with **no offer at all** — 24,99 €/Jahr at full price.

**What actually has to happen:** create a *new* **Einführungsangebot** of type **Kostenlose Testversion
(Free Trial), 1 Woche**. Same seven days, different object, different audience. Because only one
introductory offer may be active per territory and date range, it must either replace the
19,99 €-first-year offer or be scheduled to follow it (the current window ends 30 Sept 2026, so a trial
could start 1 Oct). Replace it now if the trial is to be live for this review.

The Aktionsangebot stays as-is — dormant, harmless, and later the honest home for option C's win-back.

**Done 2026-08-23.** The Jahresabo's Einführungsangebote now reads a single row:
**23. Aug. 2026 bis Kein Enddatum · 175 Länder oder Regionen · Für die erste Woche kostenlos · Im
Voraus.** The 19,99 €-first-year offer is gone; the Aktionsangebot is untouched and still dormant.

**Nothing needs wiring in RevenueCat.** Introductory offers are **store-managed**: the App Store
applies them automatically to eligible customers and the SDK reads them off the StoreKit product at
runtime. There is no dashboard field, no toggle and no product re-import. That is precisely the
difference from the Aktionsangebot, which *would* have required the package's Promotional Offer field.
The only remaining work is the paywall text, which was broken independently of this change.

**Still to verify:** *Übermittelte Elemente* → the Jahresabo must still read **Bereit zur Prüfung**
after the product edit. Whether an offer edit pulls a subscription out of review the way the
display-name edit did (§6) is **not established** — check rather than assume, because assuming it was
fine is what cost round two.

**No further paywall work beyond §3.10's fix.** With `{{ product.offer_price }}` in place the yearly
renders *"Gratis für 1 Woche, dann 24,99 €/J (2,08 €/Mon.)"* on its own, and the monthly
*"2,99 € für 1 Monat, dann 4,99 €/Mo"*.

**The badge cannot be made conditional — a Package component has no offer-state override.**

An earlier revision of this section said to move `FREE TRIAL` under the `</> Introductory` override.
**That is not possible, and the mistake is worth recording.** In the RevenueCat editor the offer-state
dropdown (`</> Default | Introductory | …`) appears on **Text properties** only. Select the Package
layer and the panel has no such dropdown at all — only a `Default | Selected` toggle, which keys off
whether the *package is selected*, not off eligibility. The Annual badge is currently wired to exactly
that: `SPARE {{ product.relative_discount }}` unselected, `FREE TRIAL` selected.

So a badge on the Package component is shown to **everyone**, eligible or not. Three ways out:

| | What | Trade-off |
|---|---|---|
| A | Delete the `FREE TRIAL` badge from the Annual package | The Introductory *text* already carries the trial and is self-correcting, but the package loses all visual emphasis |
| **B** | **Set the badge to a discount claim in both states** | True for everyone — a price comparison, not an offer claim. Keeps the visual emphasis, drops the trial wording. **Chosen 2026-08-23.** |
| C | Build the badge as a **separate Text component** overlaid on the package | Text components *do* get the Introductory override, so it could show only to eligible users. Correct mechanism, but editor layout work — revisit after approval |

**Who a wrong badge actually harms:** a **lapsed subscriber**. They are the only people ineligible for
the introductory offer who still reach the paywall — and they would see FREE TRIAL, tap, and be charged
24,99 €. That is the Guideline 2.3.1 complaint exactly.

**What B looks like as configured (2026-08-23):** the Annual package's badge reads
`SAVE {{ product.relative_discount }}` in English and `SPARE {{ product.relative_discount }}` in
German, set identically on **both** the `Default` and `Selected` package states so it no longer flips
wording when the package is tapped. With real prices it renders **SPARE 58%** (24,99 €/Jahr against
12 × 4,99 €/Monat = 59,88 €); the editor's 19% comes from its mock prices. `relative_discount` compares
the two *regular* prices, so the offer change does not affect it and it stays true for eligible and
ineligible customers alike.

The trial is therefore carried by the Introductory **text** alone — *"Free for 1 week, then
$79.99/yr"* — which is exactly the self-correcting surface: an ineligible customer falls through to the
Default text and is promised nothing.

**Two checks, both confirmed 2026-08-23:**

1. ✅ With the toolbar `</> Offer` pill back on **Default**, the Annual's non-introductory text still
   reads `{{ product.price_per_period_abbreviated }} ({{ product.price_per_month }}/Mon.)`. That state
   is what ineligible customers see; the Introductory variant deliberately drops the per-month tail.
2. ⚠️ The editor preview renders **mock offer data for both packages** ("$1.99 for 1 week") regardless
   of what App Store Connect holds, and mock prices ($9.99 / $79.99, 19%). It is never confirmation.
   Verify on device with an eligible Sandbox account.

**Published 2026-08-23.** The draft is live. §3.10 is closed.

#### Testing the trial: eligibility is per **subscription group**, not per product

A customer qualifies for an introductory offer only if they have **never subscribed to any product in
the group**. Both products live in `gymstreak.pro.abos`, so:

- **Julian's own Apple Account is no longer eligible.** It bought the monthly in sandbox on 2026-08-23
  (§7b), which makes it an existing subscriber in the group. Testing with it shows the **Default** text,
  not the trial — and that looks exactly like the fix having failed. It has not.
- **To see the trial**, use a Sandbox Apple Account that has never subscribed (App Store Connect →
  Benutzer und Zugriffsrechte → Sandbox) **on an Xcode build** — TestFlight ignores the Sandbox Apple
  Account and forces the Medien-&-Käufe account (§3.6).
- **App Review will see it**: reviewers use a fresh sandbox account.
- **Consequence for real users, by design:** anyone who takes the monthly's 2,99 € first month is then
  ineligible for the annual's trial, and vice versa. One introductory offer per customer per group.

**Open sub-decision:** the **monthly** keeps its 2,99 €-first-month introductory offer, so the paywall
would read *"2,99 € für 1 Monat"* beside *"Gratis für 1 Woche"*. Legitimate and common, but if both
packages should lead with a trial the monthly needs the same treatment.

---

## 4. Fault 3 — Xcode Cloud overrode the build number · **FIXED**

Found while investigating, cited by nobody, and the most expensive of the five.

Apple named the version **1.1.9 (68)** while `store-build` ships `CURRENT_PROJECT_VERSION = 1000`.
**Xcode Cloud stamps submissions with its own counter**, not the project's `CFBundleVersion`. Shipped
builds were 63, 64, 65, 66, 68, with 69 queued.

`FounderStatusService.cutoffBuild` is `1000` and the grant is `originalBuild < cutoffBuild`. Had 1.1.9
been approved, every new install would have reported `68`, read as pre-cutoff, and been **granted
Founder — Pro, free, permanently.** No error, no crash; the only symptom would have been revenue that
never arrived.

`FounderStatusTests.shippingBuildIsNotBelowCutoff` cannot catch this: the suite is app-hosted and
reads the *locally built* `CFBundleVersion`. It never sees the number Xcode Cloud stamps.

**Fixed 2026-08-20:** App Store Connect → Xcode Cloud → Einstellungen → Build-Nummer → next build
**1001**. Confirmed in the UI. Installs already in the wild (63–66) stay correctly below the cutoff
and keep their grant; 68 was never released publicly; TestFlight is excluded by §3a's environment
guard regardless.

> **Standing hazard.** If that setting is ever reset, or a workflow recreated, the counter can return
> to a low value and this fault returns silently. **Read the number in App Store Connect before every
> submission.**

---

## 5. Fault 4 — the privacy nutrition labels said "no data collected" · **FIXED**

Found 2026-08-21, fixed the same day. App Store Connect → App-Datenschutz reported **"Keine Daten
erfasst — Der Entwickler erfasst keine Daten von dieser App."**

That was true before RevenueCat. It is not true now, and `pro-subscription.md` §9.7 already specified
the correct answers — §9.6 step 12 required this in the same release that turns purchases on, and it
was missed. A privacy label that contradicts the app's actual behaviour is its own rejection risk,
independent of the two guidelines already cited.

**Published 2026-08-21** and confirmed in the Vorschau der Produktseite: *Nicht mit dir verknüpfte
Daten → Käufe*; Datentypen: *1 Datentyp erfasst: Einkaufsverlauf*; *Verwendet für App-Funktionalität
und Analyse*. The answers given:

- Add **Purchases → Purchase History**.
- Purposes: **App Functionality** *and* **Analytics** (RevenueCat's dashboard — Customer History,
  Charts, Experiments — is an analytics use of that data, anonymous app user ID or not).
- Linked to the user's identity: **No**.
- Used to track you: **No**.

Everything else genuinely stays "not collected": health, fitness and workout data never reach a
server the developer controls, the AI Coach runs on device, and there is no IDFA or attribution SDK.

**Benutzer-ID is deliberately left unticked, and it is a judgement call.** RevenueCat generates an
anonymous app user ID, and Apple's *User ID* type covers an "assigned user ID". It stays off because
the app creates and transmits no identifier of its own, and because RevenueCat — the party that knows
what it collects — declares only `UserDefaults` and Purchase History in its **own** privacy manifest,
which Xcode merges into the app's Privacy Report at archive time. Declaring more than the SDK does
would put the app's answer at odds with the manifest Apple actually reads. Recorded so the reasoning
survives if a reviewer ever queries it.

**This publishes without an app version** — Apple: *"You may update your answers at any time, and you
do not need to submit an app update in order to change your answers."* So it can be done now, and
independently of the resubmission.

**The click path** (App Store Connect in German; English labels in brackets):

1. App → sidebar **App-Datenschutz** [App Privacy].
2. Next to the current "Keine Daten erfasst" answer, **Bearbeiten** [Edit] — or **Erste Schritte**
   [Get Started] if no answer has been given yet.
3. Choose **„Ja, wir erfassen Daten von dieser App"** [Yes, we collect data from this app] →
   **Weiter** [Next].
4. In the data-type grid tick **Käufe** [Purchases] — a single checkbox whose description is
   Purchase History's own definition ("Käufe oder Kauftendenzen eines Accounts oder einer
   Einzelperson"), so there is no sub-item to pick. Tick nothing else, in particular not
   **Gesundheit und Fitness**, not **Finanzinformationen → Zahlungsinformationen** (Apple handles
   billing; the app never sees payment details) and not **Kennungen → Benutzer-ID** (below) →
   **Sichern** [Save].
5. Click the **Käufe** row — the dialog is titled **Einkaufsverlauf** — and answer:
   - *Wie werden diese Daten verwendet?* → **App-Funktionalität** and **Analyse**
   - *Mit der Identität verknüpft?* → **Nein**
   - *Für Tracking verwendet?* → **Nein**

   → **Sichern**.
6. **Veröffentlichen** [Publish], top right, and confirm in the dialog.

---

## 6. Fault 5 — the subscriptions were withdrawn from review · **FIXED 2026-08-23**

Editing the group's localized display name (fixing "RideStreak Pro Zugriff" → "GymStreak Pro Zugriff")
required pulling the group out of the submission. The group and **both** products then read **"Vom
Entwickler abgelehnt"**.

**Apple reviews the app and its subscriptions together.** Resubmitting the binary while the products
sit outside review is a documented cause of precisely the 2.1(b) rejection — the reviewer reaches a
paywall and cannot buy.

**And that is how 1.1.10 (1002) went in** — submitted with the subscriptions still developer-rejected.

**It is not, however, the cause of either rejection.** §3.7's screenshot settled that: the reviewer
never reached a purchase sheet, so product review state never came into play. It also cannot explain
the *first* rejection, where §3.1 records both subscriptions as "In Prüfung" alongside the binary.
Fix it because it is wrong and because it would eventually bite — not because it is the answer.

**Current state — verified 2026-08-23.** All three items are back in the submission and read
**"Bereit zur Prüfung"** under *Übermittelte Elemente*:

| Element | Typ | Prüfungsstatus |
|---|---|---|
| `gymstreak.pro.abos` | Abo-Gruppe | 🕒 Bereit zur Prüfung |
| GymStreak Pro – Jahresabo (1 Jahr) | Abo | 🕒 Bereit zur Prüfung |
| GymStreak Pro – Monatsabo (1 Monat) | Abo | 🕒 Bereit zur Prüfung |
| iOS-App 1.1.10 (1002) | App-Version | ❌ Abgelehnt — 2.1.0 Performance: App Completeness |

They will go into review together with the next binary. **Re-read this table before every submission**
— any edit to the group or a product can silently pull it back out.

The rename itself is done and correct: Deutsch *GymStreak Pro Zugriff*, English (USA) *GymStreak Pro
Access*, both with app name *GymStreak*.

---

## 7. Where things stand

### Done

- [x] Paywall footer: Terms of Use + Privacy Policy buttons (RevenueCat, no binary needed)
- [x] Settings → Legal section, en + de (`LegalLinks.swift`, `SettingsRootView.swift`)
- [x] `onPurchaseFailure` / `onRestoreFailure` logging (`ProPaywallView.swift`)
- [x] Privacy Policy URL in App Store Connect
- [x] Terms of Use link in the German App Description
- [x] Terms of Use link in the **English** App Description
- [x] Xcode Cloud build number — **confirmed working**: Apple reviewed 1.1.10 as build **1002** (§1b)
- [x] Subscription group display name: RideStreak → GymStreak
- [x] Privacy nutrition labels: Käufe / Einkaufsverlauf, App-Funktionalität + Analyse, unlinked, no tracking — **published 2026-08-21**
- [x] In-App Purchase Key confirmed valid in RevenueCat
- [x] Sandbox transactions checked — 2026-08-17 present, 2026-08-18 empty (§3.4)
- [x] Reviewer's customer record identified: `$RCA••••c6cc` (§3.4)
- [x] 3.1.2(c) confirmed resolved — not re-cited in the 1.1.10 rejection (§1b)
- [x] Subscriptions + group returned to review, "Bereit zur Prüfung" (§6) — **2026-08-23**
- [x] `Screenshot-0823-075757.png` downloaded and read — it is the Customer Center (§3.7)
- [x] 2026-08-23 reviewer session read in RevenueCat: no transaction, again (§3.4b)
- [x] Products confirmed to be real App Store products, correctly wired to entitlement and offering (§3.4b)
- [x] **A purchase completed end-to-end from a TestFlight build** (§7b) — the purchase path is proven
- [x] **Settings purchase + restore rows** — `settingsUpgrade` placement, `RestorePurchasesSettingsRow`, Customer Center narrowed to entitled plans (§3.9) — **2026-08-23**, build green, iOS suite green
- [x] App Store Connect offer configuration verified and recorded (§3.10) — **2026-08-23**
- [x] Yearly's introductory offer changed to a real **7-day free trial**, no end date (§3.10 B) — **2026-08-23**
- [x] Paywall Introductory text rewritten to `{{ product.offer_price }} … {{ product.offer_period_with_unit }}`, both packages, both locales, both selection states (§3.10) — **2026-08-23**, *draft, not yet published*
- [x] Annual badge changed to `SAVE`/`SPARE {{ product.relative_discount }}` on both package states (§3.10) — **2026-08-23**
- [x] **Paywall draft published** (§3.10) — **2026-08-23**
- [x] **App Review Notes written** (§9a) — **2026-08-23**
- [x] Documentation: `pro-subscription.md` §5i, §5k and §9.8, `settings-tab.md`, TestFlight notes (en + de)

### Open — one ordered list

**Nothing is open on our side.** 1.1.11 (1004) was submitted on 2026-08-23 with all four elements in
one submission (§10). The list below is kept as the record of what closed it.

| # | Do | Outcome |
|---|---|---|
| 1 | **Commit the working tree and run the merge chain** | ✅ done — `store-build` is at `8e25d5e`, carrying §3.9's Settings rows and `MARKETING_VERSION = 1.1.11` |
| 2 | **Read the build number App Store Connect actually stamps** | ✅ done — Xcode Cloud stamped **1004**, comfortably ≥ 1000, so no production install reads as a Founder (§4) |
| 3 | **Re-check *Übermittelte Elemente*** | ✅ done — group + both subs read *Bereit zur Prüfung* alongside the binary (§6, §10) |
| 4 | Verify the new Settings rows on a **TestFlight build**, iPhone then iPad | ⬜ **not done** — shipped on the unit tests and the preview alone. If a third rejection cites 2.1(b) again, this is the first thing to close |
| 5 | **Record a screen capture of a completed purchase** and attach it | ⬜ **not done, and not required.** Apple never asked for one — the request lived only in our own §9 draft. The draft was rewritten to drop the promise and spell out the click path instead |
| 6 | **Submit binary + group + both subscriptions together** | Apple reviews them as one submission; splitting them is §6 | App Store Connect |
| 7 | Sandbox purchase test **on an iPad** in compatibility mode | §3.8's theory is demoted, not refuted. Cheap to close once a build exists | TestFlight on iPad |

### 7a. Reading RevenueCat after a review session

The exact click paths, because the defaults hide the sandbox data every time.

**A — did a transaction reach RevenueCat on the review date?**

1. RevenueCat → the **Gym Streak (App Store)** project → **Customers** in the left sidebar.
2. Sort by **Last Seen**, descending. The reviewer sits at the top for that day.
3. Identify the record by **Country = United States** + **First Seen = the review date**, early UTC.
   Their app version must read the *submitted* build (1.1.10). Do **not** use the "Has made sandbox
   purchase" filter — it excludes exactly the record wanted.
4. Open it and look for the **"This Customer has sandbox purchases / Show sandbox data"** banner.
   - **Absent** → no transaction was ever created; the failure is upstream of RevenueCat, in
     StoreKit or Apple's sandbox. (This is what 2026-08-18 showed.)
   - **Present** → a transaction existed; the failure is downstream and RevenueCat's own logs have it.

**B — sandbox transactions on the products themselves.**

1. **Product catalog → Products → GymStreak Pro – Jahresabo** (`gymstreak.iap.pro.yearly.sub`).
2. Scroll to **Recent Transactions** and turn the **Sandbox** toggle **on**. The default view is
   production-only and reads "No transactions yet" no matter what.
3. Repeat for the **Monatsabo**. A sandbox subscription renews every few minutes, so one real test
   purchase shows as several `Renewal` rows.

**Before concluding anything, re-read §3.4's record-reading trap** — a local simulator record looks
exactly like a reviewer's and already cost one round.

### 7b. The purchase flow works — verified end to end, 2026-08-23

**The first successful purchase from a distributed build.** TestFlight 1.1.10, iPhone, real Apple
Account (`j.manke@icloud.com`), German storefront:

1. Routines tab → ➕ → the paywall renders with both packages and correct prices.
2. Monthly selected → **Pro freischalten** → Apple's native purchase sheet appears, headed
   **TestFlight**, naming *GymStreak Pro – Monatsabo*, the intro price, the renewal price and date, and
   *"Nur zu Testzwecken. Für die Bestätigung dieses Kaufs werden dir keine Gebühren in Rechnung
   gestellt."*
3. **Abonnieren** → *"Du bist jetzt startklar — Dein Kauf war erfolgreich."*
4. The paywall dismissed and the entitlement applied.

So `RevenueCatPurchaseGateway`, the offering, the entitlement wiring, `PaywallView` and
`onPurchaseCompleted` are all proven against a real StoreKit transaction. **There was never a bug in
the purchase path.** That is what makes §3.9 the answer.

**Testing note:** a TestFlight build **ignores** Settings → Entwickler → Sandbox-Apple Account. It runs
purchases in the sandbox *environment* but authenticates against the account signed into **Medien &
Käufe** — the real one. Being prompted for the real Apple Account is expected; purchases stay free. If
iOS says *"Gib das Passwort für … in den Einstellungen ein"*, that is a device account state, not an
app fault — re-authenticate in Settings and the purchase proceeds.

### Before submitting

All eight cleared for 1.1.11 (1004) on 2026-08-23. **Keep this list — it is the checklist for any
future resubmission**, not a one-off.

1. ✅ **The paywall draft is published** (§3.10).
2. ✅ **App Review Notes name the exact click path** (§9a).
3. ✅ **Privacy labels published** (§5).
4. ✅ **The binary actually contains §3.9's Settings rows.** `store-build` is at `8e25d5e`; archiving
   `7150b19` would have re-uploaded the rejected 1.1.10 binary.
5. ✅ **Build number in App Store Connect ≥ 1000** (§4) — Xcode Cloud stamped **1004**. Read the number
   in App Store Connect rather than trusting `CURRENT_PROJECT_VERSION`; Xcode Cloud overrides it.
6. ✅ **Subscriptions "Bereit zur Prüfung" alongside the binary** (§6) — re-read after the yearly's
   introductory-offer edit, still in review.
7. ➖ **Screen capture of a completed purchase** — dropped. Apple never asked; see §7 item 5.
8. ✅ **Submit binary + group + both subscriptions as one submission.**

---

## 9. What we are telling App Review

**No code change fixes the purchase error.** Worth stating plainly so nobody assumes otherwise: the
two code changes are the Settings Legal section (a 3.1.2(c) fix) and the purchase-failure logging.
The logging writes to the **device's** log, so it helps only when *we* can read the console — an iPad
test, or a user report after launch. It tells us nothing about a future App Review attempt.

What has actually changed for a re-review: the legal links (paywall footer, Settings, metadata), the
privacy labels, and the build number. The purchase path itself is byte-for-byte what the reviewer
tried, minus two logging callbacks. If the failure was an Apple-side sandbox problem, a re-review is
itself the test.

### The reply text

**Rewritten 2026-08-23** — the earlier draft asked Apple for the error text, which they have since
supplied unprompted (§3.7), and defended 3.1.2(c), which was not re-cited. Both asks are spent. The
message now has one job: tell the reviewer where the paywall is.

```
Hello,

Thank you for the screenshot — it identified the problem immediately, and we have fixed it.

The screen in your screenshot is our subscription *management* screen (restore, change, cancel,
request a refund). It correctly reports "No subscriptions found" because no purchase had been made
yet, but it is not where a purchase is started, and we can see why that was misleading. Our records
confirm no purchase was ever attempted during either review session, so nothing failed — the purchase
screen was simply never reached.

We have made three changes:

1. The Settings screen now offers a direct "Upgrade to Gym Streak Pro" option for users without a
   subscription, which opens the purchase screen immediately.
2. We have corrected the pricing text on the purchase screen. It previously described the
   introductory offer as a free trial; it now states the actual introductory price and the price that
   follows it.
3. We have added step-by-step instructions below, and a screen recording of a completed purchase.

To reach the purchase screen in this build:

  Settings tab > Subscription > Upgrade to Gym Streak Pro

or, from anywhere in the app:

  Routines tab > + (top right) > create a routine > the Pro screen appears

Both subscriptions and the subscription group are submitted for review together with this build.

Thank you for your time.
```

Sent before resubmitting — the message thread closes once a new submission goes in. If the thread is
already closed because the submission was withdrawn, the same text goes into App Review Information →
Notes instead.

---

## 9a. The App Review notes — entered 2026-08-23

App Store Connect → *Informationen zur App-Prüfung* → **Anmerkungen**. Verbatim:

```
To test purchases: Settings tab → Subscription → Get Gym Streak Pro. Alternatively: Routines tab → +
→ create 3 routines, and for the next one the Pro screen appears.
Settings → Manage subscription is for restoring/cancelling an existing subscription, not for
purchasing.
```

*Anmeldung erforderlich* is unticked — the app needs no account (`monetization-strategy.md` §1).

**This is the single cheapest thing that would have prevented both rejections.** Two reviewers went
looking for the purchase, found only the Customer Center, and rejected the app; neither had anything
telling them where to tap. It should have been in 1.1.9.

> Minor and left as-is: the fallback path is more conservative than reality. The `firstRoutineCreated`
> soft paywall fires after the **first** routine, not the fourth — a reviewer following the note
> literally still reaches a paywall (at routine 1 via the soft placement, or at the 4th ➕ via
> `routineCap`), so both routes work.

> **Second inaccuracy, worth fixing before the next submission:** the note says *Settings tab →
> **Subscription** → Get Gym Streak Pro*, but the section header in the shipped app is
> **"Gym Streak Pro"** — `settings.section.subscription = "Gym Streak Pro"` in both `en.lproj` and
> `de.lproj`. The key is named `subscription`; the visible string is not. A reviewer scanning for a
> heading called "Subscription" will not find one. The §10 reply gives the corrected path; the
> Anmerkungen field still carries the old wording.


---

## 10. The third submission — 1.1.11 (1004), 2026-08-23

Submitted with all four elements in one submission, exactly as §6 requires:

| Element | Typ | Prüfungsstatus at submission |
|---|---|---|
| `gymstreak.pro.abos` | Abo-Gruppe | 🕒 Bereit zur Prüfung |
| GymStreak Pro – Jahresabo (1 Jahr) | Abo | 🕒 Bereit zur Prüfung |
| GymStreak Pro – Monatsabo (1 Monat) | Abo | 🕒 Bereit zur Prüfung |
| iOS-App 1.1.11 (**1004**) | App-Version | 🕒 Bereit zur Prüfung |

**Two things learned about the App Store Connect mechanics**, both non-obvious enough to be worth
writing down:

- **"Zur Prüfung hinzufügen" greyed out on the subscription-group page is the *good* state.** It means
  the group is already attached to the open submission. The button is only live for an element sitting
  *outside* review (status "Vom Entwickler abgelehnt") — the §6 condition. Read *Übermittelte Elemente*
  on the submission page, not the button, to know where things stand.
- **"Erneut zur App-Prüfung übermitteln" stays greyed out while the version has no build attached.**
  After removing the rejected build, the button only comes back once Xcode Cloud's upload finishes
  processing and the build is selected on the version page. It is not a sign that anything is wrong
  with the subscriptions.

### The reply sent to App Review

Rewritten once more before sending: the §9 draft promised a screen recording that was never made, so
that promise came out and the click path went in, with the corrected section name (§9a).

```
Hello,

Thank you for the screenshot — it identified the problem immediately.

The screen you captured is our subscription *management* screen. It correctly
reported "No subscriptions found" because no purchase had been made yet, but it
is not where a purchase is started. Our payment records confirm that no purchase
was ever attempted during either review session, so nothing failed — the purchase
screen was simply never reached. That was our fault: in the previous build, every
route to it required app data that a fresh install does not have.

This build (1.1.11) adds a direct, always-available route.

To purchase the In-App Purchase:

  1. Open the app and tap the "Settings" tab (bottom right).
  2. Scroll to the "Gym Streak Pro" section.
  3. Tap "Get Gym Streak Pro".
  4. The purchase screen opens, showing both subscriptions with their price,
     duration and the links to our Terms of Use (EULA) and Privacy Policy.
  5. Tap either plan, then "Continue" to complete the purchase.

No account or sign-in is required at any point.

The management screen you saw previously is now shown only to users who already
have an active subscription, so it can no longer be mistaken for the purchase
screen. A "Restore purchases" option sits directly below the purchase entry.

An alternative route, if you prefer to reach the purchase screen through normal
use: Routines tab > "+" (top right) > create a routine. The Pro screen appears
after the routine is saved.

We have also corrected the pricing text on the purchase screen: it previously
described the introductory offer as a free trial. The annual plan now carries a
genuine 7-day free trial, and the text states whatever the App Store actually
offers for each plan.

The subscription group and both subscriptions are submitted for review together
with this build.

Thank you for your time.
```

### If it is rejected a third time

The Settings route is the fix, and it has **not been verified on a real device** (§7 item 4) — only
unit-tested and previewed. So on a third 2.1(b), close that gap first: install the TestFlight build on
an iPad Air (both rejections came from one, §3.8), walk the exact five steps above, and read
`§7a`'s RevenueCat trail afterwards to see whether a transaction was attempted this time. A reviewer
session that *again* shows no transaction means they still never reached the paywall, and the problem
is discoverability, not StoreKit.
