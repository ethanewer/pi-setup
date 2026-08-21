import { describe, expect, test } from "bun:test";
import {
  isPlaceholderDshowMic,
  parseDshowAudioDevices,
  pickWindowsMicrophone,
  toDshowInput,
} from "../forks/pi-voice-stt-safe/src/audio/windows-dshow.ts";

const listing = `
[in#0 @ 00000223175cee80] Could not enumerate video devices (or none found).
[in#0 @ 00000223175cee80] "Microphone (USB Advanced Audio Device)" (audio)
[in#0 @ 00000223175cee80]   Alternative name "@device_cm_{33D9A762-90C8-11D0-BD43-00A0C911CE86}\\wave_{FDD88285-09ED-4683-8291-C7BB96014D76}"
[in#0 @ 00000223175cee80] "Microphone (Steam Streaming Microphone)" (audio)
[in#0 @ 00000223175cee80] "Microphone (High Definition Audio Device)" (audio)
[in#0 @ 00000223175cee80] "Headset Microphone (Oculus Virtual Audio Device)" (audio)
[in#0 @ 00000223175cee80] "Internal AUX Jack (Steam Streaming Speakers)" (audio)
Error opening input file dummy.
`;

describe("parseDshowAudioDevices", () => {
  test("reads friendly names and skips alternative device paths", () => {
    expect(parseDshowAudioDevices(listing)).toEqual([
      "Microphone (USB Advanced Audio Device)",
      "Microphone (Steam Streaming Microphone)",
      "Microphone (High Definition Audio Device)",
      "Headset Microphone (Oculus Virtual Audio Device)",
      "Internal AUX Jack (Steam Streaming Speakers)",
    ]);
  });
});

describe("pickWindowsMicrophone", () => {
  test("prefers a USB microphone over onboard and virtual devices", () => {
    expect(pickWindowsMicrophone(parseDshowAudioDevices(listing))).toBe(
      "Microphone (USB Advanced Audio Device)",
    );
  });

  test("skips Steam/Oculus virtual devices when a physical mic exists", () => {
    expect(
      pickWindowsMicrophone([
        "Microphone (Steam Streaming Microphone)",
        "Microphone (High Definition Audio Device)",
        "Headset Microphone (Oculus Virtual Audio Device)",
      ]),
    ).toBe("Microphone (High Definition Audio Device)");
  });

  test("falls back to the first listed device when everything looks virtual", () => {
    expect(pickWindowsMicrophone(["Microphone (Steam Streaming Microphone)"])).toBe(
      "Microphone (Steam Streaming Microphone)",
    );
  });
});

describe("toDshowInput", () => {
  test("uses the dshow audio= form without extra quotes", () => {
    expect(toDshowInput("Microphone (USB Advanced Audio Device)")).toBe(
      "audio=Microphone (USB Advanced Audio Device)",
    );
  });
});

describe("isPlaceholderDshowMic", () => {
  test("matches only the stock Windows default", () => {
    expect(isPlaceholderDshowMic("audio=Microphone")).toBe(true);
    expect(isPlaceholderDshowMic("audio=Microphone (USB Advanced Audio Device)")).toBe(false);
  });
});

describe("probeWindowsDshowInput", () => {
  test("retries after a failed listing instead of caching the miss", async () => {
    const { probeWindowsDshowInput, resetWindowsDshowProbeCache } = await import(
      "../forks/pi-voice-stt-safe/src/audio/windows-dshow-probe.ts"
    );
    resetWindowsDshowProbeCache();
    let calls = 0;
    const list = async () => {
      calls += 1;
      return calls === 1 ? "" : listing;
    };
    expect(await probeWindowsDshowInput("ffmpeg", list)).toBeUndefined();
    expect(await probeWindowsDshowInput("ffmpeg", list)).toBe(
      "audio=Microphone (USB Advanced Audio Device)",
    );
    expect(await probeWindowsDshowInput("ffmpeg", list)).toBe(
      "audio=Microphone (USB Advanced Audio Device)",
    );
    expect(calls).toBe(2);
    resetWindowsDshowProbeCache();
  });
});
