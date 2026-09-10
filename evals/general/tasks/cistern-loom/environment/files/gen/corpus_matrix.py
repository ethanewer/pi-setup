# -*- coding: utf-8 -*-
"""Large matrix tests for the extra modules: clustering, blending,
detail reports, district tables and profile curves."""

TMATRIX = [
    ("tests/matrix.test.ts", '''// matrix.test.ts - data-driven contract matrix over the added modules.

import { describe, expect, it } from "vitest";
import { center, distance, cluster, mergeOrder, type FlowPoint } from "../src/algo/cluster.js";
import { blend, compliant, bestShare, type Source } from "../src/algo/mix.js";
import { dailyLines, renderDetails, detailTotal, dayOfInstant } from "../src/reports/detail.js";
import { type Segment } from "../src/data/ledger.js";
import { hourFactor, averageFactor, profileTable } from "../src/data/profiles.js";
import { DISTRICT_DEFAULTS } from "../src/data/district-defaults.js";
import { priceForVolume, tariffFromRows } from "../src/data/tariffs.js";
import { type RawRecord } from "../src/data/records.js";

describe("clustering", () => {
  const points: FlowPoint[] = [
    { zone: "a", flows: [1, 1, 1] },
    { zone: "b", flows: [1, 2, 1] },
    { zone: "c", flows: [9, 9, 9] },
    { zone: "d", flows: [8, 9, 8] },
  ];

  it("computes distances and centers", () => {
    expect(distance([0, 0], [3, 4])).toBe(5);
    expect(center([[1, 2], [3, 4]])).toEqual([2, 3]);
    expect(center([])).toEqual([]);
  });

  it("clusters similar zones together", () => {
    const out = cluster(points, 2);
    expect(out.length).toBe(2);
    const a = out[0]?.members ?? [];
    const b = out[1]?.members ?? [];
    expect([...a, ...b].sort()).toEqual(["a", "b", "c", "d"]);
  });

  it("returns single-zone clusters when k is large", () => {
    expect(cluster(points, 5).length).toBe(4);
  });

  it("emits a merge order", () => {
    const m: number[][] = [
      [0, 1, 5],
      [1, 0, 5],
      [5, 5, 0],
    ];
    expect(mergeOrder(m).length).toBe(3);
  });
});

describe("blending", () => {
  const srcs: Source[] = [
    { id: "s1", flow: 100, quality: 80 },
    { id: "s2", flow: 300, quality: 60 },
  ];

  it("blends by flow weight", () => {
    const r = blend(srcs);
    expect(r.quality).toBeCloseTo(65, 6);
    expect(r.minQuality).toBe(60);
    expect(r.maxQuality).toBe(80);
  });

  it("handles empty and zero-flow sets", () => {
    expect(blend([]).quality).toBe(0);
    const r = blend([{ id: "x", flow: 0, quality: 50 }]);
    expect(r.quality).toBe(0);
  });

  it("evaluates compliance and best share", () => {
    expect(compliant(blend(srcs), 60)).toBe(true);
    expect(compliant(blend(srcs), 70)).toBe(false);
    expect(bestShare(srcs)).toBe(100);
  });
});

describe("detail reports", () => {
  const segs = new Map<string, readonly Segment[]>([
    ["m1", [
      { fromInstant: 0, toInstant: 86400, consumption: 10 },
      { fromInstant: 86400, toInstant: 172800, consumption: 5 },
    ]],
    ["m2", [{ fromInstant: 0, toInstant: 86400, consumption: 3 }]],
  ]);

  it("aggregates daily lines", () => {
    const lines = dailyLines(segs);
    expect(lines.length).toBe(3);
    expect(detailTotal(lines)).toBe(18);
    expect(dayOfInstant(90000)).toBe(1);
  });

  it("renders per-meter detail blocks", () => {
    const lines = dailyLines(segs);
    const text = renderDetails({ serial: "m1", district: "north", unit: null, installedDay: 1 }, lines);
    expect(text).toContain("---m1");
  });
});

describe("profiles", () => {
  it("serves deterministic curves", () => {
    expect(profileTable("flat").length).toBe(24);
    expect(hourFactor("flat", 5)).toBe(1);
    expect(hourFactor("nightlow", 0)).toBeLessThan(hourFactor("nightlow", 12));
    expect(averageFactor("flat")).toBe(1);
  });
});

describe("district table matrix", () => {
  it("holds every pricing tier combination", () => {
    const expected = 16 * 4 * 5;
    expect(DISTRICT_DEFAULTS.length).toBe(expected);
  });

  it("prices a large volume across the whole tier matrix", () => {
    const rows: RawRecord[] = [
      { upTo: 10, price: 100 },
      { upTo: 10, price: 50 },
      { upTo: 0, price: 0 },
    ];
    const t = tariffFromRows("x", "y", rows);
    expect(priceForVolume(t, 10)).toBe(1000);
  });
});

'''),
]