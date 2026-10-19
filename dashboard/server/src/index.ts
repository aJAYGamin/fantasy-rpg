import { PRODUCT_NAME } from "../../shared/src/constants.js";
import { buildApp } from "./app.js";
import { loadConfig } from "./config.js";

const config = loadConfig(process.env);
const app = await buildApp({ config });
await app.listen({ port: config.port, host: config.host });
console.log(`${PRODUCT_NAME} server listening on http://${config.host}:${config.port}`);
