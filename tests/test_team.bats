#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

# --- join.sh ---

@test "join: creates team and adds agent" {
  run bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Joined team myteam as alice" ]]
}

@test "join: creates team config on first join" {
  bash "$SCRIPTS/join.sh" newteam first claude-code /tmp/proj
  [ -f "$TEST_SKILL_DIR/teams/newteam/config.json" ]
}

@test "join: adds multiple agents to same team" {
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj-a
  bash "$SCRIPTS/join.sh" myteam bob codex /tmp/proj-b
  run bash "$SCRIPTS/team.sh" myteam
  [[ "$output" =~ "alice" ]]
  [[ "$output" =~ "bob" ]]
  [[ "$output" =~ "2 member" ]]
}

@test "join: re-join with same name adds registration instead of duplicate agent" {
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj-a
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj-b
  run bash "$SCRIPTS/team.sh" myteam
  [ "$status" -eq 0 ]
  [[ "$output" =~ "alice" ]]
  [[ "$output" =~ "1 member" ]]
  [[ "$output" =~ "+1 more" ]]
}

@test "role-instructions: set and get local team role instruction" {
  bash "$SCRIPTS/join.sh" myteam reviewer codex /tmp/proj
  run bash "$SCRIPTS/role-instructions.sh" set myteam reviewer $'Review code.\nFocus regressions.'
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Updated instruction for reviewer" ]]

  run bash "$SCRIPTS/role-instructions.sh" get myteam reviewer
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Review code." ]]
  [[ "$output" =~ "Focus regressions." ]]
}

@test "role-instructions: re-join preserves local role instruction" {
  bash "$SCRIPTS/join.sh" myteam reviewer codex /tmp/proj-a
  bash "$SCRIPTS/role-instructions.sh" set myteam reviewer "Keep the architecture lens." >/dev/null
  bash "$SCRIPTS/join.sh" myteam reviewer codex /tmp/proj-b

  run bash "$SCRIPTS/role-instructions.sh" get myteam reviewer
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Keep the architecture lens." ]]
}

@test "role-instructions: refuses unknown local agent" {
  bash "$SCRIPTS/join.sh" myteam alice codex /tmp/proj
  run bash "$SCRIPTS/role-instructions.sh" set myteam missing "Nope"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Agent not found" ]]
}

# --- leave.sh ---

@test "leave: removes agent from team" {
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj
  bash "$SCRIPTS/join.sh" myteam bob claude-code /tmp/proj-b
  run bash "$SCRIPTS/leave.sh" myteam alice
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Left team myteam" ]]
  run bash "$SCRIPTS/team.sh" myteam
  [[ ! "$output" =~ "alice" ]]
  [[ "$output" =~ "bob" ]]
}

@test "leave: removes team dir when last member leaves" {
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj
  bash "$SCRIPTS/leave.sh" myteam alice
  [ ! -d "$TEST_SKILL_DIR/teams/myteam" ]
}

# --- team.sh ---

@test "team: shows team members with types" {
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj-a
  bash "$SCRIPTS/join.sh" myteam bob codex /tmp/proj-b
  run bash "$SCRIPTS/team.sh" myteam
  [ "$status" -eq 0 ]
  [[ "$output" =~ "alice" ]]
  [[ "$output" =~ "claude-code" ]]
  [[ "$output" =~ "bob" ]]
  [[ "$output" =~ "codex" ]]
}

# --- whoami.sh ---

@test "whoami: returns agent identity" {
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj
  run bash "$SCRIPTS/whoami.sh" /tmp/proj claude-code
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=alice" ]]
  [[ "$output" =~ "teams=myteam" ]]
}

@test "whoami: returns not_joined when no match" {
  run bash "$SCRIPTS/whoami.sh" /tmp/unknown claude-code
  [ "$status" -eq 0 ]
  [[ "$output" =~ "not_joined=true" ]]
}

@test "whoami: returns multiple when multiple identities" {
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj
  bash "$SCRIPTS/join.sh" myteam reviewer claude-code /tmp/proj
  run bash "$SCRIPTS/whoami.sh" /tmp/proj claude-code
  [ "$status" -eq 0 ]
  [[ "$output" =~ "multiple=true" ]]
  [[ "$output" =~ "alice" ]]
  [[ "$output" =~ "reviewer" ]]
}

@test "whoami: lists available teams when not joined" {
  bash "$SCRIPTS/join.sh" team1 alice claude-code /tmp/other
  run bash "$SCRIPTS/whoami.sh" /tmp/nothere claude-code
  [[ "$output" =~ "available_teams=team1" ]]
}

@test "whoami: finds re-joined agent in another project registration" {
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj-a
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj-b
  run bash "$SCRIPTS/whoami.sh" /tmp/proj-b claude-code
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=alice" ]]
  [[ "$output" =~ "teams=myteam" ]]
}

@test "whoami: suggests same-type agents registered elsewhere when no exact match" {
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj-a
  run bash "$SCRIPTS/whoami.sh" /tmp/proj-b claude-code
  [ "$status" -eq 0 ]
  [[ "$output" =~ "suggest=true" ]]
  [[ "$output" =~ "agents=alice" ]]
  [[ "$output" =~ "available_teams=myteam" ]]
}

@test "whoami: does not treat same path on another client as current identity" {
  AGMSG_CLIENT_ID=client-a AGMSG_CLIENT_LABEL=alpha bash "$SCRIPTS/join.sh" myteam alice codex /tmp/shared-proj
  AGMSG_CLIENT_ID=client-b AGMSG_CLIENT_LABEL=beta bash "$SCRIPTS/join.sh" myteam bob codex /tmp/shared-proj

  AGMSG_CLIENT_ID=client-a run bash "$SCRIPTS/whoami.sh" /tmp/shared-proj codex
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=alice" ]]
  [[ "$output" =~ "client=client-a" ]]
  [[ ! "$output" =~ "bob" ]]

  AGMSG_CLIENT_ID=client-b run bash "$SCRIPTS/whoami.sh" /tmp/shared-proj codex
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=bob" ]]
  [[ "$output" =~ "client=client-b" ]]
  [[ ! "$output" =~ "alice" ]]
}

@test "whoami: auto-detects claude-code from CLAUDE_CODE_SESSION_ID env" {
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj
  CLAUDE_CODE_SESSION_ID=test-session run bash "$SCRIPTS/whoami.sh" /tmp/proj
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=alice" ]]
  [[ "$output" =~ "type=claude-code" ]]
}

@test "whoami: auto-detects codex from CODEX_SANDBOX env" {
  bash "$SCRIPTS/join.sh" myteam bob codex /tmp/proj
  # Unset CLAUDE_CODE_SESSION_ID: bats can run under a CC session that
  # already exports it, which would shadow the codex signal under the
  # CLAUDE_CODE_SESSION_ID-first detection order.
  unset CLAUDE_CODE_SESSION_ID
  CODEX_SANDBOX=seatbelt run bash "$SCRIPTS/whoami.sh" /tmp/proj
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=bob" ]]
  [[ "$output" =~ "type=codex" ]]
}

@test "whoami: auto-detects codex from CODEX_THREAD_ID env" {
  bash "$SCRIPTS/join.sh" myteam bob codex /tmp/proj
  unset CLAUDE_CODE_SESSION_ID
  CODEX_THREAD_ID=some-thread run bash "$SCRIPTS/whoami.sh" /tmp/proj
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=bob" ]]
  [[ "$output" =~ "type=codex" ]]
}

@test "whoami: defaults to claude-code when no env vars set" {
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj
  run env -u CLAUDE_CODE_SESSION_ID -u CODEX_SANDBOX -u CODEX_THREAD_ID \
    -u GEMINI_API_KEY -u GOOGLE_GEMINI_CLI \
    AGMSG_DISABLE_PROCESS_DETECTION=1 \
    bash "$SCRIPTS/whoami.sh" /tmp/proj
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=alice" ]]
  [[ "$output" =~ "type=claude-code" ]]
}

@test "whoami: explicit type overrides auto-detection" {
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj
  bash "$SCRIPTS/join.sh" myteam bob codex /tmp/proj
  CODEX_SANDBOX=test run bash "$SCRIPTS/whoami.sh" /tmp/proj claude-code
  [ "$status" -eq 0 ]
  [[ "$output" =~ "agent=alice" ]]
  [[ "$output" =~ "type=claude-code" ]]
}

# --- reset.sh ---

@test "reset: removes only current project registration" {
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj-a
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj-b
  run bash "$SCRIPTS/reset.sh" /tmp/proj-a claude-code alice
  [ "$status" -eq 0 ]
  [[ "$output" =~ "removed 1 registration" ]]
  run bash "$SCRIPTS/whoami.sh" /tmp/proj-a claude-code
  [[ "$output" =~ "suggest=true" ]]
  run bash "$SCRIPTS/whoami.sh" /tmp/proj-b claude-code
  [[ "$output" =~ "agent=alice" ]]
}

@test "reset: removes agent when last registration is cleared" {
  bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj-a
  run bash "$SCRIPTS/reset.sh" /tmp/proj-a claude-code alice
  [ "$status" -eq 0 ]
  [[ "$output" =~ "removed 1 registration" ]]
  [ ! -d "$TEST_SKILL_DIR/teams/myteam" ]
}

@test "reset: removes only the current client registration for the same path" {
  AGMSG_CLIENT_ID=client-a AGMSG_CLIENT_LABEL=alpha bash "$SCRIPTS/join.sh" myteam alice codex /tmp/shared-proj
  AGMSG_CLIENT_ID=client-b AGMSG_CLIENT_LABEL=beta bash "$SCRIPTS/join.sh" myteam bob codex /tmp/shared-proj

  AGMSG_CLIENT_ID=client-a run bash "$SCRIPTS/reset.sh" /tmp/shared-proj codex alice
  [ "$status" -eq 0 ]
  [[ "$output" =~ "removed 1 registration" ]]

  AGMSG_CLIENT_ID=client-a run bash "$SCRIPTS/whoami.sh" /tmp/shared-proj codex
  [[ "$output" =~ "not_joined=true" ]]

  AGMSG_CLIENT_ID=client-b run bash "$SCRIPTS/whoami.sh" /tmp/shared-proj codex
  [[ "$output" =~ "agent=bob" ]]
}

# --- rename-team.sh ---

@test "rename-team: renames the team dir and updates config.json name" {
  bash "$SCRIPTS/join.sh" oldteam alice claude-code /tmp/proj
  run bash "$SCRIPTS/rename-team.sh" oldteam newteam
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Renamed team oldteam → newteam" ]]
  [ ! -d "$TEST_SKILL_DIR/teams/oldteam" ]
  [ -f "$TEST_SKILL_DIR/teams/newteam/config.json" ]
  run sqlite3 :memory: "SELECT json_extract(readfile('$TEST_SKILL_DIR/teams/newteam/config.json'), '\$.name');"
  [ "$output" = "newteam" ]
}

@test "rename-team: preserves agents in the team" {
  bash "$SCRIPTS/join.sh" oldteam alice claude-code /tmp/proj-a
  bash "$SCRIPTS/join.sh" oldteam bob   codex       /tmp/proj-b
  bash "$SCRIPTS/rename-team.sh" oldteam newteam
  run bash "$SCRIPTS/team.sh" newteam
  [ "$status" -eq 0 ]
  [[ "$output" =~ "alice" ]]
  [[ "$output" =~ "bob" ]]
  [[ "$output" =~ "2 member" ]]
}

@test "rename-team: migrates messages to the new team name" {
  bash "$SCRIPTS/join.sh" oldteam alice claude-code /tmp/proj-a
  bash "$SCRIPTS/join.sh" oldteam bob   claude-code /tmp/proj-b
  bash "$SCRIPTS/send.sh" oldteam alice bob "hello"
  bash "$SCRIPTS/rename-team.sh" oldteam newteam
  run bash "$SCRIPTS/inbox.sh" newteam bob
  [ "$status" -eq 0 ]
  [[ "$output" =~ "hello" ]]
}

@test "rename-team: fails when old team is missing" {
  run bash "$SCRIPTS/rename-team.sh" nope newname
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Team not found: nope" ]]
}

@test "rename-team: fails when new team already exists" {
  bash "$SCRIPTS/join.sh" team-a alice claude-code /tmp/proj-a
  bash "$SCRIPTS/join.sh" team-b bob   claude-code /tmp/proj-b
  run bash "$SCRIPTS/rename-team.sh" team-a team-b
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Team already exists: team-b" ]]
}

@test "rename-team: fails when old and new are identical" {
  bash "$SCRIPTS/join.sh" sameteam alice claude-code /tmp/proj
  run bash "$SCRIPTS/rename-team.sh" sameteam sameteam
  [ "$status" -ne 0 ]
  [[ "$output" =~ "same" ]]
}

@test "join: rejects unknown agent type" {
  run bash "$SCRIPTS/join.sh" myteam alice claude /tmp/proj
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Unknown agent type" ]]
}

@test "join: accepts claude-code" {
  run bash "$SCRIPTS/join.sh" myteam alice claude-code /tmp/proj
  [ "$status" -eq 0 ]
}

@test "join: accepts codex" {
  run bash "$SCRIPTS/join.sh" myteam alice codex /tmp/proj
  [ "$status" -eq 0 ]
}

@test "join: accepts gemini" {
  run bash "$SCRIPTS/join.sh" myteam alice gemini /tmp/proj
  [ "$status" -eq 0 ]
}

@test "join: accepts antigravity" {
  run bash "$SCRIPTS/join.sh" myteam alice antigravity /tmp/proj
  [ "$status" -eq 0 ]
}
