/**
 * /cost — live OpenRouter rates for the pinned models.
 *
 * Lists every OpenRouter model in the session's scoped set (the enabledModels
 * the installer pins for pi, piwf, and p), with rates fetched at command time
 * from openrouter.ai — not from Pi's cached catalog, which refreshes at most
 * every four hours. OpenAI subscription models are deliberately excluded: they
 * are a different provider and are billed outside OpenRouter.
 *
 * While the fetch runs, a cancellable loader with a spinner says so; escape
 * cancels the fetch. Each model is one line at the rates that apply when the
 * command runs — peak-window pricing during a peak window, off-peak otherwise.
 * When OpenRouter cannot be reached, the command falls back to the catalog
 * metadata Pi's cost accounting uses and says so, rather than showing stale
 * numbers as live.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { Model } from "@earendil-works/pi-ai";
import { CancellableLoader } from "@earendil-works/pi-tui";
import { costTable } from "./rates.js";
import type { OpenRouterModel } from "./rates.js";

const OPENROUTER_CATALOG_URL = "https://openrouter.ai/api/v1/models";

/** The scoped models, falling back to everything available when no scope is set. */
function pinnedModels(ctx: ExtensionContext): Model<any>[] {
	const scoped = (ctx.scopedModels ?? []).map((entry) => entry.model);
	const pool = scoped.length > 0 ? scoped : ctx.modelRegistry.getAvailable();
	return pool.filter((m) => m.provider === "openrouter");
}

async function fetchOpenRouterCatalog(signal?: AbortSignal): Promise<OpenRouterModel[] | undefined> {
	try {
		const response = await fetch(OPENROUTER_CATALOG_URL, { signal: signal ?? AbortSignal.timeout(10_000) });
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
			const models = pinned.map((m) => ({ id: m.id, cost: m.cost }));

			// A bare spinner while the fetch runs — no border frame, the editor slot
			// just shows the spinner line. Escape cancels (CancellableLoader).
			// A fetch with no UI (print/json modes never reach a command, but be
			// defensive) falls back to the plain timeout.
			let catalog: OpenRouterModel[] | undefined;
			if (ctx.hasUI) {
				const outcome = await ctx.ui.custom<{ cancelled: boolean; catalog?: OpenRouterModel[] }>(
					(tui, theme, _kb, done) => {
						const loader = new CancellableLoader(
							tui,
							(s) => theme.fg("accent", s),
							(s) => theme.fg("muted", s),
							"Fetching latest costs…",
						);
						loader.onAbort = () => done({ cancelled: true });
						// A failed fetch resolves without a catalog — the fallback below
						// applies, because the user did not cancel it.
						fetchOpenRouterCatalog(loader.signal).then(
							(data) => done({ cancelled: false, catalog: data ?? undefined }),
							() => done({ cancelled: false }),
						);
						return loader;
					},
				);
				if (outcome.cancelled) {
					ctx.ui.notify("cost: cancelled", "info");
					return;
				}
				catalog = outcome.catalog;
			} else {
				catalog = await fetchOpenRouterCatalog();
			}

			const table = costTable(models, catalog);
			// Rows only when live — the rates are self-explanatory. The one header
			// line is kept for the cached fallback, where "these are stale" matters.
			if (catalog === undefined) {
				ctx.ui.notify(`openrouter.ai unreachable — cached catalog rates ($/Mtok):\n\n${table}`, "warning");
			} else {
				ctx.ui.notify(table, "info");
			}
		},
	});
}