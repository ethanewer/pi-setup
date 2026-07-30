import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { AudioRecorder, RecordingHandle } from "../audio/types";
import type { PluginConfig } from "../config/types";
import { assertProviderReady } from "../providers/readiness";
import type { Strings } from "../i18n/strings";
import type { CleanupClient } from "../cleanup/types";
import { applyReplacements } from "./replacements";
import { parseVoiceCommand } from "./voice-commands";
import { formatTranscriptForPrompt } from "./output";

export type DictationMode = "idle" | "recording" | "processing" | "polishing";

/** Where a transcript is headed, decided by the key that stopped the recording. */
export type DictationOutcome = "insert" | "send" | "queue";

/**
 * A place the transcript will land, claimed the instant recording stops so the user does
 * not wait on the provider. Exactly one of resolve/fail/cancel is called.
 */
export type Delivery = {
  resolve(text: string): Promise<void> | void;
  fail(message: string): void;
  cancel(): void;
};

export type DictationToast = {
  variant?: "info" | "success" | "warning" | "error";
  title?: string;
  message: string;
  duration?: number;
};

export type DictationControllerOptions = {
  keybind: string;
  strings: Strings;
  loadConfig(): Promise<PluginConfig>;
  createRecorder(config: PluginConfig): AudioRecorder;
  createProvider(config: PluginConfig): { transcribe(input: { audioPath: string; language?: string; signal: AbortSignal }): Promise<{ text: string }> };
  createCleanup(config: PluginConfig): CleanupClient | null;
  /** Claim a destination for the transcript. Runs before the provider is called. */
  beginDelivery(ctx: ExtensionContext, outcome: DictationOutcome): Delivery;
  notify(ctx: ExtensionContext | undefined, toast: DictationToast): void;
  onModeChange?(mode: DictationMode, ctx: ExtensionContext | undefined): void;
  onError(ctx: ExtensionContext | undefined, error: unknown): void;
};

type StopRecordingOptions = {
  outcome?: DictationOutcome;
};

const MAX_DURATION_RETRY_MS = 1000;

// Yield one event-loop turn so the append is applied before the submit reads
// the prompt, instead of a fixed delay whose window swallows typed keystrokes.
const waitForPromptAppendFlush = () => new Promise<void>((resolve) => setImmediate(resolve));

export const createDictationController = (options: DictationControllerOptions) => {
  let recording: RecordingHandle | undefined;
  let recordingConfig: PluginConfig | undefined;
  let activeRecordingHandle: RecordingHandle | undefined;
  let activeOperation: Promise<void> | undefined;
  let transcriptionController: AbortController | undefined;
  let processing = false;
  let starting = false;
  let startCancelled = false;
  let cancelRequested = false;
  let mode: DictationMode = "idle";
  let disposed = false;
  let lastContext: ExtensionContext | undefined;

  const rememberContext = (ctx: ExtensionContext | undefined) => {
    if (ctx) lastContext = ctx;
  };

  const setMode = (nextMode: DictationMode, ctx?: ExtensionContext) => {
    if (disposed && nextMode !== "idle") return;
    rememberContext(ctx);
    mode = nextMode;
    options.onModeChange?.(nextMode, ctx ?? lastContext);
  };

  const notify = (ctx: ExtensionContext | undefined, toast: DictationToast) => {
    if (!disposed) options.notify(ctx ?? lastContext, toast);
  };

  const stopActiveRecording = async (
    ctx: ExtensionContext,
    active: RecordingHandle,
    config: PluginConfig,
    stopOptions: StopRecordingOptions,
    delivery: Delivery,
  ) => {
    const provider = options.createProvider(config);
    const controller = new AbortController();
    transcriptionController = controller;
    const timeout = setTimeout(() => controller.abort(), config.provider.timeoutSeconds * 1000);

    try {
      // No "stopping" toast: the placeholder already says so, in the place the text will
      // appear.
      const audioPath = await active.stop();
      if (disposed) return delivery.cancel();
      const result = await provider.transcribe({ audioPath, language: config.provider.language, signal: controller.signal });
      if (cancelRequested || disposed) return delivery.cancel();

      let text = applyReplacements(result.text, config.output.replacements);
      const voice = parseVoiceCommand(text, config.commands);
      if (voice.command === "clear") {
        notify(ctx, { title: "Pi Voice STT", message: options.strings.toast.cleared, variant: "info" });
        delivery.cancel();
        return;
      }
      text = voice.text;
      const cleanup = options.createCleanup(config);
      if (cleanup && text.trim()) {
        setMode("polishing", ctx);
        const cleanupController = new AbortController();
        transcriptionController = cleanupController;
        const cleanupTimeout = setTimeout(() => cleanupController.abort(), config.cleanup.timeoutSeconds * 1000);
        try {
          const cleaned = await cleanup.clean({ text, signal: cleanupController.signal });
          if (!cancelRequested && !disposed && cleaned.trim()) text = cleaned;
        } catch {
          if (!cancelRequested && !disposed) {
            notify(ctx, { title: "Pi Voice STT", message: options.strings.toast.cleanupFailed, variant: "warning" });
          }
        } finally {
          clearTimeout(cleanupTimeout);
          if (transcriptionController === cleanupController) transcriptionController = undefined;
        }
        if (cancelRequested || disposed) return delivery.cancel();
      }

      const formatted = formatTranscriptForPrompt(text, config.output);
      if (!formatted.trim()) {
        // Nothing was said. The placeholder has to go either way, or it sits in the
        // editor forever waiting for a transcript that already arrived empty.
        delivery.fail(options.strings.toast.emptyTranscript);
        return;
      }

      await delivery.resolve(voice.command === "newline" ? `${formatted}\n` : formatted);
    } catch (error) {
      // The delivery is the single report: it puts the message where the transcript was
      // going to appear. Rethrowing would add a toast saying the same thing again.
      delivery.fail(error instanceof Error ? error.message : String(error));
    } finally {
      clearTimeout(timeout);
      if (transcriptionController === controller) transcriptionController = undefined;
      await active.dispose();
    }
  };

  const stopRecording = async (ctx: ExtensionContext, stopOptions: StopRecordingOptions = {}) => {
    rememberContext(ctx);
    if (disposed) return;
    if (processing) {
      notify(ctx, { title: "Pi Voice STT", message: options.strings.toast.stillProcessing, variant: "warning" });
      return;
    }

    if (!recording) return;

    processing = true;
    setMode("processing", ctx);
    // Claimed before any await, so the placeholder is on screen in the same frame the
    // recording indicator disappears.
    const delivery = options.beginDelivery(ctx, stopOptions.outcome ?? "insert");
    const active = recording;
    const activeConfig = recordingConfig;
    recording = undefined;
    recordingConfig = undefined;
    activeRecordingHandle = active;
    if (active.timeout) clearTimeout(active.timeout);

    const operation = activeConfig
      ? stopActiveRecording(ctx, active, activeConfig, stopOptions, delivery)
      : (() => {
          const error = new Error("Recording config was not available.");
          delivery.fail(error.message);
          return Promise.reject(error);
        })();
    activeOperation = operation;
    try {
      await operation;
    } catch (error) {
      if (!cancelRequested && !disposed) throw error;
    } finally {
      if (activeOperation === operation) activeOperation = undefined;
      if (activeRecordingHandle === active) activeRecordingHandle = undefined;
      processing = false;
      cancelRequested = false;
      setMode("idle", ctx);
    }
  };

  const armMaxDuration = (handle: RecordingHandle, delayMs: number) => {
    handle.timeout = setTimeout(() => {
      if (recording !== handle || disposed) return;
      const timeoutContext = lastContext;
      // Capture itself already stopped at capture.maxSeconds (ffmpeg -t, or the
      // bridge daemon), so retry instead of dropping the transcribe trigger
      // when the session is momentarily busy.
      if (processing || !timeoutContext) {
        armMaxDuration(handle, MAX_DURATION_RETRY_MS);
        return;
      }
      void stopRecording(timeoutContext).catch((error) => options.onError(timeoutContext, error));
    }, delayMs);
  };

  const cancelActiveRecording = async (active: RecordingHandle) => {
    if (active.timeout) clearTimeout(active.timeout);
    await active.dispose();
  };

  const releaseRecording = async (active: RecordingHandle) => {
    if (active.timeout) clearTimeout(active.timeout);
    await active.dispose().catch(() => {});
  };

  const cancel = async (ctx?: ExtensionContext) => {
    rememberContext(ctx);
    if (disposed) return;

    // Esc while start() is still awaiting: there is nothing to abort yet, so
    // mark the pending recorder for release. Latching cancelRequested here
    // would instead discard the *next* recording's transcript.
    if (starting) {
      startCancelled = true;
      notify(ctx, { title: "Pi Voice STT", message: options.strings.toast.recordingCancelled, variant: "info" });
      return;
    }

    if (recording && !processing) {
      cancelRequested = true;
      const active = recording;
      recording = undefined;
      recordingConfig = undefined;
      await cancelActiveRecording(active);
      cancelRequested = false;
      setMode("idle", ctx);
      notify(ctx, { title: "Pi Voice STT", message: options.strings.toast.recordingCancelled, variant: "info" });
      return;
    }

    if (processing) {
      cancelRequested = true;
      transcriptionController?.abort();
      if (activeRecordingHandle) {
        await activeRecordingHandle.dispose().catch(() => {});
      }
      notify(ctx, { title: "Pi Voice STT", message: options.strings.toast.transcriptionCancelled, variant: "info" });
      try {
        await activeOperation;
      } catch {
        // stopRecording handles aborted transcription.
      }
    }
  };

  const startRecording = async (ctx: ExtensionContext) => {
    if (disposed) return;
    processing = true;
    starting = true;
    startCancelled = false;
    let started: RecordingHandle | undefined;
    try {
      const config = await options.loadConfig();
      if (disposed) return;
      assertProviderReady(config.provider);
      const recorder = options.createRecorder(config);
      started = await recorder.start();
      // start() can take seconds (permission prompt, bridge HTTP), so the
      // session may already be gone or the user may have cancelled: never
      // leave an unowned live microphone.
      if (disposed || startCancelled) {
        await releaseRecording(started);
        setMode("idle", ctx);
        return;
      }
      recording = started;
      recordingConfig = config;
      armMaxDuration(started, config.capture.maxSeconds * 1000);
      // No toast on start. The pulsing red cursor is the indicator, and a banner
      // repeating the keys every time is the noise this replaced.
      setMode("recording", ctx);
    } catch (error) {
      if (started) {
        if (recording === started) {
          recording = undefined;
          recordingConfig = undefined;
        }
        await releaseRecording(started);
        setMode("idle", ctx);
      }
      throw error;
    } finally {
      processing = false;
      starting = false;
    }
  };

  const toggle = async (ctx: ExtensionContext) => {
    rememberContext(ctx);
    if (recording) {
      await stopRecording(ctx, { outcome: "insert" });
      return;
    }
    // A transcription still in flight owns its own placeholder, so it does not block a
    // new recording the way it did when the editor was the only destination.
    await startRecording(ctx);
  };

  const dispose = async () => {
    disposed = true;
    transcriptionController?.abort();
    const operation = activeOperation;
    // Loop: a recorder whose start() was already in flight can still be
    // handed over while we await, and it must not outlive the session.
    while (recording) {
      const active = recording;
      recording = undefined;
      recordingConfig = undefined;
      await releaseRecording(active);
    }
    const active = activeRecordingHandle;
    if (active) await active.dispose().catch(() => {});
    await operation?.catch(() => {});
    setMode("idle", lastContext);
  };

  return {
    toggle,
    stop: (ctx: ExtensionContext, outcome: DictationOutcome = "insert") => stopRecording(ctx, { outcome }),
    stopAndSubmit: (ctx: ExtensionContext) => stopRecording(ctx, { outcome: "send" }),
    cancel,
    dispose,
    getMode: () => mode,
  };
};
