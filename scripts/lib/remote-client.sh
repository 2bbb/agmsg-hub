#!/usr/bin/env bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/client.sh"

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
  local team agent client_id ids_csv
  team="$(agmsg_sql_escape "$1")"
  agent="$(agmsg_sql_escape "$2")"
  client_id="$(agmsg_sql_escape "$(agmsg_client_id)")"
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
    sqlite3 :memory: "SELECT json_object('team', '$team', 'agent', '$agent', 'client_id', '$client_id', 'ids', json_array($ids_csv));"
  else
    sqlite3 :memory: "SELECT json_object('team', '$team', 'agent', '$agent', 'client_id', '$client_id');"
  fi
}

agmsg_json_join_payload() {
  local team agent type project client_id client_label hostname_value project_key
  team="$(agmsg_sql_escape "$1")"
  agent="$(agmsg_sql_escape "$2")"
  type="$(agmsg_sql_escape "$3")"
  project="$(agmsg_sql_escape "$4")"
  client_id="$(agmsg_sql_escape "$(agmsg_client_id)")"
  client_label="$(agmsg_sql_escape "$(agmsg_client_label)")"
  hostname_value="$(agmsg_sql_escape "$(agmsg_hostname)")"
  project_key="$(agmsg_sql_escape "$(agmsg_project_key "$4")")"

  sqlite3 :memory: "SELECT json_object(
    'team', '$team',
    'agent', '$agent',
    'type', '$type',
    'project', '$project',
    'client_id', '$client_id',
    'client_label', '$client_label',
    'hostname', '$hostname_value',
    'project_key', '$project_key'
  );"
}

agmsg_json_role_instruction_payload() {
  local team agent body_file
  team="$(agmsg_sql_escape "$1")"
  agent="$(agmsg_sql_escape "$2")"
  body_file="$3"

  sqlite3 :memory: "SELECT json_object('team', '$team', 'agent', '$agent', 'body', CAST(readfile('$(agmsg_sql_escape "$body_file")') AS TEXT));"
}

agmsg_json_reset_payload() {
  local project type agent client_id
  project="$(agmsg_sql_escape "$1")"
  type="$(agmsg_sql_escape "$2")"
  agent="$(agmsg_sql_escape "$3")"
  client_id="$(agmsg_sql_escape "$(agmsg_client_id)")"

  sqlite3 :memory: "SELECT json_object(
    'project', '$project',
    'type', '$type',
    'agent', '$agent',
    'client_id', '$client_id'
  );"
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
  local client_id="${5:-}"
  local base
  base="$(agmsg_remote_base_url)"

  local headers=()
  while IFS= read -r header_arg; do
    headers+=("$header_arg")
  done < <(agmsg_remote_headers)

  local params=(
    --data-urlencode "team=$team"
    --data-urlencode "agent=$agent"
    --data-urlencode "limit=$limit"
  )
  if [ -n "$client_id" ]; then
    params+=(--data-urlencode "client_id=$client_id")
  fi

  curl -fsS -G \
    -H "Accept: application/json" \
    ${headers[@]+"${headers[@]}"} \
    "${params[@]}" \
    "$base$path"
}

agmsg_remote_get() {
  local path="$1"
  shift
  local base
  base="$(agmsg_remote_base_url)"

  local headers=()
  while IFS= read -r header_arg; do
    headers+=("$header_arg")
  done < <(agmsg_remote_headers)

  curl -fsS -G \
    -H "Accept: application/json" \
    ${headers[@]+"${headers[@]}"} \
    "$@" \
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
  response="$(agmsg_remote_get_messages "/api/v1/messages/unread" "$team" "$agent" "$limit" "$(agmsg_client_id)")"
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
  response="$(agmsg_remote_get_messages "/api/v1/messages/history" "$team" "$agent" "$limit" "$(agmsg_client_id)")"
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

agmsg_remote_join() {
  local team="$1"
  local agent="$2"
  local type="$3"
  local project="$4"
  local payload
  payload="$(agmsg_json_join_payload "$team" "$agent" "$type" "$project")"
  agmsg_remote_post "/api/v1/teams/join" "$payload"
}

agmsg_remote_reset() {
  local project="$1"
  local type="$2"
  local agent="$3"
  local payload
  payload="$(agmsg_json_reset_payload "$project" "$type" "$agent")"
  agmsg_remote_post "/api/v1/teams/reset" "$payload"
}

agmsg_remote_role_instruction_get() {
  local team="$1"
  local agent="$2"
  local response tmp
  response="$(agmsg_remote_get "/api/v1/role-instructions" --data-urlencode "team=$team" --data-urlencode "agent=$agent")"
  tmp="$(mktemp)"
  printf '%s' "$response" > "$tmp"
  sqlite3 :memory: "SELECT COALESCE(json_extract(readfile('$(agmsg_sql_escape "$tmp")'), '$.body'), '');"
  rm -f "$tmp"
}

agmsg_remote_role_instruction_set() {
  local team="$1"
  local agent="$2"
  local body="$3"
  local body_file payload
  body_file="$(mktemp)"
  printf '%s' "$body" > "$body_file"
  payload="$(agmsg_json_role_instruction_payload "$team" "$agent" "$body_file")"
  rm -f "$body_file"
  agmsg_remote_post "/api/v1/role-instructions" "$payload" >/dev/null
}

agmsg_remote_team_rows() {
  local team="$1"
  local response tmp
  response="$(agmsg_remote_get "/api/v1/teams/members" --data-urlencode "team=$team")"
  tmp="$(mktemp)"
  printf '%s' "$response" > "$tmp"
  sqlite3 -separator $'\t' :memory: "
    SELECT
      json_extract(value, '$.name'),
      COALESCE(json_extract(value, '$.types'), ''),
      COALESCE(json_extract(value, '$.project'), '?'),
      COALESCE(json_extract(value, '$.registrations'), 0),
      COALESCE(json_extract(value, '$.client_label'), '?')
    FROM json_each(readfile('$(agmsg_sql_escape "$tmp")'), '$.members');
  "
  rm -f "$tmp"
}

agmsg_remote_identity_summary() {
  local project="$1"
  local type="$2"
  local response tmp
  response="$(agmsg_remote_get "/api/v1/identities" \
    --data-urlencode "project=$project" \
    --data-urlencode "type=$type" \
    --data-urlencode "client_id=$(agmsg_client_id)")"
  tmp="$(mktemp)"
  printf '%s' "$response" > "$tmp"

  local exact_count agent_names team_names suggested_agents suggested_teams all_teams
  exact_count="$(sqlite3 :memory: "SELECT COUNT(*) FROM json_each(readfile('$(agmsg_sql_escape "$tmp")'), '$.exact');")"
  all_teams="$(sqlite3 -separator ',' :memory: "SELECT GROUP_CONCAT(value) FROM json_each(readfile('$(agmsg_sql_escape "$tmp")'), '$.teams');")"

  local client_id
  client_id="$(agmsg_client_id)"

  if [ "$exact_count" = "0" ]; then
    suggested_agents="$(sqlite3 -separator ',' :memory: "
      SELECT GROUP_CONCAT(agent)
      FROM (
        SELECT DISTINCT json_extract(value, '$.agent') AS agent
        FROM json_each(readfile('$(agmsg_sql_escape "$tmp")'), '$.suggested')
        ORDER BY agent
      );
    ")"
    suggested_teams="$(sqlite3 -separator ',' :memory: "
      SELECT GROUP_CONCAT(team)
      FROM (
        SELECT DISTINCT json_extract(value, '$.team') AS team
        FROM json_each(readfile('$(agmsg_sql_escape "$tmp")'), '$.suggested')
        ORDER BY team
      );
    ")"
    rm -f "$tmp"
    if [ -n "$suggested_agents" ]; then
      echo "suggest=true agents=$suggested_agents teams=$suggested_teams type=$type project=$project client=$client_id available_teams=${all_teams:-none}"
    else
      echo "not_joined=true available_teams=${all_teams:-none}"
    fi
    return
  fi

  agent_names="$(sqlite3 -separator ',' :memory: "
    SELECT GROUP_CONCAT(agent)
    FROM (
      SELECT DISTINCT json_extract(value, '$.agent') AS agent
      FROM json_each(readfile('$(agmsg_sql_escape "$tmp")'), '$.exact')
      ORDER BY agent
    );
  ")"
  team_names="$(sqlite3 -separator ',' :memory: "
    SELECT GROUP_CONCAT(team)
    FROM (
      SELECT DISTINCT json_extract(value, '$.team') AS team
      FROM json_each(readfile('$(agmsg_sql_escape "$tmp")'), '$.exact')
      ORDER BY team
    );
  ")"
  rm -f "$tmp"

  if [ "$(printf '%s' "$agent_names" | awk -F, '{print NF}')" -eq 1 ]; then
    echo "agent=$agent_names teams=$team_names type=$type project=$project client=$client_id"
  else
    echo "multiple=true agents=$agent_names teams=$team_names type=$type project=$project client=$client_id"
  fi
}

agmsg_remote_identity_pairs() {
  local project="$1"
  local type="$2"
  local response tmp
  response="$(agmsg_remote_get "/api/v1/identities" \
    --data-urlencode "project=$project" \
    --data-urlencode "type=$type" \
    --data-urlencode "client_id=$(agmsg_client_id)")"
  tmp="$(mktemp)"
  printf '%s' "$response" > "$tmp"
  sqlite3 -separator $'\t' :memory: "
    SELECT json_extract(value, '$.team'), json_extract(value, '$.agent')
    FROM json_each(readfile('$(agmsg_sql_escape "$tmp")'), '$.exact')
    ORDER BY 1, 2;
  "
  rm -f "$tmp"
}
