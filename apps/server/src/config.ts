import dotenv from "dotenv";

dotenv.config();

export interface ServerConfig {
  host: string;
  port: number;
  dbPath: string;
  tokenSalt: string;
}

function envOrDefault(name: string, fallback: string): string {
  return process.env[name] && process.env[name]?.trim() ? String(process.env[name]) : fallback;
}

function mustEnv(name: string, fallback?: string): string {
  const value = fallback ? envOrDefault(name, fallback) : process.env[name];
  if (!value || !value.trim()) {
    throw new Error(`Missing environment variable: ${name}`);
  }
  return value;
}

export function loadConfig(): ServerConfig {
  return {
    host: envOrDefault("SYNCANTINOTE_SERVER_HOST", "127.0.0.1"),
    port: Number(envOrDefault("SYNCANTINOTE_SERVER_PORT", "3177")),
    dbPath: mustEnv("SYNCANTINOTE_SERVER_DB_PATH", "/var/lib/syncantinote/server.sqlite3"),
    tokenSalt: mustEnv("SYNCANTINOTE_TOKEN_SALT", "replace-me")
  };
}
