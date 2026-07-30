import { type EntryRenderer, getMarkdownTheme, type Theme } from "@earendil-works/pi-coding-agent";
import { Container, Markdown, Text } from "@earendil-works/pi-tui";

/** What a finished side exchange records. Never sent to the model — display only. */
export interface BtwExchange {
	question: string;
	answer: string;
	/** "provider/id" of the model that answered. */
	model: string;
	durationMs: number;
	toolCalls: number;
	timestamp: number;
	status: "ok" | "aborted" | "error";
	error?: string;
}

export const BTW_ENTRY_TYPE = "btw-exchange";

const COLLAPSED_ANSWER_LINES = 14;

function formatDuration(ms: number): string {
	if (ms < 1000) return `${ms}ms`;
	const seconds = ms / 1000;
	if (seconds < 60) return `${seconds.toFixed(seconds < 10 ? 1 : 0)}s`;
	const minutes = Math.floor(seconds / 60);
	return `${minutes}m${String(Math.round(seconds - minutes * 60)).padStart(2, "0")}s`;
}

export function headerLine(exchange: BtwExchange, theme: Theme): string {
	const parts = [exchange.model, formatDuration(exchange.durationMs)];
	if (exchange.toolCalls > 0) parts.push(`${exchange.toolCalls} tool${exchange.toolCalls === 1 ? "" : "s"}`);
	if (exchange.status === "aborted") parts.push("stopped");
	if (exchange.status === "error") parts.push("failed");
	return `${theme.fg("accent", "btw")} ${theme.fg("dim", `· ${parts.join(" · ")}`)}`;
}

/**
 * Renders the exchange inline in the transcript instead of in an overlay. This is the
 * whole point of the package: a side answer you can scroll back to and copy like any
 * other output, with no separate window to manage.
 */
export function createExchangeRenderer(): EntryRenderer<BtwExchange> {
	return (entry, options, theme) => {
		const data = entry.data;
		if (!data || typeof data !== "object") return undefined;

		const container = new Container();
		container.addChild(new Text(headerLine(data, theme), 1, 0));
		container.addChild(new Text(theme.fg("muted", `? ${data.question}`), 1, 0));

		if (data.status === "error") {
			container.addChild(new Text(theme.fg("error", data.error ?? "failed"), 1, 0));
			return container;
		}

		const body = data.answer.trim().length > 0 ? data.answer : theme.fg("dim", "(no answer)");
		const lines = body.split("\n");
		const truncated = !options.expanded && lines.length > COLLAPSED_ANSWER_LINES;
		const shown = truncated ? lines.slice(0, COLLAPSED_ANSWER_LINES).join("\n") : body;

		container.addChild(new Markdown(shown, 1, 0, getMarkdownTheme()));
		if (truncated) {
			container.addChild(
				new Text(theme.fg("dim", `… ${lines.length - COLLAPSED_ANSWER_LINES} more lines`), 1, 0),
			);
		}
		return container;
	};
}
