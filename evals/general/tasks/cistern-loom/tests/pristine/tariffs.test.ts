// tariffs.test.ts - tiered pricing.

import { describe, expect, it } from "vitest";
import {
  tariffFromRows,
  priceForVolume,
  reachesTopTier,
  averagePrice,
  lookupTariff,
  type Tariff,
} from "../src/data/tariffs.js";
import { type RawRecord } from "../src/data/records.js";

const ROWS: RawRecord[] = [
  { upTo: 10, price: 100 },
  { upTo: 20, price: 150 },
  { upTo: 0, price: 0 },
  { upTo: 50, price: 200 },
];

describe("tariffs", () => {
  it("builds sorted tables", () => {
    const t = tariffFromRows("north", "summer", ROWS);
    expect(t.tiers.length).toBe(4);
  });

  it("prices volumes by tier", () => {
    const t = tariffFromRows("north", "summer", ROWS);
    expect(priceForVolume(t, 5)).toBe(500);
    expect(priceForVolume(t, 15)).toBe(1750);
    expect(priceForVolume(t, 25)).toBe(3500);
    expect(priceForVolume(t, 0)).toBe(0);
  });

  it("clips boundaries and computes averages", () => {
    const t = tariffFromRows("north", "summer", ROWS);
    expect(reachesTopTier(t, 100)).toBe(true);
    expect(reachesTopTier(t, 5)).toBe(false);
    expect(averagePrice(t, 10)).toBe(100);
  });

  it("looks tariffs up by district and season", () => {
    const tables: Tariff[] = [tariffFromRows("north", "summer", ROWS)];
    expect(lookupTariff(tables, "north", "summer")?.tiers.length).toBe(4);
    expect(lookupTariff(tables, "north", "winter")).toBe(undefined);
  });
});

