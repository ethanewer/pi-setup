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
import { type ToolDefinition } from "@earendil-works/pi-coding-agent";
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
/** Whether an IP literal names this machine or a network only this machine can see. */
export declare function isPrivateAddress(address: string): boolean;
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
export declare function assertUrlAllowed(target: string, policy?: WebFetchPolicy): Promise<URL>;
export declare function htmlToText(html: string): string;
export declare function parseBingResults(html: string, limit: number): Array<{
    url: string;
    title: string;
}>;
/** A tool that searches the web (best-effort) and returns result URLs + titles. */
export declare function createWebSearchTool(policy?: WebFetchPolicy): ToolDefinition;
/** A tool that fetches a URL and returns readable text. */
export declare function createWebFetchTool(maxChars?: number, policy?: WebFetchPolicy): ToolDefinition;
/** Both web tools, for injecting into a research workflow's agents. */
export declare function createWebTools(policy?: WebFetchPolicy): ToolDefinition[];
