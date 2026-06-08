# PLAN: agmsg-hub update plan

Status: draft  
Target repository: `agmsg-hub` with optional Codex app support, remote sharing, and browser management UI  
Date: 2026-06-06

## 1. Context

The original project is a cross-agent messaging skill for Claude Code, Codex, Gemini CLI, GitHub Copilot CLI, Antigravity, and shell-based agents. Its current public goal is intentionally local-first: no daemon, no network, and no shared cloud by default. The architecture already separates the implementation into three driver axes:

- `storage`: where messages and team state live.
- `agent`: runtime-specific integration details.
- `delivery`: how incoming messages are surfaced.

The storage driver interface already covers message insertion, unread queries, mark-read operations, history, teams, members, export, and import. That makes a remote storage driver a natural extension rather than a rewrite.

agmsg-hub is intentionally independent. It should preserve the local-first default because that product constraint is useful, not because upstream acceptance is a goal. The original agmsg project is a reference point, not the destination.

## 2. Product goals

### 2.1 Codex app support

Make agmsg pleasant to use from the Codex app, not only from Codex CLI.

Goals:

- Ensure the skill metadata and installation layout are discoverable by Codex app.
- Support Codex app Local and Worktree modes with the existing local SQLite storage.
- Support Codex app Cloud mode through remote storage only.
- Keep Codex delivery semantics honest: `turn` and `off` only unless Codex exposes a monitor-equivalent API later.
- Provide clear diagnostics when sandbox, writable roots, or dependencies block agmsg usage.

### 2.2 Remote sharing

Allow multiple machines to share a team when their IP connectivity is already solved by LAN, VPN, Tailscale, WireGuard, Cloudflare Zero Trust, or equivalent.

Goals:

- One machine can act as the agmsg server.
- Server owns the canonical SQLite/event-log store.
- Remote machines use HTTP API or SSH transport; they do not mount or write the SQLite file directly.
- Remote sharing remains opt-in.
- Local-only mode remains the default and keeps working without extra dependencies.

### 2.3 Browser management GUI

Provide a browser-based admin console when `agmsgd` is enabled.

Goals:

- Inspect teams, agents, sessions, registrations, messages, unread queues, delivery modes, tokens, and server health.
- Send and read messages from the browser for debugging and administration.
- Manage tokens, team-scoped access, and remote clients.
- Show an audit/event timeline based on the event log.
- Serve the UI from the same `agmsgd` binary by default.

## 3. Non-goals

The fork should not attempt the following in the first implementation wave:

- Replace local mode with server mode.
- Share SQLite over NFS, SMB, sshfs, Dropbox, iCloud Drive, Google Drive, or similar filesystem sync.
- Add a hosted cloud service operated by the fork maintainer.
- Build a Slack/Discord clone.
- Require Node.js, Go, Rust, or Docker for the default local-only install.
- Implement complex enterprise SSO in v1.
- Make Codex app receive real-time push if the host runtime cannot support it.

## 4. Core design principles

### 4.1 Local-first remains the default

The local-first promise is valuable. The fork should keep this behavior:

```text
./install.sh
/agmsg or $agmsg
local sqlite storage
no daemon
no network
```

Server mode should be an explicit opt-in:

```text
agmsgd init
agmsgd serve
agmsg storage switch remote
```

### 4.2 Server owns SQLite

Remote clients must never directly share the SQLite DB file across machines. The server process is the only writer and the only process that opens the remote-mode database. Clients interact through an API.

### 4.3 Same semantics for CLI and GUI

The Web UI and remote storage driver must use the same public API. There should be no private GUI-only mutation path.

### 4.4 Driver-compatible extension

The remote mode should present itself as a storage driver compatible with the existing `storage_*` interface.

Target local driver path:

```text
scripts/drivers/storage/remote.sh
```

Target server implementation:

```text
cmd/agmsgd/
internal/server/
web/
```

### 4.5 Progressive implementation

Ship value in small layers:

1. Codex app polish.
2. Minimal HTTP server with health and message APIs.
3. Remote storage driver.
4. Minimal Web UI.
5. Token management and hardening.
6. Packaging and installer integration.

## 5. Proposed architecture

```text
Local-only mode, unchanged

agent runtime
  └─ agmsg skill scripts
       └─ storage driver: sqlite
            └─ ~/.agents/skills/agmsg/db/messages.db
```

```text
Remote mode with Web UI

browser
  └─ agmsg Web UI
       └─ /api/v1/*
            └─ agmsgd
                 └─ SQLite/event-log store

remote agent machine
  └─ agmsg skill scripts
       └─ storage driver: remote
            └─ HTTPS over LAN/VPN/Zero Trust
                 └─ agmsgd
                      └─ SQLite/event-log store
```

Optional MVP transport:

```text
remote agent machine
  └─ storage driver: ssh
       └─ ssh agmsg-host agmsg server-side command
            └─ SQLite/event-log store
```

The HTTP path is the main product path because it supports the browser UI. The SSH path is optional if a quick daemon-light MVP is wanted.

## 6. Phased implementation plan

### Phase 0: Independent fork baseline

Tasks:

- Add `PLAN.md`, `SPEC.md`, and `ROADMAP.md` to the fork.
- Add CI checks for shell scripts.
- Run current test suite unchanged.
- Record compatibility assumptions inherited from the original project.

Acceptance criteria:

- Existing install and local usage remain unchanged.
- No server or GUI code is active by default.
- All existing tests pass.

### Phase 1: Codex app support polish

Status: implementation complete; manual Codex app acceptance still pending.

Tasks:

- Expand `agents/openai.yaml` metadata for Codex app discovery.
- Update `SKILL.md` with explicit Codex app Local, Worktree, and Cloud notes.
- Add diagnostics script:

```text
scripts/doctor.sh
```

- Validate writable paths and sandbox-related configuration.
- Add clear failure messages for unsupported delivery modes on Codex.
- Document Windows native limitations and WSL/Git Bash fallback if shell scripts remain Bash-based.

Acceptance criteria:

- `$agmsg` is discoverable and invokable in Codex app where skills are available.
- Local and Worktree modes can use local storage.
- Cloud mode explicitly states local storage is unavailable until remote storage lands.
- Diagnostics report missing `sqlite3`, missing writable roots, missing config, and unsupported delivery mode.

Current implementation notes:

- `scripts/doctor.sh codex <project>` exists.
- `doctor.sh` validates skill files, Codex metadata, executable scripts, `sqlite3`, writable `db/` and `teams/`, Codex `writable_roots`, Codex hooks JSON, delivery-mode compatibility, and remote-storage absence.
- Codex config parsing/updating lives in `scripts/lib/codex-config.sh`; `doctor.sh` owns output and diagnostic flow.
- `doctor.sh --porcelain` emits stable `check`, `fix`, and `summary` records for agent-mediated repair flows.
- `doctor.sh --apply-fixes` explicitly adds missing Codex `writable_roots` and leaves DB/team/hook state untouched.
- `$agmsg doctor`, `$agmsg doctor raw`, and `$agmsg doctor fix` are defined in the Codex command template.
- README, SKILL.md, and Codex template state that Windows native shells are not supported for local mode; use WSL or Git Bash with `bash` and `sqlite3`.
- `docs/codex-app.md` contains the manual acceptance checklist for Codex app Local, Worktree, and Cloud behavior.
- `SKILL.md`, `templates/cmd.codex.md`, and README document Codex app Local, Worktree, and Cloud behavior.

Verification:

- `bats tests/` passes: 191/191 on 2026-06-08.
- Manual Codex app Local/Worktree acceptance from `docs/codex-app.md` has not been recorded yet.

Known non-goals for v0.1:

- Codex Cloud local SQLite access.
- Remote storage.
- Native Windows local-mode support.

### Phase 2: `agmsgd` server MVP

Tasks:

- Implement `agmsgd` as a small server binary or script-backed HTTP server.
- Default bind address: `127.0.0.1:8787`.
- Implement health endpoint.
- Implement message insert, unread, mark-read, history, teams, and team members endpoints.
- Reuse or mirror the SQLite event-log implementation.
- Add structured JSON responses and stable error schema.

Acceptance criteria:

- Server can initialize its DB.
- Server can send, list, read, and mark messages.
- No Web UI required yet.
- API can be exercised with `curl`.
- Server does not expose itself publicly unless explicitly configured.

### Phase 3: Remote storage driver

Tasks:

- Add `scripts/drivers/storage/remote.sh`.
- Add remote config commands.
- Implement `storage_check`, `storage_describe`, `storage_init`, `storage_insert_message`, `storage_unread`, `storage_mark_read`, `storage_mark_read_batch`, `storage_history`, `storage_teams`, `storage_team_members`, `storage_export`, and `storage_import`.
- Add client-side token support.
- Add friendly errors for unreachable server, unauthorized token, TLS issues, and version mismatch.

Acceptance criteria:

- `agmsg storage switch remote` works after configuration.
- Existing shell commands work through remote storage.
- Local storage can be restored by switching back.
- Remote storage is compatible with Claude Code, Codex CLI, Codex app, Gemini CLI, and shell mode subject to each runtime's delivery constraints.

### Phase 4: Browser management GUI MVP

Tasks:

- Serve static UI from `agmsgd`.
- Add dashboard page.
- Add teams page.
- Add agents/registrations page.
- Add messages page.
- Add token management page if auth is enabled.
- Add server settings page.

Acceptance criteria:

- Browser can inspect server health, teams, agents, and message history.
- Browser can send a test message.
- Browser can mark messages read.
- UI works without a separate frontend development server in production.

### Phase 5: Security, admin, and hardening

Tasks:

- Add bearer token authentication.
- Add admin and agent token scopes.
- Add team-scoped tokens.
- Add token revocation.
- Add audit log view.
- Add rate limiting for mutating endpoints.
- Add CORS default deny.
- Add explicit public-bind warning.
- Add backup/export/import flows.

Acceptance criteria:

- Remote mode can be safely used behind VPN/Zero Trust.
- Public bind requires explicit flag and visible warning.
- Tokens can be created, listed, scoped, and revoked.
- Admin UI requires admin token unless server is explicitly in local no-auth mode.

### Phase 6: Packaging and installer integration

Tasks:

- Add release artifacts for `agmsgd` if compiled.
- Add installer option for server components.
- Add update path preserving DB and config.
- Add uninstall path preserving or removing server data based on flags.
- Document deployment recipes:
  - localhost only
  - LAN
  - Tailscale
  - WireGuard
  - Cloudflare Tunnel / Access
  - reverse proxy with TLS

Acceptance criteria:

- A new user can install local-only mode as before.
- A power user can enable server mode using documented commands.
- Upgrade does not destroy existing DBs.
- Server data can be backed up and restored.

## 7. Recommended implementation stack

### Server

Preferred:

- Go single binary.
- Embedded static assets.
- SQLite driver.
- Standard library HTTP server where possible.

Rationale:

- Easy distribution across macOS, Linux, and Windows.
- Good SQLite and HTTP support.
- No runtime dependency for production.
- Works well for a small admin UI.

Alternative:

- Rust single binary.
- Node.js server only if the project intentionally accepts a Node runtime requirement for server mode.

### Web UI

Preferred MVP:

- Static HTML + minimal TypeScript/JavaScript, or Svelte/Vite compiled to static assets.

Avoid in v1:

- Heavy SPA state machinery.
- Complex build pipeline required for local-only users.

### CLI remote driver

Preferred:

- Bash + `curl` + `jq` if available.
- Avoid mandatory `jq` if the rest of agmsg currently avoids it; use small Python snippets when needed.

## 8. Configuration plan

Local agmsg config should keep current defaults. Add remote config only when selected.

Example user config:

```yaml
storage:
  active: remote
  remote:
    url: https://agmsg.internal
    token_file: ~/.agents/skills/agmsg/secrets/remote.token
    tls_verify: true
    timeout_seconds: 10
```

Server config:

```yaml
server:
  listen: 127.0.0.1:8787
  public_base_url: http://127.0.0.1:8787
  auth: token
  db_path: ~/.agents/agmsgd/messages.db
  web: true
  cors:
    enabled: false
```

## 9. Risk register

| Risk | Impact | Mitigation |
|---|---:|---|
| Remote mode breaks local simplicity | High | Keep remote opt-in; do not change default install path |
| SQLite corruption from network filesystems | High | Never support shared SQLite file mode; server owns DB |
| Codex app sandbox prevents writes | Medium | Add doctor command and clear setup docs |
| Token leakage | High | Store tokens in separate secret files with restrictive permissions |
| GUI becomes too large | Medium | Scope GUI to admin/debug workflows, not full chat replacement |
| Delivery semantics differ by agent runtime | Medium | Keep delivery axis explicit and reject unsupported modes |
| Version skew between client and server | Medium | Add `/api/v1/health` version and compatibility check |
| CORS/auth misconfiguration | High | Default no CORS and localhost-only listen |

## 10. Suggested initial implementation sequence

1. `docs: add independent fork roadmap documents`
2. `codex: improve skill metadata and diagnostics`
3. `server: add agmsgd health and sqlite store skeleton`
4. `server: implement message and team API`
5. `storage: add remote HTTP storage driver`
6. `web: add dashboard and teams pages`
7. `web: add messages and agents pages`
8. `auth: add token scopes and admin UI`
9. `packaging: add server install/update docs`

## 11. Open questions

- Should `agmsgd` live inside the skill directory or in a user-level server data directory?
- Should server mode share the exact same DB schema as the local sqlite driver or maintain a server-owned schema with import/export compatibility?
- Should SSH transport be implemented before HTTP remote storage, or skipped in favor of HTTP + GUI?
- Should Web UI support message composition to agents, or remain read-only until token scopes are complete?
- How should Codex app Cloud mode discover the remote server configuration?
- Should team names and agent names be normalized server-side?
- What minimum OS targets are required for `agmsgd` releases?

## 12. References checked while drafting

- Repository: https://github.com/2bbb/agmsg-hub
- Architecture: https://github.com/2bbb/agmsg-hub/blob/main/ARCHITECTURE.md
- Storage driver interface: https://github.com/2bbb/agmsg-hub/blob/main/docs/spec/driver-interface.md
- Codex Agent Skills: https://developers.openai.com/codex/skills
- Codex app features and modes: https://developers.openai.com/codex/app/features
