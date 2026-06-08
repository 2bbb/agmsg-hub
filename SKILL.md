---
name: agmsg
description: Cross-agent messaging via local SQLite by default, with optional remote HTTP storage. Send messages between Claude Code, Codex, Gemini CLI, GitHub Copilot CLI, and other agents.
---

# Agent Messaging

**IMPORTANT: Always use the provided scripts. NEVER directly read or edit config files, DB, or team data. There is NO register.sh — use join.sh to join a team.**

## How to use

## Runtime support

- macOS and Linux are the primary local-mode targets.
- Windows native shells are not supported yet. Use WSL or Git Bash with `bash` and `sqlite3`.
- Remote storage is available as an opt-in MVP. Local SQLite remains the default.

## Codex app notes

- Local and Worktree modes can use the local SQLite store when the skill's `db/` and `teams/` directories are writable.
- Cloud mode cannot rely on this machine's local skill database. Use remote storage when Cloud needs shared agmsg state.
- Codex supports `turn` and `off` delivery only. Do not offer `monitor` or `both`.
- Remote storage uses HTTP via `curl`. In Codex app/CLI sandboxes, localhost or LAN HTTP may be blocked even when the server is healthy. If `doctor`, `remote status`, `send`, `inbox`, or `history` fails in remote mode with a connection, DNS, timeout, or sandbox/network error, rerun the same script once with elevated/unrestricted shell permission before concluding the server is unreachable.
- To diagnose installation, sandbox, and delivery issues, run:

```bash
~/.agents/skills/__SKILL_NAME__/scripts/doctor.sh codex "$(pwd)"
~/.agents/skills/__SKILL_NAME__/scripts/doctor.sh --porcelain codex "$(pwd)"
~/.agents/skills/__SKILL_NAME__/scripts/doctor.sh --apply-fixes codex "$(pwd)"
```

### Step 1: Check identity

```bash
~/.agents/skills/__SKILL_NAME__/scripts/whoami.sh "$(pwd)" <type>
# type: claude-code, codex, gemini, antigravity, copilot
# Returns: agent=... / multiple=true ... / suggest=true ... / not_joined=true ...
```

### Step 2a: If not in a team — join one

Ask the user for a team name and agent name, then run:

```bash
~/.agents/skills/__SKILL_NAME__/scripts/join.sh <team> <agent_name> <type> "$(pwd)"
```

Do NOT manually edit config files. Always use join.sh.

### Step 2b: If already in a team — execute command

**Default (no arguments): IMMEDIATELY check inbox. Do NOT ask what to do.**

```bash
# Check inbox (marks messages as read) — DEFAULT action
~/.agents/skills/__SKILL_NAME__/scripts/inbox.sh <team> <agent_id>
~/.agents/skills/__SKILL_NAME__/scripts/inbox.sh <team> <agent_id> --wait 60 --poll 2

# Send a message
~/.agents/skills/__SKILL_NAME__/scripts/send.sh <team> <from_agent> <to_agent> "<message>"

# Message history
~/.agents/skills/__SKILL_NAME__/scripts/history.sh <team> [agent_id] [limit]

# Diagnostics
~/.agents/skills/__SKILL_NAME__/scripts/doctor.sh <type> "$(pwd)"
~/.agents/skills/__SKILL_NAME__/scripts/doctor.sh --porcelain <type> "$(pwd)"
~/.agents/skills/__SKILL_NAME__/scripts/doctor.sh --apply-fixes codex "$(pwd)"

# Remote storage MVP
~/.agents/skills/__SKILL_NAME__/scripts/server.sh serve --host 127.0.0.1 --port 8787
~/.agents/skills/__SKILL_NAME__/scripts/remote.sh configure http://127.0.0.1:8787
~/.agents/skills/__SKILL_NAME__/scripts/remote.sh switch remote
~/.agents/skills/__SKILL_NAME__/scripts/remote.sh status

# List team members
~/.agents/skills/__SKILL_NAME__/scripts/team.sh <team>

# Leave a team
~/.agents/skills/__SKILL_NAME__/scripts/leave.sh <team> <agent_id>

# Rename a team (moves dir, updates config + messages).
# After renaming, each existing member should re-run whoami.sh to refresh
# their cached team name in any running session.
~/.agents/skills/__SKILL_NAME__/scripts/rename-team.sh <old_team> <new_team>

# Clear registrations for the current project/type.
# A trailing <session_id> additionally releases any actas exclusivity locks
# this session held on <agent_id> so peers can pick them up immediately.
~/.agents/skills/__SKILL_NAME__/scripts/reset.sh "$(pwd)" <type> [agent_id] [session_id]

# Set delivery mode for this project. Replaces the legacy hook.sh on/off,
# which is kept as a deprecated alias only.
#   monitor — real-time push via SessionStart + Monitor tool (claude-code only)
#   turn    — Stop-hook pulls at the end of each assistant turn
#   both    — monitor primary, turn as fallback
#   off     — no automatic delivery
~/.agents/skills/__SKILL_NAME__/scripts/delivery.sh set <mode> <type> "$(pwd)"
~/.agents/skills/__SKILL_NAME__/scripts/delivery.sh status <type> "$(pwd)"

# Multiple roles per project (one CC = one active role).
# Claude Code: `actas` claims an exclusivity lock for <name> across sessions
# and restarts the Monitor filtered to <name> only; peer watchers stop
# subscribing to <name> while this session holds the lock. `drop` releases.
# Codex: actas is send-side only (no stable session_id during slash commands
# → no peer-visible lock). See README "Codex caveat" for details.
~/.agents/skills/__SKILL_NAME__/scripts/actas-claim.sh "$(pwd)" <type> <name> "$session_id"
~/.agents/skills/__SKILL_NAME__/scripts/reset.sh "$(pwd)" <type> <name> "$session_id"

# (Both of the above are normally driven by `/agmsg actas <name>` and
#  `/agmsg drop <name>` slash commands, which also handle the Monitor
#  TaskStop + relaunch dance described in the cmd template.)
```

## Architecture

- **Storage**: SQLite with WAL mode in `~/.agents/skills/__SKILL_NAME__/db/messages.db`
- **Teams**: `~/.agents/skills/__SKILL_NAME__/teams/<name>/config.json`
- **Concurrency**: WAL allows multiple readers + 1 writer without conflicts
- **Default mode**: Direct DB access via `sqlite3` CLI; no daemon and no network
- **Remote mode**: Optional Node.js HTTP server owning a SQLite store
- **Dependencies**: bash and sqlite3 for local mode; Node.js 24+ for server mode
