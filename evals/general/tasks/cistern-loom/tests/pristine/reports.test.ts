// reports.test.ts - table rendering and zone summaries.

import { describe, expect, it } from "vitest";
import { renderTable, format, pad, type Column, type Row } from "../src/reports/rows.js";
import {
  summarizeZone,
  rankZones,
  summariesFromRows,
  flagged,
  zoneColumns,
  zoneRow,
  type ZoneSummary,
} from "../src/reports/zonal.js";
import { type RawRecord } from "../src/data/records.js";
import { type Segment } from "../src/data/ledger.js";

describe("table rendering", () => {
  it("pads cells to alignment", () => {
    expect(pad("x", 3, "right")).toBe("  x");
    expect(pad("x", 3, "left")).toBe("x  ");
  });

  it("groups digits", () => {
    expect(format(1234)).toBe("1,234");
    expect(format(-999)).toBe("-999");
  });

  it("renders a deterministic table", () => {
    const cols: Column[] = [
      { title: "ID", align: "left" },
      { title: "N", align: "right" },
    ];
    const rows: Row[] = [[{ text: "a" }, { text: "1" }]];
    const table = renderTable(cols, rows);
    expect(table).toContain("ID");
    expect(table).toContain("a");
  });
});

describe("zone summaries", () => {
  it("summarizes meters and revenue", () => {
    const segments = new Map<string, readonly Segment[]>();
    const s = summarizeZone("north", segments, 10, 0.5, new Map([["m1", 3]]));
    expect(s.zone).toBe("north");
    expect(s.meterCount).toBe(3);
    expect(s.leakageRatio).toBe(0.5);
  });

  it("ranks zones descending", () => {
    const a: ZoneSummary = { zone: "a", meterCount: 1, consumption: 10, revenueCents: 1, leakageRatio: 0 };
    const b: ZoneSummary = { zone: "b", meterCount: 1, consumption: 20, revenueCents: 2, leakageRatio: 0 };
    expect(rankZones([a, b])[0]?.zone).toBe("b");
  });

  it("reads summaries from rows and flags leaks", () => {
    const rows: RawRecord[] = [{ zone: "north", consumption: 10, revenue: 5, meters: 2 }];
    const list = summariesFromRows(rows);
    expect(list.length).toBe(1);
    expect(list[0]?.consumption).toBe(10);
    expect(flagged(list[0]!, 0.5)).toBe(false);
    expect(zoneColumns().length).toBe(5);
    expect(zoneRow(list[0]!).length).toBe(5);
  });
});

