import { CustomEditor, type AppKeybinding, type ExtensionContext, type KeybindingsManager, type Theme } from "@earendil-works/pi-coding-agent";
import {
  CURSOR_MARKER,
  matchesKey,
  truncateToWidth,
  visibleWidth,
  type EditorComponent,
  type EditorTheme,
  type TUI,
} from "@earendil-works/pi-tui";
import type { DictationMode } from "../core/dictation-controller";
import { matchesAnyKeybind } from "../core/keybind";
import type { Strings } from "../i18n/strings";
import { composeCursorLine } from "./cursor-cell";
import { animateRenderedLines, frameAt } from "./transcribing";

type VoiceEditorOptions = {
  keybinds: string[];
  ctx: ExtensionContext;
  keybindings: KeybindingsManager;
  getMode(): DictationMode;
  getTick(): number;
  renderLabel(theme: Theme): string;
  onToggle(ctx: ExtensionContext): void;
  onCancel(ctx: ExtensionContext): void;
  onSend(ctx: ExtensionContext): void;
  onQueue(ctx: ExtensionContext): void;
  /** Stop recording, leave the transcript in the editor, then apply this keystroke. */
  onInsertThen(ctx: ExtensionContext, data: string): void;
};

/**
 * Ticks per blink phase. The dot spends this many animation frames lit and the same
 * number dim, so at the 120ms tick it pulses about once a second — calmer than the
 * two-frame flicker it replaces.
 */
const BLINK_TICKS = 4;

/** Shown at the cursor while recording, when the cells after it are blank. The brackets
 * keep it from running into whatever the user has typed. */
const RECORDING_LABEL = " recording]";

const injectRightLabel = (line: string, width: number, label: string): string => {
  const labelWidth = visibleWidth(label);
  if (width <= 0) return "";
  if (labelWidth <= 0) return truncateToWidth(line, width, "");
  if (labelWidth >= width) return truncateToWidth(label, width, "");

  const gap = " ";
  const leftWidth = Math.max(0, width - labelWidth - visibleWidth(gap));
  const left = truncateToWidth(line, leftWidth, "");
  return truncateToWidth(`${left}${gap}${label}`, width, "");
};

class VoiceEditorWrapper implements EditorComponent {
  onSubmit?: (text: string) => void;
  onChange?: (text: string) => void;
  borderColor?: (str: string) => string;

  constructor(
    private readonly base: EditorComponent,
    private readonly options: VoiceEditorOptions,
  ) {}

  // Proxy CustomEditor action handlers and app-level callbacks to the base
  // editor so pi's interactive mode can duck-type and set them properly.
  // Without this, app.exit (Ctrl+D), app.interrupt (Escape), paste-image,
  // and extension shortcuts are silently swallowed.
  private get baseRecord(): Record<string, unknown> {
    return this.base as unknown as Record<string, unknown>;
  }

  get actionHandlers(): Map<string, () => void> | undefined {
    return this.baseRecord.actionHandlers as Map<string, () => void> | undefined;
  }

  get onCtrlD(): (() => void) | undefined {
    return this.baseRecord.onCtrlD as (() => void) | undefined;
  }
  set onCtrlD(handler: (() => void) | undefined) {
    this.baseRecord.onCtrlD = handler;
  }

  get onEscape(): (() => void) | undefined {
    return this.baseRecord.onEscape as (() => void) | undefined;
  }
  set onEscape(handler: (() => void) | undefined) {
    this.baseRecord.onEscape = handler;
  }

  get onPasteImage(): (() => void) | undefined {
    return this.baseRecord.onPasteImage as (() => void) | undefined;
  }
  set onPasteImage(handler: (() => void) | undefined) {
    this.baseRecord.onPasteImage = handler;
  }

  get onExtensionShortcut(): ((data: string) => void) | undefined {
    return this.baseRecord.onExtensionShortcut as ((data: string) => void) | undefined;
  }
  set onExtensionShortcut(handler: ((data: string) => void) | undefined) {
    this.baseRecord.onExtensionShortcut = handler;
  }

  private syncBase(): void {
    if (this.onSubmit) this.base.onSubmit = this.onSubmit;
    else delete this.base.onSubmit;

    if (this.onChange) this.base.onChange = this.onChange;
    else delete this.base.onChange;

    if (this.borderColor) this.base.borderColor = this.borderColor;
  }

  get focused(): boolean {
    return Boolean((this.base as EditorComponent & { focused?: boolean }).focused);
  }

  set focused(value: boolean) {
    (this.base as EditorComponent & { focused?: boolean }).focused = value;
  }

  /**
   * The recording indicator takes the cursor's place rather than adding another element
   * to the frame: while recording, the point where typing would land pulses red, with a
   * grey "recording" beside it when there is blank space to put it. Both disappear the
   * moment transcription starts, where the placeholder takes over.
   */
  private replaceCursor(lines: string[], width: number): string[] {
    if (this.options.getMode() !== "recording") return lines;
    const theme = this.options.ctx.ui.theme;
    const lit = Math.floor(this.options.getTick() / BLINK_TICKS) % 2 === 0;
    const dot = theme.fg(lit ? "error" : "dim", "●");
    // Brackets in the same grey as the label, so the block reads as one thing and the
    // pulsing dot is the only colour in it.
    const full = {
      text: `${theme.fg("dim", "[")}${dot}${theme.fg("dim", RECORDING_LABEL)}`,
      width: RECORDING_LABEL.length + 2,
    };
    const minimal = { text: dot, width: 1 };
    let done = false;
    return lines.map((line) => {
      if (done || !line.includes(CURSOR_MARKER)) return line;
      done = true;
      return composeCursorLine(line, full, minimal, width);
    });
  }

  render(width: number): string[] {
    this.syncBase();
    const lines = this.replaceCursor(
      animateRenderedLines(this.base.render(width), frameAt(this.options.getTick()), (text) =>
        this.options.ctx.ui.theme.fg("dim", text),
      ),
      width,
    );
    if (lines.length === 0) return lines;

    const label = this.options.renderLabel(this.options.ctx.ui.theme);
    if (label.length > 0) lines[0] = injectRightLabel(lines[0] ?? "", width, label);
    return lines;
  }

  /**
   * While recording, the next keystroke decides where the transcript goes:
   *
   *   the voice key  keep it in the editor
   *   enter          send it
   *   the queue key  queue it as a follow-up
   *   escape         throw the recording away
   *   anything else  keep it in the editor, then apply the key
   *
   * The last rule is what makes recording feel like typing: pressing Option+Enter
   * mid-recording leaves the placeholder behind and puts the cursor on a fresh line,
   * rather than being swallowed or ending the recording with no destination.
   */
  handleInput(data: string): void {
    this.syncBase();
    const mode = this.options.getMode();

    if (matchesAnyKeybind(data, this.options.keybinds)) {
      this.options.onToggle(this.options.ctx);
      return;
    }

    if (mode === "recording") {
      if (matchesKey(data, "escape")) {
        this.options.onCancel(this.options.ctx);
        return;
      }
      if (matchesKey(data, "enter")) {
        this.options.onSend(this.options.ctx);
        return;
      }
      if (this.options.keybindings.matches(data, "app.message.followUp" as AppKeybinding)) {
        this.options.onQueue(this.options.ctx);
        return;
      }
      this.options.onInsertThen(this.options.ctx, data);
      return;
    }

    // Transcribing is not a modal state: the placeholder holds the spot and everything
    // typed around it behaves normally.
    this.base.handleInput(data);
  }

  invalidate(): void {
    this.base.invalidate();
  }

  getText(): string {
    return this.base.getText();
  }

  setText(text: string): void {
    this.syncBase();
    this.base.setText(text);
  }

  addToHistory(text: string): void {
    this.base.addToHistory?.(text);
  }

  // Always effective: falls back to an append when the wrapped editor has no
  // cursor-aware insertion, so a transcript can never be silently dropped.
  insertTextAtCursor(text: string): void {
    this.syncBase();
    if (this.base.insertTextAtCursor) {
      this.base.insertTextAtCursor(text);
      return;
    }
    this.base.setText(`${this.base.getText()}${text}`);
  }

  getExpandedText(): string {
    return this.base.getExpandedText?.() ?? this.base.getText();
  }

  setAutocompleteProvider(provider: Parameters<NonNullable<EditorComponent["setAutocompleteProvider"]>>[0]): void {
    this.base.setAutocompleteProvider?.(provider);
  }

  setPaddingX(padding: number): void {
    this.base.setPaddingX?.(padding);
  }

  setAutocompleteMaxVisible(maxVisible: number): void {
    this.base.setAutocompleteMaxVisible?.(maxVisible);
  }

  dispose(): void {
    (this.base as EditorComponent & { dispose?: () => void }).dispose?.();
  }
}

export const createInputIndicator = (keybind: string, strings: Strings) => {
  let mode: DictationMode = "idle";
  let tui: TUI | undefined;
  let tick = 0;
  let placeholders = 0;
  let timer: ReturnType<typeof setInterval> | undefined;

  const requestRender = () => tui?.requestRender();

  const stopAnimation = () => {
    if (!timer) return;
    clearInterval(timer);
    timer = undefined;
  };

  const animating = () => mode !== "idle" || placeholders > 0;

  const startAnimation = () => {
    if (timer || !animating()) return;
    timer = setInterval(() => {
      tick += 1;
      requestRender();
    }, 120);
  };

  const syncAnimation = () => {
    if (animating()) startAnimation();
    else stopAnimation();
  };

  return {
    attach(tuiInstance: TUI) {
      tui = tuiInstance;
      syncAnimation();
      requestRender();
    },
    setMode(nextMode: DictationMode) {
      mode = nextMode;
      tick += 1;
      syncAnimation();
      requestRender();
    },
    /** Spinners keep turning while transcripts are outstanding, in the editor or above it. */
    setPlaceholderCount(count: number) {
      placeholders = Math.max(0, count);
      syncAnimation();
      requestRender();
    },
    getTick: () => tick,
    /**
     * Only the idle affordance is a label. Recording is the pulsing cursor and
     * transcribing is the placeholder, both of which sit where the text is — so adding a
     * banner for either would just be a second thing to read.
     */
    renderLabel(theme: Theme): string {
      if (mode !== "idle") return "";
      return `${theme.fg("dim", strings.indicator.idle)} ${theme.fg("accent", keybind)}`;
    },
    dispose() {
      stopAnimation();
      tui = undefined;
      mode = "idle";
    },
  };
};

export const createVoiceEditorFactory = (
  previousFactory: ((tui: TUI, theme: EditorTheme, keybindings: KeybindingsManager) => EditorComponent) | undefined,
  // The keybindings manager is handed to the factory by Pi, not by the caller, so the
  // queue key follows whatever the user configured for app.message.followUp.
  options: Omit<VoiceEditorOptions, "keybindings"> & {
    attachTui(tui: TUI): void;
    attachEditor?(editor: EditorComponent): void;
    /** Pi hands the resolved keybindings to the factory; nothing else in the extension sees them. */
    attachKeybindings?(keybindings: KeybindingsManager): void;
  },
) => {
  return (tui: TUI, theme: EditorTheme, keybindings: KeybindingsManager): EditorComponent => {
    options.attachTui(tui);
    options.attachKeybindings?.(keybindings);
    const base = previousFactory?.(tui, theme, keybindings) ?? new CustomEditor(tui, theme, keybindings);
    const editor = new VoiceEditorWrapper(base, { ...options, keybindings });
    options.attachEditor?.(editor);
    return editor;
  };
};
