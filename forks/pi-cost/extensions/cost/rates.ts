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
	overrides?: Array<{ prompt?: string | null; completion?: string | null }> | null;
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
 * Tier note for models whose rate depends on a usage window (like V4.1 Flash's
 * off-peak/peak pricing). The row shows the off-peak rates, so name the peak
 * ones instead of silently understating the price. Empty when the overrides
 * all charge the same as the base rates.
 */
export function tierNote(pricing: OpenRouterPricing): string {
	const overrides = pricing.overrides;
	if (!Array.isArray(overrides) || overrides.length === 0) return "";
	const pairs = new Set<string>();
	for (const o of overrides) {
		const input = num(o.prompt);
		const output = num(o.completion);
		if (input !== undefined || output !== undefined) {
			pairs.add(`${fmt(perMtok(input ?? 0))} in / ${fmt(perMtok(output ?? 0))} out`);
		}
	}
	const base = `${fmt(perMtok(num(pricing.prompt) ?? 0))} in / ${fmt(perMtok(num(pricing.completion) ?? 0))} out`;
	const peak = [...pairs].filter((p) => p !== base);
	if (peak.length === 0) return "";
	return `peak windows up to ${[...peak].sort().join(", ")}`;
}

/**
 * The /cost output: one aligned row per pinned model, tier notes indented on a
 * continuation line (rows are long, and the note belongs to its model).
 */
export function costTable(
	models: readonly PinnedModel[],
	openrouter: readonly OpenRouterModel[] | undefined,
): string {
	const byId = new Map((openrouter ?? []).map((m) => [m.id, m.pricing ?? {}]));
	const width = Math.max(...models.map((m) => m.id.length));
	const lines = models.map((m) => {
		const pricing = byId.get(m.id);
		let rates: string;
		if (pricing) {
			rates = rateLabel(pricing) || "free";
		} else if (m.cost) {
			// Not in the fetched catalog (renamed, or the fetch fell back to the
			// cached one) — still show what Pi's own accounting uses.
			rates = `${catalogRateLabel(m.cost)} (catalog)`;
		} else {
			rates = "not priced";
		}
		const note = pricing ? tierNote(pricing) : "";
		const label = `  ${m.id.padEnd(width)}  ${rates}`;
		return note ? `${label}\n    ${note}` : label;
	});
	return lines.join("\n");
}