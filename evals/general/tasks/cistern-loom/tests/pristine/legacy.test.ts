// legacy.test.ts - flat-file importers and extractors.

import { describe, expect, it } from "vitest";
import { parseCsv, parseEquals, dataRowCount } from "../src/legacy/parsers.js";
import { extractSerial, extractZone, splitTs } from "../src/legacy/extract.js";
import { rowToRecord, sortedColumns, project, type LegacyRow } from "../src/legacy/compat.js";
import { naturalSort } from "../src/util/natural.js";

describe("legacy parsers", () => {
  it("parses CSV with quoted fields", () => {
    const table = parseCsv("a,b\nc,1\n\"d,2\",3\n");
    expect(table.headers).toEqual(["a", "b"]);
    expect(table.rows.length).toBe(2);
    expect(dataRowCount(table)).toBe(2);
  });

  it("parses key=value text", () => {
    const rec = parseEquals("zone=N1\nauto=  yes  \n# comment\n");
    expect(rec.zone).toBe("N1");
    expect(rec.auto).toBe("yes");
  });

  it("extracts serials and zones", () => {
    expect(extractSerial("serial MTR-ab12 here")).toBe("MTR-AB12");
    expect(extractSerial("none")).toBe(undefined);
    expect(extractZone("N1.S2 (waypoint)")).toBe("N1.S2");
    expect(extractZone("N3")).toBe("N3");
  });

  it("splits timestamps", () => {
    const t = splitTs("2026-03-02T04:05:06");
    expect(t.day).toBe(366 * 2026 + 31 * 3 + 2);
    expect(t.seconds).toBe(306);
    expect(splitTs("garbage").day).toBe(0);
  });
});

describe("legacy compat", () => {
  it("converts rows to records", () => {
    const row: LegacyRow = { columns: ["a", "b"], values: ["1", "2"] };
    expect(rowToRecord(row)).toEqual({ a: "1", b: "2" });
    expect(sortedColumns(row)).toEqual(["a", "b"]);
  });

  it("projects records", () => {
    expect(project({ a: 1, b: 2 }, ["a"])).toEqual({ a: 1 });
    expect(naturalSort(["x10", "x2"])).toEqual(["x2", "x10"]);
  });
});

