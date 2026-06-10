#!/usr/bin/env bash
set -euo pipefail

# Usage: send.sh <team> <from> <to> <message> [--project path]

TEAM="${1:?Usage: send.sh <team> <from> <to> <message>}"
FROM="${2:?Missing from agent}"
TO="${3:?Missing to agent}"
BODY="${4:?Missing message body}"
shift 4

PROJECT_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      PROJECT_PATH="${2:?Usage: send.sh <team> <from> <to> <message> [--project path]}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"
source "$SCRIPT_DIR/lib/client.sh"

sql_escape() { printf '%s' "$1" | sed "s/'/''/g"; }

if agmsg_using_remote_storage; then
  source "$SCRIPT_DIR/lib/remote-client.sh"
  agmsg_remote_send_message "$TEAM" "$FROM" "$TO" "$BODY" "$PROJECT_PATH"
  echo "Sent to $TO in team $TEAM"
  exit 0
fi

DB="$(agmsg_db_path)"

if [ ! -f "$DB" ]; then
  bash "$SCRIPT_DIR/init-db.sh"
fi

sqlite3 "$DB" "
  ALTER TABLE messages ADD COLUMN project_id TEXT;
" 2>/dev/null || true
sqlite3 "$DB" "
  ALTER TABLE messages ADD COLUMN project_key TEXT;
" 2>/dev/null || true
sqlite3 "$DB" "
  ALTER TABLE messages ADD COLUMN project_path TEXT;
" 2>/dev/null || true
sqlite3 "$DB" "
  ALTER TABLE messages ADD COLUMN from_client_id TEXT;
" 2>/dev/null || true
sqlite3 "$DB" "CREATE INDEX IF NOT EXISTS idx_messages_project ON messages(team, project_id, created_at DESC);" 2>/dev/null || true

PROJECT_KEY=""
PROJECT_ID=""
if [ -n "$PROJECT_PATH" ]; then
  PROJECT_KEY="$(agmsg_project_key "$PROJECT_PATH")"
  PROJECT_ID="$PROJECT_KEY"
fi

sqlite3 "$DB" "
  INSERT INTO messages (team, from_agent, to_agent, body, project_id, project_key, project_path, from_client_id)
  VALUES (
    '$(sql_escape "$TEAM")',
    '$(sql_escape "$FROM")',
    '$(sql_escape "$TO")',
    '$(sql_escape "$BODY")',
    NULLIF('$(sql_escape "$PROJECT_ID")', ''),
    NULLIF('$(sql_escape "$PROJECT_KEY")', ''),
    NULLIF('$(sql_escape "$PROJECT_PATH")', ''),
    '$(sql_escape "$(agmsg_client_id)")'
  );
"

echo "Sent to $TO in team $TEAM"
