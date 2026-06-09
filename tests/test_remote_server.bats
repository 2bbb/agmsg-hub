#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
  command -v node >/dev/null || skip "node is required for agmsgd tests"
  command -v curl >/dev/null || skip "curl is required for remote storage tests"

  SERVER_DB="$BATS_TEST_TMPDIR/server/messages.db"
  SERVER_PORT="$(node -e "const net=require('node:net'); const s=net.createServer(); s.listen(0, '127.0.0.1', () => { console.log(s.address().port); s.close(); });")"
  SERVER_URL="http://127.0.0.1:$SERVER_PORT"
  SERVER_LOG="$BATS_TEST_TMPDIR/agmsgd.log"

  bash "$BATS_TEST_DIRNAME/../server/server.sh" serve --host 127.0.0.1 --port "$SERVER_PORT" --db "$SERVER_DB" >"$SERVER_LOG" 2>&1 &
  SERVER_PID=$!

  wait_for_http "$SERVER_URL/api/v1/health"
}

teardown() {
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  teardown_test_env
}

wait_for_http() {
  local url="$1"
  local attempts="${2:-50}"
  local delay="${3:-0.1}"

  while [ "$attempts" -gt 0 ]; do
    curl -fsS "$url" >/dev/null 2>&1 && return 0
    sleep "$delay"
    attempts=$((attempts - 1))
  done

  echo "server did not become ready" >&2
  cat "$SERVER_LOG" >&2 || true
  return 1
}

@test "server: health endpoint reports sqlite storage" {
  run curl -fsS "$SERVER_URL/api/v1/health"
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"ok":true' ]]
  [[ "$output" =~ '"storage":"sqlite"' ]]
}

@test "server: root serves browser dashboard" {
  run curl -fsS "$SERVER_URL/"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "<title>agmsgd</title>" ]]
  [[ "$output" =~ 'id="project"' ]]
  [[ "$output" =~ "Bearer token" ]]
  [[ "$output" =~ "/api/v1/projects" ]]
  [[ "$output" =~ 'href="/archive"' ]]
  [[ "$output" =~ 'id="archive-project"' ]]
  [[ "$output" =~ "/api/v1/role-instructions" ]]
  [[ "$output" =~ "History" ]]
  [[ "$output" =~ "Send" ]]
  [[ "$output" =~ "Actas" ]]
  [[ "$output" =~ "Clients" ]]
  [[ ! "$output" =~ "Regs" ]]

  run curl -fsS "$SERVER_URL/archive"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Archive" ]]
  [[ "$output" =~ 'id="archive-list"' ]]
}

@test "remote storage: env-selected send, inbox, read, and history roundtrip" {
  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/send.sh" testteam alice bob "hello remote"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Sent to bob" ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/inbox.sh" testteam bob
  [ "$status" -eq 0 ]
  [[ "$output" =~ "1 new message" ]]
  [[ "$output" =~ "alice: hello remote" ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/inbox.sh" testteam bob
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No new messages" ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/history.sh" testteam
  [ "$status" -eq 0 ]
  [[ "$output" =~ "alice → bob: hello remote" ]]
  [[ "$output" =~ "○" ]]
}

@test "remote storage: read receipts are scoped to client id" {
  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/send.sh" testteam alice bob "remote per-client"
  [ "$status" -eq 0 ]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=client-a \
    bash "$SCRIPTS/inbox.sh" testteam bob
  [ "$status" -eq 0 ]
  [[ "$output" =~ "remote per-client" ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=client-a \
    bash "$SCRIPTS/inbox.sh" testteam bob
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No new messages" ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=client-b \
    bash "$SCRIPTS/inbox.sh" testteam bob
  [ "$status" -eq 0 ]
  [[ "$output" =~ "remote per-client" ]]
}

@test "remote storage: configure and switch make remote the default" {
  run bash "$SCRIPTS/remote.sh" configure "$SERVER_URL"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Configured remote.url" ]]

  run bash "$SCRIPTS/remote.sh" switch remote
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Switched storage.active = remote" ]]

  run bash "$SCRIPTS/remote.sh" status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "storage.active=remote" ]]
  [[ "$output" =~ "remote.health=ok" ]]

  run bash "$SCRIPTS/send.sh" testteam alice bob "configured remote"
  [ "$status" -eq 0 ]

  run bash "$SCRIPTS/inbox.sh" testteam bob
  [ "$status" -eq 0 ]
  [[ "$output" =~ "configured remote" ]]

  run bash "$SCRIPTS/remote.sh" switch local
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Switched storage.active = sqlite" ]]
}

@test "remote storage: join, team, and whoami use server registry" {
  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/join.sh" testteam alice codex /tmp/remote-proj-a
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Created team: testteam" ]]
  [[ "$output" =~ "Joined team testteam as alice" ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/join.sh" testteam bob codex /tmp/remote-proj-b
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Joined team testteam as bob" ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/team.sh" testteam
  [ "$status" -eq 0 ]
  [[ "$output" =~ "alice" ]]
  [[ "$output" =~ "bob" ]]
  [[ "$output" =~ "2 member" ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/whoami.sh" /tmp/remote-proj-a codex
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=alice" ]]
  [[ "$output" =~ "teams=testteam" ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/whoami.sh" /tmp/remote-unknown codex
  [ "$status" -eq 0 ]
  [[ "$output" =~ "suggest=true" ]]
  [[ "$output" =~ "agents=alice,bob" ]]
  [[ "$output" =~ "available_teams=testteam" ]]

  run curl -fsS "$SERVER_URL/api/v1/projects"
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"team":"testteam"' ]]
  [[ "$output" =~ 'remote-proj-a' ]]
  [[ "$output" =~ 'remote-proj-b' ]]
}

@test "remote storage: same project path on different clients stays distinct" {
  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=client-a AGMSG_CLIENT_LABEL=alpha \
    bash "$SCRIPTS/join.sh" testteam alice codex /tmp/shared-proj
  [ "$status" -eq 0 ]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=client-b AGMSG_CLIENT_LABEL=beta \
    bash "$SCRIPTS/join.sh" testteam bob codex /tmp/shared-proj
  [ "$status" -eq 0 ]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=client-a \
    bash "$SCRIPTS/whoami.sh" /tmp/shared-proj codex
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=alice" ]]
  [[ "$output" =~ "client=client-a" ]]
  [[ ! "$output" =~ "bob" ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=client-b \
    bash "$SCRIPTS/whoami.sh" /tmp/shared-proj codex
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=bob" ]]
  [[ "$output" =~ "client=client-b" ]]
  [[ ! "$output" =~ "alice" ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=client-a \
    bash "$SCRIPTS/reset.sh" /tmp/shared-proj codex alice
  [ "$status" -eq 0 ]
  [[ "$output" =~ "removed 1 registration" ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=client-b \
    bash "$SCRIPTS/whoami.sh" /tmp/shared-proj codex
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=bob" ]]
}

@test "remote storage: role instructions roundtrip via API and script" {
  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/join.sh" testteam reviewer codex /tmp/remote-reviewer
  [ "$status" -eq 0 ]

  run curl -fsS -X POST "$SERVER_URL/api/v1/role-instructions" \
    -H "content-type: application/json" \
    -d '{"team":"testteam","agent":"reviewer","body":"Review code.\nFocus regressions."}'
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"agent":"reviewer"' ]]
  [[ "$output" =~ "Focus regressions" ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/role-instructions.sh" get testteam reviewer
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Review code." ]]
  [[ "$output" =~ "Focus regressions." ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/role-instructions.sh" set testteam reviewer "Keep the architecture lens."
  [ "$status" -eq 0 ]

  run curl -fsS -G "$SERVER_URL/api/v1/role-instructions" \
    --data-urlencode team=testteam \
    --data-urlencode agent=reviewer
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Keep the architecture lens." ]]
}

@test "remote storage: inbox --wait receives a later message" {
  (
    sleep 1
    AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
      bash "$SCRIPTS/send.sh" testteam alice bob "remote delayed" >/dev/null
  ) &
  local sender_pid=$!

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/inbox.sh" testteam bob --wait 5 --poll 1
  wait "$sender_pid" 2>/dev/null || true

  [ "$status" -eq 0 ]
  [[ "$output" =~ "remote delayed" ]]
}

@test "remote storage: check-inbox uses remote unread messages" {
  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=hook-client \
    bash "$SCRIPTS/join.sh" testteam reviewer codex /tmp/hook-proj
  [ "$status" -eq 0 ]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/send.sh" testteam alice reviewer "hook remote message"
  [ "$status" -eq 0 ]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=hook-client \
    bash "$SCRIPTS/check-inbox.sh" codex /tmp/hook-proj
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"decision": "block"' ]]
  [[ "$output" =~ "testteam/reviewer" ]]
  [[ "$output" =~ "hook remote message" ]]
}

@test "remote storage: archives project registrations and exposes them under archive" {
  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=archive-client AGMSG_CLIENT_LABEL=archive-host \
    bash "$SCRIPTS/join.sh" testteam reviewer codex /tmp/archive-proj
  [ "$status" -eq 0 ]

  run curl -fsS "$SERVER_URL/api/v1/projects"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "archive-proj" ]]

  run curl -fsS -X POST "$SERVER_URL/api/v1/projects/archive" \
    -H "content-type: application/json" \
    -d '{"team":"testteam","project_id":"/tmp/archive-proj","archived":true}'
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"archived":true' ]]
  [[ "$output" =~ '"updated":1' ]]

  run curl -fsS "$SERVER_URL/api/v1/projects"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "archive-proj" ]]

  run curl -fsS "$SERVER_URL/api/v1/projects?archived=1"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "archive-proj" ]]
  [[ "$output" =~ '"archived_at"' ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=archive-client \
    bash "$SCRIPTS/whoami.sh" /tmp/archive-proj codex
  [ "$status" -eq 0 ]
  [[ "$output" =~ "archived=true" ]]
  [[ "$output" =~ "agents=reviewer" ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=archive-client \
    bash "$SCRIPTS/check-inbox.sh" codex /tmp/archive-proj
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"decision": "block"' ]]
  [[ "$output" =~ "project registration is archived" ]]

  run curl -fsS -X POST "$SERVER_URL/api/v1/projects/archive" \
    -H "content-type: application/json" \
    -d '{"team":"testteam","project_id":"/tmp/archive-proj","archived":false}'
  [ "$status" -eq 0 ]
  [[ "$output" =~ '"archived":false' ]]
  [[ "$output" =~ '"updated":1' ]]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=archive-client \
    bash "$SCRIPTS/whoami.sh" /tmp/archive-proj codex
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=reviewer" ]]
}
