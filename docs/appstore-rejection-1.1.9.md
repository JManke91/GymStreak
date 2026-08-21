# App Store rejection — 1.1.9 (68), and the road back

**Living document.** It records why Apple rejected the monetization launch, everything the
investigation has established or ruled out, what has already been fixed, and what is still open.
Update it as things change; it is the file to re-read after a context reset.

**Status: 2026-08-21 — not yet resubmitted.** Five faults are known. Four are fixed; the fifth (the
subscriptions sitting outside review) is blocking. The purchase error is **narrowed but not solved**:
the transaction never reached RevenueCat (§3.4), so the whole RevenueCat integration is exonerated
and the failure lies in StoreKit or Apple's sandbox — where we have no further visibility until the
reviewer answers or the new failure logging catches it. Do not resubmit until §7's checklist is clean.

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

## 3. Fault 2 — the purchase error · **UNDIAGNOSED**

The one Apple actually complained about, and the one still open.

### 3.1 Ruled out

Each of these is a documented cause of this exact rejection elsewhere. None applies here.

| Checked | Evidence | Verdict |
|---|---|---|
| Paid Applications Agreement | Active since 2026-01-09 | ✅ not it |
| Tax forms | W-8BEN + U.S. Certificate of Foreign Status, both active since 2024-07-26 | ✅ not it |
| Banking | Account active, DE, EUR | ✅ not it |
| Product review state at review time | Both subscriptions were "In Prüfung", submitted with the binary | ✅ not it |
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

> **Worth revisiting later, unrelated to the rejection:** the default offering is named for a *sale*.
> `pro-subscription.md` §5j already flags that a contextual gate pointed at a sale offering shows
> different prices than the same user sees elsewhere. Confirm that is intended.

### 3.4 The reviewer's session — the purchase never reached RevenueCat

**Established 2026-08-21, and it is the single most useful fact so far.**

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

### 3.5 Why there was no evidence, and what now produces some

`ProPaywallView` wired `onPurchaseCompleted`, `onRestoreCompleted` and `onRequestedDismissal` — but
**not** `onPurchaseFailure` or `onRestoreFailure`. RevenueCat showed the reviewer its own alert and
the app logged nothing, so the rejection arrived undiagnosable.

**Fixed 2026-08-20.** Both handlers now log the RevenueCat `ErrorCode` *by name*
(`storeProblemError`, `productNotAvailableForPurchaseError`, `configurationError`, …), the domain and
code, the underlying `SKError`, and the message — subsystem `app.gymstreak.pro`, category `Paywall`.
Neither changes behaviour.

### 3.6 Still open

1. **RevenueCat In-App Purchase Key** — not yet confirmed present. Path: left sidebar (bottom)
   **Apps** → click the app *name* **Gym Streak (App Store)** in the table → on the app's own
   configuration page, the section/tab **"In-app purchase key configuration"** (it sits alongside
   *App Store Connect API* and *App Store Server Notifications*; ⌘K → "in-app purchase key" also
   finds it). Configured correctly it shows **"Valid credentials"** with every permission ticked.
   RevenueCat's docs: on SDK 5.x with StoreKit 2, *"transactions will fail to be recorded without
   this key being set."* The app configures `.with(storeKitVersion: .storeKit2)`.
2. **Sandbox transactions for the annual product.** Product catalog → Products → *GymStreak Pro –
   Jahresabo* → **Recent Transactions** → flip the **Sandbox** toggle on. The default view is
   production-only, which is why it reads "No transactions yet". This is the fastest way to see
   whether *any* sandbox purchase — the 2026-08-17 test or the reviewer's attempt — was ever recorded.
3. **The reviewer's customer record** (§3.4).
4. **Ask App Review for the error text.** Replying in App Store Connect and asking for a screenshot
   would collapse this section to one line. Apple's sandbox being down that day (`STORE_PROBLEM`) is
   a documented and entirely external possibility that no amount of configuration review can exclude.

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

## 6. Fault 5 — the subscriptions are withdrawn from review · **OPEN, BLOCKING**

Editing the group's localized display name (fixing "RideStreak Pro Zugriff" → "GymStreak Pro Zugriff")
required pulling the group out of the submission. The group and **both** products now read **"Vom
Entwickler abgelehnt"**.

**Apple reviews the app and its subscriptions together.** Resubmitting the binary while the products
sit outside review is a documented cause of precisely the 2.1(b) rejection we already have — the
reviewer reaches a paywall and cannot buy. **"Zur Prüfung hinzufügen" must be pressed and the products
must be back in review before, or with, the next binary submission.**

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
- [x] Xcode Cloud next build number → 1001
- [x] Subscription group display name: RideStreak → GymStreak
- [x] Privacy nutrition labels: Käufe / Einkaufsverlauf, App-Funktionalität + Analyse, unlinked, no tracking — **published 2026-08-21**
- [x] Terms of Use link in the **English** App Description
- [x] In-App Purchase Key confirmed valid in RevenueCat
- [x] Sandbox transactions checked — 2026-08-17 present, 2026-08-18 empty (§3.4)
- [x] Reviewer's customer record identified: `$RCA••••c6cc` (§3.4)
- [x] Documentation: `pro-subscription.md` §5k and §9.8, `settings-tab.md` §5a, TestFlight notes (en + de)

### Open — one ordered list

Diagnostics and fixes interleaved deliberately: the order is by payoff and latency, not by category.

| # | Do | Why | Where |
|---|---|---|---|
| 1 | **Reply to App Review** asking for the exact error text or a screenshot | Highest payoff of anything on this list, and the only item with a turnaround delay — start it first | App Store Connect → the rejection message |
| 2 | **"Zur Prüfung hinzufügen"** on the subscription group | Blocking. Apple reviews app and subscriptions together; submitting without them repeats the 2.1(b) rejection | App Store Connect → Abos → `gymstreak.pro.abos` |
| 3 | Sandbox purchase test **on an iPad** | The one configuration never exercised — and the reviewer's device | Needs the next TestFlight build |

Steps 2–5 of the original list closed on 2026-08-21; see §3.4 for what they established. Step 2
here is best done at submission time, with the build — but its status must be checked before pressing
submit either way.

### Before submitting

**Build 68 must never ship.** The fix for Fault 3 lives in the *build number*, not in code, so
resubmitting the existing binary would reintroduce it in full: 68 < `cutoffBuild`, every production
install reads as a Founder, nobody can be charged. A **new build is mandatory**, and Xcode Cloud will
stamp it 1001.

Ship it as **1.1.10** — `main` already carries `MARKETING_VERSION = 1.1.10` and
`CURRENT_PROJECT_VERSION = 1001`, the Settings Legal section and the failure logging are only in a new
binary anyway, and 1.1.9's record is tainted with a rejection. The Legal-section work is on
`feature/improvements` and has to reach `store-build` through the usual merge chain first.

Then:

1. Build number in App Store Connect ≥ 1000 (§4).
2. Subscriptions in review alongside the binary (§6) — they are currently **"Vom Entwickler
   abgelehnt"** and will not come back on their own.
3. Privacy labels published (§5) — done.
4. App Review Information → Notes: where the legal links are, and the 2.1(b) findings (§9).
5. Attach the screen recording Apple asked for.

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

Sent before resubmitting — the message thread closes once a new submission goes in. If the thread is
already closed because the submission was withdrawn, the same text goes into App Review Information →
Notes instead.

```
Hello,

Thank you for the detailed feedback. We have addressed both issues and have one question about the
second.

Guideline 3.1.2(c)

The app now includes functional links to the Terms of Use (Apple's Standard EULA) and to our privacy
policy in two places:

1. On the subscription purchase screen itself, directly below the purchase and restore buttons.
2. In Settings > Legal, reachable at any time without starting a purchase.

The purchase screen also states, for each option, the subscription name, its length, and its price,
including the price per month for the annual plan.

The metadata now carries both as well: the privacy policy URL is set in the Privacy Policy field, and
the Terms of Use link appears at the end of the App Description in every localisation.

Guideline 2.1(b)

We have investigated thoroughly and cannot reproduce the error, and we would be grateful for one
detail from you.

Our subscription provider's logs show that no purchase transaction was created during your review
session on 18 August - the app fetched the products and displayed the paywall with correct prices,
but no transaction reached us, successfully or otherwise. Sandbox purchases from our own testing on
17 August are recorded normally. On our side we have verified that the Paid Applications Agreement is
active, tax and banking information is complete, both subscriptions are priced in all territories
with complete localisations, and our App Store server credentials validate correctly.

Could you please share the exact error message you saw, or a screenshot of it? Without it we cannot
tell whether the failure was in the purchase sheet, the sandbox account, or a transient App Store
issue, and we would rather fix the cause than guess at it.

We are submitting an updated build that includes the changes above along with additional error
logging for the purchase flow.

Thank you for your time.
```
