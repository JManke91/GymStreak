# Issue tracker: Things parent tasks and local Markdown implementation tickets

Gym Streak's user-managed work items live in the **Gym Streak** Things project (UUID `7BZCT8CLX8v5iaLRqPBHXS`). They are parent tasks: retrieve their full title, notes, and checklist through the Things MCP before planning work.

Implementation tickets are local Markdown files. A parent task is decomposed with `/to-tickets` into tracer-bullet vertical slices; it is never replaced, completed, or changed by that process.

## Conventions

- One parent task or feature per directory: `.scratch/<feature-slug>/`
- Implementation tickets are one file each at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` in dependency order
- Never use one combined tickets file
- Each ticket names its blockers and records `Status: ready-for-agent`
- The parent Things task is the source of scope; its UUID and title should be noted in the ticket set when that context is useful

## Publishing and consuming tickets

When a skill says to publish implementation tickets, write the local files under `.scratch/<feature-slug>/issues/` after the user approves the proposed breakdown.

When a skill says to fetch a parent task, use the Things MCP and the task identifier supplied by the user. When a skill says to fetch an implementation ticket, read the local Markdown file the user references.

Work the frontier: choose only a ticket whose blockers are complete. For a linear sequence, that is the lowest-numbered incomplete ticket.

## Things safety boundary

Reading a parent task is part of planning. Updating, completing, rescheduling, tagging, or creating Things tasks requires explicit user direction; local ticket generation alone is not authorization.

One sanctioned exception: when every local implementation ticket for a parent task is complete, the agent must ask the user whether the feature is finished and tested. An explicit yes to that question authorizes completing the parent Things to-do (and nothing else); any other answer leaves it untouched.
