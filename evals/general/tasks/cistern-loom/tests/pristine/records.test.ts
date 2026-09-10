// records.test.ts - raw record readers.

import { describe, expect, it } from "vitest";
import {
  readStr,
  readNum,
  readFlag,
  hasField,
  validateRecordKeys,
  missingFields,
  requireFields,
  pickFields,
  fieldCount,
  type RawRecord,
} from "../src/data/records.js";

describe("record readers", () => {
  it("reads strings", () => {
    expect(readStr({ a: " x " }, "a")).toBe("x");
    expect(readStr({ a: "" }, "a")).toBe(undefined);
    expect(readStr({ a: 5 }, "a")).toBe(undefined);
    expect(readStr({}, "a")).toBe(undefined);
  });

  it("reads numbers", () => {
    expect(readNum({ a: 2.5 }, "a")).toBe(2.5);
    expect(readNum({ a: "3.5" }, "a")).toBe(3.5);
    expect(readNum({ a: "nan" }, "a")).toBe(undefined);
    expect(readNum({ a: Infinity }, "a")).toBe(undefined);
  });

  it("reads flags", () => {
    expect(readFlag({ a: 1 }, "a", false)).toBe(true);
    expect(readFlag({ a: "yes" }, "a", false)).toBe(true);
    expect(readFlag({ a: "no" }, "a", true)).toBe(false);
    expect(readFlag({}, "a", true)).toBe(true);
    expect(readFlag({ a: "maybe" }, "a", false)).toBe(false);
  });

  it("tests presence and key grammar", () => {
    expect(hasField({ a: undefined }, "a")).toBe(false);
    expect(hasField({ a: 0 }, "a")).toBe(true);
    expect(validateRecordKeys({ good_1: 1 })).toBe(true);
    expect(validateRecordKeys({ "bad-key": 1 })).toBe(false);
  });

  it("reports and requires fields", () => {
    const rec: RawRecord = { a: 1 };
    expect(missingFields(rec, ["a", "b"])).toEqual(["b"]);
    requireFields({ a: 1, b: 2 }, ["a", "b"]);
    expect(() => requireFields(rec, ["a", "b"])).toThrow();
  });

  it("picks fields and counts them", () => {
    const rec: RawRecord = { a: 1, b: "x", c: 2 };
    expect(pickFields(rec, ["a", "c"])).toEqual({ a: 1, c: 2 });
    expect(fieldCount(rec)).toBe(3);
    expect(fieldCount({})).toBe(0);
  });
});

