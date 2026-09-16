# -*- coding: utf-8 -*-
"""vitest suite part 2: records, telemetry, ledger, tariffs, hydraulics,
leak, forecast, pressure and reports."""

TT2 = [
    ("tests/records.test.ts", '''// records.test.ts - raw record readers.

import { describe, expect, it } from "vitest";
import {
  readStr,
  readNum,
  readFlag,
  hasField,
  validateRecordKeys,
  missingFields,
  requireFields,
  pickFields,
  fieldCount,
  type RawRecord,
} from "../src/data/records.js";

describe("record readers", () => {
  it("reads strings", () => {
    expect(readStr({ a: " x " }, "a")).toBe("x");
    expect(readStr({ a: "" }, "a")).toBe(undefined);
    expect(readStr({ a: 5 }, "a")).toBe(undefined);
    expect(readStr({}, "a")).toBe(undefined);
  });

  it("reads numbers", () => {
    expect(readNum({ a: 2.5 }, "a")).toBe(2.5);
    expect(readNum({ a: "3.5" }, "a")).toBe(3.5);
    expect(readNum({ a: "nan" }, "a")).toBe(undefined);
    expect(readNum({ a: Infinity }, "a")).toBe(undefined);
  });

  it("reads flags", () => {
    expect(readFlag({ a: 1 }, "a", false)).toBe(true);
    expect(readFlag({ a: "yes" }, "a", false)).toBe(true);
    expect(readFlag({ a: "no" }, "a", true)).toBe(false);
    expect(readFlag({}, "a", true)).toBe(true);
    expect(readFlag({ a: "maybe" }, "a", false)).toBe(false);
  });

  it("tests presence and key grammar", () => {
    expect(hasField({ a: undefined }, "a")).toBe(false);
    expect(hasField({ a: 0 }, "a")).toBe(true);
    expect(validateRecordKeys({ good_1: 1 })).toBe(true);
    expect(validateRecordKeys({ "bad-key": 1 })).toBe(false);
  });

  it("reports and requires fields", () => {
    const rec: RawRecord = { a: 1 };
    expect(missingFields(rec, ["a", "b"])).toEqual(["b"]);
    requireFields({ a: 1, b: 2 }, ["a", "b"]);
    expect(() => requireFields(rec, ["a", "b"])).toThrow();
  });

  it("picks fields and counts them", () => {
    const rec: RawRecord = { a: 1, b: "x", c: 2 };
    expect(pickFields(rec, ["a", "c"])).toEqual({ a: 1, c: 2 });
    expect(fieldCount(rec)).toBe(3);
    expect(fieldCount({})).toBe(0);
  });
});

'''),
    ("tests/telemetry.test.ts", '''// telemetry.test.ts - timelines, gap filling, statistics.

import { describe, expect, it } from "vitest";
import { toTimeline, fillGaps, mean, stdev, rollingMean, meanFlow, type Reading } from "../src/data/telemetry.js";
import { type RawRecord } from "../src/data/records.js";

function recs(): RawRecord[] {
  return [
    { kind: "reading", instant: 0, flow: 10, pressure: 4, quality: 99 },
    { kind: "reading", instant: 3600, flow: 20 },
    { kind: "reading", instant: 7200, flow: 30, pressure: 3.5 },
    { kind: "other", instant: 9999 },
  ];
}

describe("telemetry", () => {
  it("builds and dedupes timelines", () => {
    const tl = toTimeline(recs());
    expect(tl.length).toBe(3);
    expect(tl[0]?.pressure).toBe(4);
    expect(tl[1]?.pressure).toBe(0);
  });

  it("fills long gaps with interpolation", () => {
    const tl = toTimeline(recs());
    const filled = fillGaps(tl, 1000);
    expect(filled.length).toBeGreaterThan(tl.length);
    expect(filled[0]?.flow).toBe(10);
  });

  it("computes statistics", () => {
    expect(mean([2, 4, 6])).toBe(4);
    expect(mean([])).toBe(0);
    expect(stdev([2, 4, 6])).toBeCloseTo(2, 10);
    expect(stdev([1])).toBe(0);
  });

  it("computes a rolling mean", () => {
    const tl: Reading[] = [
      { instant: 0, flow: 10, pressure: 1, quality: 1 },
      { instant: 1, flow: 20, pressure: 1, quality: 1 },
      { instant: 2, flow: 30, pressure: 1, quality: 1 },
    ];
    expect(rollingMean(tl, 1)).toEqual([15, 20, 25]);
  });

  it("mean flow over raw records", () => {
    expect(meanFlow(recs())).toBe(20);
  });
});

'''),
    ("tests/ledger.test.ts", '''// ledger.test.ts - register segments, volumes, meters.

import { describe, expect, it } from "vitest";
import {
  parseMeter,
  buildSegments,
  totalVolume,
  medianVolume,
  crossingCount,
  peakSegment,
  busiestMeter,
  type Register,
  type Segment,
} from "../src/data/ledger.js";

const READS: readonly Register[] = [
  { instant: 0, register: 0 },
  { instant: 86400, register: 100 },
  { instant: 172800, register: 250 },
  { instant: 259200, register: 250 }, // reset
  { instant: 345600, register: 40 },
];

describe("ledger", () => {
  it("parses meter records", () => {
    const m = parseMeter({ serial: "M1", district: "north", unit: "litre" });
    expect(m.serial).toBe("M1");
    expect(m.unit).toBe("litre");
    expect(m.installedDay).toBe(1);
    const fallback = parseMeter({ serial: "M2", district: "south" });
    expect(fallback.unit).toBe(null);
  });

  it("builds segments handling resets", () => {
    const segs = buildSegments(READS, 172800);
    expect(segs.length).toBe(3);
  });

  it("totals volume across segments", () => {
    const segs = buildSegments(READS, 172800);
    expect(totalVolume(segs)).toBe(250);
  });

  it("splits long spans", () => {
    const wide: Register[] = [
      { instant: 0, register: 0 },
      { instant: 86400 * 10, register: 400 },
    ];
    const segs = buildSegments(wide, 86400);
    expect(segs.length).toBe(2);
    expect(totalVolume(segs)).toBe(400);
  });

  it("median and peaks", () => {
    const segs = buildSegments(READS, 172800);
    expect(medianVolume(segs)).toBeGreaterThan(0);
    expect(peakSegment(segs)).toBe(150);
    expect(crossingCount(segs, 86400)).toBe(1);
  });

  it("finds the busiest meter", () => {
    const meters = [
      { serial: "a", district: "north", unit: null, installedDay: 1 },
      { serial: "b", district: "north", unit: null, installedDay: 1 },
    ];
    const segments = new Map<string, readonly Segment[]>([
      ["a", buildSegments(READS, 172800)],
    ]);
    expect(busiestMeter(meters, segments)).toBe("a");
  });
});

'''),
    ("tests/tariffs.test.ts", '''// tariffs.test.ts - tiered pricing.

import { describe, expect, it } from "vitest";
import {
  tariffFromRows,
  priceForVolume,
  reachesTopTier,
  averagePrice,
  lookupTariff,
  type Tariff,
} from "../src/data/tariffs.js";
import { type RawRecord } from "../src/data/records.js";

const ROWS: RawRecord[] = [
  { upTo: 10, price: 100 },
  { upTo: 20, price: 150 },
  { upTo: 0, price: 0 },
  { upTo: 50, price: 200 },
];

describe("tariffs", () => {
  it("builds sorted tables", () => {
    const t = tariffFromRows("north", "summer", ROWS);
    expect(t.tiers.length).toBe(4);
  });

  it("prices volumes by tier", () => {
    const t = tariffFromRows("north", "summer", ROWS);
    expect(priceForVolume(t, 5)).toBe(500);
    expect(priceForVolume(t, 15)).toBe(1750);
    expect(priceForVolume(t, 25)).toBe(3500);
    expect(priceForVolume(t, 0)).toBe(0);
  });

  it("clips boundaries and computes averages", () => {
    const t = tariffFromRows("north", "summer", ROWS);
    expect(reachesTopTier(t, 100)).toBe(true);
    expect(reachesTopTier(t, 5)).toBe(false);
    expect(averagePrice(t, 10)).toBe(100);
  });

  it("looks tariffs up by district and season", () => {
    const tables: Tariff[] = [tariffFromRows("north", "summer", ROWS)];
    expect(lookupTariff(tables, "north", "summer")?.tiers.length).toBe(4);
    expect(lookupTariff(tables, "north", "winter")).toBe(undefined);
  });
});

'''),
]


TT2 += [
    ("tests/hydraulics.test.ts", '''// hydraulics.test.ts - flow balance and pressure.

import { describe, expect, it } from "vitest";
import { Network, type NodeSpec, type LinkSpec } from "../src/model/network.js";
import { solveBalance, pressureAt, nodeOutflow } from "../src/algo/hydraulics.js";

function smallNet(): Network {
  const nodes: NodeSpec[] = [
    { id: "r", kind: "reservoir", label: "R", capacity: 1000, level: 900, point: null },
    { id: "j", kind: "junction", label: "J", capacity: 100, level: 0, point: null },
  ];
  const links: LinkSpec[] = [{ from: "r", to: "j", lengthM: 500, diameterMm: 200, roughness: 110 }];
  return new Network(nodes, links);
}

describe("hydraulics", () => {
  it("produces a deterministic flow state", () => {
    const net = smallNet();
    const demands = new Map([["j", 25]]);
    const state = solveBalance(net, demands, 40);
    expect(state.iterations).toBe(40);
    expect(state.converged).toBe(true);
    expect(nodeOutflow(state, "r", net)).toBeGreaterThanOrEqual(0);
  });

  it("estimates pressure from level", () => {
    expect(pressureAt(100, 0)).toBeCloseTo(9.8, 1);
    expect(pressureAt(10, 100)).toBe(0);
  });
});

'''),
    ("tests/leak.test.ts", '''// leak.test.ts - night-flow leak detection.

import { describe, expect, it } from "vitest";
import { baselineNightFlow, evaluateArea, alertedAreas, type LeakSample } from "../src/algo/leak.js";

const SAMPLES: LeakSample[] = [
  { instant: 1, area: "north", nightFlow: 10 },
  { instant: 2, area: "north", nightFlow: 12 },
  { instant: 3, area: "north", nightFlow: 11 },
  { instant: 4, area: "north", nightFlow: 40 },
  { instant: 5, area: "south", nightFlow: 8 },
];

describe("leak detection", () => {
  it("baselines from the lower middle of samples", () => {
    const base = baselineNightFlow(SAMPLES.filter((s) => s.area === "north"));
    expect(base).toBeCloseTo(11.5, 6);
  });

  it("flags sustained rises", () => {
    const rep = evaluateArea(SAMPLES, "north");
    expect(rep.area).toBe("north");
    expect(rep.latest).toBe(40);
    expect(rep.alerted).toBe(true);
    expect(rep.ratio).toBeGreaterThan(1.3);
  });

  it("does not flag quiet areas", () => {
    const rep = evaluateArea(SAMPLES, "south");
    expect(rep.alerted).toBe(false);
  });

  it("collects alerted areas", () => {
    const reps = [evaluateArea(SAMPLES, "north"), evaluateArea(SAMPLES, "south")];
    expect(alertedAreas(reps)).toEqual(["north"]);
  });
});

'''),
    ("tests/forecast.test.ts", '''// forecast.test.ts - demand forecast and error metrics.

import { describe, expect, it } from "vitest";
import { baseline, dayAdjustment, forecastNext, mape, type DailyDemand } from "../src/algo/forecast.js";

function week(): DailyDemand[] {
  const out: DailyDemand[] = [];
  for (let d = 0; d < 14; d += 1) {
    out.push({ day: d, demand: 100 + (d % 3) * 10 });
  }
  return out;
}

describe("forecast", () => {
  it("computes a trailing baseline", () => {
    expect(baseline(week(), 7)).toBeCloseTo(110, 6);
    expect(baseline([], 7)).toBe(0);
  });

  it("adjusts by weekday", () => {
    const days: DailyDemand[] = [
      { day: 0, demand: 100 },
      { day: 1, demand: 110 },
      { day: 2, demand: 120 },
      { day: 7, demand: 100 },
      { day: 8, demand: 110 },
      { day: 9, demand: 120 },
    ];
    expect(baseline(days, 6)).toBeCloseTo(110, 6);
    expect(dayAdjustment(days, 6, 0)).toBeCloseTo(-10, 6);
  });

  it("forecasts forward", () => {
    const f = forecastNext(week(), 7, 14);
    expect(f).toBeGreaterThanOrEqual(0);
  });

  it("scores mean absolute percentage error", () => {
    expect(mape([100, 100], [90, 110])).toBe(10);
    expect(mape([], [])).toBe(0);
  });
});

'''),
    ("tests/pressure.test.ts", '''// pressure.test.ts - pressure regulation policy.

import { describe, expect, it } from "vitest";
import { deviation, nextValve, regulate, regulationScore, type RegSpec } from "../src/algo/pressure.js";

const SPEC: RegSpec = { node: "n1", setPoint: 4, band: 0.5 };

describe("pressure regulation", () => {
  it("measures deviation from the band", () => {
    expect(deviation({ instant: 0, node: "n1", pressure: 4, valve: 0.5 }, SPEC)).toBe(0);
    expect(deviation({ instant: 0, node: "n1", pressure: 5, valve: 0.5 }, SPEC)).toBe(0.5);
    expect(deviation({ instant: 0, node: "n1", pressure: 2, valve: 0.5 }, SPEC)).toBe(1.5);
  });

  it("moves the valve against the deviation", () => {
    expect(nextValve(0.5, 0.2, 0.1)).toBe(0.6);
    expect(nextValve(0.5, -0.2, 0.1)).toBe(0.4);
    expect(nextValve(0.95, 1, 0.1)).toBe(1);
    expect(nextValve(0.05, -1, 0.1)).toBe(0);
  });

  it("regulates a series within bounds", () => {
    const samples = regulate(SPEC, [3.5, 4.5, 5.5, 3.0], 0.1);
    expect(samples.length).toBe(4);
    expect(regulationScore(samples, SPEC)).toBeGreaterThan(0);
  });
});

'''),
    ("tests/reports.test.ts", '''// reports.test.ts - table rendering and zone summaries.

import { describe, expect, it } from "vitest";
import { renderTable, format, pad, type Column, type Row } from "../src/reports/rows.js";
import {
  summarizeZone,
  rankZones,
  summariesFromRows,
  flagged,
  zoneColumns,
  zoneRow,
  type ZoneSummary,
} from "../src/reports/zonal.js";
import { type RawRecord } from "../src/data/records.js";
import { type Segment } from "../src/data/ledger.js";

describe("table rendering", () => {
  it("pads cells to alignment", () => {
    expect(pad("x", 3, "right")).toBe("  x");
    expect(pad("x", 3, "left")).toBe("x  ");
  });

  it("groups digits", () => {
    expect(format(1234)).toBe("1,234");
    expect(format(-999)).toBe("-999");
  });

  it("renders a deterministic table", () => {
    const cols: Column[] = [
      { title: "ID", align: "left" },
      { title: "N", align: "right" },
    ];
    const rows: Row[] = [[{ text: "a" }, { text: "1" }]];
    const table = renderTable(cols, rows);
    expect(table).toContain("ID");
    expect(table).toContain("a");
  });
});

describe("zone summaries", () => {
  it("summarizes meters and revenue", () => {
    const segments = new Map<string, readonly Segment[]>();
    const s = summarizeZone("north", segments, 10, 0.5, new Map([["m1", 3]]));
    expect(s.zone).toBe("north");
    expect(s.meterCount).toBe(3);
    expect(s.leakageRatio).toBe(0.5);
  });

  it("ranks zones descending", () => {
    const a: ZoneSummary = { zone: "a", meterCount: 1, consumption: 10, revenueCents: 1, leakageRatio: 0 };
    const b: ZoneSummary = { zone: "b", meterCount: 1, consumption: 20, revenueCents: 2, leakageRatio: 0 };
    expect(rankZones([a, b])[0]?.zone).toBe("b");
  });

  it("reads summaries from rows and flags leaks", () => {
    const rows: RawRecord[] = [{ zone: "north", consumption: 10, revenue: 5, meters: 2 }];
    const list = summariesFromRows(rows);
    expect(list.length).toBe(1);
    expect(list[0]?.consumption).toBe(10);
    expect(flagged(list[0]!, 0.5)).toBe(false);
    expect(zoneColumns().length).toBe(5);
    expect(zoneRow(list[0]!).length).toBe(5);
  });
});

'''),
]
