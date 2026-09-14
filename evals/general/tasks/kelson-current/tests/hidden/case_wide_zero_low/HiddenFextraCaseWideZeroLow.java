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
 * Hidden case B for kelson-current: an FEXTRA extra field whose total length
 * (512 bytes) has a ZERO low byte in the little-endian XLEN (0x0200). A
 * byte-order-confused handling that reads the length big-endian would see
 * xlen = 2, skip only two bytes and hand 510 bytes of extra-field data to
 * the inflater; the correct handling must skip all 512 bytes.
 */
public class HiddenFextraCaseWideZeroLow {

    private static final byte[] PAYLOAD = (
            "hidden case B: 512-byte FEXTRA extra field whose XLEN low byte is zero. "
          + "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
          + "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
          + "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
          + "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
          + "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
          + "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
          + "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
          + "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
          + "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
          + "end of hidden case B payload.").getBytes(java.nio.charset.StandardCharsets.US_ASCII);

    private static byte[] extra() {
        byte[] extra = new byte[512];
        extra[0] = 0x54;  // SI1
        extra[1] = 0x5A;  // SI2
        extra[2] = (byte) 0xFC;  // subfield LEN low byte (508 = 0x01FC, little-endian)
        extra[3] = 0x01;  // subfield LEN high byte
        for (int i = 4; i < extra.length; i++) {
            extra[i] = (byte) (0x2A - (i % 7));
        }
        // mark the start and end of the extra field with recognizable fences
        extra[4] = 0x7E;
        extra[5] = 0x5E;
        extra[extra.length - 2] = (byte) 0x9E;
        extra[extra.length - 1] = (byte) 0x7D;
        return extra;
    }

    @Test
    public void testWideExtraFieldZeroLowXlenByte() throws Exception {
        byte[] extra = extra();
        assertEquals(512, extra.length);
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