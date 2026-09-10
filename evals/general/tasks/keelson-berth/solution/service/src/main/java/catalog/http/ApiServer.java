package catalog.http;

import catalog.json.JsonCodec;
import catalog.model.Item;
import catalog.service.CatalogService;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.Executors;

/**
 * The HTTP surface of the catalogue service, built on the JDK's built-in
 * {@code com.sun.net.httpserver} module: no web framework, no servlets.
 *
 * Request handling is deliberately simple and deterministic.  Connections
 * are closed after every response so a serialised request stream never has
 * to wait on idle keep-alive sockets.
 */
public final class ApiServer {

    private static final int MAX_BODY_BYTES = 1 << 20;       // 1 MiB
    private static final String API_PREFIX = "/api/v1/";

    private final CatalogService service;
    private final JsonCodec json;
    private final int requestedPort;
    private HttpServer server;

    public ApiServer(CatalogService service, JsonCodec json, int requestedPort) {
        this.service = service;
        this.json = json;
        this.requestedPort = requestedPort;
    }

    /** Binds (always to 127.0.0.1) and starts serving in the background. */
    public void start() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", requestedPort), 0);
        server.setExecutor(Executors.newSingleThreadExecutor());
        server.createContext("/", this::handle);
        server.start();
    }

    /** The actually-bound port (useful when the requested port was 0). */
    public int boundPort() {
        return server == null ? requestedPort : server.getAddress().getPort();
    }

    public void stop() {
        if (server != null) {
            server.stop(0);
        }
    }

    // ------------------------------------------------------------------
    // request dispatch
    // ------------------------------------------------------------------

    private void handle(HttpExchange exchange) {
        int status;
        Object body;
        try {
            status = Integer.MIN_VALUE;
            body = null;
            String method = exchange.getRequestMethod();
            String path = exchange.getRequestURI().getPath();
            String query = exchange.getRequestURI().getRawQuery();

            if (method.equals("GET") && path.equals("/healthz")) {
                status = 200;
                body = Map.of("ok", true);
            } else if (path.startsWith(API_PREFIX)) {
                Response out = route(method, path.substring(API_PREFIX.length()),
                        query, exchange);
                status = out.status();
                body = out.body();
            } else {
                status = 404;
                body = Map.of("error", "not_found");
            }
        } catch (Exception e) {
            // A failing handler must never take the whole server down with an
            // uncaught exception; turn it into a plain 500 JSON reply.
            status = 500;
            body = Map.of("error", "internal_error");
        }
        respond(exchange, status, body);
    }

    private record Response(int status, Object body) {
    }

    private Response route(String method, String rest, String query,
                           HttpExchange exchange) throws IOException {
        if (rest.equals("items")) {
            if (method.equals("GET")) {
                String category = queryParam(query, "category");
                List<Item> rows = service.list(category);
                return new Response(200, Map.of(
                        "items", rows.stream().map(Item::toJson).toList(),
                        "count", (long) rows.size()));
            }
            if (method.equals("POST")) {
                try {
                    String raw = readBody(exchange);
                    Item item = service.add(raw);
                    return new Response(201, Map.of("item", item.toJson()));
                } catch (CatalogService.InvalidJsonException e) {
                    return new Response(400, Map.of("error", "bad_json"));
                } catch (CatalogService.InvalidItemException e) {
                    return new Response(400, Map.of("error", "invalid_item"));
                } catch (CatalogService.DuplicateSkuException e) {
                    return new Response(409, Map.of("error", "duplicate_sku"));
                }
            }
            return new Response(405, Map.of("error", "method_not_allowed"));
        }

        if (rest.startsWith("items/")) {
            String sku = rest.substring("items/".length());
            if (sku.isEmpty()) {
                return new Response(404, Map.of("error", "not_found"));
            }
            if (method.equals("GET")) {
                Optional<Item> item = service.find(sku);
                return item.map(i -> new Response(200, Map.of("item", i.toJson())))
                        .orElse(new Response(404, Map.of("error", "not_found")));
            }
            if (method.equals("DELETE")) {
                if (!service.delete(sku)) {
                    return new Response(404, Map.of("error", "not_found"));
                }
                return new Response(200, Map.of("deleted", true));
            }
            return new Response(405, Map.of("error", "method_not_allowed"));
        }

        return new Response(404, Map.of("error", "not_found"));
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    private String readBody(HttpExchange exchange)
            throws IOException, CatalogService.InvalidJsonException {
        byte[] data = exchange.getRequestBody().readNBytes(MAX_BODY_BYTES + 1);
        if (data.length > MAX_BODY_BYTES) {
            throw new CatalogService.InvalidJsonException("request body too large");
        }
        return new String(data, StandardCharsets.UTF_8);
    }

    private static String queryParam(String rawQuery, String name) {
        if (rawQuery == null || rawQuery.isEmpty()) {
            return null;
        }
        for (String pair : rawQuery.split("&")) {
            int eq = pair.indexOf('=');
            String key = eq < 0 ? pair : pair.substring(0, eq);
            String value = eq < 0 ? null : pair.substring(eq + 1);
            if (key.equals(name)) {
                return value == null ? "" : percentDecode(value);
            }
        }
        return null;
    }

    private static String percentDecode(String s) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '+') {
                sb.append(' ');
            } else if (c == '%' && i + 2 < s.length()) {
                try {
                    sb.append((char) Integer.parseInt(s.substring(i + 1, i + 3), 16));
                    i += 2;
                } catch (NumberFormatException e) {
                    sb.append(c);
                }
            } else {
                sb.append(c);
            }
        }
        return sb.toString();
    }

    private void respond(HttpExchange exchange, int status, Object body) {
        byte[] bytes = json.stringify(body).getBytes(StandardCharsets.UTF_8);
        try {
            exchange.getResponseHeaders().set("Content-Type", "application/json");
            exchange.getResponseHeaders().set("Connection", "close");
            exchange.sendResponseHeaders(status, bytes.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(bytes);
            }
        } catch (IOException e) {
            // The client went away; nothing more can be written.
        } finally {
            exchange.close();
        }
    }
}