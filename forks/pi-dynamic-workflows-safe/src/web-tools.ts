/**
 * Real web tools for research workflows. These execute in the extension host
 * process (which has network access), not in a subagent sandbox, so they perform
 * genuine HTTP requests via Node's fetch.
 *
 * - web_search: scrapes Bing's HTML result page (https://www.bing.com/search?q=…),
 *   sent with a desktop-Chrome user-agent string because Bing serves a
 *   script-only page otherwise -> result {url, title}
 * - web_fetch:  fetch a URL and return readable text (HTML stripped, truncated)
 *
 * The URL a fetch targets is model-supplied — typically taken from a page an
 * agent just read — so both tools resolve it first and refuse targets on the
 * local machine or the local network (see WebFetchPolicy): a plain GET to
 * http://169.254.169.254/… or http://localhost:8080/?data=… is both a request
 * to something that trusted the network position and an exfiltration channel.
 * Redirects are followed one hop at a time so each new target is re-checked.
 */

import { lookup } from "node:dns/promises";
import { isIP } from "node:net";
import { defineTool, type ToolDefinition } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36";

/** Where the web tools are allowed to send requests. All fields optional. */
export interface WebFetchPolicy {
  /**
   * Allow loopback, link-local, and private-range (RFC1918/CGNAT/unique-local)
   * targets. Default false: a local address is reachable only because this
   * process runs on this machine, which is exactly the position a fetched page
   * cannot be allowed to borrow.
   */
  allowPrivateNetwork?: boolean;
  /**
   * Host names (or IP literals) exempt from the private-target block, matched
   * case-insensitively against the URL's host AND port — e.g.
   * `["localhost:3000", "[::1]:3000", "dev.internal"]`. An entry that names no
   * port matches only the scheme's default port, so opening one dev server does
   * not open every other port on the same machine. This is how intentional local
   * fetching stays possible without opening the whole private range.
   */
  allowedHosts?: string[];
  /** Redirect hops to follow, each re-checked against this policy. Default 5. */
  maxRedirects?: number;
}

const DEFAULT_MAX_REDIRECTS = 5;

const REDIRECT_STATUSES: ReadonlySet<number> = new Set([301, 302, 303, 307, 308]);

/** IPv4 CIDR blocks that are the local machine or the local network. */
const PRIVATE_V4_BLOCKS: ReadonlyArray<[string, number]> = [
  ["0.0.0.0", 8], // "this host on this network"
  ["10.0.0.0", 8],
  ["100.64.0.0", 10], // carrier-grade NAT
  ["127.0.0.0", 8],
  ["169.254.0.0", 16], // link-local, incl. the cloud metadata address
  ["172.16.0.0", 12],
  ["192.0.0.0", 24], // IETF protocol assignments
  ["192.168.0.0", 16],
  ["198.18.0.0", 15], // benchmarking
  ["224.0.0.0", 4], // multicast
  ["240.0.0.0", 4], // reserved, incl. broadcast
];

function ipv4ToInt(address: string): number | null {
  const parts = address.split(".");
  if (parts.length !== 4) return null;
  let value = 0;
  for (const part of parts) {
    if (!/^\d{1,3}$/.test(part)) return null;
    const octet = Number(part);
    if (octet > 255) return null;
    value = value * 256 + octet;
  }
  return value;
}

function isPrivateV4Value(value: number): boolean {
  return PRIVATE_V4_BLOCKS.some(([base, bits]) => {
    const baseValue = ipv4ToInt(base);
    if (baseValue === null) return false;
    const mask = bits === 0 ? 0 : (-1 << (32 - bits)) >>> 0;
    return (value & mask) === (baseValue & mask);
  });
}

/**
 * The eight 16-bit groups of an IPv6 literal, or null when it doesn't parse.
 * Expanded (rather than prefix-matched as text) because the same address has
 * many spellings — `::ffff:127.0.0.1` and `::ffff:7f00:1` are the same host,
 * and a text check for the dotted form alone would miss the hex one.
 */
function ipv6Groups(address: string): number[] | null {
  let text = address.split("%")[0];
  const dotted = text.match(/^(.*:)(\d{1,3}(?:\.\d{1,3}){3})$/);
  if (dotted) {
    const v4 = ipv4ToInt(dotted[2]);
    if (v4 === null) return null;
    text = `${dotted[1]}${((v4 >>> 16) & 0xffff).toString(16)}:${(v4 & 0xffff).toString(16)}`;
  }
  const halves = text.split("::");
  if (halves.length > 2) return null;
  const head = halves[0] ? halves[0].split(":") : [];
  const tail = halves.length === 2 && halves[1] ? halves[1].split(":") : [];
  const filler = halves.length === 2 ? Array(8 - head.length - tail.length).fill("0") : [];
  const groups = [...head, ...filler, ...tail];
  if (groups.length !== 8) return null;
  const out: number[] = [];
  for (const group of groups) {
    if (!/^[0-9a-f]{1,4}$/.test(group)) return null;
    out.push(Number.parseInt(group, 16));
  }
  return out;
}

/** Whether an IP literal names this machine or a network only this machine can see. */
export function isPrivateAddress(address: string): boolean {
  const host = address.replace(/^\[|]$/g, "").toLowerCase();
  const version = isIP(host);
  if (version === 4) {
    const value = ipv4ToInt(host);
    return value === null ? true : isPrivateV4Value(value);
  }
  if (version !== 6) return true;
  const groups = ipv6Groups(host);
  if (!groups) return true;
  // An IPv4-mapped (::ffff:a.b.c.d) or IPv4-compatible (::a.b.c.d) address
  // reaches whatever its v4 form reaches — including ::1 and :: themselves,
  // which land in 0.0.0.0/8 under this view.
  if (groups.slice(0, 5).every((group) => group === 0) && (groups[5] === 0xffff || groups[5] === 0)) {
    return isPrivateV4Value(((groups[6] << 16) | groups[7]) >>> 0);
  }
  // fe80::/10 (link-local), fc00::/7 (unique-local), ff00::/8 (multicast).
  return (groups[0] & 0xffc0) === 0xfe80 || (groups[0] & 0xfe00) === 0xfc00 || (groups[0] & 0xff00) === 0xff00;
}

/**
 * Split an allowlist entry into the host name it names and the port it pins, if
 * any: `dev.internal`, `localhost:3000`, `127.0.0.1`, `[::1]`, `[::1]:8080`.
 * A bare IPv6 literal (colons but no port) is taken whole.
 */
function parseAllowedHost(entry: string): { hostname: string; port?: string } | null {
  const candidate = entry.trim().toLowerCase();
  if (!candidate) return null;
  const bracketed = candidate.match(/^\[([^\]]+)](?::(\d{1,5}))?$/);
  if (bracketed) return { hostname: bracketed[1], port: bracketed[2] };
  const parts = candidate.split(":");
  if (parts.length === 2 && /^\d{1,5}$/.test(parts[1])) return { hostname: parts[0], port: parts[1] };
  return { hostname: candidate };
}

/**
 * Whether the policy names THIS host explicitly. Matching is structural, on the
 * URL's parsed hostname and port rather than on either string spelling of them:
 * `host` carries the port and `hostname` does not, so comparing an entry against
 * both in turn made a port-less entry ("localhost") silently exempt every port
 * on that host — the whole loopback surface from one line of config. An entry
 * pins the port when it names one and means the scheme's default port when it
 * doesn't, so each opened address is the one the user actually wrote.
 */
function hostAllowlisted(url: URL, policy: WebFetchPolicy): boolean {
  if (!policy.allowedHosts?.length) return false;
  const hostname = url.hostname.replace(/^\[|]$/g, "").toLowerCase();
  const port = url.port;
  return policy.allowedHosts.some((entry) => {
    const allowed = parseAllowedHost(entry);
    if (!allowed) return false;
    if (allowed.hostname.replace(/^\[|]$/g, "") !== hostname) return false;
    return (allowed.port ?? "") === port;
  });
}

/**
 * Resolve `target` and return it only when the policy permits fetching it:
 * http(s) scheme, a host, and — unless that exact host is allowlisted or
 * `allowPrivateNetwork` is set — every address the host resolves to is public.
 * Rejecting on ANY private answer is deliberate: a name with mixed answers must
 * not be reachable by retrying.
 *
 * The allowlist exempts a host from the private-address test and nothing else:
 * the scheme and host-shape checks below run first and are not waivable, and
 * every redirect hop is re-checked against the policy from scratch (see
 * fetchText), so an allowlisted first hop cannot vouch for where it forwards to.
 */
export async function assertUrlAllowed(target: string, policy: WebFetchPolicy = {}): Promise<URL> {
  let url: URL;
  try {
    url = new URL(target);
  } catch {
    throw new Error(`not a valid absolute URL: ${target}`);
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error(`unsupported URL scheme "${url.protocol}" (only http and https are fetched)`);
  }
  if (!url.hostname) throw new Error(`URL has no host: ${target}`);

  const exempt = policy.allowPrivateNetwork === true || hostAllowlisted(url, policy);
  const literal = url.hostname.replace(/^\[|]$/g, "");
  if (isIP(literal)) {
    if (!exempt && isPrivateAddress(literal)) throw new Error(blockedMessage(url.host));
    return url;
  }
  // A name the user named (or a wide-open policy) is taken at its word: the
  // point of the opt-in is reaching a host whose addresses are private.
  if (exempt) return url;
  let addresses: Array<{ address: string }>;
  try {
    addresses = await lookup(url.hostname, { all: true });
  } catch (error) {
    throw new Error(`could not resolve ${url.hostname}: ${error instanceof Error ? error.message : error}`);
  }
  if (!addresses.length) throw new Error(`could not resolve ${url.hostname}`);
  if (addresses.some((entry) => isPrivateAddress(entry.address))) throw new Error(blockedMessage(url.host));
  return url;
}

function blockedMessage(host: string): string {
  return (
    `refusing to fetch ${host}: it resolves to a loopback, link-local, or private-network address. ` +
    `Add "${host}" to webFetchAllowedHosts (entries match host and port exactly), or set ` +
    `webFetchAllowPrivateNetwork, in ~/.pi/workflows/settings.json to allow it.`
  );
}

/**
 * Fetch with the policy enforced on the initial URL and on every redirect hop
 * (`redirect: "manual"`, followed by hand) — a 302 to http://127.0.0.1/ would
 * otherwise sail past a check done only on the URL the caller passed.
 */
async function fetchText(
  url: string,
  timeoutMs = 15000,
  policy: WebFetchPolicy = {},
): Promise<{ status: number; body: string; url: string }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const maxRedirects = policy.maxRedirects ?? DEFAULT_MAX_REDIRECTS;
  try {
    let current = url;
    for (let hop = 0; ; hop++) {
      const resolved = await assertUrlAllowed(current, policy);
      const res = await fetch(resolved, {
        headers: { "user-agent": UA },
        signal: controller.signal,
        redirect: "manual",
      });
      const location = REDIRECT_STATUSES.has(res.status) ? res.headers.get("location") : null;
      if (!location) return { status: res.status, body: await res.text(), url: resolved.toString() };
      if (hop >= maxRedirects) throw new Error(`too many redirects (${maxRedirects}) starting at ${url}`);
      current = new URL(location, resolved).toString();
    }
  } finally {
    clearTimeout(timer);
  }
}

export function htmlToText(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<\/(p|div|li|h[1-6]|tr|br)>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/[ \t]+/g, " ")
    .replace(/\n +/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export function parseBingResults(html: string, limit: number): Array<{ url: string; title: string }> {
  const out: Array<{ url: string; title: string }> = [];
  const seen = new Set<string>();
  for (const m of html.matchAll(/<h2[^>]*>\s*<a[^>]+href="(https?:\/\/[^"]+)"[^>]*>([\s\S]*?)<\/a>/g)) {
    const url = m[1];
    if (/\.bing\.com|go\.microsoft\.com/.test(url) || seen.has(url)) continue;
    seen.add(url);
    out.push({ url, title: m[2].replace(/<[^>]+>/g, "").trim() });
    if (out.length >= limit) break;
  }
  return out;
}

/** A tool that searches the web (best-effort) and returns result URLs + titles. */
export function createWebSearchTool(policy: WebFetchPolicy = {}): ToolDefinition {
  return defineTool({
    name: "web_search",
    label: "Web Search",
    description:
      "Search the web via Bing's HTML result page and return a list of result URLs and titles. Use before web_fetch to find sources.",
    promptSnippet: "Search the web for sources",
    parameters: Type.Object({
      query: Type.String({ description: "The search query." }),
      count: Type.Optional(Type.Number({ description: "Max results (default 6)." })),
    }),
    async execute(_id, params: { query: string; count?: number }) {
      const limit = Math.min(Math.max(params.count ?? 6, 1), 10);
      try {
        const { status, body } = await fetchText(
          `https://www.bing.com/search?q=${encodeURIComponent(params.query)}`,
          undefined,
          policy,
        );
        const results = parseBingResults(body, limit);
        const text = results.length
          ? results.map((r, i) => `${i + 1}. ${r.title}\n   ${r.url}`).join("\n")
          : `No results parsed (HTTP ${status}). Try a different query or fetch a known URL directly.`;
        return { content: [{ type: "text", text }], details: { results } };
      } catch (error) {
        return {
          content: [{ type: "text", text: `web_search failed: ${error instanceof Error ? error.message : error}` }],
          details: { results: [] as Array<{ url: string; title: string }> },
        };
      }
    },
  }) as unknown as ToolDefinition;
}

/** A tool that fetches a URL and returns readable text. */
export function createWebFetchTool(maxChars = 6000, policy: WebFetchPolicy = {}): ToolDefinition {
  return defineTool({
    name: "web_fetch",
    label: "Web Fetch",
    description:
      "Fetch a public http(s) URL and return its readable text content (HTML stripped, truncated). Loopback and private-network addresses are refused unless allowlisted in settings.",
    promptSnippet: "Fetch a URL's text",
    parameters: Type.Object({
      url: Type.String({ description: "The absolute URL to fetch." }),
    }),
    async execute(_id, params: { url: string }) {
      try {
        const { status, body } = await fetchText(params.url, undefined, policy);
        const text = htmlToText(body).slice(0, maxChars);
        return {
          content: [{ type: "text", text: `HTTP ${status} ${params.url}\n\n${text}` }],
          details: { status, url: params.url },
        };
      } catch (error) {
        return {
          content: [
            {
              type: "text",
              text: `web_fetch failed for ${params.url}: ${error instanceof Error ? error.message : error}`,
            },
          ],
          details: { status: 0, url: params.url },
        };
      }
    },
  }) as unknown as ToolDefinition;
}

/** Both web tools, for injecting into a research workflow's agents. */
export function createWebTools(policy: WebFetchPolicy = {}): ToolDefinition[] {
  return [createWebSearchTool(policy), createWebFetchTool(undefined, policy)];
}
