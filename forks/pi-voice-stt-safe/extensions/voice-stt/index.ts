/**
 * Extension entry point.
 *
 * The implementation lives in src/. This file exists so that the entry path ends in
 * extensions/voice-stt/index.ts: Pi labels an extension by the directory holding its
 * index file, so pointing pi.extensions straight at src/index.ts made this package
 * appear as "src" in the startup listing.
 */
export { default } from "../../src/index.js";
