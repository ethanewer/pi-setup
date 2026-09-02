package com.lattice;

/**
 * Name resolver for the Lattice "jar-dock" upload service.
 *
 * <p>Clients POST a .jar build plus a client-supplied file name; this resolver
 * decides the on-disk name stored inside the upload dock. Today it is
 * deliberately vulnerable so the hosted evidence can be demonstrated.
 */
public final class JaxUpload {

    /** Fallback base name used when nothing usable survives sanitization. */
    public static final String FALLBACK = "upload.jar";

    private JaxUpload() {
        // utility class
    }

    /**
     * Resolve a client-supplied filename to the safe on-disk base name.
     *
     * <p>BUG (do not ship): currently returns the raw client value verbatim,
     * so a hostile upload can smuggle '/' / '\' (or %2F / %5C) path components
     * and '../' parent-dir traversal and read/write anywhere on the host.
     *
     * @param raw the raw client-supplied filename (may be {@code null})
     * @return the safe, path-free base name
     */
    public static String resolve(String raw) {
        if (raw == null) {
            return FALLBACK;
        }
        // VULNERABLE: no sanitization at all.
        return raw;
    }
}
