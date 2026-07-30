import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { EditorComponent } from "@earendil-works/pi-tui";
import { checkBridgeRecorderHealth } from "./audio/bridge-recorder";
import { createRecorder } from "./audio/factory";
import { loadConfig, readConfigFile } from "./config/load-config";
import { resolveStartupOptions } from "./config/startup";
import { createDictationController, type DictationToast } from "./core/dictation-controller";
import { DEFAULT_MODE, isKnownMode, listModeNames } from "./core/modes";
import { createProvider } from "./providers/factory";
import { createCleanup } from "./cleanup/factory";
import { assertProviderReady } from "./providers/readiness";
import { createInputIndicator, createVoiceEditorFactory } from "./ui/input-indicator";
import { resolveStrings } from "./i18n/strings";
import { containsPasteMarker, formatError } from "./utils/text";

const toastType = (variant: DictationToast["variant"]): "info" | "warning" | "error" => {
  if (variant === "error") return "error";
  if (variant === "warning") return "warning";
  return "info";
};

const notify = (ctx: ExtensionContext | undefined, toast: DictationToast): void => {
  if (!ctx?.hasUI) return;
  const message = toast.title ? `${toast.title}: ${toast.message}` : toast.message;
  ctx.ui.notify(message, toastType(toast.variant));
};

const reportError = (ctx: ExtensionContext | undefined, error: unknown): void => {
  notify(ctx, { title: "Pi Voice STT", message: formatError(error), variant: "error" });
};

export default function piVoiceSttExtension(pi: ExtensionAPI) {
  const startup = resolveStartupOptions();
  const keybind = startup.keybind;
  const strings = resolveStrings(startup.locale);
  const inputIndicator = createInputIndicator(keybind, strings);
  let activeMode = startup.mode || DEFAULT_MODE;
  let activeEditor: EditorComponent | undefined;
  // Prompt as it stood right after the transcript was inserted. Anything typed
  // afterwards stays in the editor instead of being swept into the sent message.
  // Kept in both forms: getEditorText() expands pi paste markers, the editor's
  // own text still holds them.
  let insertedPrompt: string | undefined;
  let insertedEditorText: string | undefined;

  const getConfig = () => loadConfig({ configPath: startup.configPath, mode: activeMode });

  const controller = createDictationController({
    keybind,
    strings,
    loadConfig: getConfig,
    createRecorder: (config) => {
      // A new dictation invalidates the previous insertion snapshot.
      insertedPrompt = undefined;
      insertedEditorText = undefined;
      return createRecorder(config.capture);
    },
    createProvider: (config) => createProvider(config.provider),
    createCleanup: (config) => createCleanup(config.cleanup),
    appendPrompt: async (ctx, text) => {
      if (activeEditor?.insertTextAtCursor) activeEditor.insertTextAtCursor(text);
      else ctx.ui.setEditorText(`${ctx.ui.getEditorText()}${text}`);
      insertedPrompt = ctx.ui.getEditorText();
      insertedEditorText = activeEditor?.getText();
    },
    submitPrompt: async (ctx) => {
      const current = ctx.ui.getEditorText();
      const editorText = activeEditor?.getText();
      const snapshot = insertedPrompt;
      const editorSnapshot = insertedEditorText;
      insertedPrompt = undefined;
      insertedEditorText = undefined;
      const submitted = snapshot !== undefined && current.startsWith(snapshot) ? snapshot : current;
      const prompt = submitted.trimEnd();
      if (!prompt) {
        notify(ctx, { title: "Pi Voice STT", message: strings.toast.emptyTranscript, variant: "warning" });
        return;
      }

      // setEditorText writes raw editor text, so the leftover is preferably cut
      // from the editor's own text rather than from the expanded text. It may
      // only be used when the two agree character for character: setEditorText
      // lands on the editor's setText, which drops its paste map, so a raw
      // leftover that still holds a paste marker would be left with nothing to
      // expand to and its content would be gone. Writing the expanded leftover
      // instead is verbose but loses nothing, and an exact comparison decides
      // that without depending on how the editor words its markers.
      const expandedRemainder = current.slice(submitted.length);
      const rawRemainder = editorText !== undefined && editorSnapshot !== undefined && editorText.startsWith(editorSnapshot)
        ? editorText.slice(editorSnapshot.length)
        : undefined;
      const remainder = submitted === current
        ? ""
        : rawRemainder === expandedRemainder && !containsPasteMarker(expandedRemainder)
          ? rawRemainder
          : expandedRemainder;
      ctx.ui.setEditorText(remainder);
      if (ctx.isIdle()) pi.sendUserMessage(prompt);
      else pi.sendUserMessage(prompt, { deliverAs: "followUp" });
    },
    notify,
    onModeChange: (mode) => inputIndicator.setMode(mode),
    onError: reportError,
  });

  pi.registerCommand("stt", {
    description: "Voice dictation controls: start, stop, send, cancel, mode, status, doctor.",
    getArgumentCompletions: (prefix) => {
      const commands = ["start", "stop", "send", "cancel", "mode", "status", "doctor"];
      return commands
        .filter((command) => command.startsWith(prefix.trim().toLowerCase()))
        .map((command) => ({ value: command, label: command }));
    },
    handler: async (args, ctx) => {
      const trimmed = args.trim();
      const [first, ...rest] = trimmed.split(/\s+/);
      const action = (first || "status").toLowerCase();
      const param = rest.join(" ").trim();

      if (action === "start") {
        if (controller.getMode() === "idle") await controller.toggle(ctx).catch((error: unknown) => reportError(ctx, error));
        else ctx.ui.notify(`Pi Voice STT is already ${controller.getMode()}.`, "warning");
        return;
      }

      if (action === "stop") {
        await controller.stop(ctx).catch((error: unknown) => reportError(ctx, error));
        return;
      }

      if (action === "send") {
        await controller.stopAndSubmit(ctx).catch((error: unknown) => reportError(ctx, error));
        return;
      }

      if (action === "cancel") {
        await controller.cancel(ctx).catch((error: unknown) => reportError(ctx, error));
        return;
      }

      if (action === "mode") {
        const fileConfig = await readConfigFile(startup.configPath).catch(() => ({}));
        const names = listModeNames(fileConfig);
        if (!param) {
          ctx.ui.notify(`Pi Voice STT mode: ${activeMode} · available: ${names.join(", ")}`, "info");
          return;
        }
        const next = param.toLowerCase();
        if (!isKnownMode(fileConfig, next)) {
          ctx.ui.notify(`Unknown mode "${next}". Available: ${names.join(", ")}`, "error");
          return;
        }
        activeMode = next;
        ctx.ui.notify(`Pi Voice STT mode set to "${activeMode}".`, "info");
        return;
      }

      if (action === "doctor") {
        try {
          const config = await getConfig();
          assertProviderReady(config.provider);
          let capture: string = config.capture.type;
          if (config.capture.type === "bridge") {
            await checkBridgeRecorderHealth(config.capture);
            capture = `bridge ${config.capture.endpoint}`;
          } else if (config.capture.ffmpegPathError) {
            throw new Error(config.capture.ffmpegPathError);
          } else {
            const ffmpeg = await pi.exec(config.capture.ffmpegPath, ["-version"], { timeout: 5000 });
            if (ffmpeg.code !== 0) throw new Error(`ffmpeg check failed: ${ffmpeg.stderr || ffmpeg.stdout}`);
            capture = `ffmpeg ${config.capture.ffmpegPath}`;
          }
          ctx.ui.notify(`Pi Voice STT ready (${capture}, ${config.provider.type}/${config.provider.model}).`, "info");
        } catch (error) {
          reportError(ctx, error);
        }
        return;
      }

      if (action !== "status") {
        ctx.ui.notify("Usage: /stt [start|stop|send|cancel|mode <name>|status|doctor]", "error");
        return;
      }

      const configPath = startup.configPath || "defaults only (set PI_STT_CONFIG or ~/.pi/agent/stt.json)";
      // Status stays cheap and side-effect free: parsing the config file is the
      // only I/O, so no PATH scan for ffmpeg, no key file read and no Keychain
      // lookup happens here. Resolving those lives in `/stt doctor`.
      const problem = startup.configPath
        ? await readConfigFile(startup.configPath).then(() => "").catch((error: unknown) => formatError(error))
        : "";
      const status = `Pi Voice STT: ${controller.getMode()} · mode ${activeMode} · keybind ${keybind} · config ${configPath}`;
      ctx.ui.notify(
        problem ? `${status} · problem: ${problem}` : `${status} · run /stt doctor to check capture and provider`,
        problem ? "warning" : "info",
      );
    },
  });

  pi.on("session_start", (_event, ctx) => {
    if (!ctx.hasUI) return;

    const previousEditor = ctx.ui.getEditorComponent();
    ctx.ui.setEditorComponent(createVoiceEditorFactory(previousEditor, {
      keybinds: startup.keybinds,
      ctx,
      getMode: () => controller.getMode(),
      renderLabel: (theme) => inputIndicator.renderLabel(theme),
      attachTui: (tui) => inputIndicator.attach(tui),
      attachEditor: (editor) => {
        activeEditor = editor;
      },
      onToggle: (handlerCtx) => {
        void (async () => {
          // Idle -> start recording. While recording/processing -> stop. The
          // stop path honors output.submitOnStop: when enabled, Ctrl+R also
          // sends the transcript to chat (like Enter), instead of only
          // inserting it into the prompt.
          if (controller.getMode() === "idle") {
            await controller.toggle(handlerCtx);
            return;
          }
          const submitOnStop = await getConfig()
            .then((config) => config.output.submitOnStop)
            .catch(() => false);
          if (submitOnStop) await controller.stopAndSubmit(handlerCtx);
          else await controller.toggle(handlerCtx);
        })().catch((error: unknown) => reportError(handlerCtx, error));
      },
      onCancel: (handlerCtx) => {
        void controller.cancel(handlerCtx).catch((error: unknown) => reportError(handlerCtx, error));
      },
      onSend: (handlerCtx) => {
        void controller.stopAndSubmit(handlerCtx).catch((error: unknown) => reportError(handlerCtx, error));
      },
    }));
  });

  pi.on("session_shutdown", async () => {
    await controller.dispose();
    inputIndicator.dispose();
    activeEditor = undefined;
  });
}
