import { AsyncLocalStorage } from "node:async_hooks";
const isolatedAgentBrowserEnvironment = new AsyncLocalStorage();
const PROXY_ENV_NAMES = new Set(["ALL_PROXY", "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY"]);
export function getAgentBrowserProcessEnvironment(baseEnv = process.env) {
    if (isolatedAgentBrowserEnvironment.getStore() !== true)
        return baseEnv;
    return Object.fromEntries(Object.entries(baseEnv).filter(([name]) => {
        const normalizedName = name.toUpperCase();
        return !normalizedName.startsWith("AGENT_BROWSER_") && !PROXY_ENV_NAMES.has(normalizedName);
    }));
}
export function withIsolatedAgentBrowserEnvironment(run) {
    return isolatedAgentBrowserEnvironment.run(true, run);
}
