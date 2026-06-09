#!/usr/bin/env bash
set -euo pipefail

# Diagnose common agmsg install/runtime problems without mutating state.
# Usage: doctor.sh [--porcelain] [--apply-fixes] [agent_type] [project_path]

PORCELAIN=false
APPLY_FIXES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --porcelain)
      PORCELAIN=true
      shift
      ;;
    --apply-fixes)
      APPLY_FIXES=true
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: doctor.sh [--porcelain] [--apply-fixes] [agent_type] [project_path]

agent_type: claude-code, codex, gemini, antigravity, copilot, shell

--apply-fixes applies safe, explicit repairs. Current scope:
  - add missing Codex writable_roots entries

--porcelain emits stable tab-separated records:
  check<TAB><id><TAB><ok|warn|fail><TAB><message>
  fix<TAB><id><TAB><action><TAB><path><TAB><config>
  summary<TAB><ok|fail><TAB><failures><TAB><warnings>
EOF
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

AGENT_TYPE="${1:-codex}"
PROJECT_PATH="${2:-$(pwd)}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CODEX_CONFIG="${AGMSG_CODEX_CONFIG:-$HOME/.codex/config.toml}"

source "$SCRIPT_DIR/lib/codex-config.sh"
source "$SCRIPT_DIR/lib/storage.sh"

failures=0
warnings=0

ok() {
  local id="$1"
  local message="$2"
  if [ "$PORCELAIN" = true ]; then
    printf 'check\t%s\tok\t%s\n' "$id" "$message"
  else
    printf 'ok: %s\n' "$message"
  fi
}

warn() {
  local id="$1"
  local message="$2"
  warnings=$((warnings + 1))
  if [ "$PORCELAIN" = true ]; then
    printf 'check\t%s\twarn\t%s\n' "$id" "$message"
  else
    printf 'warn: %s\n' "$message"
  fi
}

fail() {
  local id="$1"
  local message="$2"
  failures=$((failures + 1))
  if [ "$PORCELAIN" = true ]; then
    printf 'check\t%s\tfail\t%s\n' "$id" "$message"
  else
    printf 'fail: %s\n' "$message"
  fi
}

fix_add_codex_writable_root() {
  local id="$1"
  local path="$2"
  if [ "$PORCELAIN" = true ]; then
    printf 'fix\t%s\tadd_codex_writable_root\t%s\t%s\n' "$id" "$path" "$CODEX_CONFIG"
  else
    printf 'AGMSG-DIRECTIVE: add "%s" to [sandbox_workspace_write].writable_roots in %s if this Codex session is sandboxed.\n' "$path" "$CODEX_CONFIG"
  fi
}

apply_codex_writable_root() {
  local path="$1"
  agmsg_codex_add_writable_root "$CODEX_CONFIG" "$path"
}

check_file() {
  local path="$1"
  local label="$2"
  local id="$3"
  if [ -f "$path" ]; then
    ok "$id" "$label exists"
  else
    fail "$id" "$label missing: $path"
  fi
}

check_executable() {
  local path="$1"
  local label="$2"
  local id="$3"
  if [ -x "$path" ]; then
    ok "$id" "$label executable"
  elif [ -f "$path" ]; then
    fail "$id" "$label exists but is not executable: $path"
  else
    fail "$id" "$label missing: $path"
  fi
}

check_writable_dir() {
  local path="$1"
  local label="$2"
  local id="$3"
  if [ ! -d "$path" ]; then
    fail "$id" "$label missing: $path"
  elif [ -w "$path" ]; then
    ok "$id" "$label writable"
  else
    fail "$id" "$label is not writable: $path"
  fi
}

check_command() {
  local cmd="$1"
  local label="$2"
  local id="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$id" "$label available"
  else
    fail "$id" "$label missing: $cmd"
  fi
}

check_codex_writable_root() {
  local path="$1"
  local label="$2"
  local id="$3"

  if [ ! -f "$CODEX_CONFIG" ]; then
    if [ "$APPLY_FIXES" = true ]; then
      if apply_codex_writable_root "$path"; then
        ok "$id" "Codex writable_roots updated for $label"
        return
      fi
      fail "$id" "Codex writable_roots repair failed for $label: $path"
      return
    fi
    warn "codex.config" "Codex config not found; Local mode may still work, but sandbox writable_roots cannot be checked"
    return
  fi

  if agmsg_codex_config_covers_path "$CODEX_CONFIG" "$path"; then
    ok "$id" "Codex writable_roots covers $label"
    return
  fi

  if [ "$APPLY_FIXES" = true ]; then
    if apply_codex_writable_root "$path"; then
      ok "$id" "Codex writable_roots updated for $label"
      return
    fi
    fail "$id" "Codex writable_roots repair failed for $label: $path"
    return
  fi

  fail "$id" "Codex writable_roots does not cover $label: $path"
  fix_add_codex_writable_root "$id" "$path"
}

check_json_file() {
  local path="$1"
  local label="$2"
  local id="$3"
  if [ ! -f "$path" ]; then
    return
  fi
  if sqlite3 :memory: "SELECT json_valid(readfile('$(printf '%s' "$path" | sed "s/'/''/g")'));" 2>/dev/null | grep -q '^1$'; then
    ok "$id" "$label JSON valid"
  else
    fail "$id" "$label JSON invalid: $path"
  fi
}

case "$AGENT_TYPE" in
  claude-code|codex|gemini|antigravity|copilot|shell) ;;
  *)
    fail "agent_type" "unknown agent type: $AGENT_TYPE"
    ;;
esac

if [ "$PORCELAIN" = false ]; then
  printf 'agmsg doctor\n'
  printf 'skill_dir: %s\n' "$SKILL_DIR"
  printf 'project: %s\n' "$PROJECT_PATH"
  printf 'agent_type: %s\n' "$AGENT_TYPE"
  if [ "$AGENT_TYPE" = "codex" ]; then
    printf 'codex_config: %s\n' "$CODEX_CONFIG"
  fi
  printf '\n'
fi

check_file "$SKILL_DIR/SKILL.md" "SKILL.md" "skill.skill_md"
if [ -f "$SKILL_DIR/agents/openai.yaml" ] || [ -f "$SKILL_DIR/openai.yaml" ]; then
  ok "skill.openai_yaml" "Codex metadata exists"
else
  fail "skill.openai_yaml" "Codex metadata missing: $SKILL_DIR/agents/openai.yaml or $SKILL_DIR/openai.yaml"
fi
check_executable "$SCRIPT_DIR/whoami.sh" "whoami.sh" "script.whoami"
check_executable "$SCRIPT_DIR/join.sh" "join.sh" "script.join"
check_executable "$SCRIPT_DIR/inbox.sh" "inbox.sh" "script.inbox"
check_executable "$SCRIPT_DIR/send.sh" "send.sh" "script.send"
check_executable "$SCRIPT_DIR/delivery.sh" "delivery.sh" "script.delivery"
check_executable "$SCRIPT_DIR/server.sh" "server.sh" "script.server"
check_executable "$SCRIPT_DIR/remote.sh" "remote.sh" "script.remote"
check_executable "$SCRIPT_DIR/role-instructions.sh" "role-instructions.sh" "script.role_instructions"
check_command sqlite3 sqlite3 "dependency.sqlite3"
check_writable_dir "$SKILL_DIR/db" "db directory" "storage.db_dir"
check_writable_dir "$SKILL_DIR/teams" "teams directory" "storage.teams_dir"

if [ "$AGENT_TYPE" = "codex" ]; then
  check_codex_writable_root "$SKILL_DIR/db" "db directory" "codex.writable_root.db"
  check_codex_writable_root "$SKILL_DIR/teams" "teams directory" "codex.writable_root.teams"

  hooks_file="$PROJECT_PATH/.codex/hooks.json"
  check_json_file "$hooks_file" "Codex hooks file" "codex.hooks_json"

  mode_output="$("$SCRIPT_DIR/delivery.sh" status codex "$PROJECT_PATH" 2>/dev/null || true)"
  case "$mode_output" in
    *"mode: monitor"*|*"mode: both"*)
      fail "codex.delivery_mode" "Codex does not support monitor delivery; run: delivery.sh set turn codex \"$PROJECT_PATH\""
      ;;
    *"mode: turn"*|*"mode: off"*)
      ok "codex.delivery_mode" "Codex delivery mode supported"
      ;;
    *)
      warn "codex.delivery_mode" "Codex delivery mode could not be derived"
      ;;
  esac
fi

if agmsg_using_remote_storage; then
  check_command curl curl "dependency.curl"
  check_command node node "dependency.node"
  source "$SCRIPT_DIR/lib/remote-client.sh"
  if agmsg_remote_health >/dev/null 2>&1; then
    ok "remote.health" "remote storage server is reachable"
  else
    fail "remote.health" "remote storage is active but the server is unreachable"
  fi
elif [ -n "$(agmsg_remote_url)" ]; then
  check_command curl curl "dependency.curl"
  warn "remote.storage" "remote server is configured but storage.active is not remote"
else
  if [ "$AGENT_TYPE" = "codex" ]; then
    warn "remote.storage" "remote storage is not configured; Codex Cloud mode cannot use local agmsg storage yet"
  else
    warn "remote.storage" "remote storage is not configured"
  fi
fi

if [ "$PORCELAIN" = false ]; then
  printf '\n'
fi
if [ "$failures" -gt 0 ]; then
  if [ "$PORCELAIN" = true ]; then
    printf 'summary\tfail\t%d\t%d\n' "$failures" "$warnings"
  else
    printf 'doctor: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
  fi
  exit 1
fi

if [ "$PORCELAIN" = true ]; then
  printf 'summary\tok\t0\t%d\n' "$warnings"
else
  printf 'doctor: ok (%d warning(s))\n' "$warnings"
fi
