package catalog.service;

import catalog.model.Item;
import catalog.json.JsonCodec;
import catalog.db.ItemRepository;

import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * The application logic of the catalogue service.
 *
 * All dependencies are injected through the constructor: the repository
 * (which the tests replace with a fake), and the JSON codec.  The class has
 * no idea where the items live or how HTTP works; it only validates input,
 * applies the business rules, and returns the outcomes.
 */
public final class CatalogService {

    /** Raised when a request body is not well-formed JSON at all. */
    public static final class InvalidJsonException extends Exception {
        public InvalidJsonException(String message) {
            super(message);
        }
    }

    /** Raised when a request body is JSON but does not describe a valid item. */
    public static final class InvalidItemException extends Exception {
        public InvalidItemException(String message) {
            super(message);
        }
    }

    /** Raised when an item with the requested sku already exists. */
    public static final class DuplicateSkuException extends Exception {
        public DuplicateSkuException(String sku) {
            super("duplicate sku " + sku);
        }
    }

    private static final int MAX_SKU_LEN = 128;
    private static final int MAX_TITLE_LEN = 256;
    private static final int MAX_CATEGORY_LEN = 64;

    private final ItemRepository repository;
    private final JsonCodec json;

    public CatalogService(ItemRepository repository, JsonCodec json) {
        this.repository = repository;
        this.json = json;
    }

    /** All items, or all items in one category when {@code category} != null. */
    public List<Item> list(String category) {
        return category == null
                ? List.copyOf(repository.findAll())
                : List.copyOf(repository.findByCategory(category));
    }

    public Optional<Item> find(String sku) {
        return repository.findBySku(sku);
    }

    /**
     * Parses and validates a JSON request body, stores the item, and returns
     * it.  Throws {@link InvalidJsonException} for malformed JSON,
     * {@link InvalidItemException} for a well-formed-but-invalid item, and
     * {@link DuplicateSkuException} when the sku is already taken.
     */
    public Item add(String body)
            throws InvalidJsonException, InvalidItemException, DuplicateSkuException {
        Object parsed;
        try {
            parsed = json.parse(body);
        } catch (JsonCodec.JsonException e) {
            throw new InvalidJsonException(e.getMessage());
        }
        if (!(parsed instanceof Map<?, ?> map)) {
            throw new InvalidItemException("request body must be a JSON object");
        }
        String sku = stringField(map, "sku", MAX_SKU_LEN);
        String title = stringField(map, "title", MAX_TITLE_LEN);
        String category = stringField(map, "category", MAX_CATEGORY_LEN);
        double price = numberField(map, "price", 0);
        int quantity = integerField(map, "quantity", 0);

        Item item = new Item(sku, title, price, quantity, category);
        if (!repository.insert(item)) {
            throw new DuplicateSkuException(sku);
        }
        return item;
    }

    /** Removes the item with the given sku; returns whether one existed. */
    public boolean delete(String sku) {
        return repository.delete(sku);
    }

    // ------------------------------------------------------------------
    // field extraction and validation
    // ------------------------------------------------------------------

    private static String stringField(Map<?, ?> map, String key, int maxLen)
            throws InvalidItemException {
        Object value = map.get(key);
        if (!(value instanceof String s)) {
            throw new InvalidItemException(key + " must be a string");
        }
        if (s.isEmpty()) {
            throw new InvalidItemException(key + " must not be empty");
        }
        if (s.length() > maxLen) {
            throw new InvalidItemException(key + " is too long (max " + maxLen + ")");
        }
        return s;
    }

    private static double numberField(Map<?, ?> map, String key, double min)
            throws InvalidItemException {
        Object value = map.get(key);
        double d;
        if (value instanceof Long l) {
            d = l.doubleValue();
        } else if (value instanceof Double dd) {
            d = dd;
        } else {
            throw new InvalidItemException(key + " must be a number");
        }
        if (Double.isNaN(d) || Double.isInfinite(d) || d < min) {
            throw new InvalidItemException(key + " is out of range");
        }
        return d;
    }

    private static int integerField(Map<?, ?> map, String key, long min)
            throws InvalidItemException {
        Object value = map.get(key);
        if (!(value instanceof Long l)) {
            throw new InvalidItemException(key + " must be an integer");
        }
        if (l < min || l > Integer.MAX_VALUE) {
            throw new InvalidItemException(key + " is out of range");
        }
        return l.intValue();
    }
}