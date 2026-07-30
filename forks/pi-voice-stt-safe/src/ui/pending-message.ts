/**
 * A message the user has committed to sending, whose text does not exist yet.
 *
 * Pressing Enter while recording has to look like sending a message immediately, but the
 * model must not receive anything until the transcript arrives. So the spot just above
 * the composer — where Pi shows its own queued-message hints — holds a `[⠏ transcribing]`
 * line until the provider answers. Then the line disappears and the real message is sent
 * for the first time. If transcription fails, the line becomes an error and nothing is
 * ever sent.
 *
 * This is a widget rather than a transcript entry on purpose: an entry is rendered once
 * and committed to the scrollback, so it can neither animate nor be replaced afterwards.
 * A widget is re-rendered every frame, which is what makes the spinner turn and the line
 * vanish at the right moment.
 */

import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { type Component, truncateToWidth } from "@earendil-works/pi-tui";

import { animateRenderedLines, frameAt } from "./transcribing";

const WIDGET_KEY = "voice-pending";
/** Widgets render above the editor, so a long message must not push the transcript away. */
const MAX_LINES = 6;
/** How long a failure stays on screen before the line clears itself. */
const ERROR_LINGER_MS = 8000;

export type PendingIntent = "send" | "queue";

type PendingItem =
	/** `text` is the whole message with the placeholder standing in for the transcript. */
	| { id: number; status: "pending"; intent: PendingIntent; text: string }
	| { id: number; status: "failed"; message: string };

export type PendingStore = {
	begin(ctx: ExtensionContext, intent: PendingIntent, text: string): number;
	resolve(ctx: ExtensionContext, id: number): void;
	fail(ctx: ExtensionContext, id: number, message: string): void;
	count(): number;
	dispose(): void;
};

export const createPendingStore = (getTick: () => number): PendingStore => {
	const items: PendingItem[] = [];
	const timers = new Map<number, ReturnType<typeof setTimeout>>();
	let nextId = 1;
	let mounted = false;

	const remove = (ctx: ExtensionContext, id: number) => {
		const index = items.findIndex((item) => item.id === id);
		if (index !== -1) items.splice(index, 1);
		const timer = timers.get(id);
		if (timer) {
			clearTimeout(timer);
			timers.delete(id);
		}
		sync(ctx);
	};

	const sync = (ctx: ExtensionContext) => {
		if (!ctx.hasUI) return;
		try {
			if (items.length === 0) {
				if (mounted) ctx.ui.setWidget(WIDGET_KEY, undefined);
				mounted = false;
				return;
			}
			if (mounted) return;
			mounted = true;
			ctx.ui.setWidget(WIDGET_KEY, (_tui, theme) => new PendingWidget(items, getTick, theme));
		} catch {
			// The widget is an indicator; failing to mount one must not lose a transcript.
		}
	};

	return {
		begin(ctx, intent, text) {
			const id = nextId++;
			items.push({ id, status: "pending", intent, text });
			sync(ctx);
			return id;
		},
		resolve(ctx, id) {
			remove(ctx, id);
		},
		fail(ctx, id, message) {
			const index = items.findIndex((item) => item.id === id);
			if (index === -1) return;
			items[index] = { id, status: "failed", message };
			timers.set(
				id,
				setTimeout(() => remove(ctx, id), ERROR_LINGER_MS),
			);
			sync(ctx);
		},
		count() {
			return items.filter((item) => item.status === "pending").length;
		},
		dispose() {
			for (const timer of timers.values()) clearTimeout(timer);
			timers.clear();
			items.length = 0;
			mounted = false;
		},
	};
};

class PendingWidget implements Component {
	constructor(
		private readonly items: readonly PendingItem[],
		private readonly getTick: () => number,
		private readonly theme: { fg(color: string, text: string): string },
	) {}

	render(width: number): string[] {
		const lines: string[] = [];
		for (const item of this.items) {
			if (item.status === "failed") {
				lines.push(truncateToWidth(this.theme.fg("error", `voice transcription failed: ${item.message}`), width, ""));
				continue;
			}
			// The message as it will be sent, with the placeholder where the transcript
			// goes. It is shown in full so the wait is over something recognisable rather
			// than over a bare spinner.
			const queued = item.intent === "queue" ? this.theme.fg("dim", "  (queued)") : "";
			const painted = animateRenderedLines(item.text.split("\n"), frameAt(this.getTick()), (part) =>
				this.theme.fg("dim", part),
			);
			const shown = painted.slice(0, MAX_LINES);
			for (const [index, line] of shown.entries()) {
				const last = index === shown.length - 1;
				lines.push(truncateToWidth(last ? `${line}${queued}` : line, width, ""));
			}
			if (painted.length > shown.length) {
				lines.push(truncateToWidth(this.theme.fg("dim", `  … ${painted.length - shown.length} more lines`), width, ""));
			}
		}
		return lines;
	}

	invalidate(): void {}
}
