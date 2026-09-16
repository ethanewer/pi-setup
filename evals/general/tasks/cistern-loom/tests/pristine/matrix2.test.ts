// matrix2.test.ts - path analysis, weather correction, tables.

import { describe, expect, it } from "vitest";
import { Network, type NodeSpec, type LinkSpec } from "../src/model/network.js";
import { hopDistances, reachable, eccentricity, commonArea } from "../src/algo/shortest.js";
import { corrections, rainFactor, wetShare, totalRain, applyCorrections, type RainfallDay } from "../src/data/weather.js";
import { DISTRICT_DEFAULTS, countForDistrict, defaultDistricts } from "../src/data/district-defaults.js";
import { HYDRANTS, districtFlow } from "../src/data/hydrants.js";

function line(): Network {
  const nodes: NodeSpec[] = [
    { id: "a", kind: "junction", label: "a", capacity: 1, level: 0, point: null },
    { id: "b", kind: "junction", label: "b", capacity: 1, level: 0, point: null },
    { id: "c", kind: "junction", label: "c", capacity: 1, level: 0, point: null },
    { id: "d", kind: "junction", label: "d", capacity: 1, level: 0, point: null },
  ];
  const links: LinkSpec[] = [
    { from: "a", to: "b", lengthM: 100, diameterMm: 100, roughness: 100 },
    { from: "b", to: "a", lengthM: 100, diameterMm: 100, roughness: 100 },
    { from: "b", to: "c", lengthM: 100, diameterMm: 100, roughness: 100 },
    { from: "c", to: "b", lengthM: 100, diameterMm: 100, roughness: 100 },
    { from: "c", to: "d", lengthM: 100, diameterMm: 100, roughness: 100 },
    { from: "d", to: "c", lengthM: 100, diameterMm: 100, roughness: 100 },
  ];
  return new Network(nodes, links);
}

describe("shortest paths", () => {
  it("computes hop distances along a path", () => {
    const net = line();
    const r = hopDistances(net, "a");
    expect(r.distances.get("a")).toBe(0);
    expect(r.distances.get("c")).toBe(2);
    expect(r.diameter).toBe(3);
  });

  it("reports reachability and eccentricity", () => {
    const net = line();
    expect(reachable(net, "a", "d")).toBe(true);
    expect(reachable(net, "d", "a")).toBe(true);
    expect(eccentricity(net, "b")).toBe(2);
  });

  it("computes the common area of seeds", () => {
    const net = line();
    expect(commonArea(net, ["a", "d"], 3)).toEqual(["a", "b", "c", "d"]);
    expect(commonArea(net, [], 2)).toEqual([]);
  });
});

describe("weather corrections", () => {
  const rain: RainfallDay[] = [
    { day: 0, mm: 0 },
    { day: 1, mm: 10 },
    { day: 2, mm: 80 },
  ];

  it("maps rain to factors", () => {
    expect(rainFactor(0)).toBe(1);
    expect(rainFactor(10)).toBeCloseTo(0.75, 6);
    expect(rainFactor(200)).toBe(0.55);
  });

  it("builds correction series and aggregates", () => {
    const corr = corrections(rain, 3);
    expect(corr.length).toBe(3);
    expect(corr[0]?.factor).toBe(1);
    expect(totalRain(rain)).toBeCloseTo(90, 6);
    expect(wetShare(rain)).toBeCloseTo(2 / 3, 6);
    expect(wetShare([])).toBe(0);
  });

  it("applies corrections to a demand series", () => {
    const corr = corrections(rain, 3);
    const out = applyCorrections([100, 100, 100], corr);
    expect(out[0]).toBe(100);
    expect(out[1]).toBe(75);
    expect(out[2]).toBe(55);
  });
});

describe("extended tables", () => {
  it("covers fourteen districts", () => {
    expect(defaultDistricts().length).toBe(16);
    expect(countForDistrict("north")).toBe(20);
    expect(DISTRICT_DEFAULTS.length).toBeGreaterThan(300);
  });

  it("keeps district hydrant totals positive", () => {
    for (const d of defaultDistricts()) {
      expect(districtFlow(d)).toBeGreaterThan(0);
    }
    expect(HYDRANTS.length).toBeGreaterThan(150);
  });
});

