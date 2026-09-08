# MCP Servers

The MCP servers this project relies on are declared in **`.mcp.json`** at the repo root (project scope, shared via git). On first use after cloning, Claude Code prompts you once to approve them — no manual `claude mcp add` needed.

## Shared servers (in `.mcp.json`)

| Server | Transport | Purpose | Setup |
|---|---|---|---|
| `context7` | HTTP (`mcp.context7.com`) | Up-to-date library/framework docs. Required by the `ios-api-researcher` agent and the global Context7 rule. | Works without a key (lower rate limits). For higher limits, get a free key at [context7.com](https://context7.com) and export `CONTEXT7_API_KEY` in your shell profile. |
| `things` | stdio (`uvx things-mcp`) | Issue tracker — parent work items live in the Things project "Gym Streak" (see `issue-tracker.md`). | Requires macOS with the [Things 3](https://culturedcode.com/things/) app and [`uv`](https://docs.astral.sh/uv/) installed (`brew install uv`). Operates on **your local** Things database. |
| `revenuecat` | HTTP (`mcp.revenuecat.ai`) | **Real subscriber and revenue data** — active subscriptions, trials, MRR, new/active customers, and paywall/placement analytics. RevenueCat's own hosted server, so no local install. | Needs a **v2 secret API key**. See "RevenueCat setup" below. |

## Secrets policy

Never put API keys or tokens into `.mcp.json` — it is committed. Use `${VAR}` / `${VAR:-default}` env expansion (supported in commands, args, env, URLs, and headers) and set the variable in your shell profile.

## RevenueCat setup

**Why it exists:** this app has no analytics backend by design (`monetization-strategy.md` §1's
no-account position), and App Store Connect suppresses every engagement metric at the app's current
volume — Retention, Sessions and Active Devices are opt-in-only *and* privacy-thresholded (§13.4).
**RevenueCat is therefore the only live user-data source there is**, and this server is how an agent
reads it without the user screenshotting a dashboard.

1. RevenueCat Dashboard → **Project Settings → API keys → + New secret API key** (Admin only).
   v2 secret keys are scoped at creation — grant least privilege: `customer_information:read` and
   the Charts & Metrics read scope are enough for reporting. Do **not** grant write scopes.
2. Store it in the Keychain rather than a plaintext profile line, matching the `cktool` precedent in
   `cloudkit-schema-automation.md`:

   ```bash
   security add-generic-password -s revenuecat-secret-key -a "$USER" -w '<sk_...>'
   ```

3. Export it from the Keychain in your shell profile, so `.mcp.json`'s `${REVENUECAT_SECRET_KEY}`
   expansion resolves. **Put it in `~/.zprofile`, not `~/.zshrc`:**

   ```bash
   export REVENUECAT_SECRET_KEY=$(security find-generic-password -s revenuecat-secret-key -w)
   ```

   `~/.zshrc` is sourced only for **interactive** shells, so a Claude Code started any other way
   (an IDE terminal, a launcher, a non-interactive login shell) gets nothing and the server 401s.
   `~/.zprofile` covers every login shell, and Terminal windows are login shells, so it covers the
   normal case too — with one Keychain read per login instead of per interactive shell.

4. **Start Claude from a shell that already has the variable.** The environment is captured at
   process launch, so adding the export to a profile does not reach an already-running session —
   `/mcp` reconnect will keep failing until you quit and relaunch. Check before starting:

   ```bash
   echo ${#REVENUECAT_SECRET_KEY}   # expect 32, not 0
   ```

### If it returns HTTP 401

Diagnose in this order — the first two are far more common than a bad key:

1. **Is the variable set in the Claude process?** If not, the header goes out as a bare `Bearer `
   and RevenueCat answers 401. This is the usual cause. Note `.mcp.json` deliberately uses
   `${REVENUECAT_SECRET_KEY}` **without** a `:-` default (unlike `context7`, where an empty key is
   legitimately valid): an unset variable must fail loudly rather than silently send an empty token.
2. **Was the session started before the export existed?** Quit and relaunch.
3. **Is the key actually valid?** Test it directly, independent of MCP — a 200 here proves the key
   and the endpoint are both fine and the problem is environment:

   ```bash
   K=$(security find-generic-password -s revenuecat-secret-key -w)
   curl -sS -o /dev/null -w 'HTTP %{http_code}\n' \
     -H "Authorization: Bearer $K" https://api.revenuecat.com/v2/projects
   ```

**Known unknown, verify on first use:** RevenueCat's official docs say the Charts & Metrics category
authenticates with a secret key, but third-party write-ups claim it returns `403 insufficient_scope`
and requires OAuth. Their own OAuth page argues for the secret key for first-party use ("if you're
calling the REST API for your own project, create a secret API key instead"). If metrics calls 403,
that is the known cause — not a bad key. Rate limit on metrics is 25 req/min.

**Not covered by this server:** App Store *downloads and impressions*. Those come from App Store
Connect, and per §13.2 RevenueCat's "New Customers" counts SDK-identity creations rather than
installs — it overstated acquisition by ~6× once already. Never quote RevenueCat customer counts as
install or user counts.

## Two Claude accounts on this Mac

`claude` uses the default config dir; `claude-private` is a shell alias for
`CLAUDE_CONFIG_DIR="$HOME/.claude-private" claude`. What that means for MCP:

- **`.mcp.json` is shared automatically** — it is project scope, read from the repo, identical for
  both.
- **Env vars are shared automatically** — the alias only changes the config dir, so both inherit the
  same shell environment. One `export` in the profile serves both; there is nothing to duplicate.
- **Approval is per account.** Server enable/disable state lives in each config dir's own
  `.claude.json` under the project entry, so **adding a server to `.mcp.json` prompts once in each
  account.** Approve it in both. This is the only per-account step.

### Project memory is shared (one directory, via symlink)

Both accounts read and write **one** memory store for this project. `claude-private`'s memory
directory is a symlink to the default account's:

```
~/.claude-private/projects/-Users-jmanke-Documents-Code-iOS-AI-GymStreak/memory
  -> ~/.claude/projects/-Users-jmanke-Documents-Code-iOS-AI-GymStreak/memory
```

Before 2026-09-06 the two were separate and had diverged badly — 31 files, only 2 present in both,
and B's index still asserted a symlink-based iOS/watch file-sharing scheme that a July-2026 audit had
disproven. So what an agent knew about this project depended on which command was typed. They were
reconciled to 20 files and then linked; the audit trail is in `.scratch/_done/memory-reconciliation/`.

Consequences:

- **Don't reconcile them again, and don't "fix" the duplication by copying files back** — that is
  what re-forks them. Identical listings in both accounts is the intended state, not a bug.
- A memory written from either account is immediately visible to the other.
- The real files live in the default config dir, **inside** `~/.claude/projects/<project>/` alongside
  session transcripts. If that project directory is ever cleaned up wholesale, the link dangles and
  *both* accounts lose their memory. If that ever happens, restore from a
  `~/claude-memory-backup-*.tgz` and consider moving the real directory to a neutral path outside
  `projects/` (e.g. `~/.claude-shared/gymstreak/memory/`) with both accounts pointing at it.

## Personal servers (intentionally NOT shared)

Servers unrelated to this project (e.g. work Jira, claude.ai connectors like Gmail/Drive) belong in your personal user scope (`~/.claude.json`, via `claude mcp add --scope user`), not here.

## Adding a new shared server

```bash
claude mcp add --transport http <name> --scope project <url>
# or edit .mcp.json directly
```

Then document it in the table above (purpose + setup), keeping secrets as env-var placeholders.
