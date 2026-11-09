#!/usr/bin/env node
/* DSH LIVE bridge —— 定时读取本机 DSH 数据，生成 live/live-data.js 供壁纸页面读取。
 * 只读文件，不调用任何模型，不联网。node live/bridge.mjs  （Ctrl+C 停止）
 */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import zlib from 'node:zlib';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const OUT_JS = path.join(HERE, 'live-data.js');
const DSH = path.join(os.homedir(), '.dsh');
const INTERVAL = Number(process.env.DSH_LIVE_INTERVAL || 5000);
const MAX_SESSIONS = 12;
const RUN_GAP_MS = 150_000;   // 最近一次活动在 150s 内有未收尾的 turn 视为「正在跑」
const LOOKBACK_MS = 36 * 3600_000;

const MAGIC = Buffer.from([0x28, 0xB5, 0x2F, 0xFD]);
const cache = new Map();      // file -> { key, st }
const log = (...a) => console.log(new Date().toLocaleTimeString('zh-CN'), ...a);

function readJSON(p) {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; }
}
function localDay(d = new Date()) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}
function textOf(msg) {
  if (!msg) return '';
  if (typeof msg === 'string') return msg;
  const c = msg.content;
  if (typeof c === 'string') return c;
  if (Array.isArray(c)) return c.filter((x) => x && x.type === 'text' && typeof x.text === 'string').map((x) => x.text).join(' ').trim();
  return '';
}
const squash = (s, n) => (s || '').replace(/\s+/g, ' ').trim().slice(0, n);

/* 工具调用的简短参数摘要：优先取第一个字符串入参（命令 / 路径 / 查询） */
function shortArg(raw) {
  if (!raw) return '';
  let a = raw;
  if (typeof a === 'string') { try { a = JSON.parse(a); } catch { return squash(a, 40); } }
  if (a && typeof a === 'object') {
    for (const k of ['command', 'query', 'path', 'file_path', 'url', 'description', 'pattern', 'prompt', 'name']) {
      if (typeof a[k] === 'string' && a[k].trim()) return squash(a[k], 40);
    }
    const first = Object.values(a).find((v) => typeof v === 'string' && v.trim());
    if (first) return squash(first, 40);
  }
  return '';
}
const VERB_OF = [
  [/^(read|grep|glob|web_|fetch|search|platform_|domain_|cache_search|research|list_|zotero_)/, '检索'],
  [/^(edit|write|create|generate|apply_|todo_|schedule_create)/, '生成'],
  [/^(check|verify|validate|cite_|test)/, '核验']
];
const verbOf = (name) => (VERB_OF.find(([re]) => re.test(name || '')) || [null, '执行'])[1];

/* ---------- 会话日志解析（zstd 多帧：按魔数切分，逐帧解压） ---------- */
function parseSession(file) {
  const st = { id: null, title: '', cwd: '', createdAt: 0, turns: 0, open: 0, lastTime: 0, lastTool: '', lastUser: '', tools: [] };
  let buf;
  try { buf = fs.readFileSync(file); } catch { return st; }
  const idx = [];
  let i = 0;
  while ((i = buf.indexOf(MAGIC, i)) !== -1) { idx.push(i); i += 4; }
  for (let k = 0; k < idx.length; k++) {
    const s = idx[k], e = k + 1 < idx.length ? idx[k + 1] : buf.length;
    let text;
    try { text = zlib.zstdDecompressSync(buf.subarray(s, e)).toString('utf8'); } catch { continue; }
    for (const line of text.split('\n')) {
      if (!line) continue;
      let ev;
      try { ev = JSON.parse(line); } catch { continue; }
      const d = ev.data || {};
      if (typeof ev.time === 'number' && ev.time > st.lastTime) st.lastTime = ev.time;
      switch (ev.type) {
        case 'session': st.id = ev.id; st.createdAt = ev.createdAt || 0; st.cwd = ev.cwd || ''; break;
        case 'session/title': if (d.title) st.title = d.title; break;
        case 'turn/start': st.turns++; st.open++; break;
        case 'turn/end': st.open = Math.max(0, st.open - 1); break;
        case 'tool/call': if (d.name) {
          st.lastTool = String(d.name); st.lastToolAt = ev.time;
          st.tools.push({ t: ev.time || 0, name: String(d.name), arg: shortArg(d.arguments) });
          if (st.tools.length > 80) st.tools.shift();
        } break;
        case 'user/message': { const t = squash(textOf(d.message), 90); if (t) st.lastUser = t; break; }
        default: break;
      }
    }
  }
  return st;
}
function sessionState(file) {
  let s;
  try { s = fs.statSync(file); } catch { return null; }
  const key = `${s.size}:${s.mtimeMs}`;
  const hit = cache.get(file);
  if (hit && hit.key === key) return hit.st;
  const st = parseSession(file);
  cache.set(file, { key, st });
  return st;
}
function collectSessions(todayIds) {
  const out = [];
  let roots = [];
  try { roots = fs.readdirSync(path.join(DSH, 'sessions')); } catch { return out; }
  const now = Date.now();
  for (const ws of roots) {
    const dir = path.join(DSH, 'sessions', ws);
    let names = [];
    try { names = fs.readdirSync(dir); } catch { continue; }
    for (const name of names) {
      if (!name.startsWith('session-')) continue;
      const file = path.join(dir, name, 'session.v4.jsonl.zstd');
      let s;
      try { s = fs.statSync(file); } catch { continue; }
      if (now - s.mtimeMs > LOOKBACK_MS && !todayIds.has(name)) continue;
      const st = sessionState(file);
      if (!st || !st.id) continue;
      out.push({ ...st, mtime: s.mtimeMs, file });
    }
  }
  return out;
}

/* ---------- 主循环 ---------- */
function build() {
  const day = localDay();
  const ledger = readJSON(path.join(DSH, 'storages', 'cost-meter', 'ledger.json')) || {};
  const usage = readJSON(path.join(DSH, '.dshw-usage.json')) || {};
  const cfg = ledger.config || {};
  const symbol = cfg.symbol || '¥';
  const days = ledger.days || {};
  const today = days[day] || {};
  const daySessions = Array.isArray(today.sessions) ? today.sessions : [];

  // 近 7 日
  const keys = Object.keys(days).sort().slice(-7);
  let weekCost = 0, weekTokens = 0, weekCalls = 0;
  for (const k of keys) {
    const d = days[k] || {};
    weekCost += d.costCny || 0;
    weekTokens += (d.input || 0) + (d.output || 0);
    weekCalls += d.calls || 0;
  }

  const todayIds = new Set(daySessions.map((s) => s.id));
  const raw = collectSessions(todayIds);
  const byId = new Map(raw.map((s) => [s.id, s]));
  const byCost = new Map(daySessions.map((s) => [s.id, s]));

  const now = Date.now();
  const sessions = [];
  for (const id of new Set([...byId.keys(), ...byCost.keys()])) {
    const st = byId.get(id) || {};
    const cost = byCost.get(id) || {};
    const lastTime = Math.max(st.lastTime || 0, cost.at || 0);
    if (now - lastTime > LOOKBACK_MS) continue;
    // 跳过空壳会话（没有花费、没有标题、没有 turn）
    if (!byCost.get(id) && !st.title && !st.turns) continue;
    const running = (st.open || 0) > 0 && now - (st.lastTime || 0) < RUN_GAP_MS;
    sessions.push({
      id,
      short: id.replace('session-', '').slice(0, 8),
      title: squash(st.title || st.lastUser || '(未命名会话)', 46),
      cwd: st.cwd || '',
      status: running ? 'running' : 'idle',
      turns: st.turns || 0,
      lastTool: st.lastTool || '',
      lastTime,
      tokens: (cost.input || 0) + (cost.output || 0),
      input: cost.input || 0,
      output: cost.output || 0,
      cacheRead: cost.cacheRead || 0,
      hit: (cost.input || 0) + (cost.cacheRead || 0) > 0 ? Math.min(1, (cost.cacheRead || 0) / ((cost.input || 0) + (cost.cacheRead || 0))) : 0,
      calls: cost.calls || 0,
      costCny: cost.costCny || 0,
      hasCost: !!byCost.get(id),
      tools: (st.tools || []).slice(-14).map((x) => `${x.name}${x.arg ? '(' + x.arg + ')' : '()'}`)
    });
  }
  sessions.sort((a, b) => (b.status === 'running') - (a.status === 'running') || b.lastTime - a.lastTime);

  /* 全局工具调用事件流（真实）：近 40 条，按时间升序 */
  const evs = [];
  for (const s of sessions) for (const t of ((byId.get(s.id) || {}).tools || [])) evs.push({ t: t.t, name: t.name, arg: t.arg, s });
  evs.sort((a, b) => a.t - b.t);
  const feed = evs.slice(-40).map((e, i) => ({
    seq: i + 1,
    time: e.t,
    verb: verbOf(e.name),
    text: squash(`${e.name}${e.arg ? ' ' + e.arg : ''}`, 52) + ' · ' + squash(e.s.title, 12)
  }));
  // 代码块的“真实行”：取工具名的第一个参数，只保留像表达式/路径的短 ASCII 片段，避免中文正文刷屏
  const bits = [...new Set(evs.slice(-320).map((e) => {
    const a = (e.arg || '').split(/[ (]/)[0];
    if (a && (!/^[\x20-\x7e]{1,44}$/.test(a))) return null;
    return e.name + '(' + a + ')';
  }).filter(Boolean))].slice(-24);
  const turns = sessions.reduce((a, s) => a + s.turns, 0);

  const payload = {
    ok: true,
    ts: now,
    day,
    symbol,
    balance: typeof usage.lastBalance === 'number' ? usage.lastBalance : null,
    todayCostBalance: typeof usage.todayUsage === 'number' ? usage.todayUsage : null,
    todayCostList: today.costCny != null ? today.costCny : null,
    today: {
      input: today.input || 0,
      output: today.output || 0,
      cacheRead: today.cacheRead || 0,
      calls: today.calls || 0,
      tokens: (today.input || 0) + (today.output || 0)
    },
    week: { costCny: weekCost, tokens: weekTokens, calls: weekCalls, days: keys.length },
    turns,
    feed,
    bits,
    active: sessions.filter((s) => s.status === 'running').length,
    sessions: sessions.slice(0, MAX_SESSIONS),
    totalSessions: sessions.length,
    model: firstModel(today),
    appMtime: appMtime()
  };
  return payload;
}
function appMtime() {
  try { return Math.round(fs.statSync(path.join(ROOT, 'index.html')).mtimeMs); } catch { return 0; }
}
function firstModel(day) {
  const bpm = day.byProviderModel || {};
  const k = Object.keys(bpm)[0];
  return k ? k.split(':').pop() : '';
}

function write(payload) {
  const body = `window.__DSH_LIVE__ = ${JSON.stringify(payload)};\n`;
  const tmp = OUT_JS + '.tmp';
  fs.writeFileSync(tmp, body);
  fs.renameSync(tmp, OUT_JS);
}

let lastErr = '';
function tick() {
  try {
    const p = build();
    write(p);
    if (lastErr) { log('恢复'); lastErr = ''; }
  } catch (e) {
    const msg = e && e.message ? e.message : String(e);
    if (msg !== lastErr) { log('错误：' + msg); lastErr = msg; }
  }
}

/* 单实例守卫 */
const LOCK = path.join(HERE, 'bridge.pid');
try {
  const pid = Number(fs.readFileSync(LOCK, 'utf8').trim());
  if (pid && pid !== process.pid) {
    try { process.kill(pid, 0); console.log('DSH LIVE bridge 已在运行，pid=' + pid); process.exit(0); } catch { /* 旧进程已死 */ }
  }
} catch { /* 没有锁文件 */ }
fs.writeFileSync(LOCK, String(process.pid));
const bye = () => {
  try { if (fs.readFileSync(LOCK, 'utf8').trim() === String(process.pid)) fs.unlinkSync(LOCK); } catch {}
  process.exit(0);
};
process.on('SIGINT', bye);
process.on('SIGTERM', bye);

/* ---------- 系统配色：只在壁纸页面报告颜色变化时写一次，平时完全不动 ---------- */
const SYS_PORT = Number(process.env.DSH_SYS_PORT || 38765);
const SYS_SCRIPT = path.join(HERE, 'set-system-theme.ps1');
let lastSys = { bg: '', ink: '' };

/* 配色落盘：壁纸重载会丢 localStorage，颜色以 live/colors.json 为准 */
const COLORS_FILE = path.join(HERE, 'colors.json');
let savedColors = null;
try { savedColors = JSON.parse(fs.readFileSync(COLORS_FILE, 'utf8')); } catch (e) { savedColors = null; }

function applySystemTheme(bg, ink) {
  const args = ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-WindowStyle', 'Hidden', '-File', SYS_SCRIPT, '-Bg', bg, '-Ink', ink];
  if (process.env.DSH_SYS_DRY === '1') args.push('-DryRun'); else args.push('-Restart');
  let p;
  try {
    p = spawn('powershell', args, { windowsHide: true });
  } catch (e) {
    log('系统配色无法启动：' + (e && e.message ? e.message : e));
    return false;
  }
  let out = '';
  const grab = d => { out = (out + d).slice(-400); };
  p.stdout.on('data', grab);
  p.stderr.on('data', grab);
  p.on('error', e => log('系统配色失败：' + e.message));
  p.on('close', code => log(`系统配色 ${code === 0 ? '已应用' : '失败(' + code + ')'} · bg ${bg} / ink ${ink}` + (code ? ' · ' + out.trim() : '')));
  return true;
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Cache-Control': 'no-store',
};

function startColorServer() {
  const srv = http.createServer((req, res) => {
    log('颜色请求 ' + req.method + ' ' + req.url + ' len=' + (req.headers['content-length'] || '?'));
    if (req.method === 'OPTIONS') { res.writeHead(204, CORS); return res.end(); }
    const p0 = req.url.split('?')[0];
    if (req.method === 'GET' && p0 === '/colors') {
      res.writeHead(200, { ...CORS, 'Content-Type': 'application/json' });
      return res.end(JSON.stringify(savedColors || {}));
    }
    if (req.method === 'POST' && p0 === '/colors') {
      let b = '';
      req.on('data', d => { b += d; if (b.length > 4096) req.destroy(); });
      req.on('end', () => {
        let j = {};
        try { j = JSON.parse(b || '{}'); } catch (e) { j = {}; }
        const variant = ['dark', 'light', 'ink'].includes(j.variant) ? j.variant : (savedColors && savedColors.variant) || 'dark';
        const bg = String(j.bg || '').toUpperCase(), ink = String(j.ink || '').toUpperCase();
        const hasColors = /^#[0-9A-F]{6}$/.test(bg) && /^#[0-9A-F]{6}$/.test(ink);
        if (j.reset === true || !hasColors) savedColors = { variant };
        else savedColors = { variant, bg, ink };
        try { fs.writeFileSync(COLORS_FILE, JSON.stringify(savedColors)); } catch (e) { log('配色保存失败：' + (e && e.message)); }
        res.writeHead(200, { ...CORS, 'Content-Type': 'application/json' });
        res.end('{"ok":true}');
      });
      return;
    }
    if (req.method !== 'POST' || p0 !== '/theme') {
      res.writeHead(404, CORS); return res.end('{"ok":false}');
    }
    let buf = '';
    req.on('data', d => { buf += d; if (buf.length > 4096) req.destroy(); });
    req.on('end', () => {
      try {
        const j = JSON.parse(buf || '{}');
        const bg = String(j.bg || '').toUpperCase(), ink = String(j.ink || '').toUpperCase();
        if (!/^#[0-9A-F]{6}$/.test(bg) || !/^#[0-9A-F]{6}$/.test(ink)) {
          res.writeHead(400, { ...CORS, 'Content-Type': 'application/json' });
          return res.end('{"ok":false,"reason":"bad-color"}');
        }
        if (bg === lastSys.bg && ink === lastSys.ink) {
          res.writeHead(200, { ...CORS, 'Content-Type': 'application/json' });
          return res.end('{"ok":true,"skip":true}');
        }
        if (!applySystemTheme(bg, ink)) {
          res.writeHead(500, { ...CORS, 'Content-Type': 'application/json' });
          return res.end('{"ok":false,"reason":"spawn"}');
        }
        lastSys = { bg, ink };
        res.writeHead(200, { ...CORS, 'Content-Type': 'application/json' });
        res.end('{"ok":true}');
      } catch (e) {
        log('颜色请求解析失败：' + (e && e.message));
        res.writeHead(400, CORS); res.end('{"ok":false}');
      }
    });
  });
  srv.on('error', e => log('颜色接口启动失败：' + e.message));
  srv.listen(SYS_PORT, '127.0.0.1', () => log('颜色接口 http://127.0.0.1:' + SYS_PORT + ' · 仅 /theme POST 会改系统配色'));
  return srv;
}

log(`DSH LIVE bridge 启动 · 每 ${INTERVAL / 1000}s 刷新一次 · 输出 ${OUT_JS}`);
startColorServer();
tick();
setInterval(tick, INTERVAL);
