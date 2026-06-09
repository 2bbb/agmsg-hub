# agmsg — Design & Architecture

Developer documentation for contributors and maintainers.

## Identity Model

A runtime address is `(team, project_id, agent)`. A client registration is
identified by `team + agent + agent_type + client_id + project_path`.

- An agent can be registered from multiple projects under the same name.
- A single absolute `project_path` is not globally unique across machines.
- `whoami.sh` resolves the current role with `client_id + project_path + type`.
- `agmsg-client.mjs whoami` resolves the same identity over the remote HTTP API
  for Windows native and other Node-only clients.
- `project_key` is optional grouping metadata, not authentication or identity.
- New messages carry `project_id/project_key/project_path`, so history and inbox
  delivery can be scoped to the current project. Legacy messages with NULL
  project metadata are treated as `Unassigned` and only appear in all-project
  history.

## Data Storage

### Messages — SQLite

`~/.agmsg-hub/db/messages.db`

- Path resolved by `scripts/lib/storage.sh` (`agmsg_db_path`); override the hub home with `AGMSG_HUB_HOME` or the storage directory with `AGMSG_STORAGE_PATH`.
- WAL journal mode for concurrent access (multiple readers + 1 writer)
- Schema:
  ```sql
  CREATE TABLE messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    team TEXT NOT NULL,
    from_agent TEXT NOT NULL,
    to_agent TEXT NOT NULL,
    body TEXT NOT NULL,
    project_id TEXT,
    project_key TEXT,
    project_path TEXT,
    from_client_id TEXT,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    read_at TEXT
  );

  CREATE TABLE message_reads (
    message_id INTEGER NOT NULL,
    team TEXT NOT NULL,
    agent TEXT NOT NULL,
    client_id TEXT NOT NULL,
    read_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    PRIMARY KEY (message_id, client_id)
  );
  ```
- `messages.read_at` is a compatibility/summary timestamp: first read by any client.
- Unread queries use `message_reads` scoped by `client_id`, so one client reading a role's message does not hide it from another client using the same role.
- Project-scoped inbox/history queries filter by `messages.project_id`.
- Indexes on `(team, to_agent, read_at)`, `(team, created_at)`, `(team, project_id, created_at)`, and `(team, agent, client_id, message_id)`.

### Team Config — JSON

`~/.agmsg-hub/teams/<team>/config.json`

```json
{
  "name": "myteam",
  "agents": {
    "alice": {
      "registrations": [
        {
          "type": "claude-code",
          "project": "/path/to/project",
          "client_id": "client-uuid",
          "client_label": "mac-mini",
          "hostname": "mac-mini",
          "project_key": "git:https://github.com/2bbb/example.git",
          "archived_at": null
        }
      ]
    }
  },
  "created_at": "2026-01-01T00:00:00Z"
}
```

Manipulated via sqlite3 JSON1 functions (no python3 dependency).

Remote/server registrations also carry `archived_at`. Archived registrations are
hidden from active project, member, identity, and role-instruction resolution,
but remain visible through the browser UI's `/archive` page and can be restored.
An archived exact identity is reported as `archived=true` by `whoami.sh` instead
of being treated as a normal `not_joined` case.

### User Config — YAML

`~/.agmsg-hub/config.yaml`

```yaml
# agmsg configuration
hook:
  check_interval: 60  # seconds between inbox checks
```

Read/written by `config.sh` using awk. Supports dotted keys (`hook.check_interval`).

## Hook System

Auto message detection uses the host agent's hook mechanism to check for new messages after each response.

### Flow

```
Agent responds → Stop hook fires → check-inbox.sh runs
  ├─ Cooldown active? → skip (Codex: JSON systemMessage)
  ├─ No unread messages? → silent (Codex: JSON systemMessage)
  └─ Unread messages found:
       1. Build notification text
       2. Insert message_reads receipts for this client
       3. Return JSON { "decision": "block", "reason": "..." }
       4. Agent sees messages in context and continues
```

### Cooldown

A marker file (`run/.lastcheck-<hash(team,agent,client_id)>`) tracks the last check time per resolved inbox pair. Configurable via `delivery.turn.check_interval` or legacy `hook.check_interval` (default 60 seconds). It lives in the run dir (hook runtime state), not the message store, so it is unaffected by `AGMSG_STORAGE_PATH`.

### Claude Code vs Codex

| Aspect | Claude Code | Codex |
|---|---|---|
| Hook config | `.claude/settings.local.json` | `.codex/hooks.json` |
| Feature flag | Not needed | `codex_hooks = true` in `config.toml` |
| Silent output | exit 0 with no output | JSON `{ "continue": true }` |
| New messages | `decision: "block"` | `decision: "block"` |
| UI label | "Stop hook error:" ([#2](https://github.com/2bbb/agmsg-hub/issues/2)) | "warning:" ([#2](https://github.com/2bbb/agmsg-hub/issues/2)) |

## Scripts

| Script | Purpose |
|---|---|
| `agmsg-client.mjs` | Portable Node remote client for Windows native / PowerShell |
| `agmsg.ps1` | PowerShell dispatcher for `agmsg-client.mjs` |
| `init-db.sh` | Create SQLite database with schema |
| `send.sh` | Insert a message into the database |
| `inbox.sh` | Show unread messages and mark as read |
| `history.sh` | Show message history (newest first, displayed oldest first) |
| `join.sh` | Add agent to team (create team if needed) |
| `leave.sh` | Remove agent from team (delete team if empty) |
| `team.sh` | List team members |
| `whoami.sh` | Identify agent by client, project path, and type |
| `rename.sh` | Rename agent in config and message history |
| `hook.sh` | Enable/disable Stop hook (on/off) |
| `check-inbox.sh` | Hook entry point — resolve all exact identities, cooldown, check, notify |
| `config.sh` | Read/write user config (YAML) |

The POSIX scripts use only `bash` and `sqlite3`. No python3 dependency. The
Windows native client path uses Node.js and supports remote storage only.

## Install Layout

```
~/.agents/skills/<cmd>/
├── SKILL.md              # Read by Codex (generated from cmd.codex.md template)
├── agents/
│   └── openai.yaml       # Codex metadata
├── scripts/              # Shell scripts plus Node/PowerShell remote client
├── templates/            # Command templates (cmd.claude-code.md, cmd.codex.md)
├── db/
│   ├── messages.db       # SQLite message store (relocatable via AGMSG_STORAGE_PATH)
│   └── config.yaml       # User configuration
├── run/                  # Hook/watcher runtime state
│   ├── watch.<sid>.pid   # Monitor watcher pidfiles
│   └── .lastcheck-*      # Cooldown markers
└── teams/
    └── <team>/
        └── config.json   # Team member registry
```

Claude Code command is installed separately to `~/.claude/commands/<cmd>.md`.

## Dependencies

- **bash** — POSIX client shell
- **sqlite3** — local database and JSON manipulation (JSON1 extension)
- **awk/sed** — POSIX config/TOML editing
- **Node.js** — server and portable remote client
- **PowerShell** — Windows native dispatcher (`scripts/agmsg.ps1`)

Local POSIX mode has no python3, no node, no network, and no daemon. Remote
server mode requires Node.js 24+ on the server host. Windows native clients use
the Node remote client and do not support local SQLite mode.

## Client identity

Remote mode must not use `project_path` as a global identity. Two machines can
legitimately have the same absolute path, so agmsg-hub assigns each client
install a stable `client_id` in `~/.agmsg-hub/client_id`.

Registrations are keyed by:

```text
team + agent + agent_type + client_id + project_path
```

`client_label` and `hostname` are display/diagnostic fields. `project_key` is
grouping metadata only:

- git repo with origin remote: `git:<remote-url>`
- git repo without remote: `git-local:<hash(realpath)>`
- non-git path: `local:<client_id>:<hash(realpath)>`

That last default is intentionally client-local. Automatically merging non-git
directories across machines is false precision; users can opt into grouping with
`AGMSG_PROJECT_KEY` when they know two directories represent the same project.
