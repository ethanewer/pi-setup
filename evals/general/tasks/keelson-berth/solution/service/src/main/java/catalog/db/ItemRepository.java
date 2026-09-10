package catalog.db;

import catalog.model.Item;

import java.util.List;
import java.util.Optional;

/**
 * Storage boundary of the catalogue service.
 *
 * The HTTP layer never touches SQL; it talks to this interface.  Production
 * uses {@link SqliteItemRepository}; tests inject fakes, which is exactly
 * why the repository is an injected constructor dependency rather than a
 * global.
 */
public interface ItemRepository {

    /** All items, ordered by sku (ascending, byte order). */
    List<Item> findAll();

    /** All items with exactly the given category, ordered by sku. */
    List<Item> findByCategory(String category);

    /** The item with the given sku, if present. */
    Optional<Item> findBySku(String sku);

    /**
     * Adds an item.  Returns {@code false} (and stores nothing) when an item
     * with the same sku already exists.
     */
    boolean insert(Item item);

    /** Removes the item with the given sku; returns whether one was removed. */
    boolean delete(String sku);
}