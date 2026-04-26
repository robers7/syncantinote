import crypto from "node:crypto";
import type Database from "better-sqlite3";
import type { HelperConfig } from "../config.js";
import {
  enqueueRemoteChange,
  getAllNoteState,
  getRuntimeNumber,
  listQueuedRemoteChanges,
  removeQueuedRevision,
  setPendingConflict,
  setRuntimeNumber,
  upsertNoteState
} from "../db/database.js";
import type { LocalNote, PullChange, PushChange, ShadowNoteState } from "../types.js";
import { applyRemoteChangeToAntinote, createSnapshot, isAntinoteRunning, readNotesFromSnapshot } from "./antinote.js";
import { pullChanges, pushChanges } from "./api.js";

function noteHash(note: LocalNote): string {
  return crypto
    .createHash("sha256")
    .update(`${note.id}|${note.title ?? ""}|${note.content}|${note.updated_at}|${note.deleted_at ?? ""}`)
    .digest("hex");
}

function stateMap(states: ShadowNoteState[]): Map<string, ShadowNoteState> {
  return new Map(states.map((s) => [s.note_id, s]));
}

function toDirtyUpsert(note: LocalNote, baseRevision: number): PushChange {
  return {
    note_id: note.id,
    operation: "upsert",
    base_server_revision: baseRevision,
    content: note.content,
    title: note.title,
    local_updated_at: note.updated_at,
    deleted_at: note.deleted_at
  };
}

function toDirtyDelete(noteId: string, baseRevision: number): PushChange {
  return {
    note_id: noteId,
    operation: "delete",
    base_server_revision: baseRevision,
    deleted_at: new Date().toISOString()
  };
}

function diffLocalNotes(notes: LocalNote[], currentStates: Map<string, ShadowNoteState>): PushChange[] {
  const changes: PushChange[] = [];
  const seenIds = new Set<string>();

  for (const note of notes) {
    seenIds.add(note.id);
    const existing = currentStates.get(note.id);
    const hashed = noteHash(note);

    if (!existing) {
      changes.push(toDirtyUpsert(note, 0));
      continue;
    }

    if (existing.last_seen_hash !== hashed) {
      changes.push(toDirtyUpsert(note, existing.last_synced_server_revision));
    }
  }

  for (const [noteId, state] of currentStates.entries()) {
    if (!seenIds.has(noteId) && state.last_synced_server_revision > 0) {
      changes.push(toDirtyDelete(noteId, state.last_synced_server_revision));
    }
  }

  return changes;
}

function updateStateForLocalSnapshot(db: Database.Database, notes: LocalNote[], priorStates: Map<string, ShadowNoteState>): void {
  const tx = db.transaction(() => {
    for (const note of notes) {
      const prior = priorStates.get(note.id);
      upsertNoteState(db, {
        note_id: note.id,
        last_seen_hash: noteHash(note),
        last_seen_updated_at: note.updated_at,
        last_synced_server_revision: prior?.last_synced_server_revision ?? 0,
        dirty_status: prior ? prior.dirty_status : "clean",
        pending_conflict: prior?.pending_conflict ?? 0
      });
    }
  });
  tx();
}

function applyQueuedRemoteIfSafe(db: Database.Database, config: HelperConfig): void {
  if (isAntinoteRunning()) {
    return;
  }

  const queued = listQueuedRemoteChanges(db);
  for (const change of queued) {
    applyRemoteChangeToAntinote(config.antinoteDbPath, change);
    removeQueuedRevision(db, change.revision);
  }
}

function handleRemoteChanges(db: Database.Database, config: HelperConfig, changes: PullChange[]): void {
  const running = isAntinoteRunning();

  const tx = db.transaction(() => {
    for (const change of changes) {
      if (change.changed_by_device === config.deviceId) {
        continue;
      }

      if (running) {
        enqueueRemoteChange(db, change);
      } else {
        applyRemoteChangeToAntinote(config.antinoteDbPath, change);
      }
    }
  });

  tx();
}

function markAcceptedChanges(
  db: Database.Database,
  notesById: Map<string, LocalNote>,
  accepted: Array<{ note_id: string; server_revision: number }>
): void {
  const states = stateMap(getAllNoteState(db));

  const tx = db.transaction(() => {
    for (const item of accepted) {
      const current = states.get(item.note_id);
      const local = notesById.get(item.note_id);

      if (!current) {
        continue;
      }

      upsertNoteState(db, {
        ...current,
        last_synced_server_revision: item.server_revision,
        last_seen_hash: local ? noteHash(local) : current.last_seen_hash,
        last_seen_updated_at: local?.updated_at ?? current.last_seen_updated_at,
        dirty_status: "clean",
        pending_conflict: 0
      });
    }
  });

  tx();
}

function markConflicts(db: Database.Database, conflicts: Array<{ note_id: string }>): void {
  const tx = db.transaction(() => {
    for (const conflict of conflicts) {
      setPendingConflict(db, conflict.note_id, 1);
    }
  });
  tx();
}

export async function runSyncIteration(db: Database.Database, config: HelperConfig): Promise<void> {
  const snapshotPath = createSnapshot(config.antinoteDbPath);
  const localNotes = readNotesFromSnapshot(snapshotPath);
  const localNotesById = new Map(localNotes.map((n) => [n.id, n]));

  const states = stateMap(getAllNoteState(db));
  const outgoing = diffLocalNotes(localNotes, states);

  updateStateForLocalSnapshot(db, localNotes, states);

  if (outgoing.length) {
    const pushResult = await pushChanges(config, config.deviceId, outgoing);
    markAcceptedChanges(db, localNotesById, pushResult.accepted);
    markConflicts(db, pushResult.conflicts);
  }

  const sinceRevision = getRuntimeNumber(db, "last_pulled_revision", 0);
  const pullResult = await pullChanges(config, sinceRevision);

  handleRemoteChanges(db, config, pullResult.changes);
  setRuntimeNumber(db, "last_pulled_revision", pullResult.latest_revision);

  applyQueuedRemoteIfSafe(db, config);
}
