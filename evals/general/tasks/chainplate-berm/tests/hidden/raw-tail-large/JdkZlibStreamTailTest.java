/*
 * Authored hidden case for chainplate-berm (not upstream code).
 * Highly compressible raw-deflate payloads of OTHER repeated byte values and
 * sizes than the upstream regression test uses (which is exactly 100000 'a'
 * bytes, NONE wrapper, single-shot feed). Same code path: output buffers are
 * sized from the remaining input byte count, so the tail of each of these
 * streams is lost unless the mechanism is fixed.
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

public class JdkZlibStreamTailTest {

    @Test
    public void testTwoHundredFiftyThousandRepeatedLetterRawDeflate() throws Exception {
        byte[] expected = new byte[250000];
        Arrays.fill(expected, (byte) 'z');
        byte[] compressed = rawDeflate(expected);
        assertArrayEquals(expected, decompress(
                JdkZlibDecompressor.builder().wrapper(ZlibWrapper.NONE).build(ByteBufAllocator.DEFAULT),
                compressed));
    }

    @Test
    public void testOneHundredEightyThousandRepeatedLetterRawDeflate() throws Exception {
        byte[] expected = new byte[180000];
        Arrays.fill(expected, (byte) 'a');
        byte[] compressed = rawDeflate(expected);
        assertArrayEquals(expected, decompress(
                JdkZlibDecompressor.builder().wrapper(ZlibWrapper.NONE).build(ByteBufAllocator.DEFAULT),
                compressed));
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

    private static byte[] decompress(Decompressor decompressor, byte[] compressed) throws Exception {
        CompositeByteBuf output = ByteBufAllocator.DEFAULT.compositeBuffer();
        try (Decompressor ignored = decompressor) {
            decompressor.status();
            decompressor.addInput(Unpooled.wrappedBuffer(compressed));
            for (;;) {
                switch (decompressor.status()) {
                    case NEED_INPUT:
                        decompressor.endOfInput();
                        break;
                    case NEED_OUTPUT:
                        output.addComponent(true, decompressor.takeOutput());
                        break;
                    case COMPLETE:
                        byte[] bytes = new byte[output.readableBytes()];
                        output.readBytes(bytes);
                        return bytes;
                    default:
                        throw new AssertionError("Unknown decompressor status");
                }
            }
        } finally {
            output.release();
        }
    }
}