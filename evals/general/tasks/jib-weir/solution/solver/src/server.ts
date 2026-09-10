// server.ts — entrypoint: `node dist/src/server.js [PORT] [DATA_FILE]`.
// The oracle and /app/start.sh invoke this. The server binds to loopback (the
// trial container runs with no external network).
import { readFileSync } from "fs";
import path from "path";
import { createApp } from "./app";
import type { MediaCreate } from "./schemas";

const args = process.argv.slice(2);
const port = Number(args[0]) || 8780;
const dataPath = args[1] || "/app/data/media.json";

const openapiPath = path.join(__dirname, "..", "..", "openapi.json");
const openapiDoc = readFileSync(openapiPath);

let seed: MediaCreate[] = [];
try {
  const raw = JSON.parse(readFileSync(dataPath, "utf8"));
  if (!Array.isArray(raw.items)) {
    throw new Error("dataset root must be an object with an items array");
  }
  seed = raw.items as MediaCreate[];
} catch (err) {
  console.error(`cannot read dataset ${dataPath}:`, err);
  process.exit(1);
}

const app = createApp(seed, openapiDoc);
app.listen(port, "127.0.0.1", () => {
  console.log(`catalogue listening on http://127.0.0.1:${port} (${seed.length} items)`);
});