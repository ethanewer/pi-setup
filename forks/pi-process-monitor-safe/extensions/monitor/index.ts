/**
 * pi-process-monitor-safe — non-blocking background watcher for pi.
 *
 * Safety-hardened local fork of pi-process-monitor@1.2.0 (MIT, Francesco
 * Frapporti). See PLAN.md and README.md for the behavioral contract. Do not
 * load this fork alongside the upstream package: tool and command names
 * collide by design because this package replaces it.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  createRealClock,
  createRealFileAdapter,
  createRealProcessAdapter,
  randomWatcherId,
} from "./adapters.ts";
import { registerMonitorExtension } from "./extension.ts";

export { registerMonitorExtension } from "./extension.ts";
export type { MonitorAdapters } from "./extension.ts";
export { createMonitorRuntime } from "./runtime.ts";
export * from "./types.ts";

export default function (pi: ExtensionAPI) {
  registerMonitorExtension(pi, {
    clock: createRealClock(),
    proc: createRealProcessAdapter(),
    files: createRealFileAdapter(),
    randomId: randomWatcherId,
    defaultCwd: () => process.cwd(),
  });
}
