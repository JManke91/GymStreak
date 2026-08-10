# Issue tracker: Things parent tasks and local Markdown implementation tickets

Gym Streak's user-managed work items live in the **Gym Streak** Things project (UUID `7BZCT8CLX8v5iaLRqPBHXS`). They are parent tasks: retrieve their full title, notes, and checklist through the Things MCP before planning work.

Implementation tickets are local Markdown files. A parent task is decomposed with `/to-tickets` into tracer-bullet vertical slices; it is never replaced, completed, or changed by that process.

## Conventions

- One parent task or feature per directory: `.scratch/<feature-slug>/`
- Implementation tickets are one file each at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` in dependency order
- Never use one combined tickets file
- Each ticket names its blockers and records `**Status:** ready-for-agent` (see `triage-labels.md` for the vocabulary and the required format)
- The parent Things task is the source of scope; its UUID and title should be noted in the ticket set when that context is useful
- The top level of `.scratch/` holds **open work only**. Finished feature directories live under `.scratch/_done/<feature-slug>/`

## Archiving a finished feature

`.scratch/` is gitignored, so nothing in it is recoverable once removed. **Never delete a ticket directory** — not on feature completion, not as cleanup, not to reduce clutter. Archiving is always a move:

```
.scratch/<feature-slug>/  →  .scratch/_done/<feature-slug>/
```

This runs as part of the completion prompt below, so the top level of `.scratch/` keeps showing only live work. A move is reversible, needs no separate confirmation, and leaves the user free to purge `.scratch/_done/` on their own terms. Deleting anything under `.scratch/` requires an explicit, specific instruction from the user.

**Harvest before archiving.** Ticket bodies accumulate knowledge that outlives the feature: root causes, discarded approaches, device-verification records, and follow-up work that was found but deliberately not done. Before moving the directory, confirm the feature's `docs/<feature>.md` exists and actually carries that material, and port anything missing. This is the enforcement point for the documentation rules in `CLAUDE.md` — the archive is not a substitute for them.

**Open follow-ups block the archive.** If a ticket records work that was found but not applied, that work must exist somewhere durable first — written up in `docs/<feature>.md`, or raised with the user as its own ticket. Say so and let the user decide; do not archive it silently.

## Publishing and consuming tickets

When a skill says to publish implementation tickets, write the local files under `.scratch/<feature-slug>/issues/` after the user approves the proposed breakdown.

When a skill says to fetch a parent task, use the Things MCP and the task identifier supplied by the user. When a skill says to fetch an implementation ticket, read the local Markdown file the user references.

Work the frontier: choose only a ticket whose blockers are complete. For a linear sequence, that is the lowest-numbered incomplete ticket.

## Things safety boundary

Reading a parent task is part of planning. Updating, completing, rescheduling, tagging, or creating Things tasks requires explicit user direction; local ticket generation alone is not authorization.

Two sanctioned exceptions:

1. **On ticket publication**: once the approved local tickets are written under `.scratch/<feature-slug>/issues/`, move the parent Things to-do under the **"Plan is ready in Claude Code"** heading in its project (`update_todo` with `heading: "Plan is ready in Claude Code"`). This only relocates the to-do — title, notes, checklist, and completion state are untouched. If the heading is missing or the call fails, tell the user and proceed; it never blocks ticket publication.
2. **On feature completion**: when every local implementation ticket for a parent task is complete, the agent must ask the user whether the feature is finished and tested. An explicit yes to that question authorizes completing the parent Things to-do (and nothing else); any other answer leaves it untouched. That same yes also authorizes marking the tickets `**Status:** done` and archiving the directory to `.scratch/_done/<feature-slug>/` per "Archiving a finished feature" above — harvest first, and never delete. Any other answer leaves the directory where it is.
