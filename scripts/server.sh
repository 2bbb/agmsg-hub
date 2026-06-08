#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-serve}"
if [ "$ACTION" = "serve" ]; then
  shift || true
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"

case "$ACTION" in
  serve)
    DB="$(agmsg_db_path)"
    exec node --no-warnings "$SCRIPT_DIR/agmsgd.mjs" --db "$DB" "$@"
    ;;
  *)
    echo "Unknown action: $ACTION (use serve)" >&2
    exit 1
    ;;
esac
