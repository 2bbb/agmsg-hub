#!/usr/bin/env bash
set -euo pipefail

# Usage: send.sh <team> <from> <to> <message>

TEAM="${1:?Usage: send.sh <team> <from> <to> <message>}"
FROM="${2:?Missing from agent}"
TO="${3:?Missing to agent}"
BODY="${4:?Missing message body}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"

if agmsg_using_remote_storage; then
  source "$SCRIPT_DIR/lib/remote-client.sh"
  agmsg_remote_send_message "$TEAM" "$FROM" "$TO" "$BODY"
  echo "Sent to $TO in team $TEAM"
  exit 0
fi

DB="$(agmsg_db_path)"

if [ ! -f "$DB" ]; then
  bash "$SCRIPT_DIR/init-db.sh"
fi

sqlite3 "$DB" "INSERT INTO messages (team, from_agent, to_agent, body) VALUES ('$TEAM', '$FROM', '$TO', '$(echo "$BODY" | sed "s/'/''/g")');"

echo "Sent to $TO in team $TEAM"
