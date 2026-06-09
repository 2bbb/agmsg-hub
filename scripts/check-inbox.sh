#!/usr/bin/env bash
set -euo pipefail

# Check inbox across all teams with cooldown. Skips if last check was < 60 seconds ago.
# Usage: check-inbox.sh <type> <project_path>

TYPE="${1:?Usage: check-inbox.sh <type> <project_path>}"
PROJECT="${2:?Missing project_path}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"
source "$SCRIPT_DIR/lib/client.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/actas-lock.sh"

# Hook runtimes that pass JSON do so on stdin. Interactive invocations such as
# Gemini's PostToolUse command may inherit a terminal stdin instead; reading
# unconditionally there blocks waiting for input.
INPUT=""
if [ ! -t 0 ]; then
  INPUT=$(cat 2>/dev/null || true)
fi

# Prevent infinite loop: if stop hook is already active, exit silently
if echo "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' 2>/dev/null; then
  exit 0
fi

# Defer to the monitor watcher when one is alive for this session.
# Avoids double-delivery when delivery.mode = both. session_id is sent in
# the hook input JSON for Stop events.
SESSION_ID=$(printf '%s' "$INPUT" \
  | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  | head -1)
if [ -n "$SESSION_ID" ]; then
  PIDFILE="$(agmsg_run_dir)/watch.$SESSION_ID.pid"
  if [ -f "$PIDFILE" ]; then
    WATCH_PID=$(cat "$PIDFILE" 2>/dev/null || true)
    if [ -n "$WATCH_PID" ] && kill -0 "$WATCH_PID" 2>/dev/null; then
      exit 0
    fi
  fi
fi

if agmsg_using_remote_storage; then
  source "$SCRIPT_DIR/lib/remote-client.sh"
  PAIRS="$(agmsg_remote_identity_pairs "$PROJECT" "$TYPE")"
else
  PAIRS="$("$SCRIPT_DIR/identities.sh" "$PROJECT" "$TYPE")"
fi

if [ -z "$PAIRS" ]; then
  exit 0
fi

mkdir -p "$(agmsg_run_dir)"
OUTPUT=""
CHECKED=0
SKIPPED=0

# Prefer the new delivery.turn.check_interval; fall back to legacy
# hook.check_interval for users who haven't migrated.
INTERVAL=$("$SCRIPT_DIR/config.sh" get delivery.turn.check_interval "")
[ -z "$INTERVAL" ] && INTERVAL=$("$SCRIPT_DIR/config.sh" get hook.check_interval 60)
case "$INTERVAL" in ''|*[!0-9]*) INTERVAL=60 ;; esac

while IFS=$'\t' read -r team agent; do
  [ -n "$team" ] || continue
  [ -n "$agent" ] || continue

  # Honor actas exclusivity locks. If (team, AGENT) is currently held by
  # another live session, that session is the owner of that role's inbox —
  # don't deliver here. Mirrors the per-pair filtering watch.sh does for
  # CC sessions (#62), giving Stop-hook delivery (codex / claude-code
  # turn-mode) the same "respect peer locks" guarantee.
  #
  state=$(actas_lock_state "$team" "$agent" "${SESSION_ID:-}")
  case "$state" in
    other:*) continue ;;
  esac

  key_input="$team	$agent	$(agmsg_client_id)"
  if command -v shasum >/dev/null 2>&1; then
    key="$(printf '%s' "$key_input" | shasum -a 256 | awk '{print $1}')"
  else
    key="$(printf '%s' "$key_input" | cksum | awk '{print $1}')"
  fi
  MARKER="$(agmsg_run_dir)/.lastcheck-$key"

  if [ -f "$MARKER" ]; then
    if [ "$(uname)" = "Darwin" ]; then
      last=$(stat -f %m "$MARKER")
    else
      last=$(stat -c %Y "$MARKER")
    fi
    now=$(date +%s)
    if [ $(( now - last )) -lt "$INTERVAL" ]; then
      SKIPPED=1
      continue
    fi
  fi

  CHECKED=1
  if ! RESULT="$("$SCRIPT_DIR/inbox.sh" "$team" "$agent" --quiet 2>&1)"; then
    OUTPUT+="agmsg inbox check failed for $team/$agent:"$'\n'
    OUTPUT+="$RESULT"$'\n\n'
    continue
  fi
  touch "$MARKER"

  if [ -n "$RESULT" ]; then
    OUTPUT+="$team/$agent:"$'\n'
    OUTPUT+="$RESULT"$'\n'
    OUTPUT+=$'\n'
  fi
done <<< "$PAIRS"

# No new messages
if [ -z "$OUTPUT" ]; then
  case "$TYPE" in
    codex|copilot)
      if [ "$CHECKED" -eq 0 ] && [ "$SKIPPED" -eq 1 ]; then
        cat <<'ENDJSON'
{
  "continue": true,
  "systemMessage": "agmsg: check skipped (cooldown)"
}
ENDJSON
        exit 0
      fi
      cat <<'ENDJSON'
{
  "continue": true,
  "systemMessage": "agmsg: no new messages"
}
ENDJSON
      ;;
  esac
  exit 0
fi

# New messages found
if [ -n "$OUTPUT" ]; then
  # Escape for JSON: backslash, double-quote, newlines, tabs (macOS/Linux compatible)
  ESCAPED=$(printf '%s' "$OUTPUT" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | awk '{if(NR>1) printf "\\n"; printf "%s",$0}')
  cat <<ENDJSON
{
  "decision": "block",
  "reason": "$ESCAPED"
}
ENDJSON
  exit 0
fi
