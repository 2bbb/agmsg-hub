#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/storage.sh"
DB="$(agmsg_db_path)"
DB_DIR="$(dirname "$DB")"
mkdir -p "$DB_DIR"

if [ ! -f "$DB" ]; then
  sqlite3 "$DB" <<'SQL'
PRAGMA journal_mode=WAL;

CREATE TABLE messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  team TEXT NOT NULL,
  from_agent TEXT NOT NULL,
  to_agent TEXT NOT NULL,
  body TEXT NOT NULL,
  project_id TEXT,
  project_key TEXT,
  project_path TEXT,
  from_client_id TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  read_at TEXT
);

CREATE INDEX idx_unread ON messages(team, to_agent, read_at) WHERE read_at IS NULL;
CREATE INDEX idx_history ON messages(team, created_at DESC);
CREATE INDEX idx_messages_project ON messages(team, project_id, created_at DESC);

CREATE TABLE message_reads (
  message_id INTEGER NOT NULL,
  team TEXT NOT NULL,
  agent TEXT NOT NULL,
  client_id TEXT NOT NULL,
  read_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  PRIMARY KEY (message_id, client_id)
);

CREATE INDEX idx_message_reads_inbox
  ON message_reads(team, agent, client_id, message_id);
SQL
  echo "DB initialized: $DB"
fi
