/**
 * pi-btw-side — Codex's /side (alias /btw) for Pi.
 *
 * `/btw` opens a clean side conversation in a full-screen view. The model sees the main
 * thread's history as reference context, answers there, and nothing it says ever enters
 * the main thread's context. Escape returns to the main thread and discards the side
 * thread. In Codex this is `fork_config.ephemeral = true` plus a boundary item and
 * developer instructions (codex-rs/tui/src/app/side.rs); here it is an in-memory
 * AgentSession seeded with the same history and the same prompt text, displayed in an
 * overlay that covers the chat.
 *
 * Design constraint inherited from the rest of this setup: nothing here may stop a long
 * run. The side thread is a separate session, so the main thread keeps streaming behind
 * the view and is untouched when it closes. Every handler swallows its own errors rather
 * than throwing into Pi's event loop.
 */

import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@earendil-works/pi-coding-agent";

import { type BtwConfig, DEFAULT_BTW_CONFIG, loadBtwConfig } from "./config.js";
import { BTW_ENTRY_TYPE, type BtwExchange, createExchangeRenderer } from "./render.js";
import { SideThread } from "./thread.js";
import { SideView } from "./view.js";

const SPINNER_MS = 120;

function notify(ctx: ExtensionContext, message: string, level: "info" | "warning" | "error" = "info"): void {
	if (!ctx.hasUI) return;
	try {
		ctx.ui.notify(message, level);
	} catch {
		// A UI that refuses a notification must not break the command.
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

/** Whether the main thread has said anything yet, so "inherited nothing" is a real fault. */
function hasConversation(ctx: ExtensionContext): boolean {
	try {
		return ctx.sessionManager.getEntries().some((entry) => entry.type === "message");
	} catch {
		return false;
	}
}

export default function btwExtension(pi: ExtensionAPI) {
	let open = false;
	let draft = "";
	let configWarned = false;
	/** Whether the main thread is mid-run. Tracked from its lifecycle events rather than
	 * polled with ctx.isIdle(), which reports idle from inside a command handler even
	 * while the host agent is streaming. */
	let mainBusy = false;
	let activeView: SideView | undefined;

	const publishMainStatus = () => {
		try {
			activeView?.setMainStatus(mainBusy ? "working" : "idle");
		} catch {
			// The status line is decoration.
		}
	};
	pi.on("agent_start", () => {
		mainBusy = true;
		publishMainStatus();
	});
	pi.on("agent_settled", () => {
		mainBusy = false;
		publishMainStatus();
	});

	pi.registerEntryRenderer<BtwExchange>(BTW_ENTRY_TYPE, createExchangeRenderer());

	function readConfig(ctx: ExtensionContext): BtwConfig {
		try {
			const loaded = loadBtwConfig();
			if (loaded.warning && !configWarned) {
				configWarned = true;
				notify(ctx, loaded.warning, "warning");
			}
			return loaded.config;
		} catch {
			// loadBtwConfig is written not to throw. If it somehow does, the command still works.
			return { ...DEFAULT_BTW_CONFIG };
		}
	}

	function record(ctx: ExtensionContext, exchange: BtwExchange): void {
		try {
			pi.appendEntry(BTW_ENTRY_TYPE, exchange);
		} catch (error) {
			notify(ctx, `btw: could not record the answer (${describe(error)})`, "warning");
		}
	}

	/**
	 * The interactive path: open the side view and stay in it until the user leaves.
	 * Everything inside runs against `thread`, never against the host session.
	 */
	async function openView(ctx: ExtensionCommandContext, config: BtwConfig, question: string): Promise<void> {
		let thread: SideThread;
		try {
			thread = await SideThread.fork(ctx, config);
		} catch (error) {
			notify(ctx, `btw: could not start a side conversation (${describe(error)})`, "error");
			return;
		}

		open = true;
		let view: SideView | undefined;
		let busy = false;
		let closed = false;
		const started = Date.now();
		let exchanges = 0;
		/**
		 * The last exchange that actually completed, written as one record so the card can
		 * never pair a new question with the previous answer. An errored, aborted or
		 * still-running turn leaves this untouched and is simply not recorded.
		 */
		let lastExchange: { question: string; answer: string; toolCalls: number; status: "ok" | "aborted" } | undefined;

		// Submissions are queued rather than dropped: the composer stays live while an
		// answer streams, and a message typed then would otherwise vanish silently.
		const queue: string[] = [];

		const submit = (text: string): void => {
			if (!view || closed) return;
			// Echo at submission time, so a queued message is visible immediately in the
			// place it will eventually be answered.
			view.addUser(text);
			queue.push(text);
			void drain();
		};

		const drain = async (): Promise<void> => {
			if (busy || closed) return;
			const text = queue.shift();
			if (text === undefined) return;

			busy = true;
			exchanges += 1;
			view?.setBusy(true);
			try {
				const result = await thread.ask(
					text,
					{
						onAssistantStart: (message) => view?.startAssistant(message),
						onAssistant: (message) => view?.updateAssistant(message),
						onToolStart: (id, label) => view?.startTool(id, label),
						onToolEnd: (id, isError) => view?.endTool(id, isError),
					},
					config.timeoutMs,
				);
				if (result.text.trim().length > 0) {
					lastExchange = {
						question: text,
						answer: result.text,
						toolCalls: result.toolCalls,
						status: result.aborted ? "aborted" : "ok",
					};
				}
				if (result.droppedMessages > 0) {
					view?.addNotice(
						`dropped ${result.droppedMessages} more of the oldest inherited message(s) to keep room to answer`,
						"dim",
					);
				}
				if (result.timedOut) {
					view?.addNotice(`stopped at the ${Math.round(config.timeoutMs / 1000)}s limit`, "error");
				} else if (result.aborted) {
					view?.addNotice("stopped", "dim");
				}
			} catch (error) {
				view?.addNotice(describe(error), "error");
			} finally {
				busy = false;
				view?.setBusy(false);
				void drain();
			}
		};

		const spinnerTimer = setInterval(() => view?.tickSpinner(), SPINNER_MS);

		try {
			await ctx.ui.custom<void>(
				(tui, theme, _keybindings, done) => {
					view = new SideView(tui, theme, {
						title: hasConversation(ctx) ? "side conversation" : "side conversation (no history to inherit)",
						initialDraft: draft,
						onSubmit: (text) => submit(text),
						onDraft: (text) => {
							draft = text;
						},
						onClose: () => {
							closed = true;
							done();
						},
					});
					activeView = view;
					// The main thread may already have been running when the view opened; its
					// transcript is hidden now, so this line is the only sign of it.
					view.setMainStatus(mainBusy ? "working" : "idle");
					if (thread.inheritedMessages === 0 && hasConversation(ctx)) {
						view.addNotice("could not inherit this conversation's history; starting empty", "error");
					} else if (thread.droppedMessages > 0) {
						// Never silent. A shortened context reads as the model forgetting things
						// it was just told, and the main thread is the obvious place to ask again.
						view.addNotice(
							`main thread is too large to fork whole; dropped its ${thread.droppedMessages} oldest message(s) to keep room to answer`,
							"dim",
						);
					}
					if (question) submit(question);
					return view;
				},
				{
					overlay: true,
					// Full screen: the point of the view is that the main thread is not on
					// screen at all while the side conversation is open.
					overlayOptions: { width: "100%", maxHeight: "100%", anchor: "top-left" },
				},
			);
		} catch (error) {
			notify(ctx, `btw: ${describe(error)}`, "error");
		} finally {
			closed = true;
			clearInterval(spinnerTimer);
			activeView = undefined;
			view = undefined;
			open = false;
			await thread.dispose();
		}

		// Discarded on exit, like Codex. `record: true` keeps a collapsed card in the
		// transcript instead; it is still a custom entry, so no model ever sees it.
		if (config.record && lastExchange) {
			const earlier = Math.max(0, exchanges - 1);
			record(ctx, {
				question: earlier === 0 ? lastExchange.question : `${lastExchange.question}  (+${earlier} earlier)`,
				answer: lastExchange.answer,
				model: `${thread.model.provider}/${thread.model.id}`,
				durationMs: Date.now() - started,
				toolCalls: lastExchange.toolCalls,
				timestamp: Date.now(),
				status: lastExchange.status,
			});
		}
	}

	/**
	 * The non-interactive path. There is no view to open in print or JSON mode, so a
	 * single question is answered and printed, and the thread is discarded.
	 */
	async function askOnce(ctx: ExtensionCommandContext, config: BtwConfig, question: string): Promise<void> {
		let thread: SideThread | undefined;
		try {
			thread = await SideThread.fork(ctx, config);
			const result = await thread.ask(question, {}, config.timeoutMs);
			// JSON mode is left alone: stray stdout would corrupt the event stream.
			if (ctx.mode === "print" && result.text.trim().length > 0) console.log(result.text);
			if (config.record) {
				record(ctx, {
					question,
					answer: result.text,
					model: `${thread.model.provider}/${thread.model.id}`,
					durationMs: result.durationMs,
					toolCalls: result.toolCalls,
					timestamp: Date.now(),
					status: result.aborted ? "aborted" : "ok",
				});
			}
		} catch (error) {
			notify(ctx, `btw: ${describe(error)}`, "error");
		} finally {
			await thread?.dispose();
		}
	}

	pi.registerCommand("btw", {
		description: "Open a side conversation in an ephemeral fork of this conversation",
		handler: async (args, ctx) => {
			const config = readConfig(ctx);
			if (!config.enabled) {
				notify(ctx, "btw is disabled in pi-btw-side.json.", "warning");
				return;
			}
			if (open) {
				notify(ctx, "btw: a side conversation is already open.", "warning");
				return;
			}
			const question = args.trim();
			if (ctx.mode !== "tui") {
				if (!question) {
					notify(ctx, "btw: pass the question, as /btw <question>, outside the TUI.", "warning");
					return;
				}
				await askOnce(ctx, config, question);
				return;
			}
			await openView(ctx, config, question);
		},
	});

	// Kept for muscle memory and for anyone who bound it: inside the view, escape is the
	// way out, so this only reports where the exit is.
	pi.registerCommand("btw:end", {
		description: "How to leave a side conversation",
		handler: async (_args, ctx) => {
			notify(ctx, open ? "btw: press escape in the side view to return." : "btw: no side conversation is open.");
		},
	});
}
