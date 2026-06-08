#!/usr/bin/env bash
# storage.sh — resolve the path to the sqlite message store (messages.db).
#
# Scope: the storage axis only — where messages are persisted. This is NOT a
# storage-driver interface; it just centralizes the path resolution that was
# previously duplicated across the script set.
#
# Resolution order:
#   1. AGMSG_STORAGE_PATH — directory that holds messages.db (env override)
#   2. built-in default   — <skill>/db
#
# [seam] A config-file layer is expected to slot in between the env override
# and the built-in default once the storage-driver work lands; the intended
# full order is env > config > default. Keep that logic here so call sites
# stay unchanged.

# Echo the directory that holds (or will hold) the message store.
agmsg_storage_dir() {
  if [ -n "${AGMSG_STORAGE_PATH:-}" ]; then
    # Strip a single trailing slash for a stable join with the filename.
    printf '%s\n' "${AGMSG_STORAGE_PATH%/}"
    return
  fi
  local lib_dir skill_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  skill_dir="$(cd "$lib_dir/../.." && pwd)"
  printf '%s\n' "$skill_dir/db"
}

# Echo the full path to messages.db.
agmsg_db_path() {
  printf '%s/messages.db\n' "$(agmsg_storage_dir)"
}

agmsg_config_file() {
  local lib_dir skill_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  skill_dir="$(cd "$lib_dir/../.." && pwd)"
  printf '%s/db/config.yaml\n' "$skill_dir"
}

agmsg_config_get() {
  local key="$1"
  local default="${2:-}"
  local config_file
  config_file="$(agmsg_config_file)"

  if [ ! -f "$config_file" ]; then
    printf '%s\n' "$default"
    return
  fi

  local section="" field="" value=""
  if [[ "$key" == *.* ]]; then
    section="${key%%.*}"
    field="${key#*.}"
  else
    field="$key"
  fi

  if [ -n "$section" ]; then
    value=$(awk -v section="$section" -v field="$field" '
      /^[^ #]/ { in_section = ($0 ~ "^" section ":") }
      in_section && $0 ~ "^  " field ":" {
        sub(/^  [^ ]+:[ \t]*/, "")
        sub(/[ \t]+#.*$/, "")
        print
        exit
      }
    ' "$config_file")
  else
    value=$(awk -v field="$field" '
      /^[^ #]/ && $0 ~ "^" field ":" {
        sub(/^[^ ]+:[ \t]*/, "")
        sub(/[ \t]+#.*$/, "")
        print
        exit
      }
    ' "$config_file")
  fi

  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default"
  fi
}

agmsg_storage_driver() {
  if [ -n "${AGMSG_STORAGE_DRIVER:-}" ]; then
    printf '%s\n' "$AGMSG_STORAGE_DRIVER"
    return
  fi
  agmsg_config_get "storage.active" "sqlite"
}

agmsg_remote_url() {
  if [ -n "${AGMSG_REMOTE_URL:-}" ]; then
    printf '%s\n' "${AGMSG_REMOTE_URL%/}"
    return
  fi
  agmsg_config_get "remote.url" ""
}

agmsg_remote_token() {
  if [ -n "${AGMSG_REMOTE_TOKEN:-}" ]; then
    printf '%s\n' "$AGMSG_REMOTE_TOKEN"
    return
  fi
  agmsg_config_get "remote.token" ""
}

agmsg_using_remote_storage() {
  [ "$(agmsg_storage_driver)" = "remote" ]
}
