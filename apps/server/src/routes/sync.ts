import type Database from "better-sqlite3";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { requireDeviceAuth, upsertDevice } from "../auth.js";
import type { ServerConfig } from "../config.js";
import type { DbChange, DbNote } from "../db/database.js";
import type { PushRequestBody } from "../types.js";

interface AcceptedPushResult {
  note_id: string;
  server_revision: number;
}

interface ConflictPushResult {
  note_id: string;
  expected_revision: number;
  actual_revision: number;
  remote_content: string | null;
  remote_title: string | null;
  remote_deleted_at: string | null;
}

function toIsoNow(): string {
  return new Date().toISOString();
}

function hasValidEnrollmentKey(request: FastifyRequest, config: ServerConfig): boolean {
  if (!config.enrollmentKey) {
    return true;
  }

  const candidate = request.headers["x-syncantinote-enrollment-key"];
  if (typeof candidate === "string") {
    return candidate === config.enrollmentKey;
  }
  if (Array.isArray(candidate)) {
    return candidate.includes(config.enrollmentKey);
  }
  return false;
}

function parsePushBody(body: unknown): PushRequestBody {
  if (!body || typeof body !== "object") {
    throw new Error("Invalid push body");
  }

  const parsed = body as { device_id?: unknown; changes?: unknown };
  if (!parsed.device_id || typeof parsed.device_id !== "string") {
    throw new Error("Invalid device_id");
  }

  if (!Array.isArray(parsed.changes)) {
    throw new Error("Invalid changes");
  }

  return {
    device_id: parsed.device_id,
    changes: parsed.changes.map((candidateUnknown) => {
      if (!candidateUnknown || typeof candidateUnknown !== "object") {
        throw new Error("Invalid change entry");
      }

      const candidate = candidateUnknown as Record<string, unknown>;
      if (typeof candidate.note_id !== "string") {
        throw new Error("Missing note_id");
      }

      if (candidate.operation !== "upsert" && candidate.operation !== "delete") {
        throw new Error("Invalid operation");
      }

      if (typeof candidate.base_server_revision !== "number") {
        throw new Error("Missing base_server_revision");
      }

      return {
        note_id: candidate.note_id,
        operation: candidate.operation,
        base_server_revision: candidate.base_server_revision,
        content: typeof candidate.content === "string" ? candidate.content : undefined,
        title: typeof candidate.title === "string" ? candidate.title : null,
        local_updated_at: typeof candidate.local_updated_at === "string" ? candidate.local_updated_at : undefined,
        deleted_at: typeof candidate.deleted_at === "string" ? candidate.deleted_at : null
      };
    })
  };
}

export async function registerSyncRoutes(
  app: FastifyInstance,
  db: Database.Database,
  config: ServerConfig
): Promise<void> {
  app.post("/auth/device", async (request: FastifyRequest, reply: FastifyReply) => {
    if (!hasValidEnrollmentKey(request, config)) {
      return reply.code(401).send({ error: "Invalid enrollment key" });
    }

    const body = request.body as { device_id?: string; device_name?: string };
    if (!body?.device_id || !body?.device_name) {
      return reply.code(400).send({ error: "device_id and device_name are required" });
    }

    const token = upsertDevice(db, config, body.device_id, body.device_name);
    return reply.send({
      device_id: body.device_id,
      token,
      issued_at: toIsoNow()
    });
  });

  app.post("/sync/push", async (request: FastifyRequest, reply: FastifyReply) => {
    const authedDevice = requireDeviceAuth(request, reply, db, config);
    if (!authedDevice) {
      return;
    }

    let body: PushRequestBody;
    try {
      body = parsePushBody(request.body);
    } catch (error) {
      return reply.code(400).send({ error: (error as Error).message });
    }

    if (body.device_id !== authedDevice.id) {
      return reply.code(403).send({ error: "device_id does not match authenticated token" });
    }

    const accepted: AcceptedPushResult[] = [];
    const conflicts: ConflictPushResult[] = [];

    const applyOne = db.transaction((change: PushRequestBody["changes"][number]) => {
      const existing = db
        .prepare(
          "SELECT id, content, title, created_at, updated_at, deleted_at, server_revision, updated_by_device FROM notes WHERE id = ?"
        )
        .get(change.note_id) as DbNote | undefined;

      const currentRevision = existing?.server_revision ?? 0;

      if (currentRevision !== change.base_server_revision) {
        conflicts.push({
          note_id: change.note_id,
          expected_revision: change.base_server_revision,
          actual_revision: currentRevision,
          remote_content: existing?.content ?? null,
          remote_title: existing?.title ?? null,
          remote_deleted_at: existing?.deleted_at ?? null
        });
        return;
      }

      const now = toIsoNow();
      const changeOperation = change.operation;

      const insertion = db
        .prepare(
          `
          INSERT INTO changes (note_id, operation, content, title, changed_at, changed_by_device, deleted_at)
          VALUES (@note_id, @operation, @content, @title, @changed_at, @changed_by_device, @deleted_at)
          `
        )
        .run({
          note_id: change.note_id,
          operation: changeOperation,
          content: changeOperation === "delete" ? null : change.content ?? "",
          title: changeOperation === "delete" ? null : (change.title ?? null),
          changed_at: now,
          changed_by_device: authedDevice.id,
          deleted_at: changeOperation === "delete" ? (change.deleted_at ?? now) : null
        });

      const newRevision = Number(insertion.lastInsertRowid);

      if (changeOperation === "delete") {
        db.prepare(
          `
          INSERT INTO notes (id, content, title, created_at, updated_at, deleted_at, server_revision, updated_by_device)
          VALUES (@id, '', NULL, @created_at, @updated_at, @deleted_at, @server_revision, @updated_by_device)
          ON CONFLICT(id) DO UPDATE SET
            updated_at = excluded.updated_at,
            deleted_at = excluded.deleted_at,
            server_revision = excluded.server_revision,
            updated_by_device = excluded.updated_by_device
          `
        ).run({
          id: change.note_id,
          created_at: existing?.created_at ?? now,
          updated_at: now,
          deleted_at: change.deleted_at ?? now,
          server_revision: newRevision,
          updated_by_device: authedDevice.id
        });
      } else {
        db.prepare(
          `
          INSERT INTO notes (id, content, title, created_at, updated_at, deleted_at, server_revision, updated_by_device)
          VALUES (@id, @content, @title, @created_at, @updated_at, NULL, @server_revision, @updated_by_device)
          ON CONFLICT(id) DO UPDATE SET
            content = excluded.content,
            title = excluded.title,
            updated_at = excluded.updated_at,
            deleted_at = NULL,
            server_revision = excluded.server_revision,
            updated_by_device = excluded.updated_by_device
          `
        ).run({
          id: change.note_id,
          content: change.content ?? "",
          title: change.title ?? null,
          created_at: existing?.created_at ?? now,
          updated_at: now,
          server_revision: newRevision,
          updated_by_device: authedDevice.id
        });
      }

      accepted.push({
        note_id: change.note_id,
        server_revision: newRevision
      });
    });

    for (const change of body.changes) {
      applyOne(change);
    }

    return reply.send({
      accepted,
      conflicts
    });
  });

  app.get("/sync/pull", async (request: FastifyRequest, reply: FastifyReply) => {
    const device = requireDeviceAuth(request, reply, db, config);
    if (!device) {
      return;
    }

    const query = request.query as { since_revision?: string; limit?: string };
    const sinceRevision = Number(query.since_revision ?? "0");
    const limit = Math.min(500, Math.max(1, Number(query.limit ?? "200")));

    if (Number.isNaN(sinceRevision) || sinceRevision < 0) {
      return reply.code(400).send({ error: "Invalid since_revision" });
    }

    const changes = db
      .prepare(
        `
        SELECT revision, note_id, operation, content, title, changed_at, changed_by_device, deleted_at
        FROM changes
        WHERE revision > ?
        ORDER BY revision ASC
        LIMIT ?
        `
      )
      .all(sinceRevision, limit) as DbChange[];

    return reply.send({
      since_revision: sinceRevision,
      latest_revision: changes.length ? changes[changes.length - 1].revision : sinceRevision,
      changes
    });
  });

  app.post("/sync/ack", async (request: FastifyRequest, reply: FastifyReply) => {
    const device = requireDeviceAuth(request, reply, db, config);
    if (!device) {
      return;
    }

    const body = request.body as { revision?: number };
    if (typeof body?.revision !== "number") {
      return reply.code(400).send({ error: "revision is required" });
    }

    return reply.send({ ok: true, device_id: device.id, revision: body.revision });
  });
}
