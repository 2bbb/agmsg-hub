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
  if [ -n "${EXTRA_SERVER_PID:-}" ]; then
    kill "$EXTRA_SERVER_PID" 2>/dev/null || true
    wait "$EXTRA_SERVER_PID" 2>/dev/null || true
  fi
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

@test "server: migrates legacy messages table before project index creation" {
  local legacy_db="$BATS_TEST_TMPDIR/legacy/messages.db"
  local legacy_port legacy_url legacy_log legacy_pid
  mkdir -p "$(dirname "$legacy_db")"
  sqlite3 "$legacy_db" "
    CREATE TABLE messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      team TEXT NOT NULL,
      from_agent TEXT NOT NULL,
      to_agent TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
      read_at TEXT
    );
    INSERT INTO messages (team, from_agent, to_agent, body)
    VALUES ('legacy', 'alice', 'bob', 'old row');
  "

  legacy_port="$(node -e "const net=require('node:net'); const s=net.createServer(); s.listen(0, '127.0.0.1', () => { console.log(s.address().port); s.close(); });")"
  legacy_url="http://127.0.0.1:$legacy_port"
  legacy_log="$BATS_TEST_TMPDIR/agmsgd-legacy.log"

  bash "$BATS_TEST_DIRNAME/../server/server.sh" serve --host 127.0.0.1 --port "$legacy_port" --db "$legacy_db" >"$legacy_log" 2>&1 &
  legacy_pid=$!
  EXTRA_SERVER_PID="$legacy_pid"
  wait_for_http "$legacy_url/api/v1/health" || {
    cat "$legacy_log" >&2 || true
    return 1
  }

  run sqlite3 "$legacy_db" "SELECT COUNT(*) FROM pragma_table_info('messages') WHERE name = 'project_id';"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  run sqlite3 "$legacy_db" "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name = 'idx_messages_project';"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  kill "$legacy_pid" 2>/dev/null || true
  wait "$legacy_pid" 2>/dev/null || true
  EXTRA_SERVER_PID=""
}

@test "server: canonicalizes stored git project keys on startup" {
  local db="$BATS_TEST_TMPDIR/canonical/messages.db"
  local port url log pid
  mkdir -p "$(dirname "$db")"
  sqlite3 "$db" "
    CREATE TABLE teams (
      name TEXT PRIMARY KEY,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
    );
    CREATE TABLE registrations (
      team TEXT NOT NULL,
      agent TEXT NOT NULL,
      agent_type TEXT NOT NULL,
      project_path TEXT NOT NULL,
      client_id TEXT NOT NULL,
      client_label TEXT NOT NULL DEFAULT '',
      hostname TEXT,
      project_key TEXT,
      archived_at TEXT,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
      PRIMARY KEY (team, agent, agent_type, client_id, project_path)
    );
    INSERT INTO teams (name) VALUES ('splitteam');
    INSERT INTO registrations (team, agent, agent_type, project_path, client_id, client_label, project_key)
    VALUES
      ('splitteam', 'mac', 'codex', '/tmp/mac', 'client-a', 'mac', 'git:git@github.com:acme/example.git'),
      ('splitteam', 'win', 'codex', 'C:\\Users\\me\\example', 'client-b', 'win', 'git:git@github.com:acme/example');
  "

  port="$(node -e "const net=require('node:net'); const s=net.createServer(); s.listen(0, '127.0.0.1', () => { console.log(s.address().port); s.close(); });")"
  url="http://127.0.0.1:$port"
  log="$BATS_TEST_TMPDIR/agmsgd-canonical.log"

  bash "$BATS_TEST_DIRNAME/../server/server.sh" serve --host 127.0.0.1 --port "$port" --db "$db" >"$log" 2>&1 &
  pid=$!
  EXTRA_SERVER_PID="$pid"
  wait_for_http "$url/api/v1/health" || {
    cat "$log" >&2 || true
    return 1
  }

  run curl -fsS "$url/api/v1/projects"
  [ "$status" -eq 0 ]
  JSON="$output" node -e '
    const data = JSON.parse(process.env.JSON);
    const projects = data.projects.filter((project) => project.team === "splitteam");
    if (projects.length !== 1) process.exit(1);
    if (projects[0].project_id !== "git:git@github.com:acme/example") process.exit(1);
    if (projects[0].roles !== 2) process.exit(1);
  '

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  EXTRA_SERVER_PID=""
}

@test "server: root serves browser dashboard" {
  run curl -fsS "$SERVER_URL/"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "<title>agmsgd</title>" ]]
  [[ "$output" =~ 'id="project"' ]]
  [[ "$output" =~ 'href="/all"' ]]
  [[ "$output" =~ "Bearer token" ]]
  [[ "$output" =~ "/api/v1/projects" ]]
  [[ "$output" =~ 'href="/archive"' ]]
  [[ "$output" =~ 'id="archive-project"' ]]
  [[ "$output" =~ "/api/v1/role-instructions" ]]
  [[ "$output" =~ "History" ]]
  [[ "$output" =~ 'id="history-limit"' ]]
  [[ "$output" =~ 'id="history-prev"' ]]
  [[ "$output" =~ 'id="history-next"' ]]
  [[ "$output" =~ "Send" ]]
  [[ "$output" =~ "Actas" ]]
  [[ "$output" =~ "Clients" ]]
  [[ ! "$output" =~ "Regs" ]]

  run curl -fsS "$SERVER_URL/archive"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Archive" ]]
  [[ "$output" =~ 'id="archive-list"' ]]

  run curl -fsS "$SERVER_URL/all"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "All projects" ]]
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

@test "remote storage: history supports limit and offset pagination" {
  for n in 1 2 3 4 5; do
    run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
      bash "$SCRIPTS/send.sh" testteam alice bob "page message $n"
    [ "$status" -eq 0 ]
  done

  run curl -fsS -G "$SERVER_URL/api/v1/messages/history" \
    --data-urlencode team=testteam \
    --data-urlencode limit=2 \
    --data-urlencode offset=0
  [ "$status" -eq 0 ]
  JSON="$output" node -e '
    const data = JSON.parse(process.env.JSON);
    if (data.total !== 5 || data.limit !== 2 || data.offset !== 0 || data.has_prev !== false || data.has_next !== true) process.exit(1);
    const bodies = data.messages.map((message) => message.body);
    if (bodies.join("|") !== "page message 5|page message 4") process.exit(1);
  '

  run curl -fsS -G "$SERVER_URL/api/v1/messages/history" \
    --data-urlencode team=testteam \
    --data-urlencode limit=2 \
    --data-urlencode offset=2
  [ "$status" -eq 0 ]
  JSON="$output" node -e '
    const data = JSON.parse(process.env.JSON);
    if (data.total !== 5 || data.limit !== 2 || data.offset !== 2 || data.has_prev !== true || data.has_next !== true) process.exit(1);
    const bodies = data.messages.map((message) => message.body);
    if (bodies.join("|") !== "page message 3|page message 2") process.exit(1);
  '
}

@test "remote storage: git project keys ignore trailing dotgit" {
  run curl -fsS -X POST \
    -H "Content-Type: application/json" \
    -d '{"team":"dotgit","agent":"mac","type":"codex","project":"/tmp/dotgit-mac","client_id":"client-a","project_key":"git:git@github.com:acme/example.git"}' \
    "$SERVER_URL/api/v1/teams/join"
  [ "$status" -eq 0 ]

  run curl -fsS -X POST \
    -H "Content-Type: application/json" \
    -d '{"team":"dotgit","agent":"win","type":"codex","project":"C:\\Users\\me\\example","client_id":"client-b","project_key":"git:git@github.com:acme/example"}' \
    "$SERVER_URL/api/v1/teams/join"
  [ "$status" -eq 0 ]

  run curl -fsS "$SERVER_URL/api/v1/projects"
  [ "$status" -eq 0 ]
  JSON="$output" node -e '
    const data = JSON.parse(process.env.JSON);
    const projects = data.projects.filter((project) => project.team === "dotgit");
    if (projects.length !== 1) process.exit(1);
    if (projects[0].project_id !== "git:git@github.com:acme/example") process.exit(1);
    if (projects[0].roles !== 2) process.exit(1);
  '
}

@test "remote storage: node client supports Windows-native command path" {
  CLIENT="$BATS_TEST_DIRNAME/../scripts/agmsg-client.mjs"

  run node "$CLIENT" remote configure "$SERVER_URL"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Configured remote.url" ]]

  run node "$CLIENT" remote switch remote
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Switched storage.active = remote" ]]

  run node "$CLIENT" remote status
  [ "$status" -eq 0 ]
  [[ "$output" =~ "storage.active=remote" ]]
  [[ "$output" =~ "remote.health=ok" ]]

  run node "$CLIENT" join testteam win-codex codex /tmp/win-native-project
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Joined team testteam as win-codex" ]]

  run node "$CLIENT" whoami /tmp/win-native-project codex
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=win-codex" ]]
  [[ "$output" =~ "teams=testteam" ]]

  run node "$CLIENT" send testteam win-codex reviewer "hello from node client" --project /tmp/win-native-project
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Sent to reviewer" ]]

  run node "$CLIENT" join testteam reviewer codex /tmp/win-native-project
  [ "$status" -eq 0 ]

  run node "$CLIENT" inbox testteam reviewer --project /tmp/win-native-project
  [ "$status" -eq 0 ]
  [[ "$output" =~ "1 new message" ]]
  [[ "$output" =~ "win-codex: hello from node client" ]]

  run node "$CLIENT" history testteam reviewer 20 --project /tmp/win-native-project
  [ "$status" -eq 0 ]
  [[ "$output" =~ "win-codex → reviewer: hello from node client" ]]

  run node "$CLIENT" team testteam
  [ "$status" -eq 0 ]
  [[ "$output" =~ "win-codex" ]]
  [[ "$output" =~ "reviewer" ]]
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

@test "remote storage: project metadata scopes unread and history" {
  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/send.sh" testteam alice bob "remote project a" --project /tmp/remote-project-a
  [ "$status" -eq 0 ]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/send.sh" testteam alice bob "remote project b" --project /tmp/remote-project-b
  [ "$status" -eq 0 ]

  project_a_key="$(AGMSG_HUB_HOME="$TEST_SKILL_DIR" bash -c 'source "$1"; source "$2"; agmsg_project_key /tmp/remote-project-a' _ "$SCRIPTS/lib/storage.sh" "$SCRIPTS/lib/client.sh")"
  project_b_key="$(AGMSG_HUB_HOME="$TEST_SKILL_DIR" bash -c 'source "$1"; source "$2"; agmsg_project_key /tmp/remote-project-b' _ "$SCRIPTS/lib/storage.sh" "$SCRIPTS/lib/client.sh")"

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    bash "$SCRIPTS/inbox.sh" testteam bob --project /tmp/remote-project-a
  [ "$status" -eq 0 ]
  [[ "$output" =~ "remote project a" ]]
  [[ ! "$output" =~ "remote project b" ]]

  run curl -fsS -G "$SERVER_URL/api/v1/messages/history" \
    --data-urlencode team=testteam \
    --data-urlencode "project_id=$project_a_key" \
    --data-urlencode limit=20
  [ "$status" -eq 0 ]
  [[ "$output" =~ "remote project a" ]]
  [[ ! "$output" =~ "remote project b" ]]

  run curl -fsS -G "$SERVER_URL/api/v1/messages/history" \
    --data-urlencode limit=20
  [ "$status" -eq 0 ]
  [[ "$output" =~ "remote project a" ]]
  [[ "$output" =~ "remote project b" ]]
  [[ "$output" =~ "$project_a_key" ]]
  [[ "$output" =~ "$project_b_key" ]]
}

@test "remote storage: check-inbox uses remote unread messages" {
  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=hook-client \
    bash "$SCRIPTS/join.sh" testteam reviewer codex /tmp/hook-proj
  [ "$status" -eq 0 ]

  run env AGMSG_STORAGE_DRIVER=remote AGMSG_REMOTE_URL="$SERVER_URL" \
    AGMSG_CLIENT_ID=hook-client \
    bash "$SCRIPTS/send.sh" testteam alice reviewer "hook remote message" --project /tmp/hook-proj
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
