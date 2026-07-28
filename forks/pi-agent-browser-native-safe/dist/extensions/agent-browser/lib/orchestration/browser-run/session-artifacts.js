export function getPersistentSessionArtifactStore(ctx) {
    const sessionDir = typeof ctx.sessionManager.getSessionDir === "function" ? ctx.sessionManager.getSessionDir() : undefined;
    const sessionId = ctx.sessionManager.getSessionId();
    return sessionDir && sessionId ? { sessionDir, sessionId } : undefined;
}
