/**
 * StarBank 家庭同步 Worker（单文件，可直接粘贴到 Cloudflare Dashboard 在线编辑器）
 *
 * 绑定要求：
 *   - D1 数据库绑定，变量名必须为 DB
 *   - 环境变量（Secret）ADMIN_TOKEN：管理员令牌，用于 /admin 管理页与 /api/admin/* 接口
 *
 * 设计要点：
 *   - 用户名+密码注册，首次注册自动创建家庭并成为主号(owner)
 *   - 主号可创建/重置/移除子号(member)
 *   - 记录级同步：updated_at 新者胜(LWW)，删除用墓碑
 *   - 计数器（星星/存钱罐/零花钱）：操作累加（op_id 幂等去重），并发加星不丢失
 *   - 增量拉取：按 family 内单调递增 seq 游标
 */

const JSON_HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, content-type, x-admin-token',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
};

const PBKDF2_ITERATIONS = 100000;
const MAX_PUSH_RECORDS = 200;
const MAX_PUSH_OPS = 500;
// 免费版 Worker 单请求 CPU 限额较低，分页取小值
const PULL_PAGE_SIZE = 100;
const COUNTER_FIELDS = ['star', 'piggy', 'pocket'];

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: JSON_HEADERS });
    }
    const url = new URL(request.url);
    try {
      if (url.pathname === '/admin' || url.pathname === '/admin/') {
        return new Response(ADMIN_HTML, {
          headers: { 'content-type': 'text/html; charset=utf-8' },
        });
      }
      if (url.pathname.startsWith('/api/admin/')) {
        return await handleAdmin(request, env, url);
      }
      if (url.pathname.startsWith('/api/')) {
        return await handleApi(request, env, url);
      }
      return json({ ok: true, service: 'starbank-family-sync' });
    } catch (e) {
      if (e instanceof HttpError) {
        return json({ error: e.message }, e.status);
      }
      return json({ error: '服务器内部错误: ' + (e && e.message) }, 500);
    }
  },
};

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
}

function nowIso() {
  return new Date().toISOString();
}

function randomHex(bytes) {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return [...buf].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function hashPassword(password, saltHex) {
  const enc = new TextEncoder();
  const salt = new Uint8Array(
    saltHex.match(/.{2}/g).map((h) => parseInt(h, 16)),
  );
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(password),
    'PBKDF2',
    false,
    ['deriveBits'],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations: PBKDF2_ITERATIONS },
    key,
    256,
  );
  return [...new Uint8Array(bits)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function readBody(request) {
  try {
    return await request.json();
  } catch (_) {
    throw new HttpError(400, '请求体必须是 JSON');
  }
}

function requireFields(body, fields) {
  for (const f of fields) {
    const v = body[f];
    if (v === undefined || v === null || String(v).trim() === '') {
      throw new HttpError(400, `缺少字段: ${f}`);
    }
  }
}

function validateUsername(username) {
  if (!/^[a-zA-Z0-9_一-龥]{2,24}$/.test(username)) {
    throw new HttpError(400, '用户名需为 2-24 位字母/数字/下划线/中文');
  }
}

function validatePassword(password) {
  if (typeof password !== 'string' || password.length < 6) {
    throw new HttpError(400, '密码至少 6 位');
  }
}

async function authenticate(request, env) {
  const header = request.headers.get('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!token) throw new HttpError(401, '未登录');
  const row = await env.DB.prepare(
    `SELECT u.id, u.family_id, u.username, u.role, u.disabled, t.token
       FROM tokens t JOIN users u ON u.id = t.user_id
      WHERE t.token = ?`,
  )
    .bind(token)
    .first();
  if (!row) throw new HttpError(401, '登录已失效，请重新登录');
  if (row.disabled) throw new HttpError(403, '账号已被停用');
  return {
    userId: row.id,
    familyId: row.family_id,
    username: row.username,
    role: row.role,
    token,
  };
}

async function issueToken(env, userId) {
  const token = randomHex(32);
  await env.DB.prepare(
    'INSERT INTO tokens (token, user_id, created_at) VALUES (?, ?, ?)',
  )
    .bind(token, userId, nowIso())
    .run();
  return token;
}

async function familyInfo(env, familyId) {
  const family = await env.DB.prepare(
    'SELECT id, name, last_seq, created_at FROM families WHERE id = ?',
  )
    .bind(familyId)
    .first();
  return family;
}

// ---------------------------------------------------------------------------
// 普通 API
// ---------------------------------------------------------------------------

async function handleApi(request, env, url) {
  const path = url.pathname;
  const method = request.method;

  if (path === '/api/register' && method === 'POST') {
    return apiRegister(request, env);
  }
  if (path === '/api/login' && method === 'POST') {
    return apiLogin(request, env);
  }

  const auth = await authenticate(request, env);

  if (path === '/api/logout' && method === 'POST') {
    await env.DB.prepare('DELETE FROM tokens WHERE token = ?')
      .bind(auth.token)
      .run();
    return json({ ok: true });
  }
  if (path === '/api/me' && method === 'GET') {
    const family = await familyInfo(env, auth.familyId);
    return json({
      user: { id: auth.userId, username: auth.username, role: auth.role },
      family: { id: family.id, name: family.name },
    });
  }
  if (path === '/api/password' && method === 'POST') {
    return apiChangePassword(request, env, auth);
  }
  if (path === '/api/members' && method === 'GET') {
    return apiListMembers(env, auth);
  }
  if (path === '/api/members' && method === 'POST') {
    return apiCreateMember(request, env, auth);
  }
  if (path === '/api/members/reset' && method === 'POST') {
    return apiResetMemberPassword(request, env, auth);
  }
  if (path === '/api/members/remove' && method === 'POST') {
    return apiRemoveMember(request, env, auth);
  }
  if (path === '/api/sync/push' && method === 'POST') {
    return apiSyncPush(request, env, auth);
  }
  if (path === '/api/sync/changes' && method === 'GET') {
    return apiSyncChanges(env, auth, url);
  }
  if (path === '/api/sync/stats' && method === 'GET') {
    return apiSyncStats(env, auth);
  }
  throw new HttpError(404, '接口不存在');
}

async function apiRegister(request, env) {
  const body = await readBody(request);
  requireFields(body, ['username', 'password']);
  const username = String(body.username).trim();
  validateUsername(username);
  validatePassword(body.password);

  const exists = await env.DB.prepare('SELECT id FROM users WHERE username = ?')
    .bind(username)
    .first();
  if (exists) throw new HttpError(409, '用户名已被占用');

  const familyId = randomHex(12);
  const userId = randomHex(12);
  const salt = randomHex(16);
  const hash = await hashPassword(body.password, salt);
  const familyName = String(body.familyName || `${username}的家庭`).trim();
  const now = nowIso();

  await env.DB.batch([
    env.DB.prepare(
      'INSERT INTO families (id, name, last_seq, created_at) VALUES (?, ?, 0, ?)',
    ).bind(familyId, familyName, now),
    env.DB.prepare(
      `INSERT INTO users (id, family_id, username, password_hash, salt, role, created_at)
       VALUES (?, ?, ?, ?, ?, 'owner', ?)`,
    ).bind(userId, familyId, username, hash, salt, now),
  ]);
  const token = await issueToken(env, userId);
  return json({
    token,
    user: { id: userId, username, role: 'owner' },
    family: { id: familyId, name: familyName },
  });
}

async function apiLogin(request, env) {
  const body = await readBody(request);
  requireFields(body, ['username', 'password']);
  const username = String(body.username).trim();
  const user = await env.DB.prepare(
    'SELECT id, family_id, username, password_hash, salt, role, disabled FROM users WHERE username = ?',
  )
    .bind(username)
    .first();
  if (!user) throw new HttpError(401, '用户名或密码错误');
  if (user.disabled) throw new HttpError(403, '账号已被停用');
  const hash = await hashPassword(body.password, user.salt);
  if (hash !== user.password_hash) {
    throw new HttpError(401, '用户名或密码错误');
  }
  const token = await issueToken(env, user.id);
  const family = await familyInfo(env, user.family_id);
  return json({
    token,
    user: { id: user.id, username: user.username, role: user.role },
    family: { id: family.id, name: family.name },
  });
}

async function apiChangePassword(request, env, auth) {
  const body = await readBody(request);
  requireFields(body, ['oldPassword', 'newPassword']);
  validatePassword(body.newPassword);
  const user = await env.DB.prepare(
    'SELECT password_hash, salt FROM users WHERE id = ?',
  )
    .bind(auth.userId)
    .first();
  const oldHash = await hashPassword(body.oldPassword, user.salt);
  if (oldHash !== user.password_hash) {
    throw new HttpError(401, '原密码错误');
  }
  const salt = randomHex(16);
  const hash = await hashPassword(body.newPassword, salt);
  await env.DB.batch([
    env.DB.prepare(
      'UPDATE users SET password_hash = ?, salt = ? WHERE id = ?',
    ).bind(hash, salt, auth.userId),
    // 修改密码后吊销除当前令牌外的所有令牌
    env.DB.prepare('DELETE FROM tokens WHERE user_id = ? AND token != ?').bind(
      auth.userId,
      auth.token,
    ),
  ]);
  return json({ ok: true });
}

async function apiListMembers(env, auth) {
  const rows = await env.DB.prepare(
    `SELECT id, username, role, disabled, created_at FROM users
      WHERE family_id = ? ORDER BY created_at`,
  )
    .bind(auth.familyId)
    .all();
  return json({ members: rows.results });
}

function requireOwner(auth) {
  if (auth.role !== 'owner') {
    throw new HttpError(403, '只有主号可以执行此操作');
  }
}

async function apiCreateMember(request, env, auth) {
  requireOwner(auth);
  const body = await readBody(request);
  requireFields(body, ['username', 'password']);
  const username = String(body.username).trim();
  validateUsername(username);
  validatePassword(body.password);
  const exists = await env.DB.prepare('SELECT id FROM users WHERE username = ?')
    .bind(username)
    .first();
  if (exists) throw new HttpError(409, '用户名已被占用');
  const userId = randomHex(12);
  const salt = randomHex(16);
  const hash = await hashPassword(body.password, salt);
  await env.DB.prepare(
    `INSERT INTO users (id, family_id, username, password_hash, salt, role, created_at)
     VALUES (?, ?, ?, ?, ?, 'member', ?)`,
  )
    .bind(userId, auth.familyId, username, hash, salt, nowIso())
    .run();
  return json({ ok: true, user: { id: userId, username, role: 'member' } });
}

async function findFamilyMember(env, auth, userId) {
  const target = await env.DB.prepare(
    'SELECT id, family_id, role FROM users WHERE id = ?',
  )
    .bind(userId)
    .first();
  if (!target || target.family_id !== auth.familyId) {
    throw new HttpError(404, '成员不存在');
  }
  return target;
}

async function apiResetMemberPassword(request, env, auth) {
  requireOwner(auth);
  const body = await readBody(request);
  requireFields(body, ['userId', 'password']);
  validatePassword(body.password);
  const target = await findFamilyMember(env, auth, body.userId);
  if (target.role === 'owner' && target.id !== auth.userId) {
    throw new HttpError(403, '不能重置其他主号的密码');
  }
  const salt = randomHex(16);
  const hash = await hashPassword(body.password, salt);
  await env.DB.batch([
    env.DB.prepare(
      'UPDATE users SET password_hash = ?, salt = ? WHERE id = ?',
    ).bind(hash, salt, target.id),
    env.DB.prepare('DELETE FROM tokens WHERE user_id = ?').bind(target.id),
  ]);
  return json({ ok: true });
}

async function apiRemoveMember(request, env, auth) {
  requireOwner(auth);
  const body = await readBody(request);
  requireFields(body, ['userId']);
  if (body.userId === auth.userId) {
    throw new HttpError(400, '不能移除自己');
  }
  const target = await findFamilyMember(env, auth, body.userId);
  await env.DB.batch([
    env.DB.prepare('DELETE FROM tokens WHERE user_id = ?').bind(target.id),
    env.DB.prepare('DELETE FROM users WHERE id = ?').bind(target.id),
  ]);
  return json({ ok: true });
}

// ---------------------------------------------------------------------------
// 同步
// ---------------------------------------------------------------------------

async function apiSyncPush(request, env, auth) {
  const body = await readBody(request);
  const records = Array.isArray(body.records) ? body.records : [];
  const ops = Array.isArray(body.ops) ? body.ops : [];
  if (records.length > MAX_PUSH_RECORDS) {
    throw new HttpError(400, `单次最多推送 ${MAX_PUSH_RECORDS} 条记录`);
  }
  if (ops.length > MAX_PUSH_OPS) {
    throw new HttpError(400, `单次最多推送 ${MAX_PUSH_OPS} 个计数操作`);
  }

  let seq = null;
  if (records.length > 0) {
    const row = await env.DB.prepare(
      'UPDATE families SET last_seq = last_seq + 1 WHERE id = ? RETURNING last_seq',
    )
      .bind(auth.familyId)
      .first();
    seq = row.last_seq;

    const stmts = [];
    for (const r of records) {
      if (!r || !r.section || !r.recordId || !r.updatedAt) {
        throw new HttpError(400, '记录缺少 section/recordId/updatedAt');
      }
      stmts.push(
        env.DB.prepare(
          `INSERT INTO records (family_id, section, record_id, seq, updated_at, deleted, payload, updated_by)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(family_id, section, record_id) DO UPDATE SET
             seq = excluded.seq,
             updated_at = excluded.updated_at,
             deleted = excluded.deleted,
             payload = excluded.payload,
             updated_by = excluded.updated_by
           WHERE excluded.updated_at > records.updated_at`,
        ).bind(
          auth.familyId,
          String(r.section),
          String(r.recordId),
          seq,
          String(r.updatedAt),
          r.deleted ? 1 : 0,
          r.payload === undefined || r.payload === null
            ? null
            : JSON.stringify(r.payload),
          auth.userId,
        ),
      );
    }
    // D1 batch 按顺序在同一事务内执行
    for (let i = 0; i < stmts.length; i += 50) {
      await env.DB.batch(stmts.slice(i, i + 50));
    }
  }

  // 计数操作：按 op_id 幂等，批量执行减少往返
  let appliedOps = 0;
  if (ops.length > 0) {
    const now = nowIso();
    const stmts = [];
    for (const op of ops) {
      if (!op || !op.opId || !op.babyId || !COUNTER_FIELDS.includes(op.field)) {
        throw new HttpError(400, '计数操作缺少 opId/babyId/field');
      }
      const delta = Number(op.delta);
      if (!Number.isFinite(delta)) {
        throw new HttpError(400, '计数操作 delta 非法');
      }
      // 先尝试登记 op_id；未被去重时才把 delta 累加进 counters。
      stmts.push(
        env.DB.prepare(
          `INSERT OR IGNORE INTO counter_ops (op_id, family_id, baby_id, field, delta, user_id, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
        ).bind(
          String(op.opId),
          auth.familyId,
          String(op.babyId),
          op.field,
          delta,
          auth.userId,
          now,
        ),
        env.DB.prepare(
          `INSERT INTO counters (family_id, baby_id, field, total)
           SELECT family_id, baby_id, field, delta FROM counter_ops WHERE op_id = ?1 AND applied = 0
           ON CONFLICT(family_id, baby_id, field) DO UPDATE SET total = total + excluded.total`,
        ).bind(String(op.opId)),
        env.DB.prepare(
          'UPDATE counter_ops SET applied = 1 WHERE op_id = ?1 AND applied = 0',
        ).bind(String(op.opId)),
      );
      appliedOps++;
    }
    for (let i = 0; i < stmts.length; i += 60) {
      await env.DB.batch(stmts.slice(i, i + 60));
    }
  }

  const family = await familyInfo(env, auth.familyId);
  return json({ ok: true, seq: family.last_seq, appliedOps });
}

async function apiSyncChanges(env, auth, url) {
  const since = Number(url.searchParams.get('since') || '0');
  if (!Number.isFinite(since) || since < 0) {
    throw new HttpError(400, 'since 参数非法');
  }
  // 复合游标：同一推送批次的记录共享 seq，必须用 (seq, section, record_id)
  // 精确续页，否则分页边界会跳过同 seq 组的剩余记录。
  const sinceSection = url.searchParams.get('sinceSection');
  const sinceRecord = url.searchParams.get('sinceRecord');

  let stmt;
  if (sinceSection !== null && sinceRecord !== null) {
    stmt = env.DB.prepare(
      `SELECT section, record_id, seq, updated_at, deleted, payload
         FROM records
        WHERE family_id = ?1
          AND (seq > ?2
               OR (seq = ?2 AND (section > ?3
                    OR (section = ?3 AND record_id > ?4))))
        ORDER BY seq, section, record_id
        LIMIT ?5`,
    ).bind(auth.familyId, since, sinceSection, sinceRecord, PULL_PAGE_SIZE + 1);
  } else {
    stmt = env.DB.prepare(
      `SELECT section, record_id, seq, updated_at, deleted, payload
         FROM records
        WHERE family_id = ?1 AND seq > ?2
        ORDER BY seq, section, record_id
        LIMIT ?3`,
    ).bind(auth.familyId, since, PULL_PAGE_SIZE + 1);
  }
  const rows = await stmt.all();

  const results = rows.results || [];
  const hasMore = results.length > PULL_PAGE_SIZE;
  const page = hasMore ? results.slice(0, PULL_PAGE_SIZE) : results;
  const last = page.length > 0 ? page[page.length - 1] : null;

  const counters = await env.DB.prepare(
    'SELECT baby_id, field, total FROM counters WHERE family_id = ?',
  )
    .bind(auth.familyId)
    .all();

  const family = await familyInfo(env, auth.familyId);
  return json({
    seq: family.last_seq,
    nextSince: last ? last.seq : since,
    nextSection: last ? last.section : null,
    nextRecord: last ? last.record_id : null,
    hasMore,
    records: page.map((r) => ({
      section: r.section,
      recordId: r.record_id,
      updatedAt: r.updated_at,
      deleted: !!r.deleted,
      payload: r.payload ? JSON.parse(r.payload) : null,
    })),
    counters: (counters.results || []).map((c) => ({
      babyId: c.baby_id,
      field: c.field,
      total: c.total,
    })),
  });
}

async function apiSyncStats(env, auth) {
  const recordCount = await env.DB.prepare(
    'SELECT COUNT(*) AS n FROM records WHERE family_id = ?',
  )
    .bind(auth.familyId)
    .first();
  const opCount = await env.DB.prepare(
    'SELECT COUNT(*) AS n FROM counter_ops WHERE family_id = ?',
  )
    .bind(auth.familyId)
    .first();
  const family = await familyInfo(env, auth.familyId);
  return json({
    seq: family.last_seq,
    recordCount: recordCount.n,
    counterOpCount: opCount.n,
  });
}

// ---------------------------------------------------------------------------
// 管理接口（X-Admin-Token）
// ---------------------------------------------------------------------------

function requireAdmin(request, env) {
  const token = request.headers.get('x-admin-token') || '';
  if (!env.ADMIN_TOKEN) {
    throw new HttpError(500, '未配置 ADMIN_TOKEN 环境变量');
  }
  if (!token || token !== env.ADMIN_TOKEN) {
    throw new HttpError(401, '管理员令牌错误');
  }
}

async function handleAdmin(request, env, url) {
  requireAdmin(request, env);
  const path = url.pathname;
  const method = request.method;

  if (path === '/api/admin/overview' && method === 'GET') {
    const families = await env.DB.prepare(
      'SELECT id, name, last_seq, created_at FROM families ORDER BY created_at',
    ).all();
    const users = await env.DB.prepare(
      'SELECT id, family_id, username, role, disabled, created_at FROM users ORDER BY created_at',
    ).all();
    return json({ families: families.results, users: users.results });
  }
  if (path === '/api/admin/reset-password' && method === 'POST') {
    const body = await readBody(request);
    requireFields(body, ['username', 'password']);
    validatePassword(body.password);
    const user = await env.DB.prepare('SELECT id FROM users WHERE username = ?')
      .bind(String(body.username).trim())
      .first();
    if (!user) throw new HttpError(404, '用户不存在');
    const salt = randomHex(16);
    const hash = await hashPassword(body.password, salt);
    await env.DB.batch([
      env.DB.prepare(
        'UPDATE users SET password_hash = ?, salt = ? WHERE id = ?',
      ).bind(hash, salt, user.id),
      env.DB.prepare('DELETE FROM tokens WHERE user_id = ?').bind(user.id),
    ]);
    return json({ ok: true });
  }
  if (path === '/api/admin/revoke-tokens' && method === 'POST') {
    const body = await readBody(request);
    requireFields(body, ['username']);
    const user = await env.DB.prepare('SELECT id FROM users WHERE username = ?')
      .bind(String(body.username).trim())
      .first();
    if (!user) throw new HttpError(404, '用户不存在');
    await env.DB.prepare('DELETE FROM tokens WHERE user_id = ?')
      .bind(user.id)
      .run();
    return json({ ok: true });
  }
  if (path === '/api/admin/delete-family' && method === 'POST') {
    const body = await readBody(request);
    requireFields(body, ['familyId']);
    const familyId = String(body.familyId);
    const users = await env.DB.prepare(
      'SELECT id FROM users WHERE family_id = ?',
    )
      .bind(familyId)
      .all();
    const stmts = [];
    for (const u of users.results || []) {
      stmts.push(env.DB.prepare('DELETE FROM tokens WHERE user_id = ?').bind(u.id));
    }
    stmts.push(
      env.DB.prepare('DELETE FROM users WHERE family_id = ?').bind(familyId),
      env.DB.prepare('DELETE FROM records WHERE family_id = ?').bind(familyId),
      env.DB.prepare('DELETE FROM counters WHERE family_id = ?').bind(familyId),
      env.DB.prepare('DELETE FROM counter_ops WHERE family_id = ?').bind(familyId),
      env.DB.prepare('DELETE FROM families WHERE id = ?').bind(familyId),
    );
    await env.DB.batch(stmts);
    return json({ ok: true });
  }
  throw new HttpError(404, '接口不存在');
}

// ---------------------------------------------------------------------------
// 极简管理页
// ---------------------------------------------------------------------------

const ADMIN_HTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>StarBank 同步管理</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 720px; margin: 24px auto; padding: 0 16px; color: #333; }
  h1 { font-size: 20px; }
  fieldset { border: 1px solid #ddd; border-radius: 8px; margin-bottom: 16px; }
  input, button { font-size: 14px; padding: 6px 10px; margin: 4px 4px 4px 0; }
  button { cursor: pointer; }
  table { border-collapse: collapse; width: 100%; font-size: 13px; }
  th, td { border: 1px solid #e5e5e5; padding: 6px 8px; text-align: left; }
  #msg { color: #c0392b; min-height: 20px; }
</style>
</head>
<body>
<h1>StarBank 家庭同步 · 管理</h1>
<fieldset>
  <legend>管理员令牌</legend>
  <input id="token" type="password" placeholder="ADMIN_TOKEN" style="width:280px">
  <button onclick="saveToken()">保存</button>
  <button onclick="loadOverview()">刷新数据</button>
</fieldset>
<div id="msg"></div>
<fieldset>
  <legend>家庭与成员</legend>
  <div id="overview">点击「刷新数据」加载</div>
</fieldset>
<fieldset>
  <legend>重置用户密码</legend>
  <input id="ru" placeholder="用户名">
  <input id="rp" placeholder="新密码(≥6位)">
  <button onclick="resetPwd()">重置</button>
</fieldset>
<fieldset>
  <legend>吊销用户所有登录</legend>
  <input id="vu" placeholder="用户名">
  <button onclick="revoke()">吊销</button>
</fieldset>
<fieldset>
  <legend>删除家庭（不可恢复！）</legend>
  <input id="df" placeholder="家庭ID">
  <button onclick="delFamily()">删除</button>
</fieldset>
<script>
const $ = (id) => document.getElementById(id);
$('token').value = localStorage.getItem('sb_admin_token') || '';
function saveToken() { localStorage.setItem('sb_admin_token', $('token').value); msg('已保存'); }
function msg(t) { $('msg').textContent = t; }
async function call(path, method, body) {
  const res = await fetch(path, {
    method,
    headers: { 'content-type': 'application/json', 'x-admin-token': $('token').value },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || res.status);
  return data;
}
async function loadOverview() {
  msg('');
  try {
    const d = await call('/api/admin/overview', 'GET');
    let html = '<table><tr><th>家庭ID</th><th>家庭名</th><th>用户名</th><th>角色</th><th>创建时间</th></tr>';
    for (const f of d.families) {
      const members = d.users.filter(u => u.family_id === f.id);
      if (members.length === 0) {
        html += '<tr><td>' + f.id + '</td><td>' + f.name + '</td><td colspan=3>(无成员)</td></tr>';
      }
      for (const u of members) {
        html += '<tr><td>' + f.id + '</td><td>' + f.name + '</td><td>' + u.username +
          '</td><td>' + (u.role === 'owner' ? '主号' : '子号') + '</td><td>' + u.created_at + '</td></tr>';
      }
    }
    html += '</table>';
    $('overview').innerHTML = html;
  } catch (e) { msg('加载失败: ' + e.message); }
}
async function resetPwd() {
  try { await call('/api/admin/reset-password', 'POST', { username: $('ru').value, password: $('rp').value }); msg('密码已重置'); }
  catch (e) { msg('失败: ' + e.message); }
}
async function revoke() {
  try { await call('/api/admin/revoke-tokens', 'POST', { username: $('vu').value }); msg('已吊销'); }
  catch (e) { msg('失败: ' + e.message); }
}
async function delFamily() {
  if (!confirm('确定删除该家庭的所有云端数据？不可恢复！')) return;
  try { await call('/api/admin/delete-family', 'POST', { familyId: $('df').value }); msg('已删除'); loadOverview(); }
  catch (e) { msg('失败: ' + e.message); }
}
</script>
</body>
</html>`;
