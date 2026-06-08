#!/usr/bin/env bash

agmsg_sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

agmsg_json_message_payload() {
  local team from_agent to_agent body
  team="$(agmsg_sql_escape "$1")"
  from_agent="$(agmsg_sql_escape "$2")"
  to_agent="$(agmsg_sql_escape "$3")"
  body="$(agmsg_sql_escape "$4")"

  sqlite3 :memory: "SELECT json_object('team', '$team', 'from_agent', '$from_agent', 'to_agent', '$to_agent', 'body', '$body');"
}

agmsg_json_read_payload() {
  local team agent ids_csv
  team="$(agmsg_sql_escape "$1")"
  agent="$(agmsg_sql_escape "$2")"
  shift 2

  ids_csv=""
  local id
  for id in "$@"; do
    case "$id" in
      ''|*[!0-9]*) continue ;;
    esac
    if [ -n "$ids_csv" ]; then
      ids_csv="$ids_csv, $id"
    else
      ids_csv="$id"
    fi
  done

  if [ -n "$ids_csv" ]; then
    sqlite3 :memory: "SELECT json_object('team', '$team', 'agent', '$agent', 'ids', json_array($ids_csv));"
  else
    sqlite3 :memory: "SELECT json_object('team', '$team', 'agent', '$agent');"
  fi
}

agmsg_remote_headers() {
  local token
  token="$(agmsg_remote_token)"
  if [ -n "$token" ]; then
    printf '%s\n' "-H" "Authorization: Bearer $token"
  fi
}

agmsg_remote_base_url() {
  local url
  url="$(agmsg_remote_url)"
  if [ -z "$url" ]; then
    echo "Remote storage is selected but remote.url is not configured." >&2
    echo "Run: remote.sh configure <url>" >&2
    return 1
  fi
  printf '%s\n' "${url%/}"
}

agmsg_remote_post() {
  local path="$1"
  local payload="$2"
  local base
  base="$(agmsg_remote_base_url)"

  local headers=()
  while IFS= read -r header_arg; do
    headers+=("$header_arg")
  done < <(agmsg_remote_headers)

  curl -fsS -X POST \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    ${headers[@]+"${headers[@]}"} \
    --data-binary "$payload" \
    "$base$path"
}

agmsg_remote_get_messages() {
  local path="$1"
  local team="$2"
  local agent="$3"
  local limit="$4"
  local base
  base="$(agmsg_remote_base_url)"

  local headers=()
  while IFS= read -r header_arg; do
    headers+=("$header_arg")
  done < <(agmsg_remote_headers)

  curl -fsS -G \
    -H "Accept: application/json" \
    ${headers[@]+"${headers[@]}"} \
    --data-urlencode "team=$team" \
    --data-urlencode "agent=$agent" \
    --data-urlencode "limit=$limit" \
    "$base$path"
}

agmsg_remote_health() {
  local base
  base="$(agmsg_remote_base_url)"

  local headers=()
  while IFS= read -r header_arg; do
    headers+=("$header_arg")
  done < <(agmsg_remote_headers)

  curl -fsS -H "Accept: application/json" ${headers[@]+"${headers[@]}"} "$base/api/v1/health"
}

agmsg_remote_send_message() {
  local team="$1"
  local from_agent="$2"
  local to_agent="$3"
  local body="$4"
  local payload
  payload="$(agmsg_json_message_payload "$team" "$from_agent" "$to_agent" "$body")"
  agmsg_remote_post "/api/v1/messages" "$payload" >/dev/null
}

agmsg_remote_unread_rows() {
  local team="$1"
  local agent="$2"
  local limit="${3:-100}"
  local response tmp
  response="$(agmsg_remote_get_messages "/api/v1/messages/unread" "$team" "$agent" "$limit")"
  tmp="$(mktemp)"
  printf '%s' "$response" > "$tmp"
  sqlite3 -separator $'\t' :memory: "
    SELECT
      json_extract(value, '$.id'),
      json_extract(value, '$.from_agent'),
      replace(replace(json_extract(value, '$.body'), char(10), '\n'), char(9), '\t'),
      json_extract(value, '$.created_at')
    FROM json_each(readfile('$(agmsg_sql_escape "$tmp")'), '$.messages');
  "
  rm -f "$tmp"
}

agmsg_remote_history_rows() {
  local team="$1"
  local agent="$2"
  local limit="${3:-20}"
  local response tmp
  response="$(agmsg_remote_get_messages "/api/v1/messages/history" "$team" "$agent" "$limit")"
  tmp="$(mktemp)"
  printf '%s' "$response" > "$tmp"
  sqlite3 -separator $'\t' :memory: "
    SELECT
      json_extract(value, '$.from_agent'),
      json_extract(value, '$.to_agent'),
      replace(replace(json_extract(value, '$.body'), char(10), '\n'), char(9), '\t'),
      json_extract(value, '$.created_at'),
      CASE WHEN json_extract(value, '$.read') THEN '○' ELSE '●' END
    FROM json_each(readfile('$(agmsg_sql_escape "$tmp")'), '$.messages');
  "
  rm -f "$tmp"
}

agmsg_remote_mark_read() {
  local team="$1"
  local agent="$2"
  shift 2
  local payload
  payload="$(agmsg_json_read_payload "$team" "$agent" "$@")"
  agmsg_remote_post "/api/v1/messages/read" "$payload" >/dev/null
}
