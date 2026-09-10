// pressure.test.ts - pressure regulation policy.

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

