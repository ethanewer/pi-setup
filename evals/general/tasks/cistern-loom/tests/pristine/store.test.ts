// store.test.ts - in-memory indexed store.

import { describe, expect, it } from "vitest";
import { CisterStore } from "../src/store/store.js";

interface Row {
  readonly zone: string;
  readonly meter: string;
  readonly flow: number;
}

const rowIndex: ReadonlyMap<string, (r: Row) => string | null> = new Map([
  ["zone", (r) => r.zone],
  ["meter", (r) => r.meter],
]);

function store(): CisterStore<Row> {
  return new CisterStore(["zone", "meter"], rowIndex);
}

describe("CisterStore", () => {
  it("inserts and fetches with monotonic ids", () => {
    const s = store();
    const doc = s.insert({ zone: "north", meter: "m1", flow: 12 });
    expect(doc.id).toBe("rec-0");
    expect(s.has(doc.id)).toBe(true);
    expect(s.get(doc.id)?.meter).toBe("m1");
  });

  it("indexes by multiple keys", () => {
    const s = store();
    const a = s.insert({ zone: "north", meter: "m1", flow: 1 });
    const b = s.insert({ zone: "north", meter: "m2", flow: 2 });
    expect(s.locate("zone", "north").sort()).toEqual([a.id, b.id].sort());
    expect(s.locate("meter", "m2")).toEqual([b.id]);
    expect(s.locate("meter", "nope")).toEqual([]);
  });

  it("rejects unknown indexes", () => {
    const s = store();
    expect(() => s.locate("bogus", "x")).toThrow();
  });

  it("reports size", () => {
    const s = store();
    s.insert({ zone: "north", meter: "m1", flow: 1 });
    expect(s.size()).toBe(1);
  });
});

