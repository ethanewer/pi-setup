// util.test.ts - money, keys, maths, natural order, periods, buckets.

import { describe, expect, it } from "vitest";
import {
  centsToEuros,
  eurosToCents,
  sumCents,
  scaleCents,
  surcharge,
  clampCents,
  isZero,
} from "../src/util/money.js";
import { makeKey, splitKey, zoneKey, meterKey, tariffKey, compareKeys } from "../src/util/keys.js";
import { lerp, clamp, trimDecimals, seededUnit, signOf, delta, relativeError } from "../src/util/math.js";
import { naturalCompare, naturalSort } from "../src/util/natural.js";
import { secondsOfDay, daysBetween, dayOf, dayBucket, periodStart, isNightly } from "../src/util/period.js";
import { equalWidth, bucketIndex, histogram, addHistograms } from "../src/util/buckets.js";
import { SeededRng } from "../src/util/seed.js";

describe("money", () => {
  it("converts euros to cents with half-even rounding", () => {
    expect(eurosToCents(1)).toBe(100);
    expect(eurosToCents(1.234)).toBe(123);
    expect(eurosToCents(1.235)).toBe(124);
    expect(eurosToCents(-0.5)).toBe(-50);
  });

  it("formats cents as euro strings", () => {
    expect(centsToEuros(0)).toBe("0.00");
    expect(centsToEuros(1234)).toBe("12.34");
    expect(centsToEuros(-5)).toBe("-0.05");
  });

  it("sums cents exactly", () => {
    expect(sumCents([1, 2, 3])).toBe(6);
    expect(sumCents([])).toBe(0);
  });

  it("scales and applies surcharges deterministically", () => {
    expect(scaleCents(100, 0.5)).toBe(50);
    expect(surcharge(100, 5)).toBe(105);
    expect(clampCents(150, 100)).toBe(100);
    expect(clampCents(-2, 100)).toBe(0);
    expect(isZero(0)).toBe(true);
    expect(isZero(1)).toBe(false);
  });
});

describe("keys", () => {
  it("builds and splits canonical keys", () => {
    const k = makeKey("z", "north", "res");
    expect(splitKey(k)).toEqual({ prefix: "z", parts: ["north", "res"] });
  });

  it("provides convenience constructors", () => {
    expect(zoneKey("n", "s1")).toBe("z:n:s1");
    expect(meterKey("d", "x")).toBe("m:d:x");
    expect(tariffKey("d", "winter")).toBe("t:d:winter");
  });

  it("compares keys lexicographically", () => {
    expect(compareKeys("a", "b")).toBe(-1);
    expect(compareKeys("b", "a")).toBe(1);
    expect(compareKeys("a", "a")).toBe(0);
  });
});

describe("math helpers", () => {
  it("interpolates and clamps", () => {
    expect(lerp(0, 10, 0.5)).toBe(5);
    expect(clamp(7, 0, 5)).toBe(5);
    expect(trimDecimals(1.23456, 2)).toBe(1.23);
  });

  it("seeded unit is deterministic and in range", () => {
    const a = seededUnit(7);
    const b = seededUnit(7);
    expect(a).toBe(b);
    expect(a >= 0 && a < 1).toBe(true);
  });

  it("computes signs, deltas and relative errors", () => {
    expect(signOf(-3)).toBe(-1);
    expect(delta(4, 6)).toBe(2);
    expect(relativeError(0, 0)).toBe(0);
    expect(relativeError(5, 5)).toBe(0);
    expect(relativeError(3, 1)).toBe(2);
  });
});

describe("natural order", () => {
  it("orders embedded numbers numerically", () => {
    expect(naturalCompare("R2", "R10")).toBe(-1);
    expect(naturalCompare("R10", "R2")).toBe(1);
    expect(naturalCompare("R2", "R2")).toBe(0);
  });

  it("sorts mixed ids", () => {
    const ids = ["R10", "R2", "R1b", "R1a", "R1"];
    const sorted = naturalSort(ids);
    expect(sorted).toEqual(["R1", "R1a", "R1b", "R2", "R10"]);
  });
});

describe("period arithmetic", () => {
  it("splits instants into days and buckets", () => {
    expect(secondsOfDay(1, 30)).toBe(5400);
    expect(daysBetween(0, 86400)).toBe(1);
    expect(dayOf(86400 * 2 + 5)).toBe(2);
    expect(dayBucket(10 * 3600)).toBe("morning");
    expect(dayBucket(20 * 3600)).toBe("evening");
    expect(dayBucket(2 * 3600)).toBe("night");
  });

  it("rounds to period starts and detects nightly windows", () => {
    expect(periodStart(3665, 3600)).toBe(3600);
    expect(isNightly(2 * 3600, 22 * 3600, 6 * 3600)).toBe(true);
    expect(isNightly(23 * 3600, 22 * 3600, 6 * 3600)).toBe(true);
    expect(isNightly(10 * 3600, 22 * 3600, 6 * 3600)).toBe(false);
  });
});

describe("buckets and rng", () => {
  it("builds equal-width buckets and histograms", () => {
    const buckets = equalWidth(0, 10, 5);
    expect(buckets.length).toBe(5);
    expect(bucketIndex(9.9, 0, 10, 5)).toBe(4);
    expect(bucketIndex(-1, 0, 10, 5)).toBe(0);
    expect(histogram([1, 1, 9], 0, 10, 5)).toEqual([2, 0, 0, 0, 1]);
    expect(addHistograms([1, 2], [3, 4, 5])).toEqual([4, 6, 5]);
  });

  it("seeded rng is reproducible", () => {
    const a = new SeededRng(42);
    const b = new SeededRng(42);
    expect(a.next()).toBe(b.next());
    expect(a.unit()).toBe(b.unit());
    expect(a.int(1, 6) >= 1 && a.int(1, 6) <= 6).toBe(true);
  });
});

