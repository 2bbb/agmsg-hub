#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { hostname, homedir } from 'node:os';

const SUPPORTED_AGENT_TYPES = new Set(['claude-code', 'codex', 'gemini', 'antigravity', 'copilot']);

function usage(status = 0) {
  const out = status === 0 ? console.log : console.error;
  out(`Usage:
  agmsg-client.mjs remote configure <url> [token]
  agmsg-client.mjs remote status
  agmsg-client.mjs remote switch remote|local
  agmsg-client.mjs join <team> <agent> <type> <project>
  agmsg-client.mjs whoami <project> [type]
  agmsg-client.mjs send <team> <from> <to> <message> [--project <path>]
  agmsg-client.mjs inbox <team> <agent> [--quiet] [--wait <seconds>] [--poll <seconds>] [--project <path>]
  agmsg-client.mjs history <team> [agent] [limit] [--project <path>]
  agmsg-client.mjs team <team>
  agmsg-client.mjs role-instructions get <team> <agent>
  agmsg-client.mjs role-instructions set <team> <agent> <text|--file path>
  agmsg-client.mjs reset <project> <type> [agent]
  agmsg-client.mjs identities <project> <type>`);
  process.exit(status);
}

function fail(message, status = 1) {
  console.error(message);
  process.exit(status);
}

function homeDir() {
  return process.env.AGMSG_HUB_HOME || join(homedir(), '.agmsg-hub');
}

function configFile() {
  return join(homeDir(), 'config.yaml');
}

function ensureHome() {
  mkdirSync(homeDir(), { recursive: true });
}

function parseConfig(text) {
  const config = {};
  let section = '';
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.replace(/[ \t]+#.*$/, '');
    if (!line.trim()) continue;
    const sectionMatch = /^([^ #][^:]*):\s*$/.exec(line);
    if (sectionMatch) {
      section = sectionMatch[1].trim();
      config[section] ||= {};
      continue;
    }
    const nestedMatch = /^  ([^:]+):\s*(.*)$/.exec(line);
    if (nestedMatch && section) {
      config[section] ||= {};
      config[section][nestedMatch[1].trim()] = unquoteConfigValue(nestedMatch[2].trim());
      continue;
    }
    const topMatch = /^([^:]+):\s*(.*)$/.exec(line);
    if (topMatch) {
      config[topMatch[1].trim()] = unquoteConfigValue(topMatch[2].trim());
    }
  }
  return config;
}

function unquoteConfigValue(value) {
  if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
    return value.slice(1, -1);
  }
  return value;
}

function readConfig() {
  const path = configFile();
  if (!existsSync(path)) return {};
  return parseConfig(readFileSync(path, 'utf8'));
}

function writeConfig(config) {
  ensureHome();
  const lines = [];
  const sections = Object.keys(config).filter((key) => typeof config[key] === 'object' && config[key] !== null);
  const scalars = Object.keys(config).filter((key) => !sections.includes(key));
  for (const key of scalars.sort()) {
    lines.push(`${key}: ${String(config[key] ?? '')}`);
  }
  for (const section of sections.sort()) {
    lines.push(`${section}:`);
    for (const key of Object.keys(config[section]).sort()) {
      lines.push(`  ${key}: ${String(config[section][key] ?? '')}`);
    }
  }
  writeFileSync(configFile(), `${lines.join('\n')}\n`);
}

function configGet(key, fallback = '') {
  const env = {
    'storage.active': process.env.AGMSG_STORAGE_DRIVER,
    'remote.url': process.env.AGMSG_REMOTE_URL,
    'remote.token': process.env.AGMSG_REMOTE_TOKEN,
  }[key];
  if (env) return key === 'remote.url' ? env.replace(/\/+$/, '') : env;

  const config = readConfig();
  if (key.includes('.')) {
    const [section, field] = key.split('.', 2);
    return config[section]?.[field] || fallback;
  }
  return config[key] || fallback;
}

function configSet(key, value) {
  const config = readConfig();
  if (key.includes('.')) {
    const [section, field] = key.split('.', 2);
    config[section] ||= {};
    config[section][field] = value;
  } else {
    config[key] = value;
  }
  writeConfig(config);
}

function storageDriver() {
  return configGet('storage.active', 'sqlite');
}

function remoteUrl() {
  return configGet('remote.url', '').replace(/\/+$/, '');
}

function remoteToken() {
  return configGet('remote.token', '');
}

function requireRemoteSelected() {
  if (storageDriver() !== 'remote') {
    fail('Windows/native Node client supports remote storage only. Run: agmsg-client.mjs remote configure <url> && agmsg-client.mjs remote switch remote');
  }
}

function requireRemoteUrl() {
  const url = remoteUrl();
  if (!url) {
    fail('remote.url is not configured. Run: agmsg-client.mjs remote configure <url>');
  }
  return url;
}

function hash(value) {
  return createHash('sha256').update(value).digest('hex');
}

function clientIdFile() {
  return join(homeDir(), 'client_id');
}

function clientId() {
  if (process.env.AGMSG_CLIENT_ID) return process.env.AGMSG_CLIENT_ID;
  const path = clientIdFile();
  if (!existsSync(path)) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, `${randomUUID()}\n`);
  }
  return readFileSync(path, 'utf8').split(/\r?\n/, 1)[0].trim();
}

function clientLabel() {
  return process.env.AGMSG_CLIENT_LABEL || shortHostname();
}

function shortHostname() {
  return hostname().split('.')[0] || 'unknown';
}

function realPath(path) {
  try {
    return realpathSync(path);
  } catch {
    return resolve(path);
  }
}

function gitOutput(args, cwd) {
  try {
    return execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
}

function normalizeProjectKey(value) {
  if (!value) return value;
  const text = String(value);
  if (!text.startsWith('git:')) return text;
  const remote = text.slice(4).replace(/[\\/]+$/, '').replace(/\.git$/i, '');
  return `git:${remote}`;
}

function projectKey(projectPath) {
  if (process.env.AGMSG_PROJECT_KEY) return normalizeProjectKey(process.env.AGMSG_PROJECT_KEY);
  const root = gitOutput(['rev-parse', '--show-toplevel'], projectPath);
  if (root) {
    const remote = gitOutput(['config', '--get', 'remote.origin.url'], root);
    if (remote) return normalizeProjectKey(`git:${remote}`);
    return `git-local:${hash(realPath(root))}`;
  }
  return `local:${clientId()}:${hash(realPath(projectPath))}`;
}

async function request(method, path, { query = {}, body = null } = {}) {
  const base = requireRemoteUrl();
  const url = new URL(`${base}${path}`);
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined && value !== null && value !== '') {
      url.searchParams.set(key, String(value));
    }
  }
  const headers = { Accept: 'application/json' };
  const token = remoteToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  const options = { method, headers };
  if (body !== null) {
    headers['Content-Type'] = 'application/json';
    options.body = JSON.stringify(body);
  }
  let response;
  try {
    response = await fetch(url, options);
  } catch (error) {
    fail(`Remote request failed: ${error.message}`);
  }
  const text = await response.text();
  let data = {};
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      fail(`Remote returned non-JSON response: ${text.slice(0, 200)}`);
    }
  }
  if (!response.ok) {
    fail(data.error?.message || response.statusText);
  }
  return data;
}

async function remoteHealthOk() {
  const base = requireRemoteUrl();
  const headers = { Accept: 'application/json' };
  const token = remoteToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  try {
    const response = await fetch(`${base}/api/v1/health`, { headers });
    return response.ok;
  } catch {
    return false;
  }
}

function parseOption(args, name) {
  const index = args.indexOf(name);
  if (index === -1) return '';
  const value = args[index + 1];
  if (!value) fail(`Missing value for ${name}`);
  args.splice(index, 2);
  return value;
}

function parsePositiveInt(value, fallback, label) {
  if (value === undefined || value === '') return fallback;
  const parsed = Number.parseInt(String(value), 10);
  if (!Number.isInteger(parsed) || parsed < 1) fail(`${label} must be a positive integer`);
  return parsed;
}

function parseNonNegativeInt(value, fallback, label) {
  if (value === undefined || value === '') return fallback;
  const parsed = Number.parseInt(String(value), 10);
  if (!Number.isInteger(parsed) || parsed < 0) fail(`${label} must be a non-negative integer`);
  return parsed;
}

function detectAgentType() {
  if (process.env.CLAUDE_CODE_SESSION_ID) return 'claude-code';
  if (process.env.CODEX_SANDBOX || process.env.CODEX_THREAD_ID) return 'codex';
  if (process.env.GOOGLE_GEMINI_CLI || process.env.GEMINI_API_KEY) return 'gemini';
  return 'codex';
}

function validateAgentType(type) {
  if (!SUPPORTED_AGENT_TYPES.has(type)) {
    fail(`Unknown agent type: '${type}' (supported: ${Array.from(SUPPORTED_AGENT_TYPES).join(', ')})`);
  }
}

function formatList(rows, field) {
  return Array.from(new Set(rows.map((row) => row[field]).filter(Boolean))).sort().join(',');
}

async function cmdRemote(args) {
  const action = args.shift() || 'status';
  if (action === 'configure') {
    const url = args[0];
    if (!url) fail('Usage: remote configure <url> [token]');
    configSet('remote.url', url.replace(/\/+$/, ''));
    if (args[1]) configSet('remote.token', args[1]);
    console.log(`Configured remote.url = ${url.replace(/\/+$/, '')}`);
    if (args[1]) console.log('Configured remote.token');
    return;
  }
  if (action === 'switch') {
    const target = args[0];
    if (target === 'remote') {
      requireRemoteUrl();
      if (!(await remoteHealthOk())) {
        fail('remote.health=fail');
      }
      configSet('storage.active', 'remote');
      console.log('Switched storage.active = remote');
      return;
    }
    if (target === 'local' || target === 'sqlite') {
      configSet('storage.active', 'sqlite');
      console.log('Switched storage.active = sqlite');
      return;
    }
    fail('Usage: remote switch remote|local');
  }
  if (action === 'status') {
    console.log(`storage.active=${storageDriver()}`);
    console.log(`remote.url=${remoteUrl()}`);
    if (!remoteUrl()) {
      console.log('remote.health=not_configured');
      return;
    }
    if (await remoteHealthOk()) {
      console.log('remote.health=ok');
    } else {
      console.log('remote.health=fail');
      process.exitCode = 1;
    }
    return;
  }
  usage(1);
}

async function cmdJoin(args) {
  requireRemoteSelected();
  const [team, agent, type, project] = args;
  if (!team || !agent || !type || !project) fail('Usage: join <team> <agent> <type> <project>');
  validateAgentType(type);
  const response = await request('POST', '/api/v1/teams/join', {
    body: {
      team,
      agent,
      type,
      project,
      client_id: clientId(),
      client_label: clientLabel(),
      hostname: hostname(),
      project_key: projectKey(project),
    },
  });
  if (response.created_team) console.log(`Created team: ${team}`);
  console.log(`Joined team ${team} as ${agent}`);
}

async function cmdWhoami(args) {
  requireRemoteSelected();
  const project = args[0];
  const type = args[1] || detectAgentType();
  if (!project) fail('Usage: whoami <project> [type]');
  validateAgentType(type);
  const data = await request('GET', '/api/v1/identities', {
    query: { project, type, client_id: clientId() },
  });
  const exact = data.exact || [];
  const archived = data.archived_exact || [];
  const suggested = data.suggested || [];
  const teams = (data.teams || []).join(',') || 'none';
  if (exact.length === 0 && archived.length > 0) {
    console.log(`archived=true agents=${formatList(archived, 'agent')} teams=${formatList(archived, 'team')} type=${type} project=${project} client=${clientId()} available_teams=${teams}`);
    return;
  }
  if (exact.length === 0 && suggested.length > 0) {
    console.log(`suggest=true agents=${formatList(suggested, 'agent')} teams=${formatList(suggested, 'team')} type=${type} project=${project} client=${clientId()} available_teams=${teams}`);
    return;
  }
  if (exact.length === 0) {
    console.log(`not_joined=true available_teams=${teams}`);
    return;
  }
  const agents = formatList(exact, 'agent');
  const teamNames = formatList(exact, 'team');
  if (agents.includes(',')) {
    console.log(`multiple=true agents=${agents} teams=${teamNames} type=${type} project=${project} client=${clientId()}`);
  } else {
    console.log(`agent=${agents} teams=${teamNames} type=${type} project=${project} client=${clientId()}`);
  }
}

async function cmdIdentities(args) {
  requireRemoteSelected();
  const [project, type] = args;
  if (!project || !type) fail('Usage: identities <project> <type>');
  const data = await request('GET', '/api/v1/identities', {
    query: { project, type, client_id: clientId() },
  });
  for (const row of data.exact || []) {
    console.log(`${row.team}\t${row.agent}`);
  }
}

async function cmdSend(args) {
  requireRemoteSelected();
  const projectPath = parseOption(args, '--project');
  const [team, fromAgent, toAgent, body] = args;
  if (!team || !fromAgent || !toAgent || body === undefined) fail('Usage: send <team> <from> <to> <message> [--project <path>]');
  const key = projectPath ? projectKey(projectPath) : null;
  await request('POST', '/api/v1/messages', {
    body: {
      team,
      from_agent: fromAgent,
      to_agent: toAgent,
      body,
      project_id: key,
      project_key: key,
      project_path: projectPath || null,
      from_client_id: clientId(),
    },
  });
  console.log(`Sent to ${toAgent} in team ${team}`);
}

async function fetchUnread(team, agent, projectPath) {
  return request('GET', '/api/v1/messages/unread', {
    query: {
      team,
      agent,
      limit: 100,
      client_id: clientId(),
      project_id: projectPath ? projectKey(projectPath) : '',
    },
  });
}

async function markRead(team, agent, ids) {
  if (ids.length === 0) return;
  await request('POST', '/api/v1/messages/read', {
    body: { team, agent, client_id: clientId(), ids },
  });
}

function sleep(ms) {
  return new Promise((resolveSleep) => setTimeout(resolveSleep, ms));
}

function formatLocalTimestamp(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value || '';
  return new Intl.DateTimeFormat(undefined, {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    timeZoneName: 'short',
  }).format(date);
}

async function cmdInbox(args) {
  requireRemoteSelected();
  const quiet = args.includes('--quiet');
  if (quiet) args.splice(args.indexOf('--quiet'), 1);
  const waitSeconds = parseNonNegativeInt(parseOption(args, '--wait') || '0', 0, '--wait');
  const pollSeconds = parsePositiveInt(parseOption(args, '--poll') || '2', 2, '--poll');
  const projectPath = parseOption(args, '--project');
  const [team, agent] = args;
  if (!team || !agent) fail('Usage: inbox <team> <agent> [--quiet] [--wait <seconds>] [--poll <seconds>] [--project <path>]');

  const deadline = Date.now() + waitSeconds * 1000;
  let announced = false;
  while (true) {
    const data = await fetchUnread(team, agent, projectPath);
    const messages = data.messages || [];
    if (messages.length > 0) {
      console.log(`${messages.length} new message(s):`);
      console.log('');
      for (const message of messages) {
        console.log(`  [${message.created_at}] ${message.from_agent}: ${message.body}`);
      }
      console.log('');
      await markRead(team, agent, messages.map((message) => message.id));
      return;
    }
    if (waitSeconds === 0 || Date.now() >= deadline) break;
    if (!quiet && !announced) {
      console.log(`Waiting up to ${waitSeconds}s for new messages...`);
      announced = true;
    }
    await sleep(pollSeconds * 1000);
  }
  if (quiet) return;
  if (waitSeconds > 0) {
    console.log(`No new messages after ${waitSeconds}s.`);
  } else {
    console.log('No new messages.');
  }
}

async function cmdHistory(args) {
  requireRemoteSelected();
  const projectPath = parseOption(args, '--project');
  const team = args.shift();
  if (!team) fail('Usage: history <team> [agent] [limit] [--project <path>]');
  let agent = '';
  let limit = 20;
  if (args.length > 0) agent = args.shift() || '';
  if (args.length > 0) limit = parsePositiveInt(args.shift(), 20, 'limit');
  if (args.length > 0) fail(`Unknown option: ${args[0]}`);
  const data = await request('GET', '/api/v1/messages/history', {
    query: {
      team,
      agent,
      limit,
      client_id: clientId(),
      project_id: projectPath ? projectKey(projectPath) : '',
    },
  });
  const messages = data.messages || [];
  if (messages.length === 0) {
    console.log('No message history.');
    return;
  }
  for (const message of messages) {
    console.log(`  ${message.read ? '○' : '●'} [${formatLocalTimestamp(message.created_at)}] ${message.from_agent} → ${message.to_agent}: ${message.body}`);
  }
}

async function cmdTeam(args) {
  requireRemoteSelected();
  const team = args[0];
  if (!team) fail('Usage: team <team>');
  const data = await request('GET', '/api/v1/teams/members', { query: { team } });
  const members = data.members || [];
  console.log(`Team: ${team}`);
  console.log('');
  for (const member of members) {
    const suffix = member.registrations > 1 ? ` (+${member.registrations - 1} more)` : '';
    console.log(`  ${member.name} (${member.types}) — ${member.client_label || '?'}: ${member.project || '?'}${suffix}`);
  }
  console.log('');
  console.log(`${members.length} member(s)`);
}

async function cmdRoleInstructions(args) {
  requireRemoteSelected();
  const action = args.shift();
  if (action === 'get') {
    const [team, agent] = args;
    if (!team || !agent) fail('Usage: role-instructions get <team> <agent>');
    const data = await request('GET', '/api/v1/role-instructions', { query: { team, agent } });
    process.stdout.write(data.body || '');
    if (data.body) process.stdout.write('\n');
    return;
  }
  if (action === 'set') {
    const [team, agent] = args;
    if (!team || !agent) fail('Usage: role-instructions set <team> <agent> <text|--file path>');
    let body;
    if (args[2] === '--file') {
      if (!args[3]) fail('Usage: role-instructions set <team> <agent> --file <path>');
      body = readFileSync(args[3], 'utf8');
    } else {
      body = args[2] || '';
    }
    await request('POST', '/api/v1/role-instructions', { body: { team, agent, body } });
    console.log(`Updated instruction for ${agent} in team ${team}`);
    return;
  }
  usage(1);
}

async function cmdReset(args) {
  requireRemoteSelected();
  const [project, type, agent = ''] = args;
  if (!project || !type) fail('Usage: reset <project> <type> [agent]');
  const data = await request('POST', '/api/v1/teams/reset', {
    body: { project, type, agent, client_id: clientId() },
  });
  if (!data.removed) {
    console.log('No registrations removed.');
  } else {
    console.log(`Reset complete: removed ${data.removed} registration(s) across ${data.touched_teams} team(s)`);
  }
}

async function main() {
  const args = process.argv.slice(2);
  const command = args.shift();
  if (!command || command === '-h' || command === '--help' || command === 'help') usage(0);
  switch (command) {
    case 'remote':
      await cmdRemote(args);
      break;
    case 'join':
      await cmdJoin(args);
      break;
    case 'whoami':
      await cmdWhoami(args);
      break;
    case 'identities':
      await cmdIdentities(args);
      break;
    case 'send':
      await cmdSend(args);
      break;
    case 'inbox':
      await cmdInbox(args);
      break;
    case 'history':
      await cmdHistory(args);
      break;
    case 'team':
      await cmdTeam(args);
      break;
    case 'role-instructions':
    case 'instructions':
      await cmdRoleInstructions(args);
      break;
    case 'reset':
      await cmdReset(args);
      break;
    default:
      fail(`Unknown command: ${command}`);
  }
}

main().catch((error) => fail(error.stack || error.message));
