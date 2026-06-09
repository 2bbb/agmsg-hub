#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
  export TEST_PROJECT="$(mktemp -d)"
  mkdir -p "$TEST_SKILL_DIR/agents"
  cp "$BATS_TEST_DIRNAME/../skills/agmsg/SKILL.md" "$TEST_SKILL_DIR/SKILL.md"
  cp "$BATS_TEST_DIRNAME/../openai.yaml" "$TEST_SKILL_DIR/agents/openai.yaml"
}

teardown() {
  teardown_test_env
  rm -rf "$TEST_PROJECT"
}

@test "doctor reports healthy shell install" {
  run bash "$SCRIPTS/doctor.sh" shell "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "doctor: ok" ]]
}

@test "doctor fails when required script is missing" {
  rm "$SCRIPTS/send.sh"
  run bash "$SCRIPTS/doctor.sh" shell "$TEST_PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "send.sh missing" ]]
}

@test "doctor rejects unknown agent type" {
  run bash "$SCRIPTS/doctor.sh" unknown "$TEST_PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "unknown agent type" ]]
}

@test "doctor codex accepts writable_roots parent directory" {
  local cfg="$TEST_PROJECT/codex-config.toml"
  cat > "$cfg" <<EOF
[sandbox_workspace_write]
writable_roots = ["$TEST_SKILL_DIR"]
EOF

  run env AGMSG_CODEX_CONFIG="$cfg" bash "$SCRIPTS/doctor.sh" codex "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Codex writable_roots covers db directory" ]]
  [[ "$output" =~ "Codex writable_roots covers teams directory" ]]
}

@test "doctor codex fails when writable_roots do not cover skill data" {
  local cfg="$TEST_PROJECT/codex-config.toml"
  cat > "$cfg" <<EOF
[sandbox_workspace_write]
writable_roots = ["$TEST_PROJECT"]
EOF

  run env AGMSG_CODEX_CONFIG="$cfg" bash "$SCRIPTS/doctor.sh" codex "$TEST_PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "does not cover db directory" ]]
  [[ "$output" =~ "AGMSG-DIRECTIVE" ]]
}

@test "doctor porcelain emits stable check, fix, and summary records" {
  local cfg="$TEST_PROJECT/codex-config.toml"
  cat > "$cfg" <<EOF
[sandbox_workspace_write]
writable_roots = ["$TEST_PROJECT"]
EOF

  run env AGMSG_CODEX_CONFIG="$cfg" bash "$SCRIPTS/doctor.sh" --porcelain codex "$TEST_PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" =~ $'check\tcodex.writable_root.db\tfail\t' ]]
  [[ "$output" =~ $'fix\tcodex.writable_root.db\tadd_codex_writable_root\t' ]]
  [[ "$output" =~ $'summary\tfail\t' ]]
}

@test "doctor apply-fixes adds missing Codex writable_roots" {
  local cfg="$TEST_PROJECT/codex-config.toml"
  cat > "$cfg" <<EOF
[projects."/tmp"]
trust_level = "trusted"
EOF

  run env AGMSG_CODEX_CONFIG="$cfg" bash "$SCRIPTS/doctor.sh" --apply-fixes codex "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  grep -q "$TEST_SKILL_DIR/db" "$cfg"
  grep -q "$TEST_SKILL_DIR/teams" "$cfg"
}

@test "doctor apply-fixes creates missing Codex config" {
  local cfg="$TEST_PROJECT/missing/config.toml"

  run env AGMSG_CODEX_CONFIG="$cfg" bash "$SCRIPTS/doctor.sh" --apply-fixes --porcelain codex "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$cfg" ]
  grep -q "$TEST_SKILL_DIR/db" "$cfg"
  grep -q "$TEST_SKILL_DIR/teams" "$cfg"
  [[ "$output" =~ $'summary\tok\t0\t' ]]
}

@test "doctor codex reports invalid hooks JSON" {
  local cfg="$TEST_PROJECT/codex-config.toml"
  cat > "$cfg" <<EOF
[sandbox_workspace_write]
writable_roots = ["$TEST_SKILL_DIR"]
EOF
  mkdir -p "$TEST_PROJECT/.codex"
  echo '{' > "$TEST_PROJECT/.codex/hooks.json"

  run env AGMSG_CODEX_CONFIG="$cfg" bash "$SCRIPTS/doctor.sh" codex "$TEST_PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Codex hooks file JSON invalid" ]]
}
