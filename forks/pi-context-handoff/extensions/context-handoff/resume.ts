/**
 * Keep a run going when Pi would otherwise stop it.
 *
 * Pi ends an agent run in several places that all look identical from outside — the
 * transcript simply stops, with no error. `_runAutoCompaction` returns false, and therefore
 * `_handlePostAgentRun` returns false and `_runAgentPrompt`'s loop exits, when:
 *
 *   - a truncated reply was compacted but not classified as an overflow (the common one),
 *   - the compaction call threw and the catch returned false,
 *   - `prepareCompaction` found nothing to compact,
 *   - the compaction was aborted,
 *   - overflow recovery already used its single `_overflowRecoveryAttempted` retry.
 *
 * The first case is observable from `session_compact`, and resuming there is cheapest:
 * that hook is awaited *before* `return this.agent.hasQueuedMessages()`, so a queued message
 * makes Pi call `agent.continue()` and carry on inside the same run. That is not a guess —
 * in session 019fcd7f a monitor event landing 28ms after such a compaction resumed the run
 * for another 600 entries, while an identical compaction with nothing queued sat dead until
 * a human typed 64 minutes later.
 *
 * The other cases never emit `session_compact` at all, so they need a backstop.
 * `agent_settled` is documented as "Pi will not continue running automatically" and is
 * emitted from `_runAgentPrompt`'s `finally`, so it fires on every one of those paths. If
 * the run ended with work unfinished and nothing has already resumed it, that is where the
 * run gets restarted.
 *
 * Why truncation is detected on `stopReason` alone: Pi's own `isContextOverflow` requires
 * `usage.output === 0` and ≥99% of the window, and the real messages carried 16 reasoning
 * tokens at 98.4%. Reproducing that test here would reproduce the bug.
 */

/**
 * Test seam. A real context truncation cannot be produced on demand, so this forces the
 * agent_settled backstop to treat one run as unfinished, which is the only way to exercise
 * the injection end to end. Mirrors the PI_STT_FAKE_* seams in the voice fork.
 */
export const FORCE_RESUME_ENV = "PI_CONTEXT_HANDOFF_FORCE_RESUME";

/** Cap on consecutive resumes with no healthy turn in between. */
export const MAX_CONSECUTIVE_RESUMES = 3;

export const RESUME_MESSAGE_TYPE = "context-handoff-resume";

/**
 * Stop reasons that mean the model did not choose to finish.
 *
 * `stop` is a deliberate end of turn and `aborted` is the user cancelling; resuming either
 * would talk over the user. Everything else — a context truncation, a provider error —
 * left work unfinished.
 */
export const UNFINISHED_STOP_REASONS: readonly string[] = ["length", "error"];

export const RESUME_TEXT =
	"Your previous response did not finish — it was cut off before you produced an answer or " +
	"a tool call, so the work you were doing is incomplete. If the context was full it has " +
	"just been compacted, so there is room now. Re-read the handoff brief above and continue " +
	"from where you were interrupted.";

export const GAVE_UP_TEXT =
	`The run has been resumed ${MAX_CONSECUTIVE_RESUMES} times in a row and each attempt ended ` +
	"unfinished. Stopping the automatic resume so this cannot loop. Summarise what you have " +
	"done and what is left, then stop, rather than continuing to retry.";

interface AssistantLike {
	role?: string;
	stopReason?: string;
	usage?: { output?: number } | null;
}

interface EntryLike {
	message?: AssistantLike | null;
}

/** True for a stop reason that means the model was cut off rather than done. */
export function isUnfinishedStop(stopReason: string | undefined): boolean {
	return stopReason !== undefined && UNFINISHED_STOP_REASONS.includes(stopReason);
}

/** The newest assistant message in a branch, or undefined when there is none. */
export function lastAssistantMessage(
	entries: readonly EntryLike[] | undefined,
): AssistantLike | undefined {
	if (!entries) return undefined;
	for (let i = entries.length - 1; i >= 0; i--) {
		const message = entries[i]?.message;
		if (message && message.role === "assistant") return message;
	}
	return undefined;
}

/** True when the newest assistant message in the branch was cut off by the context limit. */
export function lastAssistantWasTruncated(entries: readonly EntryLike[] | undefined): boolean {
	return lastAssistantMessage(entries)?.stopReason === "length";
}

/**
 * Decides whether to resume, and makes sure only one resume happens per run however many
 * hooks observe the same stop.
 */
export class ResumeGuard {
	private consecutive = 0;
	private issuedThisRun = false;

	/** `session_compact`: cheapest resume point, inside the run Pi is about to end. */
	decide(truncated: boolean, willRetry: boolean): "resume" | "give-up" | "ignore" {
		// Pi already resumes when it will retry, and a compaction after a finished turn is
		// supposed to end the run.
		if (!truncated || willRetry) {
			this.consecutive = 0;
			return "ignore";
		}
		return this.take();
	}

	/**
	 * `agent_settled`: the backstop. Pi has stopped for good, so anything unfinished that no
	 * earlier hook rescued is resumed here.
	 */
	decideOnSettled(stopReason: string | undefined, forceUnfinished = false): "resume" | "give-up" | "ignore" {
		if (this.issuedThisRun) return "ignore"; // session_compact already handled it
		if (!forceUnfinished && !isUnfinishedStop(stopReason)) {
			this.consecutive = 0;
			return "ignore";
		}
		return this.take();
	}

	private take(): "resume" | "give-up" {
		if (this.consecutive >= MAX_CONSECUTIVE_RESUMES) return "give-up";
		this.consecutive++;
		this.issuedThisRun = true;
		return "resume";
	}

	/** Called once a run is fully over, so the next run starts with a clean slate. */
	endRun(): void {
		this.issuedThisRun = false;
	}

	/** A turn that finished normally clears the streak. */
	noteHealthyTurn(): void {
		this.consecutive = 0;
		this.issuedThisRun = false;
	}

	get consecutiveResumes(): number {
		return this.consecutive;
	}
}
