// hydraulics.test.ts - flow balance and pressure.

import { describe, expect, it } from "vitest";
import { Network, type NodeSpec, type LinkSpec } from "../src/model/network.js";
import { solveBalance, pressureAt, nodeOutflow } from "../src/algo/hydraulics.js";

function smallNet(): Network {
  const nodes: NodeSpec[] = [
    { id: "r", kind: "reservoir", label: "R", capacity: 1000, level: 900, point: null },
    { id: "j", kind: "junction", label: "J", capacity: 100, level: 0, point: null },
  ];
  const links: LinkSpec[] = [{ from: "r", to: "j", lengthM: 500, diameterMm: 200, roughness: 110 }];
  return new Network(nodes, links);
}

describe("hydraulics", () => {
  it("produces a deterministic flow state", () => {
    const net = smallNet();
    const demands = new Map([["j", 25]]);
    const state = solveBalance(net, demands, 40);
    expect(state.iterations).toBe(40);
    expect(state.converged).toBe(true);
    expect(nodeOutflow(state, "r", net)).toBeGreaterThanOrEqual(0);
  });

  it("estimates pressure from level", () => {
    expect(pressureAt(100, 0)).toBeCloseTo(9.8, 1);
    expect(pressureAt(10, 100)).toBe(0);
  });
});

