# App Store Connect — pending actions

**The execution artefact.** Read this with App Store Connect open in the other window; every block
below is copy-paste ready and already character-counted, so nothing has to be reassembled or
re-counted by hand.

**It is deliberately not the derivation.** *Why* each token was chosen, what was dropped and why,
and the indexing rules that constrain every field live in
[`app-store-subtitle-keywords.md`](./app-store-subtitle-keywords.md). Do not restate them here, and
do not change a string here without changing it there — that document is the source of truth for the
reasoning, this one is the source of truth for *what to type*.

| | |
| --- | --- |
| **App** | GymStreak, Apple ID `6756426105` |
| **Change A — keyword rotation** (§2) | ✅ **entered 2026-09-06**, rides **1.1.16** — both keyword fields pasted and the version submitted (§3). **Not live until 1.1.16 is released**; the measurement clock in §5 starts then, not now. |
| **Change B — en-GB / en-AU localizations** (§7) | ✅ **entered 2026-09-09** — both localizations created, both keyword fields pasted, version submitted. **Not live until that version is released**; the §7.6 clock starts then. |

> **Subtitle and Keyword edits require a version submission.** Neither field can be changed on a live
> version; both are attached to the *next* version's App Store page. Enter them on the 1.1.16 page
> before submitting it. (Promotional Text is the only indexed-adjacent field that is editable any
> time — see `app-store-subtitle-keywords.md` §1.)

> **Do not touch 1.1.15.** It was already *Ready for Review* on 2026-09-06. These edits ride 1.1.16.

---

## 1. What is changing

**Change A — the keyword rotation** (done):

| Field | Locale | Action |
| --- | --- | --- |
| Keyword Field | en-US | **Replace** — §2.1 |
| Keyword Field | de-DE | **Replace** — §2.2 |
| Everything else | both | **Leave alone** — §4 |

One field, two locales. That is the whole of Change A.

**Change B — two new localizations** (pending, §7):

| Field | Locale | Action |
| --- | --- | --- |
| Whole localization | **en-GB**, **en-AU** | **Add** — §7.3, §7.4 |
| Keyword Field | en-GB | New 98-character string, **not** a clone of en-US — §7.4 |
| Keyword Field | en-AU | A **different** 98-character string, disjoint from en-GB — §7.4 |
| Description | en-GB, en-AU | **Clone** from en-US — one of only two fields that does not prefill — §7.4 |
| App Name, Subtitle, Promotional Text | en-GB, en-AU | **Leave the prefilled en-US values** — §7.4 |
| Screenshots | en-GB, en-AU | **Nothing to do** — Apple inherits them from en-US. Never run the `fastlane` lane — §7.2 |
| en-US, de-DE | — | **Leave alone** |

---

## 2. The strings

### Click path (identical for both locales)

1. **App Store Connect** → **Apps** → **GymStreak**
2. Left sidebar → the **1.1.16** entry under *iOS App* (the editable version, not the live one)
3. Language picker at the top-right of the *App Information / What's New* pane → choose the locale
4. Scroll to **Keywords** (directly under *Promotional Text* and *Description*)
5. Select the entire existing value and replace it — do **not** append
6. **Save** (top right). Repeat for the second locale before submitting.

### 2.1 en-US — Keyword Field · 99/100 characters

```
apple,watch,offline,private,superset,progressive,overload,lifting,weight,routine,calendar,1rm,ai,pr
```

Replaces the previous 98-character set (`lifting,weight,bodybuilding,…,1rm,ai`).

### 2.2 de-DE — Keyword Field · 99/100 characters

```
krafttraining,trainingstagebuch,muskelaufbau,superset,progressive,overload,offline,watch,ki,1rm,app
```

Replaces the previous 100-character set (`krafttraining,muskelaufbau,bodybuilding,…,ki,timer`).

**Paste check, both locales:** no spaces anywhere, commas only, and the field must not wrap onto a
second line. If App Store Connect reports over 100 characters, an editor has substituted a Unicode
character — retype the commas.

---

## 3. Verification once saved

Completed 2026-09-06.

- [x] en-US keyword field reads exactly the §2.1 string
- [x] de-DE keyword field reads exactly the §2.2 string
- [x] Both subtitles still read as in §4 below — confirm visually, they are easy to edit by accident
- [x] 1.1.16 submitted (the fields do not go live until the version does)

---

## 4. What is deliberately NOT changing

Stated explicitly so a reader does not mistake any of it for an omission.

| Field | Value stays | Why |
| --- | --- | --- |
| **Subtitle en-US** | `Strength Training Plan & Log` (28/30) | **The subtitle is the field that converts.** It shipped 2026-08-25 in the ASO pass that **doubled** page-view→download conversion (`acquisition-strategy.md` §1). The keyword field is invisible and cannot affect conversion at all — it only feeds ranking. Rotating the invisible field is pure upside; rewriting the visible one would bet a measured +110% conversion gain against unproven niche terms. |
| **Subtitle de-DE** | `Workout Tracker, Trainingsplan` (30/30) | Same reasoning. It also carries all three German head tokens, and the new keyword field is derived *assuming* it keeps them. |
| **App Name** | both locales | The exclusion lists for both keyword fields are computed from it (`app-store-subtitle-keywords.md` §2). Changing it invalidates both strings. |
| **Description** | both locales | Not indexed. It converts, and it currently converts well. |
| **Promotional Text** | both locales | Editable any time without a submission, so it is never blocked on a release — rotate it on its own schedule. |
| **Screenshots, category, age rating, IAP names** | — | Out of scope for this change. |

**This table is about en-US and de-DE.** The en-GB and en-AU localizations added in §7 clone the
en-US App Name, Subtitle, Description and Promotional Text — so "unchanged" there means *identical
to the values above*, and the reasons are restated per field in §7.4.

`acquisition-strategy.md` §4.3 originally said to rework "Subtitle + Keyword field" together. That
instruction is superseded: the two fields carry opposite risk, and only the keyword half moves here.

---

## 5. What to check afterwards, and when

| When | Where | What | Baseline |
| --- | --- | --- | --- |
| Weekly from 1.1.16 going live | ASC → **Akquise** | **Impressionen/day** — the metric this change exists to move | **~13/day** (measured 2026-09-06); first milestone **50** (`acquisition-strategy.md` §6) |
| Weekly | ASC → Akquise | Erstmalige Downloads/day | ~1.2/day → milestone 5 |
| **~4 weeks after 1.1.16 is live** | ASC → **Analytics → Search Terms** | Which of the new tokens actually returned impressions | No prior report exists — the 2026-08-25 set never reached four weeks before being rotated |

Once Change B is entered, read the **Impressionen** row **broken out by territory** as well — §7.6
covers what the UK and Australian storefronts can and cannot tell you, and why the search-term
report, not this row, is what decides the step-2 locales.

**The search-term report is the input to the next rotation**, and it is the first real evidence this
project will have about its own keywords. Read it against the swap benches in
`app-store-subtitle-keywords.md` §4.2 and §5.2, then rotate the weakest tokens — do not rotate on a
hunch before it arrives.

Expect impressions to move slowly and noisily: re-indexing after a version goes live is not instant,
and at 13 impressions/day a single good day looks like a trend. Judge it over weeks, not days.

---

## 6. Once 1.1.16 is live

Nothing further to enter — the work becomes **reading**, on the §5 schedule. Two reminders that are
easy to get wrong:

- **Do not re-edit either keyword field before the search-term report exists.** The whole point of
  this rotation was to buy the first piece of real evidence this app has ever had about its own
  keywords; changing the fields again beforehand destroys the experiment. `app-store-subtitle-keywords.md`
  §8 is the binding rule.
- **A rejection on 2.3.7 grounds, if it happens, is about `apple`.** The fallback is written down —
  drop `apple`, keep `watch`, move the 6 characters to `split`, and record it in
  `app-store-subtitle-keywords.md` §4.2a so it is never re-tried. Nothing else in either string is
  exposed.

---

## 7. en-GB and en-AU localizations — pending

**Status: ✅ entered in App Store Connect 2026-09-09** (strings derived 2026-09-07). What remains is
reading the result — §7.6. Two new metadata localizations — **English (U.K.)** and **English (Australia)**. No app translation is
involved: the UI these users get is English either way, which is why these two locales carry none of
the one-star risk that makes es-MX/es-ES/fr/it/pt-BR a separate decision
(`acquisition-strategy.md` §4.2).

**What this actually buys — read this before deciding it is worth doing.** It is **not** "two more
keyword fields on top of what we have". The UK and Australian storefronts serve the **en-US**
metadata today (verified: `itunes.apple.com/lookup?id=6756426105&country=gb` returns the en-US name
and description). Adding a localization *replaces* that fallback rather than adding to it, so:

- **en-GB is a swap**, and it is not a UK-only swap: English (U.K.) is Apple's documented default for
  the large majority of countries — Ireland, India, Singapore, South Africa, Hong Kong and a
  hundred-plus more. All of them serve en-US today and will serve **en-GB** the moment it exists.
- **en-AU is the one genuine addition**: Apple's *App Store localizations* reference lists Australia
  and New Zealand as `English (Australia)` **plus `English (U.K.)`** as an additional supported
  language, while the **UK and Ireland have no second language at all**. So those two storefronts end
  up with two independent 100-character fields and the UK keeps one — which is why en-GB carries the
  strong general set and en-AU the complement.
- **Cloning the en-US keyword string into either field would therefore buy nothing at all.** The
  entire gain is the delta — which is why the en-GB field swaps 22 characters against en-US, and why
  the two fields below **share not one word with each other**. (Overlap with en-US no longer matters
  in these storefronts: once the localizations exist, en-US is not indexed there.)

Full mechanics, confidence levels and per-token derivation: `app-store-subtitle-keywords.md` **§6**.

### 7.1 Which version it rides — resolved

**Resolved 2026-09-09:** both localizations were entered on the version page that was editable at the
time and submitted with it. The reasoning is kept below because it recurs every time a metadata
change is scheduled.

**Adding a localization is a metadata change, so it is bound to a version's App Store page** exactly
like the Subtitle and Keyword edits in §2. It cannot be done on a live version.

| If the App Store Connect state is… | Do this |
| --- | --- |
| **1.1.16 still editable** (*Prepare for Submission*) | Add both localizations there. Same submission as §2, nothing else to decide. |
| **1.1.16 already submitted** (*Waiting for Review* / *In Review*) | **Leave 1.1.16 alone.** Put the localizations on the **next** version page (1.1.17). |

**Recommendation: do not disturb 1.1.16 to fit this in.** Pulling a submitted version out of review
restarts the queue, and 1.1.16 carries the keyword rotation — the better-evidenced half of this pass,
and the one that has been waiting on a release since 2026-09-06. The release cadence makes waiting
cheap: 1.1.14 went live 2026-09-04 and 1.1.16 was submitted two days later, so the next editable
version page opens within days. These two fields have no deadline; the rotation does.

### 7.2 Screenshots — answered, and the answer is "nothing to do"

This is the question that would otherwise stop the task halfway, so it is settled here rather than in
a footnote. **App Store Connect Help**, *Localize app information*, verbatim:

> "When you add a language to your app, screenshots and the properties for the new language default
> to those of the primary language, **except for the description and keywords**."

So the new localizations inherit the six live en-US screenshots automatically, submission is **not**
blocked, and **no screenshot work is required** — nor is any screenshot *upload*.

> **Do not add `en-GB`/`en-AU` to `fastlane/Snapfile`, and do not run
> `fastlane upload_screenshots`.**

That lane is `deliver(overwrite_screenshots: true, screenshots_path: "./fastlane/screenshots")`, and
`fastlane/screenshots/` currently holds exactly **one** PNG per language
(`iPhone 17 Pro Max-01-Routines-List-dark.png`, 1320×2868) while the live listing has **six** at
1242×2688 — `Routines`, `Exercises`, `Create_Exercise`, `Progress`, `History`, `Weight_adjustment`
(verified 2026-09-07). Running the lane today would **replace six live screenshots with one**, in
every locale it touches. The repository cannot currently reproduce the live set at all, so
"regenerate for the new locales" is not the cheap option — it is a rebuild of the whole set, to
produce pictures identical to the ones already there, of an English UI, for two English-speaking
storefronts.

**One consequence worth recording, because it bites later.** Apple calls inherited screenshots
*"derived from another localization"*, and they do **not** count as uploaded ones: if the app's
**primary language** is ever changed, App Store Connect requires real screenshots to have been
uploaded *and approved* for the new primary language first. That is the cause of the recurring
"missing screenshots" submission errors on the developer forums. It does not affect this change; it
affects any future decision to make en-GB the primary language — and note that Apple adds the same
requirement **per custom product page**, so it also interacts with lever #8 in
`acquisition-strategy.md`.

**If real files are ever needed**, recover the exact live images rather than regenerating them — they
are public, and the full-resolution originals come back by rewriting the thumbnail suffix. Tested
2026-09-07:

```bash
mkdir -p /tmp/gs-shots && cd /tmp/gs-shots
curl -s "https://itunes.apple.com/lookup?id=6756426105&country=us" \
  | python3 -c 'import json,sys,re
for u in json.load(sys.stdin)["results"][0]["screenshotUrls"]:
    print(re.sub(r"/320x480bb\.jpg$", "/1242x2688bb.png", u))' \
  | while read u; do curl -s -O "$u" ; done
# → six 1242×2688 PNGs
```

### 7.3 Click path — *adding* a localization is not the same as editing one

1. **App Store Connect** → **Apps** → **GymStreak**
2. Left sidebar → the editable version page under *iOS App* (§7.1 decides which one)
3. Language picker at the top of the page → **Add Language** at the bottom of the dropdown. This is
   the step that differs from §2: editing an existing locale uses the same picker, but only *Add
   Language* creates one
4. Choose **English (U.K.)**
5. **Only two fields need typing: Description and Keywords.** Everything else — App Name, Subtitle,
   Promotional Text, What's New, screenshots — arrives **prefilled from en-US** (§7.2's quote).
   Leave the prefilled values exactly as they are; that is the clone, and it is deliberate (§7.4)
6. Check the **App Information** pane's language picker as well as the version page's — the App Name
   and Subtitle live there, and both panes should now list the new language
7. **Save** (top right)
8. Repeat from step 3 for **English (Australia)** — same Description, **a different keyword string**
9. Submit the version. A new localization does not go live until the version does

### 7.4 The fields

The Description is the same for both locales. **The two keyword fields are different from each other
on purpose** — Australia and New Zealand index both, so a token repeated across them would buy a slot
the other one already owns (`app-store-subtitle-keywords.md` §6.1, §6.3).

#### Keyword Field — en-GB · 98/100 characters

```
progressive,overload,superset,calendar,routine,planner,journal,progress,lifting,weight,watch,ai,pr
```

The **strong standalone set**, because most of the storefronts en-GB serves index nothing else.
Against en-US it swaps 22 characters that are dead in these storefronts — `apple`, `offline`,
`private`, `1rm` — for 22 that are live: `planner`, `journal`, `progress`. Derivation: §6.2 there.

#### Keyword Field — en-AU · 98/100 characters

```
hypertrophy,timer,rest,coach,program,split,diary,exercise,offline,volume,powerlifting,1rm,dumbbell
```

The **complement**: zero overlap with en-GB, so in Australia and New Zealand the two fields together
index 26 distinct tokens instead of 13. `program` rather than `programme` is the one measured
Australian spelling difference. Derivation: §6.3 there.

**Paste check, both fields:** no spaces anywhere, commas only, and neither may wrap to a second line.
If App Store Connect reports over 100 characters, an editor has substituted a Unicode character —
retype the commas.

#### Description — copy from App Store Connect, not from the docs

**Select the entire en-US Description inside App Store Connect, copy it, switch the language picker
to the new localization, and paste it unchanged.** It is one of only two fields that does not
prefill, so it has to be entered for both locales.

⚠️ **Do not paste from `app-store-description.md`.** That document deliberately stages copy that is
**not yet published** — the Apple Calendar sync paragraph must only go live in the release that ships
the feature (see its header note). Pasting the document into a new localization would advertise a
feature the installed app does not have. App Store Connect's own en-US field is the live truth; the
document is the staging area.

Cloning is right here for a reason that costs nothing: the Description is **not indexed**, so it
converts but never ranks. A spelling pass was run anyway — **`analyzes` is the only Americanism in
all 3,898 characters**, and it stays (§6.5 has the reasoning).

#### App Name, Subtitle, Promotional Text, What's New — leave the prefilled values

| Field | Prefilled value to leave alone |
| --- | --- |
| App Name | `GymStreak – Workout Tracker` (27 chars, **en dash**) |
| Subtitle | `Strength Training Plan & Log` (28/30) |
| Promotional Text | whatever en-US currently reads |
| What's New | whatever en-US currently reads |

Both keyword fields' exclusion lists are computed from the App Name and Subtitle, so changing either
one invalidates both strings above. The Subtitle is also **the field that converts** — the pass it
belonged to doubled page-view→download conversion — which is why no locale varies it (§4).

### 7.5 Verify once saved

Completed 2026-09-09 (confirmed by the user; the agent has no App Store Connect access).

- [x] The version page **and** the App Information pane both list **English (U.K.)** and
      **English (Australia)**
- [x] en-GB keyword field reads exactly the §7.4 en-GB string (98 characters, no spaces)
- [x] en-AU keyword field reads exactly the §7.4 en-AU string (98 characters, no spaces)
- [x] **The two keyword fields share no word.** If they look similar, one was pasted twice
- [x] Both Descriptions match the en-US field **as it reads in App Store Connect**, and contain no
      calendar-sync paragraph unless en-US already ships it
- [x] App Name in both reads `GymStreak – Workout Tracker` with an **en dash**; Subtitle in both
      reads `Strength Training Plan & Log`
- [x] Both localizations show **six** screenshots (inherited — nothing was uploaded)
- [x] **en-US and de-DE are untouched** — the language picker makes it easy to edit the wrong locale
- [x] Version submitted

### 7.6 What to watch, and the decision it feeds

| When | Where | What |
| --- | --- | --- |
| Weekly, from the carrying version going live | ASC → **Akquise**, broken out by **territory** | Impressionen for **United Kingdom**, **Australia** and **New Zealand** |
| Same view | ASC → Akquise → territory | The **rest of the en-GB fallback territories** (Ireland, India, Singapore, South Africa, …) — they switched from the en-US field to the en-GB one, so they are part of this experiment whether or not that was the intent |
| ~4 weeks after the version is live | ASC → **Analytics → Search Terms** | Whether `planner`, `journal` and `progress` returned anything — and whether `progress`/`planner` were silently deduplicated against `progressive`/`plan` (§6.2's stated risk) |

**One falsifiable prediction, worth writing down before the data arrives.** The en-GB field drops
`apple`, `offline`, `private` and `1rm` across every territory that previously served en-US. If
impressions in those territories **fall**, those four tokens were doing work that the GB/AU
autocomplete probes could not see, and the fix is to move them back (§6.6's benches say which
characters to spend). If impressions hold or rise, the probe method transfers between storefronts and
the same approach can be used for the step-2 locales with more confidence.

**Calibrate the expectation before reading any of it.** The UK is ~3% of the customer base and
Australia does not appear in the geography split at all (`acquisition-strategy.md` §1, n=100).
Against a total of ~13 impressions/day, the UK storefront is on the order of **half an impression a
day**. No weekly reading of that row will be statistically meaningful for months. That is not an
argument against the change — it is free, reversible and risk-free — but it **is** an argument against
treating the per-storefront Impressionen row as the evidence that decides the step-2 locales, and
against `acquisition-strategy.md` §3's framing of this lever as the biggest mechanical win available.

**What actually decides step 2** (es-MX, es-ES, fr, it, pt-BR — Phase C, `acquisition-strategy.md`
§5): the **search-term report**, which reports per storefront and will show whether tokens bought in
a *metadata-only* localization return impressions at all. Those locales carry a real one-star risk —
a user downloading in a language the app does not speak — and §10's guardrails put the App Store
rating above revenue, so they need evidence that the mechanism works, not just a plausible mechanism.
en-GB and en-AU are the risk-free way to buy that evidence.

---

## 8. Related pending work

- **The next keyword rotation** — blocked, deliberately, on the first search-term report (~4 weeks
  after 1.1.16 is live). `app-store-subtitle-keywords.md` §8 is the binding rule; the swap benches
  in its §4.2, §5.2 and §6.5 are what the report gets read against.
- **Step-2 metadata locales** (es-MX, es-ES, fr, it, pt-BR) — Phase C in `acquisition-strategy.md`
  §5, and gated on the evidence described in §7.6. They are **not** a repeat of §7: they carry a
  one-star risk en-GB/en-AU do not, and they need a decision about how plainly the localized
  description states which languages the UI actually speaks.
- **Nothing else in App Store Connect is pending.** Both subtitles, both App Names, both existing
  descriptions and the screenshots stay as they are (§4, §7.2).
