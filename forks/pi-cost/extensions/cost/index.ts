/**
 * /cost — live OpenRouter rates for the pinned models.
 *
 * Lists every OpenRouter model in the session's scoped set (the enabledModels
 * the installer pins for pi, piwf, and p), with rates fetched at command time
 * from openrouter.ai — not from Pi's cached catalog, which refreshes at most
 * every four hours. OpenAI subscription models are deliberately excluded: they
 * are a different provider and are billed outside OpenRouter.
 *
 * Rates are dollars per million tokens. When OpenRouter cannot be reached, the
 * command falls back to the catalog metadata Pi's cost accounting uses and says
 * so, rather than showing stale numbers as live.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { Model } from "@earendil-works/pi-ai";
import { costTable } from "./rates.js";
import type { OpenRouterModel } from "./rates.js";

const OPENROUTER_CATALOG_URL = "https://openrouter.ai/api/v1/models";
const FETCH_TIMEOUT_MS = 10_000;

/** The scoped models, falling back to everything available when no scope is set. */
function pinnedModels(ctx: ExtensionContext): Model<any>[] {
	const scoped = (ctx.scopedModels ?? []).map((entry) => entry.model);
	const pool = scoped.length > 0 ? scoped : ctx.modelRegistry.getAvailable();
	return pool.filter((m) => m.provider === "openrouter");
}

async function fetchOpenRouterCatalog(): Promise<OpenRouterModel[] | undefined> {
	try {
		const response = await fetch(OPENROUTER_CATALOG_URL, { signal: AbortSignal.timeout(10_000) });
		if (!response.ok) throw new Error(`HTTP ${response.status}`);
		const payload = (await response.json()) as { data?: OpenRouterModel[] };
		return payload.data;
	} catch {
		return undefined;
	}
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("cost", {
		description: "Live OpenRouter rates ($/Mtok) for the pinned models",
		handler: async (_args, ctx) => {
			const pinned = pinnedModels(ctx);
			if (pinned.length === 0) {
				ctx.ui.notify("cost: no OpenRouter models in the scoped set (/scoped-models)", "warning");
				return;
			}
			const catalog = await fetchOpenRouterCatalog();
			const table = costTable(
				pinned.map((m) => ({ id: m.id, cost: m.cost })),
				catalog,
			);
			const header =
				catalog === undefined
					? "OpenRouter rates ($/Mtok) — openrouter.ai unreachable, showing cached catalog"
					: "OpenRouter rates ($/Mtok), live from openrouter.ai";
			ctx.ui.notify(`${header}\n\n${table}`, "info");
		},
	});
}