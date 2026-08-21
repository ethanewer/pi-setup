import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { FfmpegCaptureConfig } from "../config/types";
import { assertExecutablePath } from "../utils/executable";
import { formatError, truncate } from "../utils/text";
import type { AudioRecorder, RecordingHandle } from "./types";
import { isPlaceholderDshowMic } from "./windows-dshow.ts";

const MAX_STDERR_BYTES = 24 * 1024;
const WIN32 = process.platform === "win32";

const collectStderr = (stream: NodeJS.ReadableStream): (() => string) => {
  let stderr = "";
  stream.setEncoding("utf8");
  stream.on("data", (chunk: string) => {
    stderr += chunk;
    if (Buffer.byteLength(stderr, "utf8") > MAX_STDERR_BYTES) {
      stderr = stderr.slice(-MAX_STDERR_BYTES);
    }
  });
  return () => stderr;
};

const waitForExit = (child: ChildProcess): Promise<string> => {
  return new Promise((resolve) => {
    child.once("error", (error) => resolve(`process error: ${formatError(error)}`));
    child.once("close", (code, signal) => resolve(signal ? `signal ${signal}` : `exit ${code ?? "unknown"}`));
  });
};

const taskkill = (pid: number, force: boolean): void => {
  const args = ["/PID", String(pid), "/T"];
  if (force) args.push("/F");
  spawnSync("taskkill", args, { stdio: "ignore", windowsHide: true });
};

const ffmpegArgs = (config: FfmpegCaptureConfig, inputFormat: string, input: string, outputPath: string): string[] => {
  const args = ["-hide_banner", "-loglevel", "warning", "-f", inputFormat];
  // Input options must precede -i. dshow otherwise drops or never delivers frames.
  if (inputFormat === "dshow") args.push("-rtbufsize", "16M");
  args.push(
    "-i",
    input,
    "-vn",
    "-acodec",
    "pcm_s16le",
    "-ar",
    String(config.sampleRate),
    "-ac",
    String(config.channels),
    "-t",
    String(config.maxSeconds),
    "-y",
    outputPath,
  );
  return args;
};

export const createFfmpegRecorder = (config: FfmpegCaptureConfig): AudioRecorder => ({
  async start() {
    // Config load only reports an unresolvable path so the diagnostics still
    // run; nothing is spawned until it resolves to an absolute executable.
    if (config.ffmpegPathError) throw new Error(config.ffmpegPathError);
    assertExecutablePath(config.ffmpegPath, "STT capture.ffmpegPath");

    let inputFormat = config.inputFormat;
    let input = config.input;
    if (WIN32 && inputFormat === "dshow" && isPlaceholderDshowMic(input)) {
      const { probeWindowsDshowInput } = await import("./windows-dshow-probe.ts");
      const probed = await probeWindowsDshowInput(config.ffmpegPath);
      if (probed) input = probed;
    }

    const tempDir = mkdtempSync(join(tmpdir(), "pi-voice-stt-"));
    const outputPath = join(tempDir, "recording.wav");
    // stdin stays open so we can send ffmpeg's interactive `q` — SIGINT does not
    // stop ffmpeg on Windows, and killing it leaves a 0-byte WAV.
    const child = spawn(config.ffmpegPath, ffmpegArgs(config, inputFormat, input, outputPath), {
      stdio: ["pipe", "ignore", "pipe"],
      windowsHide: true,
    });

    const getStderr = collectStderr(child.stderr!);
    const exited = waitForExit(child);
    let stopped = false;

    const terminate = () => {
      if (child.exitCode !== null || child.signalCode !== null) return;
      try {
        child.stdin?.write("q");
        child.stdin?.end();
      } catch {
        /* already dead */
      }
    };

    const forceKill = () => {
      if (child.exitCode !== null || child.signalCode !== null) return;
      if (WIN32 && child.pid !== undefined) {
        taskkill(child.pid, true);
        return;
      }
      try {
        child.kill("SIGKILL");
      } catch {
        /* already dead */
      }
    };

    const stop = async () => {
      if (!stopped) {
        stopped = true;
        terminate();
      }

      const killTimer = setTimeout(forceKill, 3000);
      const exitResult = await exited;
      clearTimeout(killTimer);
      const stderrText = getStderr();

      let size = 0;
      try {
        size = (await stat(outputPath)).size;
      } catch {
        throw new Error(
          `ffmpeg did not create an audio file (${exitResult}) using ${inputFormat} ${input}. ${truncate(stderrText)}`,
        );
      }

      if (size < config.minBytes) {
        throw new Error(
          `Recording is too small (${size} bytes) — the audio source produced no data ` +
            `(${inputFormat} ${input}). ` +
            `Check microphone permission and that capture.inputFormat/capture.input point to a real device. ` +
            `On Windows, list devices with: ffmpeg -f dshow -list_devices true -i dummy and set capture.input to audio=<exact name>. ` +
            `On Linux, if the default PulseAudio source is empty, try ALSA (inputFormat "alsa", input "default"; list with: arecord -L). ` +
            truncate(stderrText),
        );
      }

      return outputPath;
    };

    const dispose = async () => {
      if (!stopped) {
        stopped = true;
        terminate();
      }
      const killTimer = setTimeout(forceKill, 3000);
      await exited.catch((error: unknown) => {
        console.warn(`Pi Voice STT recording cleanup failed: ${formatError(error)}`);
      });
      clearTimeout(killTimer);
      await rm(tempDir, { recursive: true, force: true }).catch((error: unknown) => {
        console.warn(`Pi Voice STT temp cleanup failed: ${formatError(error)}`);
      });
    };

    return {
      outputPath,
      stop,
      dispose,
    } satisfies RecordingHandle;
  },
});
