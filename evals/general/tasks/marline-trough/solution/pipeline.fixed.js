// pipeline.js — fluxline entrypoint.
//
//   node lib/pipeline.js <input.ndjson> <config.json> <output.ndjson>
//
// Reads the NDJSON input as a stream, normalizes every record through
// lib/transform.js, and streams the NDJSON output, awaiting each write so
// the OS-level write backpressure propagates all the way up to the input
// stream. Exit codes: 0 ok, 1 runtime error, 2 usage/config error.

import { createReadStream, createWriteStream } from "node:fs";
import { createInterface } from "node:readline";
import { loadConfig } from "./config.js";
import { transform } from "./transform.js";

const USAGE =
  "usage: node lib/pipeline.js <input.ndjson> <config.json> <output.ndjson>";

async function main() {
  if (process.argv.length !== 5) {
    console.error(USAGE);
    process.exitCode = 2;
    return;
  }
  const [inPath, configPath, outPath] = process.argv.slice(2);

  const cfg = await loadConfig(configPath);

  const lines = createInterface({ input: createReadStream(inPath) });
  const out = createWriteStream(outPath);

  let n = 0;
  for await (const rec of transform(lines, cfg)) {
    await out.write(JSON.stringify(rec) + "\n");
    n++;
  }

  out.end();
  await out.close();
  console.error(`fluxline: ${process.argv[1]} -> ${outPath} (${n} records)`);
}

try {
  await main();
} catch (err) {
  console.error(`fluxline: ${err.message}`);
  process.exitCode = 1;
}
