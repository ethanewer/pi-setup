package catalog.model;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * A single catalogue stock item, as stored in the SQLite {@code items}
 * table and served by the HTTP API.
 */
public record Item(String sku, String title, double price, int quantity, String category) {

    /** Converts this item to the plain-Java shape used by the JSON codec. */
    public Map<String, Object> toJson() {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("sku", sku);
        map.put("title", title);
        map.put("price", price);
        map.put("quantity", (long) quantity);
        map.put("category", category);
        return map;
    }
}