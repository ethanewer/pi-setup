package org.mds;

import java.io.File;
import java.io.PrintWriter;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.util.HashMap;
import java.util.Map;

import javax.xml.parsers.DocumentBuilderFactory;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;

/**
 * Lightweight MDS cluster daemon role.
 *
 * A single-node MDS store emulator. Each daemon role reads the site
 * configuration file (/app/config/core.xml) at startup, validates the
 * complementary role binding declared for its role, binds a socket on the
 * configured node address at a role-derived port, writes its pid + ready
 * markers under /app/run, and then idles forever so the supervising process
 * (start.sh) can observe that all roles are alive.
 *
 * Role ports are derived from the configured RPC port:
 *   primary   -> rpc.port
 *   data      -> rpc.port + 1
 *   secondary -> rpc.port + 2
 *
 * The gateway service (a long-lived dependent server) is started separately
 * and listens on rpc.port + 10.
 */
public class Daemon {

    private static Map<String, String> readProps(File config) throws Exception {
        Map<String, String> out = new HashMap<String, String>();
        DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
        dbf.setNamespaceAware(false);
        dbf.setExpandEntityReferences(false);
        dbf.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false);
        Document doc = dbf.newDocumentBuilder().parse(config);
        NodeList props = doc.getElementsByTagName("property");
        for (int i = 0; i < props.getLength(); i++) {
            Element p = (Element) props.item(i);
            NodeList names = p.getElementsByTagName("name");
            NodeList values = p.getElementsByTagName("value");
            if (names.getLength() == 0 || values.getLength() == 0) {
                continue;
            }
            String name = names.item(0).getTextContent().trim();
            String val = values.item(0).getTextContent().trim();
            out.put(name, val);
        }
        return out;
    }

    public static void main(String[] argv) throws Exception {
        if (argv.length != 1) {
            System.err.println("usage: Daemon <primary|data|secondary>");
            System.exit(2);
        }
        String role = argv[0].toLowerCase();

        File config = new File("/app/config/core.xml");
        if (!config.isFile()) {
            System.err.println("missing /app/config/core.xml");
            System.exit(2);
        }
        Map<String, String> props = readProps(config);
        String address = props.get("mds.address");
        String rpcPortStr = props.get("mds.rpc.port");
        String binding = props.get("mds.binding." + role);

        if (address == null || address.isEmpty()) {
            System.err.println("role=" + role + " bad/empty mds.address");
            System.exit(2);
        }
        if (rpcPortStr == null) {
            System.err.println("role=" + role + ": bad/empty mds.rpc.port");
            System.exit(2);
        }
        if (binding == null || binding.isEmpty()) {
            System.err.println("role=" + role + ": missing role binding property mds.binding." + role);
            System.exit(2);
        }

        // Validate the address early.
        InetAddress.getByName(address);

        final int basePort;
        basePort = Integer.parseInt(rpcPortStr.trim());
        int offset;
        switch (role) {
            case "primary":   offset = 0; break;
            case "data":      offset = 1; break;
            case "secondary": offset = 2; break;
            default:
                System.err.println("unknown role " + role);
                System.exit(2);
                return;
        }
        int port = basePort + offset;

        InetAddress bindAddr = InetAddress.getByName(address);
        ServerSocket ss;
        try {
            ss = new ServerSocket(port, 16, bindAddr);
        } catch (java.net.BindException ex) {
            System.err.println("role=" + role + " BIND FAILED on " + address + ":" + port);
            throw ex;
        }

        new File("/app/run").mkdirs();
        try (PrintWriter w = new PrintWriter(new File("/app/run/" + role + ".pid"))) {
            w.println(ProcessHandle.current().pid());
        }
        try (PrintWriter w = new PrintWriter(new File("/app/run/" + role + ".ready"))) {
            w.println("ready role=" + role + " binding=" + binding);
        }
        System.out.println(role + " READY addr=" + address + " port=" + port + " binding=" + binding);

        // Keep the JVM alive and the socket bound.
        for (;;) {
            Thread.sleep(60000L);
        }
    }
}