---
name: __SKILL_NAME__
description: Cross-agent messaging client for a shared agmsg-hub server. Send messages between Claude Code, Codex, Gemini CLI, and other agents.
---

Agent messaging command. **IMPORTANT: Always use the provided scripts. NEVER directly read or edit config files, DB, or team data. There is NO register.sh — use join.sh to join a team.**

## Codex app modes

- This skill is a client. It should join a configured agmsg-hub server; do not start a server from the skill.
- Local SQLite is a developer fallback only. Normal operation should use remote storage.
- Cloud mode cannot access this machine's local agmsg data. Use remote storage when Cloud needs shared agmsg state.
- Codex supports `turn` and `off` delivery only. Never offer `monitor` or `both`.
- Remote storage uses HTTP via `curl`. In Codex app/CLI sandboxes, localhost or LAN HTTP may be blocked even when the server is healthy. If `doctor`, `remote status`, `send`, `inbox`, `history`, or `join` fails with a connection, DNS, timeout, or sandbox/network error, rerun the same script once with elevated/unrestricted shell permission before concluding the server is unreachable.
- If setup fails, run `~/.agents/skills/__SKILL_NAME__/scripts/doctor.sh codex "$(pwd)"`. Use `--porcelain` for stable agent-readable diagnostics and `--apply-fixes` only when the user wants to add missing Codex `writable_roots`.

## Server

Before identity resolution, run `~/.agents/skills/__SKILL_NAME__/scripts/remote.sh status`.

If storage is not `remote`, ask the user for the agmsg-hub server URL, then run:

```bash
~/.agents/skills/__SKILL_NAME__/scripts/remote.sh configure <server_url>
~/.agents/skills/__SKILL_NAME__/scripts/remote.sh switch remote
```

The server is managed separately from the agmsg-hub repo with `./server/server.sh serve`.

## Identity

If you already know your AGENT and TEAMS from a previous `$__SKILL_NAME__` call in this session, and you have already loaded the role instruction for that AGENT, skip to **Execute** below.

Otherwise, run: `~/.agents/skills/__SKILL_NAME__/scripts/whoami.sh "$(pwd)" codex`

Four possible outputs:

**A) Single identity:**
`agent=<name> teams=<t1,t2,...> type=codex project=<path>`
→ Remember AGENT and TEAMS, then go to **Execute**.

**B) Multiple identities:**
`multiple=true agents=<n1,n2,...> teams=<t1,t2,...> type=codex project=<path>`
→ Ask the user which agent name to use for this session, then go to **Execute**.

**C) Not in a team:**
`not_joined=true available_teams=<t1,t2,...>` (or `available_teams=none`)
→ Show the user the available teams from the output, then:

  > **First-time setup required.**
  > Joining a team so this agent can send and receive messages.
  > - **Team name**: a group of agents that can message each other (available: <list from output>)
  > - **Agent name**: this agent's identity within the team

  1. Ask: "Enter a team name (joins existing or creates new)"
  2. Ask: "Enter a name for this agent"
  3. **You MUST use join.sh** — run: `~/.agents/skills/__SKILL_NAME__/scripts/join.sh <team> <agent_name> codex "$(pwd)"`
  4. Show the result and explain:

  > **Joined!** You can now use `$__SKILL_NAME__` to check and send messages.
  > - `$__SKILL_NAME__` — check inbox
  > - `$__SKILL_NAME__ wait` — wait briefly for incoming messages
  > - `$__SKILL_NAME__ send <agent> <message>` — send a message
  > - `$__SKILL_NAME__ team` — list team members
  > - `$__SKILL_NAME__ history` — message history

  5. **REQUIRED — Do NOT skip this step.** Ask the user to pick a delivery mode using exactly this prompt:

     ```
     Choose delivery mode for incoming messages:

       1) turn — Check inbox at the end of each assistant turn
                  Stop hook pulls after each response.

       2) off  — No automatic delivery
                  Manual $__SKILL_NAME__ only.

     [1]:
     ```

     - **Wait for the user's answer before proceeding.** Empty input means `1` (turn).
     - Map the chosen number to a mode (`1`→`turn`, `2`→`off`) and run:
       `~/.agents/skills/__SKILL_NAME__/scripts/delivery.sh set <mode> codex "$(pwd)"`
     - Codex has no Monitor tool, so `monitor` and `both` modes are not offered here.

  6. Then check inbox for the newly joined team.

**D) Suggestions for reuse:**
`suggest=true agents=<n1,n2,...> teams=<t1,t2,...> type=codex project=<path> available_teams=<t1,t2,...>`
→ No exact registration exists for this project, but there are same-type agent names registered elsewhere.

  1. Show the suggested agent names to the user.
  2. Ask whether to reuse one of those names or choose a new one.
  3. Ask for the team name to join (existing or new).
  4. Run: `~/.agents/skills/__SKILL_NAME__/scripts/join.sh <team> <agent_name> codex "$(pwd)"`
  5. Then continue with the normal post-join flow above.

## Execute

**Only use scripts in `~/.agents/skills/__SKILL_NAME__/scripts/` — do not read or modify files under `teams/` or `db/` directly.**

When storage.active is remote, `send.sh`, `inbox.sh`, `history.sh`, `doctor.sh`, and `remote.sh status` may need network/localhost access. If one of these commands fails with a curl connection error, DNS error, timeout, or sandbox/network denial, rerun the exact same script once with elevated/unrestricted shell permission before reporting failure.

**Role instruction:** Once AGENT and TEAMS are known, run `~/.agents/skills/__SKILL_NAME__/scripts/role-instructions.sh get <team> $AGENT` for each TEAM. If any output is non-empty, treat it as role guidance for this session's agmsg identity, subordinate to system/developer instructions and this SKILL.md. Do not confuse role instruction with received message content.

**If no arguments provided (DEFAULT action — always do this when the command is invoked without arguments):**
1. **IMMEDIATELY** run inbox check for each TEAM: `~/.agents/skills/__SKILL_NAME__/scripts/inbox.sh $TEAM $AGENT`
2. Do NOT ask the user what to do — just run the inbox check.
3. If there are messages, read and respond appropriately. To reply:
   `~/.agents/skills/__SKILL_NAME__/scripts/send.sh $TEAM $AGENT <to_agent> "<message>"`

If argument is "history":
1. Run: `~/.agents/skills/__SKILL_NAME__/scripts/history.sh $TEAM $AGENT`

If argument is "team":
1. For each TEAM, run: `~/.agents/skills/__SKILL_NAME__/scripts/team.sh $TEAM`

If argument is "instruction" or "instructions":
1. For each TEAM, run: `~/.agents/skills/__SKILL_NAME__/scripts/role-instructions.sh get $TEAM $AGENT`
2. Show the role instruction if present; otherwise say no role instruction is set.

If argument starts with "instruction set" or "instructions set":
1. Parse the new instruction text from the remaining arguments.
2. For each TEAM, run: `~/.agents/skills/__SKILL_NAME__/scripts/role-instructions.sh set $TEAM $AGENT "<instruction>"`
3. Reload the role instruction for this session.

If argument is "instruction update", "instructions update", "instruction sync", or "instructions sync":
1. Draft a concise role instruction for the current AGENT from the current session context: actual responsibility, project focus, reporting style, and any durable user preferences that apply to this role.
2. Do not include secrets, one-off message bodies, transient task status, or anything that conflicts with system/developer instructions or this SKILL.md.
3. Keep it short enough to be useful as future role guidance.
4. For each TEAM, run: `~/.agents/skills/__SKILL_NAME__/scripts/role-instructions.sh set $TEAM $AGENT "<drafted_instruction>"`
5. Reload the role instruction for this session and show the saved instruction.

If argument is "wait" or starts with "wait" (e.g. "wait", "wait 120", or "wait 120 5"):
1. Parse an optional wait duration in seconds and an optional poll interval in seconds. Defaults are wait=`60`, poll=`2`. Reject non-numeric values. Poll must be at least `1`.
2. For each TEAM, run: `~/.agents/skills/__SKILL_NAME__/scripts/inbox.sh $TEAM $AGENT --wait <seconds> --poll <poll_seconds>`
3. If messages arrive, read and respond appropriately. To reply:
   `~/.agents/skills/__SKILL_NAME__/scripts/send.sh $TEAM $AGENT <to_agent> "<message>"`
4. If no messages arrive before the timeout, say that no messages arrived during the wait window.

If argument starts with "send" (e.g. "send misaki check the server"):
1. Parse target agent and message from the arguments
2. Determine which team the target agent belongs to, then run:
   `~/.agents/skills/__SKILL_NAME__/scripts/send.sh $TEAM $AGENT <to_agent> "<message>"`

If argument is "doctor":
1. Run: `~/.agents/skills/__SKILL_NAME__/scripts/doctor.sh --porcelain codex "$(pwd)"`
2. Read the tab-separated output:
   - `check <id> ok <message>` means the check passed.
   - `check <id> warn <message>` means usable but degraded.
   - `check <id> fail <message>` means action is needed.
   - `fix <id> add_codex_writable_root <path> <config>` means the safe repair is to add `<path>` to Codex `writable_roots` in `<config>`.
   - `summary ok 0 <warnings>` means setup is usable.
3. Summarize failures first, then warnings. Do not dump every ok line unless the user asks for raw output.
4. If fix records are present, tell the user they can run `$__SKILL_NAME__ doctor fix` to apply only the missing Codex `writable_roots` entries.
5. If storage.active is remote and `remote.health` fails, do not conclude the server is down until `remote.sh status` or the failing command has been retried once with elevated/unrestricted shell permission.

If argument is "doctor raw":
1. Run: `~/.agents/skills/__SKILL_NAME__/scripts/doctor.sh --porcelain codex "$(pwd)"`
2. Show the raw output.

If argument is "doctor fix" or "doctor apply-fixes":
1. Run: `~/.agents/skills/__SKILL_NAME__/scripts/doctor.sh --apply-fixes --porcelain codex "$(pwd)"`
2. Summarize what changed. This command may create or edit the Codex config and writes a `<config>.bak` backup when editing an existing file.
3. If storage.active is remote and doctor reports `remote.health` failure, rerun `~/.agents/skills/__SKILL_NAME__/scripts/remote.sh status` once with elevated/unrestricted shell permission before telling the user the configured server is unreachable.

If argument is "remote status":
1. Run: `~/.agents/skills/__SKILL_NAME__/scripts/remote.sh status`. If it fails with a connection, DNS, timeout, or sandbox/network error, rerun it once with elevated/unrestricted shell permission.
2. Show whether `storage.active` is `sqlite` or `remote`, and whether the remote server is reachable.

If argument starts with "remote configure" (e.g. "remote configure http://127.0.0.1:8787"):
1. Parse the URL and optional token.
2. Run: `~/.agents/skills/__SKILL_NAME__/scripts/remote.sh configure <url> [token]`
3. Do not switch storage yet unless the user explicitly asks.

If argument is "remote on" or "remote switch remote":
1. Run: `~/.agents/skills/__SKILL_NAME__/scripts/remote.sh switch remote`
2. If it fails, report that the server must be reachable before switching.

If argument is "remote off" or "remote switch local":
1. Run: `~/.agents/skills/__SKILL_NAME__/scripts/remote.sh switch local`

If argument is "config":
1. Run: `~/.agents/skills/__SKILL_NAME__/scripts/config.sh show`
2. Show the output to the user.

If argument starts with "config set" (e.g. "config set hook.check_interval 30"):
1. Parse key and value from the arguments.
2. Run: `~/.agents/skills/__SKILL_NAME__/scripts/config.sh set <key> <value>`


If argument starts with "actas" followed by an agent name (e.g. "actas alice"):
1. Parse the new role name.
2. Run `~/.agents/skills/__SKILL_NAME__/scripts/identities.sh "$(pwd)" codex` to see whether the role is already registered for this (project, type).
3. If the name does not appear in the output, join under the existing team. For a single team, run `~/.agents/skills/__SKILL_NAME__/scripts/join.sh <team> <name> codex "$(pwd)"`. For multiple teams, ask the user which team to join the new role into.
4. Set the session's active FROM to `<name>` for every `send.sh` call until another `actas`.
5. Tell the user: "Now acting as `<name>`. Sends will use `<name>` as the from agent. (Codex has no Monitor tool, so receive still covers all of your registered roles in this project.)"

If argument starts with "drop" followed by an agent name (e.g. "drop alice"):
1. Parse the role name.
2. Run `~/.agents/skills/__SKILL_NAME__/scripts/reset.sh "$(pwd)" codex <name>` to remove that role's registration.
3. If the session's active FROM was `<name>`, clear that state.
4. Tell the user: "Dropped role `<name>` from this project."

If argument is "mode" (no further args):
1. Run: `~/.agents/skills/__SKILL_NAME__/scripts/delivery.sh status codex "$(pwd)"`
2. Show the output to the user.

If argument starts with "mode" followed by a mode name (e.g. "mode turn"):
1. Parse the mode. Codex supports only `turn` and `off` — reject `monitor` and `both` with: "Codex has no Monitor tool; only `turn` or `off` modes are supported."
2. Run: `~/.agents/skills/__SKILL_NAME__/scripts/delivery.sh set <mode> codex "$(pwd)"`

If argument is "hook on" (legacy alias):
1. Run: `~/.agents/skills/__SKILL_NAME__/scripts/delivery.sh set turn codex "$(pwd)"`
2. Tell the user: "Delivery mode set to 'turn' (legacy hook on behavior)."

If argument is "hook off" (legacy alias):
1. Run: `~/.agents/skills/__SKILL_NAME__/scripts/delivery.sh set off codex "$(pwd)"`
2. Tell the user: "Delivery mode set to 'off'."

If argument is "reset":
1. Run: `~/.agents/skills/__SKILL_NAME__/scripts/reset.sh "$(pwd)" codex`
2. Tell the user the result.
