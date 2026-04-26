export type SyncOperation = "upsert" | "delete";

export interface LocalNote {
  id: string;
  content: string;
  title: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface ShadowNoteState {
  note_id: string;
  last_seen_hash: string;
  last_seen_updated_at: string | null;
  last_synced_server_revision: number;
  dirty_status: "clean" | "dirty";
  pending_conflict: number;
}

export interface PushChange {
  note_id: string;
  operation: SyncOperation;
  base_server_revision: number;
  content?: string;
  title?: string | null;
  local_updated_at?: string;
  deleted_at?: string | null;
}

export interface PullChange {
  revision: number;
  note_id: string;
  operation: SyncOperation;
  content: string | null;
  title: string | null;
  changed_at: string;
  changed_by_device: string;
  deleted_at: string | null;
}
