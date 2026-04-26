export type SyncOperation = "upsert" | "delete";

export interface PushChange {
  note_id: string;
  operation: SyncOperation;
  base_server_revision: number;
  content?: string;
  title?: string | null;
  local_updated_at?: string;
  deleted_at?: string | null;
}

export interface PushRequestBody {
  device_id: string;
  changes: PushChange[];
}

export interface PullResponseChange {
  revision: number;
  note_id: string;
  operation: SyncOperation;
  content: string | null;
  title: string | null;
  changed_at: string;
  changed_by_device: string;
  deleted_at: string | null;
}
