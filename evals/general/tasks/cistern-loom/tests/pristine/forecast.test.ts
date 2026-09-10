// forecast.test.ts - demand forecast and error metrics.

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

