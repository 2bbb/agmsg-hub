#!/usr/bin/env node
import { createServer } from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const API_VERSION = 'v1';
const SERVER_VERSION = '0.1.0';
const WEB_UI_HTML = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>agmsgd</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #f7f7f4;
      --fg: #1e2328;
      --muted: #66707a;
      --line: #d8ddd8;
      --panel: #ffffff;
      --accent: #1463ff;
      --danger: #b3261e;
      --ok: #167344;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #111315;
        --fg: #e8eaed;
        --muted: #a1a8b0;
        --line: #30363d;
        --panel: #181b1f;
        --accent: #7aa2ff;
        --danger: #ff8a80;
        --ok: #78d59a;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--fg);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
      line-height: 1.45;
    }
    header {
      border-bottom: 1px solid var(--line);
      padding: 14px 20px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
    }
    h1 { font-size: 18px; margin: 0; letter-spacing: 0; }
    main {
      display: grid;
      grid-template-columns: minmax(220px, 300px) minmax(0, 1fr);
      gap: 0;
      min-height: calc(100vh - 57px);
    }
    aside {
      border-right: 1px solid var(--line);
      padding: 16px;
      overflow: auto;
    }
    section {
      padding: 16px 20px;
      overflow: auto;
    }
    .toolbar {
      display: flex;
      align-items: center;
      gap: 8px;
      flex-wrap: wrap;
    }
    .status {
      font-size: 13px;
      color: var(--muted);
    }
    .ok { color: var(--ok); }
    .error { color: var(--danger); }
    button, input, textarea, select {
      font: inherit;
      color: inherit;
    }
    button {
      border: 1px solid var(--line);
      background: var(--panel);
      border-radius: 6px;
      padding: 7px 10px;
      cursor: pointer;
    }
    button.primary {
      background: var(--accent);
      border-color: var(--accent);
      color: white;
    }
    input, textarea, select {
      width: 100%;
      border: 1px solid var(--line);
      background: var(--panel);
      border-radius: 6px;
      padding: 8px 9px;
    }
    textarea { min-height: 86px; resize: vertical; }
    label {
      display: grid;
      gap: 5px;
      font-size: 13px;
      color: var(--muted);
    }
    .stack { display: grid; gap: 12px; }
    .row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .panel {
      border: 1px solid var(--line);
      background: var(--panel);
      border-radius: 8px;
      padding: 14px;
    }
    .panel h2 {
      font-size: 15px;
      margin: 0 0 10px;
      letter-spacing: 0;
    }
    .team-list {
      display: grid;
      gap: 6px;
    }
    .team-button {
      text-align: left;
      width: 100%;
      display: flex;
      justify-content: space-between;
      gap: 8px;
    }
    .team-button[aria-current="true"] {
      outline: 2px solid var(--accent);
      outline-offset: 1px;
    }
    .select-button {
      padding: 4px 7px;
      font-size: 13px;
    }
    .selected-row {
      outline: 2px solid var(--accent);
      outline-offset: -2px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 14px;
    }
    th, td {
      border-bottom: 1px solid var(--line);
      padding: 8px 6px;
      text-align: left;
      vertical-align: top;
    }
    th {
      color: var(--muted);
      font-weight: 600;
    }
    .messages {
      display: grid;
      gap: 8px;
    }
    .message {
      border: 1px solid var(--line);
      background: var(--panel);
      border-radius: 8px;
      padding: 10px;
    }
    .message-head {
      display: flex;
      justify-content: space-between;
      gap: 10px;
      color: var(--muted);
      font-size: 13px;
      margin-bottom: 6px;
    }
    .message-body {
      white-space: pre-wrap;
      overflow-wrap: anywhere;
    }
    .empty {
      color: var(--muted);
      font-size: 14px;
      padding: 10px 0;
    }
    @media (max-width: 760px) {
      main { grid-template-columns: 1fr; }
      aside { border-right: 0; border-bottom: 1px solid var(--line); }
      .row { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <header>
    <h1>agmsgd</h1>
    <div class="toolbar">
      <span id="health" class="status">Checking...</span>
      <button id="refresh">Refresh</button>
    </div>
  </header>
  <main>
    <aside class="stack">
      <label>Bearer token
        <input id="token" type="password" autocomplete="off">
      </label>
      <div class="panel">
        <h2>Teams</h2>
        <div id="teams" class="team-list"></div>
      </div>
    </aside>
    <section class="stack">
      <div class="panel">
        <h2 id="team-title">No team selected</h2>
        <div id="members" class="empty"></div>
      </div>
      <div class="panel">
        <h2>Role Instruction</h2>
        <form id="instruction-form" class="stack">
          <div id="instruction-target" class="status">No role selected</div>
          <label>Instruction
            <textarea id="instruction"></textarea>
          </label>
          <div class="toolbar">
            <button class="primary" type="submit">Save</button>
            <span id="instruction-status" class="status"></span>
          </div>
        </form>
      </div>
      <div class="panel">
        <h2>Send</h2>
        <form id="send-form" class="stack">
          <div class="row">
            <label>From
              <input id="from" autocomplete="off">
            </label>
            <label>To
              <input id="to" autocomplete="off">
            </label>
          </div>
          <label>Message
            <textarea id="body"></textarea>
          </label>
          <div class="toolbar">
            <button class="primary" type="submit">Send</button>
            <span id="send-status" class="status"></span>
          </div>
        </form>
      </div>
      <div class="panel">
        <h2>History</h2>
        <div id="messages" class="messages"></div>
      </div>
    </section>
  </main>
  <script>
    const state = { teams: [], members: [], selectedTeam: "", selectedAgent: "" };
    const els = {
      health: document.querySelector("#health"),
      refresh: document.querySelector("#refresh"),
      token: document.querySelector("#token"),
      teams: document.querySelector("#teams"),
      teamTitle: document.querySelector("#team-title"),
      members: document.querySelector("#members"),
      instructionForm: document.querySelector("#instruction-form"),
      instructionTarget: document.querySelector("#instruction-target"),
      instruction: document.querySelector("#instruction"),
      instructionStatus: document.querySelector("#instruction-status"),
      messages: document.querySelector("#messages"),
      form: document.querySelector("#send-form"),
      from: document.querySelector("#from"),
      to: document.querySelector("#to"),
      body: document.querySelector("#body"),
      sendStatus: document.querySelector("#send-status"),
    };

    function headers(extra = {}) {
      const base = { ...extra };
      const token = els.token.value.trim();
      if (token) base.Authorization = "Bearer " + token;
      return base;
    }

    async function api(path, options = {}) {
      const response = await fetch(path, {
        ...options,
        headers: headers(options.headers || {}),
      });
      const text = await response.text();
      const data = text ? JSON.parse(text) : {};
      if (!response.ok) {
        const message = data.error?.message || response.statusText;
        throw new Error(message);
      }
      return data;
    }

    function setHealth(text, cls = "") {
      els.health.className = "status " + cls;
      els.health.textContent = text;
    }

    function escapeText(value) {
      return String(value ?? "");
    }

    async function loadHealth() {
      try {
        const health = await api("/api/v1/health");
        setHealth("OK " + health.server_version, "ok");
      } catch (error) {
        setHealth(error.message, "error");
      }
    }

    async function loadTeams() {
      const data = await api("/api/v1/teams");
      state.teams = data.teams || [];
      if (!state.selectedTeam && state.teams.length > 0) {
        state.selectedTeam = state.teams[0].name;
      }
      renderTeams();
    }

    function renderTeams() {
      els.teams.replaceChildren();
      if (state.teams.length === 0) {
        const empty = document.createElement("div");
        empty.className = "empty";
        empty.textContent = "No teams";
        els.teams.append(empty);
        return;
      }
      for (const team of state.teams) {
        const button = document.createElement("button");
        button.className = "team-button";
        button.type = "button";
        button.setAttribute("aria-current", team.name === state.selectedTeam ? "true" : "false");
        button.innerHTML = "<span></span><span></span>";
        button.children[0].textContent = team.name;
        button.children[1].textContent = team.members;
        button.addEventListener("click", () => {
          state.selectedTeam = team.name;
          refreshSelected();
        });
        els.teams.append(button);
      }
    }

    async function loadMembers() {
      if (!state.selectedTeam) {
        els.teamTitle.textContent = "No team selected";
        els.members.className = "empty";
        els.members.textContent = "No members";
        state.members = [];
        state.selectedAgent = "";
        renderInstructionEmpty();
        return;
      }
      els.teamTitle.textContent = state.selectedTeam;
      const data = await api("/api/v1/teams/members?team=" + encodeURIComponent(state.selectedTeam));
      const members = data.members || [];
      state.members = members;
      if (members.length === 0) {
        els.members.className = "empty";
        els.members.textContent = "No members";
        state.selectedAgent = "";
        renderInstructionEmpty();
        return;
      }
      if (!members.some((member) => member.name === state.selectedAgent)) {
        state.selectedAgent = members[0].name;
      }
      const table = document.createElement("table");
      table.innerHTML = "<thead><tr><th>Name</th><th>Types</th><th>Project</th><th>Regs</th><th></th></tr></thead><tbody></tbody>";
      for (const member of members) {
        const tr = document.createElement("tr");
        if (member.name === state.selectedAgent) {
          tr.className = "selected-row";
        }
        for (const value of [member.name, member.types, member.project, member.registrations]) {
          const td = document.createElement("td");
          td.textContent = escapeText(value);
          tr.append(td);
        }
        const action = document.createElement("td");
        const button = document.createElement("button");
        button.className = "select-button";
        button.type = "button";
        button.textContent = member.name === state.selectedAgent ? "Selected" : "Select";
        button.addEventListener("click", async () => {
          state.selectedAgent = member.name;
          if (!els.from.value.trim()) {
            els.from.value = member.name;
          }
          await refreshSelected();
        });
        action.append(button);
        tr.append(action);
        table.querySelector("tbody").append(tr);
      }
      els.members.className = "";
      els.members.replaceChildren(table);
    }

    function renderInstructionEmpty() {
      els.instructionTarget.textContent = "No role selected";
      els.instruction.value = "";
      els.instructionStatus.textContent = "";
    }

    async function loadInstruction() {
      if (!state.selectedTeam || !state.selectedAgent) {
        renderInstructionEmpty();
        return;
      }
      els.instructionTarget.textContent = state.selectedTeam + " / " + state.selectedAgent;
      els.instructionStatus.textContent = "";
      const data = await api(
        "/api/v1/role-instructions?team=" + encodeURIComponent(state.selectedTeam) +
        "&agent=" + encodeURIComponent(state.selectedAgent)
      );
      els.instruction.value = data.body || "";
    }

    async function loadHistory() {
      els.messages.replaceChildren();
      if (!state.selectedTeam) {
        const empty = document.createElement("div");
        empty.className = "empty";
        empty.textContent = "No messages";
        els.messages.append(empty);
        return;
      }
      const data = await api("/api/v1/messages/history?team=" + encodeURIComponent(state.selectedTeam) + "&limit=100");
      const messages = data.messages || [];
      if (messages.length === 0) {
        const empty = document.createElement("div");
        empty.className = "empty";
        empty.textContent = "No messages";
        els.messages.append(empty);
        return;
      }
      for (const message of messages) {
        const item = document.createElement("article");
        item.className = "message";
        const head = document.createElement("div");
        head.className = "message-head";
        const route = document.createElement("span");
        route.textContent = message.from_agent + " -> " + message.to_agent;
        const time = document.createElement("span");
        time.textContent = message.created_at + (message.read ? " read" : " unread");
        const body = document.createElement("div");
        body.className = "message-body";
        body.textContent = message.body;
        head.append(route, time);
        item.append(head, body);
        els.messages.append(item);
      }
    }

    async function refreshSelected() {
      renderTeams();
      try {
        await loadMembers();
        await Promise.all([loadInstruction(), loadHistory()]);
      } catch (error) {
        setHealth(error.message, "error");
      }
    }

    async function refreshAll() {
      await loadHealth();
      try {
        await loadTeams();
        await refreshSelected();
      } catch (error) {
        setHealth(error.message, "error");
      }
    }

    els.refresh.addEventListener("click", refreshAll);
    els.token.addEventListener("change", refreshAll);
    els.instructionForm.addEventListener("submit", async (event) => {
      event.preventDefault();
      if (!state.selectedTeam || !state.selectedAgent) return;
      els.instructionStatus.textContent = "";
      try {
        await api("/api/v1/role-instructions", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            team: state.selectedTeam,
            agent: state.selectedAgent,
            body: els.instruction.value,
          }),
        });
        els.instructionStatus.textContent = "Saved";
      } catch (error) {
        els.instructionStatus.textContent = error.message;
      }
    });
    els.form.addEventListener("submit", async (event) => {
      event.preventDefault();
      if (!state.selectedTeam) return;
      els.sendStatus.textContent = "";
      try {
        await api("/api/v1/messages", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            team: state.selectedTeam,
            from_agent: els.from.value.trim(),
            to_agent: els.to.value.trim(),
            body: els.body.value,
          }),
        });
        els.body.value = "";
        els.sendStatus.textContent = "Sent";
        await refreshAll();
      } catch (error) {
        els.sendStatus.textContent = error.message;
      }
    });

    refreshAll();
  </script>
</body>
</html>`;

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

    CREATE TABLE IF NOT EXISTS teams (
      name TEXT PRIMARY KEY,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
    );

    CREATE TABLE IF NOT EXISTS registrations (
      team TEXT NOT NULL,
      agent TEXT NOT NULL,
      agent_type TEXT NOT NULL,
      project_path TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
      PRIMARY KEY (team, agent, agent_type, project_path),
      FOREIGN KEY (team) REFERENCES teams(name) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_registrations_project
      ON registrations(project_path, agent_type);
    CREATE INDEX IF NOT EXISTS idx_registrations_team_agent
      ON registrations(team, agent);

    CREATE TABLE IF NOT EXISTS role_instructions (
      team TEXT NOT NULL,
      agent TEXT NOT NULL,
      body TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
      PRIMARY KEY (team, agent),
      FOREIGN KEY (team) REFERENCES teams(name) ON DELETE CASCADE
    );
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

function htmlResponse(res, status, html) {
  const body = Buffer.from(html, 'utf8');
  res.writeHead(status, {
    'content-type': 'text/html; charset=utf-8',
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

    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
      htmlResponse(res, 200, WEB_UI_HTML);
      return;
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
    if (req.method === 'POST' && url.pathname === '/api/v1/teams/join') {
      await handleJoin(req, res, db);
      return;
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/teams') {
      handleTeams(res, db);
      return;
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/teams/members') {
      handleTeamMembers(url, res, db);
      return;
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/role-instructions') {
      handleGetRoleInstruction(url, res, db);
      return;
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/role-instructions') {
      await handleSetRoleInstruction(req, res, db);
      return;
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/identities') {
      handleIdentities(url, res, db);
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

async function handleJoin(req, res, db) {
  const payload = await readJson(req);
  if (payload === null) {
    errorResponse(res, 400, 'invalid_json', 'request body is not valid JSON');
    return;
  }

  const team = payload.team || '';
  const agent = payload.agent || '';
  const agentType = payload.type || payload.agent_type || '';
  const project = payload.project || payload.project_path || '';
  if (!team || !agent || !agentType || !project) {
    errorResponse(res, 400, 'missing_field', 'team, agent, type, and project are required');
    return;
  }

  const existingTeam = db.prepare('SELECT name FROM teams WHERE name = ?').get(team);
  db.prepare('INSERT OR IGNORE INTO teams (name) VALUES (?)').run(team);
  db.prepare(`
    INSERT OR IGNORE INTO registrations (team, agent, agent_type, project_path)
    VALUES (?, ?, ?, ?)
  `).run(team, agent, agentType, project);

  jsonResponse(res, 200, {
    team,
    agent,
    created_team: !existingTeam,
  });
}

function handleTeams(res, db) {
  const rows = db.prepare(`
    SELECT
      teams.name AS name,
      teams.created_at AS created_at,
      COUNT(DISTINCT registrations.agent) AS members
    FROM teams
    LEFT JOIN registrations ON registrations.team = teams.name
    GROUP BY teams.name
    ORDER BY teams.name ASC
  `).all();

  jsonResponse(res, 200, { teams: rows });
}

function handleTeamMembers(url, res, db) {
  const team = url.searchParams.get('team') || '';
  if (!team) {
    errorResponse(res, 400, 'missing_field', 'team is required');
    return;
  }

  const teamRow = db.prepare('SELECT name FROM teams WHERE name = ?').get(team);
  if (!teamRow) {
    errorResponse(res, 404, 'not_found', 'team not found');
    return;
  }

  const rows = db.prepare(`
    SELECT
      r.agent AS name,
      GROUP_CONCAT(DISTINCT r.agent_type) AS types,
      COALESCE((
        SELECT r2.project_path
        FROM registrations r2
        WHERE r2.team = r.team AND r2.agent = r.agent
        ORDER BY r2.rowid DESC
        LIMIT 1
      ), '?') AS project,
      COUNT(*) AS registrations
    FROM registrations r
    WHERE r.team = ?
    GROUP BY r.agent
    ORDER BY r.agent ASC
  `).all(team);

  jsonResponse(res, 200, { team, members: rows });
}

function requireRegisteredAgent(res, db, team, agent) {
  const row = db.prepare(`
    SELECT 1
    FROM registrations
    WHERE team = ? AND agent = ?
    LIMIT 1
  `).get(team, agent);
  if (row) {
    return true;
  }
  errorResponse(res, 404, 'not_found', 'team/agent registration not found');
  return false;
}

function handleGetRoleInstruction(url, res, db) {
  const team = url.searchParams.get('team') || '';
  const agent = url.searchParams.get('agent') || '';
  if (!team || !agent) {
    errorResponse(res, 400, 'missing_field', 'team and agent are required');
    return;
  }
  if (!requireRegisteredAgent(res, db, team, agent)) {
    return;
  }

  const row = db.prepare(`
    SELECT body, updated_at
    FROM role_instructions
    WHERE team = ? AND agent = ?
  `).get(team, agent);

  jsonResponse(res, 200, {
    team,
    agent,
    body: row?.body || '',
    updated_at: row?.updated_at || null,
  });
}

async function handleSetRoleInstruction(req, res, db) {
  const payload = await readJson(req);
  if (payload === null) {
    errorResponse(res, 400, 'invalid_json', 'request body is not valid JSON');
    return;
  }

  const team = payload.team || '';
  const agent = payload.agent || '';
  const body = payload.body;
  if (!team || !agent || typeof body !== 'string') {
    errorResponse(res, 400, 'missing_field', 'team, agent, and string body are required');
    return;
  }
  if (!requireRegisteredAgent(res, db, team, agent)) {
    return;
  }

  const row = db.prepare(`
    INSERT INTO role_instructions (team, agent, body, updated_at)
    VALUES (?, ?, ?, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
    ON CONFLICT(team, agent) DO UPDATE SET
      body = excluded.body,
      updated_at = excluded.updated_at
    RETURNING team, agent, body, updated_at
  `).get(team, agent, body);

  jsonResponse(res, 200, row);
}

function handleIdentities(url, res, db) {
  const project = url.searchParams.get('project') || '';
  const agentType = url.searchParams.get('type') || '';
  if (!project || !agentType) {
    errorResponse(res, 400, 'missing_field', 'project and type are required');
    return;
  }

  const teams = db.prepare('SELECT name FROM teams ORDER BY name ASC').all().map((row) => row.name);
  const exact = db.prepare(`
    SELECT team, agent
    FROM registrations
    WHERE project_path = ? AND agent_type = ?
    ORDER BY team ASC, agent ASC
  `).all(project, agentType);
  const suggested = db.prepare(`
    SELECT DISTINCT team, agent
    FROM registrations
    WHERE agent_type = ? AND NOT (project_path = ?)
    ORDER BY team ASC, agent ASC
  `).all(agentType, project);

  jsonResponse(res, 200, { exact, suggested, teams });
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
