/*
 * Authored hidden case for chainplate-berm (not upstream code).
 * The upstream regression test parameterizes over the ZLIB, GZIP and NONE
 * wrappers but never over ZLIB_OR_NONE (the wrapper that sniffs the first two
 * bytes and resolves to raw deflate for non-zlib streams). These cases drive
 * the same tail-loss code path through that wrapper value, with payloads the
 * upstream test does not use.
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

public class JdkZlibZlibOrNoneRawTailTest {

    @Test
    public void testZlibOrNoneResolvesToRawAndFullyDecompresses() throws Exception {
        byte[] expected = new byte[100000];
        Arrays.fill(expected, (byte) 'a');
        byte[] compressed = rawDeflate(expected);
        assertArrayEquals(expected, decompress(
                JdkZlibDecompressor.builder().wrapper(ZlibWrapper.ZLIB_OR_NONE)
                        .build(ByteBufAllocator.DEFAULT), compressed));
    }

    @Test
    public void testZlibOrNoneResolvesToRawHalfMeg() throws Exception {
        byte[] expected = new byte[500000];
        Arrays.fill(expected, (byte) 'n');
        byte[] compressed = rawDeflate(expected);
        assertArrayEquals(expected, decompress(
                JdkZlibDecompressor.builder().wrapper(ZlibWrapper.ZLIB_OR_NONE)
                        .build(ByteBufAllocator.DEFAULT), compressed));
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