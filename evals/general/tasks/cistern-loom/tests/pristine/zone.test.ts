// zone.test.ts - zone registry semantics.

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

