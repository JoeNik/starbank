-- StarBank 家庭同步 D1 数据库结构
-- 在 Cloudflare Dashboard → D1 → 你的数据库 → Console 中整段粘贴执行

CREATE TABLE IF NOT EXISTS families (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  last_seq INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  salt TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'member',
  disabled INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tokens (
  token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_used_at TEXT
);

CREATE TABLE IF NOT EXISTS records (
  family_id TEXT NOT NULL,
  section TEXT NOT NULL,
  record_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0,
  payload TEXT,
  updated_by TEXT,
  PRIMARY KEY (family_id, section, record_id)
);
CREATE INDEX IF NOT EXISTS idx_records_family_seq ON records(family_id, seq);

CREATE TABLE IF NOT EXISTS counters (
  family_id TEXT NOT NULL,
  baby_id TEXT NOT NULL,
  field TEXT NOT NULL,
  total REAL NOT NULL DEFAULT 0,
  PRIMARY KEY (family_id, baby_id, field)
);

CREATE TABLE IF NOT EXISTS counter_ops (
  op_id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  baby_id TEXT NOT NULL,
  field TEXT NOT NULL,
  delta REAL NOT NULL,
  user_id TEXT,
  created_at TEXT NOT NULL,
  applied INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_counter_ops_family ON counter_ops(family_id, created_at);

-- ============================================================
-- 从 2026-07-26 之前的旧版本升级时，执行下面两行（新部署无需执行）：
-- ALTER TABLE counter_ops ADD COLUMN applied INTEGER NOT NULL DEFAULT 0;
-- UPDATE counter_ops SET applied = 1;
-- ============================================================
