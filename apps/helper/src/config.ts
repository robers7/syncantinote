import dotenv from "dotenv";
import path from "node:path";

dotenv.config();

export interface HelperConfig {
  deviceId: string;
  deviceName: string;
  apiBaseUrl: string;
  apiToken: string;
  antinoteDbPath: string;
  helperDbPath: string;
  pollIntervalMs: number;
}

function mustEnv(name: string): string {
  const value = process.env[name];
  if (!value || !value.trim()) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function withHome(expandedPath: string): string {
  if (expandedPath.startsWith("$HOME")) {
    const home = process.env.HOME;
    if (!home) {
      throw new Error("$HOME is not set");
    }
    return expandedPath.replace("$HOME", home);
  }
  return expandedPath;
}

export function loadConfig(): HelperConfig {
  const antinoteDb = withHome(mustEnv("SYNCANTINOTE_ANTINOTE_DB_PATH"));
  const helperDb = withHome(mustEnv("SYNCANTINOTE_HELPER_DB_PATH"));

  return {
    deviceId: mustEnv("SYNCANTINOTE_DEVICE_ID"),
    deviceName: process.env.SYNCANTINOTE_DEVICE_NAME?.trim() || "Unknown Device",
    apiBaseUrl: mustEnv("SYNCANTINOTE_API_BASE_URL").replace(/\/$/, ""),
    apiToken: mustEnv("SYNCANTINOTE_API_TOKEN"),
    antinoteDbPath: path.resolve(antinoteDb),
    helperDbPath: path.resolve(helperDb),
    pollIntervalMs: Number(process.env.SYNCANTINOTE_POLL_INTERVAL_MS || "30000")
  };
}
