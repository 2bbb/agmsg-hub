#!/usr/bin/env bash
set -euo pipefail

# Usage: history.sh <team> [agent_id] [limit]
# Shows message history. If agent_id given, shows only that agent's messages.

TEAM="${1:?Usage: history.sh <team> [agent_id] [limit]}"
AGENT="${2:-}"
LIMIT="${3:-20}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"
source "$SCRIPT_DIR/lib/client.sh"
CLIENT_ID="$(agmsg_client_id)"

if agmsg_using_remote_storage; then
  source "$SCRIPT_DIR/lib/remote-client.sh"
  RESULT="$(agmsg_remote_history_rows "$TEAM" "$AGENT" "$LIMIT")"

  if [ -z "$RESULT" ]; then
    echo "No message history."
    exit 0
  fi

  while IFS=$'\t' read -r from to body ts status; do
    echo "  $status [$ts] $from → $to: $body"
  done <<< "$RESULT"
  exit 0
fi

DB="$(agmsg_db_path)"

if [ ! -f "$DB" ]; then
  echo "No messages (DB not initialized)"
  exit 0
fi

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
"

if [ -n "$AGENT" ]; then
  WHERE="WHERE m.team='$TEAM' AND (m.from_agent='$AGENT' OR m.to_agent='$AGENT')"
else
  WHERE="WHERE m.team='$TEAM'"
fi

# Escape newlines/tabs in body, use unit separator between fields
RESULT=$(sqlite3 "$DB" "
  SELECT m.from_agent || char(31) || m.to_agent || char(31) || replace(replace(m.body, char(10), '\n'), char(9), '\t') || char(31) || m.created_at || char(31) || CASE WHEN mr.message_id IS NULL THEN '●' ELSE '○' END
  FROM messages m
  LEFT JOIN message_reads mr
    ON mr.message_id = m.id
   AND mr.client_id = '$(printf '%s' "$CLIENT_ID" | sed "s/'/''/g")'
  $WHERE ORDER BY m.created_at DESC LIMIT $LIMIT;
")

if [ -z "$RESULT" ]; then
  echo "No message history."
  exit 0
fi

# Reverse order (oldest first) and display
REVERSED=$(echo "$RESULT" | tail -r 2>/dev/null || echo "$RESULT" | tac 2>/dev/null || echo "$RESULT" | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}')
while IFS=$'\x1f' read -r from to body ts status; do
  echo "  $status [$ts] $from → $to: $body"
done <<< "$REVERSED"
