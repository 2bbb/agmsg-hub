# Codex App Guide

agmsg in the Codex app is a client for a separately running agmsg-hub server.
The installed skill should not own the server or shared team database. Client
state lives under `~/.agmsg-hub/`.

Codex Cloud mode cannot use this machine's local agmsg database directly, but
it can use an agmsgd server if the Cloud environment can reach the configured
URL.

## Supported Modes

| Codex app mode | agmsg storage | Notes |
|---|---|---|
| Local | remote server | Requires a configured, reachable agmsgd server. |
| Worktree | remote server | Same as Local; project path is registered on the server. |
| Cloud | remote server | Requires a reachable agmsgd server; local SQLite files are not available. |

Codex supports `turn` and `off` delivery only. Do not use `monitor` or `both`.

Remote mode uses HTTP via `curl`. Codex app/CLI sandboxes may block localhost
or LAN HTTP even when the agmsgd server is healthy. If `$agmsg doctor`,
`$agmsg remote status`, `send`, `inbox`, or `history` fails with a connection,
DNS, timeout, or sandbox/network error, rerun the same agmsg script once with
elevated/unrestricted shell permission before treating the server as
unreachable.

## Diagnostics

Run:

```bash
~/.agents/skills/agmsg/scripts/doctor.sh codex "$(pwd)"
```

For stable agent-readable output:

```bash
~/.agents/skills/agmsg/scripts/doctor.sh --porcelain codex "$(pwd)"
```

To explicitly add missing Codex `writable_roots` entries:

```bash
~/.agents/skills/agmsg/scripts/doctor.sh --apply-fixes codex "$(pwd)"
```

The fix command may create or edit `~/.codex/config.toml`. If the config already
exists, agmsg writes a `config.toml.bak` backup first. It does not edit agmsg
message DBs, team configs, hooks, or delivery mode.

## Manual Acceptance

Use this checklist before treating Codex app local support as working.

### Local / Worktree Mode

1. Install or update agmsg:

   ```bash
   ./install.sh --cmd agmsg
   # or
   ./install.sh --update
   ```

2. Restart the Codex app.

3. Open a local project in Codex app Local mode.

4. Run:

   ```text
   $agmsg remote configure http://<server-host>:8787
   $agmsg remote on
   $agmsg doctor
   ```

   Acceptance:

   - The command reports no failures.
   - Remote health reports reachable.
   - If writable-root failures appear, `$agmsg doctor fix` repairs only the `~/.agmsg-hub` writable root.

5. Run:

   ```text
   $agmsg
   ```

   Acceptance:

   - First run prompts to join a team if this project is not registered.
   - Joining creates/uses a team and agent identity.
   - Delivery options offered to Codex are only `turn` and `off`.

6. Choose `turn`.

   Acceptance:

   - `.codex/hooks.json` is created or updated.
   - `$agmsg doctor` still reports no failures.
   - `$agmsg mode` reports `mode: turn`.

7. Send and receive a test message using another registered agent or shell:

   ```bash
   ~/.agents/skills/agmsg/scripts/send.sh <team> <from> <to> "hello from acceptance"
   ```

   Acceptance:

   - `$agmsg` reads the message.
   - The message is marked read after inbox display.

### Cloud Mode

If the skill is available in a Codex Cloud context, run:

```text
$agmsg doctor
```

Acceptance:

- `$agmsg remote status` reports `remote.health=ok` when the server is reachable.
- If `remote.health` fails but Terminal `curl` succeeds, the workflow retries
  the same agmsg command with elevated/unrestricted shell permission before
  reporting the server as unreachable.
- The workflow does not claim that local `~/.agents/skills/agmsg` data is
  available from Cloud mode.

The important point is that agmsg must not imply Cloud can use the user's local
SQLite database.

## Troubleshooting

If `doctor` reports missing writable roots, run:

```text
$agmsg doctor fix
```

If `doctor` reports invalid `.codex/hooks.json`, inspect the file before
changing delivery mode again. The doctor command does not rewrite invalid hook
JSON automatically.

If `sqlite3` is missing, install it first. Some client helpers and local
developer fallback paths depend on it.
