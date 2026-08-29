import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/**
 * PalisadeDaemon - clean-room, invented "palisade" distributed store.
 *
 * A single daemon plays one of three roles (primary / data / secondary) of a
 * tiny three-node cluster on one host.
 *
 * Each role instance:
 *   - binds its RPC port on 127.0.0.1,
 *   - keeps a heartbeat file fresh under /var/run/palisade/,
 *   - answers the TCP line "GET /status" with a JSON snapshot of the whole
 *     cluster (derived from the three fresh heartbeat files), then closes.
 */
public class PalisadeDaemon {

    static final String HB = "/var/run/palisade";
    static int primaryPort, dataPort, secondaryPort;

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("usage: PalisadeDaemon <conf> <primary|data|secondary>");
            System.exit(2);
        }
        String conf = args[0];
        String role = args[1];
        Map<String, String> cfg = loadConf(conf);

        String host = cfg.getOrDefault("host", "palisade.local.hollow.farm");
        primaryPort   = parsePort(cfg.get("primary_port"), 26100);
        dataPort      = parsePort(cfg.get("data_port"), 26101);
        secondaryPort = parsePort(cfg.get("secondary_port"), 26102);
        int capMb     = cfg.containsKey("capacity_mb") ? Integer.parseInt(cfg.get("capacity_mb").trim()) : 65536;
        long capBytes = (long) capMb * 3L * 1024L * 1024L;

        new File(HB).mkdirs();
        final String safeHost = host.replaceAll("[^A-Za-z0-9.-]", "_");
        final int port = portFor(role);

        Thread hb = new Thread(() -> {
            while (true) {
                try {
                    Path p = Paths.get(HB, safeHost + "." + role + ".hb");
                    Files.write(p, (role + " " + port + " " + System.currentTimeMillis() + "\n")
                            .getBytes(StandardCharsets.UTF_8));
                    Thread.sleep(1200);
                } catch (Exception e) { /* keep looping */ }
            }
        }, "heartbeat-" + role);
        hb.setDaemon(true);
        hb.start();

        ServerSocket srv = new ServerSocket();
        srv.setReuseAddress(true);
        srv.bind(new InetSocketAddress(InetAddress.getLoopbackAddress(), port));
        System.out.println("PALISADE " + role + " UP port=" + port + " host=" + host);

        while (true) {
            Socket c;
            try { c = srv.accept(); } catch (Exception e) { continue; }
            try (Socket sock = c) {
                sock.setSoTimeout(1500);
                BufferedReader r = new BufferedReader(new InputStreamReader(sock.getInputStream()));
                String line = r.readLine();
                String out = "HOLD\n";
                if (line != null && line.contains("status")) {
                    out = statusJson(host, capBytes) + "\n";
                }
                OutputStream os = sock.getOutputStream();
                os.write(out.getBytes(StandardCharsets.UTF_8));
                os.flush();
            } catch (Exception e) { /* reset connection */ }
        }
    }

    static int portFor(String role) {
        switch (role) {
            case "data":      return dataPort;
            case "secondary": return secondaryPort;
            default:          return primaryPort;
        }
    }

    static int parsePort(String raw, int def) {
        if (raw == null) return def;
        return Integer.parseInt(raw.trim());
    }

    static long heartbeatAge(String role, String host) {
        String safeHost = host.replaceAll("[^A-Za-z0-9.-]", "_");
        File f = new File(HB, safeHost + "." + role + ".hb");
        if (!f.isFile()) return Long.MAX_VALUE;
        return System.currentTimeMillis() - f.lastModified();
    }

    static String statusJson(String host, long capacity) {
        boolean online = true;
        StringBuilder nodes = new StringBuilder();
        for (String role : new String[]{"primary", "data", "secondary"}) {
            if (nodes.length() > 0) nodes.append(",");
            boolean alive = heartbeatAge(role, host) <= 5000;
            if (!alive) online = false;
            nodes.append("{\"role\":\"").append(role)
                 .append("\",\"port\":").append(portFor(role))
                 .append(",\"online\":").append(alive ? "true" : "false")
                 .append("}");
        }
        return "{\"name\":\"palisade\",\"host\":\"" + host + "\",\"health\":\"cluster\",\"online\":"
             + (online ? "true" : "false") + ",\"capacity\":" + capacity + ",\"nodes\":[" + nodes + "]}";
    }

    static Map<String, String> loadConf(String path) throws IOException {
        Map<String, String> m = new HashMap<>();
        for (String raw : Files.readAllLines(Paths.get(path))) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            int eq = line.indexOf('=');
            if (eq <= 0) continue;
            m.put(line.substring(0, eq).trim(), line.substring(eq + 1).trim());
        }
        return m;
    }
}