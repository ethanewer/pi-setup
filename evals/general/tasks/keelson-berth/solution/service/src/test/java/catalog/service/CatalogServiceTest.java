package catalog.service;

import catalog.db.ItemRepository;
import catalog.json.JsonCodec;
import catalog.model.Item;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.TreeMap;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Unit tests for the application logic with a fake repository, proving that
 * the service depends only on the ItemRepository contract and not on SQLite.
 */
class CatalogServiceTest {

    private static final Item ALPHA =
            new Item("alpha", "Alpha pad", 9.99, 12, "paper");
    private static final Item BETA =
            new Item("beta", "Beta pen", 2.5, 0, "paper");
    private static final Item GAMMA =
            new Item("gamma", "Gamma light", 59.0, 3, "lighting");

    private FakeRepository repository;
    private CatalogService service;

    @BeforeEach
    void setUp() {
        repository = new FakeRepository();
        repository.all.put(ALPHA.sku(), ALPHA);
        repository.all.put(BETA.sku(), BETA);
        repository.all.put(GAMMA.sku(), GAMMA);
        service = new CatalogService(repository, new JsonCodec());
    }

    @Test
    void listsAllItemsInSkuOrder() {
        assertEquals(List.of(ALPHA, BETA, GAMMA), service.list(null));
    }

    @Test
    void filtersExactlyByCategory() {
        assertEquals(List.of(ALPHA, BETA), service.list("paper"));
        assertEquals(List.of(GAMMA), service.list("lighting"));
        assertEquals(List.of(), service.list("no-such-category"));
    }

    @Test
    void findsBySku() {
        assertEquals(Optional.of(BETA), service.find("beta"));
        assertTrue(service.find("missing").isEmpty());
    }

    @Test
    void addsValidItem() throws Exception {
        String body = "{\"sku\":\"delta\",\"title\":\"Delta reel\","
                + "\"price\":12.0,\"quantity\":5,\"category\":\"lighting\"}";
        Item created = service.add(body);

        assertEquals(new Item("delta", "Delta reel", 12.0, 5, "lighting"), created);
        assertTrue(repository.all.containsKey("delta"));
        // and the stored item is exactly what came back
        assertEquals(created, repository.all.get("delta"));
    }

    @Test
    void rejectsBadJson() {
        assertThrows(CatalogService.InvalidJsonException.class,
                () -> service.add("not json {"));
        // A JSON array is well-formed JSON but not a valid item payload;
        // that is an InvalidItem, not a parse failure.
        assertThrows(CatalogService.InvalidItemException.class,
                () -> service.add("[1, 2, 3]"));
    }

    @Test
    void rejectsMalformedItems() {
        assertThrows(CatalogService.InvalidItemException.class,
                () -> service.add("{\"sku\":\"d\",\"title\":\"t\",\"price\":1,"
                        + "\"quantity\":1}"), // missing category
                "missing category");
        assertThrows(CatalogService.InvalidItemException.class,
                () -> service.add("{\"sku\":\"\",\"title\":\"t\",\"price\":1,"
                        + "\"quantity\":1,\"category\":\"c\"}"),
                "empty sku");
        assertThrows(CatalogService.InvalidItemException.class,
                () -> service.add("{\"sku\":\"d\",\"title\":\"t\",\"price\":-1,"
                        + "\"quantity\":1,\"category\":\"c\"}"),
                "negative price");
        assertThrows(CatalogService.InvalidItemException.class,
                () -> service.add("{\"sku\":\"d\",\"title\":\"t\",\"price\":1,"
                        + "\"quantity\":-3,\"category\":\"c\"}"),
                "negative quantity");
        assertThrows(CatalogService.InvalidItemException.class,
                () -> service.add("{\"sku\":\"d\",\"title\":\"t\",\"price\":1,"
                        + "\"quantity\":2.5,\"category\":\"c\"}"),
                "fractional quantity");
        assertThrows(CatalogService.InvalidItemException.class,
                () -> service.add("{\"sku\":\"d\",\"title\":\"t\",\"price\":\"1\","
                        + "\"quantity\":1,\"category\":\"c\"}"),
                "string price");
        assertThrows(CatalogService.InvalidItemException.class,
                () -> service.add("{\"sku\":\"d\",\"title\":\"t\",\"price\":1,"
                        + "\"quantity\":1,\"category\":58}"),
                "numeric category");
        assertTrue(service.find("d").isEmpty(), "failed adds must not persist");
    }

    @Test
    void rejectsDuplicateSku() throws Exception {
        String body = "{\"sku\":\"beta\",\"title\":\"Copy\",\"price\":1.0,"
                + "\"quantity\":1,\"category\":\"paper\"}";
        assertThrows(CatalogService.DuplicateSkuException.class,
                () -> service.add(body));
        // the original row must be untouched
        assertEquals(BETA, repository.all.get("beta"));
    }

    @Test
    void deletesExistingButNotMissing() {
        assertTrue(service.delete("alpha"));
        assertFalse(service.find("alpha").isPresent());
        assertFalse(service.delete("alpha"));
        assertFalse(service.delete("never-here"));
    }

    /** In-memory stand-in for the SQLite repository. */
    static final class FakeRepository implements ItemRepository {
        final TreeMap<String, Item> all = new TreeMap<>();

        @Override
        public List<Item> findAll() {
            return new ArrayList<>(all.values());
        }

        @Override
        public List<Item> findByCategory(String category) {
            List<Item> out = new ArrayList<>();
            for (Item item : all.values()) {
                if (item.category().equals(category)) {
                    out.add(item);
                }
            }
            out.sort(Comparator.comparing(Item::sku));
            return out;
        }

        @Override
        public Optional<Item> findBySku(String sku) {
            return Optional.ofNullable(all.get(sku));
        }

        @Override
        public boolean insert(Item item) {
            return all.putIfAbsent(item.sku(), item) == null;
        }

        @Override
        public boolean delete(String sku) {
            return all.remove(sku) != null;
        }
    }
}