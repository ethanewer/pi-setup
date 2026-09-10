// network.test.ts - graph construction, traversal, distances.

import { describe, expect, it } from "vitest";
import { Network, distanceKm, linkKey, type NodeSpec, type LinkSpec } from "../src/model/network.js";

function sample(): { nodes: NodeSpec[]; links: LinkSpec[] } {
  const nodes: NodeSpec[] = [
    { id: "r1", kind: "reservoir", label: "Reservoir A", capacity: 1000, level: 800, point: { lon: 1, lat: 1 } },
    { id: "t1", kind: "tank", label: "Tank B", capacity: 500, level: 300, point: { lon: 2, lat: 2 } },
    { id: "j1", kind: "junction", label: "Junction C", capacity: 50, level: 10, point: { lon: 3, lat: 3 } },
    { id: "p1", kind: "pump", label: "Pump D", capacity: 80, level: 20, point: null },
  ];
  const links: LinkSpec[] = [
    { from: "r1", to: "t1", lengthM: 1000, diameterMm: 300, roughness: 110 },
    { from: "t1", to: "j1", lengthM: 800, diameterMm: 200, roughness: 100 },
    { from: "p1", to: "t1", lengthM: 400, diameterMm: 250, roughness: 120 },
  ];
  return { nodes, links };
}

describe("Network", () => {
  it("counts nodes and links", () => {
    const { nodes, links } = sample();
    const net = new Network(nodes, links);
    expect(net.nodeCount()).toBe(4);
    expect(net.linkCount()).toBe(3);
  });

  it("rejects duplicate node ids", () => {
    const { nodes, links } = sample();
    const dup = [...nodes, { ...nodes[0]! }];
    expect(() => new Network(dup as NodeSpec[], links)).toThrow();
  });

  it("resolves nodes and links", () => {
    const { nodes, links } = sample();
    const net = new Network(nodes, links);
    expect(net.hasNode("r1")).toBe(true);
    expect(net.hasNode("zz")).toBe(false);
    expect(net.node("r1").fillRatio()).toBeCloseTo(0.8);
    expect(net.node("r1").headroom()).toBe(200);
    expect(() => net.node("zz")).toThrow();
    expect(net.link("r1", "t1").from).toBe("r1");
    expect(() => net.link("r1", "j1")).toThrow();
  });

  it("lists neighbours in insertion order", () => {
    const { nodes, links } = sample();
    const net = new Network(nodes, links);
    expect(net.neighbours("t1")).toEqual(["j1"]);
    expect(net.neighbours("r1")).toEqual(["t1"]);
    expect(net.neighbours("j1")).toEqual([]);
  });

  it("sorts node ids by capacity", () => {
    const { nodes, links } = sample();
    const net = new Network(nodes, links);
    expect(net.sortedNodeIds()[0]).toBe("r1");
  });
});

describe("geometry", () => {
  it("computes the link key deterministically", () => {
    expect(linkKey("a", "b")).toBe("a->b");
  });

  it("approximates haversine distance", () => {
    const d = distanceKm({ lon: 0, lat: 0 }, { lon: 0, lat: 1 });
    expect(d).toBeCloseTo(111.19, 1);
  });
});

