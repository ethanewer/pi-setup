// pipeline.test.js — fluxline transformation-semantics tests.
//
// These run the real CLI on small inline fixtures. They pin the documented
// semantics (scales, drops, emit order, tolerant input handling); they are
// small by design and do not stress the working-set budget, which is
// enforced downstream by the CI memory probe.

import { test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { writeFile, readFile, mkdir, rm } from "node:fs/promises";

const HERE = new URL(".", import.meta.url).pathname;
const PROJECT = HERE + "../";
const WORK = "/tmp/fluxline-test";

const CFG = JSON.stringify({
  scales: { cpu: 10, mem: 1, net: 1000, disk: 2 },
  drops: [
    { sensor: "cpu", below: 5000 },
    { sensor: "net", above: 3000000 },
  ],
  emit: ["site", "ts", "sensor", "value"],
});

async function runPipeline(lines) {
  await mkdir(WORK, { recursive: true });
  const seq = `${process.pid}-${Math.random().toString(36).slice(2)}`;
  const inPath = `${WORK}/in-${seq}.ndjson`;
  const cfgPath = `${WORK}/cfg-${seq}.json`;
  const outPath = `${WORK}/out-${seq}.ndjson`;
  await writeFile(inPath, lines.join("\n") + "\n");
  await writeFile(cfgPath, CFG);
  const child = spawn(process.execPath,
    ["lib/pipeline.js", inPath, cfgPath, outPath], { cwd: PROJECT });
  const code = await new Promise((res) => child.on("exit", res));
  let out = "";
  if (code === 0) {
    out = await readFile(outPath, "utf8");
  }
  await rm(WORK, { recursive: true, force: true });
  return { code, out };
}

function records(text) {
  return text.trim() === "" ? [] : text.trim().split("\n").map(JSON.parse);
}

test("scales raw by the configured multiplier and emits in emit order", async () => {
  const { code, out } = await runPipeline([
    '{"site":"A","ts":1,"sensor":"cpu","raw":600}',
    '{"site":"B","ts":2,"sensor":"net","raw":42}',
  ]);
  assert.equal(code, 0);
  assert.deepEqual(records(out), [
    { site: "A", ts: 1, sensor: "cpu", value: 6000 },
    { site: "B", ts: 2, sensor: "net", value: 42000 },
  ]);
});

test("unknown sensors and rows missing emit keys are dropped", async () => {
  const { code, out } = await runPipeline([
    '{"site":"A","ts":1,"sensor":"therm","raw":600}', // not in scales
    '{"site":"A","sensor":"cpu","raw":600}',     // no ts -> emit key missing
    '{"ts":3,"sensor":"cpu","raw":600}',              // no site -> emit key missing
    '{"site":"A","ts":4,"sensor":"cpu","raw":501}',
  ]);
  assert.equal(code, 0);
  assert.deepEqual(records(out), [{ site: "A", ts: 4, sensor: "cpu", value: 5010 }]);
});

test("blank and malformed lines are skipped", async () => {
  const { code, out } = await runPipeline([
    "",
    "   ",
    "{ this is not json",
    '{"site":"A","ts":5,"sensor":"cpu","raw":501}',
  ]);
  assert.equal(code, 0);
  assert.deepEqual(records(out), [{ site: "A", ts: 5, sensor: "cpu", value: 5010 }]);
});

test("drop rules apply to the normalized value with strict boundaries", async () => {
  const { code, out } = await runPipeline([
    '{"site":"A","ts":1,"sensor":"cpu","raw":499}',  // 4990 < 5000 -> dropped
    '{"site":"A","ts":2,"sensor":"cpu","raw":500}',  // 5000 == below  -> kept
    '{"site":"A","ts":3,"sensor":"net","raw":2999}', // 2999000 < 3M   -> kept
    '{"site":"A","ts":4,"sensor":"net","raw":3000}', // 3000000 == above -> kept
    '{"site":"A","ts":5,"sensor":"net","raw":3001}', // > 3M -> dropped
  ]);
  assert.equal(code, 0);
  assert.deepEqual(records(out), [
    { site: "A", ts: 2, sensor: "cpu", value: 5000 },
    { site: "A", ts: 3, sensor: "net", value: 2999000 },
    { site: "A", ts: 4, sensor: "net", value: 3000000 },
  ]);
});

test("output is deterministic for identical inputs", async () => {
  const lines = [
    '{"site":"A","ts":1,"sensor":"cpu","raw":600}',
    '{"site":"B","ts":2,"sensor":"mem","raw":777}',
  ];
  const a = await runPipeline(lines);
  const b = await runPipeline(lines);
  assert.equal(a.code, 0);
  assert.equal(b.code, 0);
  assert.equal(a.out, b.out);
});

test("config with no drops and a different emit list is honored", async () => {
  await mkdir(WORK, { recursive: true });
  const seq = `${process.pid}-${Math.random().toString(36).slice(2)}`;
  const inPath = `${WORK}/in-${seq}.ndjson`;
  const cfgPath = `${WORK}/cfg-${seq}.json`;
  const outPath = `${WORK}/out-${seq}.ndjson`;
  await writeFile(inPath, '{"site":"C","ts":9,"sensor":"mem","raw":123}\n');
  await writeFile(cfgPath, JSON.stringify({
    scales: { mem: 4 },
    emit: ["sensor", "ts", "value"],
  }));
  const child = spawn(process.execPath,
    ["lib/pipeline.js", inPath, cfgPath, outPath], { cwd: PROJECT });
  const code = await new Promise((res) => child.on("exit", res));
  assert.equal(code, 0);
  const out = await readFile(outPath, "utf8");
  assert.deepEqual(records(out), [{ sensor: "mem", ts: 9, value: 492 }]);
  await rm(WORK, { recursive: true, force: true });
});