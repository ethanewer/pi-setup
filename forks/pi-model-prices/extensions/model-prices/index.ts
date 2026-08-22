/**
 * /models — a model picker that shows API prices.
 *
 * The built-in /model selector shows `id [provider]` and nothing else, and Pi
 * offers no extension hook into it. This command is the same picker — search,
 * arrow keys, Enter to switch, Esc to cancel, Tab to toggle the scoped/all
 * scope — with each row annotated:
 *
 *   → z-ai/glm-5.3 [openrouter, $1.40 in, $4.40 out, $0.26 cache read] ✓
 *     gpt-5.6-luna [openai, $0.20 in, $1.20 out, $0.25 cache write, $0.02 cache read]
 *
 * Rates are dollars per million tokens from the model catalog (the same
 * metadata Pi's cost accounting uses, including OpenRouter's refreshed
 * catalog). Models reached through a subscription login show `[provider, sub]`
 * instead of rates. A model whose long-context tier applies above an input
 * threshold gets a footer line, because the row's rates are the short-context
 * ones and silently omitting that would misprice a long session.
 *
 * `/models <provider/model>` (or a bare `<model>`) switches directly, the way
 * the built-in command's argument form does.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { Theme } from "@earendil-works/pi-coding-agent";
import type { Model } from "@earendil-works/pi-ai";
import { modelsAreEqual } from "@earendil-works/pi-ai";
import type { AutocompleteItem, Focusable, KeybindingsManager, TUI } from "@earendil-works/pi-tui";
import { Container, fuzzyFilter, Input, Spacer, Text } from "@earendil-works/pi-tui";

import { badgeLabel, tierLines } from "./pricing.js";

interface PickerRow {
	model: Model<any>;
	/** Inside of the `[provider, …]` badge: rate list, "sub", or "". */
	badge: string;
}

/** The model-registry slice this module needs, so tests can fake it. */
interface RegistryCtx {
	scopedModels: readonly { model: Model<any> }[];
	modelRegistry: {
		getAvailable(): Model<any>[];
		isUsingOAuth(model: Model<any>): boolean;
		getProvider(provider: string): { auth?: { oauth?: { isSubscription?: boolean } } } | undefined;
	};
}

/** Model list to pick from: the session's scoped models when set, else everything available. */
function candidateModels(ctx: RegistryCtx): Model<any>[] {
	return ctx.scopedModels.length > 0 ? ctx.scopedModels.map((s) => s.model) : ctx.modelRegistry.getAvailable();
}

/** Whether this model's provider is currently reached through a subscription login. */
function isSubscription(ctx: RegistryCtx, model: Model<any>): boolean {
	// Mirrors ModelRuntime.isUsingSubscription: OAuth in use AND the provider's
	// OAuth flow is backed by a subscription (Claude Pro/Max, ChatGPT, Grok, …).
	if (!ctx.modelRegistry.isUsingOAuth(model)) return false;
	return ctx.modelRegistry.getProvider(model.provider)?.auth?.oauth?.isSubscription === true;
}

function buildRow(ctx: RegistryCtx, model: Model<any>): PickerRow {
	return { model, badge: badgeLabel(model.cost, isSubscription(ctx, model)) };
}

function sortRows(rows: readonly PickerRow[], currentModel: Model<any> | undefined): PickerRow[] {
	return rows.slice().sort((a, b) => {
		const aCurrent = modelsAreEqual(currentModel, a.model);
		const bCurrent = modelsAreEqual(currentModel, b.model);
		if (aCurrent !== bCurrent) return aCurrent ? -1 : 1;
		return (
			a.model.provider.localeCompare(b.model.provider) || a.model.id.localeCompare(b.model.id)
		);
	});
}

function rowLabel(row: PickerRow): string {
	const badge = row.badge ? `, ${row.badge}` : "";
	return `${row.model.id} [${row.model.provider}${badge}]`;
}

const MAX_VISIBLE = 10;

class ModelPricePicker extends Container implements Focusable {
	private readonly tui: TUI;
	private readonly theme: Theme;
	private readonly keybindings: KeybindingsManager;
	private readonly currentModel: Model<any> | undefined;
	private readonly scopedRows: readonly PickerRow[];
	private readonly allRows: readonly PickerRow[];
	private rows: readonly PickerRow[];
	private filtered: readonly PickerRow[];
	private selectedIndex = 0;
	private readonly searchInput = new Input();
	private readonly listContainer = new Container();
	private readonly scopeText: Text | undefined;
	private readonly onSelect: (model: Model<any>) => void;
	private readonly onCancel: () => void;
	private _focused = false;

	constructor(options: {
		tui: TUI;
		theme: Theme;
		keybindings: KeybindingsManager;
		currentModel: Model<any> | undefined;
		scopedRows: readonly PickerRow[];
		allRows: readonly PickerRow[];
		onSelect: (model: Model<any>) => void;
		onCancel: () => void;
	}) {
		super();
		this.tui = options.tui;
		this.theme = options.theme;
		this.keybindings = options.keybindings;
		this.currentModel = options.currentModel;
		this.scopedRows = options.scopedRows;
		this.allRows = options.allRows;
		this.onSelect = options.onSelect;
		this.onCancel = options.onCancel;

		// Like the built-in selector: start in the scoped view when a scope is
		// configured, otherwise show every available model.
		this.rows = this.scopedRows.length > 0 ? this.scopedRows : this.allRows;
		this.filtered = this.rows;

		this.addChild(new Spacer(1));
		if (this.scopedRows.length > 0) {
			this.scopeText = new Text(this.scopeLabel(), 0, 0);
			this.addChild(this.scopeText);
			this.addChild(new Text(this.theme.fg("muted", "tab (all/scoped)"), 0, 0));
		} else {
			this.addChild(
				new Text(
					this.theme.fg(
						"warning",
						"Only showing models from configured providers. Use /login to add providers.",
					),
					0,
					0,
				),
			);
		}
		this.addChild(
			new Text(
				this.theme.fg("muted", "Type to filter, up/down to move, Enter to switch, Esc to cancel"),
				0,
				0,
			),
		);
		this.addChild(new Spacer(1));
		this.addChild(this.searchInput);
		this.addChild(new Spacer(1));
		this.addChild(this.listContainer);
		this.addChild(new Spacer(1));

		this.updateList();
		this.tui.requestRender();
	}

	get focused(): boolean {
		return this._focused;
	}

	set focused(value: boolean) {
		this._focused = value;
		// Propagate for IME cursor positioning, per the TUI contract.
		this.searchInput.focused = value;
	}

	private scopeLabel(): string {
		const scoped = this.rows === this.scopedRows;
		const all = this.theme.fg(scoped ? "muted" : "accent", "all");
		const only = this.theme.fg(scoped ? "accent" : "muted", "scoped");
		return `${this.theme.fg("muted", "Scope: ")}${all}${this.theme.fg("muted", " | ")}${only}`;
	}

	private filter(query: string): void {
		this.filtered = query
			? fuzzyFilter(this.rows as PickerRow[], query, (row) =>
					`${row.model.provider}/${row.model.id} ${row.model.name}`,
				)
			: this.rows;
		// Jump to the best match while filtering; keep the position when the
		// query is cleared, matching the built-in selector's behaviour.
		this.selectedIndex = query
			? 0
			: Math.min(this.selectedIndex, Math.max(0, this.filtered.length - 1));
		this.updateList();
	}

	private updateList(): void {
		this.listContainer.clear();
		const startIndex = Math.max(
			0,
			Math.min(this.selectedIndex - Math.floor(MAX_VISIBLE / 2), this.filtered.length - MAX_VISIBLE),
		);
		const endIndex = Math.min(startIndex + MAX_VISIBLE, this.filtered.length);

		for (let i = startIndex; i < endIndex; i++) {
			const row = this.filtered[i];
			if (!row) continue;
			const isSelected = i === this.selectedIndex;
			const isCurrent = modelsAreEqual(this.currentModel, row.model);
			let line: string;
			if (isSelected) {
				line = this.theme.fg("accent", `→ ${rowLabel(row)}`);
			} else {
				line = `  ${rowLabel(row)}`;
			}
			if (isCurrent) line += this.theme.fg("success", " ✓");
			this.listContainer.addChild(new Text(line, 0, 0));
		}

		if (startIndex > 0 || endIndex < this.filtered.length) {
			this.listContainer.addChild(
				new Text(this.theme.fg("muted", `  (${this.selectedIndex + 1}/${this.filtered.length})`), 0, 0),
			);
		}

		if (this.filtered.length === 0) {
			this.listContainer.addChild(new Text(this.theme.fg("muted", "  No matching models"), 0, 0));
		} else {
			const selected = this.filtered[this.selectedIndex];
			this.listContainer.addChild(new Spacer(1));
			const context = Math.round(selected.model.contextWindow / 1000);
			this.listContainer.addChild(
				new Text(
					this.theme.fg("muted", `  Model Name: ${selected.model.name} (${context}k context)`),
					0,
					0,
				),
			);
			// The row's rates are the base ones; say when a long-context tier
			// replaces them, or a long session looks cheaper than it is.
			for (const tier of tierLines(selected.model.cost?.tiers)) {
				this.listContainer.addChild(new Text(this.theme.fg("muted", `  ${tier}`), 0, 0));
			}
		}
	}

	handleInput(keyData: string): void {
		const kb = this.keybindings;
		if (kb.matches(keyData, "tui.input.tab")) {
			if (this.scopedRows.length > 0) {
				this.rows = this.rows === this.scopedRows ? this.allRows : this.scopedRows;
				const currentIndex = this.rows.findIndex((row) => modelsAreEqual(this.currentModel, row.model));
				this.selectedIndex = currentIndex >= 0 ? currentIndex : 0;
				this.scopeText?.setText(this.scopeLabel());
				this.filter(this.searchInput.getValue());
			}
			return;
		}
		if (kb.matches(keyData, "tui.select.up")) {
			if (this.filtered.length === 0) return;
			this.selectedIndex =
				this.selectedIndex === 0 ? this.filtered.length - 1 : this.selectedIndex - 1;
			this.updateList();
		} else if (kb.matches(keyData, "tui.select.down")) {
			if (this.filtered.length === 0) return;
			this.selectedIndex =
				this.selectedIndex === this.filtered.length - 1 ? 0 : this.selectedIndex + 1;
			this.updateList();
		} else if (kb.matches(keyData, "tui.select.confirm")) {
			const row = this.filtered[this.selectedIndex];
			if (row) this.onSelect(row.model);
		} else if (kb.matches(keyData, "tui.select.cancel")) {
			this.onCancel();
		} else {
			this.searchInput.handleInput(keyData);
			this.filter(this.searchInput.getValue());
		}
	}
}

async function switchTo(pi: ExtensionAPI, ctx: { ui: { notify(message: string, type?: "info" | "warning" | "error"): void } }, model: Model<any>): Promise<void> {
	const ok = await pi.setModel(model);
	if (!ok) {
		ctx.ui.notify(`No API key for ${model.provider}/${model.id}`, "error");
		return;
	}
	ctx.ui.notify(`Model: ${model.provider}/${model.id}`, "info");
}

export default function (pi: ExtensionAPI) {
	// Argument completions only receive a prefix, so the model list is cached
	// at session start for that one use; the handler always reads live state.
	let completionModels: Model<any>[] = [];

	pi.on("session_start", async (_event, ctx) => {
		completionModels = candidateModels(ctx);
	});

	pi.registerCommand("models", {
		description: "Select model with API prices (per-million-token in/out/cache rates)",
		getArgumentCompletions: (prefix: string): AutocompleteItem[] | null => {
			const items: AutocompleteItem[] = completionModels.map((m) => ({
				value: `${m.provider}/${m.id}`,
				label: m.id,
				description: m.provider,
			}));
			const lower = prefix.toLowerCase();
			const filtered = items.filter((item) => item.value.toLowerCase().includes(lower));
			return filtered.length > 0 ? filtered : null;
		},
		handler: async (args, ctx) => {
			const target = args.trim();
			const models = candidateModels(ctx);

			if (models.length === 0) {
				ctx.ui.notify("No models available. Use /login to configure providers.", "warning");
				return;
			}

			// Argument form: switch directly, like the built-in command.
			if (target) {
				const exact = models.find((m) => `${m.provider}/${m.id}` === target);
				if (exact) {
					await switchTo(pi, ctx, exact);
					return;
				}
				const byId = models.filter((m) => m.id === target);
				if (byId.length === 1) {
					await switchTo(pi, ctx, byId[0]);
				} else if (byId.length > 1) {
					const options = byId.map((m) => `${m.provider}/${m.id}`).join(", ");
					ctx.ui.notify(`Ambiguous model id; use provider/model: ${options}`, "warning");
				} else {
					ctx.ui.notify(`No model matches '${target}'`, "warning");
				}
				return;
			}

			const scopedRows = sortRows(
				ctx.scopedModels.map((s) => buildRow(ctx, s.model)),
				ctx.model,
			);
			const allRows = sortRows(
				models.map((m) => buildRow(ctx, m)),
				ctx.model,
			);

			// Outside the TUI there is no picker; the price list is the point,
			// so print it instead of degrading to a bare switch.
			if (ctx.mode !== "tui") {
				const rows = scopedRows.length > 0 ? scopedRows : allRows;
				const lines = rows.map((row) => `  ${rowLabel(row)}`);
				ctx.ui.notify(`Models:\n${lines.join("\n")}`, "info");
				return;
			}

			const selected = await ctx.ui.custom<Model<any> | null>(
				(tui, theme, keybindings, done) =>
					new ModelPricePicker({
						tui,
						theme,
						keybindings,
						currentModel: ctx.model,
						scopedRows,
						allRows,
						onSelect: (model) => done(model),
						onCancel: () => done(null),
					}),
			);
			if (selected) await switchTo(pi, ctx, selected);
		},
	});
}
