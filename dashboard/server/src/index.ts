import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { PRODUCT_NAME } from "../../shared/src/constants.js";
import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";
import { openDatabase } from "./db/database.js";

const config = loadConfig(process.env);
// SQLite creates the file, but not the folder that holds it.
mkdirSync(dirname(config.dbPath), { recursive: true });
const db = openDatabase(config.dbPath);
const app = await buildApp({ config, db });

// Closing the database flushes the WAL file, so a Ctrl+C never leaves a half-written database behind.
async function shutdown(code: number) {
  await app.close();
  db.close();
  process.exit(code);
}

process.once("SIGINT", () => void shutdown(0));
process.once("SIGTERM", () => void shutdown(0));

try {
  await app.listen({ port: config.port, host: config.host });
} catch (error) {
  const inUse = (error as NodeJS.ErrnoException).code === "EADDRINUSE";
  const reason = inUse
    ? `port ${config.port} is already in use; stop the other program or set AMETHYST_PORT`
    : error instanceof Error ? error.message : String(error);
  console.error(`Could not start on http://${config.host}:${config.port}: ${reason}`);
  await shutdown(1);
}

console.log(`${PRODUCT_NAME} server listening on http://${config.host}:${config.port}`);
