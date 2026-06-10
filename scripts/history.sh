#!/usr/bin/env bash
set -euo pipefail

# Usage: history.sh <team> [agent_id] [limit] [--project path]
# Shows message history. If agent_id given, shows only that agent's messages.

if [ $# -lt 1 ]; then
  echo "Usage: history.sh <team> [agent_id] [limit] [--project path]" >&2
  exit 1
fi

TEAM="$1"
shift
AGENT=""
AGENT_SET=0
LIMIT="20"
LIMIT_SET=0
PROJECT_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      PROJECT_PATH="${2:?Usage: history.sh <team> [agent_id] [limit] [--project path]}"
      shift 2
      ;;
    *)
      if [ "$AGENT_SET" -eq 0 ]; then
        AGENT="$1"
        AGENT_SET=1
        shift
      elif [ "$LIMIT_SET" -eq 0 ]; then
        LIMIT="$1"
        LIMIT_SET=1
        shift
      else
        echo "Unknown option: $1" >&2
        exit 1
      fi
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"
source "$SCRIPT_DIR/lib/client.sh"
CLIENT_ID="$(agmsg_client_id)"
PROJECT_ID=""
if [ -n "$PROJECT_PATH" ]; then
  PROJECT_ID="$(agmsg_project_key "$PROJECT_PATH")"
fi

format_local_time() {
  local ts="$1"
  if date -d "$ts" "+%Y-%m-%d %H:%M:%S %Z" 2>/dev/null; then
    return
  fi

  local epoch
  if epoch="$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" "+%s" 2>/dev/null)"; then
    date -r "$epoch" "+%Y-%m-%d %H:%M:%S %Z" 2>/dev/null && return
  fi

  printf '%s\n' "$ts"
}

if agmsg_using_remote_storage; then
  source "$SCRIPT_DIR/lib/remote-client.sh"
  RESULT="$(agmsg_remote_history_rows "$TEAM" "$AGENT" "$LIMIT" "$PROJECT_PATH")"

  if [ -z "$RESULT" ]; then
    echo "No message history."
    exit 0
  fi

  while IFS=$'\t' read -r from to body ts status; do
    echo "  $status [$(format_local_time "$ts")] $from → $to: $body"
  done <<< "$RESULT"
  exit 0
fi

DB="$(agmsg_db_path)"

if [ ! -f "$DB" ]; then
  echo "No messages (DB not initialized)"
  exit 0
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
sqlite3 "$DB" "
  CREATE TABLE IF NOT EXISTS message_reads (
    message_id INTEGER NOT NULL,
    team TEXT NOT NULL,
    agent TEXT NOT NULL,
    client_id TEXT NOT NULL,
    read_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    PRIMARY KEY (message_id, client_id)
  );
  CREATE INDEX IF NOT EXISTS idx_message_reads_inbox
    ON message_reads(team, agent, client_id, message_id);
  CREATE INDEX IF NOT EXISTS idx_messages_project
    ON messages(team, project_id, created_at DESC);
"

if [ -n "$AGENT" ]; then
  WHERE="WHERE m.team='$TEAM' AND (m.from_agent='$AGENT' OR m.to_agent='$AGENT')"
else
  WHERE="WHERE m.team='$TEAM'"
fi
if [ -n "$PROJECT_ID" ]; then
  WHERE="$WHERE AND m.project_id='$(printf '%s' "$PROJECT_ID" | sed "s/'/''/g")'"
fi

# Escape newlines/tabs in body, use unit separator between fields
RESULT=$(sqlite3 "$DB" "
  SELECT m.from_agent || char(31) || m.to_agent || char(31) || replace(replace(m.body, char(10), '\n'), char(9), '\t') || char(31) || m.created_at || char(31) || CASE WHEN mr.message_id IS NULL THEN '●' ELSE '○' END
  FROM messages m
  LEFT JOIN message_reads mr
    ON mr.message_id = m.id
   AND mr.client_id = '$(printf '%s' "$CLIENT_ID" | sed "s/'/''/g")'
  $WHERE ORDER BY m.created_at DESC, m.id DESC LIMIT $LIMIT;
")

if [ -z "$RESULT" ]; then
  echo "No message history."
  exit 0
fi

while IFS=$'\x1f' read -r from to body ts status; do
  echo "  $status [$(format_local_time "$ts")] $from → $to: $body"
done <<< "$RESULT"
