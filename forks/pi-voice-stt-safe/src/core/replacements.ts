/**
 * Apply a user-defined dictionary of literal replacements to a transcript.
 * Matching is case-insensitive and word-boundary aware; longer keys are
 * applied first so multi-word terms win over their substrings. Pure and
 * deterministic so it can be unit tested.
 */
const escapeRegExp = (value: string): string => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

const WORD_CHARACTER = /[\p{L}\p{N}_]/u;
const WORD_CHARACTER_CLASS = "[\\p{L}\\p{N}_]";

/**
 * `\b` is ASCII-only, so keys such as "café" or "c++" would never match. The
 * boundary is asserted with a Unicode word class instead, and only on the sides
 * where the key itself starts or ends with a word character: that keeps "café"
 * from matching inside "cafés" while letting "c++" match at all.
 */
const boundedPattern = (key: string): RegExp => {
  const characters = [...key];
  const before = WORD_CHARACTER.test(characters[0] ?? "") ? `(?<!${WORD_CHARACTER_CLASS})` : "";
  const after = WORD_CHARACTER.test(characters[characters.length - 1] ?? "") ? `(?!${WORD_CHARACTER_CLASS})` : "";
  return new RegExp(`${before}${escapeRegExp(key)}${after}`, "giu");
};

export const applyReplacements = (text: string, replacements: Record<string, string>): string => {
  if (!text) return text;
  const keys = Object.keys(replacements)
    .filter((key) => key.trim().length > 0)
    .sort((a, b) => b.length - a.length);

  let result = text;
  for (const key of keys) {
    const value = replacements[key] ?? "";
    // Replacer function: the configured value is a literal, so "$&" or "$1"
    // must not expand as a substitution pattern.
    result = result.replace(boundedPattern(key), () => value);
  }
  return result;
};
