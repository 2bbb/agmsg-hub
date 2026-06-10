#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
shift || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"

usage() {
  cat <<'EOF'
Usage:
  role-instructions.sh get <team> <agent>
  role-instructions.sh set <team> <agent> <text>
  role-instructions.sh set <team> <agent> --file <path>
EOF
}

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

local_config_path() {
  local team="$1"
  printf '%s/%s/config.json\n' "$(agmsg_teams_dir)" "$team"
}

read_body_arg() {
  if [ "${1:-}" = "--file" ]; then
    local path="${2:?Usage: role-instructions.sh set <team> <agent> --file <path>}"
    cat "$path"
    return
  fi
  printf '%s' "${1:-}"
}

local_get_instruction() {
  local team="$1"
  local agent="$2"
  local config
  config="$(local_config_path "$team")"
  if [ ! -f "$config" ]; then
    echo "Team not found: $team" >&2
    return 1
  fi

  sqlite3 :memory: "
    SELECT COALESCE(json_extract(value, '$.instruction'), '')
    FROM json_each(json_extract(readfile('$(sql_escape "$config")'), '$.agents'))
    WHERE key = '$(sql_escape "$agent")';
  "
}

local_set_instruction() {
  local team="$1"
  local agent="$2"
  local body="$3"
  local config body_file
  config="$(local_config_path "$team")"
  if [ ! -f "$config" ]; then
    echo "Team not found: $team" >&2
    return 1
  fi

  local exists
  exists="$(sqlite3 :memory: "
    SELECT EXISTS(
      SELECT 1
      FROM json_each(json_extract(readfile('$(sql_escape "$config")'), '$.agents'))
      WHERE key = '$(sql_escape "$agent")'
    );
  ")"
  if [ "$exists" != "1" ]; then
    echo "Agent not found in team $team: $agent" >&2
    return 1
  fi

  body_file="$(mktemp)"
  printf '%s' "$body" > "$body_file"
  sqlite3 :memory: "
    WITH
      input(json) AS (
        SELECT readfile('$(sql_escape "$config")')
      ),
      rebuilt_agents(json) AS (
        SELECT json_group_object(
          key,
          CASE
            WHEN key = '$(sql_escape "$agent")'
              THEN json_set(value, '$.instruction', CAST(readfile('$(sql_escape "$body_file")') AS TEXT))
            ELSE value
          END
        )
        FROM input, json_each(json_extract(input.json, '$.agents'))
      )
    SELECT json_set(input.json, '$.agents', json(rebuilt_agents.json))
    FROM input, rebuilt_agents;
  " > "$config.tmp"
  mv "$config.tmp" "$config"
  rm -f "$body_file"
  echo "Updated instruction for $agent in team $team"
}

if agmsg_using_remote_storage; then
  source "$SCRIPT_DIR/lib/remote-client.sh"
  case "$ACTION" in
    get)
      TEAM="${1:?Usage: role-instructions.sh get <team> <agent>}"
      AGENT="${2:?Missing agent}"
      agmsg_remote_role_instruction_get "$TEAM" "$AGENT"
      ;;
    set)
      TEAM="${1:?Usage: role-instructions.sh set <team> <agent> <text|--file path>}"
      AGENT="${2:?Missing agent}"
      shift 2
      BODY="$(read_body_arg "$@")"
      agmsg_remote_role_instruction_set "$TEAM" "$AGENT" "$BODY"
      echo "Updated instruction for $AGENT in team $TEAM"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
  exit 0
fi

case "$ACTION" in
  get)
    TEAM="${1:?Usage: role-instructions.sh get <team> <agent>}"
    AGENT="${2:?Missing agent}"
    local_get_instruction "$TEAM" "$AGENT"
    ;;
  set)
    TEAM="${1:?Usage: role-instructions.sh set <team> <agent> <text|--file path>}"
    AGENT="${2:?Missing agent}"
    shift 2
    BODY="$(read_body_arg "$@")"
    local_set_instruction "$TEAM" "$AGENT" "$BODY"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
