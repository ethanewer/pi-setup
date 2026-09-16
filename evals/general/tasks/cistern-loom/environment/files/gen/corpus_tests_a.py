# -*- coding: utf-8 -*-
"""vitest suite part 1: util, config, network, zone, store."""

TT = [
    ("tests/util.test.ts", '''// util.test.ts - money, keys, maths, natural order, periods, buckets.

import { describe, expect, it } from "vitest";
import {
  centsToEuros,
  eurosToCents,
  sumCents,
  scaleCents,
  surcharge,
  clampCents,
  isZero,
} from "../src/util/money.js";
import { makeKey, splitKey, zoneKey, meterKey, tariffKey, compareKeys } from "../src/util/keys.js";
import { lerp, clamp, trimDecimals, seededUnit, signOf, delta, relativeError } from "../src/util/math.js";
import { naturalCompare, naturalSort } from "../src/util/natural.js";
import { secondsOfDay, daysBetween, dayOf, dayBucket, periodStart, isNightly } from "../src/util/period.js";
import { equalWidth, bucketIndex, histogram, addHistograms } from "../src/util/buckets.js";
import { SeededRng } from "../src/util/seed.js";

describe("money", () => {
  it("converts euros to cents with half-even rounding", () => {
    expect(eurosToCents(1)).toBe(100);
    expect(eurosToCents(1.234)).toBe(123);
    expect(eurosToCents(1.235)).toBe(124);
    expect(eurosToCents(-0.5)).toBe(-50);
  });

  it("formats cents as euro strings", () => {
    expect(centsToEuros(0)).toBe("0.00");
    expect(centsToEuros(1234)).toBe("12.34");
    expect(centsToEuros(-5)).toBe("-0.05");
  });

  it("sums cents exactly", () => {
    expect(sumCents([1, 2, 3])).toBe(6);
    expect(sumCents([])).toBe(0);
  });

  it("scales and applies surcharges deterministically", () => {
    expect(scaleCents(100, 0.5)).toBe(50);
    expect(surcharge(100, 5)).toBe(105);
    expect(clampCents(150, 100)).toBe(100);
    expect(clampCents(-2, 100)).toBe(0);
    expect(isZero(0)).toBe(true);
    expect(isZero(1)).toBe(false);
  });
});

describe("keys", () => {
  it("builds and splits canonical keys", () => {
    const k = makeKey("z", "north", "res");
    expect(splitKey(k)).toEqual({ prefix: "z", parts: ["north", "res"] });
  });

  it("provides convenience constructors", () => {
    expect(zoneKey("n", "s1")).toBe("z:n:s1");
    expect(meterKey("d", "x")).toBe("m:d:x");
    expect(tariffKey("d", "winter")).toBe("t:d:winter");
  });

  it("compares keys lexicographically", () => {
    expect(compareKeys("a", "b")).toBe(-1);
    expect(compareKeys("b", "a")).toBe(1);
    expect(compareKeys("a", "a")).toBe(0);
  });
});

describe("math helpers", () => {
  it("interpolates and clamps", () => {
    expect(lerp(0, 10, 0.5)).toBe(5);
    expect(clamp(7, 0, 5)).toBe(5);
    expect(trimDecimals(1.23456, 2)).toBe(1.23);
  });

  it("seeded unit is deterministic and in range", () => {
    const a = seededUnit(7);
    const b = seededUnit(7);
    expect(a).toBe(b);
    expect(a >= 0 && a < 1).toBe(true);
  });

  it("computes signs, deltas and relative errors", () => {
    expect(signOf(-3)).toBe(-1);
    expect(delta(4, 6)).toBe(2);
    expect(relativeError(0, 0)).toBe(0);
    expect(relativeError(5, 5)).toBe(0);
    expect(relativeError(3, 1)).toBe(2);
  });
});

describe("natural order", () => {
  it("orders embedded numbers numerically", () => {
    expect(naturalCompare("R2", "R10")).toBe(-1);
    expect(naturalCompare("R10", "R2")).toBe(1);
    expect(naturalCompare("R2", "R2")).toBe(0);
  });

  it("sorts mixed ids", () => {
    const ids = ["R10", "R2", "R1b", "R1a", "R1"];
    const sorted = naturalSort(ids);
    expect(sorted).toEqual(["R1", "R1a", "R1b", "R2", "R10"]);
  });
});

describe("period arithmetic", () => {
  it("splits instants into days and buckets", () => {
    expect(secondsOfDay(1, 30)).toBe(5400);
    expect(daysBetween(0, 86400)).toBe(1);
    expect(dayOf(86400 * 2 + 5)).toBe(2);
    expect(dayBucket(10 * 3600)).toBe("morning");
    expect(dayBucket(20 * 3600)).toBe("evening");
    expect(dayBucket(2 * 3600)).toBe("night");
  });

  it("rounds to period starts and detects nightly windows", () => {
    expect(periodStart(3665, 3600)).toBe(3600);
    expect(isNightly(2 * 3600, 22 * 3600, 6 * 3600)).toBe(true);
    expect(isNightly(23 * 3600, 22 * 3600, 6 * 3600)).toBe(true);
    expect(isNightly(10 * 3600, 22 * 3600, 6 * 3600)).toBe(false);
  });
});

describe("buckets and rng", () => {
  it("builds equal-width buckets and histograms", () => {
    const buckets = equalWidth(0, 10, 5);
    expect(buckets.length).toBe(5);
    expect(bucketIndex(9.9, 0, 10, 5)).toBe(4);
    expect(bucketIndex(-1, 0, 10, 5)).toBe(0);
    expect(histogram([1, 1, 9], 0, 10, 5)).toEqual([2, 0, 0, 0, 1]);
    expect(addHistograms([1, 2], [3, 4, 5])).toEqual([4, 6, 5]);
  });

  it("seeded rng is reproducible", () => {
    const a = new SeededRng(42);
    const b = new SeededRng(42);
    expect(a.next()).toBe(b.next());
    expect(a.unit()).toBe(b.unit());
    expect(a.int(1, 6) >= 1 && a.int(1, 6) <= 6).toBe(true);
  });
});

'''),
    ("tests/config.test.ts", '''// config.test.ts - freezeConfig validation matrix.

import { describe, expect, it } from "vitest";
import { freezeConfig, horizonSpan, type FrozenConfig } from "../src/model/config.js";

describe("freezeConfig", () => {
  it("breaks without the required fields", () => {
    const { ok, issues } = freezeConfig({ name: "x" });
    expect(ok).toBe(false);
    expect(issues.length).toBeGreaterThan(0);
  });

  it.each([
    ["valid minimal", { name: "n", district: "north", season: "summer" }, true],
    ["with horizon", { name: "n", district: "north", season: "winter", horizonDays: 90 }, true],
    ["bad horizon", { name: "n", district: "north", season: "winter", horizonDays: 0 }, false],
    ["huge horizon", { name: "n", district: "north", season: "winter", horizonDays: 400 }, false],
    ["non-number horizon", { name: "n", district: "north", season: "winter", horizonDays: "x" }, false],
    ["bad curve", { name: "n", district: "north", season: "winter", demandCurve: "sine" }, false],
    ["float horizon", { name: "n", district: "north", season: "winter", horizonDays: 2.5 }, false],
  ])("handles: %s", (_label: string, raw: Record<string, string | number | boolean>, wantOk: boolean) => {
    const { ok } = freezeConfig(raw);
    expect(ok).toBe(wantOk);
  });

  it("applies defaults for absent optional fields", () => {
    const { ok, config } = freezeConfig({ name: "n", district: "north", season: "winter" });
    expect(ok).toBe(true);
    expect(config?.horizonDays).toBe(30);
    expect(config?.demandCurve).toBe("flat");
    expect(config?.tariffActive).toBe(true);
    expect(config?.demandActive).toBe(false);
    expect(config?.tariffLookup).toBe("default");
  });

  it("respects explicit flags and start day", () => {
    const { ok, config } = freezeConfig({
      name: "n",
      district: "north",
      season: "winter",
      demandActive: "yes",
      tariffActive: "no",
      startDay: 5,
    });
    expect(ok).toBe(true);
    expect(config?.demandActive).toBe(true);
    expect(config?.tariffActive).toBe(false);
    expect(config?.startDay).toBe(5);
    expect(horizonSpan(config as FrozenConfig)).toBe(30);
  });

  it("parses numeric strings as ints", () => {
    const { ok, config } = freezeConfig({
      name: "n",
      district: "east",
      season: "spring",
      horizonDays: "45",
    });
    expect(ok).toBe(true);
    expect(config?.horizonDays).toBe(45);
  });
});

'''),
    ("tests/network.test.ts", '''// network.test.ts - graph construction, traversal, distances.

import { describe, expect, it } from "vitest";
import { Network, distanceKm, linkKey, type NodeSpec, type LinkSpec } from "../src/model/network.js";

function sample(): { nodes: NodeSpec[]; links: LinkSpec[] } {
  const nodes: NodeSpec[] = [
    { id: "r1", kind: "reservoir", label: "Reservoir A", capacity: 1000, level: 800, point: { lon: 1, lat: 1 } },
    { id: "t1", kind: "tank", label: "Tank B", capacity: 500, level: 300, point: { lon: 2, lat: 2 } },
    { id: "j1", kind: "junction", label: "Junction C", capacity: 50, level: 10, point: { lon: 3, lat: 3 } },
    { id: "p1", kind: "pump", label: "Pump D", capacity: 80, level: 20, point: null },
  ];
  const links: LinkSpec[] = [
    { from: "r1", to: "t1", lengthM: 1000, diameterMm: 300, roughness: 110 },
    { from: "t1", to: "j1", lengthM: 800, diameterMm: 200, roughness: 100 },
    { from: "p1", to: "t1", lengthM: 400, diameterMm: 250, roughness: 120 },
  ];
  return { nodes, links };
}

describe("Network", () => {
  it("counts nodes and links", () => {
    const { nodes, links } = sample();
    const net = new Network(nodes, links);
    expect(net.nodeCount()).toBe(4);
    expect(net.linkCount()).toBe(3);
  });

  it("rejects duplicate node ids", () => {
    const { nodes, links } = sample();
    const dup = [...nodes, { ...nodes[0]! }];
    expect(() => new Network(dup as NodeSpec[], links)).toThrow();
  });

  it("resolves nodes and links", () => {
    const { nodes, links } = sample();
    const net = new Network(nodes, links);
    expect(net.hasNode("r1")).toBe(true);
    expect(net.hasNode("zz")).toBe(false);
    expect(net.node("r1").fillRatio()).toBeCloseTo(0.8);
    expect(net.node("r1").headroom()).toBe(200);
    expect(() => net.node("zz")).toThrow();
    expect(net.link("r1", "t1").from).toBe("r1");
    expect(() => net.link("r1", "j1")).toThrow();
  });

  it("lists neighbours in insertion order", () => {
    const { nodes, links } = sample();
    const net = new Network(nodes, links);
    expect(net.neighbours("t1")).toEqual(["j1"]);
    expect(net.neighbours("r1")).toEqual(["t1"]);
    expect(net.neighbours("j1")).toEqual([]);
  });

  it("sorts node ids by capacity", () => {
    const { nodes, links } = sample();
    const net = new Network(nodes, links);
    expect(net.sortedNodeIds()[0]).toBe("r1");
  });
});

describe("geometry", () => {
  it("computes the link key deterministically", () => {
    expect(linkKey("a", "b")).toBe("a->b");
  });

  it("approximates haversine distance", () => {
    const d = distanceKm({ lon: 0, lat: 0 }, { lon: 0, lat: 1 });
    expect(d).toBeCloseTo(111.19, 1);
  });
});

'''),
    ("tests/zone.test.ts", '''// zone.test.ts - zone registry semantics.

import { describe, expect, it } from "vitest";
import { ZoneRegistry, type ZoneSpec } from "../src/model/zone.js";

const SPECS: ZoneSpec[] = [
  { zone: "north", sector: "a", priority: 1, baselineDemand: 100 },
  { zone: "north", sector: "b", priority: 2, baselineDemand: 150 },
  { zone: "south", sector: "a", priority: 1, baselineDemand: 80 },
];

describe("ZoneRegistry", () => {
  it("registers and resolves zones", () => {
    const reg = new ZoneRegistry(SPECS);
    expect(reg.size()).toBe(3);
    expect(reg.has("z:north:a")).toBe(true);
    expect(reg.has("z:west:a")).toBe(false);
    expect(reg.get("z:north:a").priority).toBe(1);
    expect(() => reg.get("z:missing:a")).toThrow();
  });

  it("sorts keys and totals demand", () => {
    const reg = new ZoneRegistry(SPECS);
    expect(reg.keysSorted()).toEqual(["z:north:a", "z:north:b", "z:south:a"]);
    expect(reg.totalDemand()).toBe(330);
  });
});

'''),
    ("tests/store.test.ts", '''// store.test.ts - in-memory indexed store.

import { describe, expect, it } from "vitest";
import { CisterStore } from "../src/store/store.js";

interface Row {
  readonly zone: string;
  readonly meter: string;
  readonly flow: number;
}

const rowIndex: ReadonlyMap<string, (r: Row) => string | null> = new Map([
  ["zone", (r) => r.zone],
  ["meter", (r) => r.meter],
]);

function store(): CisterStore<Row> {
  return new CisterStore(["zone", "meter"], rowIndex);
}

describe("CisterStore", () => {
  it("inserts and fetches with monotonic ids", () => {
    const s = store();
    const doc = s.insert({ zone: "north", meter: "m1", flow: 12 });
    expect(doc.id).toBe("rec-0");
    expect(s.has(doc.id)).toBe(true);
    expect(s.get(doc.id)?.meter).toBe("m1");
  });

  it("indexes by multiple keys", () => {
    const s = store();
    const a = s.insert({ zone: "north", meter: "m1", flow: 1 });
    const b = s.insert({ zone: "north", meter: "m2", flow: 2 });
    expect(s.locate("zone", "north").sort()).toEqual([a.id, b.id].sort());
    expect(s.locate("meter", "m2")).toEqual([b.id]);
    expect(s.locate("meter", "nope")).toEqual([]);
  });

  it("rejects unknown indexes", () => {
    const s = store();
    expect(() => s.locate("bogus", "x")).toThrow();
  });

  it("reports size", () => {
    const s = store();
    s.insert({ zone: "north", meter: "m1", flow: 1 });
    expect(s.size()).toBe(1);
  });
});

'''),
]