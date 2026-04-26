import crypto from "node:crypto";
import type Database from "better-sqlite3";
import type { FastifyReply, FastifyRequest } from "fastify";
import type { ServerConfig } from "./config.js";
import type { DbDevice } from "./db/database.js";

export function hashToken(token: string, salt: string): string {
  return crypto.createHash("sha256").update(`${salt}:${token}`).digest("hex");
}

export function issueToken(): string {
  return crypto.randomBytes(32).toString("hex");
}

export function upsertDevice(
  db: Database.Database,
  config: ServerConfig,
  deviceId: string,
  deviceName: string
): string {
  const token = issueToken();
  const tokenHash = hashToken(token, config.tokenSalt);
  const now = new Date().toISOString();

  db.prepare(
    `
    INSERT INTO devices (id, name, token_hash, created_at, last_seen_at)
    VALUES (@id, @name, @token_hash, @created_at, @last_seen_at)
    ON CONFLICT(id) DO UPDATE SET
      name = excluded.name,
      token_hash = excluded.token_hash,
      last_seen_at = excluded.last_seen_at
    `
  ).run({
    id: deviceId,
    name: deviceName,
    token_hash: tokenHash,
    created_at: now,
    last_seen_at: now
  });

  return token;
}

export function findDeviceByToken(
  db: Database.Database,
  config: ServerConfig,
  token: string
): DbDevice | undefined {
  const tokenHash = hashToken(token, config.tokenSalt);
  return db
    .prepare("SELECT id, name, token_hash, created_at, last_seen_at FROM devices WHERE token_hash = ?")
    .get(tokenHash) as DbDevice | undefined;
}

export function touchDevice(db: Database.Database, deviceId: string): void {
  db.prepare("UPDATE devices SET last_seen_at = ? WHERE id = ?").run(new Date().toISOString(), deviceId);
}

export function extractBearerToken(request: FastifyRequest): string | null {
  const auth = request.headers.authorization;
  if (!auth) return null;

  const [scheme, token] = auth.split(" ");
  if (!scheme || !token) return null;
  if (scheme.toLowerCase() !== "bearer") return null;

  return token;
}

export function requireDeviceAuth(
  request: FastifyRequest,
  reply: FastifyReply,
  db: Database.Database,
  config: ServerConfig
): DbDevice | null {
  const token = extractBearerToken(request);
  if (!token) {
    void reply.code(401).send({ error: "Missing bearer token" });
    return null;
  }

  const device = findDeviceByToken(db, config, token);
  if (!device) {
    void reply.code(401).send({ error: "Invalid token" });
    return null;
  }

  touchDevice(db, device.id);
  return device;
}
