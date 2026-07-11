# MCP Servers

The MCP servers this project relies on are declared in **`.mcp.json`** at the repo root (project scope, shared via git). On first use after cloning, Claude Code prompts you once to approve them — no manual `claude mcp add` needed.

## Shared servers (in `.mcp.json`)

| Server | Transport | Purpose | Setup |
|---|---|---|---|
| `context7` | HTTP (`mcp.context7.com`) | Up-to-date library/framework docs. Required by the `ios-api-researcher` agent and the global Context7 rule. | Works without a key (lower rate limits). For higher limits, get a free key at [context7.com](https://context7.com) and export `CONTEXT7_API_KEY` in your shell profile. |
| `things` | stdio (`uvx things-mcp`) | Issue tracker — parent work items live in the Things project "Gym Streak" (see `issue-tracker.md`). | Requires macOS with the [Things 3](https://culturedcode.com/things/) app and [`uv`](https://docs.astral.sh/uv/) installed (`brew install uv`). Operates on **your local** Things database. |

## Secrets policy

Never put API keys or tokens into `.mcp.json` — it is committed. Use `${VAR}` / `${VAR:-default}` env expansion (supported in commands, args, env, URLs, and headers) and set the variable in your shell profile.

## Personal servers (intentionally NOT shared)

Servers unrelated to this project (e.g. work Jira, claude.ai connectors like Gmail/Drive) belong in your personal user scope (`~/.claude.json`, via `claude mcp add --scope user`), not here.

## Adding a new shared server

```bash
claude mcp add --transport http <name> --scope project <url>
# or edit .mcp.json directly
```

Then document it in the table above (purpose + setup), keeping secrets as env-var placeholders.
