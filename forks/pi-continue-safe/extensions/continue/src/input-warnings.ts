import type { ExtensionContext } from "@earendil-works/pi-coding-agent";

const warnedKeys = new Set<string>();
const pendingWarnings: string[] = [];

/** Queue a degraded-input warning once per key, for readers that have no UI context. */
export function queueInputWarning(key: string, message: string): void {
	if (warnedKeys.has(key)) return;
	warnedKeys.add(key);
	pendingWarnings.push(message);
}

/** Show queued degraded-input warnings; they stay queued until a UI-capable context appears. */
export function flushInputWarnings(ctx: ExtensionContext): void {
	if (pendingWarnings.length === 0 || !ctx.hasUI) return;
	for (const message of pendingWarnings.splice(0, pendingWarnings.length)) {
		ctx.ui.notify(message, "warning");
	}
}

/** Report a one-shot runtime warning immediately, keyed so repeated failures stay quiet. */
export function warnInputOnce(ctx: ExtensionContext, key: string, message: string): void {
	queueInputWarning(key, message);
	flushInputWarnings(ctx);
}
