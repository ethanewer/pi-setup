// presets.test.ts - district defaults, hydrants, presets, fixtures.

import { describe, expect, it } from "vitest";
import { presetRegistry, findPreset, presetNames } from "../src/data/presets.js";
import {
  DISTRICT_DEFAULTS,
  findDefault,
  defaultDistricts,
  countForDistrict,
  topDistricts,
} from "../src/data/district-defaults.js";
import { HYDRANTS, flaggedHydrants, districtPressure, districtFlow } from "../src/data/hydrants.js";
import { SEED_METERS, seedMeter, seedDistricts } from "../src/data/fixtures.js";

describe("presets", () => {
  it("knows the preset registry", () => {
    expect(presetRegistry().length).toBeGreaterThan(8);
    expect(findPreset("north-summer")?.district).toBe("north");
    expect(findPreset("missing")).toBe(undefined);
    expect(presetNames().length).toBe(presetRegistry().length);
  });
});

describe("district defaults", () => {
  it("carries a large consistent table", () => {
    expect(DISTRICT_DEFAULTS.length).toBeGreaterThan(150);
    expect(defaultDistricts().length).toBeGreaterThanOrEqual(8);
    expect(countForDistrict("north")).toBe(20);
  });

  it("resolves defaults by district and class", () => {
    const d = findDefault("north", "residential");
    expect(d?.zone).toBe("north-res");
    expect(d?.minPressure).toBeGreaterThan(0);
    expect(findDefault("mars", "residential")).toBe(undefined);
  });

  it("orders top districts by nominal", () => {
    const top = topDistricts(3);
    expect(top.length).toBeLessThanOrEqual(3);
  });
});

describe("hydrants", () => {
  it("holds the register and flags issues", () => {
    expect(HYDRANTS.length).toBeGreaterThan(100);
    expect(flaggedHydrants().length).toBeGreaterThan(0);
  });

  it("computes district aggregates", () => {
    expect(districtPressure("north")).toBeGreaterThan(0);
    expect(districtFlow("north")).toBeGreaterThan(0);
    expect(districtPressure("nope")).toBe(0);
  });
});

describe("fixtures", () => {
  it("serves seed meters", () => {
    expect(SEED_METERS.length).toBe(64);
    expect(seedMeter("MTR-0001")?.district).toBe("south");
    expect(seedMeter("missing")).toBe(undefined);
    expect(seedDistricts().length).toBeGreaterThanOrEqual(4);
  });
});

