#!/usr/bin/env node
import { createServer } from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const API_VERSION = 'v1';
const SERVER_VERSION = '0.2.0';
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
      width: min(1280px, 100%);
      margin: 0 auto;
      padding: 16px 20px 28px;
    }
    section {
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
    button.danger {
      border-color: var(--danger);
      color: var(--danger);
    }
    a {
      color: var(--accent);
      text-decoration: none;
    }
    .nav {
      display: flex;
      align-items: center;
      gap: 12px;
      font-size: 13px;
    }
    .hidden { display: none !important; }
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
    .topbar {
      display: grid;
      grid-template-columns: minmax(260px, 1fr) minmax(180px, 260px) auto auto auto;
      align-items: end;
      gap: 10px;
    }
    .topbar label {
      min-width: 0;
    }
    .topbar input,
    .topbar select {
      height: 36px;
      padding: 6px 8px;
    }
    .topbar .status {
      align-self: center;
      white-space: nowrap;
    }
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
    .panel-header h2 {
      margin: 0;
    }
    .panel-header {
      display: flex;
      align-items: end;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 10px;
      flex-wrap: wrap;
    }
    .history-controls {
      display: flex;
      align-items: end;
      justify-content: flex-end;
      gap: 8px;
      flex-wrap: wrap;
    }
    .history-controls label {
      min-width: 104px;
    }
    .history-controls select {
      width: auto;
      height: 36px;
      padding: 6px 8px;
    }
    .history-controls button {
      height: 36px;
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
    .client-list {
      display: grid;
      gap: 4px;
      min-width: 260px;
    }
    .client-line {
      display: grid;
      gap: 1px;
    }
    .client-meta {
      color: var(--muted);
      font-size: 12px;
      overflow-wrap: anywhere;
    }
    @media (max-width: 760px) {
      main { padding: 12px; }
      .topbar { grid-template-columns: 1fr; }
      .row { grid-template-columns: 1fr; }
      .panel-header { align-items: stretch; }
      .history-controls { justify-content: flex-start; }
    }
  </style>
</head>
<body>
  <header>
    <h1>agmsgd</h1>
    <nav class="nav">
      <a href="/">Projects</a>
      <a href="/all">All</a>
      <a href="/archive">Archive</a>
    </nav>
  </header>
  <main class="stack">
    <div class="panel topbar">
      <label>Project
        <select id="project"></select>
      </label>
      <label>Bearer token
        <input id="token" type="password" autocomplete="off">
      </label>
      <span id="health" class="status">Checking...</span>
      <button id="refresh" type="button">Refresh</button>
      <button id="archive-project" class="danger" type="button">Archive</button>
    </div>
    <section id="archive-view" class="panel hidden">
      <h2>Archive</h2>
      <div id="archive-list" class="empty"></div>
    </section>
    <section id="workspace-view" class="stack">
      <div class="panel" id="history-panel">
        <div class="panel-header">
          <h2>History</h2>
          <div class="history-controls">
            <label>Per page
              <select id="history-limit">
                <option value="20">20</option>
                <option value="50">50</option>
                <option value="100">100</option>
              </select>
            </label>
            <button id="history-prev" type="button">Prev</button>
            <span id="history-page" class="status">0-0 of 0</span>
            <button id="history-next" type="button">Next</button>
          </div>
        </div>
        <div id="messages" class="messages"></div>
      </div>
      <div class="panel" id="send-panel">
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
      <div class="panel" id="members-panel">
        <h2>Actas</h2>
        <div id="members" class="empty"></div>
      </div>
      <div class="panel" id="instruction-panel">
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
    </section>
  </main>
  <script>
    const state = {
      projects: [],
      members: [],
      selectedProject: null,
      selectedAgent: "",
      historyLimit: 20,
      historyOffset: 0,
      historyTotal: 0,
    };
    const els = {
      health: document.querySelector("#health"),
      refresh: document.querySelector("#refresh"),
      token: document.querySelector("#token"),
      project: document.querySelector("#project"),
      members: document.querySelector("#members"),
      instructionForm: document.querySelector("#instruction-form"),
      instructionTarget: document.querySelector("#instruction-target"),
      instruction: document.querySelector("#instruction"),
      instructionStatus: document.querySelector("#instruction-status"),
      messages: document.querySelector("#messages"),
      historyLimit: document.querySelector("#history-limit"),
      historyPrev: document.querySelector("#history-prev"),
      historyNext: document.querySelector("#history-next"),
      historyPage: document.querySelector("#history-page"),
      form: document.querySelector("#send-form"),
      from: document.querySelector("#from"),
      to: document.querySelector("#to"),
      body: document.querySelector("#body"),
      sendStatus: document.querySelector("#send-status"),
      archiveProject: document.querySelector("#archive-project"),
      archiveView: document.querySelector("#archive-view"),
      archiveList: document.querySelector("#archive-list"),
      workspaceView: document.querySelector("#workspace-view"),
      sendPanel: document.querySelector("#send-panel"),
      membersPanel: document.querySelector("#members-panel"),
      instructionPanel: document.querySelector("#instruction-panel"),
    };
    const archiveMode = location.pathname === "/archive";
    const allMode = location.pathname === "/all";

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

    function selectedTeam() {
      return state.selectedProject?.team || "";
    }

    function projectIdentity(project) {
      return project ? project.team + "\\t" + project.project_id : "";
    }

    function basename(value) {
      const clean = String(value || "").replace(/[/#]+$/, "");
      const parts = clean.split(/[/:]+/).filter(Boolean);
      return parts[parts.length - 1] || clean || "project";
    }

    function projectLabel(project) {
      if (!project) return "No project";
      const key = project.project_key || "";
      const name = key.startsWith("git:") ? basename(key.slice(4)).replace(/\\.git$/, "") : basename(project.project_path);
      const clients = project.clients ? " · " + project.clients : "";
      return name + " · " + project.team + " · " + project.roles + " actas" + clients;
    }

    function messageProjectLabel(message) {
      if (!message.project_id) return "Unassigned";
      const project = state.projects.find((candidate) => candidate.team === message.team && candidate.project_id === message.project_id);
      if (project) return projectLabel(project);
      const key = message.project_key || "";
      if (key.startsWith("git:")) return basename(key.slice(4)).replace(/\\.git$/, "");
      return basename(message.project_path || message.project_id);
    }

    function matchesSelectedProject(client) {
      if (!state.selectedProject) return false;
      const identity = client.project_key || client.project || "";
      return identity === state.selectedProject.project_id;
    }

    function latestProject(member) {
      const clients = member.clients || [];
      if (clients.length > 0) return clients[clients.length - 1].project || member.project || "";
      return member.project || "";
    }

    function renderClientsCell(td, member) {
      const clients = member.clients || [];
      if (clients.length === 0) {
        td.textContent = escapeText(member.registrations || 0);
        return;
      }
      const list = document.createElement("div");
      list.className = "client-list";
      for (const client of clients) {
        const line = document.createElement("div");
        line.className = "client-line";
        const head = document.createElement("div");
        head.textContent = [client.type, client.client_label || client.hostname || client.client_id].filter(Boolean).join(" / ");
        const meta = document.createElement("div");
        meta.className = "client-meta";
        meta.textContent = client.project || "";
        line.append(head, meta);
        list.append(line);
      }
      td.append(list);
    }

    async function loadHealth() {
      try {
        const health = await api("/api/v1/health");
        setHealth("OK " + health.server_version, "ok");
      } catch (error) {
        setHealth(error.message, "error");
      }
    }

    function renderHistoryPager() {
      const total = state.historyTotal;
      const start = total === 0 ? 0 : state.historyOffset + 1;
      const end = Math.min(state.historyOffset + state.historyLimit, total);
      els.historyPage.textContent = start + "-" + end + " of " + total;
      els.historyPrev.disabled = state.historyOffset <= 0;
      els.historyNext.disabled = state.historyOffset + state.historyLimit >= total;
      els.historyLimit.value = String(state.historyLimit);
    }

    function resetHistoryPage() {
      state.historyOffset = 0;
      state.historyTotal = 0;
      renderHistoryPager();
    }

    async function loadProjects(archived = false) {
      const previous = projectIdentity(state.selectedProject);
      const data = await api("/api/v1/projects" + (archived ? "?archived=1" : ""));
      state.projects = data.projects || [];
      state.selectedProject = allMode ? null : state.projects.find((project) => projectIdentity(project) === previous) || state.projects[0] || null;
      renderProjects();
    }

    function renderProjects() {
      els.project.replaceChildren();
      els.archiveProject.disabled = archiveMode || !state.selectedProject;
      if (allMode) {
        const option = document.createElement("option");
        option.value = "__all__";
        option.textContent = "All projects";
        option.selected = true;
        els.project.append(option);
        els.project.disabled = true;
        return;
      }
      if (state.projects.length === 0) {
        const option = document.createElement("option");
        option.value = "";
        option.textContent = archiveMode ? "No archived projects" : "No projects";
        els.project.append(option);
        els.project.disabled = true;
        return;
      }
      els.project.disabled = false;
      for (const project of state.projects) {
        const option = document.createElement("option");
        option.value = projectIdentity(project);
        option.textContent = projectLabel(project);
        option.selected = projectIdentity(project) === projectIdentity(state.selectedProject);
        els.project.append(option);
      }
    }

    async function setProjectArchived(project, archived) {
      await api("/api/v1/projects/archive", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          team: project.team,
          project_id: project.project_id,
          archived,
        }),
      });
    }

    function renderArchive() {
      if (state.projects.length === 0) {
        els.archiveList.className = "empty";
        els.archiveList.textContent = "No archived projects";
        return;
      }
      const table = document.createElement("table");
      table.innerHTML = "<thead><tr><th>Project</th><th>Team</th><th>Roles</th><th>Clients</th><th>Archived</th><th></th></tr></thead><tbody></tbody>";
      for (const project of state.projects) {
        const tr = document.createElement("tr");
        for (const value of [projectLabel(project), project.team, project.roles, project.clients || "", project.archived_at || ""]) {
          const td = document.createElement("td");
          td.textContent = escapeText(value);
          tr.append(td);
        }
        const action = document.createElement("td");
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = "Restore";
        button.addEventListener("click", async () => {
          await setProjectArchived(project, false);
          await refreshAll();
        });
        action.append(button);
        tr.append(action);
        table.querySelector("tbody").append(tr);
      }
      els.archiveList.className = "";
      els.archiveList.replaceChildren(table);
    }

    async function loadMembers() {
      const team = selectedTeam();
      if (!team) {
        els.members.className = "empty";
        els.members.textContent = "No actas";
        state.members = [];
        state.selectedAgent = "";
        renderInstructionEmpty();
        return;
      }
      const data = await api("/api/v1/teams/members?team=" + encodeURIComponent(team));
      const members = (data.members || [])
        .map((member) => ({ ...member, clients: (member.clients || []).filter(matchesSelectedProject) }))
        .filter((member) => member.clients.length > 0);
      state.members = members;
      if (members.length === 0) {
        els.members.className = "empty";
        els.members.textContent = "No actas";
        state.selectedAgent = "";
        renderInstructionEmpty();
        return;
      }
      if (!members.some((member) => member.name === state.selectedAgent)) {
        state.selectedAgent = members[0].name;
      }
      const table = document.createElement("table");
      table.innerHTML = "<thead><tr><th>Name</th><th>Types</th><th>Latest Project</th><th>Clients</th><th></th></tr></thead><tbody></tbody>";
      for (const member of members) {
        const tr = document.createElement("tr");
        if (member.name === state.selectedAgent) {
          tr.className = "selected-row";
        }
        for (const value of [member.name, member.types, latestProject(member)]) {
          const td = document.createElement("td");
          td.textContent = escapeText(value);
          tr.append(td);
        }
        const clients = document.createElement("td");
        renderClientsCell(clients, member);
        tr.append(clients);
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
      const team = selectedTeam();
      if (!team || !state.selectedAgent) {
        renderInstructionEmpty();
        return;
      }
      els.instructionTarget.textContent = team + " / " + state.selectedAgent;
      els.instructionStatus.textContent = "";
      const data = await api(
        "/api/v1/role-instructions?team=" + encodeURIComponent(team) +
        "&agent=" + encodeURIComponent(state.selectedAgent)
      );
      els.instruction.value = data.body || "";
    }

    async function loadHistory() {
      els.messages.replaceChildren();
      const team = selectedTeam();
      if (!allMode && !team) {
        state.historyTotal = 0;
        renderHistoryPager();
        const empty = document.createElement("div");
        empty.className = "empty";
        empty.textContent = "No messages";
        els.messages.append(empty);
        return;
      }
      const params = new URLSearchParams();
      params.set("limit", String(state.historyLimit));
      params.set("offset", String(state.historyOffset));
      if (!allMode) {
        params.set("team", team);
        if (state.selectedProject?.project_id) {
          params.set("project_id", state.selectedProject.project_id);
        }
      }
      const data = await api("/api/v1/messages/history?" + params.toString());
      const messages = data.messages || [];
      state.historyLimit = data.limit || state.historyLimit;
      state.historyOffset = data.offset || 0;
      state.historyTotal = data.total || 0;
      renderHistoryPager();
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
        route.textContent = allMode
          ? messageProjectLabel(message) + " · " + message.team + " · " + message.from_agent + " -> " + message.to_agent
          : message.from_agent + " -> " + message.to_agent;
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
        els.archiveView.classList.toggle("hidden", !archiveMode);
        els.workspaceView.classList.toggle("hidden", archiveMode);
        els.archiveProject.classList.toggle("hidden", archiveMode || allMode);
        els.sendPanel.classList.toggle("hidden", allMode);
        els.membersPanel.classList.toggle("hidden", allMode);
        els.instructionPanel.classList.toggle("hidden", allMode);
        await loadProjects(archiveMode);
        if (archiveMode) {
          renderArchive();
        } else if (allMode) {
          await loadHistory();
        } else {
          await refreshSelected();
        }
      } catch (error) {
        setHealth(error.message, "error");
      }
    }

    els.refresh.addEventListener("click", refreshAll);
    els.token.addEventListener("change", refreshAll);
    els.archiveProject.addEventListener("click", async () => {
      if (!state.selectedProject) return;
      if (!confirm("Archive this project registration group?")) return;
      try {
        await setProjectArchived(state.selectedProject, true);
        await refreshAll();
      } catch (error) {
        setHealth(error.message, "error");
      }
    });
    els.project.addEventListener("change", async () => {
      state.selectedProject = state.projects.find((project) => projectIdentity(project) === els.project.value) || null;
      state.selectedAgent = "";
      resetHistoryPage();
      await refreshSelected();
    });
    els.historyLimit.addEventListener("change", async () => {
      state.historyLimit = Number.parseInt(els.historyLimit.value, 10) || 20;
      resetHistoryPage();
      await loadHistory();
    });
    els.historyPrev.addEventListener("click", async () => {
      state.historyOffset = Math.max(0, state.historyOffset - state.historyLimit);
      await loadHistory();
    });
    els.historyNext.addEventListener("click", async () => {
      if (state.historyOffset + state.historyLimit >= state.historyTotal) return;
      state.historyOffset += state.historyLimit;
      await loadHistory();
    });
    els.instructionForm.addEventListener("submit", async (event) => {
      event.preventDefault();
      const team = selectedTeam();
      if (!team || !state.selectedAgent) return;
      els.instructionStatus.textContent = "";
      try {
        await api("/api/v1/role-instructions", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            team,
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
      const team = selectedTeam();
      if (!team) return;
      els.sendStatus.textContent = "";
      try {
        await api("/api/v1/messages", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            team,
            from_agent: els.from.value.trim(),
            to_agent: els.to.value.trim(),
            body: els.body.value,
            project_id: state.selectedProject?.project_id || null,
            project_key: state.selectedProject?.project_key || null,
            project_path: state.selectedProject?.project_path || null,
          }),
        });
        els.body.value = "";
        els.sendStatus.textContent = "Sent";
        resetHistoryPage();
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
      project_id TEXT,
      project_key TEXT,
      project_path TEXT,
      from_client_id TEXT,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
      read_at TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_unread
      ON messages(team, to_agent, read_at)
      WHERE read_at IS NULL;
    CREATE INDEX IF NOT EXISTS idx_history
      ON messages(team, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_messages_project
      ON messages(team, project_id, created_at DESC);

    CREATE TABLE IF NOT EXISTS message_reads (
      message_id INTEGER NOT NULL,
      team TEXT NOT NULL,
      agent TEXT NOT NULL,
      client_id TEXT NOT NULL,
      read_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
      PRIMARY KEY (message_id, client_id),
      FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_message_reads_inbox
      ON message_reads(team, agent, client_id, message_id);

    CREATE TABLE IF NOT EXISTS teams (
      name TEXT PRIMARY KEY,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
    );

    CREATE TABLE IF NOT EXISTS role_instructions (
      team TEXT NOT NULL,
      agent TEXT NOT NULL,
      body TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
      PRIMARY KEY (team, agent),
      FOREIGN KEY (team) REFERENCES teams(name) ON DELETE CASCADE
    );
  `);
  ensureMessagesProjectColumns(db);
  ensureRegistrationsTable(db);
  return db;
}

function ensureMessagesProjectColumns(db) {
  const columns = db.prepare('PRAGMA table_info(messages)').all().map((row) => row.name);
  const addColumn = (name, type) => {
    if (!columns.includes(name)) {
      db.exec(`ALTER TABLE messages ADD COLUMN ${name} ${type}`);
    }
  };
  addColumn('project_id', 'TEXT');
  addColumn('project_key', 'TEXT');
  addColumn('project_path', 'TEXT');
  addColumn('from_client_id', 'TEXT');
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_messages_project
      ON messages(team, project_id, created_at DESC);
  `);
}

function createRegistrationsTable(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS registrations (
      team TEXT NOT NULL,
      agent TEXT NOT NULL,
      agent_type TEXT NOT NULL,
      project_path TEXT NOT NULL,
      client_id TEXT NOT NULL,
      client_label TEXT NOT NULL DEFAULT '',
      hostname TEXT,
      project_key TEXT,
      archived_at TEXT,
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
      PRIMARY KEY (team, agent, agent_type, client_id, project_path),
      FOREIGN KEY (team) REFERENCES teams(name) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_registrations_project
      ON registrations(client_id, project_path, agent_type);
    CREATE INDEX IF NOT EXISTS idx_registrations_team_agent
      ON registrations(team, agent);
    CREATE INDEX IF NOT EXISTS idx_registrations_project_key
      ON registrations(project_key);
    CREATE INDEX IF NOT EXISTS idx_registrations_archived
      ON registrations(archived_at);
  `);
}

function ensureRegistrationsTable(db) {
  const columns = db.prepare('PRAGMA table_info(registrations)').all().map((row) => row.name);
  if (columns.length === 0) {
    createRegistrationsTable(db);
    return;
  }

  const hasClientId = columns.includes('client_id');
  if (hasClientId) {
    if (!columns.includes('client_label')) {
      db.exec("ALTER TABLE registrations ADD COLUMN client_label TEXT NOT NULL DEFAULT ''");
    }
    if (!columns.includes('hostname')) {
      db.exec('ALTER TABLE registrations ADD COLUMN hostname TEXT');
    }
    if (!columns.includes('project_key')) {
      db.exec('ALTER TABLE registrations ADD COLUMN project_key TEXT');
    }
    if (!columns.includes('archived_at')) {
      db.exec('ALTER TABLE registrations ADD COLUMN archived_at TEXT');
    }
    db.exec(`
      CREATE INDEX IF NOT EXISTS idx_registrations_project
        ON registrations(client_id, project_path, agent_type);
      CREATE INDEX IF NOT EXISTS idx_registrations_team_agent
        ON registrations(team, agent);
      CREATE INDEX IF NOT EXISTS idx_registrations_project_key
        ON registrations(project_key);
      CREATE INDEX IF NOT EXISTS idx_registrations_archived
        ON registrations(archived_at);
    `);
    return;
  }

  const legacyRows = db.prepare('SELECT * FROM registrations').all();
  db.exec('DROP TABLE registrations');
  createRegistrationsTable(db);
  const insert = db.prepare(`
    INSERT OR IGNORE INTO registrations
      (team, agent, agent_type, project_path, client_id, client_label, hostname, project_key, archived_at, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  for (const row of legacyRows) {
    insert.run(
      row.team,
      row.agent,
      row.agent_type,
      row.project_path,
      'legacy',
      'legacy',
      null,
      null,
      null,
      row.created_at || new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
    );
  }
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
    project_id: row.project_id || null,
    project_key: row.project_key || null,
    project_path: row.project_path || null,
    from_client_id: row.from_client_id || null,
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

function offsetParam(value) {
  const parsed = Number.parseInt(value || '', 10);
  if (!Number.isFinite(parsed)) {
    return 0;
  }
  return Math.max(0, parsed);
}

function createHandler({ db, token, verbose }) {
  return async function handler(req, res) {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (verbose) {
      console.error(`${req.method} ${url.pathname}`);
    }

    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html' || url.pathname === '/all' || url.pathname === '/archive')) {
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
    if (req.method === 'POST' && url.pathname === '/api/v1/teams/reset') {
      await handleReset(req, res, db);
      return;
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/teams') {
      handleTeams(res, db);
      return;
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/projects') {
      handleProjects(url, res, db);
      return;
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/projects/archive') {
      await handleProjectArchive(req, res, db);
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

  const projectId = payload.project_id || payload.project_key || null;
  const projectKey = payload.project_key || null;
  const projectPath = payload.project_path || null;
  const fromClientId = payload.from_client_id || null;

  const row = db.prepare(`
    INSERT INTO messages (team, from_agent, to_agent, body, project_id, project_key, project_path, from_client_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    RETURNING id, created_at
  `).get(payload.team, payload.from_agent, payload.to_agent, payload.body, projectId, projectKey, projectPath, fromClientId);

  jsonResponse(res, 201, row);
}

function handleUnread(url, res, db) {
  const team = url.searchParams.get('team') || '';
  const agent = url.searchParams.get('agent') || '';
  const clientId = url.searchParams.get('client_id') || '';
  const projectId = url.searchParams.get('project_id') || '';
  const limit = intParam(url.searchParams.get('limit'), 100);
  if (!team || !agent || !clientId) {
    errorResponse(res, 400, 'missing_field', 'team, agent, and client_id are required');
    return;
  }

  const projectClause = projectId ? 'AND m.project_id = ?' : '';
  const params = projectId
    ? [clientId, team, agent, projectId, limit]
    : [clientId, team, agent, limit];
  const rows = db.prepare(`
    SELECT m.id, m.team, m.from_agent, m.to_agent, m.body, m.created_at, mr.read_at
         , m.project_id, m.project_key, m.project_path, m.from_client_id
    FROM messages m
    LEFT JOIN message_reads mr
      ON mr.message_id = m.id
     AND mr.client_id = ?
    WHERE m.team = ? AND m.to_agent = ? ${projectClause} AND mr.message_id IS NULL
    ORDER BY m.created_at ASC, m.id ASC
    LIMIT ?
  `).all(...params);

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
  const clientId = payload.client_id || '';
  if (!team || !agent || !clientId) {
    errorResponse(res, 400, 'missing_field', 'team, agent, and client_id are required');
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
      INSERT OR IGNORE INTO message_reads (message_id, team, agent, client_id)
      SELECT id, team, to_agent, ?
      FROM messages
      WHERE team = ? AND to_agent = ?
        AND id IN (${placeholders})
    `).run(clientId, team, agent, ...ids);
    db.prepare(`
      UPDATE messages
      SET read_at = COALESCE(read_at, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
      WHERE team = ? AND to_agent = ? AND id IN (${placeholders})
    `).run(team, agent, ...ids);
  } else {
    result = db.prepare(`
      INSERT OR IGNORE INTO message_reads (message_id, team, agent, client_id)
      SELECT id, team, to_agent, ?
      FROM messages
      WHERE team = ? AND to_agent = ?
        AND NOT EXISTS (
          SELECT 1
          FROM message_reads mr
          WHERE mr.message_id = messages.id
            AND mr.client_id = ?
        )
    `).run(clientId, team, agent, clientId);
    db.prepare(`
      UPDATE messages
      SET read_at = COALESCE(read_at, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
      WHERE team = ? AND to_agent = ? AND read_at IS NULL
    `).run(team, agent);
  }

  jsonResponse(res, 200, { updated: result.changes });
}

function handleHistory(url, res, db) {
  const team = url.searchParams.get('team') || '';
  const agent = url.searchParams.get('agent') || '';
  const clientId = url.searchParams.get('client_id') || '';
  const projectId = url.searchParams.get('project_id') || '';
  const limit = intParam(url.searchParams.get('limit'), 20);
  const offset = offsetParam(url.searchParams.get('offset'));

  const conditions = [];
  const params = [];
  if (team) {
    conditions.push('m.team = ?');
    params.push(team);
  }
  if (agent) {
    conditions.push('(m.from_agent = ? OR m.to_agent = ?)');
    params.push(agent, agent);
  }
  if (projectId) {
    conditions.push('m.project_id = ?');
    params.push(projectId);
  }
  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
  const total = db.prepare(`
    SELECT COUNT(*) AS total
    FROM messages m
    ${where}
  `).get(...params).total;
  const effectiveOffset = total > 0
    ? Math.min(offset, Math.floor((total - 1) / limit) * limit)
    : 0;

  const rows = clientId
    ? db.prepare(`
        SELECT m.id, m.team, m.from_agent, m.to_agent, m.body, m.created_at, mr.read_at,
               m.project_id, m.project_key, m.project_path, m.from_client_id
        FROM messages m
        LEFT JOIN message_reads mr
          ON mr.message_id = m.id
         AND mr.client_id = ?
        ${where}
        ORDER BY m.created_at DESC, m.id DESC
        LIMIT ? OFFSET ?
      `).all(clientId, ...params, limit, effectiveOffset)
    : db.prepare(`
        SELECT m.id, m.team, m.from_agent, m.to_agent, m.body, m.created_at, m.read_at,
               m.project_id, m.project_key, m.project_path, m.from_client_id
        FROM messages m
        ${where}
        ORDER BY m.created_at DESC, m.id DESC
        LIMIT ? OFFSET ?
      `).all(...params, limit, effectiveOffset);

  jsonResponse(res, 200, {
    messages: rows.reverse().map(messageRow),
    total,
    limit,
    offset: effectiveOffset,
    has_prev: effectiveOffset > 0,
    has_next: effectiveOffset + limit < total,
  });
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
  const clientId = payload.client_id || '';
  const clientLabel = payload.client_label || clientId;
  const hostname = payload.hostname || null;
  const projectKey = payload.project_key || null;
  if (!team || !agent || !agentType || !project || !clientId) {
    errorResponse(res, 400, 'missing_field', 'team, agent, type, project, and client_id are required');
    return;
  }

  const existingTeam = db.prepare('SELECT name FROM teams WHERE name = ?').get(team);
  db.prepare('INSERT OR IGNORE INTO teams (name) VALUES (?)').run(team);
  db.prepare(`
    INSERT INTO registrations
      (team, agent, agent_type, project_path, client_id, client_label, hostname, project_key)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(team, agent, agent_type, client_id, project_path) DO UPDATE SET
      client_label = excluded.client_label,
      hostname = excluded.hostname,
      project_key = excluded.project_key,
      archived_at = NULL
  `).run(team, agent, agentType, project, clientId, clientLabel, hostname, projectKey);

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
    LEFT JOIN registrations ON registrations.team = teams.name AND registrations.archived_at IS NULL
    GROUP BY teams.name
    ORDER BY teams.name ASC
  `).all();

  jsonResponse(res, 200, { teams: rows });
}

function projectIdSql(alias = '') {
  const prefix = alias ? `${alias}.` : '';
  return `COALESCE(NULLIF(${prefix}project_key, ''), ${prefix}project_path)`;
}

function archivedParam(url) {
  const value = (url.searchParams.get('archived') || '').toLowerCase();
  return value === '1' || value === 'true' || value === 'yes';
}

function handleProjects(url, res, db) {
  const archived = archivedParam(url);
  const archiveWhere = archived ? 'r.archived_at IS NOT NULL' : 'r.archived_at IS NULL';
  const projectId = projectIdSql('r');
  const projectIdR2 = projectIdSql('r2');
  const rows = db.prepare(`
    SELECT
      r.team AS team,
      ${projectId} AS project_id,
      COALESCE(r.project_key, '') AS project_key,
      COALESCE((
        SELECT r2.project_path
        FROM registrations r2
        WHERE r2.team = r.team
          AND ${projectIdR2} = ${projectId}
          AND r2.archived_at ${archived ? 'IS NOT NULL' : 'IS NULL'}
        ORDER BY r2.rowid DESC
        LIMIT 1
      ), '') AS project_path,
      COUNT(DISTINCT r.agent) AS roles,
      COUNT(*) AS registrations,
      GROUP_CONCAT(DISTINCT r.client_label) AS clients,
      MAX(r.archived_at) AS archived_at
    FROM registrations r
    WHERE ${archiveWhere}
    GROUP BY r.team, ${projectId}
    ORDER BY team ASC, project_path ASC
  `).all();

  jsonResponse(res, 200, { projects: rows });
}

async function handleProjectArchive(req, res, db) {
  const payload = await readJson(req);
  if (payload === null) {
    errorResponse(res, 400, 'invalid_json', 'request body is not valid JSON');
    return;
  }

  const team = payload.team || '';
  const projectId = payload.project_id || '';
  const archived = Boolean(payload.archived);
  if (!team || !projectId) {
    errorResponse(res, 400, 'missing_field', 'team and project_id are required');
    return;
  }

  const sqlProjectId = projectIdSql();
  const result = db.prepare(`
    UPDATE registrations
    SET archived_at = ${archived ? "strftime('%Y-%m-%dT%H:%M:%SZ', 'now')" : 'NULL'}
    WHERE team = ?
      AND ${sqlProjectId} = ?
      AND archived_at ${archived ? 'IS NULL' : 'IS NOT NULL'}
  `).run(team, projectId);

  jsonResponse(res, 200, { archived, updated: result.changes });
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
        WHERE r2.team = r.team AND r2.agent = r.agent AND r2.archived_at IS NULL
        ORDER BY r2.rowid DESC
        LIMIT 1
      ), '?') AS project,
      COALESCE((
        SELECT r2.client_label
        FROM registrations r2
        WHERE r2.team = r.team AND r2.agent = r.agent AND r2.archived_at IS NULL
        ORDER BY r2.rowid DESC
        LIMIT 1
      ), '?') AS client_label,
      COUNT(*) AS registrations
    FROM registrations r
    WHERE r.team = ? AND r.archived_at IS NULL
    GROUP BY r.agent
    ORDER BY r.agent ASC
  `).all(team);

  const registrationRows = db.prepare(`
    SELECT agent, agent_type, project_path, client_id, client_label, hostname, project_key, created_at
    FROM registrations
    WHERE team = ? AND archived_at IS NULL
    ORDER BY agent ASC, client_label ASC, project_path ASC
  `).all(team);
  const registrationsByAgent = new Map();
  for (const row of registrationRows) {
    if (!registrationsByAgent.has(row.agent)) {
      registrationsByAgent.set(row.agent, []);
    }
    registrationsByAgent.get(row.agent).push({
      type: row.agent_type,
      project: row.project_path,
      client_id: row.client_id,
      client_label: row.client_label,
      hostname: row.hostname,
      project_key: row.project_key,
      created_at: row.created_at,
    });
  }

  jsonResponse(res, 200, {
    team,
    members: rows.map((row) => ({
      ...row,
      clients: registrationsByAgent.get(row.name) || [],
    })),
  });
}

async function handleReset(req, res, db) {
  const payload = await readJson(req);
  if (payload === null) {
    errorResponse(res, 400, 'invalid_json', 'request body is not valid JSON');
    return;
  }

  const project = payload.project || payload.project_path || '';
  const agentType = payload.type || payload.agent_type || '';
  const clientId = payload.client_id || '';
  const agent = payload.agent || '';
  if (!project || !agentType || !clientId) {
    errorResponse(res, 400, 'missing_field', 'project, type, and client_id are required');
    return;
  }

  let touchedTeams;
  let result;
  if (agent) {
    touchedTeams = db.prepare(`
      SELECT COUNT(DISTINCT team) AS count
      FROM registrations
      WHERE project_path = ? AND agent_type = ? AND client_id = ? AND agent = ?
    `).get(project, agentType, clientId, agent).count;
    result = db.prepare(`
      DELETE FROM registrations
      WHERE project_path = ? AND agent_type = ? AND client_id = ? AND agent = ?
    `).run(project, agentType, clientId, agent);
  } else {
    touchedTeams = db.prepare(`
      SELECT COUNT(DISTINCT team) AS count
      FROM registrations
      WHERE project_path = ? AND agent_type = ? AND client_id = ?
    `).get(project, agentType, clientId).count;
    result = db.prepare(`
      DELETE FROM registrations
      WHERE project_path = ? AND agent_type = ? AND client_id = ?
    `).run(project, agentType, clientId);
  }

  const emptyTeams = db.prepare(`
    SELECT teams.name AS name
    FROM teams
    LEFT JOIN registrations ON registrations.team = teams.name
    GROUP BY teams.name
    HAVING COUNT(registrations.agent) = 0
  `).all();
  for (const row of emptyTeams) {
    db.prepare('DELETE FROM teams WHERE name = ?').run(row.name);
  }

  jsonResponse(res, 200, {
    removed: result.changes,
    touched_teams: touchedTeams,
  });
}

function requireRegisteredAgent(res, db, team, agent) {
  const row = db.prepare(`
    SELECT 1
    FROM registrations
    WHERE team = ? AND agent = ? AND archived_at IS NULL
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
  const clientId = url.searchParams.get('client_id') || '';
  if (!project || !agentType || !clientId) {
    errorResponse(res, 400, 'missing_field', 'project, type, and client_id are required');
    return;
  }

  const teams = db.prepare('SELECT name FROM teams ORDER BY name ASC').all().map((row) => row.name);
  const exact = db.prepare(`
    SELECT team, agent
    FROM registrations
    WHERE project_path = ? AND agent_type = ? AND client_id = ? AND archived_at IS NULL
    ORDER BY team ASC, agent ASC
  `).all(project, agentType, clientId);
  const archivedExact = db.prepare(`
    SELECT team, agent, archived_at
    FROM registrations
    WHERE project_path = ? AND agent_type = ? AND client_id = ? AND archived_at IS NOT NULL
    ORDER BY team ASC, agent ASC
  `).all(project, agentType, clientId);
  const suggested = db.prepare(`
    SELECT DISTINCT team, agent
    FROM registrations
    WHERE agent_type = ? AND client_id = ? AND NOT (project_path = ?) AND archived_at IS NULL
    ORDER BY team ASC, agent ASC
  `).all(agentType, clientId, project);

  jsonResponse(res, 200, { exact, archived_exact: archivedExact, suggested, teams });
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
