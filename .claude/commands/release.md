# Full Release Pipeline

Orchestrate a full release by merging the current feature branch all the way to `store-build` in three sequential steps, then cleaning up the source branch:

1. Current branch → `main`
2. `main` → `testflight-beta`
3. `testflight-beta` → `store-build`
4. Delete `<source-branch>` (local + remote)

Each phase must complete successfully before the next begins. If any phase fails, stop immediately and report the failure — do not proceed to the next phase.

---

## Pre-flight checks

Before doing anything else:

1. Run `git status` — if there are uncommitted changes, **stop and inform the user**. Do not stash or discard anything automatically.
2. Run `git rev-parse --abbrev-ref HEAD` to capture `<source-branch>`. If it is `main`, **stop and inform the user** that they are already on `main`.
3. Inform the user of the plan:
   > "Starting release pipeline: `<source-branch>` → `main` → `testflight-beta` → `store-build`. `<source-branch>` will be deleted (locally and on origin) once the pipeline completes."

---

## Phase 1 — Merge `<source-branch>` into `main`

1. `git fetch origin`
2. `git checkout main && git pull origin main`
3. `git merge <source-branch> -X theirs -m "Merge <source-branch> into main"`
4. Verify `git status` shows no remaining conflicts. If conflicts remain (e.g., delete/modify conflicts that `-X theirs` doesn't auto-resolve), resolve each with `git checkout --theirs <file> && git add <file>`, then `git commit --no-edit`.
5. `git push origin main`

Announce: **"Phase 1 complete — `<source-branch>` merged into `main`."**
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
7. **Generate App Store release notes** for `<old-version>` — do this **before** clearing the WhatToTest files, while they still hold this version's notes. See [App Store release notes](#app-store-release-notes) below for how to distill and where to write them.
8. Archive `TestFlight/WhatToTest.en-US.txt` into `CHANGELOG.md` under a new `## [<old-version>] - <YYYY-MM-DD>` heading with `### Added / Improved / Fixed` subsections (categorize each bullet by content). If `CHANGELOG.md` does not exist, create it with a `# Changelog` header. Clear both WhatToTest files afterward.
9. `git add GymStreak.xcodeproj/project.pbxproj CHANGELOG.md TestFlight/WhatToTest.en-US.txt TestFlight/WhatToTest.de-DE.txt AppStore/ReleaseNotes.<old-version>.md`
10. `git commit -m "Bump version to <new-version> for next release cycle"`
11. `git push origin main`

Announce: **"Phase 3 complete — `testflight-beta` merged into `store-build`, version bumped to `<new-version>`."**

---

## Phase 4 — Delete the source branch

Only runs after Phases 1–3 have **all** completed successfully (merged and pushed). If any earlier phase failed, skip this phase entirely — the branch must survive for retry.

1. Safety check: `<source-branch>` must not be `main`, `testflight-beta`, or `store-build`. If it is one of these, skip deletion and note it in the final report.
2. Verify the branch is fully merged: `git branch --merged main` (while on `main`) must list `<source-branch>`. If it does not, **do not delete** — report this instead.
3. Delete the local branch: `git branch -d <source-branch>` (use `-d`, not `-D` — if git refuses, that's a signal something isn't merged; stop and report rather than forcing).
4. Delete the remote branch, if it exists on origin: check with `git ls-remote --heads origin <source-branch>`. If it exists, run `git push origin --delete <source-branch>`. If it doesn't exist remotely (branch was never pushed), skip and note it.

Announce: **"Phase 4 complete — `<source-branch>` deleted locally and on origin."** (adjust wording if the remote half was skipped).

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

## Final report

Summarize the entire pipeline:
- Which branch was the starting point
- Commits merged in each phase
- Any conflicts that were auto-resolved (list affected files per phase)
- Old version → new version
- Confirmation that WhatToTest files were archived and cleared
- Confirmation that `AppStore/ReleaseNotes.<old-version>.md` was written (or that it was skipped because WhatToTest was empty)
- Confirmation that `<source-branch>` was deleted locally and on origin (or why deletion was skipped)
- **Print the full generated App Store notes (English and German) inline in the chat**, clearly labeled per language, so they can be copy/pasted straight into App Store Connect.
