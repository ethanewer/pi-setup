/**
 * Purpose: Keep wrapper-side navigation policy parsing and evaluation small and explicit.
 * Responsibilities: Parse allowed-domain argv values, resolve the resource roots of a wrapper-launched Electron app, and detect final-page host and scheme escapes.
 * Scope: Wrapper diagnostics only; upstream remains responsible for browser-time enforcement.
 * Invariants/Assumptions: A `*.host` entry authorizes subdomains only, and any observed URL that is neither an allowlisted http(s) host, a no-page placeholder, an Electron app-local scheme, nor a `file:` URL inside the resource root of the app this wrapper launched is an escape.
 */
import { existsSync } from "node:fs";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { resolveRealWritePath } from "./write-path-policy.js";
/** Placeholder pages that carry no navigated content, so they can never be an allowlist escape. */
const NO_PAGE_URL_PATTERN = /^(?:about:(?:blank|newtab)(?:[?#][\s\S]*)?|chrome:\/\/(?:newtab|new-tab-page)\/?|edge:\/\/newtab\/?|chrome-error:\/\/[\s\S]*)$/i;
export const ELECTRON_APP_URL_SCHEMES_ENV = "PI_AGENT_BROWSER_ELECTRON_APP_URL_SCHEMES";
/** Schemes an Electron target renders for its own UI, none of which can address an arbitrary host path. */
export const ELECTRON_APP_URL_SCHEMES = ["app:", "chrome-extension:", "devtools:", "electron:"];
/**
 * `file:` names any file on the host, so no scheme-level opt-in can ever exempt it; it is exempted only by resolving
 * inside the resource root of the Electron app this wrapper launched.
 */
const NEVER_EXEMPT_URL_SCHEMES = ["file:", "filesystem:", "http:", "https:"];
const LOCAL_FILE_URL_SCHEME = "file:";
const MAC_APP_BUNDLE_SUFFIX = ".app";
function normalizeUrlScheme(value) {
    const normalized = value.trim().toLowerCase().replace(/:.*$/, "");
    return normalized.length > 0 ? `${normalized}:` : undefined;
}
/**
 * @param {string} scheme
 * @param {NodeJS.ProcessEnv} [env]
 */
export function isElectronAppUrlScheme(scheme, env = process.env) {
    const normalized = normalizeUrlScheme(scheme);
    if (normalized === undefined || NEVER_EXEMPT_URL_SCHEMES.includes(normalized))
        return false;
    if (ELECTRON_APP_URL_SCHEMES.includes(normalized))
        return true;
    return (env[ELECTRON_APP_URL_SCHEMES_ENV] ?? "")
        .split(/[,\s]+/)
        .flatMap((entry) => {
        const configured = normalizeUrlScheme(entry);
        return configured ? [configured] : [];
    })
        .includes(normalized);
}
function pathIsWithin(path, parent) {
    const relativePath = relative(parent, path);
    return relativePath.length === 0 || (!relativePath.startsWith("..") && !isAbsolute(relativePath));
}
/** macOS packaged apps keep their UI under `Contents/Resources`, so the bundle directory is the resource root. */
function getAppBundleRoot(path) {
    let candidate = resolve(path);
    for (;;) {
        if (basename(candidate).toLowerCase().endsWith(MAC_APP_BUNDLE_SUFFIX))
            return candidate;
        const parent = dirname(candidate);
        if (parent === candidate)
            return undefined;
        candidate = parent;
    }
}
/** The payload layouts `hasLinuxElectronEvidence` accepts, so the exemption root is derived from the same evidence that identified the app. */
const ELECTRON_RESOURCE_PAYLOAD_RELATIVE_PATHS = [["resources", "app.asar"], ["resources", "app"]];
function hasElectronResourcePayload(directory) {
    return ELECTRON_RESOURCE_PAYLOAD_RELATIVE_PATHS.some((segments) => existsSync(join(directory, ...segments)));
}
/**
 * A packaged Linux app keeps `resources/` beside its executable or one level above it, and launch evidence accepts
 * both, so the directory that actually holds the payload is the resource root. The narrower directory wins and no
 * further ancestor is considered, so the exemption never grows past the launched app's own resource root.
 * @param {string} executableDirectory
 */
function getElectronResourceRoot(executableDirectory) {
    if (hasElectronResourcePayload(executableDirectory))
        return executableDirectory;
    const parent = dirname(executableDirectory);
    return parent !== executableDirectory && hasElectronResourcePayload(parent) ? parent : undefined;
}
/**
 * The resource root of an Electron app this wrapper launched: the application bundle when one is known, otherwise the
 * directory holding the app's `resources/` payload, and the directory holding the launched executable when neither is
 * identifiable. A filesystem root is never returned, so an unusual executable location cannot exempt the whole disk.
 * @param {{ appPath?: string; executablePath?: string } | undefined} launch
 * @returns {string[]}
 */
export function getLocalAppFileRootsForLaunch(launch) {
    const roots = [];
    const appPath = launch?.appPath?.trim();
    if (appPath)
        roots.push(resolve(appPath));
    const executablePath = launch?.executablePath?.trim();
    if (executablePath) {
        const executableDirectory = dirname(resolve(executablePath));
        roots.push(getAppBundleRoot(executableDirectory) ?? getElectronResourceRoot(executableDirectory) ?? executableDirectory);
    }
    return [...new Set(roots)].filter((root) => dirname(root) !== root);
}
function normalizeLocalAppFileRoots(roots) {
    return [...new Set((roots ?? []).flatMap((root) => (typeof root === "string" && root.trim().length > 0 ? [resolve(root.trim())] : [])))]
        .filter((root) => dirname(root) !== root);
}
/**
 * A packaged Electron app loads its own UI with `loadFile()`, so the observed URL is `file://.../index.html` under
 * the app's resource root. Only that root is exempt, and containment is decided on real paths so a `..` segment or a
 * symlink inside the bundle cannot reach `/etc/passwd`, `~/.aws/credentials`, or `~/.ssh`. When no resource root is
 * known for the launch, nothing is exempt.
 * @param {string} url
 * @param {readonly string[] | undefined} localAppFileRoots
 */
export function isLocalAppFileUrl(url, localAppFileRoots) {
    const roots = normalizeLocalAppFileRoots(localAppFileRoots);
    if (roots.length === 0)
        return false;
    let filePath;
    try {
        filePath = fileURLToPath(url);
    }
    catch {
        return false;
    }
    const realFilePath = resolveRealWritePath(resolve(filePath));
    return roots.some((root) => pathIsWithin(realFilePath, resolveRealWritePath(root)));
}
function normalizeDomainEntry(value) {
    let candidate = value.trim().toLowerCase();
    if (!candidate)
        return undefined;
    const subdomainsOnly = candidate.startsWith("*.");
    if (subdomainsOnly)
        candidate = candidate.slice(2);
    try {
        if (/^[a-z][a-z0-9+.-]*:\/\//i.test(candidate)) {
            candidate = new URL(candidate).hostname;
        }
    }
    catch {
        return undefined;
    }
    candidate = candidate.replace(/\.$/, "");
    if (candidate.includes("/"))
        candidate = candidate.split("/")[0] ?? "";
    if (candidate.includes(":"))
        candidate = candidate.split(":")[0] ?? "";
    if (candidate.length === 0)
        return undefined;
    return subdomainsOnly ? `*.${candidate}` : candidate;
}
function splitAllowedDomainsValue(value) {
    return value.split(/[,\s]+/).map((entry) => entry.trim()).filter(Boolean);
}
export function parseAllowedDomainsPolicyFromArgs(args) {
    const domains = [];
    for (let index = 0; index < args.length; index += 1) {
        const arg = args[index];
        if (arg === "--allowed-domains") {
            const value = args[index + 1];
            if (value && !value.startsWith("-")) {
                domains.push(...splitAllowedDomainsValue(value));
                index += 1;
            }
            continue;
        }
        if (arg?.startsWith("--allowed-domains=")) {
            domains.push(...splitAllowedDomainsValue(arg.slice("--allowed-domains=".length)));
        }
    }
    const allowedDomains = [...new Set(domains.flatMap((domain) => {
            const normalized = normalizeDomainEntry(domain);
            return normalized ? [normalized] : [];
        }))];
    if (allowedDomains.length === 0)
        return undefined;
    return { allowedDomains, display: allowedDomains.join(", ") };
}
function classifyObservedUrl(url) {
    const trimmed = url.trim();
    if (trimmed.length === 0 || NO_PAGE_URL_PATTERN.test(trimmed))
        return { noPage: true };
    let parsed;
    try {
        parsed = new URL(trimmed);
    }
    catch {
        return {};
    }
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:")
        return { scheme: parsed.protocol };
    return { host: parsed.hostname.toLowerCase().replace(/\.$/, "") };
}
export function isHostAllowedByDomains(host, allowedDomains) {
    const normalizedHost = host.toLowerCase().replace(/\.$/, "");
    return allowedDomains.some((domain) => domain.startsWith("*.")
        ? normalizedHost.endsWith(domain.slice(1))
        : normalizedHost === domain || normalizedHost.endsWith(`.${domain}`));
}
export function getAllowedDomainsViolation(options) {
    if (!options.policy || !options.url)
        return undefined;
    const observed = classifyObservedUrl(options.url);
    if (observed.noPage)
        return undefined;
    // Electron targets legitimately render their own app UI schemes; every other non-http(s) URL stays policed.
    if (observed.scheme !== undefined && options.allowLocalAppUrls) {
        if (isElectronAppUrlScheme(observed.scheme))
            return undefined;
        // Packaged Electron apps load their UI with `loadFile()`, so a `file:` URL inside the launched app's own
        // resource root is app UI rather than an allowlist escape; any other `file:` URL stays a violation.
        if (observed.scheme === LOCAL_FILE_URL_SCHEME && isLocalAppFileUrl(options.url, options.localAppFileRoots))
            return undefined;
    }
    if (observed.host !== undefined && isHostAllowedByDomains(observed.host, options.policy.allowedDomains))
        return undefined;
    const observedHost = observed.host ?? observed.scheme ?? "an unparsable URL";
    const localAppFileRoots = normalizeLocalAppFileRoots(options.localAppFileRoots);
    const appSchemeHint = !options.allowLocalAppUrls || observed.scheme === undefined
        ? ""
        : observed.scheme === LOCAL_FILE_URL_SCHEME
            ? ` A file: URL is exempt only when it resolves inside the resource root of the Electron app this wrapper launched${localAppFileRoots.length > 0 ? ` (${localAppFileRoots.join(", ")})` : ", and no resource root is known for this launch"}.`
            : NEVER_EXEMPT_URL_SCHEMES.includes(observed.scheme)
                ? ""
                : ` An Electron app scheme is exempt only when it is listed in ${ELECTRON_APP_URL_SCHEMES_ENV}.`;
    const summary = observed.host !== undefined
        ? `Navigation policy blocked: --allowed-domains ${options.policy.display} does not allow ${observedHost} (${options.url}).`
        : `Navigation policy blocked: --allowed-domains ${options.policy.display} allows http(s) hosts only, but the page ended on ${observedHost} (${options.url}).${appSchemeHint}`;
    return {
        allowedDomains: options.policy.allowedDomains,
        allowedDisplay: options.policy.display,
        observedHost,
        observedUrl: options.url,
        summary,
    };
}
