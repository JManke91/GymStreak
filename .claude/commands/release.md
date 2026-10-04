# Full Release Pipeline

Release whatever has landed on `main` (via merged PRs) all the way to `store-build` in three sequential steps:

1. Sync `main` with `origin/main` — this is the release starting point
2. `main` → `testflight-beta`
3. `testflight-beta` → `store-build`, then bump the version on `main`

Each phase must complete successfully before the next begins. If any phase fails, stop immediately and report the failure — do not proceed to the next phase.

This is the default release path for the worktree + PR workflow. To release a long-lived feature branch by merging it into `main` first, use `/release-from-branch` instead.

---

## Pre-flight checks

Before doing anything else:

1. Run `git status` — if there are uncommitted changes, **stop and inform the user**. Do not stash or discard anything automatically.
2. Run `git rev-parse --abbrev-ref HEAD` to capture `<start-branch>` (the branch this checkout is on — `main`, or the worktree's own branch). The pipeline checks out `main`, `testflight-beta` and `store-build` in **this** checkout and returns to `<start-branch>` at the end.
3. Run `git worktree list`. If `main`, `testflight-beta` or `store-build` is checked out in **another** worktree, git will refuse to check it out here — **stop and tell the user** which worktree holds it, so they can switch that checkout away or run `/release` from there.
4. `git fetch origin`, then report what is being released: `git log --oneline origin/store-build..origin/main` (the commits/PRs on `main` not yet in the store build). If that list is empty, **stop and tell the user** there is nothing to release.
5. Inform the user of the plan:
   > "Starting release pipeline from `main` (`<short-sha>`): `main` → `testflight-beta` → `store-build`, then version bump on `main`."

---

## Phase 1 — Sync `main`

1. `git checkout main && git pull origin main`
2. Verify `git rev-parse main` equals `git rev-parse origin/main`. If local `main` has commits that are not on `origin/main` (`git log --oneline origin/main..main` is non-empty), **stop and tell the user** — the release must start from exactly what is on origin, never from unpushed local commits.

Announce: **"Phase 1 complete — `main` is at `<short-sha>` and matches `origin/main`."**
If this phase fails for any reason, stop and report the error.

---

## Phase 2 — Merge `main` into `testflight-beta`

Follow all steps from the **merge-main-to-testflight** command:

1. `git checkout testflight-beta && git pull origin testflight-beta`
2. `git merge main -X theirs -m "Merge main into testflight-beta"`
3. Verify `git status` shows no remaining conflicts. If conflicts remain, resolve each with `git checkout --theirs <file> && git add <file>`, then `git commit --no-edit`.
4. `git push origin testflight-beta`
5. `git checkout main`

Announce: **"Phase 2 complete — `main` merged into `testflight-beta`."**
If this phase fails for any reason, stop and report the error.

---

## Phase 3 — Merge `testflight-beta` into `store-build` and bump version

Follow all steps from the **merge-testflight-to-store** command:

### Part A: Merge

1. `git checkout store-build && git pull origin store-build`
2. `git merge testflight-beta -X theirs -m "Merge testflight-beta into store-build"`
3. Verify `git status` shows no remaining conflicts. If conflicts remain, resolve each with `git checkout --theirs <file> && git add <file>`, then `git commit --no-edit`.
4. `git push origin store-build`

### Part B: Version bump on main

5. `git checkout main && git pull origin main`
6. Read `MARKETING_VERSION` from `GymStreak.xcodeproj/project.pbxproj`. Increment the patch component by 1 (e.g., `1.1.2` → `1.1.3`). Replace **all 6** production occurrences (3 targets × 2 configurations: GymStreak, GymStreakWidgetsExtension, GymStreakWatch Watch App — each for Debug and Release). **Do not** change the version in test targets (`GymStreakUITests`, `GymStreakWatchUITests` — these sit at their own value, e.g. `1.0`). The **current** value is `<old-version>` — this is the version being shipped to the store, and the version the App Store notes below describe.
6b. **Bump the build number in the same edit.** Read `CURRENT_PROJECT_VERSION` from the same file and increment it by 1 (e.g. `1000` → `1001`). Replace the **same 6** production occurrences and no others — the test targets (`GymStreakTests`, `GymStreakUITests`, `GymStreakWatchTests`) keep `CURRENT_PROJECT_VERSION = 1`. Capture the result as `<new-build>` for the final report.

   > **This step is load-bearing and must never be skipped.** The Founder grant (`docs/pro-subscription.md`, `docs/monetization-strategy.md` §7.1) grants Pro permanently and free to every install whose `AppTransaction.originalAppVersion` is below `FounderStatusService.cutoffBuild` (`1000`). Before the monetization release every shipped build was `1`, which is what makes the grant work for existing users. If a release ever ships with a build number below the cutoff again, **every new paying user is silently granted Founder forever** — the app looks fine and the bug only surfaces as missing revenue. If the current value is somehow below `1000`, stop and tell the user rather than guessing.
7. **Generate App Store release notes** for `<old-version>` — do this **before** clearing the WhatToTest files, while they still hold this version's notes. See [App Store release notes](#app-store-release-notes) below for how to distill and where to write them.
7b. **Refresh the marketing copy (Werbetexte)** for `<old-version>` — also **before** the WhatToTest files are cleared, since they are the input. See [Marketing copy (Werbetexte)](#marketing-copy-werbetexte) below. This step always produces `AppStore/Marketing.<old-version>.md`; it may also edit files under `docs/marketing/`.
8. Archive `TestFlight/WhatToTest.en-US.txt` into `CHANGELOG.md` under a new `## [<old-version>] - <YYYY-MM-DD>` heading with `### Added / Improved / Fixed` subsections (categorize each bullet by content). If `CHANGELOG.md` does not exist, create it with a `# Changelog` header. Clear both WhatToTest files afterward.
9. `git add GymStreak.xcodeproj/project.pbxproj CHANGELOG.md TestFlight/WhatToTest.en-US.txt TestFlight/WhatToTest.de-DE.txt AppStore/ReleaseNotes.<old-version>.md AppStore/Marketing.<old-version>.md` — plus any file under `docs/marketing/` that step 7b actually modified (`git add docs/marketing/` is fine; it is a no-op when nothing changed).
10. `git commit -m "Bump version to <new-version> for next release cycle"`
11. `git push origin main`

Announce: **"Phase 3 complete — `testflight-beta` merged into `store-build`, version bumped to `<new-version>` (build `<new-build>`)."**

---

## Phase 4 — Return to the starting branch

Only runs after Phases 1–3 have all completed. If `<start-branch>` is not `main`, run `git checkout <start-branch>` so `main` is not left checked out in this worktree (which would block other worktrees from checking it out). If `<start-branch>` is `main`, there is nothing to do.

---

## App Store release notes

The App Store "What's New" text is generated from the version being shipped to the store — i.e. `<old-version>`, whose full notes live in `TestFlight/WhatToTest.en-US.txt` and `TestFlight/WhatToTest.de-DE.txt`. **Generate this in Phase 3 Part B, step 7, before those files are cleared.**

The WhatToTest files are the developer/tester-facing long form — detailed, exhaustive, and often jargon-heavy. The App Store notes are the **end-user-facing short form**: fewer items, benefit-led, and skimmable. Do not copy WhatToTest verbatim.

### How to distill

1. Read both `TestFlight/WhatToTest.en-US.txt` (source for English) and `TestFlight/WhatToTest.de-DE.txt` (source for German).
2. If a WhatToTest file is empty, there is nothing to ship for this version — skip App Store notes generation and note that in the final report.
3. Condense into concise, user-facing "What's New" copy per language, following these rules:
   - **Lead with the biggest, most exciting user-visible features.** A workout-tracking user cares about "swap in alternative exercises mid-workout" or "your Apple Watch now shows planned sets," not internal refactors or edge-case fixes.
   - **Merge granular bullets into themes.** Several WhatToTest lines about the same feature (e.g. multiple watch-timer tweaks) become one clear highlight.
   - **Drop developer jargon and minor internal fixes.** Keep only fixes users actually noticed/reported. Omit anything not user-facing.
   - **Aim for ~4–7 short bullets** (a one-line intro sentence is optional). Keep the tone friendly and active ("You can now…", "New:…"). Comfortably under the App Store's 4,000-character limit.
   - **No emojis.** App Store release notes do not accept emoji — use plain text only. Use a simple hyphen (`-`) or bullet (`•`) as the list marker, never an emoji.
   - **German is a genuine translation**, distilled from `WhatToTest.de-DE.txt` — not a machine echo of the English. Match the app's existing German voice.
4. Write the result to `AppStore/ReleaseNotes.<old-version>.md` (create the `AppStore/` folder if it does not exist) using this structure:

   ```markdown
   # App Store Release Notes — v<old-version>

   ## English (en-US)

   <distilled English "What's New" text>

   ## German (de-DE)

   <distilled German "What's New" text>
   ```

5. This file is a per-version record (like `CHANGELOG.md`) and is committed with the version bump — it is included in the `git add` in Phase 3 Part B, step 9.

---

## Marketing copy (Werbetexte)

The App Store listing has four copy assets, all maintained in `docs/marketing/`. They do **not** all
get rewritten every release — they differ in how expensive a mistake is and in what is allowed to
trigger a change:

| Asset | Doc | Per release |
|---|---|---|
| **Promotional Text** (170 chars, en-US + de-DE) | `app-store-promotional-text.md`, superseded set in `app-store-subtitle-keywords.md` §4.3 / §5.3 | **Regenerate.** Editable without a build, so a refresh costs nothing and a stale line is the most likely thing to be pasted back by mistake. |
| **Description** (4,000 chars, en-US + de-DE) | `app-store-description.md` | **Diff only.** Propose a targeted edit when this release changes what the app may claim; never rewrite wholesale. |
| **Subtitle** (30 chars) | `app-store-subtitle-keywords.md` §4.1 / §5.1 | **Flag only.** The subtitle drove a measured +110% page-view→download conversion (§8) — do not experiment with it inside a release pipeline. |
| **Keyword Field** (100 chars ×4 storefronts) | `app-store-subtitle-keywords.md` §4.2 / §5.2 / §6.2 / §6.3 | **Flag only.** Rotation is driven by the search-term report and by App Name changes (§8), not by release cadence. |

**The generated copy is a proposal, not a publication.** Nothing here reaches App Store Connect
automatically; the user pastes it. Never edit `docs/marketing/` beyond what the rules below
authorize, and never silently overwrite a live string.

### Inputs

1. `TestFlight/WhatToTest.en-US.txt` and `.de-DE.txt` — what shipped in `<old-version>`.
2. `docs/marketing/app-store-subtitle-keywords.md` §3 ("Feature basis — what the copy is allowed to
   claim"), §4, §5 — the current live strings and their character counts.
3. `docs/marketing/app-store-description.md` and `app-store-promotional-text.md` — current copy plus
   their hold-gates and Pro-claim notes.
4. `Domain/Models/Pro/ProFeatureCaps.swift` and `docs/pro-subscription.md` — the free-vs-Pro
   boundary. A cap change can silently make a live claim like "Track unlimited, free" **false**;
   that is a correctness bug in the listing, not a copy preference.

### Step 1 — Resolve hold-gates (always, even when WhatToTest is empty)

Several variants in the marketing docs are written but held behind "paste only once the feature is
live on the App Store" (e.g. the Apple Calendar sync copy in `app-store-description.md` and the
calendar variant in `app-store-promotional-text.md`). `<old-version>` is the build going to the
store **now**, so a hold whose feature is in this build is satisfied by this release.

For each hold-gate found: state whether this release releases it, and if so, say the held copy is
now the one to paste and update the note in the doc from "hold until live" to "live as of
v`<old-version>`". If a hold is *not* released, leave it and say why.

### Step 2 — Promotional Text (regenerate)

Write a fresh recommended line per locale, leading with this release's strongest user-visible
feature where one exists, otherwise restating the strongest standing differentiator.

- **Hard limit 170 characters.** Verify each with `printf '%s' '<text>' | wc -m` and report the count
  as `N/170` — a rejected paste is the one failure mode this step exists to prevent.
- German is a genuine translation in the app's German voice, not a machine echo (same rule as the
  release notes).
- No emoji. No claim that §3's feature basis does not support.
- Keep the no-**account** promise if used; never reintroduce a no-**subscription** claim (removed at
  the Pro launch — `app-store-promotional-text.md`).
- Carry the previously live line through as "current" so the user can see what is being replaced.

### Step 3 — Description (diff only)

Decide whether `<old-version>` changed what the description may claim: a new user-facing capability
worth a section, a hold-gate released by step 1, or a claim that a cap/pricing change made false.

- **No → say "no change needed" in one line and move on.** Do not restate the description.
- **Yes → propose the smallest edit that works**: quote the exact paragraph to replace or the
  insertion point, give the new text per locale, and state the reason.
- **Re-measure both locales** with the method in `app-store-description.md`
  (`sed -n '<block>p' | wc -m`) and report `N/4000` each. **German had only 16 characters of
  headroom at the last measurement** — if a proposed German edit does not fit, say so and propose
  the sentence to trim rather than shipping an over-length block.
- Note that a description change **rides a version submission**, so it lands with `<new-version>`'s
  binary, not today's.

### Step 4 — Subtitle & Keyword Field (flag only)

Do not rewrite these. Report one of:

- **"No action"** — the App Name, subtitle and feature basis are unchanged and no search-term report
  is due.
- **A flag with the reason**, when a trigger from §8 fired: the App Name changed (which invalidates
  **all three** English keyword fields at once, not just en-US), a cap change made a claim in §3
  stale, or the first search-term report is now available (~4 weeks after 1.1.16 went live) and is
  the input to the next rotation.

A flag ends with "rotate deliberately in a separate pass, against the swap benches in §4.2 / §5.2 /
§6.5" — never with generated replacement strings.

### Step 5 — Write the per-version record

Write everything to `AppStore/Marketing.<old-version>.md` (same folder and lifecycle as
`ReleaseNotes.<old-version>.md`), using this structure:

```markdown
# App Store Marketing Copy — v<old-version>

## Hold-gates resolved
<one line per gate, or "none">

## Promotional Text (paste now — no build required)

### English (en-US) — N/170
<text>

### German (de-DE) — N/170
<text>

Previously live: <old line per locale>

## Description — <no change needed | proposed edit>
<targeted diff per locale with char counts, or the one-line no-op>

## Subtitle & Keyword Field — <no action | flag>
<reason>
```

Then update the source docs in `docs/marketing/` **only** where this release made them factually
wrong: a resolved hold-gate's note, a claim invalidated by a cap change, and the new promotional
text recorded as the current recommendation with its date and version. Leave the rationale,
evidence and swap-bench sections alone — they are the reasoning history, not release state.

If both WhatToTest files were empty, skip steps 2–4, still run step 1, and note in the final report
that marketing copy was skipped because nothing shipped.

---

## Final report

Summarize the entire pipeline:
- The `main` commit the release started from, and the list of commits/PRs it shipped (from pre-flight step 4)
- Commits merged in each phase
- Any conflicts that were auto-resolved (list affected files per phase)
- Old version → new version
- **Old build number → new build number** (`CURRENT_PROJECT_VERSION`), stated explicitly — this is the Founder-grant cutoff guard from Phase 3 Part B step 6b
- Confirmation that WhatToTest files were archived and cleared
- Confirmation that `AppStore/ReleaseNotes.<old-version>.md` and `AppStore/Marketing.<old-version>.md` were written (or that they were skipped because WhatToTest was empty)
- Any `docs/marketing/` files updated, and why
- Confirmation that this checkout is back on `<start-branch>`
- **Print the full generated App Store notes (English and German) inline in the chat**, clearly labeled per language, so they can be copy/pasted straight into App Store Connect.
- **Print the generated Promotional Text (English and German) inline too**, each with its `N/170`
  character count, under a heading that says it can be pasted **without a new build**. Follow it
  with the description verdict (one line if unchanged, the proposed diff if not) and the
  subtitle/keyword verdict (one line). Keep this block visually separate from the What's New block
  above it — they go into different App Store Connect fields, and one of them is live immediately
  while the other waits for the binary.
