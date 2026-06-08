#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-status}"
shift || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"
source "$SCRIPT_DIR/lib/remote-client.sh"

usage() {
  cat <<'EOF'
Usage:
  remote.sh configure <url> [token]
  remote.sh status
  remote.sh switch remote
  remote.sh switch local
EOF
}

case "$ACTION" in
  configure)
    URL="${1:?Usage: remote.sh configure <url> [token]}"
    TOKEN="${2:-}"
    bash "$SCRIPT_DIR/config.sh" set remote.url "${URL%/}" >/dev/null
    if [ -n "$TOKEN" ]; then
      bash "$SCRIPT_DIR/config.sh" set remote.token "$TOKEN" >/dev/null
    fi
    echo "Configured remote.url = ${URL%/}"
    if [ -n "$TOKEN" ]; then
      echo "Configured remote.token"
    fi
    ;;
  status)
    echo "storage.active=$(agmsg_storage_driver)"
    echo "remote.url=$(agmsg_remote_url)"
    if [ -z "$(agmsg_remote_url)" ]; then
      echo "remote.health=not_configured"
      exit 0
    fi
    if agmsg_remote_health >/dev/null; then
      echo "remote.health=ok"
    else
      echo "remote.health=fail"
      exit 1
    fi
    ;;
  switch)
    TARGET="${1:?Usage: remote.sh switch remote|local}"
    case "$TARGET" in
      remote)
        if [ -z "$(agmsg_remote_url)" ]; then
          echo "remote.url is not configured. Run: remote.sh configure <url>" >&2
          exit 1
        fi
        agmsg_remote_health >/dev/null
        bash "$SCRIPT_DIR/config.sh" set storage.active remote >/dev/null
        echo "Switched storage.active = remote"
        ;;
      local|sqlite)
        bash "$SCRIPT_DIR/config.sh" set storage.active sqlite >/dev/null
        echo "Switched storage.active = sqlite"
        ;;
      *)
        echo "Unknown storage target: $TARGET (use remote|local)" >&2
        exit 1
        ;;
    esac
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown action: $ACTION" >&2
    usage >&2
    exit 1
    ;;
esac
