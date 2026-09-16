# -*- coding: utf-8 -*-
"""util modules of the cistern corpus (strict-mode correct by default)."""

CUT = [
    ("src/util/errors.ts", """/**
 * errors.ts - typed failure model for the cistern library.
 *
 * Every routine that can fail reports a CisError carrying a stable code
 * grouped by layer: U util, C config, D data, R reports, S service. A
 * short token and a human message travel with the error.
 */

export type ErrorCode =
  | "U-INTERNAL"
  | "U-INVARIANT"
  | "U-RANGE"
  | "C-UNKNOWN-KEY"
  | "C-BAD-TYPE"
  | "C-OUT-OF-BOUNDS"
  | "D-EMPTY"
  | "D-MALFORMED"
  | "D-COLLISION"
  | "D-NO-VALUE"
  | "R-EMPTY-ROW"
  | "S-NOT-CONVERGED"
  | "S-DIVIDED-BY-ZERO";

/** Error carrying a stable code and an operator-facing message. */
export class CisError extends Error {
  readonly code: ErrorCode;
  readonly detail: string;

  constructor(code: ErrorCode, message: string, detail = "") {
    super(message);
    this.name = "CisError";
    this.code = code;
    this.detail = detail;
  }

  /** One-line human summary including the detail payload when present. */
  summarize(): string {
    return `${this.code}: ${this.message}` + (this.detail ? ` (${this.detail})` : "");
  }
}

/** Shape of a failed invariant. */
export interface InvariantFailure {
  readonly label: string;
  readonly left: string;
  readonly right: string;
}

/** Throw a U-INVARIANT error when the condition does not hold. */
export function invariant(condition: boolean, label: string, left = "", right = ""): void {
  if (!condition) {
    const fail: InvariantFailure = { label, left, right };
    throw new CisError(
      "U-INVARIANT",
      `invariant failed: ${fail.label}`,
      `${fail.left} != ${fail.right}`,
    );
  }
}

/** Range check on a quantity; throws U-RANGE when out of bounds. */
export function assertRange(value: number, min: number, max: number, what: string): void {
  if (!Number.isFinite(value)) {
    throw new CisError("U-RANGE", `${what} must be finite, got ${value}`);
  }
  if (value < min || value > max) {
    throw new CisError("U-RANGE", `${what} out of range [${min}, ${max}]: ${value}`);
  }
}

/** Finiteness check with a human label. */
export function requireFinite(value: number, what: string): void {
  if (!Number.isFinite(value)) {
    throw new CisError("U-RANGE", `${what} is not a finite number`);
  }
}

/** Standard unknown-key failure helper. */
export function unknownKey(kind: string, key: string): CisError {
  return new CisError("C-UNKNOWN-KEY", `${kind} key not found: \`${key}\``);
}

"""),
    ("src/util/money.ts", """// money.ts - integer-cent money. Tariffs, billing and all reports pass
// through this module, so rounding is defined in exactly one place: sums
// accumulate in whole cents and a single half-even rounding happens at the
// boundary the report wants.

export type Cents = number;

export const CENTS_PER_EURO = 100;

/** Round a real value to the nearest integer, ties toward even. */
export function roundHalfEven(value: number): number {
  const floored = Math.floor(value);
  const frac = value - floored;
  if (frac > 0.5) {
    return floored + 1;
  }
  if (frac < 0.5) {
    return floored;
  }
  return floored % 2 === 0 ? floored : floored + 1;
}

/** Convert a euro amount expressed as a decimal number into cents. */
export function eurosToCents(euros: number): Cents {
  return roundHalfEven(euros * CENTS_PER_EURO);
}

/** Convert cents into a two-decimal euro string, signed when negative. */
export function centsToEuros(cents: Cents): string {
  const sign = cents < 0 ? "-" : "";
  const abs = Math.abs(cents);
  const whole = Math.floor(abs / CENTS_PER_EURO);
  const frac = abs % CENTS_PER_EURO;
  return `${sign}${whole}.${String(frac).padStart(2, "0")}`;
}

/** Sum a list of cent amounts exactly. */
export function sumCents(values: readonly Cents[]): Cents {
  let total = 0;
  for (const v of values) {
    total += v;
  }
  return total;
}

/** Scale cents by a decimal factor with half-even rounding. */
export function scaleCents(cents: Cents, factor: number): Cents {
  return roundHalfEven(cents * factor);
}

/** Apply a surcharge in the given percent (5 => +5%) to cents. */
export function surcharge(cents: Cents, percent: number): Cents {
  return roundHalfEven(cents * (1 + percent / 100));
}

/** Clamp a cent amount into the [0, limit] band. */
export function clampCents(cents: Cents, limit: Cents): Cents {
  if (cents < 0) {
    return 0;
  }
  if (cents > limit) {
    return limit;
  }
  return cents;
}

/** True when the amount is within half a cent of zero. */
export function isZero(cents: Cents): boolean {
  return Math.abs(cents) < 1;
}

/** True when the first amount is strictly larger than the second. */
export function exceeds(amount: Cents, limit: Cents): boolean {
  return amount > limit;
}

"""),
    ("src/util/keys.ts", """// keys.ts: canonical compound keys for pools, meters and tariff tables.
// A canonical key is a fixed concatenation of components joined by colons,
// so sorting and dictionary lookup see one plain string.

export interface KeyParts {
  readonly prefix: string;
  readonly parts: readonly string[];
}

/** Join a prefix and any number of parts into a canonical key. */
export function makeKey(prefix: string, ...parts: readonly string[]): string {
  return [prefix, ...parts].join(":");
}

/** Split a canonical key back into prefix and components. */
export function splitKey(key: string): KeyParts {
  const pieces = key.split(":");
  return { prefix: pieces[0] ?? "", parts: pieces.slice(1) };
}

/** Canonical key for a zone/sector pair. */
export function zoneKey(zone: string, sector: string): string {
  return makeKey("z", zone, sector);
}

/** Canonical key for a meter endpoint. */
export function meterKey(district: string, serial: string): string {
  return makeKey("m", district, serial);
}

/** Canonical key for a tariff table. */
export function tariffKey(district: string, season: string): string {
  return makeKey("t", district, season);
}

/** Lexicographic comparison returning -1, 0 or +1. */
export function compareKeys(a: string, b: string): number {
  if (a < b) {
    return -1;
  }
  if (a > b) {
    return 1;
  }
  return 0;
}

/** Guard that a key starts with one of the accepted prefixes. */
export function assertKeyPrefix(key: string, prefixes: readonly string[]): void {
  const first = key.split(":")[0] ?? "";
  if (prefixes.indexOf(first) < 0) {
    throw new Error(`unexpected key prefix '${first}' in '${key}'`);
  }
}

"""),
    ("src/util/math.ts", """// math.ts: small deterministic numeric helpers used by the hydraulics and
// leak layers. All computations stay in IEEE doubles; float results feed
// only reporting, never money.

/** Linear interpolation between a and b at position t. */
export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

/** Clamp a value into a closed interval. */
export function clamp(value: number, lo: number, hi: number): number {
  if (value < lo) {
    return lo;
  }
  if (value > hi) {
    return hi;
  }
  return value;
}

/** Trim a value to a fixed number of decimals. */
export function trimDecimals(value: number, digits: number): number {
  const f = Math.pow(10, digits);
  return Math.round(value * f) / f;
}

/** Deterministic pseudo-random in [0,1) from a seed word. */
export function seededUnit(seed: number): number {
  let x = Math.abs(Math.floor(seed)) + 1;
  x = (x * 9301 + 49297) % 233280;
  return x / 233280;
}

/** Sign of a number: -1, 0 or 1. */
export function signOf(value: number): number {
  return value < 0 ? -1 : value > 0 ? 1 : 0;
}

/** Absolute difference of two numbers. */
export function delta(a: number, b: number): number {
  return Math.abs(a - b);
}

/** Relative difference, 0 when both are zero. */
export function relativeError(actual: number, expected: number): number {
  if (expected === 0) {
    return actual === 0 ? 0 : Infinity;
  }
  return Math.abs(actual - expected) / Math.abs(expected);
}

"""),
]