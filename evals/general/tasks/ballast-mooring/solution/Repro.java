import io.netty.handler.codec.DateFormatter;

import java.util.Date;

public class Repro {
    public static void main(String[] args) {
        String header = "Set-Cookie: foo=bar; Expires=Sun 08:49:37 06 Nov 1994; Path=/";
        int start = header.indexOf("Sun 08");
        int end = header.indexOf("; Path=/");
        Date parsed = DateFormatter.parseHttpDate(header, start, end);
        System.out.println("parsed: " + parsed);
        System.exit(parsed == null ? 1 : 0);
    }
}