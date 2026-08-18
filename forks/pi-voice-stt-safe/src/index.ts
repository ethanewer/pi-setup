import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { EditorComponent } from "@earendil-works/pi-tui";
import { checkBridgeRecorderHealth } from "./audio/bridge-recorder";
import { createRecorder } from "./audio/factory";
import { loadConfig, readConfigFile } from "./config/load-config";
import { resolveStartupOptions } from "./config/startup";
import { DEFAULT_PROFILE, isKnownProfile, listProfileNames, resolveEffectiveProfile, writeProfileState } from "./config/profiles";
import { createDictationController, type DictationToast } from "./core/dictation-controller";
import { DEFAULT_MODE, isKnownMode, listModeNames } from "./core/modes";
import { createProvider } from "./providers/factory";
import { createCleanup } from "./cleanup/factory";
import { assertProviderReady } from "./providers/readiness";
import { createInputIndicator, createVoiceEditorFactory } from "./ui/input-indicator";
import { resolveStrings } from "./i18n/strings";
import { containsPasteMarker, formatError } from "./utils/text";
import type { AppKeybinding, KeybindingsManager } from "@earendil-works/pi-coding-agent";
import type { KeyId } from "@earendil-works/pi-tui";
import type { Delivery } from "./core/dictation-controller";
import { nextFreeSlot, placeholderText, replacePlaceholder } from "./ui/transcribing";
import { createPendingStore } from "./ui/pending-message";
import { textFrom } from "./utils/coerce";
import { kittyCtrlShiftLetterRegex } from "./utils/keybind";

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
  const profileKeybind = startup.profileKeybind;
  const strings = resolveStrings(startup.locale);
  const inputIndicator = createInputIndicator(keybind, strings);
  let activeMode = startup.mode || DEFAULT_MODE;
  let activeEditor: EditorComponent | undefined;
  let activeProfile = startup.profile;
  const terminalInputCleanup: Array<() => void> = [];
  // Prompt as it stood right after the transcript was inserted. Anything typed
  // afterwards stays in the editor instead of being swept into the sent message.
  // Kept in both forms: getEditorText() expands pi paste markers, the editor's
  // own text still holds them.
  let insertedPrompt: string | undefined;
  let insertedEditorText: string | undefined;

  // Apply the persisted last-selection (sidecar state) once loaded; env and
  // the config `profile` key are already folded into startup.profile.
  void (async () => {
    const fileConfig = await readConfigFile(startup.configPath).catch(() => ({}));
    const effective = await resolveEffectiveProfile({
      configPath: startup.configPath,
      envProfile: textFrom(process.env.PI_STT_PROFILE),
      configProfile: startup.profile,
    });
    const safe = isKnownProfile(fileConfig, effective) ? effective : isKnownProfile(fileConfig, startup.profile) ? startup.profile : DEFAULT_PROFILE;
    if (safe !== activeProfile) {
      activeProfile = safe;
      inputIndicator.setProfile(activeProfile);
    }
  })().catch(() => {});

  const getConfig = () => loadConfig({ configPath: startup.configPath, mode: activeMode, profile: activeProfile });

  const pendingMessages = createPendingStore(() => inputIndicator.getTick());

  /**
   * Put the dictation key in `/hotkeys`, which lists Pi's own bindings plus whatever
   * extensions registered. The editor wrapper sees the key before Pi's shortcut dispatch,
   * so this registration is what makes it discoverable rather than what makes it work —
   * and its handler covers the case where the editor does not have focus.
   */
  let shortcutRegistered = false;
  const registerVoiceShortcut = (keybindings: KeybindingsManager, ctx: ExtensionContext) => {
    if (shortcutRegistered) return;
    const primary = startup.keybinds[0];
    if (!primary) return;
    shortcutRegistered = true;
    // "alt" reads as Option on macOS, the way Pi renders its own hints.
    const asOption = (key: string) =>
      key
        .split("+")
        .map((part) => (process.platform === "darwin" && part === "alt" ? "Option" : part.charAt(0).toUpperCase() + part.slice(1)))
        .join("+");
    const queueKey = keybindings.getKeys("app.message.followUp" as AppKeybinding)[0];
    const queue = queueKey ? asOption(queueKey) : "the follow-up key";
    const alternates = startup.keybinds.slice(1).join(" / ");
    try {
      pi.registerShortcut(primary as KeyId, {
        // Kept short: /hotkeys renders this in a fixed-width table and truncates.
        description:
          `Voice dictation${alternates ? ` (also ${alternates})` : ""} · recording: ` +
          `Enter send · ${queue} queue · Esc cancel`,
        handler: (shortcutCtx) => {
          void controller.toggle(shortcutCtx).catch((error: unknown) => reportError(shortcutCtx, error));
        },
      });
    } catch {
      // Not a key id Pi can bind — a configuration of only literal characters, say. The
      // key still works through the editor; it just cannot be listed.
      void ctx;
    }
  };

  /**
   * Slots of the placeholders outstanding anywhere. Each transcription owns one, so its
   * result can only land in its own block, and the spinner keeps turning while any remain.
   */
  const openSlots = new Set<number>();
  const claimSlot = (): number => {
    const slot = nextFreeSlot(openSlots);
    openSlots.add(slot);
    inputIndicator.setPlaceholderCount(openSlots.size);
    return slot;
  };
  const releaseSlot = (slot: number) => {
    openSlots.delete(slot);
    inputIndicator.setPlaceholderCount(openSlots.size);
  };

  /**
   * Rewrite the editor's text. Prefers the editor's own raw text so paste markers
   * survive, and falls back to the expanded text when a marker would be orphaned:
   * setEditorText drops the paste map, and a marker with nothing to expand to loses the
   * pasted content entirely.
   */
  const rewriteEditor = (ctx: ExtensionContext, rewrite: (text: string) => { text: string; replaced: boolean }): boolean => {
    const raw = activeEditor?.getText();
    if (raw !== undefined && !containsPasteMarker(raw)) {
      const next = rewrite(raw);
      if (next.replaced) ctx.ui.setEditorText(next.text);
      return next.replaced;
    }
    const next = rewrite(ctx.ui.getEditorText());
    if (next.replaced) ctx.ui.setEditorText(next.text);
    return next.replaced;
  };

  /** The transcript is destined for the prompt: hold its place with a placeholder. */
  const beginEditorDelivery = (ctx: ExtensionContext): Delivery => {
    const slot = claimSlot();
    const marker = placeholderText(slot);
    if (activeEditor?.insertTextAtCursor) activeEditor.insertTextAtCursor(marker);
    else ctx.ui.setEditorText(`${ctx.ui.getEditorText()}${marker}`);

    let settled = false;
    const finish = (replacement: string) => {
      if (settled) return false;
      settled = true;
      releaseSlot(slot);
      return rewriteEditor(ctx, (text) => replacePlaceholder(text, replacement, marker));
    };

    return {
      resolve: (text) => {
        // A placeholder the user deleted while waiting means the transcript has nowhere to
        // go; appending it to whatever they typed instead would be worse than losing it.
        // Say that plainly rather than reporting an insertion that did not happen.
        if (!finish(text)) {
          notify(ctx, {
            title: "Pi Voice STT",
            message: "Transcript discarded: its placeholder was removed from the prompt.",
            variant: "warning",
          });
        }
      },
      fail: (message) => {
        finish("");
        notify(ctx, { title: "Pi Voice STT", message, variant: "error" });
      },
      cancel: () => {
        finish("");
      },
    };
  };

  /**
   * The user already committed to sending or queueing, so the whole message leaves the
   * composer now — anything already typed included, with the placeholder standing where
   * the cursor was. It waits above the editor until the transcript exists, and only then
   * is a message sent for the first time; the model sees nothing before that.
   *
   * On failure the composed text goes back into the editor. Taking someone's typing and
   * then losing it because a provider timed out is not an acceptable way to fail.
   */
  const beginMessageDelivery = (ctx: ExtensionContext, outcome: "send" | "queue"): Delivery => {
    // Insert at the cursor first, then take the line: the transcript lands where the
    // cursor was, keeping whatever was typed on either side of it.
    const slot = claimSlot();
    const marker = placeholderText(slot);
    if (activeEditor?.insertTextAtCursor) activeEditor.insertTextAtCursor(marker);
    else ctx.ui.setEditorText(`${ctx.ui.getEditorText()}${marker}`);
    // The expanded text, so pasted content travels with the message rather than as a
    // marker that no longer has anything to expand to once the editor is cleared.
    const composed = ctx.ui.getEditorText();
    ctx.ui.setEditorText("");

    const id = pendingMessages.begin(ctx, outcome, composed);
    let settled = false;
    const settle = () => {
      if (settled) return false;
      settled = true;
      releaseSlot(slot);
      return true;
    };

    const restore = () => {
      const { text } = replacePlaceholder(composed, "", marker);
      if (text.trim().length === 0) return;
      const current = ctx.ui.getEditorText();
      ctx.ui.setEditorText(current.length > 0 ? `${text}${current}` : text);
    };

    return {
      resolve: (text) => {
        if (!settle()) return;
        pendingMessages.resolve(ctx, id);
        const { text: full, replaced } = replacePlaceholder(composed, text, marker);
        const prompt = (replaced ? full : `${composed} ${text}`).trim();
        if (!prompt) return;
        if (outcome === "queue" || !ctx.isIdle()) pi.sendUserMessage(prompt, { deliverAs: "followUp" });
        else pi.sendUserMessage(prompt);
      },
      fail: (message) => {
        if (!settle()) return;
        pendingMessages.fail(ctx, id, message);
        restore();
      },
      cancel: () => {
        if (!settle()) return;
        pendingMessages.resolve(ctx, id);
        restore();
      },
    };
  };

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
    createProvider: (config) => {
      // Test seam. PI_STT_FAKE_TRANSCRIPT replaces the provider with a fixed answer so
      // the placeholder lifecycle can be driven end to end without a microphone or an API
      // call; PI_STT_FAKE_FAIL makes it fail instead. Both are ignored unless set, and
      // neither can widen what the real provider is allowed to do.
      const fake = process.env.PI_STT_FAKE_TRANSCRIPT;
      const fail = process.env.PI_STT_FAKE_FAIL;
      if (fake === undefined && fail === undefined) return createProvider(config.provider);
      const delayMs = Number.parseInt(process.env.PI_STT_FAKE_DELAY_MS ?? "", 10);
      return {
        transcribe: async () => {
          await new Promise((resolve) => setTimeout(resolve, Number.isFinite(delayMs) ? delayMs : 2000));
          if (fail !== undefined) throw new Error(fail || "fake transcription failure");
          return { text: fake ?? "" };
        },
      };
    },
    createCleanup: (config) => createCleanup(config.cleanup),
    beginDelivery: (ctx, outcome) => (outcome === "insert" ? beginEditorDelivery(ctx) : beginMessageDelivery(ctx, outcome)),
    notify,
    onModeChange: (mode) => inputIndicator.setMode(mode),
    onError: reportError,
  });

  const switchProfile = async (ctx: ExtensionContext, next: string): Promise<void> => {
    if (controller.getMode() === "processing") {
      notify(ctx, { title: "Pi Voice STT", message: strings.profile.busy, variant: "warning" });
      return;
    }
    activeProfile = next;
    inputIndicator.setProfile(next);
    try {
      await writeProfileState(startup.configPath, next);
    } catch {
      notify(ctx, { title: "Pi Voice STT", message: strings.profile.persistFailed, variant: "warning" });
    }
    notify(ctx, { title: "Pi Voice STT", message: strings.profile.set(next), variant: "success" });
  };

  const showProfileMenu = async (ctx: ExtensionContext): Promise<void> => {
    const fileConfig = await readConfigFile(startup.configPath).catch(() => ({}));
    const names = listProfileNames(fileConfig);
    if (names.length <= 1) {
      notify(ctx, { title: "Pi Voice STT", message: strings.profile.none, variant: "warning" });
      return;
    }
    const labels = names.map((name) => (name === activeProfile ? `${name} (${strings.profile.activeMarker})` : name));
    const byLabel = new Map(labels.map((label, index) => [label, names[index] ?? ""]));
    const chosen = await ctx.ui.select(strings.profile.menuTitle, labels);
    if (!chosen) return;
    const next = byLabel.get(chosen) ?? "";
    if (!next || next === activeProfile) return;
    if (!isKnownProfile(fileConfig, next)) {
      notify(ctx, { title: "Pi Voice STT", message: strings.profile.unknown(next), variant: "error" });
      return;
    }
    await switchProfile(ctx, next);
  };

  pi.registerCommand("stt", {
    description: "Voice dictation controls: start, stop, send, cancel, mode, profile, status, doctor.",
    getArgumentCompletions: (prefix) => {
      const commands = ["start", "stop", "send", "cancel", "mode", "profile", "status", "doctor"];
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

      if (action === "profile") {
        const fileConfig = await readConfigFile(startup.configPath).catch(() => ({}));
        const names = listProfileNames(fileConfig);
        if (!param) {
          ctx.ui.notify(strings.profile.list(activeProfile, names), "info");
          return;
        }
        const next = param.toLowerCase();
        if (!isKnownProfile(fileConfig, next)) {
          ctx.ui.notify(strings.profile.unknown(next), "error");
          return;
        }
        if (next === activeProfile) {
          ctx.ui.notify(`Pi Voice STT profile is already "${activeProfile}".`, "info");
          return;
        }
        await switchProfile(ctx, next);
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
        ctx.ui.notify("Usage: /stt [start|stop|send|cancel|mode <name>|profile <name>|status|doctor]", "error");
        return;
      }

      const configPath = startup.configPath || "defaults only (set PI_STT_CONFIG or ~/.pi/agent/stt.json)";
      // Status stays cheap and side-effect free: parsing the config file is the
      // only I/O, so no PATH scan for ffmpeg, no key file read and no Keychain
      // lookup happens here. Resolving those lives in `/stt doctor`.
      const problem = startup.configPath
        ? await readConfigFile(startup.configPath).then(() => "").catch((error: unknown) => formatError(error))
        : "";
      const status = `Pi Voice STT: ${controller.getMode()} · mode ${activeMode} · profile ${activeProfile} · keybind ${keybind} · config ${configPath}`;
      ctx.ui.notify(
        problem ? `${status} · problem: ${problem}` : `${status} · run /stt doctor to check capture and provider`,
        problem ? "warning" : "info",
      );
    },
  });

  pi.registerShortcut(startup.profileKeybind as KeyId, {
    description: "Pi Voice STT: switch profile",
    handler: async (ctx) => {
      if (!ctx.hasUI) return;
      await showProfileMenu(ctx).catch((error: unknown) => reportError(ctx, error));
    },
  });

  pi.on("session_start", (_event, ctx) => {
    if (!ctx.hasUI) return;

    // Raw Kitty CSI-u fallback for ctrl+shift+<letter> keybinds: pi-tui's key
    // parser misreads Kitty modifier 5 (shift+ctrl) as ctrl-only, so match the
    // raw sequence here. Works when the terminal (and tmux, with
    // `set -s extended-keys on`) forwards the Kitty keyboard protocol.
    const kittyRegex = kittyCtrlShiftLetterRegex(profileKeybind);
    const unsubscribeTerminal = kittyRegex
      ? ctx.ui.onTerminalInput((data) => {
          if (kittyRegex.test(data)) {
            void showProfileMenu(ctx).catch((error: unknown) => reportError(ctx, error));
            return { consume: true };
          }
          return undefined;
        })
      : undefined;
    if (unsubscribeTerminal) terminalInputCleanup.push(unsubscribeTerminal);

    const previousEditor = ctx.ui.getEditorComponent();
    ctx.ui.setEditorComponent(createVoiceEditorFactory(previousEditor, {
      keybinds: startup.keybinds,
      profileKeybind,
      ctx,
      getMode: () => controller.getMode(),
      getTick: () => inputIndicator.getTick(),
      renderLabel: (theme) => inputIndicator.renderLabel(theme),
      attachTui: (tui) => inputIndicator.attach(tui),
      attachKeybindings: (keybindings) => registerVoiceShortcut(keybindings, ctx),
      attachEditor: (editor) => {
        activeEditor = editor;
      },
      onToggle: (handlerCtx) => {
        // Idle starts recording; recording stops it and keeps the transcript in the
        // prompt. Sending has its own key, so the voice key has exactly one meaning.
        void controller.toggle(handlerCtx).catch((error: unknown) => reportError(handlerCtx, error));
      },
      onCancel: (handlerCtx) => {
        void controller.cancel(handlerCtx).catch((error: unknown) => reportError(handlerCtx, error));
      },
      onSend: (handlerCtx) => {
        void controller.stopAndSubmit(handlerCtx).catch((error: unknown) => reportError(handlerCtx, error));
      },
      onQueue: (handlerCtx) => {
        void controller.stop(handlerCtx, "queue").catch((error: unknown) => reportError(handlerCtx, error));
      },
      onInsertThen: (handlerCtx, data) => {
        // stop() claims the placeholder synchronously, before its first await, so the
        // keystroke can be replayed in the same tick — awaiting the returned promise
        // would hold it until the provider answered, and Option+Enter would land its
        // newline seconds later.
        void controller.stop(handlerCtx, "insert").catch((error: unknown) => reportError(handlerCtx, error));
        activeEditor?.handleInput(data);
      },
      onShowProfileMenu: (handlerCtx) => {
        void showProfileMenu(handlerCtx).catch((error: unknown) => reportError(handlerCtx, error));
      },
    }));
  });

  pi.on("session_shutdown", async () => {
    pendingMessages.dispose();
    for (const unsubscribe of terminalInputCleanup) unsubscribe();
    terminalInputCleanup.length = 0;
    await controller.dispose();
    inputIndicator.dispose();
    activeEditor = undefined;
  });
}
