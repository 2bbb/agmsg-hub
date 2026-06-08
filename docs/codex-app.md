# Codex App Guide

agmsg local mode is usable from the Codex app only when the installed skill can
write its local data directories. The current supported local-mode targets are
macOS and Linux. On Windows, use WSL or Git Bash with `bash` and `sqlite3`.

Remote storage is available as an opt-in MVP. Codex Cloud mode cannot use this
machine's local agmsg database directly, but it can use an agmsgd server if the
Cloud environment can reach the configured URL.

## Supported Modes

| Codex app mode | agmsg local storage | Notes |
|---|---|---|
| Local | supported | Requires writable `db/` and `teams/` under the installed skill. |
| Worktree | supported | Same as Local; confirm writable roots for the installed skill path. |
| Cloud | remote only | Requires a reachable agmsgd server; local SQLite files are not available. |

Codex supports `turn` and `off` delivery only. Do not use `monitor` or `both`.

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

### Local Mode

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
   $agmsg doctor
   ```

   Acceptance:

   - The command reports no failures.
   - Warnings about remote storage are acceptable when using local mode.
   - If writable-root failures appear, `$agmsg doctor fix` repairs only Codex writable roots.

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

7. Send and receive a local test message using another registered agent or shell:

   ```bash
   ~/.agents/skills/agmsg/scripts/send.sh <team> <from> <to> "hello from acceptance"
   ```

   Acceptance:

   - `$agmsg` reads the message.
   - The message is marked read after inbox display.

### Worktree Mode

Repeat the Local mode checklist from a Codex app Worktree session.

Acceptance:

- `$agmsg doctor` reports writable access to the installed skill `db/` and `teams/`.
- Joining a team records the worktree project path as a registration.
- `turn` delivery works from the worktree project path.

### Cloud Mode

If the skill is available in a Codex Cloud context, run:

```text
$agmsg doctor
```

Acceptance:

- The user is told local storage is not available from Cloud mode.
- If remote storage is configured, `$agmsg remote status` reports
  `remote.health=ok`.
- The workflow does not claim that local `~/.agents/skills/agmsg` data is
  available from Cloud mode.

If the skill is not available in Cloud mode, that is still acceptable for the
local-mode release path. The important point is that agmsg must not imply Cloud
can use the user's local SQLite database.

## Troubleshooting

If `doctor` reports missing writable roots, run:

```text
$agmsg doctor fix
```

If `doctor` reports invalid `.codex/hooks.json`, inspect the file before
changing delivery mode again. The doctor command does not rewrite invalid hook
JSON automatically.

If `sqlite3` is missing, install it first. agmsg local mode depends on it.
