import fs from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";
import { SCHEMA_SQL } from "./schema.js";

export interface DbDevice {
  id: string;
  name: string;
  token_hash: string;
  created_at: string;
  last_seen_at: string | null;
}

export interface DbNote {
  id: string;
  content: string;
  title: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  server_revision: number;
  updated_by_device: string;
}

export interface DbChange {
  revision: number;
  note_id: string;
  operation: "upsert" | "delete";
  content: string | null;
  title: string | null;
  changed_at: string;
  changed_by_device: string;
  deleted_at: string | null;
}

export function openDatabase(dbPath: string): Database.Database {
  const dir = path.dirname(dbPath);
  fs.mkdirSync(dir, { recursive: true });

  const db = new Database(dbPath);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");

  db.exec(SCHEMA_SQL);
  return db;
}
