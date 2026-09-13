/*
 * Authored hidden case for chainplate-berm (not upstream code).
 * The upstream regression test feeds the ENTIRE compressed buffer with a
 * single addInput call; these cases feed it in small chunks (128-byte and
 * 7-byte pieces), interleaving output draining with input feeding. Exercising
 * the same sizing/pending-output code path from a different feeding shape.
 */
package io.netty.handler.codec.compression;

import io.netty.buffer.ByteBufAllocator;
import io.netty.buffer.CompositeByteBuf;
import io.netty.buffer.Unpooled;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.util.Arrays;
import java.util.zip.Deflater;
import java.util.zip.DeflaterOutputStream;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.fail;

public class JdkZlibChunkedInputTest {

    @Test
    public void testChunkedRawDeflateRepeatedLetter() throws Exception {
        byte[] expected = new byte[300000];
        Arrays.fill(expected, (byte) 'm');
        byte[] compressed = rawDeflate(expected);
        assertArrayEquals(expected, decompressChunked(
                JdkZlibDecompressor.builder().wrapper(ZlibWrapper.NONE).build(ByteBufAllocator.DEFAULT),
                compressed, 128));
    }

    @Test
    public void testChunkedRawDeflateTinyChunks() throws Exception {
        byte[] expected = new byte[100000];
        Arrays.fill(expected, (byte) 'a');
        byte[] compressed = rawDeflate(expected);
        assertArrayEquals(expected, decompressChunked(
                JdkZlibDecompressor.builder().wrapper(ZlibWrapper.NONE).build(ByteBufAllocator.DEFAULT),
                compressed, 7));
    }

    private static byte[] decompressChunked(Decompressor decompressor, byte[] compressed,
                                            int chunkSize) throws Exception {
        CompositeByteBuf output = ByteBufAllocator.DEFAULT.compositeBuffer();
        try (Decompressor ignored = decompressor) {
            decompressor.status();
            int off = 0;
            while (off < compressed.length) {
                if (decompressor.status() == Decompressor.Status.NEED_OUTPUT) {
                    drain(output, decompressor);
                }
                int n = Math.min(chunkSize, compressed.length - off);
                decompressor.addInput(Unpooled.wrappedBuffer(compressed, off, n));
                off += n;
                drain(output, decompressor);
                if (decompressor.status() == Decompressor.Status.COMPLETE) {
                    // The stream ended exactly at a chunk boundary; nothing more to feed.
                    byte[] bytes = new byte[output.readableBytes()];
                    output.readBytes(bytes);
                    return bytes;
                }
            }
            decompressor.endOfInput();
            drain(output, decompressor);
            if (decompressor.status() != Decompressor.Status.COMPLETE) {
                fail("decompressor did not reach COMPLETE after endOfInput: " + decompressor.status());
            }
            byte[] bytes = new byte[output.readableBytes()];
            output.readBytes(bytes);
            return bytes;
        } finally {
            output.release();
        }
    }

    private static void drain(CompositeByteBuf output, Decompressor decompressor) throws Exception {
        while (decompressor.status() == Decompressor.Status.NEED_OUTPUT) {
            output.addComponent(true, decompressor.takeOutput());
        }
    }

    private static byte[] rawDeflate(byte[] data) throws Exception {
        Deflater deflater = new Deflater(Deflater.DEFAULT_COMPRESSION, true);
        try {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            DeflaterOutputStream stream = new DeflaterOutputStream(output, deflater);
            stream.write(data);
            stream.close();
            return output.toByteArray();
        } finally {
            deflater.end();
        }
    }
}