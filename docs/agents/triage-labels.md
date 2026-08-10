# Triage labels

Local implementation tickets use these standard `Status:` values:

- `needs-triage`
- `needs-info`
- `ready-for-agent`
- `ready-for-human`
- `done`
- `wontfix`

New tickets created by `/to-tickets` start as `ready-for-agent`. These are local status values only; do not add or alter Things tags unless the user explicitly asks.

## Writing the status line

Write it as a bold Markdown field so it can be found mechanically:

```markdown
**Status:** done — <one-line evidence: what was verified, when, on what>
```

Use exactly one of the values above as the first word after `**Status:**`; free-text evidence follows after an em dash. Do not invent synonyms — `complete`, `completed`, and `implemented` are **not** status values (older tickets predate this rule and use them inconsistently).

`ready-for-human` means the agent is finished and the change awaits the user's manual verification. `done` is the terminal state and means that verification passed; only the user's confirmation moves a ticket into it. Feature archival keys off every ticket in a set being `done` or `wontfix` — see `issue-tracker.md`.
