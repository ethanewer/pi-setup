import { textFrom } from "../utils/coerce";

/**
 * Octets of a dotted-quad IPv4 literal in the one canonical form a URL hostname
 * keeps: four decimal octets, no `inet_aton` shorthand and no leading zeros, so
 * `127.1` or `0177.0.0.1` are not read as loopback by this predicate.
 */
const ipv4Octets = (literal: string): number[] | null => {
  const parts = literal.split(".");
  if (parts.length !== 4) return null;

  const octets: number[] = [];
  for (const part of parts) {
    if (!/^\d{1,3}$/.test(part)) return null;
    if (part.length > 1 && part.startsWith("0")) return null;
    const octet = Number(part);
    if (octet > 255) return null;
    octets.push(octet);
  }
  return octets;
};

/**
 * The eight 16-bit groups of an IPv6 literal, so every spelling of one address
 * compares equal: `::1`, `0:0:0:0:0:0:0:1` and `::ffff:127.0.0.1` all expand
 * here instead of being matched as text.
 */
const ipv6Groups = (literal: string): number[] | null => {
  const halves = literal.split("::");
  if (halves.length > 2) return null;

  const groupsFrom = (half: string): number[] | null => {
    if (!half) return [];
    const parts = half.split(":");
    const groups: number[] = [];
    for (const [index, part] of parts.entries()) {
      if (index === parts.length - 1 && part.includes(".")) {
        const octets = ipv4Octets(part);
        if (!octets) return null;
        groups.push((octets[0] << 8) | octets[1], (octets[2] << 8) | octets[3]);
        continue;
      }
      if (!/^[0-9a-f]{1,4}$/.test(part)) return null;
      groups.push(Number.parseInt(part, 16));
    }
    return groups;
  };

  const head = groupsFrom(halves[0]);
  const tail = halves.length === 2 ? groupsFrom(halves[1]) : [];
  if (!head || !tail) return null;

  if (halves.length === 1) return head.length === 8 ? head : null;
  // "::" has to stand for at least one omitted zero group.
  if (head.length + tail.length > 7) return null;
  return [...head, ...Array(8 - head.length - tail.length).fill(0), ...tail];
};

/** `::1` in any spelling, or an IPv4-mapped address inside 127.0.0.0/8. */
const isLoopbackIpv6 = (literal: string): boolean => {
  const groups = ipv6Groups(literal);
  if (!groups || groups.slice(0, 5).some(Boolean)) return false;
  if (groups[5] === 0xffff) return groups[6] >>> 8 === 127;
  return groups[5] === 0 && groups[6] === 0 && groups[7] === 1;
};

/**
 * Whether a hostname names this machine and nothing else: the whole loopback
 * space — `localhost` (with or without the fully qualified trailing dot), any
 * 127.0.0.0/8 literal, `::1`, and IPv4-mapped loopback — and nothing outside
 * it. Names that merely start with one of those labels (`localhost.evil.com`,
 * `127.0.0.1.evil.com`) resolve wherever their owner points them, so they are
 * not loopback; neither is `0.0.0.0`, which is a wildcard rather than a
 * destination.
 */
export const isLoopbackHostname = (hostname: string): boolean => {
  const host = hostname.trim().toLowerCase();
  if (host.startsWith("[") && host.endsWith("]")) return isLoopbackIpv6(host.slice(1, -1));
  if (host.includes(":")) return isLoopbackIpv6(host);

  const name = host.endsWith(".") ? host.slice(0, -1) : host;
  if (name === "localhost") return true;

  const octets = ipv4Octets(name);
  return octets !== null && octets[0] === 127;
};

/**
 * Whether an endpoint stays on this machine, whatever its scheme. A loopback
 * host cannot hand a credential to a third party, so it never needs one
 * defaulted for it — endpointRequiresAuth is stricter on purpose, since it also
 * decides whether an already configured key is sent as a header.
 */
export const isLoopbackEndpoint = (endpoint: string): boolean => {
  try {
    return isLoopbackHostname(new URL(endpoint).hostname.toLowerCase());
  } catch {
    return false;
  }
};

/**
 * Domain each named vendor alias is pinned to. A named alias injects that
 * vendor's API key, so its endpoint may not be redirected to a third-party
 * host: arbitrary hosts belong to `openai-compatible` / `local`. Extra hosts
 * (vendor-protocol gateways, proxies) can be allowed through the
 * PI_STT_ALLOWED_ENDPOINT_HOSTS environment variable, which lives outside the
 * config file on purpose.
 */
export const VENDOR_ENDPOINT_DOMAINS: Record<string, string> = {
  openai: "openai.com",
  groq: "groq.com",
  mistral: "mistral.ai",
  deepgram: "deepgram.com",
  elevenlabs: "elevenlabs.io",
  gladia: "gladia.io",
  assemblyai: "assemblyai.com",
};

const allowedEndpointHosts = (): string[] =>
  textFrom(process.env.PI_STT_ALLOWED_ENDPOINT_HOSTS)
    .split(",")
    .map((host) => host.trim().toLowerCase())
    .filter(Boolean);

const matchesDomain = (hostname: string, domain: string): boolean => hostname === domain || hostname.endsWith(`.${domain}`);

/** Endpoints reach user-visible toasts, so any userinfo is masked first. */
const redactEndpoint = (endpoint: string): string => endpoint.replace(/^([a-z][a-z0-9+.-]*:\/\/)[^/?#]*@/i, "$1***@");

/**
 * Whether an already validated endpoint belongs to a named vendor, so a
 * vendor-specific default (e.g. the OpenAI key) may be applied to it. Hosts
 * listed in PI_STT_ALLOWED_ENDPOINT_HOSTS count as that vendor too, matching
 * how secureEndpointFrom treats them.
 */
export const isVendorEndpoint = (endpoint: string, vendor: string): boolean => {
  const domain = VENDOR_ENDPOINT_DOMAINS[vendor] ?? "";
  if (!domain) return false;

  let hostname: string;
  try {
    hostname = new URL(endpoint).hostname.toLowerCase();
  } catch {
    return false;
  }

  return matchesDomain(hostname, domain) || allowedEndpointHosts().includes(hostname);
};

/**
 * Registrable domain of a hostname, approximated as its last two labels
 * because no public suffix list is available here. Bare IP literals have none,
 * so they only ever match themselves.
 */
const registrableDomain = (hostname: string): string => {
  if (hostname.includes(":") || /^[\d.]+$/.test(hostname)) return "";
  const labels = hostname.split(".");
  if (labels.length < 2 || labels.some((label) => !label)) return "";
  return labels.slice(-2).join(".");
};

/**
 * Whether a URL taken from a provider response may be followed with the API key
 * attached: the same origin as a configured endpoint, or an HTTPS host in the
 * same registrable domain (regional API hosts such as eu.api.<vendor>).
 * Anything else — another domain, a bare IP, plain HTTP off loopback — is not.
 */
export const isSameSiteEndpoint = (endpoint: string, configuredEndpoints: string[]): boolean => {
  let url: URL;
  try {
    url = new URL(endpoint);
  } catch {
    return false;
  }

  const hostname = url.hostname.toLowerCase();
  const domain = registrableDomain(hostname);

  return configuredEndpoints.some((configured) => {
    let configuredUrl: URL;
    try {
      configuredUrl = new URL(configured);
    } catch {
      return false;
    }

    if (url.origin === configuredUrl.origin) return true;
    if (url.protocol !== "https:") return false;

    const configuredHost = configuredUrl.hostname.toLowerCase();
    if (hostname === configuredHost) return true;
    return Boolean(domain) && domain === registrableDomain(configuredHost);
  });
};

export const secureEndpointFrom = (value: unknown, fallback: string, vendor = ""): string => {
  const endpoint = textFrom(value, fallback);

  let url: URL;
  try {
    url = new URL(endpoint);
  } catch {
    throw new Error(`Invalid STT endpoint: ${redactEndpoint(endpoint)}`);
  }

  if (url.username || url.password) {
    throw new Error("STT endpoint must not include credentials. Use apiKeyEnv or Keychain instead.");
  }

  if (url.protocol !== "https:" && !(url.protocol === "http:" && isLoopbackHostname(url.hostname))) {
    throw new Error(
      `STT endpoint must use HTTPS unless it points at this machine, got ${redactEndpoint(endpoint)}. ` +
        `Plain http is accepted for loopback only: localhost, any 127.0.0.0/8 address, or ::1.`,
    );
  }

  const domain = vendor ? VENDOR_ENDPOINT_DOMAINS[vendor] ?? "" : "";
  const hostname = url.hostname.toLowerCase();
  if (domain && !matchesDomain(hostname, domain) && !allowedEndpointHosts().includes(hostname)) {
    throw new Error(
      `STT provider "${vendor}" only accepts endpoints on ${domain}, got ${hostname}. ` +
        `Use provider.type "openai-compatible" (or "local") for a custom host, ` +
        `or list the host in PI_STT_ALLOWED_ENDPOINT_HOSTS.`,
    );
  }

  return endpoint;
};

export const endpointRequiresAuth = (endpoint: string): boolean => {
  const url = new URL(endpoint);
  return !(url.protocol === "http:" && isLoopbackHostname(url.hostname));
};
