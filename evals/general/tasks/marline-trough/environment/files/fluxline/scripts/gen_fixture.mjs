// gen_fixture.mjs — deterministic NDJSON workload generator for fluxline.
//
//   node scripts/gen_fixture.mjs <seed> <rows> <output.ndjson> [sensor_set]
//
// sensor_set is one of "standard" (default), "plant", "grid". The output is
// fully deterministic for a given (seed, rows, sensor_set); it writes
// well-formed NDJSON records plus a sprinkling of blank lines, malformed
// lines, unknown-sensor rows, and rows missing the "site" field, so the
// pipeline's documented tolerant behavior is exercised.

const SITES = ["A", "B", "C", "D", "E"];

const SENSOR_SETS = {
  standard: { cpu: [120, 920], mem: [40, 960], net: [120, 4000], disk: [10, 900] },
  plant: { temp: [150, 210], volt: [220, 1400], flow: [300, 1200], press: [100, 400] },
  grid: { freq: [480, 520], load: [10, 900], solar: [0, 700], wind: [0, 900] },
};

class Rng {
  constructor(seed) {
    this.state = seed & 0x7fffffff;
    if (this.state === 0) this.state = 0x9e3779b9;
  }
  next() {
    // LCG (Numerical Recipes constants); low 31 bits stay exactly representable.
    this.state = (Math.imul(this.state, 1664525) + 1013904223) & 0x7fffffff;
    return this.state;
  }
  int(lo, hi) {
    return lo + (this.next() % (hi - lo + 1));
  }
  pick(arr) {
    return arr[this.next() % arr.length];
  }
  chance(den) {
    return this.next() % den === 0;
  }
}

function usage() {
  console.error("usage: node scripts/gen_fixture.mjs <seed> <rows> <output.ndjson> [sensor_set]");
  process.exit(2);
}

async function main() {
  if (process.argv.length < 5) usage();
  const seed = Number(process.argv[2]);
  const rows = Number(process.argv[3]);
  const outPath = process.argv[4];
  const setName = process.argv[5] || "standard";
  const ranges = SENSOR_SETS[setName];
  if (!ranges || !Number.isInteger(seed) || !Number.isInteger(rows) || rows < 1) usage();

  const sensors = Object.keys(ranges);
  const rng = new Rng(seed);
  const fs = await import("node:fs/promises");
  let ts = 1_700_000_000;
  const enc = new TextEncoder();
  const chunk = new Uint8Array(1 << 20);

  let pos = 0;

  const fh = await fs.open(outPath, "w");
  const flush = async () => {
    if (pos > 0) {
      await fh.write(chunk.subarray(0, pos));
      pos = 0;
    }
  };
  // happily buffer one small line at a time into a 1 MiB chunk
  const transcribe = async (s) => {
    const b = enc.encode(s);
    if (pos + b.length > chunk.length) await flush();
    chunk.set(b, pos);
    pos += b.length;
  };
  try {
    for (let i = 0; i < rows; i++) {
      if (rng.chance(50)) {
        await transcribe("\n"); // blank line
        continue;
      }
      if (rng.chance(100)) {
        await transcribe("{ this is not json\n"); // malformed line
        continue;
      }
      const unknown = rng.chance(50);
      const sensor = unknown ? "therm" : rng.pick(sensors);
      const known = ranges[sensor] ? ranges[sensor] : ranges[rng.pick(sensors)];
      const lo = known[0];
      const hi = known[1];
      const raw = rng.int(lo, hi);
      const site = rng.pick(SITES);
      ts += rng.int(1, 5);
      // 1 in 200 rows is missing the "site" field (dropped by the pipeline)
      if (rng.chance(200)) {
        await transcribe(`{"ts":${ts},"sensor":"${sensor}","raw":${raw},"unit":"u"}\n`);
      } else {
        await transcribe(`{"site":"${site}","ts":${ts},"sensor":"${sensor}","raw":${raw},"unit":"u"}\n`);
      }
    }
    await flush();
  } finally {
    await fh.close();
  }
}

await main();