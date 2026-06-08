#!/usr/bin/env bats

load test_helper

setup() {
  setup_test_env
  export TEST_PROJECT="$(mktemp -d)"
  source "$SCRIPTS/lib/codex-config.sh"
}

teardown() {
  teardown_test_env
  rm -rf "$TEST_PROJECT"
}

@test "codex config: parent writable_root covers child path" {
  local child="$TEST_SKILL_DIR/db"
  agmsg_path_covers "$TEST_SKILL_DIR" "$child"
}

@test "codex config: detects covered writable_root" {
  local cfg="$TEST_PROJECT/config.toml"
  cat > "$cfg" <<EOF
[sandbox_workspace_write]
writable_roots = ["$TEST_SKILL_DIR"]
EOF

  agmsg_codex_config_covers_path "$cfg" "$TEST_SKILL_DIR/db"
  agmsg_codex_config_covers_path "$cfg" "$TEST_SKILL_DIR/teams"
}

@test "codex config: creates missing config with writable_root" {
  local cfg="$TEST_PROJECT/missing/config.toml"

  agmsg_codex_add_writable_root "$cfg" "$TEST_SKILL_DIR/db"

  [ -f "$cfg" ]
  grep -q "$TEST_SKILL_DIR/db" "$cfg"
}

@test "codex config: backs up existing config once" {
  local cfg="$TEST_PROJECT/config.toml"
  cat > "$cfg" <<EOF
[projects."/tmp"]
trust_level = "trusted"
EOF

  AGMSG_CODEX_CONFIG_BACKED_UP=false
  agmsg_codex_add_writable_root "$cfg" "$TEST_SKILL_DIR/db"
  agmsg_codex_add_writable_root "$cfg" "$TEST_SKILL_DIR/teams"

  [ -f "$cfg.bak" ]
  grep -q 'trust_level = "trusted"' "$cfg.bak"
}

@test "codex config: appends to multiline writable_roots cleanly" {
  local cfg="$TEST_PROJECT/config.toml"
  cat > "$cfg" <<EOF
[sandbox_workspace_write]
writable_roots = [
  "$TEST_PROJECT"
]
EOF

  agmsg_codex_add_writable_root "$cfg" "$TEST_SKILL_DIR/db"

  grep -q '",*$' "$cfg"
  grep -q "$TEST_SKILL_DIR/db" "$cfg"
}
