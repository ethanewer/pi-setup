package io.netty.handler.codec.compression;

import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;
import io.netty.channel.embedded.EmbeddedChannel;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Hidden case C for kelson-current: TWO concatenated gzip members where the
 * FIRST member has both an FEXTRA extra field and an FNAME file name, and the
 * SECOND member is a plain gzip stream (no extra field). The decoder must
 * reset its extra-field state between members: a first-member extra field
 * must not leak its length into the second member's header parsing, and the
 * FNAME skip must run cleanly after the extra field.
 */
public class HiddenFextraCaseConcatMixed {

    private static final byte[] FIRST = (
            "hidden case C first member: 12-byte FEXTRA extra field plus an FNAME field. "
          + "This member must decode intact.").getBytes(java.nio.charset.StandardCharsets.US_ASCII);

    private static final byte[] SECOND = (
            "hidden case C second member: a plain gzip stream with no extra field, "
          + "which must not be corrupted by the first member's extra-field state. "
          + "0123456789 0123456789 0123456789 0123456789").getBytes(java.nio.charset.StandardCharsets.US_ASCII);

    private static final byte[] EXTRA = {
        0x42, 0x47,                                  // subfield SI1 SI2
        0x08, 0x00,                                  // subfield length, little-endian: 8
        0x00, 0x00, 0x00, 0x00, 0x66, 0x69, 0x7A, 0x69
    };

    @Test
    public void testConcatenatedFirstMemberExtraFieldPlusName() throws Exception {
        byte[] firstGz = gzipWithExtraFieldAndName(FIRST, EXTRA, "hcasec.bin");
        byte[] secondGz = gzip(SECOND);
        byte[] both = new byte[firstGz.length + secondGz.length];
        System.arraycopy(firstGz, 0, both, 0, firstGz.length);
        System.arraycopy(secondGz, 0, both, firstGz.length, secondGz.length);

        // sanity: both members together are valid gzip per the JDK reader
        byte[] expected = new byte[FIRST.length + SECOND.length];
        System.arraycopy(FIRST, 0, expected, 0, FIRST.length);
        System.arraycopy(SECOND, 0, expected, FIRST.length, SECOND.length);
        assertArrayEquals(expected, jdkGunzip(both));

        EmbeddedChannel ch = new EmbeddedChannel(new JdkZlibDecoder(true, 0));
        try {
            assertTrue(ch.writeInbound(Unpooled.copiedBuffer(both)));
            assertArrayEquals(expected, drain(ch));
        } finally {
            assertFalse(ch.finish());
            ch.close();
        }
    }

    private static byte[] drain(EmbeddedChannel ch) throws IOException {
        ByteArrayOutputStream decoded = new ByteArrayOutputStream();
        ByteBuf msg;
        while ((msg = ch.readInbound()) != null) {
            msg.readBytes(decoded, msg.readableBytes());
            msg.release();
        }
        return decoded.toByteArray();
    }

    private static byte[] gzip(byte[] data) throws IOException {
        ByteArrayOutputStream bytesOut = new ByteArrayOutputStream();
        GZIPOutputStream gzipOut = new GZIPOutputStream(bytesOut);
        gzipOut.write(data);
        gzipOut.close();
        return bytesOut.toByteArray();
    }

    /** Gzip stream whose header has FLG.FEXTRA (with the given extra bytes) AND a null-terminated FNAME. */
    private static byte[] gzipWithExtraFieldAndName(byte[] data, byte[] extra, String name) throws IOException {
        byte[] standard = gzip(data);
        ByteArrayOutputStream mod = new ByteArrayOutputStream();
        byte[] header = java.util.Arrays.copyOfRange(standard, 0, 10);
        header[3] |= 0x04 | 0x08; // FLG.FEXTRA | FLG.FNAME
        mod.write(header);
        mod.write(extra.length & 0xff);
        mod.write((extra.length >>> 8) & 0xff);
        mod.write(extra);
        byte[] nameBytes = name.getBytes(java.nio.charset.StandardCharsets.US_ASCII);
        mod.write(nameBytes);
        mod.write(0x00);
        mod.write(standard, 10, standard.length - 10);
        return mod.toByteArray();
    }

    private static byte[] jdkGunzip(byte[] gz) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        GZIPInputStream in = new GZIPInputStream(new ByteArrayInputStream(gz));
        byte[] buf = new byte[256];
        int n;
        while ((n = in.read(buf)) != -1) {
            out.write(buf, 0, n);
        }
        in.close();
        return out.toByteArray();
    }
}