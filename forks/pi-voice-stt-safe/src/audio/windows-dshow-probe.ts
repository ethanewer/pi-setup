import { spawn, spawnSync } from "node:child_process";
import { parseDshowAudioDevices, pickWindowsMicrophone, toDshowInput } from "./windows-dshow.ts";

const LIST_TIMEOUT_MS = 8000;

let cached: string | undefined;
let inflight: Promise<string | undefined> | undefined;

const listDshowStderr = (ffmpegPath: string): Promise<string> =>
  new Promise((resolve) => {
    const child = spawn(
      ffmpegPath,
      ["-hide_banner", "-f", "dshow", "-list_devices", "true", "-i", "dummy"],
      { stdio: ["ignore", "ignore", "pipe"], windowsHide: true },
    );
    let stderr = "";
    let finished = false;
    const finish = (value: string) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      resolve(value);
    };
    const timer = setTimeout(() => {
      if (child.pid !== undefined) {
        spawnSync("taskkill", ["/PID", String(child.pid), "/T", "/F"], { stdio: "ignore", windowsHide: true });
      } else {
        try {
          child.kill("SIGKILL");
        } catch {
          /* already gone */
        }
      }
      finish(stderr);
    }, LIST_TIMEOUT_MS);
    child.stderr?.setEncoding("utf8");
    child.stderr?.on("data", (chunk: string) => {
      stderr += chunk;
    });
    child.once("error", () => finish(""));
    child.once("close", () => finish(stderr));
  });

/** Resolve `audio=<friendly name>` after a successful listing; retry on empty or failed probes. */
export const probeWindowsDshowInput = async (
  ffmpegPath: string,
  listDevices: (ffmpegPath: string) => Promise<string> = listDshowStderr,
): Promise<string | undefined> => {
  if (cached) return cached;
  if (inflight) return inflight;
  inflight = (async () => {
    try {
      const name = pickWindowsMicrophone(parseDshowAudioDevices(await listDevices(ffmpegPath)));
      const result = name ? toDshowInput(name) : undefined;
      if (result) cached = result;
      return result;
    } catch {
      return undefined;
    }
  })().finally(() => {
    inflight = undefined;
  });
  return inflight;
};

export const resetWindowsDshowProbeCache = (): void => {
  cached = undefined;
  inflight = undefined;
};
