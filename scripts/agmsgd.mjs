#!/usr/bin/env node
import { createServer } from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const API_VERSION = 'v1';
const SERVER_VERSION = '0.1.0';

function parseArgs(argv) {
  const args = {
    host: '127.0.0.1',
    port: 8787,
    db: '',
    token: '',
    verbose: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--host') {
      args.host = argv[++i] || args.host;
    } else if (arg === '--port') {
      args.port = Number(argv[++i] || args.port);
    } else if (arg === '--db') {
      args.db = argv[++i] || '';
    } else if (arg === '--token') {
      args.token = argv[++i] || '';
    } else if (arg === '--verbose') {
      args.verbose = true;
    } else if (arg === '-h' || arg === '--help') {
      usage(0);
    } else {
      console.error(`Unknown option: ${arg}`);
      usage(1);
    }
  }

  if (!args.db) {
    console.error('Missing required --db <path>');
    usage(1);
  }
  if (!Number.isInteger(args.port) || args.port < 0 || args.port > 65535) {
    console.error('Invalid --port value');
    usage(1);
  }

  return args;
}

function usage(status) {
  const out = status === 0 ? console.log : console.error;
  out('Usage: agmsgd.mjs --db <path> [--host 127.0.0.1] [--port 8787] [--token <token>] [--verbose]');
  process.exit(status);
}

function initDb(path) {
  mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec(`
    PRAGMA journal_mode=WAL;

    CREATE TABLE IF NOT EXISTS messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      team TEXT NOT NULL,
      from_agent TEXT NOT NULL,
      to_agent TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
      read_at TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_unread
      ON messages(team, to_agent, read_at)
      WHERE read_at IS NULL;
    CREATE INDEX IF NOT EXISTS idx_history
      ON messages(team, created_at DESC);
  `);
  return db;
}

function jsonResponse(res, status, payload) {
  const body = Buffer.from(JSON.stringify(payload), 'utf8');
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': body.length,
  });
  res.end(body);
}

function errorResponse(res, status, code, message) {
  jsonResponse(res, status, { error: { code, message } });
}

function requireAuth(req, res, token) {
  if (!token) {
    return true;
  }
  if (req.headers.authorization === `Bearer ${token}`) {
    return true;
  }
  errorResponse(res, 401, 'unauthorized', 'missing or invalid token');
  return false;
}

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  if (chunks.length === 0) {
    return {};
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    return null;
  }
}

function messageRow(row) {
  return {
    id: row.id,
    team: row.team,
    from_agent: row.from_agent,
    to_agent: row.to_agent,
    body: row.body,
    created_at: row.created_at,
    read_at: row.read_at,
    read: row.read_at !== null,
  };
}

function intParam(value, fallback) {
  const parsed = Number.parseInt(value || '', 10);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.max(1, Math.min(parsed, 500));
}

function createHandler({ db, token, verbose }) {
  return async function handler(req, res) {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (verbose) {
      console.error(`${req.method} ${url.pathname}`);
    }

    if (req.method === 'GET' && url.pathname === '/api/v1/health') {
      jsonResponse(res, 200, {
        ok: true,
        api_version: API_VERSION,
        server_version: SERVER_VERSION,
        storage: 'sqlite',
      });
      return;
    }

    if (!requireAuth(req, res, token)) {
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/v1/messages') {
      await handleSend(req, res, db);
      return;
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/messages/unread') {
      handleUnread(url, res, db);
      return;
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/messages/read') {
      await handleRead(req, res, db);
      return;
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/messages/history') {
      handleHistory(url, res, db);
      return;
    }

    errorResponse(res, 404, 'not_found', 'endpoint not found');
  };
}

async function handleSend(req, res, db) {
  const payload = await readJson(req);
  if (payload === null) {
    errorResponse(res, 400, 'invalid_json', 'request body is not valid JSON');
    return;
  }

  const required = ['team', 'from_agent', 'to_agent', 'body'];
  const missing = required.filter((name) => !payload[name]);
  if (missing.length > 0) {
    errorResponse(res, 400, 'missing_field', `missing: ${missing.join(', ')}`);
    return;
  }

  const row = db.prepare(`
    INSERT INTO messages (team, from_agent, to_agent, body)
    VALUES (?, ?, ?, ?)
    RETURNING id, created_at
  `).get(payload.team, payload.from_agent, payload.to_agent, payload.body);

  jsonResponse(res, 201, row);
}

function handleUnread(url, res, db) {
  const team = url.searchParams.get('team') || '';
  const agent = url.searchParams.get('agent') || '';
  const limit = intParam(url.searchParams.get('limit'), 100);
  if (!team || !agent) {
    errorResponse(res, 400, 'missing_field', 'team and agent are required');
    return;
  }

  const rows = db.prepare(`
    SELECT id, team, from_agent, to_agent, body, created_at, read_at
    FROM messages
    WHERE team = ? AND to_agent = ? AND read_at IS NULL
    ORDER BY created_at ASC, id ASC
    LIMIT ?
  `).all(team, agent, limit);

  jsonResponse(res, 200, { messages: rows.map(messageRow) });
}

async function handleRead(req, res, db) {
  const payload = await readJson(req);
  if (payload === null) {
    errorResponse(res, 400, 'invalid_json', 'request body is not valid JSON');
    return;
  }

  const team = payload.team || '';
  const agent = payload.agent || '';
  if (!team || !agent) {
    errorResponse(res, 400, 'missing_field', 'team and agent are required');
    return;
  }

  let result;
  if (Array.isArray(payload.ids) && payload.ids.length > 0) {
    const ids = payload.ids
      .map((value) => Number.parseInt(String(value), 10))
      .filter((value) => Number.isInteger(value) && value > 0);
    if (ids.length === 0) {
      jsonResponse(res, 200, { updated: 0 });
      return;
    }
    const placeholders = ids.map(() => '?').join(', ');
    result = db.prepare(`
      UPDATE messages
      SET read_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      WHERE team = ? AND to_agent = ? AND read_at IS NULL
        AND id IN (${placeholders})
    `).run(team, agent, ...ids);
  } else {
    result = db.prepare(`
      UPDATE messages
      SET read_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
      WHERE team = ? AND to_agent = ? AND read_at IS NULL
    `).run(team, agent);
  }

  jsonResponse(res, 200, { updated: result.changes });
}

function handleHistory(url, res, db) {
  const team = url.searchParams.get('team') || '';
  const agent = url.searchParams.get('agent') || '';
  const limit = intParam(url.searchParams.get('limit'), 20);
  if (!team) {
    errorResponse(res, 400, 'missing_field', 'team is required');
    return;
  }

  let rows;
  if (agent) {
    rows = db.prepare(`
      SELECT id, team, from_agent, to_agent, body, created_at, read_at
      FROM messages
      WHERE team = ? AND (from_agent = ? OR to_agent = ?)
      ORDER BY created_at DESC, id DESC
      LIMIT ?
    `).all(team, agent, agent, limit);
  } else {
    rows = db.prepare(`
      SELECT id, team, from_agent, to_agent, body, created_at, read_at
      FROM messages
      WHERE team = ?
      ORDER BY created_at DESC, id DESC
      LIMIT ?
    `).all(team, limit);
  }

  jsonResponse(res, 200, { messages: rows.reverse().map(messageRow) });
}

const args = parseArgs(process.argv.slice(2));
const db = initDb(args.db);
const server = createServer(createHandler({ db, token: args.token, verbose: args.verbose }));

server.listen(args.port, args.host, () => {
  const address = server.address();
  console.log(`agmsgd listening on http://${address.address}:${address.port}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    server.close(() => {
      db.close();
      process.exit(0);
    });
  });
}
