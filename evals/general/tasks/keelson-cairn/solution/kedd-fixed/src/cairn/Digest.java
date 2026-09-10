package cairn;

import java.security.MessageDigest;

/**
 * SHA-256 hex helpers (pure JDK, no third-party code).
 *
 * The kedd journal line format is
 *
 *     <ordinal>|<payload>|<digest>
 *
 * where <digest> is the first 16 hex characters of the SHA-256 (lowercase,
 * hex-encoded) of the UTF-8 bytes of
 *
 *     <ordinal>:<payload>:<width>
 *
 * so any reader can recompute an entry's digest from its event alone.
 */
public final class Digest {

    private Digest() {
    }

    /** Full 64-char lowercase sha-256 hex digest of the UTF-8 bytes. */
    public static String sha256Hex(String input) {
        MessageDigest md = Digest.sha256(input);
        StringBuilder sb = new StringBuilder(64);
        for (byte b : md.digest()) {
            sb.append("0123456789abcdef".charAt((b >> 4) & 0x0F));
            sb.append("0123456789abcdef".charAt(b & 0x0F));
        }
        return sb.toString();
    }

    /** Journal digest: first 16 hex chars of the sha-256 of the input. */
    public static String shortHex(String input) {
        return sha256Hex(input).substring(0, 16);
    }

    private static MessageDigest sha256(String input) {
        MessageDigest md;
        try {
            md = MessageDigest.getInstance("SHA-256");
        } catch (java.security.NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("JVM without SHA-256", impossible);
        }
        md.update(input.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        return md;
    }
}