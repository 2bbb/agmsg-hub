# SPEC: agmsg server, remote storage, Codex app, and browser GUI

Status: draft  
Date: 2026-06-06  
Audience: independent fork maintainer and agent implementers

## 1. Scope

This specification defines an optional server-backed extension for agmsg.

It covers:

- Codex app integration behavior.
- `agmsgd` server behavior.
- Browser management GUI behavior.
- Remote HTTP storage driver behavior.
- API shape.
- Auth and token scopes.
- Data model extensions.
- Migration and compatibility requirements.

It does not replace the local sqlite storage driver or the existing no-daemon mode.

## 2. Terms

| Term | Meaning |
|---|---|
| agmsg | The existing skill and CLI script system. |
| agmsgd | Optional server process that owns the remote-mode data store and serves HTTP API + Web UI. |
| local mode | Existing no-daemon, no-network storage behavior. |
| remote mode | agmsg uses HTTP API to access an agmsgd server. |
| host agent | Claude Code, Codex, Codex app, Gemini CLI, Copilot CLI, Antigravity, or shell caller. |
| storage driver | Swappable implementation of the `storage_*` interface. |
| remote storage driver | Client-side storage driver that translates `storage_*` calls into HTTP API requests. |
| registration | A mapping from team + agent + agent_type + project path to an active identity record. |
| event log | Append-only store of message/team lifecycle events. |
| admin token | Token with server administration privileges. |
| agent token | Token scoped to agent or team operations. |

## 3. Compatibility requirements

### 3.1 Local compatibility

The following must remain true:

- Existing local installation works without `agmsgd`.
- Existing shell commands keep their arguments and output behavior where practical.
- Existing local sqlite data remains readable.
- Existing delivery modes keep their meaning.
- Existing skill invocation names remain configurable.

### 3.2 Codex compatibility

Codex app support must follow these constraints:

- Skills are supported by Codex CLI, IDE extension, and Codex app.
- Codex app Local and Worktree modes run on the user's computer and can use local storage if sandbox permissions allow it.
- Codex app Cloud mode must not assume access to the user's local `~/.agents/skills/agmsg` database.
- Codex has no monitor-equivalent delivery mode in current agmsg assumptions; support `turn` and `off` only.

### 3.3 Remote compatibility

Remote mode must implement the existing storage driver contract.

Required client functions:

```bash
storage_check
storage_describe
storage_init
storage_insert_message <team> <from> <to> <body>
storage_unread <team> <agent> [--limit N]
storage_mark_read <id>
storage_mark_read_batch <id> [<id> ...]
storage_history <team> <agent> [--limit N]
storage_teams
storage_team_members <team>
storage_export <file>
storage_import <file>
```

## 4. System architecture

### 4.1 Local mode

```text
host agent
  └─ agmsg skill
      └─ scripts/*.sh
          └─ storage driver: sqlite
              └─ local SQLite DB
```

### 4.2 Remote mode

```text
host agent
  └─ agmsg skill
      └─ scripts/*.sh
          └─ storage driver: remote
              └─ HTTPS API
                  └─ agmsgd
                      ├─ auth/token layer
                      ├─ API handlers
                      ├─ event projection layer
                      ├─ SQLite store
                      └─ embedded Web UI
```

### 4.3 Browser GUI

```text
browser
  └─ static Web UI served by agmsgd
      └─ same /api/v1 endpoints used by remote storage driver
```

The Web UI must not call private mutation functions that bypass auth, event logging, or validation.

## 5. Component specification

## 5.1 `agmsgd`

### Responsibilities

- Own the canonical remote-mode DB.
- Serve HTTP API under `/api/v1`.
- Optionally serve Web UI under `/`.
- Enforce auth and scopes.
- Validate requests.
- Serialize writes as required by SQLite/event-log semantics.
- Provide export/import and backup operations.
- Expose health, version, and compatibility information.

### Non-responsibilities

- It does not install VPN, TLS certificates, or reverse proxies.
- It does not run a hosted cloud service.
- It does not directly manage host-agent sandboxes.
- It does not implement every delivery mode itself.

### Process defaults

Default invocation:

```bash
agmsgd serve
```

Default behavior:

```yaml
listen: 127.0.0.1:8787
web: true
auth: token
db_path: ~/.agents/agmsgd/messages.db
public_base_url: http://127.0.0.1:8787
cors.enabled: false
```

Public network bind must be explicit:

```bash
agmsgd serve --listen 0.0.0.0:8787
```

When binding to non-loopback, print a warning unless `--yes-i-know-this-is-public` or equivalent explicit flag is supplied.

## 5.2 Remote storage driver

File:

```text
scripts/drivers/storage/remote.sh
```

### Responsibilities

- Read remote server configuration.
- Check dependencies: `curl`, and optionally `python3` or `jq` for JSON processing.
- Check server health and compatible API version.
- Translate storage driver functions to HTTP requests.
- Preserve structured output expected by existing commands.
- Convert common HTTP errors to agmsg driver statuses.

### Configuration

Suggested file:

```text
~/.agents/skills/<cmd>/config/storage-remote.yaml
```

Suggested fields:

```yaml
url: https://agmsg.internal
token_file: ~/.agents/skills/agmsg/secrets/remote.token
timeout_seconds: 10
tls_verify: true
agent_type_hint: codex
```

Environment variable overrides:

```bash
AGMSG_REMOTE_URL
AGMSG_REMOTE_TOKEN
AGMSG_REMOTE_TOKEN_FILE
AGMSG_REMOTE_TIMEOUT
AGMSG_REMOTE_TLS_VERIFY
```

### Error mapping

| HTTP / condition | Driver status | User-facing meaning |
|---|---|---|
| 200/201/204 | `ok` | Operation succeeded |
| Connection refused / timeout | `runtime_error` | Server unreachable |
| 401 | `runtime_error` | Token missing or invalid |
| 403 | `runtime_error` | Token lacks scope |
| 404 team/message | `runtime_error` | Requested resource not found |
| 409 | `runtime_error` | Conflict, stale state, or duplicate operation |
| 426 | `runtime_error` | Client/server version mismatch |
| 500 | `runtime_error` | Server error |

If the original project later defines additional driver statuses worth preserving, refine this mapping.

## 5.3 Web UI

### Pages

#### Dashboard

Shows:

- Server status.
- Version.
- Storage type and DB path, with sensitive path hiding option.
- Team count.
- Agent count.
- Message count.
- Unread count.
- Last event timestamp.
- Public bind warning.
- Auth status.

#### Teams

Shows:

- Team list.
- Member count.
- Last activity.
- Actions: view, create, rename, archive/delete if supported.

#### Team detail

Shows:

- Members.
- Registrations.
- Recent messages.
- Unread queues.
- Delivery modes by registration if available.

#### Agents

Shows:

- Agent name.
- Agent type.
- Teams.
- Project registrations.
- Last seen.
- Active `actas` locks if exported by local/runtime state.

#### Messages

Shows:

- Team filter.
- From filter.
- To filter.
- Unread-only toggle.
- Search.
- Message timeline.
- Send message form.
- Mark read action.

#### Events / Audit log

Shows raw projected events:

- `message_sent`
- `message_read`
- `team_joined`
- `team_left`
- `token_created`
- `token_revoked`
- `server_started` if logged
- `config_changed` if logged

#### Tokens

Admin-only page:

- List tokens by name, scope, created time, last used time.
- Create token.
- Revoke token.
- Rotate token.
- Copy token once after creation.

#### Settings

Shows:

- Listen address.
- Public base URL.
- CORS status.
- DB path.
- Auth mode.
- Export/import buttons.
- Compact button if implemented.

### UI constraints

- Must be usable from desktop browser.
- Must work behind reverse proxy path prefix if configured.
- Must not require authentication flows unsupported by Codex in-app browser.
- Must avoid storing bearer tokens in localStorage if possible. Prefer HTTP-only cookie for browser sessions when served by `agmsgd`.
- If bearer token is manually pasted, store in memory by default and offer explicit remember option.

## 6. Data model

## 6.1 Existing event model

Continue to use append-only events for core message semantics.

Canonical event examples:

```json
{"type":"message_sent","id":"0192...","team":"proj-a","from":"alice","to":"bob","body":"please review","at":"2026-06-06T10:00:00Z"}
{"type":"message_read","id":"0192...","msg_id":"0192...","agent":"bob","at":"2026-06-06T10:01:00Z"}
{"type":"team_joined","id":"0192...","team":"proj-a","agent":"alice","agent_type":"codex","project":"/work/repo","at":"2026-06-06T10:02:00Z"}
{"type":"team_left","id":"0192...","team":"proj-a","agent":"alice","at":"2026-06-06T10:03:00Z"}
```

## 6.2 Server-specific tables

Suggested tables:

```sql
CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  at TEXT NOT NULL,
  body_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_type_at ON events(type, at);
CREATE INDEX IF NOT EXISTS idx_events_at ON events(at);
```

Token table:

```sql
CREATE TABLE IF NOT EXISTS tokens (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  scopes_json TEXT NOT NULL,
  team TEXT,
  agent TEXT,
  created_at TEXT NOT NULL,
  last_used_at TEXT,
  revoked_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_tokens_name ON tokens(name);
CREATE INDEX IF NOT EXISTS idx_tokens_team ON tokens(team);
```

Optional server event table can reuse the same `events` table with server event types.

## 6.3 Event projection views

The server should expose projections for:

- Teams.
- Team members.
- Registrations.
- Messages.
- Unread queues.
- Audit timeline.

Projection can be computed on demand initially. Materialized projection tables can be added later if performance requires them.

## 7. HTTP API

All API endpoints are under:

```text
/api/v1
```

All JSON responses use:

```http
Content-Type: application/json
```

Errors use a stable shape:

```json
{
  "error": {
    "code": "unauthorized",
    "message": "Missing or invalid token",
    "details": {}
  }
}
```

### 7.1 Health and metadata

#### `GET /api/v1/health`

Response:

```json
{
  "status": "ok",
  "server_version": "0.1.0",
  "api_version": "v1",
  "storage": "sqlite",
  "auth": "token",
  "web": true,
  "time": "2026-06-06T10:00:00Z"
}
```

#### `GET /api/v1/capabilities`

Response:

```json
{
  "api_version": "v1",
  "features": {
    "messages": true,
    "teams": true,
    "registrations": true,
    "tokens": true,
    "events": true,
    "sse": false,
    "export_import": true
  },
  "min_remote_driver_version": "0.1.0"
}
```

### 7.2 Teams

#### `GET /api/v1/teams`

Response:

```json
{
  "teams": [
    {
      "team": "proj-a",
      "member_count": 3,
      "message_count": 42,
      "last_activity_at": "2026-06-06T10:00:00Z"
    }
  ]
}
```

#### `GET /api/v1/teams/{team}`

Response:

```json
{
  "team": "proj-a",
  "members": ["alice", "bob"],
  "registrations": [],
  "message_count": 42,
  "unread_count": 4
}
```

#### `GET /api/v1/teams/{team}/members`

Response:

```json
{
  "team": "proj-a",
  "members": [
    {
      "agent": "alice",
      "agent_types": ["claude-code", "codex"],
      "projects": ["/work/repo"],
      "last_seen_at": "2026-06-06T10:00:00Z"
    }
  ]
}
```

#### `POST /api/v1/teams/{team}/join`

Request:

```json
{
  "agent": "alice",
  "agent_type": "codex",
  "project": "/work/repo",
  "delivery_mode": "turn"
}
```

Response:

```json
{
  "ok": true,
  "event_id": "0192..."
}
```

#### `POST /api/v1/teams/{team}/leave`

Request:

```json
{
  "agent": "alice"
}
```

Response:

```json
{
  "ok": true,
  "event_id": "0192..."
}
```

### 7.3 Messages

#### `POST /api/v1/messages`

Request:

```json
{
  "team": "proj-a",
  "from": "alice",
  "to": "bob",
  "body": "please review api/server.go",
  "metadata": {
    "agent_type": "codex",
    "project": "/work/repo"
  }
}
```

Response:

```json
{
  "id": "0192...",
  "team": "proj-a",
  "from": "alice",
  "to": "bob",
  "body": "please review api/server.go",
  "at": "2026-06-06T10:00:00Z"
}
```

#### `GET /api/v1/messages`

Query parameters:

- `team` required for most client calls.
- `agent` optional.
- `to` optional.
- `from` optional.
- `unread` optional boolean.
- `limit` optional integer.
- `cursor` optional pagination cursor.

Example:

```text
GET /api/v1/messages?team=proj-a&agent=bob&unread=1&limit=50
```

Response:

```json
{
  "messages": [
    {
      "id": "0192...",
      "team": "proj-a",
      "from": "alice",
      "to": "bob",
      "body": "please review",
      "at": "2026-06-06T10:00:00Z",
      "read": false
    }
  ],
  "next_cursor": null
}
```

#### `POST /api/v1/messages/{id}/read`

Request:

```json
{
  "agent": "bob"
}
```

Response:

```json
{
  "ok": true,
  "event_id": "0192..."
}
```

#### `POST /api/v1/messages/read-batch`

Request:

```json
{
  "agent": "bob",
  "ids": ["0192...", "0193..."]
}
```

Response:

```json
{
  "ok": true,
  "event_ids": ["0194...", "0195..."]
}
```

#### `GET /api/v1/history`

Query parameters:

- `team` required.
- `agent` optional.
- `limit` optional.
- `cursor` optional.

Response shape mirrors `GET /messages` but includes read state when available.

### 7.4 Registrations and agents

#### `GET /api/v1/agents`

Response:

```json
{
  "agents": [
    {
      "agent": "alice",
      "teams": ["proj-a"],
      "agent_types": ["codex", "claude-code"],
      "projects": ["/work/repo"],
      "last_seen_at": "2026-06-06T10:00:00Z"
    }
  ]
}
```

#### `GET /api/v1/registrations`

Query parameters:

- `team` optional.
- `agent` optional.
- `agent_type` optional.
- `project` optional.

Response:

```json
{
  "registrations": [
    {
      "team": "proj-a",
      "agent": "alice",
      "agent_type": "codex",
      "project": "/work/repo",
      "delivery_mode": "turn",
      "joined_at": "2026-06-06T10:00:00Z",
      "last_seen_at": "2026-06-06T10:10:00Z"
    }
  ]
}
```

### 7.5 Events

#### `GET /api/v1/events`

Query parameters:

- `team` optional.
- `type` optional.
- `limit` optional.
- `cursor` optional.

Response:

```json
{
  "events": [
    {
      "id": "0192...",
      "type": "message_sent",
      "at": "2026-06-06T10:00:00Z",
      "body": {}
    }
  ],
  "next_cursor": null
}
```

#### `GET /api/v1/events/stream`

Optional post-MVP endpoint using Server-Sent Events.

Use cases:

- Browser live refresh.
- Future remote delivery optimizations.

The remote storage driver must not require SSE in v1.

### 7.6 Tokens

Token endpoints require admin scope.

#### `GET /api/v1/tokens`

Response:

```json
{
  "tokens": [
    {
      "id": "tok_0192...",
      "name": "macbook-codex",
      "scopes": ["message:read", "message:write", "team:read"],
      "team": "proj-a",
      "agent": "alice",
      "created_at": "2026-06-06T10:00:00Z",
      "last_used_at": null,
      "revoked_at": null
    }
  ]
}
```

#### `POST /api/v1/tokens`

Request:

```json
{
  "name": "macbook-codex",
  "scopes": ["message:read", "message:write", "team:read"],
  "team": "proj-a",
  "agent": "alice"
}
```

Response returns the raw token exactly once:

```json
{
  "id": "tok_0192...",
  "token": "agmsg_xxx",
  "name": "macbook-codex",
  "scopes": ["message:read", "message:write", "team:read"]
}
```

#### `POST /api/v1/tokens/{id}/revoke`

Response:

```json
{
  "ok": true
}
```

### 7.7 Export/import

#### `GET /api/v1/export`

Admin only. Returns JSONL or archive format.

#### `POST /api/v1/import`

Admin only. Accepts export format. Must support dry run:

```text
POST /api/v1/import?dry_run=1
```

## 8. Authentication and authorization

### 8.1 Auth modes

Supported v1 modes:

| Mode | Use case |
|---|---|
| `none-localhost` | Local dev only; allowed only on loopback bind. |
| `token` | Default for server mode. |

Future modes:

- Reverse proxy auth header.
- OIDC.
- mTLS.

### 8.2 Token format

Token prefix:

```text
agmsg_
```

Tokens must be stored server-side as hashes, not plaintext.

Suggested raw token shape:

```text
agmsg_<base64url-random-32-bytes>
```

### 8.3 Scopes

Initial scopes:

| Scope | Meaning |
|---|---|
| `admin` | Full administration. |
| `team:read` | List teams and members. |
| `team:write` | Join/leave teams. |
| `message:read` | Read messages and history. |
| `message:write` | Send messages and mark read. |
| `token:read` | List tokens. |
| `token:write` | Create/revoke tokens. |
| `export` | Export data. |
| `import` | Import data. |

Tokens can optionally be constrained to:

- `team`
- `agent`

Authorization rule:

```text
request allowed if token has required scope and requested team/agent falls within token constraints
```

### 8.4 Browser auth

Preferred for GUI:

- Admin logs in by pasting admin token.
- Server creates an HTTP-only session cookie.
- Web UI uses cookie auth for subsequent API requests.

MVP fallback:

- Web UI stores token in memory only.
- User pastes token again after refresh.

Avoid default localStorage token persistence.

## 9. Codex app integration spec

### 9.1 Skill metadata

`agents/openai.yaml` should include enough metadata for Codex app to show the skill clearly.

Suggested shape:

```yaml
display_name: agmsg
short_description: Cross-agent messaging for local and remote agent teams.
allow_implicit_invocation: true
```

If Codex plugin packaging is added later, package metadata should remain separate from the skill workflow instructions.

### 9.2 Invocation

Codex app user-visible usage:

```text
$agmsg
$agmsg send bob please review this change
$agmsg history
$agmsg team
$agmsg mode turn
```

### 9.3 Modes

| Codex app mode | Storage support | Notes |
|---|---|---|
| Local | local or remote | Local sqlite works if writable roots allow it. |
| Worktree | local or remote | Worktree path becomes part of registration metadata. |
| Cloud | remote only | Local user DB is not assumed to exist. |

### 9.4 Delivery modes

| Delivery mode | Codex app support | Notes |
|---|---|---|
| `turn` | yes | Default for Codex. |
| `off` | yes | Manual checks only. |
| `monitor` | no | Reject with clear message. |
| `both` | no | Reject with clear message unless monitor support appears. |

### 9.5 Diagnostics

`doctor.sh codex <project>` should check:

- Skill directory exists.
- `SKILL.md` exists and has valid metadata.
- `agents/openai.yaml` exists.
- `sqlite3` exists for local mode.
- `curl` exists for remote mode.
- Writable DB/config paths are accessible.
- Codex `writable_roots` covers local agmsg data paths when sandboxing is in use.
- Project Codex hooks JSON is valid when present.
- Active storage driver is compatible with current runtime target.
- Delivery mode is compatible with Codex.

Human output should stay readable. `doctor.sh --porcelain codex <project>` should emit stable tab-separated records:

```text
check<TAB><id><TAB><ok|warn|fail><TAB><message>
fix<TAB><id><TAB><action><TAB><path><TAB><config>
summary<TAB><ok|fail><TAB><failures><TAB><warnings>
```

When a Codex writable-root fix is possible, porcelain output should include `fix ... add_codex_writable_root ...`.

`doctor.sh --apply-fixes codex <project>` may mutate only explicitly safe local configuration. Initial allowed mutation:

- Create or update Codex `[sandbox_workspace_write].writable_roots`.
- Back up an existing Codex config to `<config>.bak` before editing.
- Do not alter message DBs, team configs, hooks, or delivery mode.

Implementation boundary:

- `scripts/doctor.sh` owns command-line options, checks, and output format.
- `scripts/lib/codex-config.sh` owns narrow Codex config parsing/updating for writable roots.

Codex skill-facing aliases:

```text
$agmsg doctor
$agmsg doctor raw
$agmsg doctor fix
```

- `doctor` runs porcelain diagnostics and summarizes failures/warnings.
- `doctor raw` prints porcelain diagnostics directly.
- `doctor fix` runs `doctor.sh --apply-fixes --porcelain codex "$(pwd)"`.

## 10. CLI and command UX

### 10.1 Server commands

Preferred commands if `agmsgd` is compiled:

```bash
agmsgd init
agmsgd serve
agmsgd serve --listen 127.0.0.1:8787
agmsgd serve --listen 0.0.0.0:8787 --auth token
agmsgd token create --name macbook-codex --team proj-a --agent alice
agmsgd token list
agmsgd token revoke <id>
agmsgd export > agmsg-export.jsonl
agmsgd import agmsg-export.jsonl
agmsgd compact
```

### 10.2 Client commands

Preferred additions to existing agmsg CLI/scripts:

```bash
agmsg storage list
agmsg storage switch remote
agmsg remote configure https://agmsg.internal
agmsg remote token set
agmsg remote status
agmsg remote doctor
```

Script equivalents can live under:

```text
scripts/storage.sh
scripts/remote.sh
scripts/doctor.sh
```

## 11. Validation rules

### Names

Team and agent names:

- Must be non-empty.
- Recommended allowed characters: `A-Z`, `a-z`, `0-9`, `_`, `-`, `.`, `/` for team namespaces only if already supported.
- Reject names containing control characters.
- Reject path traversal semantics when names are used in filesystem paths.

### Message bodies

- Must be UTF-8.
- Default max size: 64 KiB.
- Configurable server-side.
- Store exact text; do not interpret Markdown or commands server-side.

### Projects

- Store project path as metadata.
- Do not require path to exist on server for remote clients.
- Consider hashing or redacting paths in GUI if privacy mode is enabled.

## 12. Concurrency and consistency

### 12.1 Server writes

All event writes should happen inside SQLite transactions.

Write path:

1. Validate request.
2. Authorize request.
3. Generate UUIDv7 event/message ID.
4. Insert event row.
5. Commit.
6. Return projected record.

### 12.2 Read-after-write

A successful write must be immediately visible to subsequent reads on the same server process.

### 12.3 Idempotency

Post-MVP, support optional idempotency keys for message send:

```http
Idempotency-Key: <client-generated-key>
```

MVP can omit this if duplicate sends are acceptable.

### 12.4 Pagination

Use cursor-based pagination for API responses with history/event lists.

Cursor may encode:

- `at`
- `id`

Do not expose raw SQL offsets as stable API if avoidable.

## 13. Import/export format

### 13.1 Export

MVP export can be JSONL events:

```jsonl
{"type":"message_sent",...}
{"type":"message_read",...}
```

Include metadata header as first line or sidecar:

```json
{"type":"agmsg_export_header","version":"1","created_at":"2026-06-06T10:00:00Z"}
```

### 13.2 Import

Import must:

- Validate JSONL.
- Reject unknown required fields.
- Support dry-run.
- Avoid duplicate event IDs.
- Preserve event IDs where possible.

## 14. Observability

### Logs

Server logs should include:

- start/stop
- listen address
- DB path
- auth mode
- request method/path/status/duration
- token ID, not raw token
- error code

Avoid logging:

- raw token
- full message body by default
- private project paths when privacy mode is enabled

### Health

Health endpoint must not leak sensitive config. Admin endpoint can expose more detail.

## 15. Testing strategy

### 15.1 Unit tests

- API request validation.
- Token hashing and scope matching.
- Event projection.
- Message unread logic.
- Import/export validation.
- Remote driver response parsing.

### 15.2 Integration tests

- Start `agmsgd` with temp DB.
- Configure remote driver against local server.
- Run existing send/inbox/history/team flows through remote storage.
- Test unauthorized and forbidden cases.
- Test switching local -> remote -> local.

### 15.3 Agent compatibility tests

- Claude Code local mode smoke test.
- Codex CLI smoke test.
- Codex app Local mode manual test.
- Codex app Worktree mode manual test.
- Gemini CLI smoke test if available.

### 15.4 Browser tests

- Dashboard loads.
- Teams page loads.
- Messages page sends message.
- Mark read updates unread count.
- Token page hides raw token after creation.

## 16. Acceptance criteria for v0.1 server release

A v0.1 server release is acceptable when:

- Local-only agmsg remains unchanged.
- `agmsgd serve` starts with an empty DB.
- Admin token can be generated.
- Remote driver can send/read/mark/history/team through HTTP.
- Browser dashboard, teams, agents, and messages pages work.
- Server binds to localhost by default.
- Remote deployment behind VPN/Zero Trust is documented.
- Tests cover the remote driver happy path and common auth failures.

## 17. Future extensions

- SSH transport driver.
- SSE/browser live updates.
- Team-scoped Web UI mode.
- Reverse-proxy auth.
- OIDC.
- mTLS.
- WebSocket delivery for capable future agents.
- Server-side search index.
- Message attachments.
- Project aliases to avoid leaking full paths.
- Plugin distribution for Codex.
- Separate mobile-friendly admin UI.

## 18. References checked while drafting

- Repository: https://github.com/2bbb/agmsg-hub
- Architecture: https://github.com/2bbb/agmsg-hub/blob/main/ARCHITECTURE.md
- Storage driver interface: https://github.com/2bbb/agmsg-hub/blob/main/docs/spec/driver-interface.md
- Codex Agent Skills: https://developers.openai.com/codex/skills
- Codex app features and modes: https://developers.openai.com/codex/app/features
