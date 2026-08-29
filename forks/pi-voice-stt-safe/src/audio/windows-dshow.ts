/**
 * DirectShow device listing for Windows ffmpeg capture.
 *
 * ffmpeg's stock default `audio=Microphone` is not a real device name. dshow
 * wants the friendly name from `-list_devices`, e.g. `audio=Microphone (USB …)`.
 */

const VIRTUAL_AUDIO =
  /steam streaming|oculus virtual|nvidia broadcast|vb-audio|cable (input|output)|stereo mix|wave out mix|what u hear|internal aux jack/i;

/** Parse friendly audio names from `ffmpeg -f dshow -list_devices true` stderr. */
export const parseDshowAudioDevices = (stderr: string): string[] => {
  const names: string[] = [];
  for (const line of stderr.split(/\r?\n/)) {
    const match = line.match(/"([^"]+)"\s*\(audio\)/i);
    if (match && !names.includes(match[1])) names.push(match[1]);
  }
  return names;
};

/**
 * Prefer a physical microphone over virtual loopbacks. USB mics win over
 * onboard when both exist; virtual Steam/Oculus devices are last resorts.
 */
export const pickWindowsMicrophone = (names: string[]): string | undefined => {
  if (names.length === 0) return undefined;
  const physical = names.filter((name) => !VIRTUAL_AUDIO.test(name));
  const pool = physical.length > 0 ? physical : names;
  const mics = pool.filter((name) => /microphone/i.test(name));
  const usb = mics.filter((name) => /usb/i.test(name));
  return usb[0] ?? mics[0] ?? pool[0];
};

export const toDshowInput = (deviceName: string): string => `audio=${deviceName}`;

/** Stock default that is not a real DirectShow friendly name. */
export const isPlaceholderDshowMic = (input: string): boolean =>
  input === "audio=Microphone" || input === "Microphone";

