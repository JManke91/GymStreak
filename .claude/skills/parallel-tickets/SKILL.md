---
name: parallel-tickets
description: Find the local tickets in .scratch that are unblocked right now and safe to work in parallel, and hand back one ready-to-paste kickoff prompt per ticket for its own Claude Code worktree. Use when the user wants to parallelize a feature's tickets, asks which tickets can run at the same time, or wants to start several worktrees on one ticket set.
argument-hint: "[feature-slug ...] — omit to scan every open feature in .scratch/"
---

# Parallel Tickets

Read-only analysis. Pick the tickets that can start **now** and run **side by side** without stepping on each other, then hand the user one kickoff prompt per ticket to paste into a fresh worktree session. Never edit a ticket, never start implementation, never spawn the worktrees yourself.

The conventions this relies on — the canonical `.scratch/` location, the `in-progress` claim, when a blocker counts as cleared — live in `docs/agents/issue-tracker.md` ("Parallel work in worktrees") and `docs/agents/triage-labels.md`. Read both first.

## 1. Locate the ticket store

`.scratch/` is gitignored, so it exists only in the **main checkout**, never in a worktree. Resolve it from wherever you are:

```bash
MAIN="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"; ls "$MAIN/.scratch"
```

Scan the feature directories the user named, or every top-level directory except `_done/`. `_done/` is read only to resolve cross-set blockers.

## 2. Build the graph

For each `issues/NN-*.md`, read its `**Status:**`, `**Blocked by:**` and `**Touches:**` lines (`grep -E '^\*\*(Status|Blocked by|Touches):'`). Blocker lines in older tickets are prose — interpret them, including cross-set references (`<other-feature> ticket 08`, resolved under `.scratch/` or `.scratch/_done/`) and phrases like "every preceding ticket".

A **candidate** is a ticket with status `ready-for-agent` whose blockers are all **cleared**:

- `done` or `wontfix` → cleared, **unless** its status evidence names a worktree branch that is not yet in the **worktree base** — the commit a new worktree starts from. Claude Code's default (`worktree.baseRef: "fresh"`) is the remote default branch, `origin/HEAD`; with `"head"` set in a settings file it is the main checkout's `HEAD`. Check with `git fetch -q origin && git merge-base --is-ancestor <branch> <base>`; a not-yet-merged blocker is reported as "waiting on merge", because the new worktree would not contain its code.
- `ready-for-human`, `in-progress`, `ready-for-agent`, `needs-*` → **not** cleared.

Skip tickets that are `in-progress` (claimed by a running worktree), `ready-for-human`, `needs-triage`, `needs-info`, `done`, `wontfix`. A legacy status (`complete`, `implemented`) counts as `done`; say so in the report.

Also read the soft hints in the prose — "should not run concurrently with …", "edits the same view as 01, do 01 first". They are not blocking edges but they are conflict evidence for step 3.

## 3. Check independence

Unblocked is not the same as parallel-safe: two unblocked tickets that edit the same view will merge-conflict. For every candidate, establish its **conflict surface**:

1. The `**Touches:**` line, if present.
2. Otherwise the ticket body plus the feature's `docs/<feature>.md`, and a quick grep for the types/screens it names — enough to name the files or areas it will edit, no deeper. Delegate this to an `Explore` subagent when there are more than ~4 candidates.

Two candidates **conflict** when their surfaces share a file or a hard hotspot. Repo hotspots:

| Hotspot | Class |
|---|---|
| Same Swift file, view, ViewModel or service | hard — serialize |
| `GymStreak/App/AppDependencies.swift` (new wiring) | hard — serialize |
| `GymStreak/Domain/Models/GymStreakSchema.swift`, any `@Model` change | hard — serialize (schema + CloudKit deploy) |
| `WatchModels.swift` (both target copies) / watch sync payload | hard — serialize (wire compatibility) |
| `GymStreak.xcodeproj/project.pbxproj`, `*.entitlements` (build settings, targets) | hard — serialize |
| A ticket that restructures a whole file others append to (e.g. migrating `Localizable.strings` to a String Catalog) | hard — serializes against every ticket that adds strings |
| `Localizable.strings` en/de, watch `Localizable.xcstrings` — adding keys | soft — resolve at merge |
| `TestFlight/WhatToTest.*.txt`, `CHANGELOG.md` — appending a bullet | soft — resolve at merge |
| Same `docs/<feature>.md` — different sections | soft — resolve at merge |

Soft conflicts do not prevent parallel work; list them so the user expects them at merge time.

Then pick the **parallel set**: the largest group of candidates with no hard conflict between any pair. When two candidates conflict, keep the one that unblocks more downstream tickets; on a tie within one set keep the lower number, across sets pick one and name the swap as an alternative the user can choose. Prefer fewer, cleanly separable worktrees over squeezing in a risky one.

## 4. Report

Lead with the answer: how many tickets can start now, in parallel. Then:

- **Start now** — one row per ticket in the parallel set: `feature/NN — title`, its conflict surface in a few words, which downstream tickets it unblocks.
- **Deferred** — unblocked but conflicting, with the ticket it collides with and why.
- **Waiting** — blocked tickets and what they wait on (unfinished blocker, user verification, or merge into the worktree base).
- **Merge notes** — the soft conflicts to expect.

Then one kickoff block per ticket in the parallel set, each in its own fenced block so it can be copied whole. Worktree name: `<feature-slug>-<NN>`. Fill in `<MAIN>` with the resolved absolute path.

````
Start: claude --worktree <feature-slug>-<NN>   (or a new worktree session in the desktop app)

Implement ticket <feature-slug>/<NN> — <title>.

The ticket lives outside this worktree (.scratch/ is gitignored and only exists in the main checkout):
<MAIN>/.scratch/<feature-slug>/issues/<NN>-<slug>.md

1. Claim it before anything else: set its status line to
   **Status:** in-progress — branch <this worktree's branch>, started <today>
   Abort and tell me if it is no longer ready-for-agent — someone else claimed it.
2. Implement only this ticket, following CLAUDE.md (docs, Monetization Gate re-check, architecture review, TestFlight notes). Read the other tickets of the set for context but never edit them.
3. Other worktrees are building in parallel: pass your own -derivedDataPath to xcodebuild, keep simulator driving short, and do not touch files outside this ticket's scope.
4. Commit to this worktree's branch. Do not merge, rebase onto other worktrees, or push unless I ask.
5. When finished, set the ticket to ready-for-human per docs/agents/triage-labels.md; the evidence must name the branch (later tickets check that it was merged), and end with the manual test steps.
````

Close with one line: after the user verifies a ticket and its branch is in the worktree base (merged into `main` and pushed, with the default setting), rerun `/parallel-tickets` for the next wave.
