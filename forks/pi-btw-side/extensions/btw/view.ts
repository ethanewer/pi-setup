/**
 * The side-conversation view.
 *
 * A full-screen overlay that shows the side thread and nothing else, the way Codex's
 * /side replaces the chat view with a clean thread and returns on Ctrl+C. The main
 * thread is not touched: it is hidden behind this view and keeps running, and its
 * transcript is intact when the view closes.
 *
 * Messages are rendered with Pi's own components, so the side conversation looks like
 * the real chat rather than like a widget: same markdown, same thinking blocks, same
 * user-message styling.
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import {
	AssistantMessageComponent,
	getMarkdownTheme,
	getSelectListTheme,
	type Theme,
	UserMessageComponent,
} from "@earendil-works/pi-coding-agent";
import { type Component, Editor, type Focusable, matchesKey, type TUI, visibleWidth } from "@earendil-works/pi-tui";

/** What the main thread is doing, shown top right the way Codex shows parent status. */
export type MainStatus = "working" | "idle";

export interface SideViewOptions {
	title: string;
	/** Submitted text from the composer. The view does not clear it until this resolves. */
	onSubmit: (text: string) => void;
	/** Escape: leave and discard the thread, whatever it is doing. */
	onClose: () => void;
	/** Called with the composer text when the view closes, so a draft survives a reopen. */
	onDraft: (text: string) => void;
	initialDraft?: string;
}

type Block =
	| { kind: "user"; component: UserMessageComponent }
	| { kind: "assistant"; component: AssistantMessageComponent; message: AssistantMessage }
	| { kind: "tool"; id: string; label: string; state: "running" | "done" | "error" }
	| { kind: "notice"; text: string; tone: "dim" | "error" };

const MIN_TRANSCRIPT_ROWS = 3;
const FALLBACK_ROWS = 40;

export class SideView implements Component, Focusable {
	focused = true;

	private readonly blocks: Block[] = [];
	private readonly editor: Editor;
	private mainStatus: MainStatus = "idle";
	private busy = false;
	private spinnerFrame = 0;
	/** Rows scrolled up from the bottom. 0 sticks to the newest output. */
	private scrollBack = 0;
	private lastTranscriptRows = 0;
	private lastTotalRows = 0;

	constructor(
		private readonly tui: TUI,
		private readonly theme: Theme,
		private readonly options: SideViewOptions,
	) {
		this.editor = new Editor(tui, {
			borderColor: (text: string) => theme.fg("dim", text),
			selectList: getSelectListTheme(),
		});
		this.editor.onSubmit = (text: string) => {
			const trimmed = text.trim();
			if (trimmed.length === 0) return;
			this.editor.setText("");
			this.editor.addToHistory(trimmed);
			this.options.onSubmit(trimmed);
		};
		if (options.initialDraft) this.editor.setText(options.initialDraft);
		this.editor.focused = true;
	}

	// ---- state updates, all called from the extension ----

	addUser(text: string): void {
		this.blocks.push({ kind: "user", component: new UserMessageComponent(text, getMarkdownTheme(), 0) });
		this.stickToBottom();
	}

	addNotice(text: string, tone: "dim" | "error" = "dim"): void {
		this.blocks.push({ kind: "notice", text, tone });
		this.stickToBottom();
	}

	startAssistant(message: AssistantMessage): void {
		const component = new AssistantMessageComponent(message, false, getMarkdownTheme());
		this.blocks.push({ kind: "assistant", component, message });
		this.stickToBottom();
	}

	updateAssistant(message: AssistantMessage): void {
		// Streaming replaces the message object, so match on the newest assistant block
		// rather than by identity.
		for (let i = this.blocks.length - 1; i >= 0; i--) {
			const block = this.blocks[i];
			if (block.kind !== "assistant") continue;
			block.message = message;
			block.component.updateContent(message);
			this.stickToBottom();
			return;
		}
		this.startAssistant(message);
	}

	startTool(id: string, label: string): void {
		this.blocks.push({ kind: "tool", id, label, state: "running" });
		this.stickToBottom();
	}

	endTool(id: string, isError: boolean): void {
		for (let i = this.blocks.length - 1; i >= 0; i--) {
			const block = this.blocks[i];
			if (block.kind === "tool" && block.id === id) {
				block.state = isError ? "error" : "done";
				break;
			}
		}
		this.tui.requestRender();
	}

	setBusy(busy: boolean): void {
		this.busy = busy;
		this.stickToBottom();
	}

	setMainStatus(status: MainStatus): void {
		if (this.mainStatus === status) return;
		this.mainStatus = status;
		this.tui.requestRender();
	}

	tickSpinner(): void {
		if (!this.busy) return;
		this.spinnerFrame = (this.spinnerFrame + 1) % SPINNER.length;
		this.tui.requestRender();
	}

	private stickToBottom(): void {
		this.scrollBack = 0;
		this.tui.requestRender();
	}

	// ---- input ----

	handleInput(data: string): void {
		if (matchesKey(data, "escape")) {
			// Escape always returns to the main thread, including mid-answer. Leaving
			// discards the thread anyway, so "stop this answer" and "leave" are the same
			// action; making the first press mean only "stop" was a trap, because the key
			// silently did nothing visible when the view was busy.
			//
			// Codex leaves on Ctrl+C. That key never reaches a focused component here — Pi
			// claims it for clear/exit — so escape is the only exit, and the footer says so.
			this.options.onDraft(this.editor.getText());
			this.options.onClose();
			return;
		}

		if (matchesKey(data, "pageUp")) return this.scrollBy(this.lastTranscriptRows - 1);
		if (matchesKey(data, "pageDown")) return this.scrollBy(-(this.lastTranscriptRows - 1));
		if (matchesKey(data, "shift+up")) return this.scrollBy(1);
		if (matchesKey(data, "shift+down")) return this.scrollBy(-1);

		this.editor.focused = this.focused;
		this.editor.handleInput(data);
		this.tui.requestRender();
	}

	private scrollBy(rows: number): void {
		const max = Math.max(0, this.lastTotalRows - this.lastTranscriptRows);
		this.scrollBack = Math.min(max, Math.max(0, this.scrollBack + rows));
		this.tui.requestRender();
	}

	invalidate(): void {
		for (const block of this.blocks) {
			if (block.kind === "user" || block.kind === "assistant") block.component.invalidate();
		}
		this.editor.invalidate();
	}

	// ---- rendering ----

	render(width: number): string[] {
		const rows = terminalRows();
		this.editor.focused = this.focused;

		const header = this.renderHeader(width);
		const editor = this.editor.render(width);
		const footer = [this.renderFooter(width)];
		const chrome = header.length + editor.length + footer.length;
		const transcriptRows = Math.max(MIN_TRANSCRIPT_ROWS, rows - chrome);

		const body = this.renderTranscript(width);
		this.lastTotalRows = body.length;
		this.lastTranscriptRows = transcriptRows;

		let visible: string[];
		if (body.length <= transcriptRows) {
			// A short conversation grows downward from the top, like the main chat: header,
			// what has been said, then the composer directly under it. Padding above
			// instead would strand the composer at the bottom of a tall terminal behind a
			// wall of blank rows.
			visible = body;
		} else {
			const end = body.length - this.scrollBack;
			visible = body.slice(Math.max(0, end - transcriptRows), end);
		}

		const lines = [...header, ...visible, ...editor, ...footer];
		// The overlay composites onto the chat behind it, so it has to stay opaque for the
		// full height even when there is nothing to put there yet.
		while (lines.length < rows) lines.push("");
		// Same reason, horizontally: a short line would let the main transcript show through.
		return lines.map((line) => pad(line, width));
	}

	private renderHeader(width: number): string[] {
		const left = `${this.theme.fg("accent", "btw")} ${this.theme.fg("dim", `· ${this.options.title}`)}`;
		const right = this.theme.fg("dim", this.mainStatus === "working" ? "main thread: working" : "main thread: idle");
		return [row(left, right, width), ""];
	}

	private renderFooter(width: number): string {
		const left = this.busy
			? `${this.theme.fg("accent", SPINNER[this.spinnerFrame])} ${this.theme.fg("dim", "answering · esc return to the main thread")}`
			: this.theme.fg("dim", "esc return to the main thread");
		const right = this.theme.fg("dim", this.scrollBack > 0 ? `scrolled ${this.scrollBack} · shift+↓ to follow` : "side conversation");
		return row(left, right, width);
	}

	private renderTranscript(width: number): string[] {
		const lines: string[] = [];
		for (const block of this.blocks) {
			// Pi's message components carry their own trailing padding, so only the
			// bare-line blocks need a separator of their own.
			if (lines.length > 0 && (block.kind === "tool" || block.kind === "notice")) lines.push("");
			switch (block.kind) {
				case "user":
				case "assistant":
					lines.push(...block.component.render(width));
					break;
				case "tool": {
					const mark = block.state === "running" ? "⋯" : block.state === "error" ? "✗" : "✓";
					const color = block.state === "error" ? "error" : "dim";
					lines.push(this.theme.fg(color, `  ${mark} ${block.label}`));
					break;
				}
				case "notice":
					lines.push(this.theme.fg(block.tone === "error" ? "error" : "dim", `  ${block.text}`));
					break;
			}
		}
		return lines;
	}
}

const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

function terminalRows(): number {
	const rows = process.stdout.rows;
	return typeof rows === "number" && rows > 10 ? rows : FALLBACK_ROWS;
}

/** Left text and right text on one line, separated by padding. */
function row(left: string, right: string, width: number): string {
	const gap = width - visibleWidth(left) - visibleWidth(right);
	if (gap < 1) return truncate(left, width);
	return left + " ".repeat(gap) + right;
}

function pad(line: string, width: number): string {
	const used = visibleWidth(line);
	if (used >= width) return line;
	return line + " ".repeat(width - used);
}

function truncate(line: string, width: number): string {
	return visibleWidth(line) <= width ? line : line.slice(0, Math.max(0, width));
}
