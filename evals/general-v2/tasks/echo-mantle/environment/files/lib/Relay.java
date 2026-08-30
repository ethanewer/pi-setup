import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Relay - a tiny JVM daemon for the Mantle bench.
 *   Relay peer      <role>      <port>          cluster node
 *   Relay reporter  <httpPort>  <r1:p1> <r2:p2> <r3:p3>   status publisher
 */
public class Relay {
    static final Path RUN = Paths.get("/app/run");
    static final int TIMEOUT_MS = 900;

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("usage: Relay peer <role> <port> | Relay reporter <port> <c1:p1> <c2:p2> <c3:p3>");
            System.exit(2);
        }
        switch (args[0]) {
            case "peer":
                runPeer(args[1], Integer.parseInt(args[2]));
                break;
            case "reporter": {
                String[][] nodes = new String[args.length - 2][];
                for (int i = 2; i < args.length; i++) {
                    int c = args[i].lastIndexOf(':');
                    nodes[i - 2] = new String[]{args[i].substring(0, c), args[i].substring(c + 1)};
                }
                runReporter(Integer.parseInt(args[1]), nodes);
                break;
            }
            default:
                System.err.println("unknown mode " + args[0]);
                System.exit(2);
        }
    }

    static void heartbeat(final String role) {
        Thread t = new Thread(() -> {
            try {
                Files.createDirectories(RUN);
                while (true) {
                    Files.write(RUN.resolve(role + ".heartbeat"),
                                (System.currentTimeMillis() + "\n").getBytes());
                    Thread.sleep(4000);
                }
            } catch (Exception ignored) { }
        });
        t.setDaemon(true);
        t.start();
    }

    static void runPeer(String role, int port) throws Exception {
        Files.createDirectories(RUN);
        Files.write(RUN.resolve(role + ".pid"),
                (ProcessHandle.current().pid() + "\n").getBytes());
        heartbeat(role);
        ServerSocket server = new ServerSocket(port, 64, InetAddress.getByName("127.0.0.1"));
        while (true) {
            Socket s = server.accept();
            try {
                s.setSoTimeout(TIMEOUT_MS);
                InputStream in = s.getInputStream();
                byte[] buf = new byte[64];
                int n = in.read(buf);
                String line = new String(buf, 0, Math.max(0, n)).trim();
                if (line.startsWith("PING")) {
                    OutputStream out = s.getOutputStream();
                    out.write(("PONG ok " + role + "\n").getBytes());
                    out.flush();
                }
            } catch (Exception ignored) { } finally {
                try { s.close(); } catch (Exception ignored) { }
            }
        }
    }

    static boolean probePort(int port) {
        try (Socket s = new Socket()) {
            s.connect(new InetSocketAddress("127.0.0.1", port), TIMEOUT_MS);
            s.setSoTimeout(TIMEOUT_MS);
            s.getOutputStream().write("PING relay\n".getBytes());
            s.getOutputStream().flush();
            InputStream in = s.getInputStream();
            byte[] buf = new byte[64];
            int n = in.read(buf);
            return n > 0 && new String(buf, 0, n).contains("PONG");
        } catch (Exception e) {
            return false;
        }
    }

    static String buildStatus(String[][] nodes) {
        StringBuilder sb = new StringBuilder();
        sb.append("{\"cluster\":\"relay-bank\",\"healthy\":");
        boolean all = true;
        for (String[] n2 : nodes) {
            int p = Integer.parseInt(n2[1]);
            all = all && probePort(p);
        }
        sb.append(all);
        sb.append(",\"members\":[");
        for (int i = 0; i < nodes.length; i++) {
            if (i > 0) sb.append(",");
            int p = Integer.parseInt(nodes[i][1]);
            boolean up = probePort(p);
            sb.append("{\"role\":\"").append(nodes[i][0])
              .append("\",\"port\":").append(p)
              .append(",\"up\":").append(up).append("}");
        }
        sb.append("],\"expected\":").append(nodes.length)
          .append(",\"timestamp_ms\":").append(System.currentTimeMillis())
          .append("}");
        return sb.toString();
    }

    static void runReporter(int httpPort, String[][] nodes) throws Exception {
        Files.createDirectories(RUN);
        // background thread keeps /app/status.json fresh even with no web hits
        Thread refresher = new Thread(() -> {
            try {
                while (true) {
                    Files.write(Paths.get("/app/status.json"),
                            buildStatus(nodes).getBytes());
                    Thread.sleep(2000);
                }
            } catch (Exception ignored) { }
        });
        refresher.setDaemon(true);
        refresher.start();
        final ServerSocket server = new ServerSocket(httpPort, 64, InetAddress.getByName("127.0.0.1"));
        while (true) {
            Socket s = server.accept();
            try {
                String body = buildStatus(nodes);   // fresh on every request
                Files.write(Paths.get("/app/status.json"), body.getBytes());
                byte[] b = body.getBytes();
                OutputStream out = s.getOutputStream();
                out.write(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                        + "Content-Length: " + b.length
                        + "\r\nConnection: close\r\n\r\n").getBytes());
                out.write(b);
                out.flush();
            } catch (Exception ignored) { } finally {
                try { s.close(); } catch (Exception ignored) { }
            }
        }
    }
}