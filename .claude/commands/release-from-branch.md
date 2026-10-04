# Full Release Pipeline — from a feature branch

Orchestrate a full release by merging the current feature branch all the way to `store-build` in three sequential steps, then cleaning up the source branch:

1. Current branch → `main`
2. `main` → `testflight-beta`
3. `testflight-beta` → `store-build`
4. Delete `<source-branch>` (local + remote)

Each phase must complete successfully before the next begins. If any phase fails, stop immediately and report the failure — do not proceed to the next phase.

This is the legacy path for a long-lived feature branch. The default workflow (worktrees + PRs merged into `main`) releases from `main` directly with `/release`. Phases 2 and 3 are shared: they live in `.claude/commands/release.md` and are not duplicated here.

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

## Phases 2 and 3 — `main` → `testflight-beta` → `store-build`, version bump

Read `.claude/commands/release.md` and execute its **Phase 2** and **Phase 3** (Part A merge, Part B version bump including step 6b build-number bump, App Store release notes and marketing copy) exactly as written there, together with the sections they reference. Do **not** run that file's pre-flight, Phase 1 or Phase 4 — this pipeline's own pre-flight, Phase 1 and Phase 4 replace them.

---

## Phase 4 — Delete the source branch

Only runs after Phases 1–3 have **all** completed successfully (merged and pushed). If any earlier phase failed, skip this phase entirely — the branch must survive for retry.

1. Safety check: `<source-branch>` must not be `main`, `testflight-beta`, or `store-build`. If it is one of these, skip deletion and note it in the final report.
2. Verify the branch is fully merged: `git branch --merged main` (while on `main`) must list `<source-branch>`. If it does not, **do not delete** — report this instead.
3. Delete the local branch: `git branch -d <source-branch>` (use `-d`, not `-D` — if git refuses, that's a signal something isn't merged; stop and report rather than forcing).
4. Delete the remote branch, if it exists on origin: check with `git ls-remote --heads origin <source-branch>`. If it exists, run `git push origin --delete <source-branch>`. If it doesn't exist remotely (branch was never pushed), skip and note it.

Announce: **"Phase 4 complete — `<source-branch>` deleted locally and on origin."** (adjust wording if the remote half was skipped).

---

## Final report

Produce the full **Final report** from `.claude/commands/release.md` (version and build-number bump, WhatToTest archive, release notes, marketing copy, and the inline App Store / Promotional Text blocks), with these branch-specific items in place of its starting-point and return-to-branch lines:
- Which branch was the starting point (`<source-branch>`)
- Commits merged in each phase, and any conflicts auto-resolved (affected files per phase, including Phase 1)
- Confirmation that `<source-branch>` was deleted locally and on origin (or why deletion was skipped)
