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

  bash "$SCRIPTS/server.sh" serve --host 127.0.0.1 --port "$SERVER_PORT" --db "$SERVER_DB" >"$SERVER_LOG" 2>&1 &
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
  [[ "$output" =~ 'id="teams"' ]]
  [[ "$output" =~ "/api/v1/teams" ]]
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
