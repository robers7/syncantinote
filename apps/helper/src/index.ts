import { loadConfig } from "./config.js";
import { openHelperDatabase } from "./db/database.js";
import { runSyncIteration } from "./services/syncEngine.js";

async function main(): Promise<void> {
  const config = loadConfig();
  const db = openHelperDatabase(config.helperDbPath);

  console.log(`[syncantinote-helper] started for device ${config.deviceId}`);

  const run = async (): Promise<void> => {
    try {
      await runSyncIteration(db, config);
      console.log(`[syncantinote-helper] sync iteration ok at ${new Date().toISOString()}`);
    } catch (error) {
      console.error("[syncantinote-helper] sync iteration failed", error);
    }
  };

  await run();
  setInterval(() => {
    void run();
  }, config.pollIntervalMs);
}

main().catch((error) => {
  console.error("Fatal helper startup error", error);
  process.exit(1);
});
