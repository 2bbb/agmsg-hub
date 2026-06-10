#!/usr/bin/env bash

agmsg_hash_string() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
    return
  fi
  printf '%s' "$1" | cksum | awk '{print $1}'
}

agmsg_generate_client_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr 'A-Z' 'a-z'
    return
  fi
  agmsg_hash_string "$(hostname 2>/dev/null || echo unknown):$(date +%s):$$"
}

agmsg_client_id_file() {
  printf '%s/client_id\n' "$(agmsg_home)"
}

agmsg_client_id() {
  if [ -n "${AGMSG_CLIENT_ID:-}" ]; then
    printf '%s\n' "$AGMSG_CLIENT_ID"
    return
  fi

  local path
  path="$(agmsg_client_id_file)"
  if [ ! -f "$path" ]; then
    mkdir -p "$(dirname "$path")"
    agmsg_generate_client_id > "$path"
  fi
  sed -n '1p' "$path"
}

agmsg_hostname() {
  hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown
}

agmsg_client_label() {
  if [ -n "${AGMSG_CLIENT_LABEL:-}" ]; then
    printf '%s\n' "$AGMSG_CLIENT_LABEL"
    return
  fi
  agmsg_hostname
}

agmsg_realpath() {
  local path="$1"
  if [ -d "$path" ]; then
    (cd "$path" 2>/dev/null && pwd -P) || printf '%s\n' "$path"
    return
  fi

  local dir base
  dir="$(dirname "$path")"
  base="$(basename "$path")"
  if [ -d "$dir" ]; then
    printf '%s/%s\n' "$(cd "$dir" 2>/dev/null && pwd -P)" "$base"
    return
  fi
  printf '%s\n' "$path"
}

agmsg_normalize_project_key() {
  local key="$1"
  case "$key" in
    git:*)
      local remote="${key#git:}"
      while [ "${remote%/}" != "$remote" ]; do
        remote="${remote%/}"
      done
      case "$remote" in
        *.git) remote="${remote%.git}" ;;
      esac
      printf 'git:%s\n' "$remote"
      ;;
    *)
      printf '%s\n' "$key"
      ;;
  esac
}

agmsg_project_key() {
  local project_path="$1"
  if [ -n "${AGMSG_PROJECT_KEY:-}" ]; then
    agmsg_normalize_project_key "$AGMSG_PROJECT_KEY"
    return
  fi

  local git_root remote real
  if git_root="$(git -C "$project_path" rev-parse --show-toplevel 2>/dev/null)"; then
    remote="$(git -C "$git_root" config --get remote.origin.url 2>/dev/null || true)"
    if [ -n "$remote" ]; then
      agmsg_normalize_project_key "git:$remote"
      return
    fi
    printf 'git-local:%s\n' "$(agmsg_hash_string "$(agmsg_realpath "$git_root")")"
    return
  fi

  real="$(agmsg_realpath "$project_path")"
  printf 'local:%s:%s\n' "$(agmsg_client_id)" "$(agmsg_hash_string "$real")"
}
