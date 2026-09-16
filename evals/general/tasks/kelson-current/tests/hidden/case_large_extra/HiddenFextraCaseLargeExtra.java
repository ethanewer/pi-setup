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
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Hidden case A for kelson-current: an FEXTRA extra field whose total length
 * (300 bytes) has a NONZERO high byte in the little-endian XLEN, so the
 * correct handling must read the length byte-order-sensitively and skip all
 * 300 bytes. The extra field content is a canonical subfield (SI1=0x41,
 * SI2=0x45, LEN=296) followed by 296 bytes of patterned data that includes
 * 0x00 runs, gzip magic bytes and high-entropy bytes, embedded on purpose so
 * any mis-skip lands the inflater in visibly wrong state.
 */
public class HiddenFextraCaseLargeExtra {

    private static final byte[] PAYLOAD = (
            "hidden case A: 300-byte FEXTRA extra field with nonzero high XLEN byte. "
          + "Every character below is deliberate ASCII payload that must round-trip byte for byte. "
          + "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 !@#$%^&*()"
          + "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 !@#$%^&*()"
          + "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 !@#$%^&*()"
          + "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 !@#$%^&*()"
          + "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 !@#$%^&*()"
          + "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 !@#$%^&*()"
          + "end of hidden case A payload.").getBytes(java.nio.charset.StandardCharsets.US_ASCII);

    private static byte[] extra() {
        byte[] extra = new byte[300];
        extra[0] = 0x41;  // SI1
        extra[1] = 0x45;  // SI2
        extra[2] = 0x28;  // subfield LEN low byte (296 = 0x0128, little-endian)
        extra[3] = 0x01;  // subfield LEN high byte
        java.util.Arrays.fill(extra, 4, extra.length, (byte) 0xA5);
        // sprinkle suspicious bytes: deflate-ish headers, gzip magic, NULs, run markers
        for (int i = 4; i < extra.length; i += 37) {
            extra[i] = (byte) 0x1F;
            extra[i + 1 < extra.length ? i + 1 : i] = (byte) 0x8B;
            extra[(i + 2) % extra.length] = 0x00;
            extra[(i + 3) % extra.length] = (byte) (i & 0xFF);
            extra[(i + 5) % extra.length] = (byte) 0xFF;
        }
        return extra;
    }

    @Test
    public void testLargeExtraFieldNonzeroHighXlenByte() throws Exception {
        byte[] extra = extra();
        assertEquals(300, extra.length);
        byte[] gz = gzipWithExtraField(PAYLOAD, extra);

        // sanity: the crafted stream is valid gzip per the JDK reader
        assertArrayEquals(PAYLOAD, jdkGunzip(gz));

        EmbeddedChannel ch = new EmbeddedChannel(new JdkZlibDecoder(true, 0));
        try {
            assertTrue(ch.writeInbound(Unpooled.copiedBuffer(gz)));
            assertArrayEquals(PAYLOAD, drain(ch));
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

    private static byte[] gzipWithExtraField(byte[] data, byte[] extra) throws IOException {
        byte[] standard = gzip(data);
        ByteArrayOutputStream withExtra = new ByteArrayOutputStream();
        byte[] header = java.util.Arrays.copyOfRange(standard, 0, 10);
        header[3] |= 0x04; // FLG.FEXTRA
        withExtra.write(header);
        withExtra.write(extra.length & 0xff);
        withExtra.write((extra.length >>> 8) & 0xff);
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