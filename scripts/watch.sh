#!/usr/bin/env bash
set -u

# Stream new agmsg messages for the current session as they arrive.
#
# Intended to be launched by Claude Code's Monitor tool from the SessionStart
# hook (`session-start.sh`), but also works standalone as `tail -f` for
# inbox: any agent runtime that can read stdout can consume it.
#
# Usage: watch.sh <session_id> <project_path> <agent_type> [active_name]
#
# Behavior:
#   - Resolves (team, agent) pairs for (project_path, agent_type) via
#     identities.sh or the remote identity API. By default, subscribes to
#     unread messages addressed to any of those pairs for this client.
#   - When [active_name] is given, narrows the subscription to only pairs
#     whose agent name matches — useful for `actas` exclusive role mode.
#   - Uses per-client read receipts. Starting or restarting the watcher does
#     not skip unread backlog for this client.
#   - Polls the SQLite DB at AGMSG_WATCH_INTERVAL seconds (default 5, also
#     overridable via the delivery.monitor.poll_interval config key).
#   - Emits one line per new message:
#         <ts> | <team> | <from> → <to> | <body>
#     Newlines in body are escaped to literal "\n" so each message stays a
#     single line — easier for Monitor to deliver as one event.
#   - Writes a pidfile at ~/.agents/agmsg/run/watch.<session_id>.pid and
#     removes it on EXIT / SIGTERM / SIGINT.

SESSION_ID="${1:?Usage: watch.sh <session_id> <project_path> <agent_type> [active_name]}"
PROJECT_PATH="${2:?Missing project_path}"
AGENT_TYPE="${3:?Missing agent_type}"
ACTIVE_NAME="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"
source "$SCRIPT_DIR/lib/client.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/actas-lock.sh"
CLIENT_ID="$(agmsg_client_id)"
REMOTE=false
if agmsg_using_remote_storage; then
  REMOTE=true
  source "$SCRIPT_DIR/lib/remote-client.sh"
else
  DB="$(agmsg_db_path)"
fi
RUN_DIR="$(agmsg_run_dir)"
PIDFILE="$RUN_DIR/watch.$SESSION_ID.pid"

# Resolve poll interval. Env var wins over config, default 5s.
INTERVAL="${AGMSG_WATCH_INTERVAL:-}"
if [ -z "$INTERVAL" ]; then
  INTERVAL="$("$SCRIPT_DIR/config.sh" get delivery.monitor.poll_interval 5 2>/dev/null || echo 5)"
fi
case "$INTERVAL" in ''|*[!0-9]*) INTERVAL=5 ;; esac

mkdir -p "$RUN_DIR" 2>/dev/null || true

# Sequential re-invocation of Monitor for this same session_id leaves the
# previous watch.sh running but loses track of it (pidfile gets clobbered).
# Stop the prior holder before claiming the slot. ps args check defends
# against pid recycling — only touch processes whose cmdline still matches
# our watch.sh. See #66.
if [ -f "$PIDFILE" ]; then
  prev_pid=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$prev_pid" ] && [ "$prev_pid" != "$$" ] && kill -0 "$prev_pid" 2>/dev/null; then
    prev_cmd=$(ps -o args= -p "$prev_pid" 2>/dev/null || true)
    case "$prev_cmd" in
      *"$SKILL_DIR/scripts/watch.sh"*) kill "$prev_pid" 2>/dev/null || true ;;
    esac
  fi
fi

echo $$ > "$PIDFILE"
# EXIT only removes the pidfile if it still records our pid. A successor
# watcher (Monitor re-invoked for the same session_id) overwrites $PIDFILE
# with its own pid before killing us; without this guard our EXIT trap
# would erase the successor's record. See #66.
trap '[ "$(cat "$PIDFILE" 2>/dev/null)" = "$$" ] && rm -f "$PIDFILE"' EXIT
trap 'exit 0' INT TERM HUP

# Resolve subscription set.
if [ "$REMOTE" = true ]; then
  PAIRS="$(agmsg_remote_identity_pairs "$PROJECT_PATH" "$AGENT_TYPE")"
else
  PAIRS="$("$SCRIPT_DIR/identities.sh" "$PROJECT_PATH" "$AGENT_TYPE")"
fi
if [ -n "$ACTIVE_NAME" ]; then
  PAIRS=$(printf '%s\n' "$PAIRS" | awk -v n="$ACTIVE_NAME" -F'\t' 'NF >= 2 && $2 == n')
fi

# Honor actas exclusivity locks. A (team, agent) pair currently owned by
# another live session is removed from this watcher's subscription so
# messages addressed to that role only reach the owning session. Pairs we
# own (or that are free) stay in. See #62.
#
# When ACTIVE_NAME is set (the watcher was launched by an `actas` flow),
# we also CLAIM the lock for each surviving pair. Implicit claim here makes
# the exclusivity take effect machine-wide on the next peer watcher cycle,
# without needing the skill cmd templates to call a separate helper. If a
# claim fails because another live session beat us to it, exit with an
# error — the user's host agent surfaces stderr and the original (broad)
# watcher was already stopped by the actas flow, so this state is recoverable
# by `drop` on the other session.
if [ -n "$PAIRS" ]; then
  filtered=""
  skipped=""
  held=""
  while IFS=$'\t' read -r _team _agent; do
    [ -z "$_team" ] && continue
    state=$(actas_lock_state "$_team" "$_agent" "$SESSION_ID")
    case "$state" in
      other:*)
        # If the caller is asking specifically for this name (actas flow),
        # treat the conflict as a hard failure. Otherwise (broad subscribe)
        # silently skip — peer owns the role, we don't need it.
        if [ -n "$ACTIVE_NAME" ]; then
          held="${held:+$held }${_team}/${_agent}(${state#other:})"
        else
          skipped="${skipped:+$skipped }${_team}/${_agent}(${state#other:})"
        fi
        continue
        ;;
    esac
    if [ -n "$ACTIVE_NAME" ]; then
      # Implicit claim — `actas` was the invoking flow. Covers the race
      # where state-check said free but a peer claimed it between then and
      # now.
      result=$(actas_lock_claim "$_team" "$_agent" "$SESSION_ID" 2>/dev/null || true)
      case "$result" in
        held:*)
          held="${held:+$held }${_team}/${_agent}(${result#held:})"
          continue
          ;;
      esac
    fi
    filtered="${filtered:+$filtered$'\n'}${_team}"$'\t'"${_agent}"
  done <<< "$PAIRS"
  PAIRS="$filtered"
  if [ -n "$skipped" ]; then
    echo "agmsg watch: skipping pairs held by other sessions: $skipped" >&2
  fi
  if [ -n "$held" ]; then
    echo "agmsg watch: cannot claim (held by other sessions): $held" >&2
    echo "agmsg watch: run \`/agmsg drop <name>\` in the owning session, then retry." >&2
    exit 1
  fi
fi

if [ -z "$PAIRS" ]; then
  if [ -n "$ACTIVE_NAME" ]; then
    echo "agmsg watch: no registration for agent '$ACTIVE_NAME' in $PROJECT_PATH ($AGENT_TYPE); nothing to do"
  else
    echo "agmsg watch: no available identities (all held by other sessions, or none joined); nothing to do"
  fi
  exit 0
fi

sql_escape() { printf '%s' "$1" | sed "s/'/''/g"; }

ensure_read_receipts_table() {
  [ "$REMOTE" = false ] || return 0
  [ -f "$DB" ] || return 0
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
  " 2>/dev/null || true
}

fetch_pair_unread() {
  local team="$1" agent="$2"
  if [ "$REMOTE" = true ]; then
    agmsg_remote_unread_rows "$team" "$agent" 100
    return
  fi

  [ -f "$DB" ] || return 0
  ensure_read_receipts_table
  local t_esc a_esc c_esc
  t_esc="$(sql_escape "$team")"
  a_esc="$(sql_escape "$agent")"
  c_esc="$(sql_escape "$CLIENT_ID")"
  sqlite3 -separator $'\t' "$DB" "
    SELECT
      m.id,
      m.from_agent,
      replace(replace(m.body, char(13), ''), char(10), '\\n'),
      m.created_at
    FROM messages m
    LEFT JOIN message_reads mr
      ON mr.message_id = m.id
     AND mr.client_id = '$c_esc'
    WHERE m.team = '$t_esc'
      AND m.to_agent = '$a_esc'
      AND mr.message_id IS NULL
    ORDER BY m.id ASC
    LIMIT 100;
  " 2>/dev/null || true
}

mark_pair_read() {
  local team="$1" agent="$2"
  shift 2
  [ "$#" -gt 0 ] || return 0

  if [ "$REMOTE" = true ]; then
    agmsg_remote_mark_read "$team" "$agent" "$@" >/dev/null 2>&1 || true
    return
  fi

  [ -f "$DB" ] || return 0
  ensure_read_receipts_table
  local ids_csv="" id t_esc a_esc c_esc
  for id in "$@"; do
    case "$id" in
      ''|*[!0-9]*) continue ;;
    esac
    ids_csv="${ids_csv:+$ids_csv,}$id"
  done
  [ -n "$ids_csv" ] || return 0
  t_esc="$(sql_escape "$team")"
  a_esc="$(sql_escape "$agent")"
  c_esc="$(sql_escape "$CLIENT_ID")"
  sqlite3 "$DB" "
    INSERT OR IGNORE INTO message_reads (message_id, team, agent, client_id)
    SELECT id, team, to_agent, '$c_esc'
    FROM messages
    WHERE team='$t_esc' AND to_agent='$a_esc' AND id IN ($ids_csv);
    UPDATE messages
    SET read_at=COALESCE(read_at, strftime('%Y-%m-%dT%H:%M:%SZ','now'))
    WHERE team='$t_esc' AND to_agent='$a_esc' AND id IN ($ids_csv);
  " >/dev/null 2>&1 || true
}

while true; do
  while IFS=$'\t' read -r team agent; do
    [ -z "$team" ] && continue
    ROWS="$(fetch_pair_unread "$team" "$agent")"
    if [ -n "$ROWS" ]; then
      ids=()
      while IFS=$'\t' read -r id from body ts; do
        [ -z "$id" ] && continue
        ids+=("$id")
        printf '%s | %s | %s → %s | %s\n' "$ts" "$team" "$from" "$agent" "$body"
      done <<< "$ROWS"
      mark_pair_read "$team" "$agent" "${ids[@]}"
    fi
  done <<< "$PAIRS"

  # Run sleep in the background and `wait` for it so signal traps fire
  # immediately. Bash defers traps while a foreground builtin like `sleep`
  # is blocking, which would otherwise delay shutdown by up to $INTERVAL.
  sleep "$INTERVAL" &
  wait $! 2>/dev/null
done
