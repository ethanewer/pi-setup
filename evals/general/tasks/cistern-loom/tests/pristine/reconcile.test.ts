// reconcile.test.ts - end-to-end pipeline.

import { describe, expect, it } from "vitest";
import { reconcile, renderText, type ReconcileOutput } from "../src/service/reconcile.js";
import { type RawRecord } from "../src/data/records.js";

describe("reconcile", () => {
  it("rejects invalid config", () => {
    const out = () =>
      reconcile({ name: "n" } as RawRecord, [{ kind: "reading", zone: "north", flow: 1 }]);
    expect(out).toThrow();
  });

  it("counts meters and sums consumption", () => {
    const config: RawRecord = { name: "n", district: "north", season: "summer" };
    const recs: RawRecord[] = [
      { kind: "meter", serial: "m1" },
      { kind: "meter", serial: "m2" },
      { kind: "reading", zone: "north", flow: 10 },
      { kind: "reading", zone: "north", flow: 5 },
    ];
    const out = reconcile(config, recs);
    expect(out.meterCount).toBe(2);
    expect(out.consumed).toBe(15);
    expect(out.leaked).toBe(false);
  });

  it("flags exceptional flows as leaks", () => {
    const config: RawRecord = { name: "n", district: "north", season: "summer", startDay: 30 };
    const recs: RawRecord[] = [{ kind: "reading", zone: "north", flow: 1000 }];
    const out = reconcile(config, recs);
    expect(out.consumed).toBe(1000);
    expect(out.leaked).toBe(true);
  });

  it("renders report text deterministically", () => {
    const text = renderText("run-a", 2, 3, 15, false);
    expect(text).toContain("report=run-a");
    expect(text).toContain("meters=3");
    const output: ReconcileOutput = { report: text, zoneCount: 2, meterCount: 3, consumed: 15, leaked: false };
    expect(output.report).toBe(text);
  });
});

