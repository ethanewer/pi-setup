// config.test.ts - freezeConfig validation matrix.

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

