/**
 * Pure rate-formatting logic for /cost. No imports, no I/O — unit-testable.
 *
 * OpenRouter's /api/v1/models payload prices every field in dollars per single
 * token (e.g. "0.00000015"). Everything here converts to the $/Mtok rates the
 * occ picker and Pi's own cost accounting display, omits zero components, and
 * orders them in / cache write before cache read when charged.
 */

export interface OpenRouterPricing {
	prompt?: string | null;
	completion?: string | null;
	input_cache_read?: string | null;
	input_cache_write?: string | null;
	overrides?: Array<{
		prompt?: string | null;
		completion?: string | null;
		input_cache_read?: string | null;
		input_cache_write?: string | null;
		utc_days?: string[];
		utc_start?: number;
		utc_end?: number;
	}> | null;
}

/** Model.cost from Pi's catalog — already dollars per million tokens. */
export interface CatalogCost {
	input?: number;
	output?: number;
	cacheRead?: number;
	cacheWrite?: number;
}

export interface PinnedModel {
	id: string;
	cost?: CatalogCost;
}

export interface OpenRouterModel {
	id: string;
	pricing?: OpenRouterPricing;
}

function num(value: string | number | null | undefined): number | undefined {
	if (value === null || value === undefined) return undefined;
	const n = typeof value === "number" ? value : Number(value);
	return Number.isFinite(n) && n > 0 ? n : undefined;
}

function fmt(rate: number): string {
	if (rate >= 0.01) return `$${rate.toFixed(2)}`;
	// Small cache rates need their decimals ($0.003, $0.016): three, trimmed.
	return `$${rate.toFixed(3).replace(/0$/, "")}`;
}

function perMtok(rate: number): number {
	return rate * 1_000_000;
}

const DAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"] as const;

/** HHMM (e.g. 1000 = 10:00, 400 = 04:00) to minutes since UTC midnight. */
function hhmm(value: number): number {
	return Math.floor(value / 100) * 60 + (value % 100);
}

/**
 * The rates that apply right now: OpenRouter models like V4.1 Flash price
 * usage windows by UTC day and time-of-day (`utc_start`/`utc_end` are HHMM
 * times — 100 is 01:00, 1000 is 10:00; `utc_end: 0` means through end of
 * day). The first override whose day and window contain `now` wins, with its
 * fields applied over the base; when none match, the base rates apply. An
 * override with days but no window (the weekend entries) covers the whole day.
 */
export function effectivePricing(pricing: OpenRouterPricing, now: Date): OpenRouterPricing {
	const overrides = pricing.overrides;
	if (!Array.isArray(overrides) || overrides.length === 0) return pricing;
	const day = DAY_NAMES[now.getUTCDay()];
	const minute = now.getUTCHours() * 60 + now.getUTCMinutes();
	for (const override of overrides) {
		if (override.utc_days && !override.utc_days.includes(day)) continue;
		if (override.utc_start !== undefined || override.utc_end !== undefined) {
			const start = hhmm(override.utc_start ?? 0);
			// utc_end: 0 is OpenRouter's "through end of day" (24:00), not midnight.
			const end = override.utc_end === undefined || override.utc_end === 0 ? 24 * 60 : hhmm(override.utc_end);
			if (end > start) {
				if (minute < start || minute >= end) continue;
			} else if (minute >= end && minute < start) {
				// Window wraps midnight, e.g. 2200 → 0030; outside it means between
				// the wrapped end and the start.
				continue;
			}
		}
		return { ...pricing, ...override };
	}
	return pricing;
}

/**
 * The row's rate list: "$0.15 in / $0.60 out / $0.25 cache write / $0.03 cache
 * read". Cache write precedes cache read when charged, mirroring how the cost
 * breakdown is usually quoted; zero components are omitted. Empty string when
 * nothing is priced (e.g. a free model).
 */
export function rateLabel(pricing: OpenRouterPricing): string {
	const parts: string[] = [];
	const input = num(pricing.prompt);
	const output = num(pricing.completion);
	const cacheWrite = num(pricing.input_cache_write);
	const cacheRead = num(pricing.input_cache_read);
	if (input !== undefined) parts.push(`${fmt(perMtok(input))} in`);
	if (output !== undefined) parts.push(`${fmt(perMtok(output))} out`);
	if (cacheWrite !== undefined) parts.push(`${fmt(perMtok(cacheWrite))} cache write`);
	if (cacheRead !== undefined) parts.push(`${fmt(perMtok(cacheRead))} cache read`);
	return parts.join(" / ");
}

/** Same shape as rateLabel, but from the catalog's per-Mtok `cost` metadata. */
export function catalogRateLabel(cost: CatalogCost): string {
	const parts: string[] = [];
	if (num(cost.input) !== undefined) parts.push(`${fmt(cost.input as number)} in`);
	if (num(cost.output) !== undefined) parts.push(`${fmt(cost.output as number)} out`);
	if (num(cost.cacheWrite) !== undefined) parts.push(`${fmt(cost.cacheWrite as number)} cache write`);
	if (num(cost.cacheRead) !== undefined) parts.push(`${fmt(cost.cacheRead as number)} cache read`);
	return parts.join(" / ");
}

/**
 * The /cost output: one line per pinned model at the rates that apply when the
 * command runs — peak-window pricing during a peak window, off-peak otherwise.
 */
export function costTable(
	models: readonly PinnedModel[],
	openrouter: readonly OpenRouterModel[] | undefined,
	now: Date = new Date(),
): string {
	const byId = new Map((openrouter ?? []).map((m) => [m.id, m.pricing ?? {}]));
	const width = Math.max(...models.map((m) => m.id.length));
	const lines = models.map((m) => {
		const pricing = byId.get(m.id);
		let rates: string;
		if (pricing) {
			rates = rateLabel(effectivePricing(pricing, now)) || "free";
		} else if (m.cost) {
			// Not in the fetched catalog (renamed, or the fetch fell back to the
			// cached one) — still show what Pi's own accounting uses.
			rates = `${catalogRateLabel(m.cost)} (catalog)`;
		} else {
			rates = "not priced";
		}
		return `  ${m.id.padEnd(width)}  ${rates}`;
	});
	return lines.join("\n");
}