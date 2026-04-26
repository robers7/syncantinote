import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import Database from "better-sqlite3";
import type { LocalNote, PullChange } from "../types.js";

function getNotesColumns(db: Database.Database): Set<string> {
  const rows = db.prepare("PRAGMA table_info(notes)").all() as Array<{ name: string }>;
  return new Set(rows.map((row) => row.name));
}

export function createSnapshot(antinoteDbPath: string): string {
  if (!fs.existsSync(antinoteDbPath)) {
    throw new Error(`Antinote DB not found at ${antinoteDbPath}`);
  }

  const snapshotPath = path.join(os.tmpdir(), `syncantinote-${Date.now()}-${Math.random().toString(16).slice(2)}.sqlite3`);
  fs.copyFileSync(antinoteDbPath, snapshotPath);
  return snapshotPath;
}

export function readNotesFromSnapshot(snapshotPath: string): LocalNote[] {
  const db = new Database(snapshotPath, { readonly: true, fileMustExist: true });
  try {
    const columns = getNotesColumns(db);
    if (!columns.size) {
      return [];
    }

    const idExpr = columns.has("id") ? "CAST(id AS TEXT) AS id" : "CAST(rowid AS TEXT) AS id";
    const contentExpr = columns.has("content") ? "CAST(content AS TEXT) AS content" : "'' AS content";
    const titleExpr = columns.has("title") ? "CAST(title AS TEXT) AS title" : "NULL AS title";
    const createdExpr = columns.has("created_at")
      ? "CAST(created_at AS TEXT) AS created_at"
      : columns.has("updated_at")
        ? "CAST(updated_at AS TEXT) AS created_at"
        : "datetime('now') AS created_at";
    const updatedExpr = columns.has("updated_at")
      ? "CAST(updated_at AS TEXT) AS updated_at"
      : columns.has("created_at")
        ? "CAST(created_at AS TEXT) AS updated_at"
        : "datetime('now') AS updated_at";
    const deletedExpr = columns.has("deleted_at") ? "CAST(deleted_at AS TEXT) AS deleted_at" : "NULL AS deleted_at";

    const rows = db
      .prepare(`SELECT ${idExpr}, ${contentExpr}, ${titleExpr}, ${createdExpr}, ${updatedExpr}, ${deletedExpr} FROM notes`)
      .all() as LocalNote[];

    return rows.map((row) => ({
      id: String(row.id),
      content: row.content ?? "",
      title: row.title ?? null,
      created_at: row.created_at,
      updated_at: row.updated_at,
      deleted_at: row.deleted_at ?? null
    }));
  } finally {
    db.close();
    fs.rmSync(snapshotPath, { force: true });
  }
}

export function isAntinoteRunning(): boolean {
  const result = spawnSync("pgrep", ["-x", "Antinote"], { stdio: "ignore" });
  return result.status === 0;
}

export function applyRemoteChangeToAntinote(antinoteDbPath: string, change: PullChange): void {
  const db = new Database(antinoteDbPath);
  try {
    const columns = getNotesColumns(db);
    if (!columns.has("id")) {
      throw new Error("Antinote notes table does not expose stable id column.");
    }

    if (change.operation === "delete") {
      if (columns.has("deleted_at")) {
        if (columns.has("updated_at")) {
          db.prepare("UPDATE notes SET deleted_at = ?, updated_at = ? WHERE id = ?").run(
            change.deleted_at ?? change.changed_at,
            change.changed_at,
            change.note_id
          );
        } else {
          db.prepare("UPDATE notes SET deleted_at = ? WHERE id = ?").run(change.deleted_at ?? change.changed_at, change.note_id);
        }
      } else {
        db.prepare("DELETE FROM notes WHERE id = ?").run(change.note_id);
      }
      return;
    }

    if (!columns.has("content")) {
      throw new Error("Antinote notes table does not include content column.");
    }

    const insertColumns = ["id", "content"];
    const insertValues = ["@id", "@content"];
    const updateParts = ["content = excluded.content"];

    if (columns.has("title")) {
      insertColumns.push("title");
      insertValues.push("@title");
      updateParts.push("title = excluded.title");
    }

    if (columns.has("created_at")) {
      insertColumns.push("created_at");
      insertValues.push("@created_at");
    }

    if (columns.has("updated_at")) {
      insertColumns.push("updated_at");
      insertValues.push("@updated_at");
      updateParts.push("updated_at = excluded.updated_at");
    }

    if (columns.has("deleted_at")) {
      insertColumns.push("deleted_at");
      insertValues.push("NULL");
      updateParts.push("deleted_at = NULL");
    }

    const sql = `
      INSERT INTO notes (${insertColumns.join(", ")})
      VALUES (${insertValues.join(", ")})
      ON CONFLICT(id) DO UPDATE SET ${updateParts.join(", ")}
    `;

    db.prepare(sql).run({
      id: change.note_id,
      content: change.content ?? "",
      title: change.title,
      created_at: change.changed_at,
      updated_at: change.changed_at
    });
  } finally {
    db.close();
  }
}
