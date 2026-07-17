PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS profiles (
  id TEXT PRIMARY KEY,
  google_sub TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL,
  nickname TEXT NOT NULL,
  display_mode TEXT NOT NULL DEFAULT 'masked'
    CHECK (display_mode IN ('masked', 'public')),
  joined_at TEXT NOT NULL,
  left_at TEXT,
  hidden_at TEXT,
  consent_version TEXT NOT NULL,
  last_app_version TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS profiles_active_idx
  ON profiles(left_at, hidden_at, joined_at);

CREATE TABLE IF NOT EXISTS daily_usage (
  user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  local_day TEXT NOT NULL,
  total_tokens INTEGER NOT NULL CHECK (total_tokens >= 0),
  estimated_cost_micro_usd INTEGER NOT NULL CHECK (estimated_cost_micro_usd >= 0),
  pricing_version TEXT NOT NULL,
  app_version TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (user_id, local_day)
);

CREATE INDEX IF NOT EXISTS daily_usage_period_idx
  ON daily_usage(local_day, total_tokens, estimated_cost_micro_usd);

CREATE TABLE IF NOT EXISTS refresh_sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_used_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS refresh_sessions_user_idx
  ON refresh_sessions(user_id, expires_at);

CREATE TABLE IF NOT EXISTS admin_audit (
  id TEXT PRIMARY KEY,
  actor_id TEXT NOT NULL REFERENCES profiles(id),
  action TEXT NOT NULL,
  target_id TEXT,
  created_at TEXT NOT NULL
);
