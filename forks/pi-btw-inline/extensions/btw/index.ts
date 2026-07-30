/**
 * pi-btw-inline — Codex's /side (alias /btw) for Pi, rendered inline.
 *
 * `/btw <question>` forks the current conversation into an ephemeral side thread: the
 * model sees the main thread's history as reference context only, answers the question,
 * and nothing it says ever enters the main thread's context. In Codex the fork is
 * `fork_config.ephemeral = true` plus a boundary item and developer instructions
 * (codex-rs/tui/src/app/side.rs); here it is an in-memory AgentSession seeded with the
 * same history and the same prompt text.
 *
 * What is deliberately different: there is no overlay. The answer is appended to the
 * transcript as a custom entry, which Pi renders inline and never sends to the model.
 *
 * Design constraint inherited from the rest of this setup: nothing here may stop a long
 * run. The side thread is a separate session, so its failures cannot touch the main
 * turn; the command never blocks Pi's input loop; and every handler swallows its own
 * errors rather than throwing into Pi's event loop.
 */

import type { ImageContent } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

import { type BtwConfig, DEFAULT_BTW_CONFIG, loadBtwConfig } from "./config.js";
import { BTW_ENTRY_TYPE, type BtwExchange, createExchangeRenderer } from "./render.js";
import { SideThread } from "./thread.js";

const STATUS_KEY = "btw";
const WIDGET_KEY = "btw";

function notify(ctx: ExtensionContext, message: string, level: "info" | "warning" | "error" = "info"): void {
	if (!ctx.hasUI) return;
	try {
		ctx.ui.notify(message, level);
	} catch {
		// A UI that refuses a notification must not break the command.
	}
}

function setStatus(ctx: ExtensionContext, text: string | undefined): void {
	if (!ctx.hasUI) return;
	try {
		ctx.ui.setStatus(STATUS_KEY, text);
	} catch {
		// Status is cosmetic.
	}
}

function setWidget(ctx: ExtensionContext, lines: string[] | undefined): void {
	if (!ctx.hasUI) return;
	try {
		ctx.ui.setWidget(WIDGET_KEY, lines);
	} catch {
		// Widgets are cosmetic.
	}
}

/** Whether the main thread has said anything yet, so "inherited nothing" is a real fault. */
function hasConversation(ctx: ExtensionContext): boolean {
	try {
		return ctx.sessionManager.getEntries().some((entry) => entry.type === "message");
	} catch {
		return false;
	}
}

function describe(error: unknown): string {
	if (error instanceof Error && typeof error.message === "string") return error.message;
	try {
		return String(error);
	} catch {
		return "unknown error";
	}
}

/** Last `count` display lines of the answer so far, for the live preview widget. */
function previewLines(text: string, tool: string | undefined, count: number): string[] {
	const lines = text.split("\n").filter((line) => line.trim().length > 0);
	const tail = lines.slice(-count);
	if (tool) tail.push(`⋯ ${tool}`);
	return tail.length > 0 ? tail : ["thinking…"];
}

export default function btwExtension(pi: ExtensionAPI) {
	let thread: SideThread | null = null;
	let answering = false;
	let configWarned = false;

	pi.registerEntryRenderer<BtwExchange>(BTW_ENTRY_TYPE, createExchangeRenderer());

	function readConfig(ctx: ExtensionContext): BtwConfig {
		let config: BtwConfig;
		try {
			const loaded = loadBtwConfig();
			config = loaded.config;
			if (loaded.warning && !configWarned) {
				configWarned = true;
				notify(ctx, loaded.warning, "warning");
			}
		} catch {
			// loadBtwConfig is written not to throw. If it somehow does, the command still works.
			config = { ...DEFAULT_BTW_CONFIG };
		}
		// Sticky mode routes typed input to the side thread. Outside the TUI there is no
		// way to see or leave that mode, so it is never enabled there.
		return ctx.mode === "tui" ? config : { ...config, sticky: false };
	}

	function idleStatus(): string {
		return "btw · side thread";
	}

	async function closeThread(ctx: ExtensionContext, message?: string): Promise<void> {
		const current = thread;
		thread = null;
		answering = false;
		setWidget(ctx, undefined);
		setStatus(ctx, undefined);
		if (current) await current.dispose();
		if (message) notify(ctx, message);
	}

	function record(ctx: ExtensionContext, exchange: BtwExchange): void {
		try {
			pi.appendEntry(BTW_ENTRY_TYPE, exchange);
		} catch (error) {
			notify(ctx, `btw: could not record the answer (${describe(error)})`, "warning");
		}
		// Print mode renders no entries, so the answer would otherwise be invisible. JSON
		// mode is left alone: stray stdout would corrupt the event stream.
		if (ctx.mode === "print" && exchange.answer.trim().length > 0) {
			console.log(exchange.answer);
		}
	}

	async function ask(
		ctx: ExtensionContext,
		question: string,
		config: BtwConfig,
		images?: ImageContent[],
	): Promise<void> {
		const current = thread;
		if (!current) return;

		answering = true;
		setStatus(ctx, "btw · answering");
		let tool: string | undefined;
		let text = "";
		const paint = () => {
			if (config.livePreview) setWidget(ctx, previewLines(text, tool, config.previewLines));
		};
		paint();

		try {
			const result = await current.ask(
				question,
				{
					onText: (value) => {
						text = value;
						paint();
					},
					onTool: (label) => {
						tool = label;
						paint();
					},
				},
				config.timeoutMs,
				images,
			);

			// A turn stopped before it said anything has nothing to show; recording an
			// empty card would just be noise in the transcript.
			if (result.aborted && result.text.trim().length === 0) {
				notify(ctx, "btw: stopped.");
			} else {
				record(ctx, {
					question,
					answer: result.text,
					model: `${current.model.provider}/${current.model.id}`,
					durationMs: result.durationMs,
					toolCalls: result.toolCalls,
					timestamp: Date.now(),
					status: result.aborted ? "aborted" : "ok",
				});
			}
			if (result.timedOut) {
				notify(ctx, `btw: the side answer hit the ${Math.round(config.timeoutMs / 1000)}s limit and was stopped.`, "warning");
			}
		} catch (error) {
			const message = describe(error);
			record(ctx, {
				question,
				answer: "",
				model: `${current.model.provider}/${current.model.id}`,
				durationMs: 0,
				toolCalls: 0,
				timestamp: Date.now(),
				status: "error",
				error: message,
			});
			notify(ctx, `btw: ${message}`, "error");
		} finally {
			answering = false;
			setWidget(ctx, undefined);
			// /btw:end (or shutdown) can land while this turn is still unwinding. It has
			// already torn the thread down and cleared the footer, so re-showing the
			// side-thread status here would strand it on screen for the rest of the session.
			if (thread !== current) {
				setStatus(ctx, undefined);
			} else if (!config.sticky) {
				// A non-sticky side thread is a one-shot question: close it so the next typed
				// message goes to the main thread, exactly as if /btw had never been used.
				await closeThread(ctx);
			} else {
				setStatus(ctx, idleStatus());
			}
		}
	}

	/** Fire-and-forget in the TUI so the composer stays live while the side thread works;
	 * awaited in print mode, where nothing else would keep the process alive. */
	function dispatch(ctx: ExtensionContext, question: string, config: BtwConfig): Promise<void> | undefined {
		if (ctx.mode === "tui") {
			void ask(ctx, question, config);
			return undefined;
		}
		return ask(ctx, question, config);
	}

	pi.registerCommand("btw", {
		description: "Ask a side question in an ephemeral fork of this conversation",
		handler: async (args, ctx) => {
			const config = readConfig(ctx);
			if (!config.enabled) {
				notify(ctx, "btw is disabled in pi-btw-inline.json.", "warning");
				return;
			}

			const question = args.trim();

			if (thread) {
				if (answering) {
					notify(ctx, "btw: still answering. /btw:end cancels it.", "warning");
					return;
				}
				if (!question) {
					notify(ctx, "btw: a side conversation is already open. /btw:end returns to the main thread.");
					return;
				}
				await dispatch(ctx, question, config);
				return;
			}

			try {
				thread = await SideThread.fork(ctx, config);
			} catch (error) {
				thread = null;
				notify(ctx, `btw: could not start a side conversation (${describe(error)})`, "error");
				return;
			}

			setStatus(ctx, idleStatus());
			// Inheriting the history is the whole point, and the failure mode is silent —
			// the side thread just answers without context. Say so rather than let the user
			// wonder why the answer ignores the conversation.
			if (thread.inheritedMessages === 0 && hasConversation(ctx)) {
				notify(ctx, "btw: could not inherit this conversation's history; the side thread starts empty.", "warning");
			}
			if (!question) {
				notify(
					ctx,
					config.sticky
						? "btw: side conversation open. Messages go to it until /btw:end."
						: "btw: type the question as /btw <question>.",
				);
				if (!config.sticky) await closeThread(ctx);
				return;
			}
			await dispatch(ctx, question, config);
		},
	});

	pi.registerCommand("btw:end", {
		description: "Close the side conversation and return to the main thread",
		handler: async (_args, ctx) => {
			if (!thread) {
				notify(ctx, "btw: no side conversation is open.");
				return;
			}
			await closeThread(ctx, "btw: back on the main thread. The side conversation was discarded.");
		},
	});

	/**
	 * Sticky mode. While a side conversation is open, typed input belongs to it — the
	 * main thread must not see it. Every path returns "handled" or "continue"; the hook
	 * never throws, so a bug here cannot make the composer stop working.
	 */
	pi.on("input", async (event, ctx) => {
		try {
			if (!thread) return { action: "continue" } as const;
			// Messages this or another extension injected are not the user talking to the
			// side thread.
			if (event.source === "extension") return { action: "continue" } as const;

			const text = event.text.trim();
			if (text.length === 0) return { action: "continue" } as const;

			// Extension commands were already dispatched before this event, so anything
			// still starting with "/" is a skill or a prompt template. Expanding one into
			// the side thread, or letting it reach the main agent from inside side mode,
			// are both surprising; Codex takes the same line and disables them.
			if (text.startsWith("/")) {
				notify(ctx, "btw: skills and prompt templates are not available in a side conversation. /btw:end first.", "warning");
				return { action: "handled" } as const;
			}

			if (answering) {
				notify(ctx, "btw: still answering. /btw:end cancels it.", "warning");
				return { action: "handled" } as const;
			}

			const config = readConfig(ctx);
			if (!config.sticky) return { action: "continue" } as const;

			void ask(ctx, text, config, event.images);
			return { action: "handled" } as const;
		} catch (error) {
			notify(ctx, `btw: ${describe(error)}`, "error");
			return { action: "continue" } as const;
		}
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		await closeThread(ctx);
	});

	// A fork of a conversation that is no longer on screen is worse than no fork at all,
	// and a live side thread would keep swallowing typed input after the switch. Pi
	// normally builds a fresh extension instance for a replacement session, so this is a
	// backstop for the paths that reuse one (/reload in particular).
	pi.on("session_start", async (_event, ctx) => {
		if (thread) await closeThread(ctx);
	});
}
