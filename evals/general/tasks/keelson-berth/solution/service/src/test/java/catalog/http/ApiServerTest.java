package catalog.http;

import catalog.db.SqliteItemRepository;
import catalog.json.JsonCodec;
import catalog.service.CatalogService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;
import java.time.Duration;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * End-to-end test: real SQLite file, real JDBC repository, real HTTP server
 * on an ephemeral port, real HTTP calls through java.net.http.  This is the
 * test that proves the whole stack actually works together.
 */
class ApiServerTest {

    private Path dbFile;
    private Connection seedConnection;
    private ApiServer server;
    private int port;
    private final HttpClient client = HttpClient.newBuilder()
            .version(HttpClient.Version.HTTP_1_1)
            .connectTimeout(Duration.ofSeconds(5))
            .build();

    @BeforeEach
    void setUp() throws Exception {
        dbFile = Files.createTempFile("catalog-test", ".sqlite");
        seedConnection = DriverManager.getConnection("jdbc:sqlite:" + dbFile);
        // seed two rows directly through JDBC, exactly as a fixture would
        try (Statement st = seedConnection.createStatement()) {
            st.execute("CREATE TABLE items ("
                    + " sku TEXT PRIMARY KEY, title TEXT NOT NULL,"
                    + " price REAL NOT NULL, quantity INTEGER NOT NULL,"
                    + " category TEXT NOT NULL)");
            st.execute("INSERT INTO items VALUES ('b','Bee wax',3.5,8,'craft')");
            st.execute("INSERT INTO items VALUES ('a','Ant funnel',12,2,'craft')");
            st.execute("INSERT INTO items VALUES ('c','Cone loom',99.9,0,'textile')");
        }

        SqliteItemRepository repository = new SqliteItemRepository(seedConnection);
        JsonCodec json = new JsonCodec();
        CatalogService service = new CatalogService(repository, json);
        server = new ApiServer(service, json, 0); // ephemeral port
        server.start();
        port = server.boundPort();
    }

    @AfterEach
    void tearDown() throws Exception {
        server.stop();
        seedConnection.close();
        Files.deleteIfExists(dbFile);
    }

    // ------------------------------------------------------------------
    // helpers
    // ------------------------------------------------------------------

    private HttpResponse<byte[]> get(String path) throws Exception {
        return client.send(
                HttpRequest.newBuilder(uri(path)).GET().build(),
                HttpResponse.BodyHandlers.ofByteArray());
    }

    private HttpResponse<byte[]> delete(String path) throws Exception {
        return client.send(
                HttpRequest.newBuilder(uri(path)).DELETE().build(),
                HttpResponse.BodyHandlers.ofByteArray());
    }

    private HttpResponse<byte[]> post(String path, String body) throws Exception {
        return client.send(
                HttpRequest.newBuilder(uri(path))
                        .header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString(body))
                        .build(),
                HttpResponse.BodyHandlers.ofByteArray());
    }

    private URI uri(String path) {
        return URI.create("http://127.0.0.1:" + port + path);
    }

    private Object parse(HttpResponse<byte[]> response) throws Exception {
        return new JsonCodec().parse(
                new String(response.body(), StandardCharsets.UTF_8));
    }

    private static Map<?, ?> obj(Object value) {
        return (Map<?, ?>) value;
    }

    /** Prices may arrive as Long or Double depending on how they serialised. */
    private static double asDouble(Object value) {
        return ((Number) value).doubleValue();
    }

    // ------------------------------------------------------------------
    // tests
    // ------------------------------------------------------------------

    @Test
    void healthz() throws Exception {
        HttpResponse<byte[]> response = get("/healthz");
        assertEquals(200, response.statusCode());
        assertEquals(Map.of("ok", true), parse(response));
    }

    @Test
    void listsSeedRowsInSkuOrder() throws Exception {
        HttpResponse<byte[]> response = get("/api/v1/items");
        assertEquals(200, response.statusCode());
        Map<?, ?> root = obj(parse(response));
        assertEquals(3L, root.get("count"));
        List<?> items = (List<?>) root.get("items");
        assertEquals(3, items.size());
        Map<?, ?> first = obj(items.get(0));
        assertEquals("a", first.get("sku"));
        assertEquals("Ant funnel", first.get("title"));
        assertEquals(12.0, asDouble(first.get("price")), 1e-9);
        assertEquals(2L, first.get("quantity"));
        assertEquals("craft", first.get("category"));
        Map<?, ?> last = obj(items.get(2));
        assertEquals("c", last.get("sku"));
        assertEquals(99.9, asDouble(last.get("price")), 1e-9);
    }

    @Test
    void filtersByCategoryAndIgnoresUnknownQueryParams() throws Exception {
        Map<?, ?> craft = obj(parse(get("/api/v1/items?category=craft")));
        assertEquals(2L, craft.get("count"));
        Map<?, ?> textile = obj(parse(get("/api/v1/items?category=textile")));
        assertEquals(1L, textile.get("count"));
        Map<?, ?> none = obj(parse(get("/api/v1/items?category=zzz")));
        assertEquals(0L, none.get("count"));
        // unknown query parameters must be ignored, not treated as filters
        Map<?, ?> all = obj(parse(get("/api/v1/items?sort=desc&category=craft")));
        assertEquals(2L, all.get("count"));
    }

    @Test
    void getsAndDeletesSingleItems() throws Exception {
        HttpResponse<byte[]> ok = get("/api/v1/items/b");
        assertEquals(200, ok.statusCode());
        Map<?, ?> item = obj(obj(parse(ok)).get("item"));
        assertEquals("b", item.get("sku"));
        assertEquals(3.5, asDouble(item.get("price")), 1e-9);

        HttpResponse<byte[]> missing = get("/api/v1/items/no-such-sku");
        assertEquals(404, missing.statusCode());
        assertEquals(Map.of("error", "not_found"), parse(missing));

        HttpResponse<byte[]> gone = delete("/api/v1/items/b");
        assertEquals(200, gone.statusCode());
        assertEquals(Map.of("deleted", true), parse(gone));

        HttpResponse<byte[]> goneAgain = delete("/api/v1/items/b");
        assertEquals(404, goneAgain.statusCode());
        assertEquals(Map.of("error", "not_found"), parse(goneAgain));
    }

    @Test
    void postsItemsAndRejectsBadOnes() throws Exception {
        String valid = "{\"sku\":\"d\",\"title\":\"Drum mat\",\"price\":21.5,"
                + "\"quantity\":4,\"category\":\"craft\"}";
        HttpResponse<byte[]> created = post("/api/v1/items", valid);
        assertEquals(201, created.statusCode());
        Map<?, ?> createdItem = obj(obj(parse(created)).get("item"));
        assertEquals("d", createdItem.get("sku"));
        assertEquals(21.5, asDouble(createdItem.get("price")), 1e-9);

        // the new row must be visible through a subsequent listing
        Map<?, ?> craft = obj(parse(get("/api/v1/items?category=craft")));
        assertEquals(3L, craft.get("count"));

        // duplicate sku
        HttpResponse<byte[]> dup = post("/api/v1/items", valid);
        assertEquals(409, dup.statusCode());
        assertEquals(Map.of("error", "duplicate_sku"), parse(dup));

        // unparseable body
        HttpResponse<byte[]> badJson = post("/api/v1/items", "not json {");
        assertEquals(400, badJson.statusCode());
        assertEquals(Map.of("error", "bad_json"), parse(badJson));

        // well-formed but invalid item
        HttpResponse<byte[]> invalid = post("/api/v1/items",
                "{\"sku\":\"e\",\"title\":\"\",\"price\":1,\"quantity\":1,"
                        + "\"category\":\"craft\"}");
        assertEquals(400, invalid.statusCode());
        assertEquals(Map.of("error", "invalid_item"), parse(invalid));

        // object with a non-integer quantity
        HttpResponse<byte[]> floatQty = post("/api/v1/items",
                "{\"sku\":\"e\",\"title\":\"T\",\"price\":1,\"quantity\":2.5,"
                        + "\"category\":\"craft\"}");
        assertEquals(400, floatQty.statusCode());

        // the failed posts must not have persisted anything
        HttpResponse<byte[]> after = get("/api/v1/items/no-such-sku-x");
        assertEquals(404, after.statusCode());
    }

    @Test
    void rejectsWrongMethodAndUnknownPaths() throws Exception {
        HttpResponse<byte[]> put = client.send(
                HttpRequest.newBuilder(uri("/api/v1/items"))
                        .PUT(HttpRequest.BodyPublishers.noBody()).build(),
                HttpResponse.BodyHandlers.ofByteArray());
        assertEquals(405, put.statusCode());
        assertEquals(Map.of("error", "method_not_allowed"), parse(put));

        HttpResponse<byte[]> unknown = get("/api/v1/what");
        assertEquals(404, unknown.statusCode());
        assertEquals(Map.of("error", "not_found"), parse(unknown));

        HttpResponse<byte[]> root = get("/");
        assertEquals(404, root.statusCode());
        assertEquals(Map.of("error", "not_found"), parse(root));

        // every response is JSON
        assertTrue(put.headers().firstValue("content-type").orElse("")
                .startsWith("application/json"));
        HttpResponse<byte[]> list = get("/api/v1/items");
        assertTrue(list.headers().firstValue("content-type").orElse("")
                .startsWith("application/json"));
    }

    @Test
    void survivesAcrossManySequentialRequests() throws Exception {
        for (int i = 0; i < 20; i++) {
            HttpResponse<byte[]> response = get("/healthz");
            assertEquals(200, response.statusCode());
        }
        for (int i = 0; i < 5; i++) {
            HttpResponse<byte[]> response =
                    get("/api/v1/items?category=craft");
            assertEquals(200, response.statusCode());
        }
    }
}