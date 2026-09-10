// leak.test.ts - night-flow leak detection.

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

