// ledger.test.ts - register segments, volumes, meters.

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

