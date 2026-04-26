import type { HelperConfig } from "../config.js";
import type { PullChange, PushChange } from "../types.js";

interface PushResponse {
  accepted: Array<{ note_id: string; server_revision: number }>;
  conflicts: Array<{
    note_id: string;
    expected_revision: number;
    actual_revision: number;
    remote_content: string | null;
    remote_title: string | null;
    remote_deleted_at: string | null;
  }>;
}

interface PullResponse {
  since_revision: number;
  latest_revision: number;
  changes: PullChange[];
}

function authHeaders(config: HelperConfig): HeadersInit {
  return {
    "Content-Type": "application/json",
    Authorization: `Bearer ${config.apiToken}`
  };
}

export async function pushChanges(
  config: HelperConfig,
  deviceId: string,
  changes: PushChange[]
): Promise<PushResponse> {
  const response = await fetch(`${config.apiBaseUrl}/sync/push`, {
    method: "POST",
    headers: authHeaders(config),
    body: JSON.stringify({
      device_id: deviceId,
      changes
    })
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Push failed (${response.status}): ${text}`);
  }

  return (await response.json()) as PushResponse;
}

export async function pullChanges(config: HelperConfig, sinceRevision: number): Promise<PullResponse> {
  const response = await fetch(`${config.apiBaseUrl}/sync/pull?since_revision=${sinceRevision}`, {
    method: "GET",
    headers: authHeaders(config)
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Pull failed (${response.status}): ${text}`);
  }

  return (await response.json()) as PullResponse;
}
