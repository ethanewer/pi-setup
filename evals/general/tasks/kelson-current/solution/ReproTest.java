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
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Authored reproduction for the kelson-current task: a valid gzip stream that
 * carries an FEXTRA extra field in its header (as BGZF and other tools emit)
 * must decompress to exactly the original bytes through the gzip codec, and
 * must decompress identically with the JDK's own gzip reader.
 *
 * On the pre-fix tree this test FAILS (DecompressionException, nothing
 * emitted); on a fixed tree it passes.
 */
public class ReproTest {

    private static final byte[] PAYLOAD = (
            "repro: gzip with an FEXTRA extra header field must decode to the exact original bytes. "
          + "The same stream decodes cleanly with the JDK GZIPInputStream, so the codec is at fault. "
          + "0123456789012345678901234567890123456789").getBytes(java.nio.charset.StandardCharsets.US_ASCII);

    private static final byte[] EXTRA = {
        0x42, 0x43,          // subfield SI1 SI2 (BGZF-style "BC" subfield id)
        0x04, 0x00,          // subfield length, little-endian: 4
        0x01, 0x00, 0x00, 0x00
    };

    @Test
    public void testGzipWithFextraExtraFieldDecodes() throws Exception {
        byte[] gz = gzipWithExtraField(PAYLOAD, EXTRA);

        // Sanity-check the crafted stream with the JDK's own gzip reader.
        assertArrayEquals(PAYLOAD, jdkGunzip(gz));

        // Netty's gzip decoder must produce the identical bytes. Before the
        // fix the extra field was never skipped and the inflater saw garbage.
        EmbeddedChannel ch = new EmbeddedChannel(new JdkZlibDecoder(true, 0));
        try {
            assertTrue(ch.writeInbound(Unpooled.copiedBuffer(gz)));
            ByteBuf msg = ch.readInbound();
            assertTrue(msg != null, "no inbound message; decoder failed or emitted nothing");
            ByteArrayOutputStream decoded = new ByteArrayOutputStream();
            while (msg != null) {
                msg.readBytes(decoded, msg.readableBytes());
                msg.release();
                msg = ch.readInbound();
            }
            assertArrayEquals(PAYLOAD, decoded.toByteArray());
            decoded.close();
        } finally {
            ch.finish();
            ch.close();
        }
    }

    private static byte[] gzip(byte[] data) throws IOException {
        ByteArrayOutputStream bytesOut = new ByteArrayOutputStream();
        GZIPOutputStream gzipOut = new GZIPOutputStream(bytesOut);
        gzipOut.write(data);
        gzipOut.close();
        return bytesOut.toByteArray();
    }

    /** Build a gzip stream whose header carries an FEXTRA extra field of xlen == extra.length bytes. */
    private static byte[] gzipWithExtraField(byte[] data, byte[] extra) throws IOException {
        byte[] standard = gzip(data);
        ByteArrayOutputStream withExtra = new ByteArrayOutputStream();
        byte[] header = java.util.Arrays.copyOfRange(standard, 0, 10);
        header[3] |= 0x04; // FLG.FEXTRA
        withExtra.write(header);
        withExtra.write(extra.length & 0xff);          // XLEN low byte, little-endian
        withExtra.write((extra.length >>> 8) & 0xff);  // XLEN high byte
        withExtra.write(extra);
        withExtra.write(standard, 10, standard.length - 10);
        return withExtra.toByteArray();
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