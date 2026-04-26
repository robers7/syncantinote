import fs from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";
import { HELPER_SCHEMA_SQL } from "./schema.js";
import type { PullChange, ShadowNoteState } from "../types.js";

export function openHelperDatabase(helperDbPath: string): Database.Database {
  fs.mkdirSync(path.dirname(helperDbPath), { recursive: true });
  const db = new Database(helperDbPath);
  db.pragma("journal_mode = WAL");
  db.exec(HELPER_SCHEMA_SQL);
  return db;
}

export function getAllNoteState(db: Database.Database): ShadowNoteState[] {
  return db
    .prepare(
      `
      SELECT note_id, last_seen_hash, last_seen_updated_at, last_synced_server_revision, dirty_status, pending_conflict
      FROM note_state
      `
    )
    .all() as ShadowNoteState[];
}

export function upsertNoteState(db: Database.Database, state: ShadowNoteState): void {
  db.prepare(
    `
    INSERT INTO note_state (note_id, last_seen_hash, last_seen_updated_at, last_synced_server_revision, dirty_status, pending_conflict)
    VALUES (@note_id, @last_seen_hash, @last_seen_updated_at, @last_synced_server_revision, @dirty_status, @pending_conflict)
    ON CONFLICT(note_id) DO UPDATE SET
      last_seen_hash = excluded.last_seen_hash,
      last_seen_updated_at = excluded.last_seen_updated_at,
      last_synced_server_revision = excluded.last_synced_server_revision,
      dirty_status = excluded.dirty_status,
      pending_conflict = excluded.pending_conflict
    `
  ).run(state);
}

export function setDirtyStatus(db: Database.Database, noteId: string, status: "clean" | "dirty"): void {
  db.prepare("UPDATE note_state SET dirty_status = ? WHERE note_id = ?").run(status, noteId);
}

export function setPendingConflict(db: Database.Database, noteId: string, pending: number): void {
  db.prepare("UPDATE note_state SET pending_conflict = ? WHERE note_id = ?").run(pending, noteId);
}

export function getRuntimeNumber(db: Database.Database, key: string, defaultValue = 0): number {
  const row = db.prepare("SELECT value FROM runtime_state WHERE key = ?").get(key) as { value: string } | undefined;
  if (!row) return defaultValue;
  const n = Number(row.value);
  return Number.isFinite(n) ? n : defaultValue;
}

export function setRuntimeNumber(db: Database.Database, key: string, value: number): void {
  db.prepare(
    `
    INSERT INTO runtime_state (key, value)
    VALUES (?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value
    `
  ).run(key, String(value));
}

export function enqueueRemoteChange(db: Database.Database, change: PullChange): void {
  db.prepare(
    `
    INSERT OR IGNORE INTO remote_apply_queue
    (revision, note_id, operation, content, title, deleted_at, changed_at, changed_by_device)
    VALUES (@revision, @note_id, @operation, @content, @title, @deleted_at, @changed_at, @changed_by_device)
    `
  ).run(change);
}

export function listQueuedRemoteChanges(db: Database.Database): PullChange[] {
  return db
    .prepare(
      `
      SELECT revision, note_id, operation, content, title, changed_at, changed_by_device, deleted_at
      FROM remote_apply_queue
      ORDER BY revision ASC
      `
    )
    .all() as PullChange[];
}

export function removeQueuedRevision(db: Database.Database, revision: number): void {
  db.prepare("DELETE FROM remote_apply_queue WHERE revision = ?").run(revision);
}
