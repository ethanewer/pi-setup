import { describe, expect, test } from "bun:test";
import mlxExtension from "../extensions/mlx/index";

describe("conditional mlx extension", () => {
  test("registers only on macOS and exposes the optimized download command", async () => {
    let mlxCommand: any;
    const execCalls: Array<{ command: string; args: string[] }> = [];
    const pi: any = {
      registerCommand(name: string, command: any) {
        if (name === "mlx") mlxCommand = command;
      },
      registerProvider() {},
      unregisterProvider() {},
      on() {},
      async setModel() { return true; },
      async exec(command: string, args: string[]) {
        execCalls.push({ command, args });
        return { code: 0, stdout: "Optimized Ornith-35B is already installed", stderr: "" };
      },
    };

    mlxExtension(pi);
    if (process.platform !== "darwin") {
      expect(mlxCommand).toBeUndefined();
      return;
    }

    expect(mlxCommand).toBeDefined();
    const notifications: string[] = [];
    const statuses: unknown[] = [];
    await mlxCommand.handler("download optimized-ornith", {
      waitForIdle: async () => {},
      modelRegistry: { getAvailable: () => [] },
      ui: {
        notify: (message: string) => notifications.push(message),
        setStatus: (_key: string, value: unknown) => statuses.push(value),
      },
    });

    expect(execCalls).toHaveLength(1);
    expect(execCalls[0].args[0]).toEndWith("/extensions/mlx/build_ornith.py");
    expect(notifications.at(-1)).toContain("already installed");
    expect(statuses).toEqual(["downloading optimized Ornith-35B…", undefined]);
  });
});
