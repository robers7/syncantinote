export const HELPER_SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS note_state (
  note_id TEXT PRIMARY KEY,
  last_seen_hash TEXT NOT NULL,
  last_seen_updated_at TEXT,
  last_synced_server_revision INTEGER NOT NULL DEFAULT 0,
  dirty_status TEXT NOT NULL DEFAULT 'clean' CHECK (dirty_status IN ('clean', 'dirty')),
  pending_conflict INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS runtime_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS remote_apply_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  revision INTEGER NOT NULL,
  note_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  content TEXT,
  title TEXT,
  deleted_at TEXT,
  changed_at TEXT NOT NULL,
  changed_by_device TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_remote_apply_queue_revision ON remote_apply_queue (revision);
`;
