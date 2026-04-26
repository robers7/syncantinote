import Fastify from "fastify";
import { loadConfig } from "./config.js";
import { openDatabase } from "./db/database.js";
import { registerHealthRoutes } from "./routes/health.js";
import { registerSyncRoutes } from "./routes/sync.js";

async function main(): Promise<void> {
  const config = loadConfig();
  const db = openDatabase(config.dbPath);

  const app = Fastify({ logger: true });

  await registerHealthRoutes(app);
  await registerSyncRoutes(app, db, config);

  await app.listen({ host: config.host, port: config.port });
  app.log.info(`syncantinote server listening on ${config.host}:${config.port}`);
}

main().catch((error) => {
  console.error("Fatal server startup error", error);
  process.exit(1);
});
