# ROADMAP: agmsg-hub server, remote sharing, Codex app, and Web UI

Status: draft  
Date: 2026-06-06

## Roadmap summary

This roadmap turns agmsg-hub into a local-first agmsg distribution with optional server-backed sharing and browser management.

The key rule is: keep local mode boring and stable. Add server mode as an opt-in layer.

```text
v0.0 baseline      fork hygiene + docs
v0.1 codex-app     skill metadata + diagnostics
v0.2 agmsgd-api    server API MVP
v0.3 remote-driver remote HTTP storage driver
v0.4 web-ui        browser dashboard/messages/admin MVP
v0.5 hardening     auth scopes, backup, deployment docs
v1.0 stable        packaged releases + compatibility guarantee
```

## Milestone 0: Fork baseline

Target: immediately after fork

### Goals

- Preserve local-only behavior.
- Add planning docs.
- Establish test and development conventions.

### Issues

#### M0.1 Add fork planning docs

Deliverables:

- `PLAN.md`
- `SPEC.md`
- `ROADMAP.md`

Acceptance:

- Docs describe Codex app, server, remote driver, and Web UI direction.
- Docs state local-only mode remains the default.

#### M0.2 Baseline test run

Deliverables:

- Document current test command.
- Record passing/failing tests before server changes.

Acceptance:

- Contributor can run tests from a fresh clone.
- Existing behavior is not modified.

#### M0.3 Add independent development strategy

Deliverables:

- Branch naming convention.
- Compatibility checklist.
- Release checklist.

Acceptance:

- Development notes remind maintainers not to break local-only mode.

## Milestone 1: Codex app polish

Target: v0.1

### Goals

- Make agmsg easier to use from Codex app.
- Improve diagnostics around Codex limitations.
- Clarify Local/Worktree/Cloud behavior.

### Issues

#### M1.1 Expand Codex skill metadata

Deliverables:

- Update `agents/openai.yaml` or equivalent installed metadata.
- Add short description and clearer display metadata.

Acceptance:

- Skill appears with meaningful name and description in Codex skill listings where available.
- Existing `$agmsg` invocation still works.

#### M1.2 Document Codex app modes

Deliverables:

- Update `SKILL.md` and README.
- Add Codex app section covering Local, Worktree, and Cloud.

Acceptance:

- Docs state Local/Worktree can use local storage.
- Docs state Cloud requires remote storage.
- Docs state Codex supports `turn` and `off` delivery only.

#### M1.3 Add Codex doctor command

Deliverables:

- `scripts/doctor.sh`
- Codex-specific checks under `doctor.sh codex`.

Checks:

- Skill files present.
- `sqlite3` present for local mode.
- `curl` present for remote mode.
- DB/config paths writable.
- Delivery mode compatible with runtime.

Acceptance:

- Doctor prints human-readable diagnostics.
- Doctor exits non-zero on actionable failure.
- Doctor emits `AGMSG-DIRECTIVE` when an agent-mediated fix is appropriate.

Status:

- Started. `doctor.sh codex` checks skill layout, executable scripts, `sqlite3`, writable local data directories, Codex `writable_roots`, hooks JSON validity, delivery-mode compatibility, and remote-storage absence. Codex config helpers live in `scripts/lib/codex-config.sh`. `doctor.sh --porcelain` emits stable `check`, `fix`, and `summary` records. `doctor.sh --apply-fixes` explicitly adds missing Codex `writable_roots`. The Codex template exposes `$agmsg doctor`, `$agmsg doctor raw`, and `$agmsg doctor fix`. Docs now state that Windows native shells are not supported for local mode.

#### M1.4 Improve unsupported delivery mode errors

Deliverables:

- Clear rejection for `monitor` and `both` under Codex.
- Suggested command: `agmsg mode turn`.

Acceptance:

- Codex users do not get silent partial behavior.

## Milestone 2: `agmsgd` API MVP

Target: v0.2

### Goals

- Add a server that owns SQLite/event-log storage.
- Provide an HTTP API usable by curl and future remote driver.
- Keep Web UI out of scope except a basic placeholder page.

### Issues

#### M2.1 Add server skeleton

Deliverables:

- `cmd/agmsgd/main.go` or equivalent.
- `agmsgd serve` command.
- Config loading.
- Default localhost binding.

Acceptance:

- `agmsgd serve` starts and logs bind address.
- `GET /api/v1/health` returns status JSON.

#### M2.2 Add server SQLite store

Deliverables:

- DB initialization.
- Events table.
- Token table placeholder if auth is included early.

Acceptance:

- Empty DB initializes automatically or via `agmsgd init`.
- Repeated start is idempotent.

#### M2.3 Implement message API

Endpoints:

- `POST /api/v1/messages`
- `GET /api/v1/messages`
- `POST /api/v1/messages/{id}/read`
- `POST /api/v1/messages/read-batch`
- `GET /api/v1/history`

Acceptance:

- Send/read/history round trip works through curl.
- Mark-read changes unread projection.
- Message IDs are opaque UUIDv7 or compatible generated IDs.

#### M2.4 Implement team API

Endpoints:

- `GET /api/v1/teams`
- `GET /api/v1/teams/{team}`
- `GET /api/v1/teams/{team}/members`
- `POST /api/v1/teams/{team}/join`
- `POST /api/v1/teams/{team}/leave`

Acceptance:

- Team join/leave writes events.
- Team members projection works.

#### M2.5 Add capabilities endpoint

Endpoint:

- `GET /api/v1/capabilities`

Acceptance:

- Remote driver can detect API version and supported features.

## Milestone 3: Remote HTTP storage driver

Target: v0.3

### Goals

- Make existing agmsg commands work through `agmsgd`.
- Provide remote sharing across machines.

### Issues

#### M3.1 Add remote storage driver

Deliverables:

- `scripts/drivers/storage/remote.sh`

Functions:

- `storage_check`
- `storage_describe`
- `storage_init`
- `storage_insert_message`
- `storage_unread`
- `storage_mark_read`
- `storage_mark_read_batch`
- `storage_history`
- `storage_teams`
- `storage_team_members`
- `storage_export`
- `storage_import`

Acceptance:

- Driver can be sourced by existing storage loader.
- Driver maps functions to HTTP calls.

#### M3.2 Add remote configuration command

Deliverables:

- `agmsg remote configure <url>`
- `agmsg remote token set`
- `agmsg remote status`

Acceptance:

- Remote config persists outside shell session.
- Token is stored in a secret file with restrictive permissions.

#### M3.3 Implement storage switch flow

Deliverables:

- `agmsg storage switch remote`
- Compatibility check against `/api/v1/health` and `/api/v1/capabilities`.

Acceptance:

- Switch succeeds only when server is reachable and compatible.
- Failed switch leaves existing storage active.

#### M3.4 Remote driver integration tests

Deliverables:

- Start temp server.
- Configure remote driver.
- Send/read/history/team tests.

Acceptance:

- Existing shell-level commands work with remote storage.

## Milestone 4: Browser Web UI MVP

Target: v0.4

### Goals

- Provide a browser GUI for server administration and debugging.
- Use the same API as remote clients.

### Issues

#### M4.1 Serve embedded static Web UI

Deliverables:

- `web/` source.
- Static build embedded or copied into server release.
- Root route `/` serves UI.

Acceptance:

- Opening `http://127.0.0.1:8787/` loads dashboard.
- API remains under `/api/v1`.

#### M4.2 Dashboard page

Shows:

- Health.
- Version.
- Storage.
- Teams count.
- Agents count.
- Messages count.
- Unread count.
- Last event.

Acceptance:

- Values load from API.
- Error state is readable if server/auth fails.

#### M4.3 Teams and team detail pages

Shows:

- Team list.
- Members.
- Registrations.
- Recent activity.

Acceptance:

- Admin can inspect who is in each team.

#### M4.4 Messages page

Features:

- Filter by team/from/to/unread.
- Send a message.
- Mark read.
- View history.

Acceptance:

- Admin can debug messaging from browser.
- Browser actions produce the same events as CLI actions.

#### M4.5 Agents page

Shows:

- Agent name.
- Agent type.
- Teams.
- Project registrations.
- Last seen where available.

Acceptance:

- Multi-project and multi-runtime registrations are visible.

## Milestone 5: Auth, security, and operations

Target: v0.5

### Goals

- Make remote mode safe for real personal/team use behind VPN or Zero Trust.
- Add backup/restore and admin tools.

### Issues

#### M5.1 Add bearer token auth

Deliverables:

- Token generation.
- Token hashing.
- Auth middleware.
- Admin token bootstrap.

Acceptance:

- Missing/invalid token returns 401.
- Revoked token no longer works.
- Raw token is shown only at creation time.

#### M5.2 Add token scopes

Scopes:

- `admin`
- `team:read`
- `team:write`
- `message:read`
- `message:write`
- `token:read`
- `token:write`
- `export`
- `import`

Acceptance:

- Team-scoped token cannot access another team.
- Agent-scoped token cannot impersonate another agent unless permitted.

#### M5.3 Token management UI

Deliverables:

- Token list.
- Create token form.
- Revoke action.
- Copy-once raw token display.

Acceptance:

- Admin can create a remote-client token without using CLI.

#### M5.4 Add export/import/backup UI and CLI

Deliverables:

- `agmsgd export`
- `agmsgd import`
- Web UI buttons.
- Dry-run import.

Acceptance:

- Export can restore into an empty DB.
- Import rejects malformed data.

#### M5.5 Add deployment docs

Recipes:

- Localhost only.
- LAN.
- Tailscale.
- WireGuard.
- Cloudflare Tunnel / Access.
- Reverse proxy with TLS.

Acceptance:

- Docs warn against exposing unauthenticated server publicly.
- Docs state that SQLite file sharing over network filesystem is unsupported.

## Milestone 6: Release packaging

Target: v1.0 candidate

### Goals

- Make server mode installable and updateable.
- Define compatibility guarantee.

### Issues

#### M6.1 Build release artifacts

Deliverables:

- macOS arm64.
- macOS amd64 if needed.
- Linux amd64.
- Linux arm64.
- Windows amd64 if supported.

Acceptance:

- `agmsgd --version` works on each target.

#### M6.2 Installer integration

Deliverables:

- `install.sh --server` or equivalent.
- Update path preserving data.
- Uninstall path with `--keep-data`.

Acceptance:

- Local-only users are not forced to install server binary.
- Server users can update without losing DB/config.

#### M6.3 Version compatibility policy

Deliverables:

- API version policy.
- Remote driver compatibility checks.
- Migration policy.

Acceptance:

- Client/server mismatch produces clear error.
- Server exposes minimum compatible remote driver version.

#### M6.4 v1.0 documentation pass

Deliverables:

- README server quickstart.
- Codex app guide.
- Remote sharing guide.
- Web UI admin guide.
- Security guide.

Acceptance:

- A new user can choose local-only or server mode without reading source code.

## Backlog

### Optional SSH transport

Purpose:

- Provide a daemon-light remote mode for users who already trust SSH.

Potential command shape:

```bash
agmsg storage switch ssh
agmsg ssh configure user@host ~/.agents/skills/agmsg
```

Acceptance:

- Send/read/history works through SSH.
- SSH mode is documented as separate from Web UI mode.

### SSE live updates

Purpose:

- Auto-refresh Web UI.
- Potential future push-like clients.

Acceptance:

- Browser message list updates without manual refresh.
- CLI remote driver does not depend on SSE.

### Project privacy aliases

Purpose:

- Avoid exposing full local paths in remote server UI.

Acceptance:

- Clients can send project alias/hash.
- Admin can opt into showing raw paths.

### Message search

Purpose:

- Search history by body/from/to/team.

Acceptance:

- Search is paginated.
- Search respects token scope.

### Reverse proxy auth

Purpose:

- Let Cloudflare Access, oauth2-proxy, or similar front agmsgd.

Acceptance:

- Server trusts configured header only from configured proxy source.

### OIDC

Purpose:

- First-class browser login for teams.

Acceptance:

- Optional; token auth remains available.

## Release checklist

### For every release

- Existing local mode smoke test.
- Remote driver smoke test if server code changed.
- Web UI smoke test if UI changed.
- Auth regression test if auth changed.
- Export/import compatibility check if schema changed.
- README updated.
- Changelog updated.

### For security-sensitive release

- Verify token hashes are not reversible.
- Verify raw tokens are not logged.
- Verify public bind warning.
- Verify CORS default deny.
- Verify team-scoped token isolation.

## Version targets

### v0.1: Codex app polish

Status: implementation complete; manual Codex app acceptance still pending.

Expected user value:

- Codex app users get clearer behavior and fewer setup failures.

Exit checklist:

- `docs/codex-app.md` contains Local, Worktree, and Cloud acceptance steps.
- `$agmsg doctor`, `$agmsg doctor raw`, and `$agmsg doctor fix` are documented.
- Installer ships `doctor.sh` and `scripts/lib/codex-config.sh`.
- Existing local install/update flows still preserve DB and team configs.
- BATS suite passes in an environment with bats-core installed. Last run:
  191/191 passed on 2026-06-08.
- Manual Codex app Local and Worktree acceptance is recorded before v0.1 is
  considered closed.

### v0.2: agmsgd API MVP

Expected user value:

- Developers can experiment with a local HTTP server.

### v0.3: Remote sharing MVP

Expected user value:

- Multiple machines can share messages through one server.

### v0.4: Web UI MVP

Expected user value:

- Server can be inspected and managed from a browser.

### v0.5: Secure remote beta

Expected user value:

- Safe use behind VPN/Zero Trust with scoped tokens and backup.

### v1.0: Stable optional server mode

Expected user value:

- Local-only mode and server mode are both documented, tested, and supportable.

## References checked while drafting

- Repository: https://github.com/2bbb/agmsg-hub
- Architecture: https://github.com/2bbb/agmsg-hub/blob/main/ARCHITECTURE.md
- Storage driver interface: https://github.com/2bbb/agmsg-hub/blob/main/docs/spec/driver-interface.md
- Codex Agent Skills: https://developers.openai.com/codex/skills
- Codex app features and modes: https://developers.openai.com/codex/app/features
