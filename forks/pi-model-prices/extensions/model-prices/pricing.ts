/**
 * Pure pricing-label helpers for the /models picker. No TUI imports so the
 * formatting logic can be unit-tested without Pi's packages installed.
 *
 * All rates are dollars per million tokens, which is exactly what Pi stores in
 * `model.cost` (and what OpenRouter and the vendor catalogs quote).
 */

export interface CostRates {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
}

export interface CostTier extends CostRates {
	/** Total input usage above which this tier applies to the whole request. */
	inputTokensAbove: number;
}

/**
 * Format a per-million-token dollar rate. Two decimals is the convention
 * ($1.40), but a third is kept when it is significant: DeepSeek's $0.016 cache
 * read would round away at two, and "cache read" rates are exactly the small
 * ones where the precision matters.
 */
export function formatCost(value: number): string {
	if (!Number.isFinite(value)) return "?";
	return value.toFixed(3).replace(/(\.\d\d)0$/, "$1");
}

/**
 * The rate components of a badge, in display order: in, out, cache write,
 * cache read. Zero components are omitted — a $0 cache write is the common
 * case (OpenRouter passes cache writes through at $0 for many models) and
 * printing it would only add noise.
 */
export function rateParts(cost: CostRates | undefined): string[] {
	if (!cost) return [];
	const parts: string[] = [];
	if (cost.input > 0) parts.push(`$${formatCost(cost.input)} in`);
	if (cost.output > 0) parts.push(`$${formatCost(cost.output)} out`);
	if (cost.cacheWrite > 0) parts.push(`$${formatCost(cost.cacheWrite)} cache write`);
	if (cost.cacheRead > 0) parts.push(`$${formatCost(cost.cacheRead)} cache read`);
	return parts;
}

/**
 * The inside of the `[provider, …]` badge. A subscription model shows just
 * `sub` — per-token prices are not what the user pays there, and printing
 * implied rates next to "sub" invites misreading them as the bill.
 */
export function badgeLabel(cost: CostRates | undefined, subscription: boolean): string {
	if (subscription) return "sub";
	return rateParts(cost).join(", ");
}

/** One line per input-pricing tier, for the footer of the selected model. */
export function tierLines(tiers: readonly CostTier[] | undefined): string[] {
	if (!tiers?.length) return [];
	return tiers
		.slice()
		.sort((a, b) => a.inputTokensAbove - b.inputTokensAbove)
		.map((tier) => {
			const threshold = `above ${Math.round(tier.inputTokensAbove / 1000)}k input tokens`;
			const rates = rateParts(tier).join(", ");
			return `long-context rates ${threshold} (whole request): ${rates}`;
		});
}
