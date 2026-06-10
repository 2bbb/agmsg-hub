#!/usr/bin/env bash

# Helpers for reading/updating Codex config.toml.
#
# Scope is intentionally narrow: enough TOML handling for the Codex
# [sandbox_workspace_write].writable_roots array used by agmsg. This is not a
# general TOML parser.

: "${AGMSG_CODEX_CONFIG_BACKED_UP:=false}"

agmsg_canonical_path() {
  local path="$1"
  if [ -d "$path" ]; then
    (cd "$path" && pwd -P)
  else
    local parent base
    parent="$(dirname "$path")"
    base="$(basename "$path")"
    if [ -d "$parent" ]; then
      printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$base"
    else
      printf '%s\n' "$path"
    fi
  fi
}

agmsg_path_covers() {
  local root="$1"
  local target="$2"
  root="$(agmsg_canonical_path "$root")"
  target="$(agmsg_canonical_path "$target")"

  [ "$root" = "$target" ] && return 0
  case "$target" in
    "$root"/*) return 0 ;;
    *) return 1 ;;
  esac
}

agmsg_codex_writable_roots() {
  local config="$1"
  awk '
    /^\[/ { in_sandbox = ($0 == "[sandbox_workspace_write]") }
    in_sandbox && /writable_roots[[:space:]]*=/ {
      in_roots = 1
    }
    in_roots {
      print
      if ($0 ~ /\]/) exit
    }
  ' "$config" |
    grep -Eo '"[^"]+"' |
    sed 's/^"//; s/"$//'
}

agmsg_codex_config_covers_path() {
  local config="$1"
  local path="$2"
  local root

  [ -f "$config" ] || return 1

  while IFS= read -r root; do
    [ -n "$root" ] || continue
    if agmsg_path_covers "$root" "$path"; then
      return 0
    fi
  done < <(agmsg_codex_writable_roots "$config")

  return 1
}

agmsg_codex_backup_config_once() {
  local config="$1"
  if [ "$AGMSG_CODEX_CONFIG_BACKED_UP" = true ]; then
    return
  fi
  if [ -f "$config" ]; then
    cp "$config" "$config.bak"
  fi
  AGMSG_CODEX_CONFIG_BACKED_UP=true
}

agmsg_codex_add_writable_root() {
  local config="$1"
  local path="$2"
  local entry

  case "$path" in
    *\"*|*$'\n'*)
      return 1
      ;;
  esac

  mkdir -p "$(dirname "$config")"
  agmsg_codex_backup_config_once "$config"
  entry="\"$path\""

  if [ ! -f "$config" ]; then
    printf '[sandbox_workspace_write]\nwritable_roots = [%s]\n' "$entry" > "$config"
    return
  fi

  if ! grep -q '^\[sandbox_workspace_write\]' "$config" 2>/dev/null; then
    printf '\n[sandbox_workspace_write]\nwritable_roots = [%s]\n' "$entry" >> "$config"
    return
  fi

  if ! awk '
    /^\[/ { in_sandbox = ($0 == "[sandbox_workspace_write]") }
    in_sandbox && /writable_roots[[:space:]]*=/ { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$config" 2>/dev/null; then
    awk -v entry="$entry" '
      { print }
      /^\[sandbox_workspace_write\]/ { print "writable_roots = [" entry "]" }
    ' "$config" > "$config.tmp" && mv "$config.tmp" "$config"
    return
  fi

  awk -v entry="$entry" '
    /^\[/ { in_sandbox = ($0 == "[sandbox_workspace_write]") }
    in_sandbox && /writable_roots[[:space:]]*=/ {
      in_roots = 1
      if ($0 ~ /\]/) {
        sub(/\]/, ", " entry "]")
        print
        in_roots = 0
        next
      }
      print
      next
    }
    in_roots && /\]/ {
      if (pending != "") {
        sub(/[[:space:]]*$/, ",", pending)
        print pending
        pending = ""
      }
      print "  " entry
      print
      in_roots = 0
      next
    }
    in_roots {
      if (pending != "") {
        print pending
      }
      pending = $0
      next
    }
    { print }
  ' "$config" > "$config.tmp" && mv "$config.tmp" "$config"
}
