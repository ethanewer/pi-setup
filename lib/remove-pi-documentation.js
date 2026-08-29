const SECTION_START = "\n\nPi documentation (read only when the user asks about pi itself, its SDK, extensions, themes, skills, or TUI):";
const SECTION_END = "\n- Always read pi .md files completely and follow links to related docs (e.g., tui.md for TUI API details)";
export default function (pi) {
  pi.on("before_agent_start", (event) => {
    const start = event.systemPrompt.indexOf(SECTION_START);
    if (start === -1) return;
    const marker = event.systemPrompt.indexOf(SECTION_END, start);
    if (marker === -1) return;
    const end = marker + SECTION_END.length;
    return { systemPrompt: event.systemPrompt.slice(0, start) + event.systemPrompt.slice(end) };
  });
}
