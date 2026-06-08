#!/usr/bin/env bash
set -euo pipefail

# Usage: inbox.sh <team> <agent_id> [--quiet] [--wait seconds] [--poll seconds]
# Shows unread messages and marks them as read.
# --quiet: only output if there are unread messages (for hooks)
# --wait: poll until messages arrive or the timeout elapses
# --poll: polling interval while waiting, seconds

TEAM="${1:?Usage: inbox.sh <team> <agent_id> [--quiet] [--wait seconds] [--poll seconds]}"
AGENT="${2:?Missing agent_id}"
shift 2

QUIET=false
WAIT_SECONDS=0
POLL_SECONDS=2

while [ $# -gt 0 ]; do
  case "$1" in
    --quiet)
      QUIET=true
      shift
      ;;
    --wait)
      WAIT_SECONDS="${2:?Usage: inbox.sh <team> <agent_id> [--quiet] [--wait seconds] [--poll seconds]}"
      shift 2
      ;;
    --poll)
      POLL_SECONDS="${2:?Usage: inbox.sh <team> <agent_id> [--quiet] [--wait seconds] [--poll seconds]}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

case "$WAIT_SECONDS" in
  ''|*[!0-9]*)
    echo "--wait must be a non-negative integer" >&2
    exit 1
    ;;
esac
case "$POLL_SECONDS" in
  ''|*[!0-9]*)
    echo "--poll must be a positive integer" >&2
    exit 1
    ;;
esac
if [ "$POLL_SECONDS" -lt 1 ]; then
  echo "--poll must be a positive integer" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"

REMOTE=false
if agmsg_using_remote_storage; then
  REMOTE=true
  source "$SCRIPT_DIR/lib/remote-client.sh"
else
  DB="$(agmsg_db_path)"
fi

fetch_unread() {
  if [ "$REMOTE" = true ]; then
    agmsg_remote_unread_rows "$TEAM" "$AGENT" 100
    return
  fi

  if [ ! -f "$DB" ]; then
    return 0
  fi

  sqlite3 -separator $'\t' "$DB" "
    SELECT
      id,
      from_agent,
      replace(replace(body, char(10), '\n'), char(9), '\t'),
      created_at
    FROM messages
    WHERE team='$TEAM' AND to_agent='$AGENT' AND read_at IS NULL
    ORDER BY created_at ASC, id ASC;
  "
}

mark_read() {
  if [ $# -eq 0 ]; then
    return 0
  fi

  if [ "$REMOTE" = true ]; then
    agmsg_remote_mark_read "$TEAM" "$AGENT" "$@" 2>/dev/null || true
    return
  fi

  if [ ! -f "$DB" ]; then
    return 0
  fi

  local ids_csv="" id
  for id in "$@"; do
    case "$id" in
      ''|*[!0-9]*) continue ;;
    esac
    if [ -n "$ids_csv" ]; then
      ids_csv="$ids_csv,$id"
    else
      ids_csv="$id"
    fi
  done
  if [ -z "$ids_csv" ]; then
    return 0
  fi

  sqlite3 "$DB" "UPDATE messages SET read_at=strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE team='$TEAM' AND to_agent='$AGENT' AND read_at IS NULL AND id IN ($ids_csv);" 2>/dev/null || true
}

display_and_mark() {
  local unread="$1"
  local count
  count=$(echo "$unread" | wc -l | tr -d ' ')
  echo "$count new message(s):"
  echo ""
  local ids=()
  local id from body ts
  while IFS=$'\t' read -r id from body ts; do
    ids+=("$id")
    echo "  [$ts] $from: $body"
  done <<< "$unread"
  echo ""
  mark_read "${ids[@]}"
}

DEADLINE=$(( $(date +%s) + WAIT_SECONDS ))
ANNOUNCED=false

while true; do
  UNREAD="$(fetch_unread)"
  if [ -n "$UNREAD" ]; then
    display_and_mark "$UNREAD"
    exit 0
  fi

  NOW="$(date +%s)"
  if [ "$WAIT_SECONDS" -eq 0 ] || [ "$NOW" -ge "$DEADLINE" ]; then
    break
  fi

  if [ "$QUIET" = false ] && [ "$ANNOUNCED" = false ]; then
    echo "Waiting up to ${WAIT_SECONDS}s for new messages..."
    ANNOUNCED=true
  fi
  sleep "$POLL_SECONDS"
done

if [ "$QUIET" = true ]; then
  exit 0
fi

if [ "$REMOTE" = false ] && [ ! -f "$DB" ] && [ "$WAIT_SECONDS" -eq 0 ]; then
  echo "No messages (DB not initialized)"
elif [ "$WAIT_SECONDS" -gt 0 ]; then
  echo "No new messages after ${WAIT_SECONDS}s."
else
  echo "No new messages."
fi
