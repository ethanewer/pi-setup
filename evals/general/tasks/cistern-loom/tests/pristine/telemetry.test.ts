// telemetry.test.ts - timelines, gap filling, statistics.

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

